create table if not exists public.chat_profile_reactions (
  target_user_id uuid not null references auth.users(id) on delete cascade,
  reactor_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (reaction in ('👍','❤️','👎','😂')),
  created_at timestamptz not null default now(),
  primary key (target_user_id, reactor_id),
  check (target_user_id <> reactor_id)
);
alter table public.chat_profile_reactions enable row level security;
grant select, insert, update, delete on public.chat_profile_reactions to authenticated;

drop policy if exists "Leer reacciones de perfiles visibles" on public.chat_profile_reactions;
create policy "Leer reacciones de perfiles visibles"
on public.chat_profile_reactions for select to authenticated
using (
  coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
  and (
    target_user_id = (select auth.uid())
    or exists (
      select 1 from public.chat_profiles p
      where p.user_id = target_user_id and p.is_registered = true and p.is_visible = true
    )
  )
);

drop policy if exists "Reaccionar perfiles visibles" on public.chat_profile_reactions;
create policy "Reaccionar perfiles visibles"
on public.chat_profile_reactions for insert to authenticated
with check (
  (select auth.uid()) = reactor_id
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
  and target_user_id <> (select auth.uid())
  and exists (
    select 1 from public.chat_profiles p
    where p.user_id = target_user_id and p.is_registered = true and p.is_visible = true
  )
);

drop policy if exists "Cambiar reaccion propia" on public.chat_profile_reactions;
create policy "Cambiar reaccion propia"
on public.chat_profile_reactions for update to authenticated
using (
  (select auth.uid()) = reactor_id
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
)
with check (
  (select auth.uid()) = reactor_id
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
  and exists (
    select 1 from public.chat_profiles p
    where p.user_id = target_user_id and p.is_registered = true and p.is_visible = true
  )
);

drop policy if exists "Quitar reaccion propia" on public.chat_profile_reactions;
create policy "Quitar reaccion propia"
on public.chat_profile_reactions for delete to authenticated
using (
  (select auth.uid()) = reactor_id
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
);
