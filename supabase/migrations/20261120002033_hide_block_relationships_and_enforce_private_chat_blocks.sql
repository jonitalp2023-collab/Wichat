create or replace function private.is_chat_user_blocked(first_user uuid, second_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.chat_user_blocks b
    where
      (b.blocker_id = first_user and b.blocked_id = second_user)
      or
      (b.blocker_id = second_user and b.blocked_id = first_user)
  );
$function$;

revoke all on function private.is_chat_user_blocked(uuid, uuid) from public, anon;
grant execute on function private.is_chat_user_blocked(uuid, uuid) to authenticated;

drop policy if exists chat_user_blocks_select_participants on public.chat_user_blocks;
create policy chat_user_blocks_select_own
  on public.chat_user_blocks
  for select
  to authenticated
  using (blocker_id = (select auth.uid()));

drop policy if exists "Leer mensajes privados propios" on public.private_messages;
create policy "Leer mensajes privados propios"
  on public.private_messages
  for select
  to authenticated
  using (
    (
      (select auth.uid()) = sender_id
      or (select auth.uid()) = recipient_id
    )
    and not private.is_chat_user_blocked(sender_id, recipient_id)
  );

drop policy if exists "Enviar mensajes privados propios" on public.private_messages;
create policy "Enviar mensajes privados propios"
  on public.private_messages
  for insert
  to authenticated
  with check (
    (select auth.uid()) = sender_id
    and not private.is_chat_user_blocked(sender_id, recipient_id)
  );
