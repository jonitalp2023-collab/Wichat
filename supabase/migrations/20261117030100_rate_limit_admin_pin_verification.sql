create table if not exists public.wichat_admin_pin_attempts (
  user_id uuid not null,
  attempted_at timestamptz not null default now(),
  succeeded boolean not null default false
);
create index if not exists wichat_admin_pin_attempts_user_time_idx
  on public.wichat_admin_pin_attempts (user_id, attempted_at desc);
alter table public.wichat_admin_pin_attempts enable row level security;
revoke all on table public.wichat_admin_pin_attempts from anon, authenticated;

create or replace function public.verify_admin_pin(pin_input text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  crypto_schema text;
  saved_hash text;
  valid_pin boolean;
  current_user_id uuid := auth.uid();
  failed_attempts integer;
begin
  if current_user_id is null then
    return false;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(current_user_id::text, 0));
  delete from public.wichat_admin_pin_attempts
  where attempted_at < now() - interval '1 day';
  select count(*) into failed_attempts
  from public.wichat_admin_pin_attempts
  where user_id = current_user_id
    and succeeded = false
    and attempted_at > now() - interval '15 minutes';
  if failed_attempts >= 5 then
    return false;
  end if;
  select n.nspname into crypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';
  select pin_hash into saved_hash
  from public.wichat_admin_config
  where singleton = true;
  if saved_hash is null or crypto_schema is null then
    return false;
  end if;
  execute format('select %I.crypt($1, $2) = $2', crypto_schema)
  into valid_pin
  using coalesce(pin_input, ''), saved_hash;
  valid_pin := coalesce(valid_pin, false);
  insert into public.wichat_admin_pin_attempts(user_id, succeeded)
  values (current_user_id, valid_pin);
  if valid_pin then
    delete from public.wichat_admin_pin_attempts
    where user_id = current_user_id and succeeded = false;
    update public.wichat_admins
    set sender_id = current_user_id::text
    where nickname = 'UNIX' and active = true;
  end if;
  return valid_pin;
end;
$function$;
revoke all on function public.verify_admin_pin(text) from public, anon;
grant execute on function public.verify_admin_pin(text) to authenticated, service_role;
