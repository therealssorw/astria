# Accounts, login and saved data

Players sign in with Discord. Their gold, bag, kills and deaths live in
Supabase and are written **only** by the dedicated server.

## The pieces

| File | Runs on | Does |
| --- | --- | --- |
| `scripts/core/account/supabase.gd` | both | HTTP layer; knows the URL and the two keys |
| `scripts/core/account/auth.gd` | client | Discord OAuth (PKCE), token storage, silent re-login |
| `scripts/core/account/save_store.gd` | server | verifies tokens, loads/writes saves |
| `supabase/migrations/0001_accounts.sql` | database | tables, RLS, signup trigger |

## Flow

1. Menu shows **LOG IN WITH DISCORD**. `Auth` makes a PKCE verifier, listens on
   `127.0.0.1:27045`, and opens the system browser at Supabase's `/authorize`.
2. Discord authenticates; Supabase redirects back to the loopback port with an
   auth code, which `Auth` trades (with the verifier) for an access token and a
   refresh token. The refresh token is kept in `user://account.cfg`.
3. The client connects and sends the **access token** in `sv_register`.
4. The server calls `/auth/v1/user` to verify it, loads `player_saves` with the
   service key, and drops the row straight into `Net.players[peer_id]`.
5. Every change to gold/items/kills/deaths calls `Net._persist`, which queues a
   debounced write (10 s). Disconnect flushes immediately.

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
3. **Migration** — run `supabase/migrations/0001_accounts.sql`.
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
entering the public registry broadcast, stale items being dropped from a loaded
bag, a failed write being requeued rather than lost, and PKCE staying base64url.
