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

import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import {
  resolveOperationalTestAccount,
  resolveOperationalTestSource,
} from '../_shared/test-account.ts';

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

function toE164(raw: string): string | null {
  let value = raw.replace(/[\s().-]/g, '');
  if (value.startsWith('00')) value = `+${value.slice(2)}`;
  if (value.startsWith('0')) value = `+33${value.slice(1)}`;
  if (!value.startsWith('+')) value = `+33${value}`;
  return /^\+[1-9]\d{7,14}$/.test(value) ? value : null;
}

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

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) {
      return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);
    }

    // Le healthcheck Twilio est lui aussi protege : il divulgue l'etat d'un
    // fournisseur payant et ne doit pas servir de ping public.
    if (body.warm === true) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return jsonResponse(req, { error: adminAuth.error }, adminAuth.status);
      return jsonResponse(req, { warm: true });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return jsonResponse(req, { error: 'Configuration serveur incomplete' }, 500);
    }
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const type = typeof body.type === 'string' ? body.type.trim().slice(0, 80) : 'CUSTOM';
    const destinataireId = typeof body.destinataire_id === 'string' ? body.destinataire_id : null;
    const telephoneRaw = typeof body.telephone === 'string' ? body.telephone : '';
    const contenuRaw = typeof body.contenu === 'string'
      ? body.contenu
      : (typeof body.message === 'string' ? body.message : '');
    const prefixType = typeof body.prefix_type === 'string' ? body.prefix_type.slice(0, 80) : null;
    const idempotencyKey = typeof body.idempotency_key === 'string'
      ? body.idempotency_key.trim()
      : null;
    const telephone = toE164(telephoneRaw);

    if (!telephone || !contenuRaw.trim()) {
      return jsonResponse(req, { error: 'telephone E.164 et contenu requis' }, 400);
    }
    if (contenuRaw.length > 1000) {
      return jsonResponse(req, { error: 'contenu trop long' }, 413);
    }
    const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (destinataireId && !UUID_REGEX.test(destinataireId)) {
      return jsonResponse(req, { error: 'destinataire_id invalide' }, 400);
    }
    if (idempotencyKey && !IDEMPOTENCY_KEY_PATTERN.test(idempotencyKey)) {
      return jsonResponse(req, { error: 'idempotency_key invalide' }, 400);
    }
    if (auth.isServiceRole && !idempotencyKey) {
      return jsonResponse(req, {
        error: 'idempotency_key requise pour un appel interne',
      }, 400);
    }

    // Les appels navigateur sont limites a deux cas metier explicites. Les
    // crons/triggers continuent a passer par le secret interne strict.
    let estAdminActif = false;
    let etablissementId: string | null = null;
    if (!auth.isServiceRole) {
      if (auth.role === 'ADMIN' || auth.role === 'ADMIN_PLATEFORME') {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return jsonResponse(req, { error: adminAuth.error }, adminAuth.status);
        estAdminActif = true;
        if (type !== 'TEST_ADMIN') {
          return jsonResponse(req, { error: 'Type SMS interdit depuis le navigateur admin' }, 403);
        }
      } else {
        if (type !== 'MISSION_URGENTE') {
          return jsonResponse(req, { error: 'Type SMS interdit depuis le navigateur' }, 403);
        }
        const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
        const userClient = createClient(supabaseUrl, anonKey, {
          auth: { persistSession: false },
          global: { headers: { Authorization: `Bearer ${bearer}` } },
        });
        const { data: permissions, error: permissionError } = await userClient
          .rpc('fn_mes_permissions_etab', { p_etablissement_id: null });
        const permissionsJson = permissions as Record<string, any> | null;
        etablissementId = typeof permissionsJson?.etablissement_id === 'string'
          ? permissionsJson.etablissement_id
          : null;
        if (permissionError || !permissionsJson?.permissions?.missions || !etablissementId) {
          return jsonResponse(req, { error: 'Permission etablissement requise' }, 403);
        }

        // Une alerte urgence ne peut viser qu'un profil que la source metier
        // place effectivement dans le pool de cet etablissement.
        const { data: pool, error: poolError } = await userClient.rpc('fn_pool_urgence_etablissement', {
          p_etablissement_id: etablissementId,
        });
        const cibleDansPool = Array.isArray(pool)
          && pool.some((row: Record<string, unknown>) => row.soignant_id === destinataireId);
        if (poolError || !cibleDansPool) {
          return jsonResponse(req, { error: 'Destinataire hors du pool autorise' }, 403);
        }
      }

      // Rate-limit distribue en base + limite courte en memoire. Le secret
      // interne n'est pas limite ici : les queues et crons ont leurs propres
      // controles de volume.
      if (applyRateLimit('send-sms', `${auth.userId}:${getClientIp(req)}`, { max: 5, windowMs: 60_000 })) {
        return jsonResponse(req, { error: 'Trop de SMS envoyes. Reessayez dans 1 minute.' }, 429);
      }
      const { data: callerAllowed, error: callerLimitError } = await supabaseAdmin.rpc('fn_verifier_rate_limit', {
        p_cle: auth.userId,
        p_action: 'edge_send_sms_caller',
        p_max_tentatives: estAdminActif ? 10 : 30,
        p_fenetre_secondes: 3600,
      });
      if (callerLimitError || callerAllowed !== true) {
        return jsonResponse(req, { error: 'Limite horaire SMS atteinte' }, 429);
      }

      if (!estAdminActif) {
        if (!destinataireId || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(destinataireId)) {
          return jsonResponse(req, { error: 'destinataire_id invalide' }, 400);
        }
        const { data: cible, error: cibleError } = await supabaseAdmin
          .from('soignants')
          .select('telephone, supprime_le')
          .eq('id', destinataireId)
          .maybeSingle();
        if (cibleError || !cible || cible.supprime_le || toE164(cible.telephone || '') !== telephone) {
          return jsonResponse(req, { error: 'Destinataire non autorise' }, 403);
        }
        const { data: targetAllowed, error: targetLimitError } = await supabaseAdmin.rpc('fn_verifier_rate_limit', {
          p_cle: destinataireId,
          p_action: 'edge_send_sms_target',
          p_max_tentatives: 3,
          p_fenetre_secondes: 600,
        });
        if (targetLimitError || targetAllowed !== true) {
          return jsonResponse(req, { error: 'Ce destinataire a deja ete alerte recemment' }, 429);
        }
      }
    }

    // Aucun canal SMS externe pour les fixtures, OTP compris. Le test admin
    // sans destinataire explicite se classe avec l'identité de l'appelant ;
    // tout autre appel sans compte opérationnel identifiable échoue fermé.
    const classificationUserId = destinataireId
      || (estAdminActif ? auth.userId : null);
    if (!classificationUserId) {
      return jsonResponse(req, {
        error: 'Classification du destinataire indisponible',
      }, 503);
    }
    const testAccount = await resolveOperationalTestAccount(
      supabaseAdmin,
      classificationUserId,
    );
    if (!testAccount.ok) {
      console.error('[send-sms] classification test indisponible');
      return jsonResponse(req, {
        error: 'Classification du destinataire indisponible',
      }, 503);
    }
    if (testAccount.isTest) {
      await Promise.resolve(supabaseAdmin.from('journaux_audit').insert({
        acteur_id: null,
        type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED',
        type_ressource: 'sms',
        id_ressource: classificationUserId,
        details: {
          type,
          canal: 'SMS',
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
      body,
    );
    if (!sourceAccount.ok) {
      console.error('[send-sms] classification source test indisponible');
      return jsonResponse(req, {
        error: 'Classification de la source indisponible',
      }, 503);
    }
    if (sourceAccount.isTest) {
      await Promise.resolve(supabaseAdmin.from('journaux_audit').insert({
        acteur_id: null,
        type_acteur: 'SYSTEME',
        action: 'NOTIFICATION_SKIPPED',
        type_ressource: 'sms',
        id_ressource: classificationUserId,
        details: {
          type,
          canal: 'SMS',
          raison: 'test_source',
        },
      })).catch(() => {});
      return jsonResponse(req, {
        success: true,
        skipped: true,
        reason: 'test_source',
      });
    }

    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
    // Compat : TWILIO_FROM_NUMBER (nouveau nom standard) avec fallback
    // TWILIO_PHONE_NUMBER (ancien nom). Au moins l'un doit être défini.
    const fromNumber = Deno.env.get("TWILIO_FROM_NUMBER") || Deno.env.get("TWILIO_PHONE_NUMBER");

    if (!accountSid || !authToken || !fromNumber) {
      return jsonResponse(req, {
        success: true,
        configured: false,
        message: "SMS non configuré — Twilio pas encore activé.",
      }, 503);
    }

    // ── Opt-out global SMS d'alerte (sms_alertes_actives) ──
    // Vérifié pour les 2 cas critiques. Si le soignant a opt-out, on skip.
    if (destinataireId && (type === 'MISSION_URGENTE' || type === 'RAPPEL_MISSION_J1')) {
      const { data: soignant } = await supabaseAdmin
        .from('soignants')
        .select('sms_actif, sms_alertes_actives')
        .eq('id', destinataireId)
        .maybeSingle();

      // Cumulatif : sms_actif (consentement initial) ET sms_alertes_actives (opt-in granulaire)
      // Si l'un des 2 est explicitement false, on skip.
      const optedOut = soignant?.sms_actif === false || soignant?.sms_alertes_actives === false;
      if (optedOut) {
        return jsonResponse(req, {
          success: true,
          skipped: true,
          reason: 'sms_opt_out',
        });
      }
    }

    // [J2.3.A] Vérification préférences notifications (canal SMS).
    // Un OTP de vérification est un message transactionnel explicitement
    // demandé par l'utilisateur. Il ne dépend pas de l'opt-in aux alertes
    // facultatives : sinon la queue pourrait acquitter un code jamais reçu.
    if (destinataireId && type && type !== 'OTP_VERIFICATION_TELEPHONE') {
      const TYPE_TO_EVENT: Record<string, string> = {
        'SMS_MISSION_URGENTE': 'URGENCE',
        'MISSION_URGENTE': 'URGENCE',
        'SMS_ANNULATION_TARDIVE': 'URGENCE',
        'RAPPEL_MISSION_J1': 'RAPPEL_J1_MISSION',
        'LITIGE_OUVERTURE': 'LITIGE_OUVERT',
        'LITIGE_RAPPEL_J1': 'LITIGE_OUVERT',
        'LITIGE_RAPPEL_J3': 'LITIGE_OUVERT',
        'LITIGE_RAPPEL_J5': 'LITIGE_OUVERT',
        'REMBOURSEMENT_CONFIRME': 'PAIEMENT_RECU',
      };
      const typeEvenement = TYPE_TO_EVENT[type] || null;
      if (typeEvenement) {
        const { data: should, error: preferenceError } = await supabaseAdmin.rpc('fn_doit_notifier' as any, {
          p_utilisateur_id: destinataireId,
          p_type_evenement: typeEvenement,
          p_canal: 'SMS',
        });
        if (preferenceError || typeof should !== 'boolean') {
          return jsonResponse(req, { error: 'Verification des preferences indisponible' }, 503);
        }
        if (should === false) {
          await Promise.resolve(supabaseAdmin.from('journaux_audit').insert({
            acteur_id: null, type_acteur: 'SYSTEME',
            action: 'NOTIFICATION_SKIPPED', type_ressource: 'sms',
            id_ressource: destinataireId,
            details: { type, type_evenement: typeEvenement, canal: 'SMS', raison: 'preference_user_off' },
          })).catch(() => {});
          return jsonResponse(req, { success: true, skipped: true, reason: 'preference_user_off' });
        }
      } else {
        const { data: preferences, error: preferenceError } = await supabaseAdmin
          .from('preferences_notifications')
          .select('canal_sms')
          .eq('utilisateur_id', destinataireId)
          .maybeSingle();
        if (preferenceError) {
          return jsonResponse(req, { error: 'Verification des preferences indisponible' }, 503);
        }
        // Le defaut produit pour SMS est OFF lorsqu'aucun choix explicite
        // n'existe. Les urgences mappees restent non desactivables via la RPC.
        if (preferences?.canal_sms !== true) {
          return jsonResponse(req, { success: true, skipped: true, reason: 'preference_user_off' });
        }
      }
    }

    // Formater le numéro en E.164
    const to = telephone;

    // Appeler l'API Twilio
    const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
    const credentials = btoa(`${accountSid}:${authToken}`);

    // [FIX 20] Préfixe résolu via prefix_type (override) ou DEFAULT
    const prefix = resolveSmsPrefix(prefixType);
    const maxBodyLen = Math.max(20, SMS_MAX_LENGTH - prefix.length);
    const contenu = contenuRaw.trim();
    const smsBody = contenu.length > maxBodyLen
      ? contenu.substring(0, maxBodyLen - 3) + "..."
      : contenu;
    const fullBody = `${prefix}${smsBody}`;

    let requestFingerprint: string | null = null;
    if (idempotencyKey) {
      requestFingerprint = await sha256Hex(JSON.stringify({
        type,
        destinataire_id: destinataireId,
        telephone: to,
        contenu: fullBody,
      }));
      const { data: reservation, error: reservationError } =
        await supabaseAdmin.rpc('fn_reserver_envoi_sms_idempotent', {
          p_idempotency_key: idempotencyKey,
          p_request_fingerprint: requestFingerprint,
        });
      if (reservationError) {
        console.error('[send-sms] réservation idempotente indisponible');
        return jsonResponse(req, {
          error: 'Réservation SMS indisponible',
        }, 503);
      }

      const reservationStatus = (reservation as Record<string, unknown> | null)
        ?.statut;
      if (reservationStatus === 'CONFLIT') {
        return jsonResponse(req, {
          error: 'idempotency_key déjà utilisée avec un autre SMS',
        }, 409);
      }
      if (reservationStatus === 'DEJA_ENVOYE') {
        return jsonResponse(req, {
          success: true,
          skipped: true,
          idempotent: true,
          sid: (reservation as Record<string, unknown>)?.provider_id ?? null,
          to,
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
        console.error('[send-sms] statut de réservation inattendu');
        return jsonResponse(req, {
          error: 'Réservation SMS incohérente',
        }, 503);
      }
    }

    const finalizeIdempotency = async (
      status: 'ENVOYE' | 'ERREUR' | 'INDETERMINE',
      providerId: string | null,
      error: string | null,
    ): Promise<void> => {
      if (!idempotencyKey || !requestFingerprint) return;
      const { error: finalizationError } = await supabaseAdmin.rpc(
        'fn_finaliser_envoi_sms_idempotent',
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
          `SMS_IDEMPOTENCY_FINALIZATION_FAILED:${finalizationError.message}`,
        );
      }
    };

    let twilioRes: Response;
    let twilioData: Record<string, any>;
    try {
      twilioRes = await fetch(twilioUrl, {
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
      twilioData = await twilioRes.json();
    } catch (twilioError) {
      const message = twilioError instanceof Error
        ? twilioError.message
        : 'réponse Twilio indéterminée';
      try {
        await finalizeIdempotency('INDETERMINE', null, message);
      } catch (finalizationError) {
        console.error('[send-sms] finalisation indéterminée impossible', finalizationError);
      }
      return jsonResponse(req, {
        success: false,
        pending: true,
        error: 'Résultat Twilio indéterminé, aucun renvoi automatique',
      }, 503);
    }

    if (!twilioRes.ok) {
      const providerError = twilioData.message || JSON.stringify(twilioData);
      const ambiguousProviderFailure = twilioRes.status >= 500;
      try {
        await finalizeIdempotency(
          ambiguousProviderFailure ? 'INDETERMINE' : 'ERREUR',
          null,
          providerError,
        );
      } catch (finalizationError) {
        console.error('[send-sms] finalisation échec impossible', finalizationError);
        return jsonResponse(req, {
          success: false,
          pending: true,
          error: 'Échec Twilio non finalisé',
        }, 503);
      }
      console.error("Twilio error:", twilioData);
      if (ambiguousProviderFailure) {
        return jsonResponse(req, {
          success: false,
          pending: true,
          error: 'Résultat Twilio 5xx indéterminé, aucun renvoi automatique',
        }, 503);
      }
      return jsonResponse(req, {
        success: false,
        error: twilioData.message || "Erreur envoi SMS",
      }, 502);
    }

    const providerId = typeof twilioData.sid === 'string' && twilioData.sid
      ? twilioData.sid
      : null;
    if (!providerId) {
      try {
        await finalizeIdempotency(
          'INDETERMINE',
          null,
          'Réponse Twilio 2xx sans SID',
        );
      } catch (finalizationError) {
        console.error('[send-sms] finalisation sans SID impossible', finalizationError);
      }
      return jsonResponse(req, {
        success: false,
        pending: true,
        error: 'Réponse Twilio sans identifiant fournisseur',
      }, 503);
    }

    try {
      await finalizeIdempotency('ENVOYE', providerId, null);
    } catch (finalizationError) {
      // Twilio a accepté le SMS, mais la réservation reste EN_COURS. Les
      // tentatives suivantes renverront pending et ne rappelleront pas Twilio.
      console.error('[send-sms] succès Twilio non finalisé', finalizationError);
      return jsonResponse(req, {
        success: false,
        pending: true,
        error: 'SMS accepté mais acquittement interne incomplet',
      }, 503);
    }

    // Logger dans sms_envoyes. Un OTP ne doit jamais rester en clair dans les
    // journaux applicatifs après son envoi ; Twilio reçoit le message réel,
    // tandis que la base ne conserve qu'une trace expurgée. Le registre privé
    // ci-dessus reste la source d'idempotence si cet audit échoue.
    const contenuJournal = type === 'OTP_VERIFICATION_TELEPHONE'
      ? `${prefix}[CODE OTP MASQUÉ]`
      : fullBody;
    const { error: auditError } = await supabaseAdmin.from("sms_envoyes")
      .insert({
        destinataire_id: destinataireId || null,
        telephone: to,
        type: type || "CUSTOM",
        contenu: contenuJournal,
        provider_id: providerId,
        statut: "ENVOYE",
        erreur: null,
        cout_eur: twilioData.price
          ? Math.abs(parseFloat(twilioData.price))
          : 0.07,
        idempotency_key: idempotencyKey,
      } as any);
    if (auditError) {
      console.error('[send-sms] audit sms_envoyes non écrit', auditError.message);
    }

    return jsonResponse(req, {
      success: true,
      sid: providerId,
      to,
    });
  } catch (err: unknown) {
    console.error("send-sms error:", err);
    return jsonResponse(req, { error: "Erreur interne" }, 500);
  }
});
