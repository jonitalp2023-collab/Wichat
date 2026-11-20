alter function public.wichat_normalize_moderation_text(text)
  set search_path = '';

revoke execute on function public.admin_set_room_topic(text, bigint, text) from public, anon;
grant execute on function public.admin_set_room_topic(text, bigint, text) to authenticated;

revoke execute on function public.admin_set_room_vip(text, bigint, boolean) from public, anon;
grant execute on function public.admin_set_room_vip(text, bigint, boolean) to authenticated;

revoke execute on function public.admin_set_vip_member(text, text, boolean) from public, anon;
grant execute on function public.admin_set_vip_member(text, text, boolean) to authenticated;
