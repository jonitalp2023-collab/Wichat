import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// rooms.id es BIGINT en este proyecto: aceptar IDs numéricos positivos.
const ROOM_ID_RE = /^(?:[1-9][0-9]*|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;

Deno.serve(async (req: Request) => {
  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ success: false, message: "Método no permitido." }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return respond({ success: false, message: "Sesión no válida." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      console.error("Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY.");
      return respond({ success: false, message: "Configuración del servidor incompleta." }, 500);
    }

    const adminDb = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const token = authHeader.substring(7);
    const { data: authData, error: authError } = await adminDb.auth.getUser(token);
    if (authError || !authData.user) {
      return respond({ success: false, message: "Sesión inválida." }, 401);
    }

    // El PIN por sí solo no otorga permisos administrativos.
    // La cuenta autenticada también debe estar habilitada en wichat_admins.
    const { data: activeAdmin, error: adminLookupError } = await adminDb
      .from("wichat_admins")
      .select("sender_id")
      .eq("sender_id", authData.user.id)
      .eq("active", true)
      .maybeSingle();

    if (adminLookupError) {
      console.error("No se pudo verificar el rol administrativo:", adminLookupError.message);
      return respond({ success: false, message: "No se pudo verificar el permiso administrativo." }, 500);
    }
    if (!activeAdmin) {
      return respond({ success: false, message: "Esta cuenta no tiene permisos de administrador." }, 403);
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return respond({ success: false, message: "El cuerpo de la solicitud no es JSON válido." }, 400);
    }

    const action = String(body.action ?? "");
    const pin = String(body.pin_input ?? "").trim();
    if (!pin) return respond({ success: false, message: "Ingresá el PIN." }, 400);

    const { data: pinValid, error: pinError } = await adminDb.rpc("verify_admin_pin", {
      pin_input: pin,
    });
    if (pinError) throw pinError;
    if (pinValid !== true) return respond({ success: false, message: "PIN incorrecto." }, 403);

    if (action === "verify_pin") return respond({ success: true, data: true });

    let result: unknown = null;
    let error: { message: string } | null = null;

    switch (action) {
      case "create_room": {
        const roomName = String(body.room_name ?? "").trim();
        if (!roomName || roomName.length > 30) {
          return respond({ success: false, message: "El nombre debe tener entre 1 y 30 caracteres." }, 400);
        }
        ({ data: result, error } = await adminDb.rpc("admin_create_room", {
          pin_input: pin,
          room_name: roomName,
        }));
        break;
      }

      case "delete_room": {
        const roomId = String(body.room_id_input ?? body.room_id ?? "").trim();
        if (!/^[1-9][0-9]*$/.test(roomId)) {
          return respond({ success: false, message: "ID de sala no válido." }, 400);
        }

        // La columna rooms.id y el argumento SQL son BIGINT.
        const numericRoomId = Number(roomId);
        if (!Number.isSafeInteger(numericRoomId) || numericRoomId <= 0) {
          return respond({ success: false, message: "ID de sala fuera de rango." }, 400);
        }

        console.log("Solicitud de eliminación de sala:", numericRoomId);
        ({ data: result, error } = await adminDb.rpc("admin_delete_room", {
          pin_input: pin,
          room_id_input: numericRoomId,
        }));

        if (!error && result !== true) {
          return respond({ success: false, message: "La sala no existe o no se eliminó." }, 404);
        }
        break;
      }

      case "set_room_topic": {
        const roomId = Number(body.room_id_input);
        const topic = body.topic_input == null ? null : String(body.topic_input).trim();
        if (!Number.isSafeInteger(roomId) || roomId <= 0 ||
            (topic !== null && topic.length > 180)) {
          return respond({ success: false, message: "Datos del tópico no válidos." }, 400);
        }
        ({ data: result, error } = await adminDb.rpc("admin_set_room_topic", {
          pin_input: pin,
          room_id_input: roomId,
          topic_input: topic,
        }));
        break;
      }

      case "set_room_vip": {
        const roomId = Number(body.room_id_input);
        const enabled = body.vip_enabled;
        if (!Number.isSafeInteger(roomId) || roomId <= 0 || typeof enabled !== "boolean") {
          return respond({ success: false, message: "Datos de sala VIP no válidos." }, 400);
        }
        ({ data: result, error } = await adminDb.rpc("admin_set_room_vip", {
          pin_input: pin,
          room_id_input: roomId,
          vip_enabled: enabled,
        }));
        break;
      }

      case "set_vip_member": {
        const nickname = String(body.nickname_input ?? "").trim();
        const enabled = body.vip_enabled;
        if (!nickname || nickname.length > 50 || typeof enabled !== "boolean") {
          return respond({ success: false, message: "Datos de membresía VIP no válidos." }, 400);
        }
        ({ data: result, error } = await adminDb.rpc("admin_set_vip_member", {
          pin_input: pin,
          nickname_input: nickname,
          vip_enabled: enabled,
        }));
        break;
      }

      case "list_bans": {
        ({ data: result, error } = await adminDb.rpc("admin_list_bans", { pin_input: pin }));
        break;
      }

      case "moderate_user": {
        const target = String(body.target_sender_id ?? "").trim();
        const roomId = String(body.room_id_input ?? body.room_id ?? "").trim();
        const moderationAction = String(body.action_name ?? "");
        const moderationReason = String(body.reason_input ?? "").trim();
        const requestedDuration = Number(body.duration_minutes_input ?? 5);

        if (!target || !/^[1-9][0-9]*$/.test(roomId) ||
            !["kick", "ban"].includes(moderationAction) ||
            ![5, 15, 60, 1440].includes(requestedDuration) ||
            !moderationReason || moderationReason.length > 500) {
          return respond({ success: false, message: "Datos de moderación no válidos. Indicá un motivo de hasta 500 caracteres." }, 400);
        }

        const numericRoomId = Number(roomId);
        if (!Number.isSafeInteger(numericRoomId) || numericRoomId <= 0) {
          return respond({ success: false, message: "ID de sala fuera de rango." }, 400);
        }

        ({ data: result, error } = await adminDb.rpc("admin_moderate_user", {
          pin_input: pin,
          target_sender_id: target,
          room_id_input: numericRoomId,
          action_name: moderationAction,
          reason_input: moderationReason,
          duration_minutes_input: requestedDuration,
          moderator_id_input: authData.user.id,
        }));
        break;
      }

      case "list_user_reports": {
        const { data: reports, error: reportsError } = await adminDb
          .from("chat_user_reports")
          .select("id,reporter_id,target_user_id,room_id,category,details,status,created_at,reviewed_at")
          .order("created_at", { ascending: false })
          .limit(100);
        if (reportsError) throw reportsError;
        const ids = [...new Set((reports || []).flatMap((r) => [r.reporter_id, r.target_user_id]).filter(Boolean))];
        let profiles: { user_id: string; nickname: string }[] = [];
        if (ids.length) {
          const { data: rows, error: profileError } = await adminDb
            .from("chat_profiles").select("user_id,nickname").in("user_id", ids);
          if (profileError) throw profileError;
          profiles = rows || [];
        }
        const names = new Map(profiles.map((p) => [p.user_id, p.nickname]));
        result = (reports || []).map((r) => ({
          ...r,
          reporter_nickname: names.get(r.reporter_id) || "Usuario",
          target_nickname: names.get(r.target_user_id) || "Usuario",
        }));
        break;
      }

      case "review_user_report": {
        const reportId = Number(body.report_id);
        const reportStatus = String(body.report_status ?? "");
        if (!Number.isSafeInteger(reportId) || reportId <= 0 ||
            !["reviewed", "dismissed", "action_taken"].includes(reportStatus)) {
          return respond({ success: false, message: "Datos de revisión no válidos." }, 400);
        }
        ({ data: result, error } = await adminDb
          .from("chat_user_reports")
          .update({
            status: reportStatus,
            reviewed_by: authData.user.id,
            reviewed_at: new Date().toISOString(),
          })
          .eq("id", reportId)
          .eq("status", "pending")
          .select("id,status,reviewed_at")
          .maybeSingle());
        if (!error && !result) return respond({ success: false, message: "La denuncia ya fue revisada o no existe." }, 404);
        break;
      }

      case "list_moderation_terms": {
        const { data: terms, error: termsError } = await adminDb
          .from("chat_moderation_terms")
          .select("id,term,category,active,created_at")
          .order("created_at", { ascending: false })
          .limit(200);
        if (termsError) throw termsError;
        result = terms || [];
        break;
      }

      case "add_moderation_term": {
        const term = String(body.term ?? "").trim();
        const category = String(body.category ?? "custom");
        if (term.length < 2 || term.length > 40 ||
            !["insulto", "custom"].includes(category)) {
          return respond({ success: false, message: "La palabra debe tener entre 2 y 40 caracteres." }, 400);
        }
        const normalized = term.normalize("NFD").replace(/[\\u0300-\\u036f]/g, "")
          .toLowerCase().replace(/[013457@$]/g, (ch) => ({"0":"o","1":"i","3":"e","4":"a","5":"s","7":"t","@":"a","$":"s"}[ch] || ch))
          .replace(/([a-z])\\1+/g, "$1").replace(/[^a-z0-9]+/g, " ").trim();
        if (normalized.length < 2) return respond({ success: false, message: "La palabra no es válida." }, 400);
        ({ data: result, error } = await adminDb.from("chat_moderation_terms")
          .upsert({ term, normalized_term: normalized, category, active: true, created_by: authData.user.id }, { onConflict: "normalized_term" })
          .select("id,term,category,active")
          .single());
        break;
      }

      case "toggle_moderation_term": {
        const termId = Number(body.term_id);
        const active = body.active === true;
        if (!Number.isSafeInteger(termId) || termId <= 0) {
          return respond({ success: false, message: "Palabra no válida." }, 400);
        }
        ({ data: result, error } = await adminDb.from("chat_moderation_terms")
          .update({ active }).eq("id", termId)
          .select("id,term,category,active").maybeSingle());
        if (!error && !result) return respond({ success: false, message: "La palabra no existe." }, 404);
        break;
      }

      case "list_moderation_history": {
        const { data: events, error: historyError } = await adminDb
          .from("wichat_moderation_events")
          .select("id,sender_id,room_id,action,reason,duration_minutes,moderated_by,created_at")
          .order("created_at", { ascending: false })
          .limit(100);
        if (historyError) throw historyError;
        const ids = [...new Set((events || []).map((event) => event.sender_id).filter(Boolean))];
        let profiles: { user_id: string; nickname: string }[] = [];
        if (ids.length) {
          const { data: profileRows, error: profileError } = await adminDb
            .from("chat_profiles").select("user_id,nickname").in("user_id", ids);
          if (profileError) throw profileError;
          profiles = profileRows || [];
        }
        const names = new Map(profiles.map((profile) => [profile.user_id, profile.nickname]));
        result = (events || []).map((event) => ({
          ...event, nickname: names.get(event.sender_id) || "Usuario",
        }));
        break;
      }

      case "unban_user": {
        const target = String(body.target_sender_id ?? "").trim();
        if (!target) return respond({ success: false, message: "Usuario no válido." }, 400);
        ({ data: result, error } = await adminDb.rpc("admin_unban_user", {
          pin_input: pin,
          target_sender_id: target,
        }));
        break;
      }

      case "list_bots": {
        ({ data: result, error } = await adminDb.from("chat_bots")
          .select("id,name,instructions,active,room_ids,cooldown_seconds,respond_to_bots,response_style,created_at,updated_at")
          .order("created_at", { ascending: true }));
        break;
      }

      case "create_bot": {
        const name = String(body.bot_name ?? "").trim();
        const instructions = String(body.bot_instructions ?? "").trim();
        const roomIds = Array.isArray(body.room_ids) ? [...new Set(body.room_ids.map((value: unknown) => Number(value)))] : [];
        const cooldownSeconds = Number(body.cooldown_seconds ?? 0);
        const respondToBots = body.respond_to_bots !== false;
        const responseStyle = String(body.response_style ?? "natural");
        if (!name || name.length > 25 || !instructions || instructions.length > 4000 ||
            roomIds.some((value: number) => !Number.isSafeInteger(value) || value <= 0) ||
            !Number.isInteger(cooldownSeconds) || cooldownSeconds < 0 || cooldownSeconds > 3600 ||
            !["natural", "brief", "expressive"].includes(responseStyle)) {
          return respond({
            success: false,
            message: "El nombre debe tener 1 a 25 caracteres y las instrucciones entre 1 y 4000.",
          }, 400);
        }

        const { count, error: countError } = await adminDb.from("chat_bots")
          .select("id", { count: "exact", head: true }).eq("active", true);
        if (countError) throw countError;
        if ((count ?? 0) >= 5) {
          return respond({
            success: false,
            message: "Ya hay 5 bots activos. Desactivá uno antes de activar otro.",
          }, 400);
        }

        ({ data: result, error } = await adminDb.from("chat_bots")
          .insert({ name, instructions, active: true, room_ids: roomIds, cooldown_seconds: cooldownSeconds, respond_to_bots: respondToBots, response_style: responseStyle })
          .select("id,name,instructions,active,room_ids,cooldown_seconds,respond_to_bots,response_style,created_at,updated_at").single());
        break;
      }

      case "update_bot": {
        const id = String(body.bot_id ?? "");
        const name = String(body.bot_name ?? "").trim();
        const instructions = String(body.bot_instructions ?? "").trim();
        const active = body.bot_active;
        const roomIds = Array.isArray(body.room_ids)
          ? [...new Set(body.room_ids.map((value: unknown) => Number(value)))]
          : [];
        const cooldownSeconds = Number(body.cooldown_seconds ?? 0);
        const respondToBots = body.respond_to_bots !== false;
        const responseStyle = String(body.response_style ?? "natural");

        if (!UUID_RE.test(id) || !name || name.length > 25 ||
            !instructions || instructions.length > 4000 ||
            typeof active !== "boolean" ||
            roomIds.some((value: number) => !Number.isSafeInteger(value) || value <= 0) ||
            !Number.isInteger(cooldownSeconds) || cooldownSeconds < 0 || cooldownSeconds > 3600 ||
            typeof body.respond_to_bots !== "undefined" && typeof body.respond_to_bots !== "boolean" ||
            !["natural", "brief", "expressive"].includes(responseStyle)) {
          return respond({ success: false, message: "Datos del bot no válidos." }, 400);
        }

        if (active) {
          const { count, error: countError } = await adminDb.from("chat_bots")
            .select("id", { count: "exact", head: true })
            .eq("active", true).neq("id", id);
          if (countError) throw countError;
          if ((count ?? 0) >= 5) {
            return respond({
              success: false,
              message: "Ya hay 5 bots activos. Desactivá uno primero.",
            }, 400);
          }
        }

        ({ data: result, error } = await adminDb.from("chat_bots")
          .update({ name, instructions, active, room_ids: roomIds, cooldown_seconds: cooldownSeconds, respond_to_bots: respondToBots, response_style: responseStyle, updated_at: new Date().toISOString() })
          .eq("id", id)
          .select("id,name,instructions,active,room_ids,cooldown_seconds,respond_to_bots,response_style,created_at,updated_at").maybeSingle());

        if (!error && !result) return respond({ success: false, message: "No se encontró ese bot." }, 404);
        break;
      }

      case "delete_bot": {
        const id = String(body.bot_id ?? "");
        if (!UUID_RE.test(id)) return respond({ success: false, message: "Bot no válido." }, 400);

        ({ data: result, error } = await adminDb.from("chat_bots")
          .delete().eq("id", id).select("id,name").maybeSingle());

        if (!error && !result) return respond({ success: false, message: "No se encontró ese bot." }, 404);
        break;
      }

      default:
        return respond({ success: false, message: "Acción administrativa desconocida." }, 400);
    }

    if (error) {
      console.error("Error administrativo:", error.message);
      return respond({ success: false, message: error.message }, 400);
    }

    return respond({ success: true, data: result });
  } catch (err) {
    console.error("Error en admin-api:", err);
    return respond({ success: false, message: "Error interno del servidor." }, 500);
  }
});
