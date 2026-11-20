create table public.chat_user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint chat_user_blocks_pkey primary key (blocker_id, blocked_id),
  constraint chat_user_blocks_no_self check (blocker_id <> blocked_id)
);

create index chat_user_blocks_blocked_id_idx
  on public.chat_user_blocks (blocked_id);

alter table public.chat_user_blocks enable row level security;

revoke all on table public.chat_user_blocks from anon;
grant select, insert, delete on table public.chat_user_blocks to authenticated;

create policy chat_user_blocks_select_participants
  on public.chat_user_blocks
  for select
  to authenticated
  using (
    blocker_id = (select auth.uid())
    or blocked_id = (select auth.uid())
  );

create policy chat_user_blocks_insert_own
  on public.chat_user_blocks
  for insert
  to authenticated
  with check (
    blocker_id = (select auth.uid())
    and blocked_id <> (select auth.uid())
  );

create policy chat_user_blocks_delete_own
  on public.chat_user_blocks
  for delete
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
    and not exists (
      select 1
      from public.chat_user_blocks b
      where
        (b.blocker_id = private_messages.sender_id and b.blocked_id = private_messages.recipient_id)
        or
        (b.blocker_id = private_messages.recipient_id and b.blocked_id = private_messages.sender_id)
    )
  );

drop policy if exists "Enviar mensajes privados propios" on public.private_messages;
create policy "Enviar mensajes privados propios"
  on public.private_messages
  for insert
  to authenticated
  with check (
    (select auth.uid()) = sender_id
    and not exists (
      select 1
      from public.chat_user_blocks b
      where
        (b.blocker_id = private_messages.sender_id and b.blocked_id = private_messages.recipient_id)
        or
        (b.blocker_id = private_messages.recipient_id and b.blocked_id = private_messages.sender_id)
    )
  );
