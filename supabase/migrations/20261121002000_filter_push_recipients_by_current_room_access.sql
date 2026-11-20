-- Filter push recipients against current room access before using the service role
-- to deliver notifications. This prevents stale subscriptions from bypassing bans/VIP rules.

create or replace function public.filter_chat_push_recipients(
  recipient_ids_input uuid[],
  room_id_input bigint
)
returns uuid[]
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(array_agg(candidate.user_id), array[]::uuid[])
  from unnest(coalesce(recipient_ids_input, array[]::uuid[])) as candidate(user_id)
  join public.rooms r on r.id = room_id_input
  where not exists (
    select 1 from public.wichat_bans b
    where b.sender_id = candidate.user_id::text
      and (b.expires_at is null or b.expires_at > now())
  )
  and not exists (
    select 1 from public.wichat_room_bans rb
    where rb.sender_id = candidate.user_id::text
      and rb.room_id = room_id_input
      and rb.expires_at > now()
  )
  and not exists (
    select 1
    from public.wichat_user_ips ui
    join public.wichat_ip_bans ib on ib.client_ip = ui.client_ip
    where ui.sender_id = candidate.user_id::text
      and ib.room_id = room_id_input
      and ib.expires_at > now()
  )
  and (
    coalesce(r.is_vip, false) = false
    or exists (
      select 1 from public.wichat_admins a
      where a.sender_id = candidate.user_id::text and a.active is true
    )
    or exists (
      select 1 from public.chat_vip_members vm
      where vm.user_id = candidate.user_id
    )
  );
$function$;

revoke all on function public.filter_chat_push_recipients(uuid[], bigint) from public, anon, authenticated;
grant execute on function public.filter_chat_push_recipients(uuid[], bigint) to service_role;
