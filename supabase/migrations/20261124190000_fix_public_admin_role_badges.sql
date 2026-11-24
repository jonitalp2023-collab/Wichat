-- ChatArgentina: make public role badges independent from profile rows.
-- Every active administrator is returned even when no chat_profiles row exists.
CREATE OR REPLACE FUNCTION public.get_chat_identity_badges()
RETURNS TABLE (
  sender_id text,
  is_registered boolean,
  is_admin boolean,
  is_owner boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT
    admin.sender_id,
    COALESCE(profile.is_registered, false) AS is_registered,
    true AS is_admin,
    (admin.role = 'owner') AS is_owner
  FROM public.wichat_admins AS admin
  LEFT JOIN public.chat_profiles AS profile
    ON profile.user_id::text = admin.sender_id
  WHERE admin.active = true

  UNION ALL

  SELECT
    profile.user_id::text AS sender_id,
    true AS is_registered,
    false AS is_admin,
    false AS is_owner
  FROM public.chat_profiles AS profile
  WHERE profile.is_registered = true
    AND NOT EXISTS (
      SELECT 1
      FROM public.wichat_admins AS admin
      WHERE admin.sender_id = profile.user_id::text
        AND admin.active = true
    );
$function$;

REVOKE ALL ON FUNCTION public.get_chat_identity_badges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_chat_identity_badges() TO anon, authenticated;
