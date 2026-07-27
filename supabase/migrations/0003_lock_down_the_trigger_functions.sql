-- Take the two trigger functions back out of the public API.
--
-- Supabase's linter caught both the moment 0001 landed, and both are the same
-- shape of mistake: a function that exists to be fired BY A TRIGGER is also,
-- by default, callable by anyone as `/rest/v1/rpc/<name>` — with the anon key
-- that ships inside every copy of the game.
--
--   handle_new_user()  is SECURITY DEFINER, so it runs as its owner and
--                      bypasses RLS. As an RPC it has no `new` record and
--                      would error rather than write anything, but a function
--                      that runs as the owner should not be reachable by a
--                      caller at all, and "it happens to fail" is not a
--                      security boundary.
--   touch_updated_at() had a mutable search_path, which is the standard way a
--                      definer-ish function gets tricked into calling somebody
--                      else's `now()`.
--
-- Triggers are unaffected: they fire as the table owner and never go through
-- the API's EXECUTE grants.

revoke execute on function public.handle_new_user()  from anon, authenticated, public;
revoke execute on function public.touch_updated_at() from anon, authenticated, public;

alter function public.touch_updated_at() set search_path = public, pg_temp;
