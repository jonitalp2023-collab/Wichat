alter view public.chat_public_profile_badges set (security_invoker = true);
revoke all on public.chat_public_profile_badges from public, anon, authenticated;
grant select on public.chat_public_profile_badges to service_role;
revoke all on function public.get_registered_profile_ids() from public, anon, authenticated;
grant execute on function public.get_registered_profile_ids() to service_role;
