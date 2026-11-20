create or replace function private.chat_message_content_allowed(message_text text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    auth.uid() is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(message_text, ''))) between 1 and 1000
    and (
      exists (
        select 1
        from public.wichat_admins wa
        where wa.sender_id = auth.uid()::text
          and wa.active = true
      )
      or not (
        message_text ~* '(^|[^[:alnum:]_])(puta|puto|mierda|mierdas|forro|pelotudo|pelotuda|conchudo|conchuda|concha|verga|pija|cag[oó]n|hdp|h[.]?d[.]?p[.]?|hijo de puta|hija de puta)([^[:alnum:]_]|$)'
      )
    );
$function$;

revoke all on function private.chat_message_content_allowed(text) from public, anon;
grant execute on function private.chat_message_content_allowed(text) to authenticated;

drop policy if exists messages_insert_room_access on public.messages;
create policy messages_insert_room_access
on public.messages
for insert
to authenticated
with check (
  sender_id = (select auth.uid())::text
  and (select public.check_chat_access(messages.sender_id, messages.room_id))
  and (select private.has_active_nickname_lease(messages.nickname))
  and (select private.chat_message_content_allowed(messages.message))
  and message_type = 'text'
  and media_url is null
  and content is null
);

-- This legacy RPC is not used by the current app. It can bypass the current
-- insert policy's checks through SECURITY DEFINER, so disable client execution.
revoke all on function public.wichat_send_message(text, text, bigint, text, text)
from public, anon, authenticated;
