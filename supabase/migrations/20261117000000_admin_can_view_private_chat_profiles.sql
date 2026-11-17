-- Allows the authenticated CHAT ARGENTINA administrator to read every registered profile,
-- including profiles whose owner has selected private visibility.
-- The administrator identity is bound server-side by verify_admin_pin() in wichat_admins.

create schema if not exists private;

create or replace function private.is_chat_profile_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and exists (
       select 1
       from public.wichat_admins as a
       where a.sender_id = (select auth.uid())::text
         and a.active is true
     );
$$;

revoke all on function private.is_chat_profile_admin() from public;
grant usage on schema private to authenticated;
grant execute on function private.is_chat_profile_admin() to authenticated;

drop policy if exists "Leer perfiles propios o visibles entre registrados" on public.chat_profiles;

create policy "Leer perfiles propios, publicos o por administrador"
on public.chat_profiles
for select
to authenticated
using (
  (select auth.uid()) = user_id
  or (
    coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, true) = false
    and is_registered = true
    and is_visible = true
  )
  or (select private.is_chat_profile_admin())
);
