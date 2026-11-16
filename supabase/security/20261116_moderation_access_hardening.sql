-- CHAT ARGENTINA
-- Refuerzo de acceso para la tabla heredada de baneos y RPC de moderacion.
-- Aplicado directamente en Supabase el 2026-11-16.
-- Mantener este parche como registro; no ejecutar en otro entorno sin revisar.

begin;

drop policy if exists "Administrar baneados" on public.banned_users;
drop policy if exists "Consultar baneados" on public.banned_users;

revoke all privileges on table public.banned_users
  from anon, authenticated, public;

revoke all privileges (id, nickname, created_at) on table public.banned_users
  from anon, authenticated, public;

revoke execute on function public.admin_moderate_user(text,text,bigint,text,text)
  from public, anon, authenticated;

revoke execute on function public.admin_moderate_user(text,text,bigint,text)
  from public, anon, authenticated;

commit;

-- La sobrecarga vigente de 7 argumentos queda disponible para service_role,
-- que es quien la invoca desde la Edge Function admin-api.
