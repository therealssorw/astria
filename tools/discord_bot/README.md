# Astria scorekeeper bot

Counts two things per Discord server, from the moment it first joins:

- **Invites** — who brought each new member in, worked out by watching which
  invite link's use count went up. Leaves are counted too and shown beside the
  total, so a revolving door does not read as a win.
- **Messages** — how many messages each member sends. Only the count is kept;
  the bot does not ask for the Message Content intent and never reads the text.

## Commands

| Command | Does |
| --- | --- |
| `/leaderboard [board] [page]` | The board, ten to a page. Buttons page it and switch board. |
| `/rank [user]` | Where someone stands on every board. |

Both are registered per server on join, so they appear immediately.

## What it needs

- **Server Members Intent** enabled on the application (Developer Portal →
  Bot → Privileged Gateway Intents). Without it no joins arrive.
- **Manage Server** on the bot's role. That permission is the only way to read
  invite use counts; without it the message board still works and the invite
  board stays empty, with a warning in the log.
- Invite URL scopes: `bot` + `applications.commands`.

## Running it

Token from `DISCORD_BOT_TOKEN`, or from `token.txt` beside `bot.js`
(git-ignored). Counts land in `data/counts.json` — override with
`ASTRIA_BOT_DATA`.

```
npm install
npm start
npm test      # counting, ranking, paging — no token or network needed
```

On the live box it is the systemd unit `astria-discord-bot.service`, installed
in `/opt/astria-bot/`, token in `/etc/astria-discord-bot.env`. Deploy with
`tools/discord_bot/deploy.sh`.
