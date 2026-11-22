-- VIP rooms require a real registered account and an active account session.
-- Existing VIP membership rows grant access only to registered accounts.
create or replace function public.check_chat_access(sender_id_input text, room_id_input bigint)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  headers json;
  ip_text text;
  user_ip inet;
  sender_uuid uuid;
  active_admin boolean := false;
begin
  -- Never allow checking or changing another user's access.
  if auth.uid() is null or sender_id_input is distinct from auth.uid()::text then
    return false;
  end if;

  -- Anonymous/guest sessions are never eligible for VIP rooms.
  if exists (
    select 1 from public.rooms
    where id = room_id_input and is_vip = true
  ) then
    if coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, true) then
      return false;
    end if;

    -- A registered account must also hold a valid account session.
    if not (select private.has_active_account_session()) then
      return false;
    end if;
  end if;

  headers := coalesce(nullif(current_setting('request.headers', true), '')::json, '{}'::json);
  ip_text := nullif(trim(headers->>'cf-connecting-ip'), '');
  if ip_text is null then
    ip_text := nullif(trim(split_part(coalesce(headers->>'x-forwarded-for', ''), ',', 1)), '');
  end if;
  if ip_text is not null then
    begin
      user_ip := ip_text::inet;
    exception when others then
      user_ip := null;
    end;
  end if;

  if user_ip is not null then
    insert into public.wichat_user_ips(sender_id, client_ip, updated_at)
    values(sender_id_input, user_ip, now())
    on conflict(sender_id) do update
      set client_ip=excluded.client_ip, updated_at=now();
  else
    select client_ip into user_ip
    from public.wichat_user_ips
    where sender_id=sender_id_input;
  end if;

  if exists (
    select 1 from public.wichat_bans
    where sender_id=sender_id_input and (expires_at is null or expires_at>now())
  ) then return false; end if;

  if exists (
    select 1 from public.wichat_room_bans
    where sender_id=sender_id_input and room_id=room_id_input and expires_at>now()
  ) then return false; end if;

  if user_ip is not null and exists (
    select 1 from public.wichat_ip_bans
    where client_ip=user_ip and room_id=room_id_input and expires_at>now()
  ) then return false; end if;

  if exists (select 1 from public.rooms where id=room_id_input and is_vip=true) then
    sender_uuid := auth.uid();
    select exists (
      select 1 from public.wichat_admins
      where sender_id=sender_uuid::text and active=true
    ) into active_admin;

    if active_admin then return true; end if;
    if not exists (
      select 1 from public.chat_vip_members
      where user_id=sender_uuid
    ) then return false; end if;
  end if;

  return true;
end;
$function$;

revoke execute on function public.check_chat_access(text, bigint) from public, anon;
grant execute on function public.check_chat_access(text, bigint) to authenticated;
