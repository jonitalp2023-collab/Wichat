-- Add evidence references for user-generated-content reports.
-- The report keeps a bounded text snapshot so moderators can review context if the original
-- message is no longer available. The reporter's existing RLS policy binds reporter_id
-- to auth.uid() and prevents reporting one's own account.
ALTER TABLE public.chat_user_reports
  ADD COLUMN target_message_id bigint
    REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN target_private_message_id bigint
    REFERENCES public.private_messages(id) ON DELETE SET NULL,
  ADD COLUMN message_snapshot text;

ALTER TABLE public.chat_user_reports
  ADD CONSTRAINT chat_user_reports_one_message_target
    CHECK (num_nonnulls(target_message_id, target_private_message_id) <= 1),
  ADD CONSTRAINT chat_user_reports_message_snapshot_length
    CHECK (message_snapshot IS NULL OR char_length(message_snapshot) <= 2000);

CREATE INDEX chat_user_reports_target_message_idx
  ON public.chat_user_reports(target_message_id)
  WHERE target_message_id IS NOT NULL;

CREATE INDEX chat_user_reports_target_private_message_idx
  ON public.chat_user_reports(target_private_message_id)
  WHERE target_private_message_id IS NOT NULL;

COMMENT ON COLUMN public.chat_user_reports.message_snapshot IS
  'Limited text snapshot retained as evidence for a user-submitted message report.';
