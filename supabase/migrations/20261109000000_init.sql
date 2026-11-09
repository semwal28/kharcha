-- Kharcha: initial schema
-- Every user-owned row carries user_id and is protected by row-level security,
-- so a signed-in user can only ever read or change their own data.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Profiles (one per auth user, created automatically on sign-up)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  display_name          text,
  monthly_income_paise  bigint not null default 0 check (monthly_income_paise >= 0),
  currency              text   not null default 'INR',
  plan                  text   not null default 'free' check (plan in ('free', 'pro', 'family')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Categories
--   Built-in categories have user_id = null and a stable `key` (e.g. 'dining').
--   Custom categories ("Other" -> "Gifts") belong to one user.
-- ---------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users (id) on delete cascade,
  key         text unique,
  name        text not null check (char_length(name) between 1 and 30),
  icon        text not null default 'tag',
  is_fixed    boolean not null default false,  -- rent, bills, subscriptions
  sort_order  int not null default 100,
  created_at  timestamptz not null default now(),
  check ((user_id is null) = (key is not null))  -- built-ins have a key, custom ones do not
);
create unique index categories_user_name_uniq on public.categories (user_id, lower(name)) where user_id is not null;

insert into public.categories (key, name, icon, is_fixed, sort_order) values
  ('dining',    'Dining & cafés',    'dining',    false, 10),
  ('delivery',  'Food delivery',     'delivery',  false, 20),
  ('groceries', 'Groceries',         'groceries', false, 30),
  ('transport', 'Transport',         'transport', false, 40),
  ('shopping',  'Shopping',          'shopping',  false, 50),
  ('bills',     'Bills & utilities', 'bills',     true,  60),
  ('fun',       'Entertainment',     'fun',       false, 70),
  ('health',    'Health & fitness',  'health',    false, 80),
  ('care',      'Personal care',     'care',      false, 90),
  ('subs',      'Subscriptions',     'subs',      true,  100),
  ('rent',      'Rent',              'rent',      true,  110),
  ('fees',      'Fees & charges',    'fees',      false, 120),
  ('other',     'Other',             'other',     false, 999);

-- ---------------------------------------------------------------------------
-- Transactions (expenses). Money is stored in paise (1 rupee = 100 paise).
-- ---------------------------------------------------------------------------
create table public.transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  amount_paise  bigint not null check (amount_paise > 0 and amount_paise <= 100000000000),
  category_id   uuid not null references public.categories (id),
  note          text check (char_length(note) <= 80),
  merchant      text check (char_length(merchant) <= 80),
  pay_method    text not null default 'UPI' check (pay_method in ('UPI', 'Card', 'Cash', 'Other')),
  spent_at      timestamptz not null default now(),
  is_recurring  boolean not null default false,
  source        text not null default 'manual' check (source in ('manual', 'quick_add', 'import')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index transactions_user_spent_idx on public.transactions (user_id, spent_at desc);

-- ---------------------------------------------------------------------------
-- Budgets: one monthly limit per user per category
-- ---------------------------------------------------------------------------
create table public.budgets (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id  uuid not null references public.categories (id) on delete cascade,
  limit_paise  bigint not null check (limit_paise >= 0),
  updated_at   timestamptz not null default now(),
  primary key (user_id, category_id)
);

-- ---------------------------------------------------------------------------
-- AI usage log, used by the ai-coach function to enforce daily limits per plan
-- ---------------------------------------------------------------------------
create table public.ai_requests (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  kind        text not null check (kind in ('plan', 'chat')),
  created_at  timestamptz not null default now()
);
create index ai_requests_user_time_idx on public.ai_requests (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Keep updated_at fresh
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger transactions_touch before update on public.transactions
  for each row execute function public.touch_updated_at();
create trigger budgets_touch before update on public.budgets
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Create a profile when someone signs up
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- A transaction or budget may only point at a built-in category or one of
-- the user's own custom categories.
-- ---------------------------------------------------------------------------
create or replace function public.category_is_usable(cat uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.categories c
    where c.id = cat and (c.user_id is null or c.user_id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.categories   enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets      enable row level security;
alter table public.ai_requests  enable row level security;

create policy "own profile: read"   on public.profiles for select using (id = auth.uid());
create policy "own profile: update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "categories: read built-in and own" on public.categories for select
  using (user_id is null or user_id = auth.uid());
create policy "categories: create own" on public.categories for insert
  with check (user_id = auth.uid() and key is null);
create policy "categories: rename own" on public.categories for update
  using (user_id = auth.uid()) with check (user_id = auth.uid() and key is null);
create policy "categories: delete own" on public.categories for delete
  using (user_id = auth.uid());

create policy "transactions: read own"   on public.transactions for select using (user_id = auth.uid());
create policy "transactions: create own" on public.transactions for insert
  with check (user_id = auth.uid() and public.category_is_usable(category_id));
create policy "transactions: update own" on public.transactions for update
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.category_is_usable(category_id));
create policy "transactions: delete own" on public.transactions for delete using (user_id = auth.uid());

create policy "budgets: read own"   on public.budgets for select using (user_id = auth.uid());
create policy "budgets: create own" on public.budgets for insert
  with check (user_id = auth.uid() and public.category_is_usable(category_id));
create policy "budgets: update own" on public.budgets for update
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.category_is_usable(category_id));
create policy "budgets: delete own" on public.budgets for delete using (user_id = auth.uid());

-- ai_requests is written and read only by the ai-coach function (service role).
-- Users may see their own usage count.
create policy "ai usage: read own" on public.ai_requests for select using (user_id = auth.uid());

-- Users may edit their name, income and currency, but never their plan;
-- only the service role (billing) changes plan.
revoke update on public.profiles from anon, authenticated;
grant update (display_name, monthly_income_paise, currency) on public.profiles to authenticated;
