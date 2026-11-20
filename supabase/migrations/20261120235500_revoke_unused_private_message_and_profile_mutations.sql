-- The client only inserts and reads private messages. It has no edit/delete workflow.
-- Remove unused table privileges as defense in depth; RLS remains the access boundary.
revoke update, delete on table public.private_messages from anon, authenticated;

-- Account deletion is handled by the trusted delete-account Edge Function.
-- No client-side profile deletion is required.
revoke delete on table public.chat_profiles from anon, authenticated;
