// The leaderboards, as a table. The slash command's choices, the /rank lines,
// the button ids and the embed titles are all walked out of this list, so a
// third board is one row here and no new code anywhere else.

export const BOARDS = [
	{
		id: "invites",
		label: "Invites",
		emoji: "📨",
		title: "Most people brought in",
		// Where this board's numbers live inside a guild record.
		counts_of: (g) => g.invites,
		unit: (n) => (n === 1 ? "invite" : "invites"),
		// Anything worth saying beside the number. Churn belongs next to the
		// total or the total flatters whoever invites people who do not stay.
		note: (g, id) => (g.left[id] ? ` · ${g.left[id]} left` : ""),
	},
	{
		id: "messages",
		label: "Messages",
		emoji: "💬",
		title: "Most messages sent",
		counts_of: (g) => g.messages,
		unit: (n) => (n === 1 ? "message" : "messages"),
		note: () => "",
	},
]

export const DEFAULT_BOARD = BOARDS[0]

export function board_by_id(id) {
	return BOARDS.find((b) => b.id === id) || DEFAULT_BOARD
}
