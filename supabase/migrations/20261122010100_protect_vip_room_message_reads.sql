-- Apply the same registered-account and active-session requirements to VIP message reads.
create or replace function private.can_access_chat_room(room_id_input bigint)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select case
    when not exists (
      select 1 from public.rooms
      where id = room_id_input and is_vip = true
    ) then true
    when auth.uid() is null then false
    when coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, true) then false
    when not (select private.has_active_account_session()) then false
    when exists (
      select 1 from public.wichat_admins
      where sender_id = auth.uid()::text and active = true
    ) then true
    when exists (
      select 1 from public.chat_vip_members
      where user_id = auth.uid()
    ) then true
    else false
  end;
$function$;
