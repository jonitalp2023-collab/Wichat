-- Add covering indexes for foreign keys used by chat history, reports and moderation.
create index if not exists chat_bot_requests_room_id_idx
  on public.chat_bot_requests (room_id);
create index if not exists chat_scheduled_announcements_room_id_idx
  on public.chat_scheduled_announcements (room_id);
create index if not exists chat_user_reports_reporter_id_idx
  on public.chat_user_reports (reporter_id);
create index if not exists chat_user_reports_reviewed_by_idx
  on public.chat_user_reports (reviewed_by);
create index if not exists chat_user_reports_room_id_idx
  on public.chat_user_reports (room_id);
create index if not exists private_messages_sender_recipient_created_idx
  on public.private_messages (sender_id, recipient_id, created_at);
create index if not exists private_messages_recipient_sender_created_idx
  on public.private_messages (recipient_id, sender_id, created_at);
create index if not exists wichat_bans_room_id_idx
  on public.wichat_bans (room_id);
create index if not exists wichat_kicks_room_id_idx
  on public.wichat_kicks (room_id);
create index if not exists wichat_room_bans_room_id_idx
  on public.wichat_room_bans (room_id);

-- Give the PIN-attempt audit log a stable primary key.
alter table public.wichat_admin_pin_attempts
  add column id bigint generated always as identity;
alter table public.wichat_admin_pin_attempts
  add constraint wichat_admin_pin_attempts_pkey primary key (id);

-- Remove a redundant duplicate of the sender_id primary-key index.
drop index if exists public.wichat_admins_sender_id_uidx;

-- Consolidate identical legacy admin policies and cache auth lookups once per query.
drop policy if exists "Consultar administradores" on public.admins;
drop policy if exists "Admin puede ver su registro" on public.admins;
create policy "Admin puede ver su registro"
  on public.admins
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users read own moderation events" on public.wichat_moderation_events;
create policy "Users read own moderation events"
  on public.wichat_moderation_events
  for select
  to authenticated
  using (sender_id = (select auth.uid())::text);

drop policy if exists chat_reactions_delete_own on public.chat_message_reactions;
create policy chat_reactions_delete_own
  on public.chat_message_reactions
  for delete
  to authenticated
  using ((select auth.uid()) is not null and user_id = (select auth.uid()));

drop policy if exists chat_reactions_insert_own on public.chat_message_reactions;
create policy chat_reactions_insert_own
  on public.chat_message_reactions
  for insert
  to authenticated
  with check (
    (select auth.uid()) is not null
    and user_id = (select auth.uid())
    and (
      message_id is not null
      or (
        private_message_id is not null
        and exists (
          select 1
          from public.private_messages pm
          where pm.id = chat_message_reactions.private_message_id
            and (pm.sender_id = (select auth.uid()) or pm.recipient_id = (select auth.uid()))
        )
      )
    )
  );

drop policy if exists chat_reactions_read on public.chat_message_reactions;
create policy chat_reactions_read
  on public.chat_message_reactions
  for select
  to authenticated
  using (
    (select auth.uid()) is not null
    and (
      message_id is not null
      or (
        private_message_id is not null
        and exists (
          select 1
          from public.private_messages pm
          where pm.id = chat_message_reactions.private_message_id
            and (pm.sender_id = (select auth.uid()) or pm.recipient_id = (select auth.uid()))
        )
      )
    )
  );

drop policy if exists chat_points_read_authenticated on public.chat_points_ledger;
create policy chat_points_read_authenticated
  on public.chat_points_ledger
  for select
  to authenticated
  using ((select auth.uid()) is not null);

drop policy if exists chat_vip_members_read_own on public.chat_vip_members;
create policy chat_vip_members_read_own
  on public.chat_vip_members
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists chat_user_reports_insert_own on public.chat_user_reports;
create policy chat_user_reports_insert_own
  on public.chat_user_reports
  for insert
  to authenticated
  with check (
    reporter_id = (select auth.uid())
    and target_user_id <> (select auth.uid())
  );

drop policy if exists "Crear perfil propio" on public.chat_profiles;
create policy "Crear perfil propio"
  on public.chat_profiles
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and is_registered = (
      coalesce((((select auth.jwt()) ->> 'is_anonymous'))::boolean, true) = false
    )
  );

drop policy if exists "Actualizar perfil propio" on public.chat_profiles;
create policy "Actualizar perfil propio"
  on public.chat_profiles
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and is_registered = (
      coalesce((((select auth.jwt()) ->> 'is_anonymous'))::boolean, true) = false
    )
  );
