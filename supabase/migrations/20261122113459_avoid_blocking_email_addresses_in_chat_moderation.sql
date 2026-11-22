-- Avoid treating email addresses as web links in the moderation filter.
create or replace function private.chat_message_content_allowed(message_text text)
returns boolean language sql stable security definer set search_path = ''
as $function$
  select auth.uid() is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(message_text, ''))) between 1 and 1000
    and (
      exists (select 1 from public.wichat_admins wa
              where wa.sender_id = auth.uid()::text and wa.active = true)
      or (
        not public.wichat_contains_insult(message_text)
        and coalesce(message_text, '') !~* '(^|[^[:alnum:]_@])((https?://|www[.])[^[:space:]]+|([[:alnum:]-]+[.])+[[:alpha:]]{2,63}([/:?#][^[:space:]]*)?)'
      )
    );
$function$;

revoke all on function private.chat_message_content_allowed(text) from public, anon;
grant execute on function private.chat_message_content_allowed(text) to authenticated;
