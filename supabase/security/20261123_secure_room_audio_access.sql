-- Revalidar bans, IP y acceso VIP al subir o firmar la reproducción de audios de sala.
drop policy if exists "Users upload audio to accessible rooms" on storage.objects;
create policy "Users upload audio to accessible rooms"
on storage.objects for insert to authenticated
with check (
  bucket_id='chat-room-audio'
  and (select private.has_active_account_session())
  and name ~ '^[0-9]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$'
  and (storage.foldername(name))[2]=(select auth.uid())::text
  and (select public.check_chat_access((select auth.uid())::text,((storage.foldername(name))[1])::bigint))
);

drop policy if exists "Users read audio in accessible rooms" on storage.objects;
create policy "Users read audio in accessible rooms"
on storage.objects for select to authenticated
using (
  bucket_id='chat-room-audio'
  and (select private.has_active_account_session())
  and name ~ '^[0-9]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$'
  and (select public.check_chat_access((select auth.uid())::text,((storage.foldername(name))[1])::bigint))
  and not (select private.is_chat_user_blocked(((storage.foldername(name))[2])::uuid,(select auth.uid())))
);