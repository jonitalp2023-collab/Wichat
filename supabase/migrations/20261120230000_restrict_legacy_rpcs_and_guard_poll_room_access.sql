-- Tighten privileged RPC exposure and enforce room membership for poll RPCs.

-- This helper is used internally by SECURITY DEFINER moderation routines.
-- The client does not need to enumerate administrative identities.
revoke execute on function public.is_wichat_admin(text) from public, anon, authenticated;

-- Legacy nickname/moderation helpers are superseded by the authenticated
-- Wichat lease/session functions and are not called by the current client.
revoke execute on function public.claim_chat_nickname(text) from public, anon, authenticated;
revoke execute on function public.heartbeat_chat_nickname() from public, anon, authenticated;
revoke execute on function public.release_chat_nickname() from public, anon, authenticated;
revoke execute on function public.wichat_contains_insult(text) from public, anon, authenticated;

create or replace function public.get_chat_room_polls(room_id_input bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if auth.uid() is null
     or not private.can_access_chat_room(room_id_input) then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',p.id,
      'room_id',p.room_id,
      'question',p.question,
      'options',p.options,
      'is_closed',p.is_closed,
      'created_at',p.created_at,
      'updated_at',p.updated_at,
      'votes',coalesce((
        select jsonb_agg(coalesce(v.cnt,0) order by opt.ord)
        from jsonb_array_elements_text(p.options) with ordinality opt(val,ord)
        left join (
          select option_index,count(*)::int cnt
          from public.chat_room_poll_votes
          where poll_id=p.id
          group by option_index
        ) v on v.option_index=opt.ord-1
      ),'[]'::jsonb),
      'total_votes',(select count(*) from public.chat_room_poll_votes where poll_id=p.id),
      'my_vote',(select option_index from public.chat_room_poll_votes where poll_id=p.id and user_id=auth.uid() limit 1)
    ) order by p.created_at desc),'[]'::jsonb)
    from public.chat_room_polls p
    where p.room_id=room_id_input
  );
end;
$function$;

create or replace function public.vote_chat_room_poll(poll_id_input uuid, option_index_input integer)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  p public.chat_room_polls%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Tenés que iniciar sesión para votar';
  end if;

  select * into p
  from public.chat_room_polls
  where id=poll_id_input
  for update;

  if not found then
    raise exception 'La encuesta no existe';
  end if;

  if not private.can_access_chat_room(p.room_id) then
    raise exception 'No tenés acceso a esta sala';
  end if;

  if p.is_closed then
    raise exception 'La encuesta está cerrada';
  end if;

  if option_index_input<0 or option_index_input>=jsonb_array_length(p.options) then
    raise exception 'Opción inválida';
  end if;

  insert into public.chat_room_poll_votes(poll_id,user_id,option_index)
  values(poll_id_input,auth.uid(),option_index_input);

  update public.chat_room_polls set updated_at=now() where id=poll_id_input;
  return true;
exception
  when unique_violation then
    raise exception 'Ya votaste en esta encuesta';
end;
$function$;

revoke execute on function public.get_chat_room_polls(bigint) from public, anon;
grant execute on function public.get_chat_room_polls(bigint) to authenticated;
revoke execute on function public.vote_chat_room_poll(uuid, integer) from public, anon;
grant execute on function public.vote_chat_room_poll(uuid, integer) to authenticated;
