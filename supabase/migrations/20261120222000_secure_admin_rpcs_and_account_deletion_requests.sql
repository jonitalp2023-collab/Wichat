create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  nickname text not null check (char_length(nickname) between 2 and 25),
  contact_email text not null check (char_length(contact_email) <= 254),
  account_type text not null check (account_type in ('registered','guest')),
  details text not null default '' check (char_length(details) <= 500),
  status text not null default 'pending' check (status in ('pending','verified','completed','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  resolution_note text
);

create index if not exists account_deletion_requests_email_created_idx
  on public.account_deletion_requests (lower(contact_email), created_at desc);
create index if not exists account_deletion_requests_status_created_idx
  on public.account_deletion_requests (status, created_at desc);

alter table public.account_deletion_requests enable row level security;
revoke all on table public.account_deletion_requests from public, anon, authenticated;
grant all on table public.account_deletion_requests to service_role;

-- RLS tables without policies are server-only: remove all direct API grants.
do $$
declare item record;
begin
  for item in
    select n.nspname, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relrowsecurity
      and not exists (
        select 1 from pg_policies p
        where p.schemaname = n.nspname and p.tablename = c.relname
      )
  loop
    execute format('revoke all privileges on table %I.%I from public, anon, authenticated', item.nspname, item.relname);
    execute format('grant all privileges on table %I.%I to service_role', item.nspname, item.relname);
  end loop;
end $$;

-- Keep only the four RPCs still called with an authenticated admin JWT.
do $$
declare item record;
begin
  for item in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'admin\_%' escape '\'
      and not (
        p.proname in ('admin_set_room_topic','admin_set_room_vip','admin_set_vip_member')
        or (p.proname = 'admin_moderate_user' and p.pronargs = 7)
      )
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', item.signature);
    execute format('grant execute on function %s to service_role', item.signature);
  end loop;
end $$;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
