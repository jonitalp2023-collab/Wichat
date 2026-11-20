drop policy if exists "Crear perfil propio" on public.chat_profiles;
create policy "Crear perfil propio"
on public.chat_profiles
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and is_registered = (
    coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
  )
  and (select private.has_active_nickname_lease(nickname))
);

drop policy if exists "Actualizar perfil propio" on public.chat_profiles;
create policy "Actualizar perfil propio"
on public.chat_profiles
for update
to authenticated
using (
  (select auth.uid()) = user_id
)
with check (
  (select auth.uid()) = user_id
  and is_registered = (
    coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
  )
  and (select private.has_active_nickname_lease(nickname))
);
