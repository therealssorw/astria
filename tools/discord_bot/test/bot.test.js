// What can silently rot here is the counting, not the gateway: an invite diff
// that picks the wrong person, a ranking that reorders under a tie, a page that
// runs off the end. All three are plain functions on purpose, so all three get
// checked without a token or a network.

import { mkdtempSync, rmSync, writeFileSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import assert from "node:assert/strict"

import { BOARDS, board_by_id } from "../src/boards.js"
import { VANITY_CODE, invite_diff } from "../src/invites.js"
import { Store } from "../src/store.js"
import { PAGE_SIZE, clamp_page, page_count, render_board, parse_button_id, button_id } from "../src/render.js"

function scratch() {
	const dir = mkdtempSync(join(tmpdir(), "astria-bot-"))
	test.after(() => rmSync(dir, { recursive: true, force: true }))
	return dir
}

function fresh_store() {
	let clock = 1_700_000_000_000
	return new Store(join(scratch(), "counts.json"), () => clock)
}

test("invite_diff credits the code whose uses went up", () => {
	const before = { abc: { uses: 3, inviter_id: "alice" }, xyz: { uses: 9, inviter_id: "bob" } }
	const after = { abc: { uses: 4, inviter_id: "alice" }, xyz: { uses: 9, inviter_id: "bob" } }
	const got = invite_diff(before, after)
	console.log(`  used code=${got.code} inviter=${got.inviter_id} reason=${got.reason}`)
	assert.equal(got.inviter_id, "alice")
	assert.equal(got.reason, "used")
})

test("invite_diff credits a single-use invite that vanished on use", () => {
	const before = { once: { uses: 0, inviter_id: "carol" }, keep: { uses: 2, inviter_id: "bob" } }
	const after = { keep: { uses: 2, inviter_id: "bob" } }
	const got = invite_diff(before, after)
	console.log(`  vanished code=${got.code} inviter=${got.inviter_id} reason=${got.reason}`)
	assert.equal(got.inviter_id, "carol")
	assert.equal(got.reason, "used-up")
})

test("invite_diff refuses to guess when two codes vanished", () => {
	const before = { a: { uses: 0, inviter_id: "alice" }, b: { uses: 0, inviter_id: "bob" } }
	const got = invite_diff(before, {})
	console.log(`  two gone -> inviter=${got.inviter_id} reason=${got.reason}`)
	assert.equal(got.inviter_id, null)
	assert.equal(got.reason, "ambiguous")
})

test("invite_diff hands a vanity join to the server owner", () => {
	const before = { [VANITY_CODE]: { uses: 40, inviter_id: null } }
	const after = { [VANITY_CODE]: { uses: 41, inviter_id: null } }
	const got = invite_diff(before, after, "owner-id")
	console.log(`  vanity inviter=${got.inviter_id} reason=${got.reason}`)
	assert.equal(got.inviter_id, "owner-id")
	assert.equal(got.reason, "vanity")
})

test("invite_diff says nothing happened when nothing happened", () => {
	const same = { a: { uses: 1, inviter_id: "alice" } }
	const got = invite_diff(same, { ...same })
	console.log(`  unchanged -> reason=${got.reason}`)
	assert.equal(got.inviter_id, null)
	assert.equal(got.reason, "unknown")
})

test("messages count per user per guild and rank biggest first", () => {
	const store = fresh_store()
	for (let i = 0; i < 5; i++) store.add_message("g1", "alice")
	for (let i = 0; i < 2; i++) store.add_message("g1", "bob")
	store.add_message("g2", "bob")

	const board = board_by_id("messages")
	const g1 = store.ranking("g1", board.counts_of)
	const g2 = store.ranking("g2", board.counts_of)
	console.log(`  g1=${JSON.stringify(g1)} g2=${JSON.stringify(g2)}`)
	assert.deepEqual(g1, [["alice", 5], ["bob", 2]])
	assert.deepEqual(g2, [["bob", 1]])
})

test("a tie keeps a stable order so paging cannot repeat or skip a row", () => {
	const store = fresh_store()
	for (const id of ["zed", "adam", "mike"]) store.add_message("g1", id)
	const first = store.ranking("g1", board_by_id("messages").counts_of).map(([id]) => id)
	store.add_message("g1", "adam")
	store.add_message("g1", "zed")
	store.add_message("g1", "mike")
	const second = store.ranking("g1", board_by_id("messages").counts_of).map(([id]) => id)
	console.log(`  first=${first.join(",")} second=${second.join(",")}`)
	assert.deepEqual(first, ["adam", "mike", "zed"])
	assert.deepEqual(second, first)
})

test("an invite is credited once, and a leave shows up beside it", () => {
	const store = fresh_store()
	store.credit_invite("g1", "alice", "newbie")
	store.credit_invite("g1", "alice", "other")
	const g = store.guild("g1")
	assert.equal(g.invites.alice, 2)

	const blamed = store.credit_leave("g1", "newbie")
	console.log(`  invites=${g.invites.alice} left=${g.left.alice} blamed=${blamed}`)
	assert.equal(blamed, "alice")
	assert.equal(g.left.alice, 1)
	assert.equal(board_by_id("invites").note(g, "alice"), " · 1 left")
})

test("a leave by someone nobody invited credits nobody", () => {
	const store = fresh_store()
	const blamed = store.credit_leave("g1", "stranger")
	console.log(`  blamed=${blamed} left=${JSON.stringify(store.guild("g1").left)}`)
	assert.equal(blamed, null)
	assert.deepEqual(store.guild("g1").left, {})
})

test("place_of finds you, and reports honestly when you are not on the board", () => {
	const store = fresh_store()
	for (let i = 0; i < 3; i++) store.add_message("g1", "alice")
	store.add_message("g1", "bob")
	const counts_of = board_by_id("messages").counts_of
	const bob = store.place_of("g1", counts_of, "bob")
	const ghost = store.place_of("g1", counts_of, "ghost")
	console.log(`  bob=#${bob.place}/${bob.total} count=${bob.count} · ghost place=${ghost.place}`)
	assert.deepEqual(bob, { place: 2, count: 1, total: 2 })
	assert.equal(ghost.place, 0)
})

test("counts survive a restart, started_at and all", () => {
	const path = join(scratch(), "counts.json")
	const first = new Store(path, () => 1_700_000_000_000)
	first.add_message("g1", "alice")
	first.credit_invite("g1", "alice", "newbie")
	first.flush()

	const second = new Store(path, () => 1_900_000_000_000)
	const g = second.guild("g1")
	console.log(`  reloaded messages=${g.messages.alice} invites=${g.invites.alice} started_at=${g.started_at}`)
	assert.equal(g.messages.alice, 1)
	assert.equal(g.invites.alice, 1)
	assert.equal(g.started_at, 1_700_000_000_000, "the clock must not restart with the process")
})

test("a corrupt file is set aside, not fatal", () => {
	const path = join(scratch(), "counts.json")
	writeFileSync(path, "{ this is not json")
	const store = new Store(path, () => 1)
	store.add_message("g1", "alice")
	console.log(`  recovered, wreck kept=${existsSync(`${path}.broken`)}`)
	assert.equal(store.guild("g1").messages.alice, 1)
	assert.ok(existsSync(`${path}.broken`))
})

test("pages wrap instead of running off either end", () => {
	const rows = Array.from({ length: PAGE_SIZE * 2 + 1 }, (_, i) => [`u${i}`, 100 - i])
	console.log(`  ${rows.length} rows -> ${page_count(rows)} pages; -1 wraps to ${clamp_page(-1, rows)}`)
	assert.equal(page_count(rows), 3)
	assert.equal(clamp_page(-1, rows), 2)
	assert.equal(clamp_page(3, rows), 0)
	assert.equal(page_count([]), 1)
})

test("a page shows its ten, and pins the viewer's own line when they are elsewhere", () => {
	const store = fresh_store()
	const many = 25
	for (let i = 0; i < many; i++) {
		for (let n = 0; n <= many - i; n++) store.add_message("g1", `u${i}`)
	}
	const board = board_by_id("messages")
	const rows = store.ranking("g1", board.counts_of)
	const { embeds, components } = render_board(board, store.guild("g1"), rows, 0, "u20")
	const body = embeds[0].data.description
	const shown = body.split("\n").filter((l) => l.includes("—")).length
	console.log(`  ${rows.length} ranked, ${shown} lines on page 1, footer="${embeds[0].data.footer.text}"`)
	assert.ok(body.includes("<@u0>"), "leader is on page one")
	assert.ok(body.includes("_(you)_"), "the viewer is told their own place")
	assert.equal(shown, PAGE_SIZE + 1) // ten rows plus the viewer's pinned line
	assert.equal(components.length, 2) // paging row, then the board switcher
})

test("an empty board says so rather than showing a blank panel", () => {
	const store = fresh_store()
	const board = board_by_id("invites")
	const { embeds, components } = render_board(board, store.guild("g1"), [], 0, "alice")
	console.log(`  empty description="${embeds[0].data.description}"`)
	assert.match(embeds[0].data.description, /Nobody yet/)
	assert.equal(components.length, 1) // no paging row when there is one page
})

test("button ids round-trip, and every board has one", () => {
	for (const board of BOARDS) {
		const back = parse_button_id(button_id(board.id, 4))
		console.log(`  ${board.id} -> ${button_id(board.id, 4)} -> ${JSON.stringify(back)}`)
		assert.deepEqual(back, { board_id: board.id, page: 4 })
	}
	assert.equal(parse_button_id("something|else|0"), null)
})

test("every board row is complete, so a new one cannot be half-added", () => {
	for (const board of BOARDS) {
		const guild = { invites: { a: 1 }, messages: { a: 1 }, left: {}, joined_by: {}, started_at: 1 }
		console.log(`  ${board.id}: "${board.label}" ${board.emoji} unit(1)=${board.unit(1)} unit(2)=${board.unit(2)}`)
		assert.ok(board.id && board.label && board.emoji && board.title)
		assert.equal(typeof board.counts_of(guild), "object")
		assert.notEqual(board.unit(1), board.unit(2), "singular and plural must differ")
		assert.equal(typeof board.note(guild, "a"), "string")
	}
})
