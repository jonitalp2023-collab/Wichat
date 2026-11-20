import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return respond({ success: false, message: "Método no permitido." }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return respond({ success: false, message: "Iniciá sesión nuevamente para continuar." }, 401);
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return respond({ success: false, message: "Solicitud no válida." }, 400);
    }
    if (body.confirmation !== "ELIMINAR") {
      return respond({ success: false, message: "Falta la confirmación de eliminación." }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      console.error("Falta la configuración segura de Supabase.");
      return respond({ success: false, message: "El servicio de eliminación no está disponible." }, 500);
    }

    const adminDb = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const token = authHeader.substring(7);
    const { data: authData, error: authError } = await adminDb.auth.getUser(token);
    const user = authData?.user;
    if (authError || !user?.id) {
      return respond({ success: false, message: "La sesión venció. Iniciá sesión nuevamente." }, 401);
    }
    if (user.is_anonymous) {
      return respond({ success: false, message: "Las cuentas de invitado no tienen una cuenta registrada para eliminar." }, 403);
    }

    const userId = user.id;
    const deleteBy = async (table: string, column: string) => {
      const { error } = await adminDb.from(table).delete().eq(column, userId);
      if (error) throw new Error(`No se pudieron limpiar los datos de ${table}: ${error.message}`);
    };
    const updateNullBy = async (table: string, column: string) => {
      const { error } = await adminDb.from(table).update({ [column]: null }).eq(column, userId);
      if (error) throw new Error(`No se pudieron anonimizar los datos de ${table}: ${error.message}`);
    };

    // Eliminar primero las fotos privadas para que Auth no quede como propietario de objetos.
    const { data: photoFiles, error: photoListError } = await adminDb.storage
      .from("chat-profile-photos")
      .list(userId, { limit: 1000 });
    if (photoListError) throw new Error("No se pudieron localizar las fotos de perfil.");
    const photoPaths = (photoFiles || [])
      .filter((file) => file.name && file.id)
      .map((file) => `${userId}/${file.name}`);
    if (photoPaths.length) {
      const { error: photoDeleteError } = await adminDb.storage
        .from("chat-profile-photos")
        .remove(photoPaths);
      if (photoDeleteError) throw new Error("No se pudieron eliminar las fotos de perfil.");
    }

    // Borrar mensajes y relaciones sociales de la cuenta.
    const { error: publicMessagesError } = await adminDb.from("messages").delete().eq("sender_id", userId);
    if (publicMessagesError) throw new Error("No se pudieron eliminar los mensajes públicos.");

    const { error: privateMessagesError } = await adminDb.from("private_messages")
      .delete().or(`sender_id.eq.${userId},recipient_id.eq.${userId}`);
    if (privateMessagesError) throw new Error("No se pudieron eliminar los mensajes privados.");

    const { error: reactionsError } = await adminDb.from("chat_message_reactions")
      .delete().eq("user_id", userId);
    if (reactionsError) throw new Error("No se pudieron eliminar las reacciones.");

    const { error: blocksError } = await adminDb.from("chat_user_blocks")
      .delete().or(`blocker_id.eq.${userId},blocked_id.eq.${userId}`);
    if (blocksError) throw new Error("No se pudieron eliminar los bloqueos.");

    const { data: polls, error: pollsError } = await adminDb.from("chat_room_polls")
      .select("id").eq("created_by", userId);
    if (pollsError) throw new Error("No se pudieron revisar las encuestas de la cuenta.");
    const pollIds = (polls || []).map((poll) => poll.id);
    if (pollIds.length) {
      const { error: pollVotesError } = await adminDb.from("chat_room_poll_votes")
        .delete().in("poll_id", pollIds);
      if (pollVotesError) throw new Error("No se pudieron eliminar los votos de las encuestas.");
    }
    const { error: ownVotesError } = await adminDb.from("chat_room_poll_votes")
      .delete().eq("user_id", userId);
    if (ownVotesError) throw new Error("No se pudieron eliminar los votos de la cuenta.");
    if (pollIds.length) {
      const { error: pollsDeleteError } = await adminDb.from("chat_room_polls")
        .delete().eq("created_by", userId);
      if (pollsDeleteError) throw new Error("No se pudieron eliminar las encuestas creadas por la cuenta.");
    }

    // Eliminar denuncias donde la cuenta figure como denunciante o denunciada.
    await updateNullBy("chat_user_reports", "reviewed_by");
    const { error: reportsError } = await adminDb.from("chat_user_reports")
      .delete().or(`reporter_id.eq.${userId},target_user_id.eq.${userId}`);
    if (reportsError) throw new Error("No se pudieron eliminar las denuncias asociadas a la cuenta.");

    // Los registros de moderación de terceros conservan su historial, sin identificar a este usuario como moderador.
    await updateNullBy("wichat_moderation_events", "moderated_by");
    await updateNullBy("chat_moderation_terms", "created_by");

    const cleanupTasks: Array<[string, string]> = [
      ["chat_profiles", "user_id"],
      ["chat_points_ledger", "user_id"],
      ["chat_vip_members", "user_id"],
      ["wichat_account_sessions", "user_id"],
      ["wichat_admin_pin_attempts", "user_id"],
      ["admins", "user_id"],
      ["wichat_admins", "sender_id"],
      ["wichat_active_nicks", "sender_id"],
      ["wichat_nicknames", "sender_id"],
      ["chat_antispam_events", "sender_id"],
      ["chat_bot_requests", "sender_id"],
      ["wichat_badword_counts", "sender_id"],
      ["wichat_insult_counts", "sender_id"],
      ["wichat_user_ips", "sender_id"],
      ["wichat_bans", "sender_id"],
      ["wichat_kicks", "sender_id"],
      ["wichat_room_bans", "sender_id"],
      ["wichat_moderation_events", "sender_id"],
      ["chat_scheduled_announcements", "created_by"],
    ];
    for (const [table, column] of cleanupTasks) await deleteBy(table, column);

    // Revocar los tokens de renovación en todos los dispositivos y borrar la identidad de Auth.
    const { error: revokeError } = await adminDb.auth.admin.signOut(token);
    if (revokeError) {
      console.error("No se pudieron revocar todas las sesiones:", revokeError.message);
      return respond({ success: false, message: "No se pudieron cerrar todas las sesiones. No se completó la eliminación; volvé a intentarlo." }, 503);
    }

    const { error: deleteUserError } = await adminDb.auth.admin.deleteUser(userId);
    if (deleteUserError) {
      console.error("No se pudo eliminar la identidad de Auth:", deleteUserError.message);
      return respond({ success: false, message: "Los datos se limpiaron, pero no se pudo cerrar la cuenta. Contactá al soporte para completar el trámite." }, 500);
    }

    return respond({ success: true, message: "Tu cuenta y los datos asociados fueron eliminados." });
  } catch (error) {
    console.error("Error en delete-account:", error);
    return respond({
      success: false,
      message: "No se pudo completar la eliminación. Tu cuenta sigue activa; contactá al soporte si el problema continúa.",
    }, 500);
  }
});
