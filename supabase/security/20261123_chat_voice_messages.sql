-- ChatArgentina: mensajes de voz en salas y conversaciones privadas.
-- Esta migración fue aplicada al proyecto Supabase pqnnzkqxkndzelsbtxvv.

begin;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-room-audio', 'chat-room-audio', false, 2097152, array['audio/webm','audio/ogg','audio/mp4','audio/aac'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-private-audio', 'chat-private-audio', false, 2097152, array['audio/webm','audio/ogg','audio/mp4','audio/aac'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

alter table public.messages drop constraint if exists messages_media_type_check;
alter table public.messages add constraint messages_media_type_check check (message_type = any (array['text','sticker','gif','audio']::text[]));
alter table public.messages drop constraint if exists messages_media_url_check;
alter table public.messages add constraint messages_media_url_check check (
 (message_type='text' and media_url is null)
 or (message_type=any(array['sticker','gif']::text[]) and media_url is not null and char_length(media_url)<=2048 and media_url ~* '^https://')
 or (message_type='audio' and media_url is not null and char_length(media_url)<=512 and media_url ~ '^[0-9]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$' and content is null)
);
alter table public.private_messages drop constraint if exists private_messages_media_type_check;
alter table public.private_messages add constraint private_messages_media_type_check check (message_type = any (array['text','sticker','gif','audio']::text[]));
alter table public.private_messages drop constraint if exists private_messages_media_url_check;
alter table public.private_messages add constraint private_messages_media_url_check check (
 (message_type='text' and media_url is null)
 or (message_type=any(array['sticker','gif']::text[]) and media_url is not null and char_length(media_url)<=2048 and media_url ~* '^https://')
 or (message_type='audio' and media_url is not null and char_length(media_url)<=512 and media_url ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$')
);

drop policy if exists messages_insert_room_access on public.messages;
create policy messages_insert_room_access on public.messages for insert to authenticated with check (
 sender_id=(select auth.uid())::text
 and (select private.has_active_account_session())
 and (select public.check_chat_access(messages.sender_id,messages.room_id))
 and (select private.has_active_nickname_lease(messages.nickname))
 and (select private.chat_message_content_allowed(messages.message))
 and ((message_type='text' and media_url is null and content is null) or (message_type='audio' and media_url is not null and content is null))
);
drop policy if exists "Enviar mensajes privados propios" on public.private_messages;
create policy "Enviar mensajes privados propios" on public.private_messages for insert to authenticated with check (
 (select auth.uid())=sender_id
 and (select private.has_active_account_session())
 and not (select private.is_chat_user_blocked(private_messages.sender_id,private_messages.recipient_id))
 and (select private.has_active_nickname_lease(private_messages.sender_nickname))
 and (select private.chat_message_content_allowed(private_messages.content))
 and ((message_type='text' and media_url is null) or (message_type='audio' and media_url is not null))
);

drop policy if exists "Users upload audio to accessible rooms" on storage.objects;
create policy "Users upload audio to accessible rooms" on storage.objects for insert to authenticated with check (
 bucket_id='chat-room-audio' and (select private.has_active_account_session())
 and name ~ '^[0-9]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$'
 and (storage.foldername(name))[2]=(select auth.uid())::text
 and (select private.can_access_chat_room(((storage.foldername(name))[1])::bigint))
);
drop policy if exists "Users read audio in accessible rooms" on storage.objects;
create policy "Users read audio in accessible rooms" on storage.objects for select to authenticated using (
 bucket_id='chat-room-audio' and (select private.has_active_account_session())
 and name ~ '^[0-9]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$'
 and (select private.can_access_chat_room(((storage.foldername(name))[1])::bigint))
 and not (select private.is_chat_user_blocked(((storage.foldername(name))[2])::uuid,(select auth.uid())))
);
drop policy if exists "Users upload own private chat audio" on storage.objects;
create policy "Users upload own private chat audio" on storage.objects for insert to authenticated with check (
 bucket_id='chat-private-audio' and (select private.has_active_account_session())
 and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and (storage.foldername(name))[2]<>(select auth.uid())::text
 and not (select private.is_chat_user_blocked(((storage.foldername(name))[1])::uuid,((storage.foldername(name))[2])::uuid))
);
drop policy if exists "Participants read private chat audio" on storage.objects;
create policy "Participants read private chat audio" on storage.objects for select to authenticated using (
 bucket_id='chat-private-audio' and (select private.has_active_account_session())
 and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|ogg|m4a)$'
 and ((storage.foldername(name))[1]=(select auth.uid())::text or (storage.foldername(name))[2]=(select auth.uid())::text)
 and not (select private.is_chat_user_blocked(((storage.foldername(name))[1])::uuid,((storage.foldername(name))[2])::uuid))
);
commit;
