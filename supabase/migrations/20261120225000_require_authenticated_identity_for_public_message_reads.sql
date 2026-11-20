-- Require a concrete Supabase identity before reading public room messages.
-- This is defense in depth alongside the per-user block check.

drop policy if exists messages_select_room_access on public.messages;

create policy messages_select_room_access
  on public.messages
  for select
  to authenticated
  using (
    (select auth.uid()) is not null
    and (select private.can_access_chat_room(messages.room_id))
    and case
      when messages.sender_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then not private.is_chat_user_blocked((select auth.uid()), messages.sender_id::uuid)
      else true
    end
  );
