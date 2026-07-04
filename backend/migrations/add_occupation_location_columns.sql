-- Adds occupation / sector / country / state to profiles table.
-- Run this in the Supabase SQL editor.

alter table profiles
  add column if not exists occupation    text,
  add column if not exists sector        text,
  add column if not exists country       text,
  add column if not exists state         text,
  add column if not exists mother_tongue text;

-- Helpful for "which state / country do most users come from" analytics.
create index if not exists profiles_country_state_idx on profiles (country, state);
create index if not exists profiles_sector_idx        on profiles (sector);
create index if not exists profiles_mother_tongue_idx on profiles (mother_tongue);
