-- Spendwell: savings goals and bill splits (who owes you).
-- Same protection as the first update: each row belongs to one user and
-- row-level security lets them see and change only their own rows.

create table public.goals (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 40),
  target_paise  bigint not null check (target_paise > 0 and target_paise <= 100000000000),
  saved_paise   bigint not null default 0 check (saved_paise >= 0 and saved_paise <= 100000000000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index goals_user_idx on public.goals (user_id);

create table public.splits (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  person        text not null check (char_length(person) between 1 and 40),
  amount_paise  bigint not null check (amount_paise > 0 and amount_paise <= 100000000000),
  note          text check (char_length(note) <= 80),
  settled_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index splits_user_idx on public.splits (user_id, created_at desc);

create trigger goals_touch before update on public.goals
  for each row execute function public.touch_updated_at();

alter table public.goals  enable row level security;
alter table public.splits enable row level security;

create policy "goals: read own"   on public.goals for select using (user_id = auth.uid());
create policy "goals: create own" on public.goals for insert with check (user_id = auth.uid());
create policy "goals: update own" on public.goals for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "goals: delete own" on public.goals for delete using (user_id = auth.uid());

create policy "splits: read own"   on public.splits for select using (user_id = auth.uid());
create policy "splits: create own" on public.splits for insert with check (user_id = auth.uid());
create policy "splits: update own" on public.splits for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "splits: delete own" on public.splits for delete using (user_id = auth.uid());
