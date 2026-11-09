\set ON_ERROR_STOP 1
insert into auth.users values ('11111111-1111-1111-1111-111111111111','a@x'), ('22222222-2222-2222-2222-222222222222','b@x');
do $$ begin assert (select count(*) from public.profiles) = 2, 'profiles auto-created'; raise notice 'PASS profiles created on sign-up'; end $$;
select id as dining from public.categories where key = 'dining' \gset

-- User A
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into public.transactions (amount_paise, category_id, note) values (25000, :'dining', 'Lunch');
insert into public.categories (user_id, name) values (auth.uid(), 'Gifts') returning id as gifts \gset
insert into public.transactions (amount_paise, category_id) values (99900, :'gifts');
insert into public.budgets (category_id, limit_paise) values (:'gifts', 200000);
do $$ begin assert (select count(*) from public.transactions) = 2; assert (select count(*) from public.categories) = 14; raise notice 'PASS user A sees own data + built-ins'; end $$;

-- User B
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
do $$ begin
  assert (select count(*) from public.transactions) = 0, 'B must not see A transactions';
  assert (select count(*) from public.categories where user_id is not null) = 0, 'B must not see A categories';
  assert (select count(*) from public.budgets) = 0, 'B must not see A budgets';
  raise notice 'PASS user B cannot read user A data';
end $$;
do $$ begin
  begin
    insert into public.transactions (amount_paise, category_id) values (100, (select id from public.categories where key='dining'));
    raise notice 'PASS user B can add own expense';
  end;
end $$;
\set ON_ERROR_STOP 0
\echo '--- the next statements must FAIL ---'
insert into public.transactions (amount_paise, category_id) values (100, :'gifts');
insert into public.transactions (user_id, amount_paise, category_id) values ('11111111-1111-1111-1111-111111111111', 100, :'dining');
update public.profiles set plan = 'pro' where id = auth.uid();
insert into public.categories (user_id, name, key) values (auth.uid(), 'Hack', 'hack');
insert into public.transactions (amount_paise, category_id) values (0, :'dining');
\echo '--- end of must-fail ---'
\set ON_ERROR_STOP 1
update public.profiles set monthly_income_paise = 6500000 where id = auth.uid();
do $$ begin
  assert (select monthly_income_paise from public.profiles) = 6500000;
  assert (select count(*) from public.profiles) = 1, 'B sees only own profile';
  raise notice 'PASS user B edits income, sees only own profile';
end $$;
update public.transactions set amount_paise = 1 where user_id = '11111111-1111-1111-1111-111111111111';
reset role;
do $$ begin assert (select count(*) from public.transactions where amount_paise = 1) = 0, 'B must not edit A rows'; raise notice 'PASS user B cannot edit user A rows'; end $$;
