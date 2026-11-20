-- Push notification device tokens and current-room subscriptions.
-- This is the source migration already applied to the linked Supabase project.
create table if not exists public.chat_push_tokens (
  user_id uuid primary key references auth.users(id) on delete cascade,
  fcm_token text not null unique,
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_push_room_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  room_id bigint not null references public.rooms(id) on delete cascade,
  updated_at timestamptz not null default now()
);

create index if not exists chat_push_room_subscriptions_room_id_idx
  on public.chat_push_room_subscriptions(room_id);

alter table public.chat_push_tokens enable row level security;
alter table public.chat_push_room_subscriptions enable row level security;

drop policy if exists "Users manage their own push token" on public.chat_push_tokens;
create policy "Users manage their own push token"
  on public.chat_push_tokens
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users manage their own push room subscription" on public.chat_push_room_subscriptions;
create policy "Users manage their own push room subscription"
  on public.chat_push_room_subscriptions
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.chat_push_tokens from anon;
revoke all on public.chat_push_room_subscriptions from anon;
grant select, insert, update, delete on public.chat_push_tokens to authenticated;
grant select, insert, update, delete on public.chat_push_room_subscriptions to authenticated;
