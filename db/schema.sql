-- Elbert sync schema. Idempotent: safe to re-run against an existing database.
--
-- Shared columns on every synced table:
--   id text primary key
--   updated_at bigint not null      -- client-assigned ms epoch, drives LWW conflict resolution
--   deleted_at bigint                -- ms epoch tombstone, null = not deleted
--   seq bigint not null default nextval('sync_seq')  -- server-assigned, drives cursor pull
--
-- sync_seq is a single global sequence shared by all 5 tables, so the sync
-- cursor is a simple monotonic integer across the whole dataset.

create sequence if not exists sync_seq;

create table if not exists decks (
  id text primary key,
  updated_at bigint not null,
  deleted_at bigint,
  seq bigint not null default nextval('sync_seq'),
  name text,
  parent_id text,
  new_per_day int,
  desired_retention double precision
);

create table if not exists notes (
  id text primary key,
  updated_at bigint not null,
  deleted_at bigint,
  seq bigint not null default nextval('sync_seq'),
  deck_id text,
  type text,
  fields jsonb,
  tags jsonb
);

create table if not exists cards (
  id text primary key,
  updated_at bigint not null,
  deleted_at bigint,
  seq bigint not null default nextval('sync_seq'),
  note_id text,
  ord int,
  due bigint,
  stability double precision,
  difficulty double precision,
  reps int,
  lapses int,
  state int,
  last_review bigint,
  suspended int,
  learning_steps int not null default 0
);

create table if not exists reviews (
  id text primary key,
  updated_at bigint not null,
  deleted_at bigint,
  seq bigint not null default nextval('sync_seq'),
  card_id text,
  ts bigint,
  rating int,
  elapsed_ms bigint,
  snapshot jsonb
);

create table if not exists media (
  id text primary key,
  updated_at bigint not null,
  deleted_at bigint,
  seq bigint not null default nextval('sync_seq'),
  hash text,
  data_base64 text,
  mime text
);

create index if not exists decks_seq_idx on decks (seq);
create index if not exists notes_seq_idx on notes (seq);
create index if not exists cards_seq_idx on cards (seq);
create index if not exists reviews_seq_idx on reviews (seq);
create index if not exists media_seq_idx on media (seq);

create or replace function bump_seq() returns trigger as $$
begin
  new.seq := nextval('sync_seq');
  return new;
end;
$$ language plpgsql;

drop trigger if exists decks_bump_seq on decks;
create trigger decks_bump_seq before insert or update on decks
  for each row execute function bump_seq();

drop trigger if exists notes_bump_seq on notes;
create trigger notes_bump_seq before insert or update on notes
  for each row execute function bump_seq();

drop trigger if exists cards_bump_seq on cards;
create trigger cards_bump_seq before insert or update on cards
  for each row execute function bump_seq();

drop trigger if exists reviews_bump_seq on reviews;
create trigger reviews_bump_seq before insert or update on reviews
  for each row execute function bump_seq();

drop trigger if exists media_bump_seq on media;
create trigger media_bump_seq before insert or update on media
  for each row execute function bump_seq();
