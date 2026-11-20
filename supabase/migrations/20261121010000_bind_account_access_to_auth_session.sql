-- Bind registered-account access to the signed Supabase Auth session.
alter table public.wichat_account_sessions
  add column if not exists auth_session_id uuid;

create or replace function private.has_active_account_session()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_jwt jsonb := (select auth.jwt());
  v_session_id uuid;
begin
  if v_uid is null then return false; end if;
  if coalesce((v_jwt ->> 'is_anonymous')::boolean, true) then return true; end if;
  begin
    v_session_id := nullif(v_jwt ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if v_session_id is null then return false; end if;
  return exists (
    select 1 from public.wichat_account_sessions s
    where s.user_id = v_uid
      and s.auth_session_id = v_session_id
      and s.expires_at > now()
  );
end;
$function$;

revoke all on function private.has_active_account_session() from public, anon;
grant execute on function private.has_active_account_session() to authenticated, service_role;

create or replace function public.wichat_claim_account_session(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_current_device text;
  v_expires timestamptz;
  v_auth_session_id uuid;
begin
  if v_uid is null then raise exception 'Tenés que iniciar sesión.'; end if;
  if p_device_id is null or length(p_device_id) < 16 or length(p_device_id) > 128 then
    raise exception 'Identificador de dispositivo no válido.';
  end if;
  begin
    v_auth_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'La sesión de autenticación no es válida.';
  end;
  if v_auth_session_id is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, true) then
    raise exception 'Se requiere una sesión registrada válida.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  select device_id, expires_at into v_current_device, v_expires
  from public.wichat_account_sessions where user_id = v_uid;
  if found and v_expires > now() and v_current_device <> p_device_id then return false; end if;
  insert into public.wichat_account_sessions(user_id, device_id, auth_session_id, expires_at, updated_at)
  values(v_uid, p_device_id, v_auth_session_id, now() + interval '2 minutes', now())
  on conflict(user_id) do update
    set device_id = excluded.device_id, auth_session_id = excluded.auth_session_id,
        expires_at = excluded.expires_at, updated_at = now();
  return true;
end;
$function$;

create or replace function public.wichat_refresh_account_session(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_auth_session_id uuid;
begin
  if v_uid is null then return false; end if;
  begin
    v_auth_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then return false;
  end;
  if v_auth_session_id is null then return false; end if;
  update public.wichat_account_sessions
  set expires_at = now() + interval '2 minutes', updated_at = now()
  where user_id = v_uid and device_id = p_device_id
    and auth_session_id = v_auth_session_id and expires_at > now();
  return found;
end;
$function$;

drop policy if exists messages_insert_room_access on public.messages;
create policy messages_insert_room_access on public.messages for insert to authenticated
with check (
  sender_id = (select auth.uid())::text
  and (select private.has_active_account_session())
  and (select check_chat_access(messages.sender_id, messages.room_id))
  and (select private.has_active_nickname_lease(messages.nickname))
  and (select private.chat_message_content_allowed(messages.message))
  and message_type = 'text' and media_url is null and content is null
);

drop policy if exists "Enviar mensajes privados propios" on public.private_messages;
create policy "Enviar mensajes privados propios" on public.private_messages for insert to authenticated
with check (
  (select auth.uid()) = sender_id
  and (select private.has_active_account_session())
  and not (select private.is_chat_user_blocked(sender_id, recipient_id))
  and (select private.has_active_nickname_lease(sender_nickname))
);

drop policy if exists "Crear perfil propio" on public.chat_profiles;
create policy "Crear perfil propio" on public.chat_profiles for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and (select private.has_active_account_session())
  and is_registered = (coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false)
  and (select private.has_active_nickname_lease(nickname))
);

drop policy if exists "Actualizar perfil propio" on public.chat_profiles;
create policy "Actualizar perfil propio" on public.chat_profiles for update to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and (select private.has_active_account_session())
  and is_registered = (coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false)
  and (select private.has_active_nickname_lease(nickname))
);

drop policy if exists "Users manage their own push room subscription" on public.chat_push_room_subscriptions;
create policy "Users manage their own push room subscription" on public.chat_push_room_subscriptions for all to authenticated
using (
  (select auth.uid()) = user_id
  and (select private.has_active_account_session())
)
with check (
  (select auth.uid()) = user_id
  and (select private.has_active_account_session())
  and (select check_chat_access((select auth.uid())::text, chat_push_room_subscriptions.room_id))
);
