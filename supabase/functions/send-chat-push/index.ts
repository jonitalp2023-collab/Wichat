import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function base64Url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToBytes(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function getGoogleAccessToken(serviceAccount: Record<string, string>) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri || "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = header + "." + claims;
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(serviceAccount.private_key.replace(/\\n/g, "\n")),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(unsigned)),
  );
  const assertion = unsigned + "." + base64Url(signature);
  const tokenResponse = await fetch(serviceAccount.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenBody = await tokenResponse.json();
  if (!tokenResponse.ok || !tokenBody.access_token) {
    throw new Error("Google OAuth no pudo emitir un token: " + JSON.stringify(tokenBody).slice(0, 500));
  }
  return String(tokenBody.access_token);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Método no permitido." }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ success: false, error: "Faltan credenciales internas de Supabase." }, 500);
    }
    const authorization = req.headers.get("Authorization") || "";
    const accessToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
    if (!accessToken) return json({ success: false, error: "Sesión no válida." }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await admin.auth.getUser(accessToken);
    const user = authData?.user;
    if (authError || !user?.id) return json({ success: false, error: "La sesión expiró o no es válida." }, 401);

    const body = await req.json();

    // Registrar el token del dispositivo usando la identidad validada por Supabase.
    // Si el celular cambió de cuenta, se elimina la asociación anterior del token.
    if (String(body?.action || "") === "register") {
      const fcmToken = String(body?.fcm_token || "").trim();
      if (fcmToken.length < 20 || fcmToken.length > 4096) {
        return json({ success: false, error: "Token FCM no válido." }, 400);
      }

      const { error: removeTokenError } = await admin
        .from("chat_push_tokens")
        .delete()
        .eq("fcm_token", fcmToken);
      if (removeTokenError) throw removeTokenError;

      const { error: removeUserError } = await admin
        .from("chat_push_tokens")
        .delete()
        .eq("user_id", user.id);
      if (removeUserError) throw removeUserError;

      const { error: insertTokenError } = await admin
        .from("chat_push_tokens")
        .insert({
          user_id: user.id,
          fcm_token: fcmToken,
          updated_at: new Date().toISOString(),
        });
      if (insertTokenError) throw insertTokenError;

      console.log("FCM token registrado para el usuario autenticado.");
      return json({ success: true, registered: true });
    }

    if (!firebaseJson) {
      return json({ success: false, error: "Falta el secreto FIREBASE_SERVICE_ACCOUNT_JSON." }, 500);
    }

    const kind = String(body?.kind || "");
    const messageId = Number(body?.message_id);
    if (!Number.isSafeInteger(messageId) || messageId < 1 || !["private", "room"].includes(kind)) {
      return json({ success: false, error: "Solicitud de notificación no válida." }, 400);
    }

    let senderId = "";
    let senderNickname = "Usuario";
    let messageText = "";
    let roomId: number | null = null;
    let recipientIds: string[] = [];

    if (kind === "private") {
      const { data: message, error } = await admin
        .from("private_messages")
        .select("id, sender_id, recipient_id, sender_nickname, content, message_type")
        .eq("id", messageId)
        .maybeSingle();
      if (error || !message) return json({ success: false, error: "No se encontró el mensaje privado." }, 404);
      if (String(message.sender_id) !== user.id) return json({ success: false, error: "No podés notificar este mensaje." }, 403);
      senderId = String(message.sender_id);
      senderNickname = String(message.sender_nickname || "Usuario");
      messageText = String(message.content || "");
      recipientIds = [String(message.recipient_id)];
    } else {
      const { data: message, error } = await admin
        .from("messages")
        .select("id, sender_id, nickname, message, content, room_id, message_type")
        .eq("id", messageId)
        .maybeSingle();
      if (error || !message) return json({ success: false, error: "No se encontró el mensaje de la sala." }, 404);
      if (String(message.sender_id || "") !== user.id) return json({ success: false, error: "No podés notificar este mensaje." }, 403);
      senderId = String(message.sender_id);
      senderNickname = String(message.nickname || "Usuario");
      messageText = String(message.message || message.content || "");
      roomId = Number(message.room_id);
      const { data: subscriptions, error: subscriptionsError } = await admin
        .from("chat_push_room_subscriptions")
        .select("user_id")
        .eq("room_id", roomId)
        .neq("user_id", senderId);
      if (subscriptionsError) throw subscriptionsError;
      recipientIds = (subscriptions || []).map((item: { user_id: string }) => String(item.user_id));
    }

    recipientIds = [...new Set(recipientIds)].filter((id) => id && id !== senderId).slice(0, 500);
    if (!recipientIds.length) return json({ success: true, sent: 0, message: "No hay destinatarios registrados para esta notificación." });

    const { data: tokenRows, error: tokenError } = await admin
      .from("chat_push_tokens")
      .select("user_id, fcm_token")
      .in("user_id", recipientIds);
    if (tokenError) throw tokenError;
    if (!tokenRows?.length) return json({ success: true, sent: 0, message: "Los destinatarios todavía no tienen token FCM." });

    let serviceAccount: Record<string, string>;
    try {
      serviceAccount = JSON.parse(firebaseJson);
    } catch {
      return json({ success: false, error: "El secreto de Firebase no contiene un JSON válido." }, 500);
    }
    if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
      return json({ success: false, error: "El JSON de Firebase no contiene los campos necesarios." }, 500);
    }

    const googleToken = await getGoogleAccessToken(serviceAccount);
    const title = kind === "private" ? "Nuevo mensaje de " + senderNickname : "ChatArgentina · Sala";
    const preview = messageText.trim()
      ? (kind === "private" ? messageText.trim() : senderNickname + ": " + messageText.trim())
      : "Te enviaron un mensaje";
    const notificationBody = preview.length > 180 ? preview.slice(0, 177) + "..." : preview;
    let sent = 0;
    const failures: string[] = [];

    for (const row of tokenRows) {
      const fcmResponse = await fetch(
        "https://fcm.googleapis.com/v1/projects/" + serviceAccount.project_id + "/messages:send",
        {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + googleToken,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: row.fcm_token,
              notification: { title, body: notificationBody },
              data: {
                kind,
                message_id: String(messageId),
                room_id: roomId === null ? "" : String(roomId),
                sender_id: senderId,
              },
              android: {
                priority: "HIGH",
                notification: {
                  channel_id: "chatargentina_messages",
                  sound: "default",
                },
              },
            },
          }),
        },
      );
      if (fcmResponse.ok) {
        sent++;
      } else {
        const detail = await fcmResponse.text();
        console.error("FCM send failed for a registered token:", fcmResponse.status, detail.slice(0, 400));
        failures.push(String(fcmResponse.status));
        if (fcmResponse.status === 404 || detail.includes("UNREGISTERED")) {
          await admin.from("chat_push_tokens").delete().eq("fcm_token", row.fcm_token);
        }
      }
    }

    return json({ success: true, sent, failed: failures.length });
  } catch (error) {
    console.error("send-chat-push error:", error);
    return json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});