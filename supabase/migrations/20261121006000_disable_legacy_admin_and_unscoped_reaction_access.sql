-- These legacy tables are not used by the current client.
-- Keep their rows intact, but remove direct client access until a supported feature needs it.
drop policy if exists "Admin puede ver su registro" on public.admins;
revoke all privileges on table public.admins from anon, authenticated;

-- Reactions currently have no active client workflow. The previous INSERT policy
-- allowed reactions on any known public message ID without checking room access.
-- Disable direct client access until message-level access checks are implemented.
drop policy if exists chat_reactions_delete_own on public.chat_message_reactions;
drop policy if exists chat_reactions_insert_own on public.chat_message_reactions;
drop policy if exists chat_reactions_read on public.chat_message_reactions;
revoke all privileges on table public.chat_message_reactions from anon, authenticated;
