-- Require a valid sender identity, room access (including bans/IP/VIP checks),
-- and an active nickname lease for every client-originated public message.
-- This closes the direct-table-insert path used by the WebView client.

drop policy if exists messages_insert_room_access on public.messages;

create policy messages_insert_room_access
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())::text
    and (select public.check_chat_access(sender_id, room_id))
    and exists (
      select 1
      from public.wichat_nicknames n
      where n.sender_id = (select auth.uid())::text
        and n.nickname_norm = lower(btrim(messages.nickname))
        and n.expires_at > now()
    )
  );
