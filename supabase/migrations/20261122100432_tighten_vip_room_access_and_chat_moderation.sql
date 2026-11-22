-- Enforce VIP visibility at the room-list layer and make configured moderation
-- terms authoritative for all direct message inserts.

drop policy if exists "Todos pueden ver salas" on public.rooms;
drop policy if exists rooms_select_public on public.rooms;
drop policy if exists rooms_select_accessible on public.rooms;

create policy rooms_select_public on public.rooms
for select to anon using (not is_vip);

create policy rooms_select_accessible on public.rooms
for select to authenticated
using (not is_vip or (select private.can_access_chat_room(rooms.id)));

create or replace function private.chat_message_content_allowed(message_text text)
returns boolean language sql stable security definer set search_path = ''
as $function$
  select auth.uid() is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(message_text, ''))) between 1 and 1000
    and (
      exists (select 1 from public.wichat_admins wa
              where wa.sender_id = auth.uid()::text and wa.active = true)
      or not public.wichat_contains_insult(message_text)
    );
$function$;

revoke all on function private.chat_message_content_allowed(text) from public, anon;
grant execute on function private.chat_message_content_allowed(text) to authenticated;

create or replace function public.wichat_moderate_message()
returns trigger language plpgsql security definer
set search_path = 'pg_catalog', 'public', 'pg_temp'
as $function$
declare total integer; active_ban boolean; clean_body text; spam_count integer;
begin
 if new.sender_id is null or new.room_id is null then return new; end if;
 if exists (select 1 from public.wichat_admins
            where sender_id = new.sender_id and active = true) then return new; end if;
 select exists(select 1 from public.wichat_room_bans
   where sender_id=new.sender_id and room_id=new.room_id and expires_at>now())
 into active_ban;
 if active_ban then return null; end if;
 clean_body:=coalesce(new.message,new.content,'');
 if public.wichat_contains_insult(clean_body) then
  insert into public.wichat_insult_counts(sender_id,room_id,insult_count,updated_at)
  values(new.sender_id,new.room_id,1,now())
  on conflict(sender_id,room_id) do update
    set insult_count=public.wichat_insult_counts.insult_count+1,updated_at=now()
  returning insult_count into total;
  if total<3 then
   insert into public.wichat_moderation_events(sender_id,room_id,action,reason)
   values(new.sender_id,new.room_id,'warning_'||total,'Mensaje bloqueado por palabra prohibida');
   return null;
  end if;
  insert into public.wichat_room_bans(sender_id,room_id,nickname,reason,expires_at)
  values(new.sender_id,new.room_id,new.nickname,'Tres infracciones por lenguaje no permitido',now()+interval '5 minutes')
  on conflict(sender_id,room_id) do update set nickname=excluded.nickname,
    reason=excluded.reason,created_at=now(),expires_at=excluded.expires_at;
  insert into public.wichat_moderation_events(sender_id,room_id,action,reason,duration_minutes)
  values(new.sender_id,new.room_id,'ban','Tres infracciones por lenguaje no permitido',5);
  return null;
 end if;
 if coalesce(new.message_type,'text')='text' and length(trim(clean_body))>=4 then
  select count(*) into spam_count from public.messages
   where sender_id=new.sender_id and room_id=new.room_id
     and created_at>now()-interval '60 seconds'
     and public.wichat_normalize_moderation_text(message)=public.wichat_normalize_moderation_text(clean_body);
  if spam_count>=2 then
   insert into public.wichat_moderation_events(sender_id,room_id,action,reason)
   values(new.sender_id,new.room_id,'spam_blocked','Mensaje repetido bloqueado automáticamente');
   return null;
  end if;
 end if;
 return new;
end;
$function$;

create or replace function public.wichat_antispam_guard()
returns trigger language plpgsql security definer
set search_path = 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
 v_sender text; v_body text; v_media text; v_hash text; v_context text;
 v_now timestamptz := clock_timestamp(); v_recent_count integer;
 v_last_sent timestamptz; v_duplicate_count integer;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then return new; end if;
 v_sender:=to_jsonb(new)->>'sender_id';
 if v_sender is null or btrim(v_sender)='' then return new; end if;
 v_body:=coalesce(to_jsonb(new)->>'message',to_jsonb(new)->>'content','');
 v_media:=coalesce(to_jsonb(new)->>'media_url','');
 v_context:=coalesce(to_jsonb(new)->>'room_id',to_jsonb(new)->>'recipient_id','chat');
 v_body:=lower(regexp_replace(btrim(v_body),'[[:space:]]+',' ','g'));
 if v_body='' then v_body:='media:'||v_media; end if;
 v_hash:=md5(v_body);
 perform pg_advisory_xact_lock(hashtextextended(v_sender,0));
 select count(*),max(sent_at) into v_recent_count,v_last_sent
 from public.chat_antispam_events
 where sender_id=v_sender and sent_at>v_now-interval '10 seconds';
 if v_recent_count>=3 then
  raise exception 'Estás enviando mensajes demasiado rápido. Esperá unos segundos.' using errcode='P0001';
 end if;
 if v_last_sent is not null and v_now-v_last_sent<interval '2 seconds' then
  raise exception 'Esperá 2 segundos antes de enviar otro mensaje.' using errcode='P0001';
 end if;
 select count(*) into v_duplicate_count from public.chat_antispam_events
 where sender_id=v_sender and context_key=v_context and body_hash=v_hash
   and sent_at>v_now-interval '60 seconds';
 if v_duplicate_count>=1 then
  raise exception 'Detectamos un mensaje repetido. Cambiá el texto antes de volver a enviarlo.' using errcode='P0001';
 end if;
 insert into public.chat_antispam_events(sender_id,body_hash,context_key,sent_at)
 values(v_sender,v_hash,v_context,v_now);
 if mod(extract(epoch from v_now)::bigint,100)=0 then
  delete from public.chat_antispam_events where sent_at<v_now-interval '1 day';
 end if;
 return new;
end;
$function$;
