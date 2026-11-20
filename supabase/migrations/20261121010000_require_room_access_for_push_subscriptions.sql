-- Only allow a user to subscribe to push notifications for rooms they can currently access.
-- Keep USING limited to ownership so users can still view or remove stale subscriptions
-- after losing room access. Enforce room access for INSERT and UPDATE through WITH CHECK.
drop policy if exists "Users manage their own push room subscription" on public.chat_push_room_subscriptions;

create policy "Users manage their own push room subscription"
on public.chat_push_room_subscriptions
for all
to authenticated
using (
  (select auth.uid()) = user_id
)
with check (
  (select auth.uid()) = user_id
  and (select public.check_chat_access((select auth.uid())::text, room_id))
);
