import { configurationDebitEmail, creerBudgetEnvoi, transportInterrompu, type BudgetEnvoi } from "../_shared/email-cron-budget.ts";
import { TYPES_ALERTES_FILTRES, traiterAlerteFiltres, resultatEnvoiEmail } from "../_shared/alertes-filtres-queue.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  cronAuthErrorResponse,
  cronAuthProbeResponse,
  isCronAuthProbe,
  verifyCronServiceAuth,
} from "../_shared/cron-service-auth.ts";
const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function canonicalizeJson(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalizeJson);
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.keys(record)
        .sort()
        .filter((key) => record[key] !== undefined)
        .map((key) => [key, canonicalizeJson(record[key])]),
    );
  }
  return value;
}

async function emailIdempotencyKey(
  scope: string,
  identity: unknown,
  body: Record<string, unknown>,
): Promise<string> {
  const serialized = JSON.stringify(canonicalizeJson({ identity, body }));
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(serialized),
  );
  const hex = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `cron.${scope}.${hex}`;
}

async function invokeIdempotentEmail(
  sb: any,
  scope: string,
  identity: unknown,
  body: Record<string, unknown>,
  budget?: BudgetEnvoi,
): Promise<"sent" | "skipped" | "pending"> {
  const idempotencyKey = await emailIdempotencyKey(scope, identity, body);
  const timeout = budget ? await budget.reserver() : undefined;
  if (timeout === null) return "pending";
  const { data, error } = await sb.functions.invoke("send-email", {
    ...(timeout ? { timeout } : {}),
    body: { ...body, idempotency_key: idempotencyKey },
  });
  if (transportInterrompu(error)) return "pending";
  if (error) throw new Error(`send-email ${scope}: ${error.message}`);
  return resultatEnvoiEmail(data);
}

async function invokeIdempotentSms(
  sb: any,
  idempotencyKey: string,
  body: Record<string, unknown>,
  budget?: BudgetEnvoi,
): Promise<"sent" | "skipped" | "pending"> {
  const timeout = budget ? await budget.reserver() : undefined;
  if (timeout === null) return "pending";
  const { data, error } = await sb.functions.invoke("send-sms", {
    ...(timeout ? { timeout } : {}),
    body: { ...body, idempotency_key: idempotencyKey },
    headers: { Authorization: `Bearer ${KEY}` },
  });
  if (transportInterrompu(error)) return "pending";
  if (error) throw new Error(`send-sms: ${error.message}`);
  if (data?.pending === true) return "pending";
  if (data?.success !== true) {
    throw new Error("send-sms: réponse invalide");
  }
  return data?.skipped === true ? "skipped" : "sent";
}

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  let deadline = Infinity;
  try {
    // Les appels Edge -> Edge doivent toujours porter explicitement le secret
    // interne. Sans cet en-tete, functions.invoke peut n'envoyer que `apikey`
    // selon la version du client et send-sms rejette alors justement l'appel.
    const sb = createClient(URL, KEY, {
      auth: { persistSession: false },
      global: {
        headers: { Authorization: `Bearer ${KEY}` },
        fetch: (input, init) => {
          if (!Number.isFinite(deadline)) return fetch(input, init);
          const timeout = AbortSignal.timeout(Math.max(1, deadline - Date.now()));
          const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
          return fetch(input, { ...init, signal });
        },
      },
    });

    const auth = await verifyCronServiceAuth(req, sb);
    if (!auth.ok) return cronAuthErrorResponse(auth);
    if (isCronAuthProbe(req)) return cronAuthProbeResponse(auth);

    const payload = await req.json().catch(() => ({})) as { mode?: unknown };
    const mode = payload.mode === "hourly" || payload.mode === "daily"
      ? payload.mode
      : "all";
    const runHourly = mode !== "daily";
    const runDaily = mode !== "hourly";
    const debit = configurationDebitEmail(cle => Deno.env.get(cle));
    const budget = runHourly && !runDaily ? creerBudgetEnvoi(startedAt, debit.budgetMs) : undefined;
    // Garde un délai pour enregistrer les acquittements avant le timeout pg_net.
    if (budget) deadline = startedAt + 45_000;
    const results: Record<string, unknown> = {};
    if (runDaily) {
    const { data: r1, error: r1Error } = await sb.rpc("fn_email_rappels_j1");
    if (r1Error) throw new Error(`fn_email_rappels_j1: ${r1Error.message}`);
    let c = 0;
    let smsJ1 = 0;
    let smsJ1Errors = 0;
    for (const r of r1 || []) {
      // Email rappel J-1 (existant)
      const rappelBody = {
        type: "RAPPEL_MISSION",
        destinataire_id: r.soignant_id,
        data: {
          prenom: r.prenom,
          mission: r.mission,
          etablissement: r.etablissement,
          heure_debut: r.heure_debut,
        },
      };
      const emailOutcome = await invokeIdempotentEmail(
        sb,
        "rappel_mission_j1",
        {
          soignant_id: r.soignant_id,
          jour: new Date().toISOString().slice(0, 10),
        },
        rappelBody,
      );
      if (emailOutcome !== "pending") c++;

      // SMS rappel J-1 en parallèle, best-effort. send-sms vérifie sms_actif AND
      // sms_alertes_actives côté serveur — on filtre déjà ici sur la présence
      // du téléphone pour éviter un appel inutile.
      try {
        const { data: soignant } = await sb.from('soignants')
          .select('telephone, sms_actif, sms_alertes_actives, est_compte_test')
          .eq('id', r.soignant_id)
          .maybeSingle();
        const optedIn = !!soignant?.telephone
          && soignant?.sms_actif !== false
          && soignant?.sms_alertes_actives !== false
          && soignant?.est_compte_test !== true;
        if (optedIn) {
          const intitule = (r.mission || '').toString().slice(0, 40);
          const etab = (r.etablissement || '').toString().slice(0, 30);
          const smsBody = `📅 Rappel : votre mission ${intitule} démarre demain à ${r.heure_debut} chez ${etab}. Bonne journée !`;
          const smsPayload = {
              type: 'RAPPEL_MISSION_J1',
              destinataire_id: r.soignant_id,
              telephone: soignant.telephone,
              contenu: smsBody,
              prefix_type: 'RAPPEL_MISSION_J1',
          };
          const smsIdempotencyKey = await emailIdempotencyKey(
            'sms_rappel_mission_j1',
            {
              soignant_id: r.soignant_id,
              jour: new Date().toISOString().slice(0, 10),
              mission: r.mission,
              etablissement: r.etablissement,
              heure_debut: r.heure_debut,
            },
            smsPayload,
          );
          const smsOutcome = await invokeIdempotentSms(
            sb,
            smsIdempotencyKey,
            smsPayload,
          );
          if (smsOutcome === 'pending') {
            throw new Error('send-sms: acquittement indéterminé');
          }
          smsJ1++;
        }
      } catch (e) {
        smsJ1Errors++;
        console.warn('[email-cron] SMS rappel J-1 failed for', r.soignant_id, e);
      }
    }
    results.rappels_j1 = c;
    results.rappels_j1_sms = smsJ1;
    results.rappels_j1_sms_erreurs = smsJ1Errors;
    const { data: v2, error: v2Error } = await sb.rpc("fn_verifier_documents_expirants");
    if (v2Error) throw new Error(`fn_verifier_documents_expirants: ${v2Error.message}`);
    results.docs_expirants = v2 || 0;
    const { data: v3, error: v3Error } = await sb.rpc("fn_auto_facturation_mensuelle");
    if (v3Error) throw new Error(`fn_auto_facturation_mensuelle: ${v3Error.message}`);
    results.factures = v3 || 0;
    const { data: v4, error: v4Error } = await sb.rpc("fn_purger_gps_ancien");
    if (v4Error) throw new Error(`fn_purger_gps_ancien: ${v4Error.message}`);
    results.purge_gps = v4 || 0;
    const { data: v5, error: v5Error } = await sb.rpc("fn_nettoyer_tokens_push");
    if (v5Error) throw new Error(`fn_nettoyer_tokens_push: ${v5Error.message}`);
    results.tokens_push = v5 || 0;

    // [J2.1.B.2.3.B] Rappels J-1 contrat de travail SALARIE
    let contratTravailRappels = 0;
    let contratTravailErreurs = 0;
    try {
      const { data: missionsManquantes, error: missionsManquantesError } =
        await sb.rpc("fn_lister_missions_contrat_travail_manquant");
      if (missionsManquantesError) throw missionsManquantesError;
      for (const mission of (missionsManquantes as any[]) || []) {
        const dateDebut = mission.debut_le ? new Date(mission.debut_le).toLocaleDateString('fr-FR') : 'demain';
        const intitule = mission.intitule || 'mission';
        let etabEnvoye = false;
        let soignantEnvoye = false;
        // Email étab
        try {
          const etabBody = {
            type: 'CONTRAT_TRAVAIL_RAPPEL_ETAB',
            destinataire_id: mission.etablissement_id,
            data: {
              intitule_mission: intitule,
              prenom_soignant: mission.prenom_soignant,
              nom_soignant: mission.nom_soignant,
              date_debut: dateDebut,
              mission_id: mission.mission_id,
            },
          };
          const etabOutcome = await invokeIdempotentEmail(
            sb,
            "contrat_travail_etab",
            { mission_id: mission.mission_id, cible: "etablissement" },
            etabBody,
          );
          etabEnvoye = etabOutcome !== "pending";
        } catch (e) {
          contratTravailErreurs++;
          console.warn('email étab fail', e);
        }
        // Email soignant
        try {
          const soignantBody = {
            type: 'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT',
            destinataire_id: mission.soignant_id,
            data: {
              prenom: mission.prenom_soignant,
              nom_etablissement: mission.nom_etablissement,
              intitule_mission: intitule,
              date_debut: dateDebut,
              mission_id: mission.mission_id,
            },
          };
          const soignantOutcome = await invokeIdempotentEmail(
            sb,
            "contrat_travail_soignant",
            { mission_id: mission.mission_id, cible: "soignant" },
            soignantBody,
          );
          soignantEnvoye = soignantOutcome !== "pending";
        } catch (e) {
          contratTravailErreurs++;
          console.warn('email soignant fail', e);
        }
        if (etabEnvoye || soignantEnvoye) {
          const { error: marquageError } = await sb.rpc(
            'fn_marquer_rappel_contrat_travail_envoye',
            {
              p_mission_id: mission.mission_id,
              p_cible_etab: etabEnvoye,
              p_cible_soignant: soignantEnvoye,
            },
          );
          if (marquageError) throw marquageError;
          contratTravailRappels++;
        }
      }
    } catch (err) {
      contratTravailErreurs++;
      console.error('Erreur rappels contrat travail:', err);
    }
    results.contrat_travail_rappels = contratTravailRappels;
    results.contrat_travail_erreurs = contratTravailErreurs;
    }

    // [J2.3.B.2] Cron envoi série email onboarding J0-J7
    if (runHourly) {
    let serieEnvoyes = 0, serieSkipped = 0, serieErreurs = 0;
    try {
      const { data: aTraiter } = await sb
        .from('serie_email_envois')
        .select('id, utilisateur_id, serie, etape, tentatives')
        .eq('statut', 'PLANIFIE')
        .lt('planifie_le', new Date().toISOString())
        .lt('tentatives', 3)
        .order('planifie_le', { ascending: true })
        .order('id')
        .limit(debit.onboarding);

      for (const envoi of (aTraiter as any[]) || []) {
        if (budget && !budget.peutCommencer()) break;
        try {
          // 1. Vérifier conditions de skip métier
          const { data: skipCheck } = await sb.rpc('fn_verifier_skip_serie_onboarding', { p_envoi_id: envoi.id });
          if (skipCheck && (skipCheck as any).skip === true) {
            await sb.from('serie_email_envois').update({
              statut: 'SKIPPED',
              skip_raison: (skipCheck as any).raison,
            }).eq('id', envoi.id);
            await sb.from('journaux_audit').insert({
              acteur_id: null, type_acteur: 'SYSTEME',
              action: 'SERIE_EMAIL_SKIPPED', type_ressource: 'serie_email_envois',
              id_ressource: envoi.id,
              details: { serie: envoi.serie, etape: envoi.etape, raison: (skipCheck as any).raison },
            });
            serieSkipped++;
            continue;
          }

          // 2. Vérifier préférences notifications utilisateur
          const { data: shouldNotify } = await sb.rpc('fn_doit_notifier', {
            p_utilisateur_id: envoi.utilisateur_id,
            p_type_evenement: 'SERIE_ONBOARDING',
            p_canal: 'EMAIL',
          });
          if (shouldNotify === false) {
            await sb.from('serie_email_envois').update({
              statut: 'SKIPPED', skip_raison: 'NOTIFICATION_DESACTIVEE',
            }).eq('id', envoi.id);
            await sb.from('journaux_audit').insert({
              acteur_id: null, type_acteur: 'SYSTEME',
              action: 'SERIE_EMAIL_SKIPPED', type_ressource: 'serie_email_envois',
              id_ressource: envoi.id,
              details: { serie: envoi.serie, etape: envoi.etape, raison: 'NOTIFICATION_DESACTIVEE' },
            });
            serieSkipped++;
            continue;
          }

          // 3. Récupérer les données dynamiques pour le template
          const { data: tplData } = await sb.rpc('fn_obtenir_donnees_template_serie', { p_envoi_id: envoi.id });

          // 4. Construire le type Resend
          const audience = envoi.serie === 'SOIGNANT_ONBOARDING' ? 'SOIGNANT' : 'ETAB';
          const emailType = `SERIE_${audience}_${envoi.etape}`;

          // 5. Invoke send-email
          const onboardingBody = {
            type: emailType,
            destinataire_id: envoi.utilisateur_id,
            data: tplData || {},
          };
          const onboardingOutcome = await invokeIdempotentEmail(
            sb,
            "serie_onboarding",
            { envoi_id: envoi.id },
            onboardingBody,
            budget,
          );
          if (onboardingOutcome === "pending") continue;

          await sb.from('serie_email_envois').update({
            statut: 'ENVOYE',
            envoye_le: new Date().toISOString(),
            tentatives: (envoi.tentatives || 0) + 1,
          }).eq('id', envoi.id);
          await sb.from('journaux_audit').insert({
            acteur_id: null, type_acteur: 'SYSTEME',
            action: 'SERIE_EMAIL_ENVOYE', type_ressource: 'serie_email_envois',
            id_ressource: envoi.id,
            details: { serie: envoi.serie, etape: envoi.etape, type: emailType },
          });
          serieEnvoyes++;

        } catch (err: any) {
          serieErreurs++;
          const newTentatives = (envoi.tentatives || 0) + 1;
          const definitif = newTentatives >= 3;
          await sb.from('serie_email_envois').update({
            statut: definitif ? 'ERREUR' : 'PLANIFIE',
            tentatives: newTentatives,
            erreur_message: err?.message || String(err),
          }).eq('id', envoi.id);
          if (definitif) {
            await sb.from('journaux_audit').insert({
              acteur_id: null, type_acteur: 'SYSTEME',
              action: 'ADMIN_ACTION', type_ressource: 'serie_email_envois',
              id_ressource: envoi.id,
              details: { event: 'SERIE_EMAIL_ERREUR_DEFINITIVE', serie: envoi.serie, etape: envoi.etape, error: err?.message },
            });
          }
          console.error(`[email-cron] Erreur série email ${envoi.id}:`, err);
        }
      }
    } catch (err) {
      serieErreurs++;
      console.error('[email-cron] Erreur globale série email:', err);
    }
    results.serie_envoyes = serieEnvoyes;
    results.serie_skipped = serieSkipped;
    results.serie_erreurs = serieErreurs;

    // Évaluation atomique + file durable. Le worker confirme sa compatibilité
    // avant que l'interface puisse proposer de nouvelles alertes établissement.
    try {
      const { data: repris, error: repriseError } = await sb.rpc('fn_reprendre_alertes_filtres');
      if (repriseError) throw repriseError;
      const { error: evaluationError } = await sb.rpc('fn_evaluer_alertes_filtres', { p_frequence: null });
      if (evaluationError) throw evaluationError;
      results.alertes_filtres_reprises = repris;
      results.alertes_filtres_erreurs = 0;
    } catch (error) {
      results.alertes_filtres_erreurs = 1;
      console.error('[email-cron] Préparation des alertes impossible', error);
    }
    }

    // [Refonte.D.1] Médiation litiges : transition automatique MEDIATION_EN_COURS > 7j → REVUE_ADMIN
    if (runDaily) {
    try {
      const { data: medRes, error: medError } =
        await sb.rpc('fn_basculer_litiges_revue_admin_timeout');
      if (medError) throw medError;
      results.litiges_basculer_revue_admin = (medRes as any)?.count ?? 0;
    } catch (err: any) {
      console.error('[email-cron] Erreur fn_basculer_litiges_revue_admin_timeout:', err?.message || err);
      results.litiges_basculer_revue_admin = -1;
    }

    // [Refonte.D.3] Email J+1 post-mission notation : scan missions TERMINEE 24-48h
    // sans notation pour rappel email aux 2 parties (idempotence via notifications_notation_j1).
    try {
      const { data: rappRes, error: rappError } =
        await sb.rpc('fn_envoyer_rappels_notation_j1');
      if (rappError) throw rappError;
      results.rappels_notation_etab = (rappRes as any)?.count_etab ?? 0;
      results.rappels_notation_soignant = (rappRes as any)?.count_soignant ?? 0;
    } catch (err: any) {
      console.error('[email-cron] Erreur fn_envoyer_rappels_notation_j1:', err?.message || err);
      results.rappels_notation_etab = -1;
      results.rappels_notation_soignant = -1;
    }
    }

    // Traiter la queue d'emails ET SMS (notifications automatiques des triggers DB)
    // [CP-C-3 D] Source de vérité : statut='EN_ATTENTE' (colonne envoye deprecated)
    if (runHourly) {
    let emailQueueCount = 0;
    let smsQueueCount = 0;
    let queueErrors = 0;
    const { data: pendingEmails, error: pendingEmailsError, count: pendingCount } = await sb
      .from('email_queue')
      .select('*', { count: 'exact' })
      .eq('statut', 'EN_ATTENTE')
      .order('cree_le')
      .order('id')
      .limit(debit.queue);
    if (pendingEmailsError) throw pendingEmailsError;
    for (const email of (pendingEmails || [])) {
      if (budget && !budget.peutCommencer()) break;
      if (TYPES_ALERTES_FILTRES.includes(email.type)) {
        try {
          const outcome = await traiterAlerteFiltres(sb, email, (body) => invokeIdempotentEmail(
            sb, 'email_queue', { email_queue_id: email.id }, body, budget,
          ));
          if (outcome === 'envoye') emailQueueCount++;
          if (outcome === 'erreur' || outcome === 'pending') queueErrors++;
        } catch (error) {
          // Pas de marquage irréversible si la validation ou le stockage tombe.
          queueErrors++;
          console.error('[email-cron] Livraison alerte à reprendre', email.id, error);
        }
        continue;
      }
      const isSmsQueueItem =
        email.type?.startsWith('SMS_') && Boolean(email.data?.telephone);
      try {
        // Si c'est un SMS (type commence par SMS_), envoyer via send-sms
        if (isSmsQueueItem) {
          const smsContenu = email.data.contenu
            ? String(email.data.contenu)
            : email.type === 'SMS_MISSION_URGENTE'
            ? `${email.data.prenom}, mission urgente dispo : ${email.data.mission}. Postulez sur jolene.app`
            : email.type === 'SMS_ANNULATION_TARDIVE'
            ? `Annulation tardive sur "${email.data.mission}". Trouvez un remplaçant sur jolene.app`
            : `Notification Jolene: ${email.data.mission || 'Voir l\'app'}`;

          const smsOutcome = await invokeIdempotentSms(
            sb,
            `email-queue.sms.${email.id}`,
            {
              telephone: email.data.telephone,
              type: email.type,
              contenu: smsContenu,
              destinataire_id: email.destinataire_id,
              data: email.data,
            },
            budget,
          );
          if (smsOutcome === 'pending') {
            queueErrors++;
            console.error(
              '[email-cron] SMS queue en état idempotent indéterminé',
              email.id,
            );
            continue;
          }
        } else {
          // Email classique
          const queueBody = {
            type: email.type,
            destinataire_id: email.destinataire_id,
            destinataire_email: email.destinataire_email,
            data: email.data,
          };
          const queueOutcome = await invokeIdempotentEmail(
            sb,
            "email_queue",
            { email_queue_id: email.id },
            queueBody,
            budget,
          );
          if (queueOutcome === "pending") continue;
        }
        const { data: markedSent, error: markSentError } = await sb
          .from('email_queue')
          .update({
            statut: 'ENVOYE',
            envoye: true,
            envoye_le: new Date().toISOString(),
          })
          .eq('id', email.id)
          .eq('statut', 'EN_ATTENTE')
          .select('id')
          .maybeSingle();
        if (markSentError || !markedSent) {
          queueErrors++;
          console.error(
            '[email-cron] envoi effectué mais marquage ENVOYE impossible; ' +
              'la ligne reste EN_ATTENTE pour une reprise idempotente',
            email.id,
            markSentError?.message || 'state conflict',
          );
          continue;
        }
        if (isSmsQueueItem) smsQueueCount++;
        else emailQueueCount++;
      } catch (err: any) {
        queueErrors++;
        const { error: markErrorError } = await sb
          .from('email_queue')
          .update({
            statut: 'ERREUR',
            erreur: err?.message || 'Erreur envoi',
          })
          .eq('id', email.id)
          .eq('statut', 'EN_ATTENTE');
        if (markErrorError) {
          console.error(
            '[email-cron] marquage ERREUR email_queue impossible',
            email.id,
            markErrorError.message,
          );
        }
      }
    }
    results.email_queue_en_attente_initial = pendingCount;
    results.email_queue_plus_ancien_secondes = pendingEmails?.[0]?.cree_le
      ? Math.max(0, Math.floor((Date.now() - Date.parse(pendingEmails[0].cree_le)) / 1000)) : 0;
    results.email_queue_lot_max = debit.queue;
    results.email_queue_budget_epuise = budget ? !budget.peutCommencer() : false;
    results.appels_transport = budget?.appels ?? null;
    results.email_queue = emailQueueCount;
    results.sms_queue = smsQueueCount;
    results.email_queue_erreurs = queueErrors;
    }

    const failures = Object.entries(results)
      .filter(([key, value]) =>
        (key.endsWith("_erreurs") && Number(value) > 0) ||
        Number(value) < 0
      )
      .map(([key]) => key);
    const success = failures.length === 0;
    const durationMs = Date.now() - startedAt;
    console.log("[email-cron] terminé", {
      request_id: requestId,
      success,
      failures,
      duration_ms: durationMs,
      results,
    });
    return new Response(
      JSON.stringify({
        success,
        request_id: requestId,
        failures,
        duration_ms: durationMs,
        results,
      }),
      {
        status: success ? 200 : 500,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
          "Access-Control-Allow-Origin": (Deno.env.get("APP_URL") || "https://jolene.app"),
        },
      },
    );
  } catch (err) {
    console.error("email-cron error:", { request_id: requestId, error: err });
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue.", request_id: requestId }),
      { status: 500, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } },
    );
  }
});
