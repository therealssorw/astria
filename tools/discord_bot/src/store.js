// The one owner of every number the bot keeps. Nothing else counts anything;
// the gateway handlers call in here and the commands read back out.
//
// It is a single JSON file written whole. A busy server is a few thousand rows
// of "id: integer", so a database would buy nothing that fs.rename does not,
// and a file you can open in a text editor is a file you can fix at 3am.

import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from "node:fs"
import { dirname } from "node:path"

// Writes are batched: a chatty server would otherwise rewrite the file once per
// message. Nothing is lost on a clean exit — flush() runs on the way out.
const SAVE_DELAY_MS = 2000

function empty_guild(started_at) {
	return {
		// When counting began for this guild. Every leaderboard is "since" this,
		// which is what makes the numbers fair to whoever joins the race late.
		started_at,
		messages: {},   // user id -> messages sent
		invites: {},    // inviter id -> members brought in
		left: {},       // inviter id -> how many of those have since left
		joined_by: {},  // member id -> who invited them, so a leave can be credited
	}
}

export class Store {
	constructor(path, now = () => Date.now()) {
		this.path = path
		this.now = now
		this._timer = null
		this.data = { version: 1, guilds: {} }
		if (existsSync(path)) {
			try {
				this.data = JSON.parse(readFileSync(path, "utf8"))
			} catch (err) {
				// A truncated file must not cost us the bot. Keep the wreck around
				// so it can be looked at, and start over rather than crash-loop.
				const wreck = `${path}.broken`
				renameSync(path, wreck)
				console.error(`[store] ${path} unreadable (${err.message}); moved to ${wreck}, starting empty`)
			}
		}
		if (!this.data.guilds) this.data.guilds = {}
	}

	// Every read and write goes through here, so a guild the bot has never seen
	// starts counting the moment it is first touched rather than erroring.
	guild(guild_id) {
		let g = this.data.guilds[guild_id]
		if (!g) {
			g = this.data.guilds[guild_id] = empty_guild(this.now())
			this._dirty()
		}
		// Older files predate some of the tables; fill them in on the way past.
		for (const key of ["messages", "invites", "left", "joined_by"]) {
			if (!g[key]) g[key] = {}
		}
		if (!g.started_at) g.started_at = this.now()
		return g
	}

	add_message(guild_id, user_id) {
		const g = this.guild(guild_id)
		g.messages[user_id] = (g.messages[user_id] || 0) + 1
		this._dirty()
		return g.messages[user_id]
	}

	// Someone joined and we know who to thank. Remembering which member it was
	// is what lets credit_leave() undo it later.
	credit_invite(guild_id, inviter_id, member_id) {
		const g = this.guild(guild_id)
		g.invites[inviter_id] = (g.invites[inviter_id] || 0) + 1
		g.joined_by[member_id] = inviter_id
		this._dirty()
		return g.invites[inviter_id]
	}

	// A leave does not take the invite back — bringing someone in still happened —
	// but the leaderboard shows the churn beside the total so the number is honest.
	credit_leave(guild_id, member_id) {
		const g = this.guild(guild_id)
		const inviter_id = g.joined_by[member_id]
		if (!inviter_id) return null
		g.left[inviter_id] = (g.left[inviter_id] || 0) + 1
		this._dirty()
		return inviter_id
	}

	// A rejoin should not pay the inviter twice for the same person, and should
	// not leave a stale "left" mark hanging on them either.
	forget_member(guild_id, member_id) {
		const g = this.guild(guild_id)
		return delete g.joined_by[member_id]
	}

	knows_member(guild_id, member_id) {
		return this.guild(guild_id).joined_by[member_id] !== undefined
	}

	// Sorted [id, count] pairs, biggest first, ties broken by id so paging is
	// stable between two calls that land either side of a new message.
	ranking(guild_id, counts_of) {
		const counts = counts_of(this.guild(guild_id))
		return Object.entries(counts)
			.filter(([, n]) => n > 0)
			.sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
	}

	// 1-based place in that ranking, or 0 for "not on the board at all".
	place_of(guild_id, counts_of, user_id) {
		const rows = this.ranking(guild_id, counts_of)
		const at = rows.findIndex(([id]) => id === user_id)
		return { place: at + 1, count: at < 0 ? 0 : rows[at][1], total: rows.length }
	}

	_dirty() {
		if (this._timer) return
		this._timer = setTimeout(() => this.flush(), SAVE_DELAY_MS)
		this._timer.unref?.()
	}

	// Write beside the real file and rename over it: a kill mid-write leaves the
	// last good copy, never half a JSON document.
	flush() {
		if (this._timer) {
			clearTimeout(this._timer)
			this._timer = null
		}
		mkdirSync(dirname(this.path), { recursive: true })
		const tmp = `${this.path}.tmp`
		writeFileSync(tmp, JSON.stringify(this.data, null, "\t"))
		renameSync(tmp, this.path)
	}
}
