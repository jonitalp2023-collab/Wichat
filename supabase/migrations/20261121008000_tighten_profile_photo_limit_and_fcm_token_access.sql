-- Profile images are capped at 3 MiB in the client; enforce the same limit in Storage.
update storage.buckets
set file_size_limit = 3145728,
    allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
where id = 'chat-profile-photos';

-- FCM tokens are registered only through send-chat-push after it validates
-- the caller's Supabase access token. The client has no direct table workflow.
drop policy if exists "Users manage their own push token" on public.chat_push_tokens;
revoke all privileges on table public.chat_push_tokens from anon, authenticated;
