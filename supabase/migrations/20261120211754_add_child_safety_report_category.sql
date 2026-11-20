ALTER TABLE public.chat_user_reports
  DROP CONSTRAINT chat_user_reports_category_check;

ALTER TABLE public.chat_user_reports
  ADD CONSTRAINT chat_user_reports_category_check
  CHECK (category = ANY (ARRAY[
    'spam'::text,
    'insultos'::text,
    'acoso'::text,
    'contenido_inapropiado'::text,
    'seguridad_infantil'::text,
    'otro'::text
  ]));
