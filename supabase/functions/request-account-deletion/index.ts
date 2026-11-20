
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = [
  "https://jonitalp2023-collab.github.io",
  "https://appassets.androidplatform.net",
];
const baseCorsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (origin && !allowedOrigins.includes(origin)) {
    return new Response(JSON.stringify({ success: false, message: "Origen no permitido." }), {
      status: 403,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  }
  const corsHeaders = { ...baseCorsHeaders, "Access-Control-Allow-Origin": origin || allowedOrigins[0] };
  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ success: false, message: "Método no permitido." }, 405);

  try {
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return respond({ success: false, message: "Solicitud no válida." }, 400);
    }

    // Honeypot para reducir envíos automatizados.
    if (typeof body.website === "string" && body.website.trim()) {
      return respond({ success: true, message: "Solicitud recibida." }, 200);
    }

    const nickname = String(body.nickname ?? "").trim().replace(/[\u0000-\u001f\u007f]/g, "");
    const email = String(body.contact_email ?? "").trim().toLowerCase();
    const accountType = String(body.account_type ?? "");
    const details = String(body.details ?? "").trim();

    if (nickname.length < 2 || nickname.length > 25) {
      return respond({ success: false, message: "El Nick debe tener entre 2 y 25 caracteres." }, 400);
    }
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return respond({ success: false, message: "Ingresá un correo electrónico válido para contactarte." }, 400);
    }
    if (!["registered", "guest"].includes(accountType)) {
      return respond({ success: false, message: "Seleccioná el tipo de cuenta." }, 400);
    }
    if (details.length > 500) {
      return respond({ success: false, message: "El detalle no puede superar los 500 caracteres." }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) {
      console.error("Falta la configuración del servicio de solicitudes.");
      return respond({ success: false, message: "El servicio no está disponible. Escribinos por correo." }, 503);
    }

    const adminDb = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count, error: rateError } = await adminDb
      .from("account_deletion_requests")
      .select("id", { count: "exact", head: true })
      .ilike("contact_email", email)
      .ilike("nickname", nickname)
      .gte("created_at", since);
    if (rateError) throw rateError;
    if ((count ?? 0) >= 3) {
      return respond({ success: false, message: "Ya recibimos varias solicitudes para esos datos. Contactanos por correo si necesitás ayuda." }, 429);
    }

    const { data, error } = await adminDb
      .from("account_deletion_requests")
      .insert({
        nickname,
        contact_email: email,
        account_type: accountType,
        details,
      })
      .select("id")
      .single();
    if (error) throw error;

    return respond({
      success: true,
      request_id: data.id,
      message: "Tu solicitud quedó registrada. El responsable revisará los datos para verificar la titularidad y coordinar la eliminación.",
    });
  } catch (error) {
    console.error("Error registrando solicitud de eliminación:", error);
    return respond({ success: false, message: "No pudimos registrar la solicitud. Volvé a intentarlo o escribinos por correo." }, 500);
  }
});
