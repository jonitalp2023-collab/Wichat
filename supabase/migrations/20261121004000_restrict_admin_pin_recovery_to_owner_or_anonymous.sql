-- Prevent a secondary admin from claiming the reserved UNIX owner identity
-- merely by knowing the global owner PIN. Only the active owner or a rate-limited
-- anonymous recovery session can verify the owner PIN.

create or replace function public.verify_admin_pin(pin_input text)
returns boolean
language plpgsql
security definer
set search_path to pg_catalog, public, pg_temp
as $function$
declare
  crypto_schema text;
  saved_hash text;
  valid_pin boolean;
  current_user_id uuid := auth.uid();
  is_anonymous_session boolean := false;
  is_current_owner boolean := false;
  failed_attempts integer;
begin
  if current_user_id is null then
    return false;
  end if;

  select coalesce(u.is_anonymous, false)
    into is_anonymous_session
  from auth.users u
  where u.id = current_user_id;

  select exists (
    select 1
    from public.wichat_admins a
    where a.sender_id = current_user_id::text
      and a.active = true
      and a.role = 'owner'
  ) into is_current_owner;

  if not is_current_owner and not is_anonymous_session then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('wichat-unix-admin-pin', 0));

  perform 1
  from public.wichat_admins a
  where upper(a.nickname) = 'UNIX' and a.active = true
  for update;

  if not found then
    return false;
  end if;

  delete from public.wichat_admin_pin_attempts
  where attempted_at < now() - interval '1 day';

  if is_anonymous_session and not is_current_owner then
    select count(*) into failed_attempts
    from public.wichat_admin_pin_attempts
    where succeeded = false
      and attempted_at > now() - interval '15 minutes';
  else
    select count(*) into failed_attempts
    from public.wichat_admin_pin_attempts
    where user_id = current_user_id
      and succeeded = false
      and attempted_at > now() - interval '15 minutes';
  end if;

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
    where upper(nickname) = 'UNIX' and active = true;
  end if;

  return valid_pin;
end;
$function$;
