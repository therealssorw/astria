// Working out who invited a new member. Discord never tells you; it only tells
// you how many times each invite link has been used. So the bot keeps its own
// copy of that tally and, when someone joins, looks for the one that went up.
//
// The diff is kept as a plain function over two maps precisely so it can be
// tested without a gateway, a token or a server.

import { Collection } from "discord.js"

// Snapshot of one guild: invite code -> uses. The vanity URL is folded in under
// a code of its own so a vanity join is recognised rather than shrugged at.
export const VANITY_CODE = "__vanity__"

/** @returns {{code: string, inviter_id: string|null, reason: string}} */
export function invite_diff(before, after, guild_owner_id = null) {
	// The normal case: exactly one code's use count went up by one.
	for (const [code, entry] of Object.entries(after)) {
		const was = before[code]?.uses ?? 0
		if (entry.uses > was) {
			if (code === VANITY_CODE) {
				// A vanity join belongs to nobody in particular; the server owner
				// is the closest honest answer, and being explicit beats guessing.
				return { code, inviter_id: guild_owner_id, reason: "vanity" }
			}
			return { code, inviter_id: entry.inviter_id ?? null, reason: "used" }
		}
	}

	// A single-use invite is deleted the instant it is used, so it is missing
	// from `after` rather than incremented. Exactly one vanished code is still
	// an answer; two or more and we cannot tell which one they walked through.
	const gone = Object.keys(before).filter((code) => !(code in after))
	if (gone.length === 1) {
		const entry = before[gone[0]]
		return { code: gone[0], inviter_id: entry.inviter_id ?? null, reason: "used-up" }
	}

	return { code: null, inviter_id: null, reason: gone.length ? "ambiguous" : "unknown" }
}

// Ask Discord for the current tally. Needs Manage Server; without it the fetch
// throws and the caller carries on counting messages, one board short but alive.
export async function snapshot_invites(guild) {
	const snap = {}
	const invites = await guild.invites.fetch()
	for (const invite of invites.values()) {
		snap[invite.code] = { uses: invite.uses ?? 0, inviter_id: invite.inviter?.id ?? null }
	}
	if (guild.vanityURLCode) {
		try {
			const vanity = await guild.fetchVanityData()
			snap[VANITY_CODE] = { uses: vanity.uses ?? 0, inviter_id: null }
		} catch {
			// Vanity data is a nice-to-have; a boost level lost mid-run is not an error.
		}
	}
	return snap
}

// One snapshot per guild, kept warm so a join only has to fetch once more.
export class InviteCache {
	constructor() {
		this.by_guild = new Collection()
	}

	async prime(guild) {
		try {
			this.by_guild.set(guild.id, await snapshot_invites(guild))
			return true
		} catch (err) {
			console.warn(`[invites] cannot read invites for ${guild.name}: ${err.message}`)
			console.warn("[invites] give the bot Manage Server, or the invite board stays empty")
			this.by_guild.set(guild.id, {})
			return false
		}
	}

	before(guild_id) {
		return this.by_guild.get(guild_id) || {}
	}

	set(guild_id, snap) {
		this.by_guild.set(guild_id, snap)
	}
}
