-- Bankpop — Supabase changes to apply in the SQL editor.
--
-- Sections 1-3 are what the app now expects. Section 1 is safe to run while a
-- game is live. Section 4 is optional and needs a decision from you first,
-- because it changes how the app authenticates.
--
-- Nothing here reads, updates or deletes application data, except the one-time
-- backfill in 4.2 which is clearly marked.
--
-- Table columns this was written against (read from the live project):
--   players_test (id, game_id, role, name, wallet, player_id, "SP/IP", avatar)
--   request_test (id, game_id, role, name, wallet, player_id, color)
--   transactions (id, value, from, to, code, time, date, game_id)


-- ===========================================================================
-- 1. Indexes
-- ===========================================================================
-- Every screen filters on game_id, and the banker reads request_test whenever a
-- request arrives. Without these, each of those reads is a sequential scan of
-- the whole table. Rows here are small, so each index costs a few KB and adds
-- no write cost you would notice.

-- Roster + bank header reads: `game_id = ?` and `game_id = ? and role = 'player'`.
create index if not exists players_test_game_role_idx
  on public.players_test (game_id, role);

-- Join-request reads, and the per-device lookups.
create index if not exists request_test_game_idx
  on public.request_test (game_id);

create index if not exists request_test_game_player_idx
  on public.request_test (game_id, player_id);

-- History screen: newest-first for one game, so the LIMIT 200 stops after 200
-- rows instead of sorting the whole game's history in memory.
create index if not exists transactions_game_date_time_idx
  on public.transactions (game_id, date desc, time desc);

-- Supports the `code LIKE '%<playerId>%'` filter as far as it can: a leading
-- wildcard can never use an index for the match itself, but the game_id prefix
-- keeps the scan inside a single game. Section 4.2 replaces the filter entirely.
create index if not exists transactions_game_code_idx
  on public.transactions (game_id, code);


-- ===========================================================================
-- 2. Realtime — this is what turns the live updates on
-- ===========================================================================
-- The app subscribes to these tables instead of polling REST once per second.
-- Until the tables are members of the publication the socket connects and
-- delivers nothing, and the screens quietly fall back to a 5-second
-- reconciliation poll — so the app keeps working, just without live updates.

-- Guarded so the whole file stays re-runnable: a bare `add table` errors with
-- "table is already member of publication" on the second run and would abort the
-- rest of the script.
do $$
declare t text;
begin
  foreach t in array array['players_test','request_test','transactions'] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Check membership:
--
--   select tablename
--   from pg_publication_tables
--   where pubname = 'supabase_realtime'
--   order by tablename;

-- Delete events carry only the replica-identity columns. The client identifies
-- rows by `id`, which is what these events include, so deletes already work —
-- but if `id` is not actually the primary key of those two tables, run this so
-- the banker's Deny/Accept deletions can never be missed:
--
--   alter table public.players_test replica identity full;
--   alter table public.request_test replica identity full;

-- Expected result: a phone on the player screen makes ~6 reads in a 30-second
-- window (the reconciliation poll) instead of 30+, and wallet changes appear
-- within milliseconds of the bank writing them. Free-tier egress for a 2-hour
-- game drops from roughly 140 MB of polling to a few MB.


-- ===========================================================================
-- 3. Atomic money transfers — the app calls this on every payment
-- ===========================================================================
-- Clients used to read both wallets, subtract, and write both back. Two devices
-- paying at the same instant both read the same balance and the second write
-- won: one payment vanished and money was created. This function locks both
-- rows, re-checks the funds and moves the money server-side in one round trip.
--
-- The app calls it as `transfer_money(...)` and falls back to the old sequence
-- (logging a warning) while it does not exist, so run this when convenient —
-- every payment gets the guarantee as soon as it is deployed.

create or replace function public.transfer_money(
  p_game_id   text,
  p_from      text,
  p_from_role text,
  p_to        text,
  p_to_role   text,
  p_amount    numeric
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from players_test%rowtype;
  v_to   players_test%rowtype;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be positive' using errcode = '22023';
  end if;

  -- Lock both rows in a stable order: two opposite transfers cannot deadlock,
  -- and neither balance can move between the check and the update.
  perform 1
     from players_test
    where game_id = p_game_id
      and player_id in (p_from, p_to)
    order by player_id
    for update;

  select * into v_from
    from players_test
   where game_id = p_game_id
     and player_id = p_from
     and role = p_from_role;
  if not found then
    raise exception 'payer not found' using errcode = 'P0002';
  end if;

  select * into v_to
    from players_test
   where game_id = p_game_id
     and player_id = p_to
     and role = p_to_role;
  if not found then
    raise exception 'payee not found' using errcode = 'P0002';
  end if;

  if v_from.wallet < p_amount then
    raise exception 'insufficient funds' using errcode = 'P0001';
  end if;

  update players_test set wallet = wallet - p_amount where id = v_from.id;
  update players_test set wallet = wallet + p_amount where id = v_to.id;

  return jsonb_build_object(
    'payer_wallet', v_from.wallet - p_amount,
    'payee_wallet', v_to.wallet + p_amount,
    'payer_name',   v_from.name,
    'payee_name',   v_to.name);
end;
$$;

-- The client maps the error codes back to its UI: P0001 shows "Insufficient
-- balance", P0002 is treated as a failed payment.
--
-- smoke test (should move 1 from a real payer to a real payee):
--
--   select public.transfer_money('<game_id>', '<payer_id>', 'player',
--                                '<payee_id>', 'player', 1);

-- Note: the app still writes the `transactions` history row itself, so this
-- function deliberately does not insert one. If you move the history write in
-- here later, remove it from the client calls in the same release.


-- ===========================================================================
-- 3.4 Accepting a join — seat the player and move the stake in one step
-- ===========================================================================
-- Accepting a request was four client calls: insert the player, delete the
-- request, read the banker, write the banker. Two devices accepting at once (a
-- second banker on another phone) could both read the same bank balance and
-- lose one stake.
--
-- The bank is the issuer, so its wallet is allowed to go negative here. That is
-- the one difference from transfer_money, which must reject an empty payer.
--
-- Idempotent: a request retried after a timeout will not seat the player twice
-- or charge the stake twice - it just clears the request again.

create or replace function public.stake_player(
  p_game_id        text,
  p_player_id      text,
  p_player_name    text,
  p_stake          numeric,
  p_payment_option text,
  p_request_id     text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_banker  players_test%rowtype;
  v_already boolean;
  v_bank    numeric;
begin
  if p_stake is null or p_stake < 0 then
    raise exception 'stake must not be negative' using errcode = '22023';
  end if;

  select * into v_banker
    from players_test
   where game_id = p_game_id
     and role = 'banker'
   order by id
   limit 1
   for update;
  if not found then
    raise exception 'banker not found' using errcode = 'P0002';
  end if;

  select exists (
    select 1
      from players_test
     where game_id = p_game_id
       and role = 'player'
       and player_id = p_player_id) into v_already;

  if v_already then
    v_bank := v_banker.wallet;
  else
    insert into players_test (name, wallet, game_id, role, player_id, "SP/IP")
    values (p_player_name, p_stake, p_game_id, 'player', p_player_id,
            p_payment_option);

    update players_test set wallet = wallet - p_stake where id = v_banker.id;
    v_bank := v_banker.wallet - p_stake;
  end if;

  delete from request_test
   where game_id = p_game_id
     and id::text = p_request_id;

  return jsonb_build_object(
    'banker_wallet',    v_bank,
    'banker_player_id', v_banker.player_id,
    'staked',           not v_already);
end;
$$;

-- smoke test (should seat a player and drop the bank balance by 200):
--
--   select public.stake_player('<game_id>', '<new_player_id>', 'Test Player',
--                              200, 'PhonePe', '<request_id>');


-- ===========================================================================
-- 4. Optional hardening — decide before running
-- ===========================================================================

-- 4.1 Row-level security -----------------------------------------------------
-- Today anyone holding the publishable key (it ships inside the app) can read
-- and write every game. RLS is the mechanism that fixes that, but there is
-- nothing to write a policy against yet: the app never signs a user in, so
-- Postgres cannot tell one device from another. Enabling RLS as things stand
-- would simply break the app.
--
-- The path is: sign players in (Supabase Auth, or Sign in with Freebuff), add an
-- `owner_id uuid` column to players_test, and then policies like
--
--   alter table public.players_test enable row level security;
--   create policy "players read their own game" on public.players_test
--     for select to authenticated
--     using (game_id in (
--       select game_id from public.players_test where owner_id = auth.uid()
--     ));
--
-- Realtime respects RLS too, so this is also what stops one game from
-- subscribing to another game's rows.

-- 4.2 Index-friendly history filter -----------------------------------------
-- The history query matches `code LIKE '%<playerId>%'`, which cannot use an
-- index. These two columns fix it permanently. The app is already written to
-- prefer them and to fall back to the wildcard filter while they are missing,
-- so this can be deployed at any time — the first open after the backfill takes
-- the indexed path.

alter table public.transactions add column if not exists payer_id text;
alter table public.transactions add column if not exists receiver_id text;

-- The two columns have to be filled in by the database, not by the app: every
-- client insert (five of them: ScanPay, the two roster pay paths, and the bank's
-- advance) writes only `code` and knows nothing about these columns. Without
-- this trigger the one-time backfill below would fill in today's rows and every
-- payment recorded from then on would be born NULL - and because the app takes
-- the indexed path as soon as the columns exist, those new payments would be
-- invisible in the history screen. The trigger keeps both paths correct without
-- touching a single insert site, present or future.
create or replace function public.transactions_fill_ids()
returns trigger
language plpgsql
as $$
begin
  -- `code` is always "<payerId>_<payeeId>" and player ids are v4 UUIDs, so the
  -- first underscore is the separator. The columns are derived, never stored
  -- independently: a writer that sets them directly must keep `code` in step
  -- (or this trigger removed). A code with no second part leaves receiver_id
  -- NULL rather than empty.
  if new.code is not null then
    new.payer_id := nullif(split_part(new.code, '_', 1), '');
    new.receiver_id := nullif(split_part(new.code, '_', 2), '');
  end if;
  return new;
end;
$$;

drop trigger if exists transactions_fill_ids on public.transactions;
create trigger transactions_fill_ids
  before insert or update of code on public.transactions
  for each row execute function public.transactions_fill_ids();

-- One-time backfill: only touches rows that have not been filled in yet.
update public.transactions
   set payer_id    = split_part(code, '_', 1),
       receiver_id = split_part(code, '_', 2)
 where payer_id is null or receiver_id is null;

create index if not exists transactions_game_payer_idx
  on public.transactions (game_id, payer_id, date desc, time desc);

create index if not exists transactions_game_receiver_idx
  on public.transactions (game_id, receiver_id, date desc, time desc);

-- 4.3 Known remaining cost ---------------------------------------------------
-- `transactions_game_code_idx` from section 1 becomes redundant once 4.2 is
-- applied and every client is on the indexed path; dropping it is optional.
