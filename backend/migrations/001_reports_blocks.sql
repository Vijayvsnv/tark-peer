-- ── Reports ──────────────────────────────────────────────────────────────────
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id),
  reported_id uuid not null references public.profiles(id),
  room_id text,                          -- agora channel name if reported from a call, nullable
  reason text not null check (reason in ('abusive_language','harassment','not_speaking_english','spam_or_scam','inappropriate_content','other')),
  details text,                          -- optional free text, max enforced client-side
  created_at timestamptz not null default now(),
  constraint no_self_report check (reporter_id != reported_id)
);
create index reports_reported_idx on public.reports(reported_id, created_at desc);

alter table public.reports enable row level security;
create policy "users can insert own reports" on public.reports
  for insert with check (auth.uid() = reporter_id);
-- no select policy for regular users; only service role reads reports

-- ── Blocks ────────────────────────────────────────────────────────────────────
create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles(id),
  blocked_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id != blocked_id)
);
create index blocks_blocker_idx on public.blocks(blocker_id);
create index blocks_blocked_idx on public.blocks(blocked_id);

alter table public.blocks enable row level security;
create policy "users manage own blocks" on public.blocks
  for all using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);
create policy "users can see blocks against them is NOT allowed" on public.blocks
  for select using (auth.uid() = blocker_id);
