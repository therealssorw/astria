# Accounts, login and saved data

Players sign in with Discord. Everything they have and everything they have
done lives in Supabase and is written **only** by the dedicated server.

## What is saved

One table drives it: `NetRegistry.PERSISTED` — entry field -> how to clean it
coming back out of the database. `snapshot()` writes exactly those keys and
`apply_save()` reads exactly those keys, so **saving a new piece of progress is
one row there plus its column in a migration**, and no new code on either side.

| Field | Column | Is |
| --- | --- | --- |
| `gold` | `coins` | the purse |
| `items` | `items` | the bag, id -> count |
| `kills` / `deaths` | same | the scoreboard |
| `hotbar` / `hot_slot` | same | the quick-use bar, as arranged |
| `quest` / `quest_kills` | same | the tracked quest and progress towards it |
| `gifts` | `gifts` | what each NPC has already handed over, so none gives twice |
| `equipped` | `equipped` | armor worn, by slot |
| `bosses` | `bosses` | boss kind -> times felled |

Not saved, on purpose: `name` and `user_id` come from the account on every
login (so a Discord rename follows the player), and `seen` — the bar's memory of
which items were already offered a slot — is re-derived from the bag, which is
what makes a slot the player cleared stay clear.

`tests/test_accounts.gd` asserts that every field of a live entry is either
saved or on that short list, so adding progress and forgetting to persist it
fails a test rather than failing a player.

## The pieces

| File | Runs on | Does |
| --- | --- | --- |
| `scripts/core/account/supabase.gd` | both | HTTP layer; knows the URL and the two keys |
| `scripts/core/account/auth.gd` | client | Discord OAuth (PKCE), token storage, silent re-login |
| `scripts/core/account/save_store.gd` | server | verifies tokens, loads/writes saves |
| `scripts/core/net/net_registry.gd` | both | what a player IS, and which of it survives a logout |
| `supabase/migrations/0001_accounts.sql` | database | tables, RLS, signup trigger |
| `supabase/migrations/0002_save_everything.sql` | database | the rest of a player: bar, quest, gifts, armor, bosses |

## Flow

1. Menu shows **LOG IN WITH DISCORD**. `Auth` makes a PKCE verifier, listens on
   `127.0.0.1:27045`, and opens the system browser at Supabase's `/authorize`.
2. Discord authenticates; Supabase redirects back to the loopback port with an
   auth code, which `Auth` trades (with the verifier) for an access token and a
   refresh token. The refresh token is kept in `user://account.cfg`.
3. The client connects and sends the **access token** in `sv_register`.
4. The server calls `/auth/v1/user` to verify it, loads `player_saves` with the
   service key, and lays the row over a **fresh** entry with
   `NetRegistry.apply_save` — so a save written by an older build still comes
   back as a complete player instead of one missing a field.
5. Every change to any of it calls `Net._persist`, which queues a debounced
   write (10 s). Disconnect flushes immediately. Gold, items, the bar, quests,
   gifts and armor all pass through `_send_purse`, which is the single place
   that hooks; kills, deaths and boss kills persist where they are counted.

Next launch, step 1 is skipped entirely: the stored refresh token becomes a
live session and the menu joins without drawing anything.

## The two keys

- **anon** — public, compiled into the client. Row-level security is what
  actually protects the data; all it can do is read your own two rows.
- **service** — bypasses RLS. Read from `ASTRIA_SUPABASE_SERVICE_KEY` on the
  dedicated server. `Supabase.service_key()` returns `""` on any non-dedicated
  build, and `tests/test_accounts.gd` asserts that.

Both, plus the project URL, can be overridden with `ASTRIA_SUPABASE_ANON_KEY`,
`ASTRIA_SUPABASE_SERVICE_KEY`, `ASTRIA_SUPABASE_URL`.

## Setup checklist (one-time, in the Supabase dashboard)

1. **Discord provider** — Authentication -> Providers -> Discord. Needs a
   Discord application (https://discord.com/developers/applications): copy its
   Client ID and Client Secret in, and add Supabase's callback URL
   (`https://<project>.supabase.co/auth/v1/callback`) to the Discord app's
   OAuth2 redirects.
2. **Redirect allow-list** — Authentication -> URL Configuration -> Redirect
   URLs: add `http://127.0.0.1:27045`. Without this Supabase refuses to send
   the browser back to the game and login silently times out.
3. **Migrations** — run `supabase/migrations/0001_accounts.sql`, then
   `0002_save_everything.sql`. As of this writing the project has **neither**:
   `list_migrations` comes back empty, so nothing has been applied yet.
4. **Keys** — put the anon key in `Supabase.ANON_KEY` (or the env var), and set
   `ASTRIA_SUPABASE_SERVICE_KEY` on the server box before `run_server.bat`.

## Testing without Discord

A server started with `--allow-guests` accepts unauthenticated players, whose
progress is not saved. The live server is never launched with it.

```bash
godot --headless --server --allow-guests
godot --username=Ada --join=127.0.0.1
```

`godot --headless res://tests/test_accounts.tscn` covers the parts that fail
silently: the service key never leaking to a client, `user_id`/gold/items never
entering the public registry broadcast, every field of a player being either
saved or deliberately not, a whole played-in player surviving the round trip
through `jsonb`, a stale or hand-edited row degrading to a sane player instead
of wedging one, a failed write being requeued rather than lost, and PKCE
staying base64url.
