// send-push — Dispatcher push multi-plateforme
//
// Routing par tokens_push.plateforme :
//   WEB     → web-push (RFC 8030 + VAPID)
//   IOS     → APNs direct HTTP/2 (clé .p8 Apple, JWT ES256, ZÉRO Google).
//             Aucun fallback FCM : Capacitor fournit ici un device token APNs.
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

import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import webpush from "npm:web-push@3.6.7";
import { apnsConfigured, sendApns } from "../_shared/apns-client.ts";
import { corsHeaders, jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import {
  resolveOperationalTestAccount,
  resolveOperationalTestSource,
} from "../_shared/test-account.ts";

type SafeLinkResult =
  | { provided: false; value: null }
  | { provided: true; value: string | null };

const WEB_PUSH_EXACT_HOSTS = new Set([
  'fcm.googleapis.com',
  'updates.push.services.mozilla.com',
  'notify.windows.com',
]);

function isAllowedWebPushEndpoint(raw: unknown): raw is string {
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > 2048) return false;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.username || url.password || url.port) return false;
    const host = url.hostname.toLowerCase();
    return WEB_PUSH_EXACT_HOSTS.has(host)
      || host.endsWith('.push.apple.com')
      || host.endsWith('.notify.windows.com');
  } catch {
    return false;
  }
}

function safeNotificationLink(raw: unknown): SafeLinkResult {
  if (raw === undefined || raw === null || raw === '') return { provided: false, value: null };
  if (typeof raw !== 'string' || raw.length > 500) return { provided: true, value: null };
  try {
    const isRelative = raw.startsWith('/') && !raw.startsWith('//');
    if (!isRelative && !/^https:\/\//i.test(raw)) return { provided: true, value: null };
    const url = new URL(raw, 'https://jolene.app');
    if (url.protocol !== 'https:' || url.port) return { provided: true, value: null };
    if (!['jolene.app', 'www.jolene.app'].includes(url.hostname.toLowerCase())) {
      return { provided: true, value: null };
    }
    return {
      provided: true,
      value: isRelative ? `${url.pathname}${url.search}${url.hash}` : url.toString(),
    };
  } catch {
    return { provided: true, value: null };
  }
}

const ALLOWED_DATA_KEYS = new Set([
  'mission_id', 'contrat_id', 'candidature_id', 'facture_id', 'litige_id',
  'presence_id', 'conversation_id', 'etablissement_id', 'soignant_id',
  'notification_id', 'action', 'statut', 'tab', 'source',
]);
const IDEMPOTENCY_KEY_PATTERN =
  /^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$/;

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function safeScalarData(raw: Record<string, unknown>): Record<string, string> {
  const result: Record<string, string> = {};
  let remainingBytes = 2500;
  for (const [key, value] of Object.entries(raw).slice(0, 30)) {
    if (!ALLOWED_DATA_KEYS.has(key)) continue;
    let scalar: string | null = null;
    if (typeof value === 'string' && value.length <= 500) scalar = value;
    else if (typeof value === 'number' && Number.isFinite(value)) scalar = String(value);
    else if (typeof value === 'boolean') scalar = value ? 'true' : 'false';
    if (scalar === null) continue;
    const bytes = new TextEncoder().encode(key + scalar).byteLength;
    if (bytes > remainingBytes) continue;
    result[key] = scalar;
    remainingBytes -= bytes;
  }
  return result;
}

const CANONICAL_NOTIFICATION_TYPES = new Set([
  'NOUVELLE_MISSION_MATCHANT_FILTRE', 'CANDIDATURE_RECUE',
  'CANDIDATURE_ACCEPTEE', 'MISSION_ASSIGNEE', 'RAPPEL_J1_MISSION',
  'POINTAGE_MANQUANT', 'FACTURE_EMISE', 'PAIEMENT_RECU',
  'CONTRAT_TRAVAIL_DEPOSE', 'LITIGE_OUVERT', 'LITIGE_RESOLU',
  'DOCUMENT_EXPIRANT', 'MANDAT_RE_SIGNATURE', 'SERIE_ONBOARDING',
  'URGENCE', 'NOUVEAU_SOIGNANT_MATCHANT_FILTRE',
  'FAVORI_NOUVELLE_MISSION', 'NOTATION_RAPPEL',
]);

function canonicalNotificationType(raw: string): string | null {
  if (!raw) return null;
  if (CANONICAL_NOTIFICATION_TYPES.has(raw)) return raw;
  if (raw.includes('URGENCE') || raw === 'ALERTE_ADMIN') return 'URGENCE';
  if (raw === 'MISSION_A_POURVOIR' || raw === 'MISSION_OUVERTE') {
    return 'NOUVELLE_MISSION_MATCHANT_FILTRE';
  }
  if (raw.startsWith('RAPPEL_MISSION')) return 'RAPPEL_J1_MISSION';
  if (raw.startsWith('CANDIDATURE_RECUE')) return 'CANDIDATURE_RECUE';
  if (raw.startsWith('CANDIDATURE_ACCEPTEE')) return 'CANDIDATURE_ACCEPTEE';
  if (raw.startsWith('MISSION_ASSIGNEE')) return 'MISSION_ASSIGNEE';
  if (raw.includes('POINTAGE') || raw.startsWith('DPAE_')) return 'POINTAGE_MANQUANT';
  if (raw.includes('CONTRAT')) return 'CONTRAT_TRAVAIL_DEPOSE';
  if (raw.includes('FACTURE') || raw.startsWith('AVOIR_')) return 'FACTURE_EMISE';
  if (raw.includes('PAIEMENT') || raw.startsWith('REMBOURSEMENT_')) return 'PAIEMENT_RECU';
  if (raw.startsWith('LITIGE_RESOLU')) return 'LITIGE_RESOLU';
  if (raw.startsWith('LITIGE_')) return 'LITIGE_OUVERT';
  if (raw.startsWith('DOCUMENT_')) return 'DOCUMENT_EXPIRANT';
  return null;
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
 * Envoie un push Android via FCM HTTP v1. Ne jamais lui transmettre un token
 * IOS issu de @capacitor/push-notifications : c'est un device token APNs brut,
 * pas un registration token FCM.
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
  if (req.method === "OPTIONS") {
    return preflightResponse(req);
  }

  try {
    if (req.method !== 'POST') {
      return jsonResponse(req, { error: 'Methode non autorisee' }, 405);
    }

    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return jsonResponse(req, { error: 'Configuration serveur incomplete' }, 500);
    }
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const requestBody = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!requestBody || Array.isArray(requestBody)) {
      return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);
    }

    const destinataire_id = typeof requestBody.destinataire_id === 'string' ? requestBody.destinataire_id : '';
    const titre = typeof requestBody.titre === 'string' ? requestBody.titre.trim() : '';
    const corps = typeof requestBody.corps === 'string' ? requestBody.corps.trim() : '';
    let type_evenement = typeof requestBody.type_evenement === 'string'
      ? requestBody.type_evenement.trim().slice(0, 100)
      : '';
    const dataPayload = requestBody.data && typeof requestBody.data === 'object' && !Array.isArray(requestBody.data)
      ? requestBody.data as Record<string, unknown>
      : {};
    const linkResult = safeNotificationLink(requestBody.lien ?? dataPayload.lien ?? dataPayload.url ?? dataPayload.link);
    const lien = linkResult.value;
    const safeDataPayload = safeScalarData(dataPayload);
    const channel_id = typeof requestBody.channel_id === 'string' ? requestBody.channel_id : undefined;
    const idempotencyKey = typeof requestBody.idempotency_key === 'string'
      ? requestBody.idempotency_key.trim()
      : null;

    if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(destinataire_id) || !titre) {
      return jsonResponse(req, { error: 'destinataire_id UUID et titre requis' }, 400);
    }
    if (titre.length > 120 || corps.length > 500) {
      return jsonResponse(req, { error: 'Notification trop longue' }, 413);
    }
    if (linkResult.provided && lien === null) {
      return jsonResponse(req, { error: 'Lien de notification interdit' }, 400);
    }
    if (type_evenement && !/^[A-Z0-9_:-]{1,100}$/.test(type_evenement)) {
      return jsonResponse(req, { error: 'type_evenement invalide' }, 400);
    }
    if (idempotencyKey && !IDEMPOTENCY_KEY_PATTERN.test(idempotencyKey)) {
      return jsonResponse(req, { error: 'idempotency_key invalide' }, 400);
    }

    // Depuis le navigateur, seuls un admin actif ou un membre etablissement
    // autorise a gerer les missions peuvent cibler un tiers. La cible d'un
    // etablissement doit appartenir a son pool urgence calcule en base.
    if (!auth.isServiceRole) {
      let estAdminActif = false;
      if (auth.role === 'ADMIN' || auth.role === 'ADMIN_PLATEFORME') {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return jsonResponse(req, { error: adminAuth.error }, adminAuth.status);
        estAdminActif = true;
      } else {
        const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
        const userClient = createClient(supabaseUrl, anonKey, {
          auth: { persistSession: false },
          global: { headers: { Authorization: `Bearer ${bearer}` } },
        });
        const { data: permissions, error: permissionError } = await userClient
          .rpc('fn_mes_permissions_etab', { p_etablissement_id: null });
        const permissionsJson = permissions as Record<string, any> | null;
        const etablissementId = permissionsJson?.etablissement_id as string | undefined;
        if (permissionError || !permissionsJson?.permissions?.missions || !etablissementId) {
          return jsonResponse(req, { error: 'Permission etablissement requise' }, 403);
        }
        const { data: pool, error: poolError } = await userClient.rpc('fn_pool_urgence_etablissement', {
          p_etablissement_id: etablissementId,
        });
        const cibleDansPool = Array.isArray(pool)
          && pool.some((row: Record<string, unknown>) => row.soignant_id === destinataire_id);
        if (poolError || !cibleDansPool) {
          return jsonResponse(req, { error: 'Destinataire hors du pool autorise' }, 403);
        }
        if (!type_evenement) type_evenement = 'MISSION_URGENTE';
      }

      if (applyRateLimit('send-push', `${auth.userId}:${getClientIp(req)}`, { max: 20, windowMs: 60_000 })) {
        return jsonResponse(req, { error: 'Trop de notifications. Reessayez dans une minute.' }, 429);
      }
      const { data: callerAllowed, error: callerLimitError } = await supabaseAdmin.rpc('fn_verifier_rate_limit', {
        p_cle: auth.userId,
        p_action: 'edge_send_push_caller',
        p_max_tentatives: estAdminActif ? 200 : 100,
        p_fenetre_secondes: 3600,
      });
      const { data: targetAllowed, error: targetLimitError } = await supabaseAdmin.rpc('fn_verifier_rate_limit', {
        p_cle: destinataire_id,
        p_action: 'edge_send_push_target',
        p_max_tentatives: 5,
        p_fenetre_secondes: 600,
      });
      if (callerLimitError || targetLimitError || callerAllowed !== true || targetAllowed !== true) {
        return jsonResponse(req, { error: 'Limite de notifications atteinte' }, 429);
      }
    }

    // La classification est volontairement placée après l'autorisation et les
    // quotas : un appelant ne peut ni sonder les UUID de recette, ni remplir
    // journaux_audit sans limite. Les fixtures gardent leur notification in-app
    // mais aucun token APNs/FCM/Web Push réel n'est contacté.
    const testAccount = await resolveOperationalTestAccount(
      supabaseAdmin,
      destinataire_id,
    );
    if (!testAccount.ok) {
      console.error('[send-push] classification test indisponible');
      return jsonResponse(req, {
        error: 'Classification du destinataire indisponible',
      }, 503);
    }
    if (testAccount.isTest) {
      await Promise.resolve(supabaseAdmin.from('journaux_audit').insert({
        acteur_id: null,
        type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED',
        type_ressource: 'push',
        id_ressource: destinataire_id,
        details: {
          type_evenement,
          canal: 'PUSH',
          raison: 'test_account',
        },
      })).catch(() => {});
      return jsonResponse(req, {
        success: true,
        skipped: true,
        reason: 'test_account',
      });
    }

    const sourceAccount = await resolveOperationalTestSource(
      supabaseAdmin,
      dataPayload,
    );
    if (!sourceAccount.ok) {
      console.error('[send-push] classification source test indisponible');
      return jsonResponse(req, {
        error: 'Classification de la source indisponible',
      }, 503);
    }
    if (sourceAccount.isTest) {
      await Promise.resolve(supabaseAdmin.from('journaux_audit').insert({
        acteur_id: null,
        type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED',
        type_ressource: 'push',
        id_ressource: destinataire_id,
        details: {
          type_evenement,
          canal: 'PUSH',
          raison: 'test_source',
        },
      })).catch(() => {});
      return jsonResponse(req, {
        success: true,
        skipped: true,
        reason: 'test_source',
      });
    }

    // Préférences notifications canal PUSH. Même un type absent/hors enum
    // respecte le canal global; URGENCE reste non désactivable dans la RPC.
    const canonicalType = canonicalNotificationType(type_evenement);
    let should: boolean;
    if (canonicalType) {
      const { data, error } = await supabaseAdmin.rpc('fn_doit_notifier' as any, {
        p_utilisateur_id: destinataire_id,
        p_type_evenement: canonicalType,
        p_canal: 'PUSH',
      });
      if (error || typeof data !== 'boolean') {
        console.error('[send-push] verification preferences impossible', error?.message);
        return jsonResponse(req, { error: 'Verification des preferences indisponible' }, 503);
      }
      should = data;
    } else {
      // Les evenements encore hors enum respectent au minimum le canal global
      // au lieu d'ignorer silencieusement l'erreur de cast PostgreSQL.
      const { data, error } = await supabaseAdmin
        .from('preferences_notifications')
        .select('canal_push')
        .eq('utilisateur_id', destinataire_id)
        .maybeSingle();
      if (error) {
        console.error('[send-push] lecture preference globale impossible', error.message);
        return jsonResponse(req, { error: 'Verification des preferences indisponible' }, 503);
      }
      should = data?.canal_push ?? true;
    }
    if (should === false) {
      await Promise.resolve(supabaseAdmin.from('journaux_audit').insert({
        acteur_id: null, type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED', type_ressource: 'push',
        id_ressource: destinataire_id,
        details: {
          type_evenement,
          type_evenement_canonique: canonicalType,
          canal: 'PUSH',
          raison: 'preference_user_off',
        },
      })).catch(() => {});
      return jsonResponse(req, { success: true, skipped: true, reason: 'preference_user_off' });
    }

    // Récupérer tous les tokens du destinataire (Web + IOS + ANDROID)
    const { data: tokens, error: tokensError } = await supabaseAdmin
      .from("tokens_push")
      .select("id, token, plateforme, endpoint, p256dh, auth_key")
      .eq("utilisateur_id", destinataire_id)
      .eq("actif", true);
    if (tokensError) {
      console.error('[send-push] Lecture tokens_push impossible:', tokensError.code);
      return jsonResponse(req, {
        error: 'Service de notification momentanément indisponible',
        code: 'PUSH_TOKENS_UNAVAILABLE',
      }, 503);
    }

    let sentWeb = 0;
    let sentFcm = 0;
    let sentApnsCount = 0;
    let skippedFcm = 0;
    let skippedApns = 0;
    const totalTokens = tokens?.length || 0;
    if (totalTokens === 0) {
      return jsonResponse(req, {
        success: true,
        skipped: true,
        reason: 'no_active_token',
        sent: 0,
        total: 0,
        email_fallback: false,
      });
    }
    const expiredTokenIds: string[] = [];
    const providerErrors: string[] = [];
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

    // Une configuration manquante est un échec avant tout effet : on ne livre
    // pas seulement certains appareils pour acquitter ensuite l'action.
    const requiresWeb = (tokens || []).some((token) => {
      const platform = (token.plateforme || '').toUpperCase();
      return (
        platform === 'WEB'
        || (!platform && token.endpoint && token.p256dh && token.auth_key)
      )
        && isAllowedWebPushEndpoint(token.endpoint)
        && Boolean(token.p256dh && token.auth_key);
    });
    const requiresApns = (tokens || []).some(
      (token) =>
        (token.plateforme || '').toUpperCase() === 'IOS'
        && Boolean(token.token),
    );
    const requiresFcm = (tokens || []).some(
      (token) =>
        (token.plateforme || '').toUpperCase() === 'ANDROID'
        && Boolean(token.token),
    );
    const configurationErrors = [
      requiresWeb && !vapidConfigured ? 'VAPID' : null,
      requiresApns && !apnsReady ? 'APNS' : null,
      requiresFcm && !(fcmAccessToken && firebaseProjectId) ? 'FCM' : null,
    ].filter((value): value is string => value !== null);
    if (configurationErrors.length > 0) {
      return jsonResponse(req, {
        success: false,
        error: 'Configuration push incomplète',
        code: 'PUSH_PROVIDER_NOT_CONFIGURED',
        providers: configurationErrors,
      }, 503);
    }

    const requestFingerprint = await sha256Hex(JSON.stringify({
      destinataire_id,
      titre,
      corps,
      type_evenement,
      lien,
      data: safeDataPayload,
      channel_id: auth.isServiceRole ? channel_id ?? null : null,
    }));

    if (idempotencyKey) {
      const { data: reservation, error: reservationError } =
        await supabaseAdmin.rpc('fn_reserver_envoi_push_idempotent', {
          p_idempotency_key: idempotencyKey,
          p_request_fingerprint: requestFingerprint,
        });
      if (reservationError) {
        console.error('[send-push] réservation idempotente indisponible');
        return jsonResponse(req, {
          success: false,
          error: 'Réservation push indisponible',
        }, 503);
      }

      const reservationStatus = (reservation as Record<string, unknown> | null)
        ?.statut;
      if (reservationStatus === 'CONFLIT') {
        return jsonResponse(req, {
          success: false,
          error: 'idempotency_key déjà utilisée avec un autre push',
        }, 409);
      }
      if (reservationStatus === 'DEJA_ENVOYE') {
        return jsonResponse(req, {
          success: true,
          skipped: true,
          idempotent: true,
          provider_result:
            (reservation as Record<string, unknown>)?.provider_id ?? null,
        });
      }
      if (
        reservationStatus === 'EN_COURS'
        || reservationStatus === 'INDETERMINE'
      ) {
        return jsonResponse(req, {
          success: false,
          pending: true,
          reason: String(reservationStatus).toLowerCase(),
        }, 202);
      }
      if (reservationStatus !== 'RESERVE') {
        console.error('[send-push] statut de réservation inattendu');
        return jsonResponse(req, {
          success: false,
          error: 'Réservation push incohérente',
        }, 503);
      }
    }

    const finalizeIdempotency = async (
      status: 'ENVOYE' | 'ERREUR' | 'INDETERMINE',
      providerId: string | null,
      error: string | null,
    ): Promise<void> => {
      if (!idempotencyKey) return;
      const { error: finalizationError } = await supabaseAdmin.rpc(
        'fn_finaliser_envoi_push_idempotent',
        {
          p_idempotency_key: idempotencyKey,
          p_request_fingerprint: requestFingerprint,
          p_statut: status,
          p_provider_id: providerId,
          p_erreur: error,
        },
      );
      if (finalizationError) {
        throw new Error(
          `PUSH_IDEMPOTENCY_FINALIZATION_FAILED:${finalizationError.message}`,
        );
      }
    };

    // Payload Web Push
    const webData: Record<string, string> = {
      ...safeDataPayload,
      type_evenement: type_evenement || '',
    };
    if (lien) {
      webData.url = lien;
      webData.lien = lien;
    }
    const webPayload = JSON.stringify({
      title: titre,
      body: corps || "",
      icon: "/favicon.svg",
      badge: "/icon-192x192.png",
      data: webData,
    });

    // FCM payload data (in-app navigation après tap)
    const fcmData: Record<string, string> = {
      ...safeDataPayload,
      type_evenement: type_evenement || "",
    };
    if (lien) fcmData.lien = lien;

    for (const t of tokens || []) {
      const plat = (t.plateforme || "").toUpperCase();
      try {
        if (plat === "WEB" || (!plat && t.endpoint && t.p256dh && t.auth_key)) {
          // Web Push standard
          // Revalider au moment de l'appel protege aussi les lignes historiques
          // creees avant l'allowlist fournisseur (defense en profondeur SSRF).
          if (!isAllowedWebPushEndpoint(t.endpoint)) {
            console.warn('[send-push] Endpoint Web Push hors allowlist, token desactive');
            expiredTokenIds.push(t.id);
          } else if (vapidConfigured && t.p256dh && t.auth_key) {
            await webpush.sendNotification(
              { endpoint: t.endpoint, keys: { p256dh: t.p256dh, auth: t.auth_key } },
              webPayload,
              { TTL: 86400 },
            );
            sentWeb++;
          } else {
            expiredTokenIds.push(t.id);
          }
        } else if (plat === "IOS") {
          // Capacitor iOS fournit un token APNs brut. Il ne faut jamais le
          // présenter à FCM (qui pourrait le refuser puis le faire désactiver).
          if (apnsReady && t.token) {
            const result = await sendApns({
              deviceToken: t.token,
              title: titre,
              body: corps || "",
              data: fcmData,
            });
            if (result.ok) sentApnsCount++;
            else if (result.expired) expiredTokenIds.push(t.id);
            else providerErrors.push(result.error || 'APNs provider error');
          } else {
            skippedApns++;
            expiredTokenIds.push(t.id);
          }
        } else if (plat === "ANDROID") {
          // FCM HTTP v1 — Android uniquement.
          if (fcmAccessToken && firebaseProjectId && t.token) {
            const result = await sendViaFcm({
              accessToken: fcmAccessToken,
              projectId: firebaseProjectId,
              token: t.token,
              title: titre,
              body: corps || "",
              data: fcmData,
              channelId: auth.isServiceRole && channel_id ? channel_id : channelForType(type_evenement),
            });
            if (result.ok) sentFcm++;
            else if (result.expired) expiredTokenIds.push(t.id);
            else providerErrors.push(result.error || 'FCM provider error');
          } else {
            skippedFcm++;
            expiredTokenIds.push(t.id);
          }
        } else {
          expiredTokenIds.push(t.id);
        }
      } catch (err: unknown) {
        if (err instanceof Error && (err.message.includes("404") || err.message.includes("410") || err.message.includes("expired"))) {
          expiredTokenIds.push(t.id);
        } else {
          console.error("[send-push] dispatch error:", err);
          providerErrors.push(
            err instanceof Error ? err.message : 'Push provider error',
          );
        }
      }
    }

    // Cleanup tokens expirés (404/410 Web Push ou UNREGISTERED FCM)
    if (expiredTokenIds.length > 0) {
      const { error: cleanupTokensError } = await supabaseAdmin.from("tokens_push")
        .update({ actif: false })
        .in("id", expiredTokenIds);
      if (cleanupTokensError) {
        console.error('[send-push] Desactivation tokens invalides impossible:', cleanupTokensError.code);
        try {
          await finalizeIdempotency(
            'INDETERMINE',
            null,
            'Nettoyage des abonnements push impossible après dispatch',
          );
        } catch (finalizationError) {
          console.error('[send-push] finalisation cleanup impossible', finalizationError);
        }
        return jsonResponse(req, {
          success: false,
          pending: true,
          error: 'Nettoyage des abonnements push momentanément indisponible',
          code: 'PUSH_TOKEN_CLEANUP_UNAVAILABLE',
        }, 503);
      }
    }

    const sent = sentWeb + sentFcm + sentApnsCount;
    const providerSummary = JSON.stringify({
      sent,
      sentWeb,
      sentFcm,
      sentApns: sentApnsCount,
    });

    if (providerErrors.length > 0) {
      try {
        await finalizeIdempotency(
          'INDETERMINE',
          sent > 0 ? providerSummary : null,
          providerErrors.join(' | ').slice(0, 1800),
        );
      } catch (finalizationError) {
        console.error('[send-push] finalisation fournisseur impossible', finalizationError);
      }
      return jsonResponse(req, {
        success: false,
        pending: true,
        error: 'Résultat push partiel ou indéterminé, aucun renvoi automatique',
        sent,
        total: totalTokens,
        provider_errors: providerErrors.length,
      }, 503);
    }

    if (sent > 0) {
      try {
        await finalizeIdempotency('ENVOYE', providerSummary, null);
      } catch (finalizationError) {
        console.error('[send-push] succès fournisseur non finalisé', finalizationError);
        return jsonResponse(req, {
          success: false,
          pending: true,
          error: 'Push livré mais acquittement interne incomplet',
          sent,
          total: totalTokens,
        }, 503);
      }
      return jsonResponse(req, {
        success: true,
        sent,
        sentWeb,
        sentFcm,
        sentApns: sentApnsCount,
        total: totalTokens,
        skippedFcm,
        skippedApns,
        apns_configured: apnsReady,
        fcm_configured: Boolean(fcmAccessToken),
        email_fallback: false,
      });
    }

    // Tous les tokens étaient invalides/expirés : fallback email avec sa
    // propre clé Resend, puis acquittement du dispatch push.
    const fallbackIdempotencyKey = `push-fallback.${requestFingerprint}`;
    let fallbackResponse: Response;
    let fallbackData: Record<string, any> | null;
    try {
      fallbackResponse = await fetch(
        `${supabaseUrl}/functions/v1/send-email`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${serviceRoleKey}` },
          body: JSON.stringify({
            type: "NOTIFICATION_PUSH_FALLBACK",
            destinataire_id,
            idempotency_key: fallbackIdempotencyKey,
            data: { titre, corps: corps || "", ...(lien ? { lien } : {}) },
          }),
        },
      );
      fallbackData = await fallbackResponse.json().catch(() => null);
    } catch (fallbackError) {
      try {
        await finalizeIdempotency(
          'ERREUR',
          null,
          fallbackError instanceof Error
            ? fallbackError.message
            : 'Fallback email inaccessible',
        );
      } catch (finalizationError) {
        console.error('[send-push] finalisation fallback impossible', finalizationError);
      }
      return jsonResponse(req, {
        success: false,
        error: 'Fallback email indisponible',
      }, 502);
    }

    if (
      !fallbackResponse.ok
      || fallbackData?.success !== true
      || fallbackData?.pending === true
    ) {
      const fallbackError =
        fallbackData?.error || `send-email HTTP ${fallbackResponse.status}`;
      try {
        await finalizeIdempotency('ERREUR', null, fallbackError);
      } catch (finalizationError) {
        console.error('[send-push] finalisation fallback échec impossible', finalizationError);
      }
      return jsonResponse(req, {
        success: false,
        error: 'Fallback email non confirmé',
      }, 502);
    }

    try {
      await finalizeIdempotency('ENVOYE', 'email-fallback', null);
    } catch (finalizationError) {
      console.error('[send-push] fallback livré non finalisé', finalizationError);
      return jsonResponse(req, {
        success: false,
        pending: true,
        error: 'Fallback livré mais acquittement interne incomplet',
      }, 503);
    }

    return jsonResponse(req, {
      success: true,
      sent: 0,
      sentWeb: 0,
      sentFcm: 0,
      sentApns: 0,
      total: totalTokens,
      skippedFcm,
      skippedApns,
      apns_configured: apnsReady,
      fcm_configured: Boolean(fcmAccessToken),
      email_fallback: true,
    });
  } catch (err) {
    console.error("send-push error:", err);
    return jsonResponse(req, { error: "Erreur interne" }, 500);
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
