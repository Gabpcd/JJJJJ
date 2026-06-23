// send-push — Dispatcher push multi-plateforme
//
// Routing par tokens_push.plateforme :
//   WEB     → web-push (RFC 8030 + VAPID)
//   IOS     → APNs direct HTTP/2 (clé .p8 Apple, JWT ES256, ZÉRO Google).
//             Fallback FCM v1 si APNs non configuré mais Firebase l'est.
//   ANDROID → FCM HTTP v1
//
// iOS passe par APNs direct car l'org policy GCP bloque la création de clés
// service account Firebase (cf. _shared/apns-client.ts). Android reste sur FCM
// (skip propre tant que FIREBASE_SERVICE_ACCOUNT_JSON absent) ; Web Push n'est
// jamais impacté.
//
// Secrets requis :
//   VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT   (Web Push)
//   APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID               (iOS direct)
//   APNS_BUNDLE_ID / APNS_ENVIRONMENT                      (iOS, optionnels)
//   FIREBASE_SERVICE_ACCOUNT_JSON / FIREBASE_PROJECT_ID    (Android FCM, optionnels)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
import { apnsConfigured, sendApns } from "../_shared/apns-client.ts";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

// ─── FCM HTTP v1 helper — Sprint 4 PR 1 ──────────────────────────────

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64url(input: string | Uint8Array): string {
  const b64 = typeof input === "string" ? btoa(input)
    : btoa(String.fromCharCode(...input));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Génère un OAuth2 access token Firebase via le flow service account JWT.
 * Cache 50 min (token Google valide 1h).
 */
async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const toSign = `${headerB64}.${payloadB64}`;

  const keyBuffer = pemToArrayBuffer(sa.private_key);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", keyBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", cryptoKey, new TextEncoder().encode(toSign),
  );
  const signatureB64 = base64url(new Uint8Array(signature));
  const jwt = `${toSign}.${signatureB64}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!tokenRes.ok) {
    const errText = await tokenRes.text();
    throw new Error(`FCM OAuth token failed: ${tokenRes.status} ${errText}`);
  }
  const tokenJson = await tokenRes.json();
  cachedAccessToken = {
    token: tokenJson.access_token,
    expiresAt: Date.now() + (tokenJson.expires_in - 60) * 1000,
  };
  return cachedAccessToken.token;
}

/**
 * Envoie un push via FCM HTTP v1.
 * FCM dispatche automatiquement vers APNS (iOS) si la clé p8 est uploadée
 * dans Firebase Console.
 *
 * Retourne true si succès, false si token expiré (404/UNREGISTERED).
 * Throw sur autres erreurs réseau.
 */
async function sendViaFcm(opts: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: string;
}): Promise<{ ok: boolean; expired: boolean; error?: string }> {
  const message: Record<string, unknown> = {
    token: opts.token,
    notification: { title: opts.title, body: opts.body },
    data: opts.data || {},
    android: {
      priority: "HIGH",
      notification: {
        channel_id: opts.channelId || "jolene_info",
        sound: "default",
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: { sound: "default", "mutable-content": 1 },
      },
    },
  };
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${opts.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${opts.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    },
  );
  if (res.ok) return { ok: true, expired: false };
  const errText = await res.text();
  // Token expiré / désinscrit
  if (res.status === 404 || errText.includes("UNREGISTERED") || errText.includes("registration-token-not-registered")) {
    return { ok: false, expired: true };
  }
  return { ok: false, expired: false, error: `FCM ${res.status}: ${errText.slice(0, 200)}` };
}

// ─── Edge function principale ────────────────────────────────────────

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Content-Type": "application/json",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST",
  };
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders });
    }
    const token = authHeader.replace("Bearer ", "");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // Appel server-to-server : les triggers DB / crons (match, mission assignée,
    // candidature, pointage…) appellent send-push avec la clé service_role ou le
    // secret vault sb_secret_*. Ces appels sont de confiance — on saute la
    // validation user (sinon auth.getUser(service_key) échoue → 401, ce qui
    // cassait TOUTES les notifications push déclenchées par le backend).
    // Pattern : _shared/admin-auth.ts.
    const secretKey = Deno.env.get("SUPABASE_SECRET_KEY") || Deno.env.get("SB_SECRET_KEY") || "";
    let estAppelService = (token === serviceRoleKey) || (!!secretKey && token === secretKey);
    if (!estAppelService) {
      try {
        const { data: vaultSecret } = await supabaseAdmin.rpc("fn_lire_secret_cron" as any);
        if (vaultSecret && typeof vaultSecret === "string" && token === vaultSecret) estAppelService = true;
      } catch { /* ignore — fallback sur validation user */ }
    }

    if (!estAppelService) {
      // Appel frontend : valider le token utilisateur.
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: corsHeaders });
      }
    }

    const { destinataire_id, titre, corps, lien, type_evenement, channel_id } = await req.json();
    if (!destinataire_id || !titre) {
      return new Response(JSON.stringify({ error: "destinataire_id et titre requis" }), { status: 400, headers: corsHeaders });
    }

    // Préférences notifications canal PUSH
    if (type_evenement) {
      const { data: should } = await supabaseAdmin.rpc('fn_doit_notifier' as any, {
        p_utilisateur_id: destinataire_id,
        p_type_evenement: type_evenement,
        p_canal: 'PUSH',
      });
      if (should === false) {
        await supabaseAdmin.from('journaux_audit').insert({
          acteur_id: null, type_acteur: 'SYSTEME',
          action: 'NOTIFICATION_SKIPPED', type_ressource: 'push',
          id_ressource: destinataire_id,
          details: { type_evenement, canal: 'PUSH', raison: 'preference_user_off' },
        }).then(() => {}).catch(() => {});
        return new Response(JSON.stringify({ success: true, skipped: true, reason: 'preference_user_off' }), {
          status: 200, headers: corsHeaders,
        });
      }
    }

    // Récupérer tous les tokens du destinataire (Web + IOS + ANDROID)
    const { data: tokens } = await supabaseAdmin
      .from("tokens_push")
      .select("id, token, plateforme, endpoint, p256dh, auth_key")
      .eq("utilisateur_id", destinataire_id)
      .eq("actif", true);

    let sentWeb = 0;
    let sentFcm = 0;
    let sentApnsCount = 0;
    let skippedFcm = 0;
    let skippedApns = 0;
    const totalTokens = tokens?.length || 0;
    const expiredTokenIds: string[] = [];
    const apnsReady = apnsConfigured();

    // ─── Configuration VAPID Web Push ──────────────────────────
    const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:support@jolene.app";
    const vapidConfigured = Boolean(vapidPublicKey && vapidPrivateKey);
    if (vapidConfigured) {
      webpush.setVapidDetails(vapidSubject, vapidPublicKey!, vapidPrivateKey!);
    }

    // ─── Configuration FCM (Sprint final) ──────────────────────
    const firebaseSaJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    let serviceAccount: ServiceAccount | null = null;
    let fcmAccessToken: string | null = null;
    let firebaseProjectId: string | null = null;
    if (firebaseSaJson) {
      try {
        serviceAccount = JSON.parse(firebaseSaJson) as ServiceAccount;
        firebaseProjectId = Deno.env.get("FIREBASE_PROJECT_ID") || serviceAccount.project_id;
        fcmAccessToken = await getFcmAccessToken(serviceAccount);
      } catch (e) {
        console.error("[send-push] FIREBASE_SERVICE_ACCOUNT_JSON parse/auth failed:", e);
      }
    }

    // Payload Web Push
    const webPayload = JSON.stringify({
      title: titre,
      body: corps || "",
      icon: "/favicon.svg",
      badge: "/icon-192x192.png",
      data: { url: lien || "https://jolene.app", type_evenement, ...{} },
    });

    // FCM payload data (in-app navigation après tap)
    const fcmData: Record<string, string> = {
      lien: lien || "/",
      type_evenement: type_evenement || "",
    };

    for (const t of tokens || []) {
      const plat = (t.plateforme || "").toUpperCase();
      try {
        if (plat === "WEB" || (!plat && t.endpoint && t.p256dh && t.auth_key)) {
          // Web Push standard
          if (vapidConfigured && t.endpoint && t.p256dh && t.auth_key) {
            await webpush.sendNotification(
              { endpoint: t.endpoint, keys: { p256dh: t.p256dh, auth: t.auth_key } },
              webPayload,
              { TTL: 86400 },
            );
            sentWeb++;
          }
        } else if (plat === "IOS" && apnsReady && t.token) {
          // APNs direct HTTP/2 (clé .p8 Apple, zéro Google)
          const result = await sendApns({
            deviceToken: t.token,
            title: titre,
            body: corps || "",
            data: fcmData,
          });
          if (result.ok) sentApnsCount++;
          else if (result.expired) expiredTokenIds.push(t.id);
          else console.warn("[send-push] APNs error:", result.error);
        } else if (plat === "IOS" || plat === "ANDROID") {
          // FCM HTTP v1 — Android, ou iOS en fallback si APNs non configuré
          if (fcmAccessToken && firebaseProjectId && t.token) {
            const result = await sendViaFcm({
              accessToken: fcmAccessToken,
              projectId: firebaseProjectId,
              token: t.token,
              title: titre,
              body: corps || "",
              data: fcmData,
              channelId: channel_id || channelForType(type_evenement),
            });
            if (result.ok) sentFcm++;
            else if (result.expired) expiredTokenIds.push(t.id);
            else console.warn("[send-push] FCM error:", result.error);
          } else if (plat === "IOS") {
            // Ni APNs ni FCM configurés → skip propre iOS
            skippedApns++;
          } else {
            // FIREBASE_SERVICE_ACCOUNT_JSON pas configuré → skip propre Android
            skippedFcm++;
          }
        }
      } catch (err: unknown) {
        if (err instanceof Error && (err.message.includes("404") || err.message.includes("410") || err.message.includes("expired"))) {
          expiredTokenIds.push(t.id);
        } else {
          console.error("[send-push] dispatch error:", err);
        }
      }
    }

    // Cleanup tokens expirés (404/410 Web Push ou UNREGISTERED FCM)
    if (expiredTokenIds.length > 0) {
      await supabaseAdmin.from("tokens_push")
        .update({ actif: false })
        .in("id", expiredTokenIds);
    }

    if (skippedFcm > 0) {
      console.warn(`[send-push] FCM not configured, ${skippedFcm} Android tokens skipped`);
    }
    if (skippedApns > 0) {
      console.warn(`[send-push] APNs not configured, ${skippedApns} iOS tokens skipped`);
    }

    const sent = sentWeb + sentFcm + sentApnsCount;

    // Fallback email si aucun push livré
    if (sent === 0 && totalTokens > 0) {
      try {
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        await fetch(`${supabaseUrl}/functions/v1/send-email`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${serviceRoleKey}` },
          body: JSON.stringify({
            type: "NOTIFICATION_PUSH_FALLBACK",
            destinataire_id,
            data: { titre, corps: corps || "", lien: lien || "https://jolene.app" },
          }),
        });
      } catch { /* email fallback failed silently */ }
    }

    return new Response(
      JSON.stringify({
        sent, sentWeb, sentFcm, sentApns: sentApnsCount,
        total: totalTokens, skippedFcm, skippedApns,
        apns_configured: apnsReady,
        fcm_configured: Boolean(fcmAccessToken),
        email_fallback: sent === 0 && totalTokens > 0,
      }),
      { headers: corsHeaders },
    );
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": getCorsOrigin(req) } });
  }
});

/**
 * Mapping type_evenement → channel Android (Sprint 4 PR 7 déclarera les
 * channels côté MainActivity Java/Kotlin).
 */
function channelForType(type?: string): string {
  if (!type) return "jolene_info";
  if (type.startsWith("URGENCE") || type === "POOL_URGENCE_NOTIFICATIONS_ENVOYEES") return "jolene_urgence";
  if (type.startsWith("CONTRAT")) return "jolene_signature";
  if (type.includes("PAIEMENT") || type.includes("FACTURE")) return "jolene_paiement";
  if (type === "MESSAGE_LITIGE" || type === "NOUVEAU_MESSAGE") return "jolene_messagerie";
  if (type.includes("POINTAGE") || type.includes("DPAE")) return "jolene_pointage";
  return "jolene_info";
}
