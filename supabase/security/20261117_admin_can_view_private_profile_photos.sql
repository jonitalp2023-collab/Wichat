-- Let the verified administrator view photos belonging to private registered profiles.
drop policy if exists "Registered users can view permitted profile photos" on storage.objects;

create policy "Registered users and admins can view permitted profile photos"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'chat-profile-photos'
  and (
    exists (
      select 1
      from public.chat_profiles as viewer
      join public.chat_profiles as profile
        on profile.user_id::text = (storage.foldername(objects.name))[1]
      where viewer.user_id = (select auth.uid())
        and viewer.is_registered = true
        and profile.is_registered = true
        and (
          profile.user_id = (select auth.uid())
          or profile.is_visible = true
        )
    )
    or (
      (select private.is_chat_profile_admin())
      and exists (
        select 1
        from public.chat_profiles as profile
        where profile.user_id::text = (storage.foldername(objects.name))[1]
          and profile.is_registered = true
      )
    )
  )
);
