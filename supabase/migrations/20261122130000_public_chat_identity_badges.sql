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
    COALESCE(profile.user_id::text, admin.sender_id) AS sender_id,
    COALESCE(profile.is_registered, false) AS is_registered,
    (admin.sender_id IS NOT NULL) AS is_admin,
    COALESCE(admin.role = 'owner', false) AS is_owner
  FROM public.chat_profiles AS profile
  FULL JOIN public.wichat_admins AS admin
    ON admin.sender_id = profile.user_id::text
   AND admin.active = true
  WHERE
    profile.is_registered = true
    OR (admin.sender_id IS NOT NULL AND admin.active = true);
$function$;

REVOKE ALL ON FUNCTION public.get_chat_identity_badges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_chat_identity_badges() TO anon, authenticated;
