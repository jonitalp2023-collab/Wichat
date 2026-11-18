
-- WiChat: role-based administration.
-- UNIX is the immutable owner role; assigned admins can moderate but cannot
-- manage rooms, bots, settings, or appoint/remove other administrators.

ALTER TABLE public.wichat_admins
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'admin';

UPDATE public.wichat_admins
SET role = CASE WHEN upper(nickname) = 'UNIX' THEN 'owner' ELSE 'admin' END;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.wichat_admins'::regclass
      AND conname = 'wichat_admins_role_check'
  ) THEN
    ALTER TABLE public.wichat_admins
      ADD CONSTRAINT wichat_admins_role_check CHECK (role IN ('owner','admin'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS wichat_admins_sender_id_uidx
  ON public.wichat_admins(sender_id);

CREATE OR REPLACE FUNCTION public.admin_moderate_user(
  pin_input text,
  target_sender_id text,
  room_id_input bigint,
  action_name text,
  reason_input text,
  duration_minutes_input integer,
  moderator_id_input uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  target_nickname text;
  expiry timestamptz;
  selected_action text;
  target_ip inet;
  moderation_reason text;
  prior_sanctions integer;
  applied_minutes integer;
  moderator_role text;
begin
  select role into moderator_role
  from public.wichat_admins
  where sender_id = moderator_id_input::text and active = true;

  if moderator_role is null then
    raise exception 'La cuenta no tiene permisos administrativos activos';
  end if;

  if moderator_role = 'owner' then
    if not public.verify_admin_pin(pin_input) then
      raise exception 'PIN incorrecto';
    end if;
  elsif moderator_role <> 'admin' then
    raise exception 'Permiso administrativo insuficiente';
  end if;

  if target_sender_id is null or trim(target_sender_id) = '' then
    raise exception 'Usuario no válido';
  end if;
  if public.is_wichat_admin(target_sender_id) then
    raise exception 'No se puede expulsar ni banear a un administrador';
  end if;
  if not exists(select 1 from public.rooms where id=room_id_input) then
    raise exception 'La sala no existe';
  end if;

  selected_action := lower(action_name);
  if selected_action not in ('kick','ban') then
    raise exception 'Acción no válida';
  end if;
  if duration_minutes_input not in (5,15,60,1440) then
    raise exception 'Duración no válida';
  end if;
  moderation_reason := nullif(left(trim(coalesce(reason_input,'')),500),'');
  if moderation_reason is null then
    raise exception 'Tenés que indicar el motivo de la moderación';
  end if;

  select nickname into target_nickname
  from public.messages
  where sender_id=target_sender_id and room_id=room_id_input
  order by created_at desc limit 1;
  target_nickname := coalesce(target_nickname,'Usuario');

  select count(*)::integer into prior_sanctions
  from public.wichat_moderation_events
  where sender_id=target_sender_id
    and created_at >= now()-interval '30 days'
    and action in ('kick','ban');

  applied_minutes := greatest(
    duration_minutes_input,
    case
      when prior_sanctions >= 3 then 1440
      when prior_sanctions = 2 then 60
      when prior_sanctions = 1 then 15
      else 5
    end
  );
  expiry := now() + make_interval(mins => applied_minutes);

  if selected_action='kick' then
    delete from public.wichat_kicks
      where sender_id=target_sender_id and room_id=room_id_input;
    insert into public.wichat_room_bans
      (sender_id,room_id,nickname,reason,created_at,expires_at)
    values
      (target_sender_id,room_id_input,target_nickname,moderation_reason,now(),expiry)
    on conflict (sender_id,room_id) do update set
      nickname=excluded.nickname, reason=excluded.reason,
      created_at=now(), expires_at=excluded.expires_at;
  else
    select client_ip into target_ip
    from public.wichat_user_ips where sender_id=target_sender_id;

    delete from public.wichat_kicks where sender_id=target_sender_id;
    delete from public.wichat_room_bans where sender_id=target_sender_id;
    delete from public.wichat_bans where sender_id=target_sender_id;

    insert into public.wichat_bans
      (sender_id,room_id,nickname,reason,created_at,expires_at)
    values
      (target_sender_id,room_id_input,target_nickname,moderation_reason,now(),expiry);

    if target_ip is not null then
      insert into public.wichat_ip_bans
        (client_ip,room_id,nickname,reason,expires_at)
      values
        (target_ip,room_id_input,target_nickname,moderation_reason,expiry)
      on conflict (client_ip,room_id) do update set
        nickname=excluded.nickname,reason=excluded.reason,
        created_at=now(),expires_at=excluded.expires_at;
    end if;
  end if;

  insert into public.wichat_moderation_events
    (sender_id,room_id,action,reason,duration_minutes,moderated_by)
  values
    (target_sender_id,room_id_input,selected_action,moderation_reason,applied_minutes,moderator_id_input);

  return jsonb_build_object(
    'success',true,'action',selected_action,'duration_minutes',applied_minutes,
    'prior_sanctions',prior_sanctions,'expires_at',expiry,
    'ip_banned',case when selected_action='ban' then target_ip is not null else false end,
    'reason',moderation_reason
  );
end;
$function$;
