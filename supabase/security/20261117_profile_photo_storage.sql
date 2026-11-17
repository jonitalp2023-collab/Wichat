-- CHAT ARGENTINA: almacenamiento privado de fotos de perfil
-- Bucket privado; cada usuario solo puede administrar archivos dentro de su carpeta UUID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-profile-photos', 'chat-profile-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

alter table public.chat_profiles
  drop constraint if exists chat_profiles_avatar_https_check;
alter table public.chat_profiles
  add constraint chat_profiles_avatar_path_check
  check (
    avatar_url is null
    or (
      char_length(avatar_url) <= 2048
      and (
        avatar_url ~* '^https://'
        or avatar_url ~ '^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]+$'
      )
    )
  );

drop policy if exists "Registered users can view permitted profile photos" on storage.objects;
create policy "Registered users can view permitted profile photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-profile-photos'
  and exists (
    select 1
    from public.chat_profiles viewer
    join public.chat_profiles profile
      on profile.user_id::text = (storage.foldername(name))[1]
    where viewer.user_id = (select auth.uid())
      and viewer.is_registered = true
      and profile.is_registered = true
      and (profile.user_id = (select auth.uid()) or profile.is_visible = true)
  )
);

drop policy if exists "Registered users upload own profile photo" on storage.objects;
create policy "Registered users upload own profile photo"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.chat_profiles p
    where p.user_id = (select auth.uid()) and p.is_registered = true
  )
);

drop policy if exists "Registered users update own profile photo" on storage.objects;
create policy "Registered users update own profile photo"
on storage.objects for update to authenticated
using (
  bucket_id = 'chat-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.chat_profiles p
    where p.user_id = (select auth.uid()) and p.is_registered = true
  )
)
with check (
  bucket_id = 'chat-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.chat_profiles p
    where p.user_id = (select auth.uid()) and p.is_registered = true
  )
);

drop policy if exists "Registered users delete own profile photo" on storage.objects;
create policy "Registered users delete own profile photo"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.chat_profiles p
    where p.user_id = (select auth.uid()) and p.is_registered = true
  )
);
