-- Call rating system: per-call ratings + cached avg on profiles.
-- Run this in the Supabase SQL editor.

create table if not exists call_ratings (
  id           uuid primary key default gen_random_uuid(),
  room_id      text        not null,
  rater_id     uuid        not null references auth.users(id) on delete cascade,
  rated_id     uuid        not null references auth.users(id) on delete cascade,
  stars        int         not null check (stars between 1 and 5),
  created_at   timestamptz not null default now(),
  unique (room_id, rater_id)  -- one rating per call per user
);

create index if not exists call_ratings_rated_id_idx on call_ratings (rated_id);

alter table profiles
  add column if not exists avg_rating   numeric(3,2) default 0,
  add column if not exists rating_count int          default 0;

-- Recompute avg_rating + rating_count for a user from call_ratings.
create or replace function recompute_user_rating(uid uuid) returns void
language plpgsql
as $$
begin
  update profiles
     set avg_rating   = coalesce((select avg(stars)::numeric(3,2) from call_ratings where rated_id = uid), 0),
         rating_count = (select count(*) from call_ratings where rated_id = uid)
   where id = uid;
end;
$$;

-- Auto-update profiles.avg_rating whenever a rating row changes.
create or replace function trg_call_rating_update() returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'DELETE') then
    perform recompute_user_rating(old.rated_id);
    return old;
  end if;
  perform recompute_user_rating(new.rated_id);
  return new;
end;
$$;

drop trigger if exists call_ratings_after_write on call_ratings;
create trigger call_ratings_after_write
  after insert or update or delete on call_ratings
  for each row execute function trg_call_rating_update();
