DROP POLICY chat_user_reports_insert_own ON public.chat_user_reports;

CREATE POLICY chat_user_reports_insert_own
ON public.chat_user_reports
FOR INSERT
TO authenticated
WITH CHECK (
  reporter_id = (SELECT auth.uid())
  AND target_user_id <> (SELECT auth.uid())
  AND (
    (
      target_message_id IS NULL
      AND target_private_message_id IS NULL
      AND message_snapshot IS NULL
    )
    OR
    (
      target_message_id IS NOT NULL
      AND target_private_message_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM public.messages m
        WHERE m.id = target_message_id
          AND m.sender_id = target_user_id::text
          AND left(coalesce(nullif(m.message, ''), m.content, ''), 2000)
              = coalesce(message_snapshot, '')
      )
    )
    OR
    (
      target_private_message_id IS NOT NULL
      AND target_message_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM public.private_messages pm
        WHERE pm.id = target_private_message_id
          AND pm.sender_id = target_user_id
          AND pm.recipient_id = (SELECT auth.uid())
          AND left(pm.content, 2000) = coalesce(message_snapshot, '')
      )
    )
  )
);
