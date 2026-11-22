-- Bloquear enlaces también en el servidor y aplicar las mismas reglas a mensajes privados.
-- Los administradores activos conservan el bypass de moderación existente.

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
        and coalesce(message_text, '') !~* '(^|[^[:alnum:]_])((https?://|www[.])[^[:space:]]+|([[:alnum:]-]+[.])+[[:alpha:]]{2,63}([/:?#][^[:space:]]*)?)'
      )
    );
$function$;

revoke all on function private.chat_message_content_allowed(text) from public, anon;
grant execute on function private.chat_message_content_allowed(text) to authenticated;

drop policy if exists "Enviar mensajes privados propios" on public.private_messages;
create policy "Enviar mensajes privados propios" on public.private_messages
for insert to authenticated
with check (
  (select auth.uid()) = sender_id
  and (select private.has_active_account_session())
  and not (select private.is_chat_user_blocked(sender_id, recipient_id))
  and (select private.has_active_nickname_lease(sender_nickname))
  and (select private.chat_message_content_allowed(content))
);
