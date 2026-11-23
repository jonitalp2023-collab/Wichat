-- Preservar el envío existente de stickers y GIF privados al habilitar audio.
drop policy if exists "Enviar mensajes privados propios" on public.private_messages;
create policy "Enviar mensajes privados propios"
on public.private_messages
for insert to authenticated
with check (
  (select auth.uid())=sender_id
  and (select private.has_active_account_session())
  and not (select private.is_chat_user_blocked(private_messages.sender_id,private_messages.recipient_id))
  and (select private.has_active_nickname_lease(private_messages.sender_nickname))
  and (select private.chat_message_content_allowed(private_messages.content))
  and (
    (message_type='text' and media_url is null)
    or (message_type=any(array['sticker','gif']::text[]) and media_url is not null)
    or (message_type='audio' and media_url is not null)
  )
);