-- The points ledger includes internal event keys and earning reasons.
-- Guest/anonymous chat sessions do not need direct access to those records.
drop policy if exists chat_points_read_authenticated on public.chat_points_ledger;

create policy chat_points_read_registered_accounts
  on public.chat_points_ledger
  for select
  to authenticated
  using (
    (select auth.uid()) is not null
    and coalesce(((select auth.jwt())->>'is_anonymous')::boolean, true) = false
  );
