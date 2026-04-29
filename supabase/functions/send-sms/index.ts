// Edge function : send-sms (Twilio)
// Envoie un SMS via Twilio. Utilisé pour les missions urgentes et les alertes critiques.
//
// Secrets requis :
//   TWILIO_ACCOUNT_SID
//   TWILIO_AUTH_TOKEN
//   TWILIO_PHONE_NUMBER (format E.164, ex: +33757592xxx)
//
// Secrets optionnels (CP-LITIGES-7a FIX 20 — préfixe configurable) :
//   SMS_PREFIX_DEFAULT      défaut "Jolene: "
//   SMS_PREFIX_OVERRIDES    JSON {type: prefix}, ex :
//                           {"LITIGE_SECURITE":"Jolene-URGENT: "}

import { createClient } from "npm:@supabase/supabase-js@2";
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

// ═══ [FIX 20] Préfixe SMS configurable ═══════════════════════════
// Appelé par le handler et testé unitairement (export via globalThis).
const SMS_PREFIX_DEFAULT = Deno.env.get("SMS_PREFIX_DEFAULT") ?? "Jolene: ";

let SMS_PREFIX_OVERRIDES: Record<string, string> = {};
try {
  const raw = Deno.env.get("SMS_PREFIX_OVERRIDES");
  if (raw && raw.trim().length > 0) {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      SMS_PREFIX_OVERRIDES = parsed;
    }
  }
} catch (err) {
  console.warn("[send-sms] SMS_PREFIX_OVERRIDES JSON invalide, fallback {} :", err);
}

export function resolveSmsPrefix(
  prefixType: string | undefined | null,
  defaultPrefix: string = SMS_PREFIX_DEFAULT,
  overrides: Record<string, string> = SMS_PREFIX_OVERRIDES,
): string {
  if (prefixType && typeof prefixType === "string" && overrides[prefixType]) {
    return overrides[prefixType];
  }
  return defaultPrefix;
}

const SMS_MAX_LENGTH = 160;

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

    // Rate-limit IP : 5 SMS/min/IP (anti-spam, coût direct Twilio).
    if (applyRateLimit('send-sms', getClientIp(req), { max: 5, windowMs: 60_000 })) {
      return new Response(JSON.stringify({ error: 'Trop de SMS envoyés. Réessayez dans 1 minute.' }), {
        status: 429,
        headers: corsHeaders(req),
      });
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
    const { telephone, type, contenu, destinataire_id, prefix_type } = body;

    if (!telephone || !contenu) {
      return new Response(JSON.stringify({ error: "telephone et contenu requis" }), {
        status: 400, headers: corsHeaders(req),
      });
    }

    // [J2.3.A] Vérification préférences notifications (canal SMS)
    if (destinataire_id && type) {
      const TYPE_TO_EVENT: Record<string, string> = {
        'SMS_MISSION_URGENTE': 'URGENCE',
        'SMS_ANNULATION_TARDIVE': 'URGENCE',
        'LITIGE_OUVERTURE': 'LITIGE_OUVERT',
        'LITIGE_RAPPEL_J1': 'LITIGE_OUVERT',
        'LITIGE_RAPPEL_J3': 'LITIGE_OUVERT',
        'LITIGE_RAPPEL_J5': 'LITIGE_OUVERT',
        'REMBOURSEMENT_CONFIRME': 'PAIEMENT_RECU',
      };
      const typeEvenement = TYPE_TO_EVENT[type] || null;
      if (typeEvenement) {
        const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
        const { data: should } = await sb.rpc('fn_doit_notifier' as any, {
          p_utilisateur_id: destinataire_id,
          p_type_evenement: typeEvenement,
          p_canal: 'SMS',
        });
        if (should === false) {
          await sb.from('journaux_audit').insert({
            acteur_id: null, type_acteur: 'SYSTEME',
            action: 'NOTIFICATION_SKIPPED', type_ressource: 'sms',
            id_ressource: destinataire_id,
            details: { type, type_evenement: typeEvenement, canal: 'SMS', raison: 'preference_user_off' },
          }).then(() => {}).catch(() => {});
          return new Response(JSON.stringify({ success: true, skipped: true, reason: 'preference_user_off' }), {
            status: 200, headers: corsHeaders(req),
          });
        }
      }
    }

    // Formater le numéro en E.164
    let to = telephone.replace(/\s/g, "").replace(/^0/, "+33");
    if (!to.startsWith("+")) to = "+33" + to;

    // Appeler l'API Twilio
    const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
    const credentials = btoa(`${accountSid}:${authToken}`);

    // [FIX 20] Préfixe résolu via prefix_type (override) ou DEFAULT
    const prefix = resolveSmsPrefix(prefix_type);
    const maxBodyLen = Math.max(20, SMS_MAX_LENGTH - prefix.length);
    const smsBody = contenu.length > maxBodyLen
      ? contenu.substring(0, maxBodyLen - 3) + "..."
      : contenu;
    const fullBody = `${prefix}${smsBody}`;

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
