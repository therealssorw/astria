-- The rest of a player, so a logout costs them nothing.
--
-- 0001 kept the purse and the scoreboard: coins, items, kills, deaths. That is
-- what a player OWNS, but not what they have DONE — the quick-use bar they
-- arranged, the quest they are half way through, the gifts they have already
-- been handed, the armor they are wearing and the bosses they have felled were
-- all still thrown away when they closed the game.
--
-- Every column here is one row of NetRegistry.PERSISTED, which is the game's
-- side of this same list. The two are walked together: adding a column without
-- its row (or the reverse) simply means that field is not saved, never a
-- broken load, because the server only ever asks for the columns the table
-- knows and only ever applies the keys the row came back with.
--
-- Nullable and defaulted on purpose. A row written by 0001 has none of these,
-- and it must keep loading: a missing column reads as "keep the default", not
-- as a corrupt save.

alter table public.player_saves
    -- the quick-use bar: 9 slots of item id, "" for an empty one. An array
    -- rather than an object because the POSITION is the whole point.
    add column if not exists hotbar      jsonb   not null default '[]'::jsonb,
    add column if not exists hot_slot    integer not null default 0,
    -- the quest being tracked, and kills counted towards it
    add column if not exists quest       text    not null default '',
    add column if not exists quest_kills integer not null default 0,
    -- GiftData ids already handed over, so no NPC gives its gift twice
    add column if not exists gifts       jsonb   not null default '{}'::jsonb,
    -- armor slot -> item id worn there. Worn pieces are NOT in `items`: a
    -- breastplate is on your back or in your sack, never both.
    add column if not exists equipped    jsonb   not null default '{}'::jsonb,
    -- boss kind -> how many times this player has put it down. Counted rather
    -- than flagged, so "has beaten it" and "has beaten it forty times" are both
    -- answerable off one column.
    add column if not exists bosses      jsonb   not null default '{}'::jsonb;

-- Same backstop as 0001's coin check: these catch a bug in the SERVER, not a
-- cheating client, which cannot write here at all.
alter table public.player_saves
    drop constraint if exists player_saves_hot_slot_in_range,
    add  constraint player_saves_hot_slot_in_range check (hot_slot between 0 and 8);

alter table public.player_saves
    drop constraint if exists player_saves_quest_kills_non_negative,
    add  constraint player_saves_quest_kills_non_negative check (quest_kills >= 0);

alter table public.player_saves
    drop constraint if exists player_saves_hotbar_is_array,
    add  constraint player_saves_hotbar_is_array check (jsonb_typeof(hotbar) = 'array');

alter table public.player_saves
    drop constraint if exists player_saves_gifts_is_object,
    add  constraint player_saves_gifts_is_object check (jsonb_typeof(gifts) = 'object');

alter table public.player_saves
    drop constraint if exists player_saves_equipped_is_object,
    add  constraint player_saves_equipped_is_object check (jsonb_typeof(equipped) = 'object');

alter table public.player_saves
    drop constraint if exists player_saves_bosses_is_object,
    add  constraint player_saves_bosses_is_object check (jsonb_typeof(bosses) = 'object');

comment on column public.player_saves.bosses is
    'Boss kind -> times felled. The one field here that is a RECORD rather than
     a possession: it is what a player has done, and it is what a leaderboard or
     a "first to beat the juggernaut" would read.';

-- Nothing below 0001 changes: still no write policy for authenticated callers,
-- so a client holding the anon key can read these columns on its own row and
-- write none of them.
grant select on public.player_saves to authenticated;
