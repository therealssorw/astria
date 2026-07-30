// Turning a ranking into something to look at. Kept away from the gateway code
// so the same page can be built by a slash command or by a button press.

import { ActionRowBuilder, ButtonBuilder, ButtonStyle, EmbedBuilder } from "discord.js"
import { BOARDS } from "./boards.js"

export const PAGE_SIZE = 10

// Astria gold, the same colour the game's UI uses for a heading.
const EMBED_COLOUR = 0xe0b64a

const MEDALS = ["🥇", "🥈", "🥉"]

// Button ids carry everything a press needs to redraw: which board, which page.
export const BUTTON_PREFIX = "lb"

export function button_id(board_id, page) {
	return `${BUTTON_PREFIX}|${board_id}|${page}`
}

export function parse_button_id(custom_id) {
	const [prefix, board_id, page] = custom_id.split("|")
	if (prefix !== BUTTON_PREFIX) return null
	return { board_id, page: Number(page) || 0 }
}

export function page_count(rows) {
	return Math.max(1, Math.ceil(rows.length / PAGE_SIZE))
}

// Pages wrap rather than dead-end, so the buttons are never a lie about what
// happens when you press them.
export function clamp_page(page, rows) {
	const pages = page_count(rows)
	return ((page % pages) + pages) % pages
}

function place_label(place) {
	return MEDALS[place - 1] || `\`#${String(place).padStart(2, " ")}\``
}

export function render_board(board, guild_record, rows, page, viewer_id) {
	page = clamp_page(page, rows)
	const start = page * PAGE_SIZE
	const slice = rows.slice(start, start + PAGE_SIZE)

	const lines = slice.map(([id, n], i) => {
		const place = start + i + 1
		const you = id === viewer_id ? " ←" : ""
		return `${place_label(place)} <@${id}> — **${n}** ${board.unit(n)}${board.note(guild_record, id)}${you}`
	})

	// An empty board is the normal state on day one; say so instead of showing
	// a blank panel that reads like something is broken.
	if (!lines.length) lines.push("_Nobody yet. Be the first._")

	// The viewer's own place, when they are further down than this page reaches.
	const mine = rows.findIndex(([id]) => id === viewer_id)
	if (mine >= 0 && (mine < start || mine >= start + PAGE_SIZE)) {
		const [, n] = rows[mine]
		lines.push("", `${place_label(mine + 1)} <@${viewer_id}> — **${n}** ${board.unit(n)} _(you)_`)
	}

	const since = Math.floor((guild_record.started_at ?? Date.now()) / 1000)
	const embed = new EmbedBuilder()
		.setColor(EMBED_COLOUR)
		.setTitle(`${board.emoji} ${board.title}`)
		.setDescription(lines.join("\n"))
		.setFooter({
			text: rows.length
				? `Page ${page + 1}/${page_count(rows)} · ${rows.length} on the board`
				: "Nothing counted yet",
		})
		.addFields({ name: "​", value: `Counting since <t:${since}:D> (<t:${since}:R>)` })

	return { embeds: [embed], components: board_controls(board, page, rows) }
}

// Two rows: paging for this board, then one button per board so you can flip
// between them without typing the command again. Both are walked out of BOARDS.
function board_controls(board, page, rows) {
	const rows_out = []
	const pages = page_count(rows)

	if (pages > 1) {
		rows_out.push(
			new ActionRowBuilder().addComponents(
				new ButtonBuilder()
					.setCustomId(button_id(board.id, page - 1))
					.setLabel("Prev")
					.setStyle(ButtonStyle.Secondary),
				new ButtonBuilder()
					.setCustomId(button_id(board.id, page + 1))
					.setLabel("Next")
					.setStyle(ButtonStyle.Secondary),
			),
		)
	}

	rows_out.push(
		new ActionRowBuilder().addComponents(
			...BOARDS.map((b) =>
				new ButtonBuilder()
					.setCustomId(button_id(b.id, 0))
					.setLabel(b.label)
					.setEmoji(b.emoji)
					.setStyle(b.id === board.id ? ButtonStyle.Primary : ButtonStyle.Secondary)
					.setDisabled(b.id === board.id),
			),
		),
	)

	return rows_out
}

// /rank — one line per board, so it grows with the table too.
export function render_rank(store, guild_id, guild_record, user_id) {
	const lines = BOARDS.map((board) => {
		const { place, count, total } = store.place_of(guild_id, board.counts_of, user_id)
		if (!place) return `${board.emoji} **${board.label}** — nothing yet`
		return `${board.emoji} **${board.label}** — #${place} of ${total}, **${count}** ${board.unit(count)}${board.note(guild_record, user_id)}`
	})

	const since = Math.floor((guild_record.started_at ?? Date.now()) / 1000)
	return {
		embeds: [
			new EmbedBuilder()
				.setColor(EMBED_COLOUR)
				.setTitle("Standing")
				.setDescription(`<@${user_id}>\n\n${lines.join("\n")}`)
				.setFooter({ text: "Counted since the bot started keeping score" })
				.setTimestamp(guild_record.started_at ?? Date.now()),
		],
		components: [
			new ActionRowBuilder().addComponents(
				...BOARDS.map((b) =>
					new ButtonBuilder()
						.setCustomId(button_id(b.id, 0))
						.setLabel(b.label)
						.setEmoji(b.emoji)
						.setStyle(ButtonStyle.Secondary),
				),
			),
		],
	}
}
