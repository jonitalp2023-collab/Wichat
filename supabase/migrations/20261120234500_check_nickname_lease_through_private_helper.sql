-- Keep nickname lease storage private while allowing the messages INSERT policy
-- to validate the authenticated user's active lease without exposing the table.

create or replace function private.has_active_nickname_lease(nickname_input text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select (select auth.uid()) is not null
     and exists (
       select 1
       from public.wichat_nicknames n
       where n.sender_id = (select auth.uid())::text
         and n.nickname_norm = lower(btrim(coalesce(nickname_input,'')))
         and n.expires_at > now()
     );
$function$;

revoke execute on function private.has_active_nickname_lease(text) from public, anon;
grant execute on function private.has_active_nickname_lease(text) to authenticated;

drop policy if exists messages_insert_room_access on public.messages;

create policy messages_insert_room_access
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())::text
    and (select public.check_chat_access(sender_id, room_id))
    and (select private.has_active_nickname_lease(nickname))
  );
