create or replace function public.wichat_release_account_session(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_auth_session_id uuid;
begin
  if v_uid is null then return false; end if;
  begin
    v_auth_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if v_auth_session_id is null then return false; end if;

  delete from public.wichat_account_sessions
  where user_id = v_uid
    and device_id = p_device_id
    and auth_session_id = v_auth_session_id;

  return found;
end;
$function$;

revoke all on function public.wichat_release_account_session(text) from public, anon;
grant execute on function public.wichat_release_account_session(text) to authenticated, service_role;
