-- Astria accounts and persistence.
--
-- Two tables, both keyed by the Supabase auth user id (which, since Discord is
-- the only provider, is one-to-one with a Discord account):
--
--   profiles      — who they are. Human-readable, safe to show to anyone.
--   player_saves  — what they own. The authoritative copy of gold, bag, score.
--
-- The split matters: a future friends list or leaderboard wants to read a name
-- and an avatar without being handed everyone's purse.
--
-- ROW-LEVEL SECURITY IS THE WHOLE POINT HERE. The anon key ships inside the
-- game client, so anyone can extract it and call this API by hand. The policies
-- below give that caller exactly one power: read its own two rows. There is no
-- insert, update or delete policy for authenticated users at all, so a player
-- cannot write their own coin balance no matter what they send.
--
-- The dedicated game server uses the SERVICE key, which bypasses RLS entirely,
-- and is the only thing that ever writes a save. That key must never appear in
-- a client build — it lives in ASTRIA_SUPABASE_SERVICE_KEY on the server box.

-- ---------------------------------------------------------------- profiles

create table if not exists public.profiles (
    user_id     uuid primary key references auth.users (id) on delete cascade,
    username    text        not null default 'Player',
    discord_id  text,
    avatar_url  text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

comment on table public.profiles is
    'Display identity, mirrored from Discord on every login by the game server.';

-- ------------------------------------------------------------ player_saves

create table if not exists public.player_saves (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    coins      bigint      not null default 0,
    -- item id -> count, matching scripts/items/item_db.gd. Stored as jsonb
    -- rather than a row per item because the game always loads and writes the
    -- whole bag at once, and never queries "who owns a sword".
    items      jsonb       not null default '{}'::jsonb,
    kills      integer     not null default 0,
    deaths     integer     not null default 0,
    updated_at timestamptz not null default now(),

    -- The server already refuses to go negative; this is the backstop that
    -- catches a bug in the server rather than a cheating client.
    constraint player_saves_coins_non_negative  check (coins  >= 0),
    constraint player_saves_kills_non_negative  check (kills  >= 0),
    constraint player_saves_deaths_non_negative check (deaths >= 0),
    constraint player_saves_items_is_object     check (jsonb_typeof(items) = 'object')
);

comment on table public.player_saves is
    'Authoritative gold/bag/score. Written ONLY by the dedicated server.';

-- ------------------------------------------------------------ seeding rows

-- Create both rows the moment an account exists, so the server never has to
-- special-case "first ever login" mid-handshake.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (user_id, username, discord_id, avatar_url)
    values (
        new.id,
        coalesce(
            new.raw_user_meta_data ->> 'full_name',
            new.raw_user_meta_data ->> 'name',
            'Player'),
        new.raw_user_meta_data ->> 'provider_id',
        new.raw_user_meta_data ->> 'avatar_url')
    on conflict (user_id) do nothing;

    insert into public.player_saves (user_id)
    values (new.id)
    on conflict (user_id) do nothing;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ------------------------------------------------------------ housekeeping

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
    for each row execute function public.touch_updated_at();

drop trigger if exists player_saves_touch on public.player_saves;
create trigger player_saves_touch before update on public.player_saves
    for each row execute function public.touch_updated_at();

-- --------------------------------------------------------------------- RLS

alter table public.profiles     enable row level security;
alter table public.player_saves enable row level security;

-- Read-only, and only your own. Deliberately no write policy: see the header.
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles
    for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "read own save" on public.player_saves;
create policy "read own save" on public.player_saves
    for select to authenticated
    using (auth.uid() = user_id);

-- PostgREST still needs the table-level grant; RLS narrows it from there.
grant select on public.profiles     to authenticated;
grant select on public.player_saves to authenticated;
revoke insert, update, delete on public.profiles     from authenticated, anon;
revoke insert, update, delete on public.player_saves from authenticated, anon;
