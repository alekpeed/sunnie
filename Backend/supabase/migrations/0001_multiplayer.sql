-- Turn-based multiplayer for Sunnie Days games (ADR-035).
--
-- Carries game moves and nothing else. Journal entries, wellness check-ins,
-- health figures, plants, meals, trips, photos, audio, and preferences never
-- reach this database — that boundary is the load-bearing half of ADR-035, and
-- every table here is named and shaped so that widening it would be an obvious
-- change rather than a quiet one.
--
-- Tables are prefixed `sunnie_` rather than placed in their own schema, because
-- a non-public schema has to be added to the API's exposed list before PostgREST
-- will serve it, and a prefix survives being applied to either a dedicated
-- project or one shared with something else.

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

-- Pseudonymous. One row per device-person, keyed by a Supabase anonymous auth
-- user: nobody supplies an email, a phone number, or a real name. `display_name`
-- is a nickname with a default, so a player who types nothing is still playable
-- rather than blocked.
create table if not exists public.sunnie_player (
    id           uuid primary key references auth.users (id) on delete cascade,
    display_name text        not null default 'Player',
    created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------

-- A short, human-sayable code, so pairing is "read me the code" rather than an
-- account lookup. Ambiguous glyphs are excluded: no O/0, no I/1, because this
-- gets read aloud and typed by someone squinting at a phone.
create or replace function public.sunnie_join_code()
returns text
language sql
volatile
as $$
    select string_agg(
        substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
               (floor(random() * 32) + 1)::int, 1),
        ''
    )
    from generate_series(1, 6);
$$;

create table if not exists public.sunnie_session (
    id             uuid primary key default gen_random_uuid(),
    join_code      text        not null unique default public.sunnie_join_code(),
    -- The mechanic, not the game: mechanics are already modelled separately in
    -- the domain, so one can ship without the other six.
    mechanic       text        not null,
    game_key       text        not null,
    pack_id        text,
    puzzle_id      text,
    status         text        not null default 'open'
                   check (status in ('open', 'active', 'finished', 'abandoned')),
    turn_player_id uuid        references public.sunnie_player (id) on delete set null,
    created_by     uuid        not null references public.sunnie_player (id) on delete cascade,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

-- Two seats, and the unique constraint is what stops a third player joining by
-- racing: seat is claimed by the database, not checked by the client.
create table if not exists public.sunnie_session_player (
    session_id uuid        not null references public.sunnie_session (id) on delete cascade,
    player_id  uuid        not null references public.sunnie_player (id) on delete cascade,
    seat       smallint    not null check (seat between 0 and 1),
    joined_at  timestamptz not null default now(),
    primary key (session_id, player_id),
    unique (session_id, seat)
);

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

-- Append-only. Nothing here is ever updated in place, so a session's state is
-- whatever replaying its moves in sequence produces — which is what makes two
-- clients written in different languages able to agree.
--
-- Two uniqueness constraints, each load-bearing:
--
--   * (session_id, action_key) is idempotency, in the same discipline as care
--     events and Watch actions (ADR-011). A phone that loses signal mid-submit
--     and retries must play one turn, not two.
--
--     The key is `game.move.<session>.<player>.<ordinal>`, and the player in it
--     is what keeps this constraint independent of the one below. Two clients
--     both plan the next ordinal before either has written a row, so an ordinal
--     is not unique in a session until this table has settled it. Without the
--     player the key would be a pure function of `sequence`, these two
--     constraints would be one constraint written twice, and both players would
--     compute the same key for the same ordinal — each then finding the other's
--     move under what it believes is its own key and dropping its turn.
--   * (session_id, sequence) is ordering, and it is what makes a simultaneous
--     submission by both players resolve to a definite result rather than a
--     racy one: the second writer's insert fails and it re-reads.
create table if not exists public.sunnie_move (
    id         uuid        primary key default gen_random_uuid(),
    session_id uuid        not null references public.sunnie_session (id) on delete cascade,
    player_id  uuid        not null references public.sunnie_player (id) on delete cascade,
    sequence   integer     not null check (sequence >= 0),
    action_key text        not null,
    payload    jsonb       not null,
    created_at timestamptz not null default now(),
    unique (session_id, action_key),
    unique (session_id, sequence)
);

create index if not exists sunnie_move_session_sequence_idx
    on public.sunnie_move (session_id, sequence);

create index if not exists sunnie_session_player_player_idx
    on public.sunnie_session_player (player_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.sunnie_player         enable row level security;
alter table public.sunnie_session        enable row level security;
alter table public.sunnie_session_player enable row level security;
alter table public.sunnie_move           enable row level security;

-- Membership is asked about from inside policies on the very table that stores
-- it, which is a recursion Postgres refuses. `security definer` steps outside
-- RLS for this one lookup; it is safe because it answers only about the caller,
-- takes no user-controlled table name, and has an empty search_path so nothing
-- can be shadowed into it.
create or replace function public.sunnie_is_member(target_session uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.sunnie_session_player sp
        where sp.session_id = target_session
          and sp.player_id = auth.uid()
    );
$$;

-- Players: your own row, and the rows of people you are actually playing with —
-- the latter so a nickname can be shown beside a move. Not the whole table.
drop policy if exists sunnie_player_select on public.sunnie_player;
create policy sunnie_player_select on public.sunnie_player
    for select using (
        id = auth.uid()
        or exists (
            select 1
            from public.sunnie_session_player mine
            join public.sunnie_session_player theirs
              on theirs.session_id = mine.session_id
            where mine.player_id = auth.uid()
              and theirs.player_id = public.sunnie_player.id
        )
    );

drop policy if exists sunnie_player_insert on public.sunnie_player;
create policy sunnie_player_insert on public.sunnie_player
    for insert with check (id = auth.uid());

drop policy if exists sunnie_player_update on public.sunnie_player;
create policy sunnie_player_update on public.sunnie_player
    for update using (id = auth.uid()) with check (id = auth.uid());

-- Sessions: members see their own. An open session is also readable by code, so
-- the second player can look one up before they are a member of it — that is
-- what joining requires, and the code is the capability.
drop policy if exists sunnie_session_select on public.sunnie_session;
create policy sunnie_session_select on public.sunnie_session
    for select using (
        public.sunnie_is_member(id)
        or status = 'open'
    );

drop policy if exists sunnie_session_insert on public.sunnie_session;
create policy sunnie_session_insert on public.sunnie_session
    for insert with check (created_by = auth.uid());

drop policy if exists sunnie_session_update on public.sunnie_session;
create policy sunnie_session_update on public.sunnie_session
    for update using (public.sunnie_is_member(id))
             with check (public.sunnie_is_member(id));

-- Membership: you may add yourself and no one else, and only to a session that
-- is still open. The seat unique constraint decides who wins a race for seat 1.
drop policy if exists sunnie_session_player_select on public.sunnie_session_player;
create policy sunnie_session_player_select on public.sunnie_session_player
    for select using (public.sunnie_is_member(session_id));

drop policy if exists sunnie_session_player_insert on public.sunnie_session_player;
create policy sunnie_session_player_insert on public.sunnie_session_player
    for insert with check (
        player_id = auth.uid()
        and exists (
            select 1 from public.sunnie_session s
            where s.id = session_id
              and s.status in ('open', 'active')
        )
    );

-- Moves: members read every move in their session, and write only their own.
-- There is deliberately no update and no delete policy — the table is
-- append-only, and a move that could be edited after the fact would make replay
-- meaningless.
drop policy if exists sunnie_move_select on public.sunnie_move;
create policy sunnie_move_select on public.sunnie_move
    for select using (public.sunnie_is_member(session_id));

drop policy if exists sunnie_move_insert on public.sunnie_move;
create policy sunnie_move_insert on public.sunnie_move
    for insert with check (
        player_id = auth.uid()
        and public.sunnie_is_member(session_id)
    );

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

-- Only moves are published. A client learns "there is a new turn" and then
-- reads it under the policies above, rather than being pushed session rows it
-- would have to be trusted to filter.
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'sunnie_move'
    ) then
        alter publication supabase_realtime add table public.sunnie_move;
    end if;
end
$$;
