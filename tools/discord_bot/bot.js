// Astria's scorekeeper. Two boards: who brought the most people in, and who
// talks the most. Both start at zero the first time the bot sees a server, so
// nobody's history counts and everyone starts the race on the same line.
//
// Run:   node bot.js          (token in DISCORD_BOT_TOKEN, or token.txt beside this file)
// Needs: Server Members Intent enabled on the application, and the Manage Server
//        permission on the bot's role — that second one is what lets it read
//        invite use counts, which is the only way to know who invited whom.

import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

import {
	ApplicationCommandOptionType,
	Client,
	Events,
	GatewayIntentBits,
	MessageFlags,
	Partials,
} from "discord.js"

import { BOARDS, DEFAULT_BOARD, board_by_id } from "./src/boards.js"
import { InviteCache, invite_diff, snapshot_invites } from "./src/invites.js"
import { Store } from "./src/store.js"
import { parse_button_id, render_board, render_rank } from "./src/render.js"

const HERE = dirname(fileURLToPath(import.meta.url))

// The token is a secret and this repo is public: it is read from the
// environment, or from a file that .gitignore already refuses to track.
function read_token() {
	if (process.env.DISCORD_BOT_TOKEN) return process.env.DISCORD_BOT_TOKEN.trim()
	const path = join(HERE, "token.txt")
	if (existsSync(path)) return readFileSync(path, "utf8").trim()
	console.error("No token. Set DISCORD_BOT_TOKEN, or put the token in tools/discord_bot/token.txt")
	process.exit(1)
}

const store = new Store(process.env.ASTRIA_BOT_DATA || join(HERE, "data", "counts.json"))
const invites = new InviteCache()

const client = new Client({
	intents: [
		GatewayIntentBits.Guilds,
		GatewayIntentBits.GuildMembers, // privileged: joins and leaves
		GatewayIntentBits.GuildMessages, // counting only, the text is never read
		GatewayIntentBits.GuildInvites,
	],
	// A leave can arrive for someone who was never in the member cache.
	partials: [Partials.GuildMember],
})

// Both commands are built out of the BOARDS table, so a new board appears in
// the choice list and in /rank without anything here being touched.
const COMMANDS = [
	{
		name: "leaderboard",
		description: "Who is winning",
		options: [
			{
				name: "board",
				description: "Which board to show",
				type: ApplicationCommandOptionType.String,
				required: false,
				choices: BOARDS.map((b) => ({ name: b.label, value: b.id })),
			},
			{
				name: "page",
				description: "Page number, from 1",
				type: ApplicationCommandOptionType.Integer,
				required: false,
				min_value: 1,
			},
		],
	},
	{
		name: "rank",
		description: "Where someone stands on every board",
		options: [
			{
				name: "user",
				description: "Whose standing (default: yours)",
				type: ApplicationCommandOptionType.User,
				required: false,
			},
		],
	},
]

// Guild-scoped registration lands immediately; global takes up to an hour and
// there is nothing here worth waiting an hour for.
async function register_commands(guild) {
	try {
		await guild.commands.set(COMMANDS)
	} catch (err) {
		console.warn(`[commands] could not register in ${guild.name}: ${err.message}`)
	}
}

client.once(Events.ClientReady, async (c) => {
	console.log(`[bot] ready as ${c.user.tag}`)
	for (const guild of c.guilds.cache.values()) {
		store.guild(guild.id) // starts the clock the first time we ever see it
		await Promise.all([register_commands(guild), invites.prime(guild)])
		console.log(`[bot] watching ${guild.name}`)
	}
	store.flush()
})

client.on(Events.GuildCreate, async (guild) => {
	store.guild(guild.id)
	await Promise.all([register_commands(guild), invites.prime(guild)])
	console.log(`[bot] added to ${guild.name}, counting from now`)
})

// --- counting ---------------------------------------------------------------

client.on(Events.MessageCreate, (message) => {
	if (!message.guild) return
	if (message.author.bot) return
	if (message.system) return
	store.add_message(message.guild.id, message.author.id)
})

client.on(Events.GuildMemberAdd, async (member) => {
	const guild = member.guild
	// A bot is added by a person clicking an OAuth link, not by an invite, so
	// counting it would credit whoever's link happened to be used last.
	if (member.user.bot) {
		invites.set(guild.id, await snapshot_invites(guild).catch(() => invites.before(guild.id)))
		return
	}

	const before = invites.before(guild.id)
	let after = before
	try {
		after = await snapshot_invites(guild)
	} catch (err) {
		console.warn(`[invites] join in ${guild.name} uncredited: ${err.message}`)
	}
	invites.set(guild.id, after)

	const { inviter_id, reason } = invite_diff(before, after, guild.ownerId)
	if (!inviter_id || inviter_id === member.id) {
		console.log(`[invites] ${member.user.tag} joined, inviter ${reason}`)
		return
	}

	// A rejoin is counted again on purpose: these are join events, and the
	// "left" tally beside the total is what keeps a revolving door visible.
	store.forget_member(guild.id, member.id)
	const total = store.credit_invite(guild.id, inviter_id, member.id)
	console.log(`[invites] ${member.user.tag} joined via ${inviter_id} (${reason}), now ${total}`)
})

client.on(Events.GuildMemberRemove, (member) => {
	if (member.user?.bot) return
	store.credit_leave(member.guild.id, member.id)
})

// Keeping the snapshot honest between joins, so a link made and used in the
// same minute still diffs to exactly one changed code.
client.on(Events.InviteCreate, (invite) => {
	const snap = { ...invites.before(invite.guild.id) }
	snap[invite.code] = { uses: invite.uses ?? 0, inviter_id: invite.inviter?.id ?? null }
	invites.set(invite.guild.id, snap)
})

client.on(Events.InviteDelete, (invite) => {
	const snap = { ...invites.before(invite.guild.id) }
	delete snap[invite.code]
	invites.set(invite.guild.id, snap)
})

// --- showing ----------------------------------------------------------------

function board_reply(guild_id, board, page, viewer_id) {
	const rows = store.ranking(guild_id, board.counts_of)
	return render_board(board, store.guild(guild_id), rows, page, viewer_id)
}

client.on(Events.InteractionCreate, async (interaction) => {
	try {
		if (interaction.isButton()) {
			const press = parse_button_id(interaction.customId)
			if (!press) return
			const board = board_by_id(press.board_id)
			// Editing in place rather than posting again: one leaderboard message
			// per invocation, no matter how much anyone pages through it.
			await interaction.update(board_reply(interaction.guildId, board, press.page, interaction.user.id))
			return
		}

		if (!interaction.isChatInputCommand()) return
		if (!interaction.guildId) {
			await interaction.reply({ content: "Boards are per server — ask me in one.", flags: MessageFlags.Ephemeral })
			return
		}

		if (interaction.commandName === "leaderboard") {
			const board = board_by_id(interaction.options.getString("board") ?? DEFAULT_BOARD.id)
			const page = (interaction.options.getInteger("page") ?? 1) - 1
			await interaction.reply(board_reply(interaction.guildId, board, page, interaction.user.id))
			return
		}

		if (interaction.commandName === "rank") {
			const who = interaction.options.getUser("user") ?? interaction.user
			await interaction.reply(render_rank(store, interaction.guildId, store.guild(interaction.guildId), who.id))
		}
	} catch (err) {
		console.error(`[interaction] ${err.stack || err.message}`)
		// A failed render must not leave the user staring at "thinking…".
		const complain = { content: "That went wrong. It is in the log.", flags: MessageFlags.Ephemeral }
		if (interaction.isRepliable() && !interaction.replied && !interaction.deferred) {
			await interaction.reply(complain).catch(() => {})
		}
	}
})

// --- living and dying -------------------------------------------------------

client.on(Events.Error, (err) => console.error(`[gateway] ${err.message}`))

process.on("unhandledRejection", (err) => {
	// The one failure everybody hits once, and the stack trace for it says
	// nothing useful. Say what to go and click instead.
	if (String(err?.message).includes("disallowed intents")) {
		console.error("[bot] Discord refused the Server Members Intent.")
		console.error("[bot] Developer Portal → your app → Bot → Privileged Gateway Intents → Server Members Intent.")
		console.error("[bot] Without it nobody's join is seen, so the invite board can never fill.")
		process.exit(1)
	}
	console.error(`[unhandled] ${err?.stack || err}`)
})

for (const signal of ["SIGINT", "SIGTERM"]) {
	process.on(signal, () => {
		console.log(`[bot] ${signal}, saving`)
		store.flush()
		client.destroy()
		process.exit(0)
	})
}

client.login(read_token())
