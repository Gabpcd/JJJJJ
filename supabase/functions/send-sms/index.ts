// Edge function : send-sms (Twilio)
// Envoie un SMS via Twilio. Utilisé pour les missions urgentes et les alertes critiques.
//
// Secrets requis :
//   TWILIO_ACCOUNT_SID
//   TWILIO_AUTH_TOKEN
//   TWILIO_PHONE_NUMBER (format E.164, ex: +33757592xxx)

import { createClient } from "npm:@supabase/supabase-js@2";

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Content-Type": "application/json",
    };
  }
  return {
    "Access-Control-Allow-Origin": "https://jolene.app",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    // Warm ping
    const bodyRaw = await req.clone().json().catch(() => ({}));
    if (bodyRaw?.warm === true) {
      return new Response(JSON.stringify({ warm: true }), { headers: corsHeaders(req) });
    }

    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
    const fromNumber = Deno.env.get("TWILIO_PHONE_NUMBER");

    if (!accountSid || !authToken || !fromNumber) {
      return new Response(JSON.stringify({
        success: true,
        configured: false,
        message: "SMS non configuré — Twilio pas encore activé.",
      }), { status: 200, headers: corsHeaders(req) });
    }

    const body = await req.json();
    const { telephone, type, contenu, destinataire_id } = body;

    if (!telephone || !contenu) {
      return new Response(JSON.stringify({ error: "telephone et contenu requis" }), {
        status: 400, headers: corsHeaders(req),
      });
    }

    // Formater le numéro en E.164
    let to = telephone.replace(/\s/g, "").replace(/^0/, "+33");
    if (!to.startsWith("+")) to = "+33" + to;

    // Appeler l'API Twilio
    const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
    const credentials = btoa(`${accountSid}:${authToken}`);

    // Tronquer le contenu à 160 caractères (1 SMS)
    const smsBody = contenu.length > 155 ? contenu.substring(0, 152) + "..." : contenu;
    const fullBody = `Jolene: ${smsBody}`;

    const twilioRes = await fetch(twilioUrl, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${credentials}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        To: to,
        From: fromNumber,
        Body: fullBody,
      }),
    });

    const twilioData = await twilioRes.json();

    // Logger dans sms_envoyes
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    try {
      await supabaseAdmin.from("sms_envoyes").insert({
        destinataire_id: destinataire_id || null,
        telephone: to,
        type: type || "CUSTOM",
        contenu: fullBody,
        provider_id: twilioData.sid || null,
        statut: twilioRes.ok ? "ENVOYE" : "ERREUR",
        erreur: twilioRes.ok ? null : (twilioData.message || JSON.stringify(twilioData)),
        cout_eur: twilioData.price ? Math.abs(parseFloat(twilioData.price)) : 0.07,
      } as any);
    } catch (_) { /* audit log best-effort */ }

    if (!twilioRes.ok) {
      console.error("Twilio error:", twilioData);
      return new Response(JSON.stringify({
        success: false,
        error: twilioData.message || "Erreur envoi SMS",
      }), { status: 200, headers: corsHeaders(req) });
    }

    return new Response(JSON.stringify({
      success: true,
      sid: twilioData.sid,
      to,
    }), { status: 200, headers: corsHeaders(req) });
  } catch (err: unknown) {
    console.error("send-sms error:", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Erreur interne" }), {
      status: 500, headers: corsHeaders(req),
    });
  }
});
