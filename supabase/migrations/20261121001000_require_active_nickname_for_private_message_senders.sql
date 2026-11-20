-- Private messages must use the authenticated sender's currently leased nickname.
-- This prevents clients from spoofing another user's display name in DMs.

drop policy if exists "Enviar mensajes privados propios" on public.private_messages;

create policy "Enviar mensajes privados propios"
  on public.private_messages
  for insert
  to authenticated
  with check (
    (select auth.uid()) = sender_id
    and not private.is_chat_user_blocked(sender_id, recipient_id)
    and (select private.has_active_nickname_lease(sender_nickname))
  );
