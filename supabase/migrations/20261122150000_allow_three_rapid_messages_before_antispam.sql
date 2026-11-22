-- Allow three rapid messages; block the fourth within the rolling 10-second window.
-- Remove the old 2-second per-message cooldown, which could block before message four.
create or replace function public.wichat_antispam_guard()
returns trigger language plpgsql security definer
set search_path = 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
 v_sender text; v_body text; v_media text; v_hash text; v_context text;
 v_now timestamptz := clock_timestamp(); v_recent_count integer;
 v_duplicate_count integer;
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
 select count(*) into v_recent_count
 from public.chat_antispam_events
 where sender_id=v_sender and sent_at>v_now-interval '10 seconds';
 -- Three messages are allowed. The fourth rapid message is blocked.
 if v_recent_count>=3 then
  raise exception 'Estás enviando mensajes demasiado rápido. Esperá unos segundos.' using errcode='P0001';
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
