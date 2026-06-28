// process-externalisation-actions — Worker async pour Sprint 4 PR 2
//
// Cron pg_cron toutes les 5 min appelle cet endpoint en service_role.
// Lit fn_externalisations_a_traiter (pagination 50/run) pour récupérer
// les actions à dispatcher selon leur type_action.
//
// Types supportés :
//   STRIPE_REFUND_TOTAL / _PARTIEL → Stripe API refunds.create
//   STRIPE_PAYMENT                  → Stripe Connect transfers.create
//   STRIPE_PAYOUT                   → Stripe payouts.create
//   CHORUS_RECYCLER_FACTURE         → piste-client.ts (PENDING_AIFE si scope KO)
//   DPAE_ANNULATION                 → email + push étab Net-Entreprises
//   EMAIL_NOTIF                     → send-email
//   PUSH_NOTIF                      → send-push
//   AVOIR_PDF_GENERATION            → génération PDF + upload Storage
//
// Sur succès → fn_externalisation_succes
// Sur échec → fn_externalisation_echec avec backoff
// Sur PENDING_AIFE → fn_externalisation_echec(..., 'PENDING_AIFE')

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SB_SECRET_KEY") ?? "";

// Cache mémoire du secret vault (sb_secret_*) utilisé par pg_cron.
// fn_lire_secret_cron lit vault.decrypted_secrets where name='service_role_key'.
let _cachedVaultSecret: string | null = null;
async function getVaultCronSecret(sb: any): Promise<string> {
  if (_cachedVaultSecret) return _cachedVaultSecret;
  if (SUPABASE_SECRET_KEY) { _cachedVaultSecret = SUPABASE_SECRET_KEY; return SUPABASE_SECRET_KEY; }
  try {
    const { data } = await sb.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _cachedVaultSecret = data; return data; }
  } catch { /* ignore */ }
  return "";
}

function corsHeaders(req: Request) {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": req.headers.get("origin") || "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

interface ActionRow {
  id: string;
  type_action: string;
  payload: Record<string, any>;
  source: string;
  source_id: string | null;
  tentatives: number;
}

interface DispatchResult {
  ok: boolean;
  resultat?: any;
  erreur?: string;
  pending_aife?: boolean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Auth : service_role only — accepte legacy JWT (env var), nouveau sb_secret_*
  // (env var ou vault.decrypted_secrets via fn_lire_secret_cron pour pg_cron).
  const authHeader = req.headers.get("Authorization") || "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();
  const vaultSecret = await getVaultCronSecret(admin);
  const matchesLegacy = SERVICE_ROLE_KEY && bearer === SERVICE_ROLE_KEY;
  const matchesNew = vaultSecret && bearer === vaultSecret;
  if (!matchesLegacy && !matchesNew) {
    return new Response(JSON.stringify({ error: "Service role required" }),
      { status: 401, headers: corsHeaders(req) });
  }

  const workerId = `worker_${crypto.randomUUID().slice(0, 8)}`;

  // Récupérer batch
  const { data: rpcData, error: rpcErr } = await admin
    .rpc("fn_externalisations_a_traiter", { p_limit: 50, p_worker_id: workerId });
  if (rpcErr) {
    console.error("[worker] fn_externalisations_a_traiter error:", rpcErr);
    return new Response(JSON.stringify({ error: "RPC failed" }),
      { status: 500, headers: corsHeaders(req) });
  }
  const actions: ActionRow[] = (rpcData as any)?.actions || [];

  let success = 0, failed = 0, pendingAife = 0;
  const startTs = Date.now();

  for (const action of actions) {
    try {
      const result = await dispatch(admin, action);
      if (result.ok) {
        await admin.rpc("fn_externalisation_succes", { p_id: action.id, p_resultat: result.resultat || {} });
        success++;
      } else if (result.pending_aife) {
        await admin.rpc("fn_externalisation_echec", { p_id: action.id, p_erreur: result.erreur || "PENDING_AIFE", p_special_statut: "PENDING_AIFE" });
        pendingAife++;
      } else {
        await admin.rpc("fn_externalisation_echec", { p_id: action.id, p_erreur: result.erreur || "Unknown error" });
        failed++;
      }
    } catch (err) {
      console.error(`[worker] action ${action.id} threw:`, err);
      await admin.rpc("fn_externalisation_echec",
        { p_id: action.id, p_erreur: (err as Error).message?.slice(0, 500) || "Exception" });
      failed++;
    }
  }

  const durationMs = Date.now() - startTs;
  console.log(`[worker] ${workerId}: ${actions.length} actions, ${success} success, ${failed} failed, ${pendingAife} pending_aife, ${durationMs}ms`);

  return new Response(JSON.stringify({
    worker_id: workerId,
    processed: actions.length,
    success, failed, pending_aife: pendingAife, duration_ms: durationMs,
  }), { headers: corsHeaders(req) });
});

// ─── Dispatch principal ──────────────────────────────────────────────

async function dispatch(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { type_action, payload } = action;
  switch (type_action) {
    case "STRIPE_REFUND_TOTAL":
    case "STRIPE_REFUND_PARTIEL":
      return dispatchStripeRefund(admin, action);
    case "STRIPE_PAYMENT":
      return dispatchStripePayment(admin, action);
    case "STRIPE_PAYOUT":
      return dispatchStripePayout(admin, action);
    case "CHORUS_RECYCLER_FACTURE":
    case "CHORUS_RECYCLE_FACTURE":
      return dispatchChorusRecycle(admin, action);
    case "DPAE_ANNULATION":
    case "DPAE_ANNULATION_NOTIF":
      return dispatchDpaeAnnulation(admin, action);
    case "EMAIL_NOTIF":
      return dispatchEmail(admin, action);
    case "PUSH_NOTIF":
      return dispatchPush(admin, action);
    case "AVOIR_PDF_GENERATION":
      return dispatchAvoirPdf(admin, action);
    case "RECOMPENSE_PARRAINAGE_SOIGNANT":
      return dispatchRecompenseParrainage(admin, action);
    case "REMBOURSEMENT_AVOIR_SWAN":
      return dispatchRemboursementAvoirSwan(admin, action);
    default:
      return { ok: false, erreur: `Type d'action non supporté : ${type_action}` };
  }
}

// ─── Stripe ──────────────────────────────────────────────────────────

async function dispatchStripeRefund(admin: any, action: ActionRow): Promise<DispatchResult> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) return { ok: false, erreur: "STRIPE_SECRET_KEY missing" };

  const { mission_id, montant, pourcentage } = action.payload;
  if (!mission_id) return { ok: false, erreur: "mission_id missing in payload" };

  // Récupérer le payment_intent_id depuis mission ou facture
  const { data: mission } = await admin.from("missions")
    .select("paiement_id, stripe_payment_intent_id, taux_horaire_base, duree_heures")
    .eq("id", mission_id).maybeSingle();

  const piId = mission?.stripe_payment_intent_id || mission?.paiement_id;
  if (!piId) return { ok: false, erreur: `Aucun payment_intent pour mission ${mission_id}` };

  // Calculer montant remboursement (centimes)
  let amountCents: number | undefined;
  if (action.type_action === "STRIPE_REFUND_PARTIEL") {
    if (pourcentage) {
      const total = (mission?.taux_horaire_base || 0) * (mission?.duree_heures || 0) * 100;
      amountCents = Math.round(total * (pourcentage / 100));
    } else if (montant) {
      amountCents = Math.round(montant * 100);
    }
  }
  // TOTAL : ne pas spécifier amount = remboursement total

  const body = new URLSearchParams({
    payment_intent: piId,
    reason: "requested_by_customer",
    ...(amountCents ? { amount: amountCents.toString() } : {}),
  });

  const res = await fetch("https://api.stripe.com/v1/refunds", {
    method: "POST",
    headers: { "Authorization": `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const json = await res.json();
  if (res.ok) return { ok: true, resultat: { refund_id: json.id, amount: json.amount } };

  // Balance insufficient → retry plus tard (pas FAILED définitif)
  if (json.error?.code === "balance_insufficient") {
    return { ok: false, erreur: "balance_insufficient (sera retenté)" };
  }
  return { ok: false, erreur: `Stripe ${res.status}: ${json.error?.message || JSON.stringify(json)}` };
}

async function dispatchStripePayment(admin: any, action: ActionRow): Promise<DispatchResult> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) return { ok: false, erreur: "STRIPE_SECRET_KEY missing" };
  const { beneficiaire_id, montant, motif } = action.payload;
  if (!beneficiaire_id || !montant) return { ok: false, erreur: "beneficiaire_id + montant requis" };

  // Récupérer Stripe Connect account du soignant
  const { data: soignant } = await admin.from("soignants")
    .select("stripe_account_id").eq("id", beneficiaire_id).maybeSingle();
  if (!soignant?.stripe_account_id) {
    return { ok: false, erreur: `Soignant ${beneficiaire_id} sans Stripe Connect account` };
  }

  const res = await fetch("https://api.stripe.com/v1/transfers", {
    method: "POST",
    headers: { "Authorization": `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      amount: Math.round(montant * 100).toString(),
      currency: "eur",
      destination: soignant.stripe_account_id,
      description: motif || "Versement Jolene",
    }),
  });
  const json = await res.json();
  if (res.ok) return { ok: true, resultat: { transfer_id: json.id, amount: json.amount } };
  if (json.error?.code === "balance_insufficient") {
    return { ok: false, erreur: "balance_insufficient (sera retenté)" };
  }
  return { ok: false, erreur: `Stripe transfer ${res.status}: ${json.error?.message}` };
}

async function dispatchStripePayout(admin: any, action: ActionRow): Promise<DispatchResult> {
  return { ok: false, erreur: "STRIPE_PAYOUT pas encore implémenté (Sprint 5+)" };
}

// ─── Parrainage soignant ────────────────────────────────────────────

// Prévient le soignant que sa prime a bien été versée : notif in-app (+ push via
// le flag push_envoyee traité en aval) ET email (via email_queue → email-cron).
async function notifierPrimeVersee(
  admin: any,
  userId: string,
  soignant: { prenom?: string | null; email?: string | null } | null,
  montant: number,
  canal: string,
): Promise<void> {
  try {
    await admin.from("notifications").insert({
      destinataire_id: userId,
      type_destinataire: "SOIGNANT",
      type: "PARRAINAGE_PRIME_VERSEE",
      titre: `🎉 Prime de parrainage versée (${montant}€)`,
      corps: canal === "STRIPE_CONNECT"
        ? `Votre prime de ${montant}€ a été versée sur votre compte Stripe.`
        : `Votre prime de ${montant}€ part en virement SEPA sur votre compte (réception sous 1 à 2 jours ouvrés).`,
      lien: "/soignant/parrainage",
    });
  } catch (_e) { /* notif best-effort */ }
  try {
    await admin.from("email_queue").insert({
      type: "PARRAINAGE_PRIME_VERSEE",
      destinataire_id: userId,
      destinataire_email: soignant?.email ?? null,
      data: { prenom: soignant?.prenom ?? null, montant, canal },
    });
  } catch (_e) { /* email best-effort */ }
}

async function dispatchRecompenseParrainage(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { parrainage_id, parrain_id, filleul_id, montant_parrain, montant_filleul } = action.payload;
  if (!parrainage_id || !parrain_id || !filleul_id) {
    return { ok: false, erreur: "parrainage_id + parrain_id + filleul_id requis" };
  }

  // Prime configurable depuis /admin/config (parametres_systeme).
  const { data: primeParam } = await admin.rpc("fn_param_num", { p_cle: "prime_parrainage_eur", p_defaut: 50 });
  const primeDefaut = Number(primeParam) || 50;

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
  const results: Record<string, string> = {};
  let allPaid = true;

  for (const [role, userId, montant] of [
    ["parrain", parrain_id, montant_parrain || primeDefaut],
    ["filleul", filleul_id, montant_filleul || primeDefaut],
  ] as const) {
    const { data: soignant } = await admin.from("soignants")
      .select("stripe_account_id, iban_virement, iban_titulaire, prenom, nom, email")
      .eq("id", userId).maybeSingle();

    // Canal 1 : Stripe Connect (libéraux)
    if (soignant?.stripe_account_id && stripeKey) {
      const res = await fetch("https://api.stripe.com/v1/transfers", {
        method: "POST",
        headers: { "Authorization": `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          amount: Math.round(montant * 100).toString(),
          currency: "eur",
          destination: soignant.stripe_account_id,
          description: `Prime parrainage Jolene (${role})`,
          "metadata[parrainage_id]": parrainage_id,
          "metadata[role]": role,
        }),
      });
      const json = await res.json();
      if (!res.ok) {
        if (json.error?.code === "balance_insufficient") {
          return { ok: false, erreur: `balance_insufficient transfert ${role} (sera retenté)` };
        }
        return { ok: false, erreur: `Stripe transfer ${role} ${res.status}: ${json.error?.message}` };
      }
      results[`${role}_canal`] = "STRIPE_CONNECT";
      results[`${role}_ref`] = json.id;
      await notifierPrimeVersee(admin, userId, soignant, montant, "STRIPE_CONNECT");
      continue;
    }

    // Canal 2 : SWAN SCT (IBAN renseigné)
    if (soignant?.iban_virement) {
      const swanResult = await dispatchVersementSwan(
        soignant.iban_virement,
        soignant.iban_titulaire || `${soignant.prenom || ""} ${soignant.nom || ""}`.trim(),
        montant,
        `Prime parrainage Jolene (${role}) - ${parrainage_id}`,
        parrainage_id,
      );
      if (!swanResult.ok) {
        return { ok: false, erreur: `SWAN SCT ${role}: ${swanResult.erreur}` };
      }
      results[`${role}_canal`] = "SWAN_SCT";
      results[`${role}_ref`] = swanResult.resultat?.payment_id || "initiated";
      await notifierPrimeVersee(admin, userId, soignant, montant, "SWAN_SCT");
      continue;
    }

    // Canal 3 : Aucun moyen de paiement → notification soignant + alerte admins (fallback)
    await admin.from("notifications").insert({
      destinataire_id: userId,
      type_destinataire: "SOIGNANT",
      type: "PARRAINAGE_PRIME_VERSEE",
      titre: `${montant}€ de prime en attente !`,
      corps: `Votre prime de parrainage de ${montant}€ est prête. Renseignez votre IBAN dans Profil > Paiements pour la recevoir.`,
      lien: "/soignant/profil?tab=paiements",
    });
    // Admin awareness : prime bloquée faute d'IBAN/Stripe → l'admin peut relancer.
    try {
      const { data: adminIds } = await admin.rpc("fn_list_admin_user_ids");
      const noms = `${soignant?.prenom || ""} ${soignant?.nom || ""}`.trim();
      for (const a of (adminIds || []) as any[]) {
        const adminId = typeof a === "string" ? a : a?.fn_list_admin_user_ids ?? a?.id;
        if (!adminId) continue;
        await admin.from("notifications").insert({
          destinataire_id: adminId,
          type_destinataire: "ADMIN_PLATEFORME",
          type: "PARRAINAGE_PRIME_BLOQUEE",
          titre: "⚠️ Prime de parrainage bloquée (pas d'IBAN)",
          corps: `Prime de ${montant}€ (${role}) en attente pour ${noms || "un soignant"} : ni Stripe ni IBAN. Relancer le soignant pour qu'il renseigne son RIB.`,
          lien: "/admin/utilisateurs",
        });
      }
    } catch (_e) { /* best-effort */ }
    results[`${role}_canal`] = "EN_ATTENTE_IBAN";
    allPaid = false;
  }

  if (allPaid) {
    await admin.from("parrainages").update({
      statut: "PRIME_VERSEE",
      prime_versee_le: new Date().toISOString(),
    }).eq("id", parrainage_id);
  }

  await admin.rpc("fn_ecrire_audit_safe", {
    p_acteur_id: parrain_id,
    p_type_acteur: "SYSTEME",
    p_action: "PARRAINAGE_SOIGNANT_PRIME_VERSEE",
    p_type_ressource: "parrainage",
    p_id_ressource: parrainage_id,
    p_details: results,
  });

  return { ok: true, resultat: results };
}

// Remboursement d'un avoir par virement SEPA SWAN (auto, fallback manuel admin).
async function dispatchRemboursementAvoirSwan(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { avoir_id, montant } = action.payload;
  if (!avoir_id) return { ok: false, erreur: "avoir_id requis" };

  const { data: avoir } = await admin.from("factures_honoraires")
    .select("id, numero_facture, soignant_id, mode_remboursement, date_remboursement, montant_ttc, montant_ht, type_document")
    .eq("id", avoir_id).maybeSingle();
  if (!avoir) return { ok: false, erreur: "Avoir introuvable" };
  if (avoir.type_document !== "AVOIR") return { ok: false, erreur: "Document non-avoir" };
  if (avoir.date_remboursement) return { ok: true, resultat: { skip: "déjà remboursé" } }; // idempotent

  const { data: sg } = await admin.from("soignants")
    .select("iban_virement, iban_titulaire, prenom, nom, email")
    .eq("id", avoir.soignant_id).maybeSingle();
  if (!sg?.iban_virement) {
    return { ok: false, erreur: "IBAN manquant — bascule virement manuel admin" };
  }

  const m = Number(montant) || Number(avoir.montant_ttc) || Number(avoir.montant_ht) || 0;
  if (m <= 0) return { ok: false, erreur: "Montant avoir invalide" };

  const swan = await dispatchVersementSwan(
    sg.iban_virement,
    sg.iban_titulaire || `${sg.prenom || ""} ${sg.nom || ""}`.trim(),
    m,
    `Remboursement avoir Jolene ${avoir.numero_facture || avoir_id}`,
    `rembavoir_${avoir_id}`,
  );
  if (!swan.ok) {
    return { ok: false, erreur: `SWAN remboursement: ${swan.erreur}` }; // retry → sinon fallback manuel
  }

  const ref = `SWAN:${swan.resultat?.payment_id || "initiated"}`;
  await admin.from("factures_honoraires").update({
    statut: "REMBOURSE",
    date_remboursement: new Date().toISOString(),
    reference_remboursement: ref,
  }).eq("id", avoir_id);

  await admin.from("notifications").insert({
    destinataire_id: avoir.soignant_id,
    type_destinataire: "SOIGNANT",
    type: "REMBOURSEMENT_CONFIRME",
    titre: "💸 Remboursement envoyé",
    corps: `Votre remboursement de ${m}€ (avoir ${avoir.numero_facture || ""}) part en virement SEPA — réception sous 1 à 2 jours ouvrés.`,
    lien: "/soignant/mes-factures-honoraires",
  });
  await admin.from("email_queue").insert({
    type: "REMBOURSEMENT_CONFIRME",
    destinataire_id: avoir.soignant_id,
    destinataire_email: sg.email ?? null,
    data: { prenom: sg.prenom ?? null, montant: m, numero: avoir.numero_facture ?? null, reference: ref },
  });

  return { ok: true, resultat: { payment_id: swan.resultat?.payment_id, reference: ref } };
}

async function dispatchVersementSwan(
  iban: string,
  beneficiaryName: string,
  amountEur: number,
  reference: string,
  idempotencyKey: string,
): Promise<DispatchResult> {
  try {
    const { swanGraphQL, swanEnv } = await import("../_shared/swan-client.ts");
    const env = swanEnv();
    if (!env.clientId || !env.graphqlUrl) {
      return { ok: false, erreur: "SWAN non configuré (SWAN_CLIENT_ID ou SWAN_GRAPHQL_URL manquant)" };
    }

    const mutation = `
      mutation InitierVersementPrime($input: InitiateCreditTransfersInput!) {
        initiateCreditTransfers(input: $input) {
          ... on InitiateCreditTransfersSuccessPayload {
            payment { id statusInfo { __typename } }
          }
          ... on AccountNotFoundRejection { message }
          ... on ForbiddenRejection { message }
          ... on InternalErrorRejection { message }
          ... on ValidationRejection { message }
        }
      }
    `;

    const variables = {
      input: {
        accountId: env.accountId,
        idempotencyKey,
        consentRedirectUrl: "https://jolene.app/swan-callback",
        creditTransfers: [{
          amount: { value: amountEur.toFixed(2), currency: "EUR" },
          sepaBeneficiary: {
            iban,
            name: beneficiaryName,
            isMyOwnIban: false,
            save: false,
          },
          reference: reference.slice(0, 35),
          label: `Prime parrainage Jolene ${amountEur}€`,
        }],
      },
    };

    const result = await swanGraphQL(mutation, variables);

    if (!result.ok) {
      const errMsg = JSON.stringify(result.errors).slice(0, 300);
      return { ok: false, erreur: `SWAN GraphQL error: ${errMsg}` };
    }

    const payload = (result.data as any)?.initiateCreditTransfers;
    if (payload?.payment?.id) {
      return { ok: true, resultat: { payment_id: payload.payment.id, status: payload.payment.statusInfo?.__typename } };
    }

    const rejection = payload?.message;
    if (rejection) {
      return { ok: false, erreur: `SWAN rejection: ${rejection}` };
    }

    return { ok: false, erreur: "SWAN: réponse inattendue" };
  } catch (err) {
    return { ok: false, erreur: `SWAN exception: ${(err as Error).message?.slice(0, 300)}` };
  }
}

// ─── Chorus Pro ──────────────────────────────────────────────────────

async function dispatchChorusRecycle(admin: any, action: ActionRow): Promise<DispatchResult> {
  // Si PISTE_OAUTH_SCOPE pas configuré (cas actuel jusqu'à déblocage AIFE),
  // marquer PENDING_AIFE pour re-check 24h
  const oauthScope = Deno.env.get("PISTE_OAUTH_SCOPE");
  if (!oauthScope || !oauthScope.includes("recyclerFacture")) {
    return { ok: false, erreur: "PISTE scopes pas activés AIFE (recyclerFacture absent)", pending_aife: true };
  }

  // À implémenter quand AIFE active les scopes (Sprint final).
  // Pour le moment : marquer PENDING_AIFE même si scope présent
  // (car la chaîne piste-client complète n'est pas dans cette PR)
  return { ok: false, erreur: "Chorus recycleFacture pas encore intégré (à finaliser post-AIFE)", pending_aife: true };
}

// ─── DPAE ────────────────────────────────────────────────────────────

async function dispatchDpaeAnnulation(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { contrat_id, mission_id, motif } = action.payload;
  if (!contrat_id) return { ok: false, erreur: "contrat_id missing" };

  // Récupérer l'étab
  const { data: contrat } = await admin.from("contrats_mission")
    .select("etablissement_id, numero_contrat, type_contrat, dpae_numero")
    .eq("id", contrat_id).maybeSingle();
  if (!contrat) return { ok: false, erreur: "contrat introuvable" };

  // Option A : email + push étab pour annulation manuelle Net-Entreprises
  // (Option B API tiers déclarant URSSAF = Sprint 5+)
  await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify({
      type: "DPAE_ANNULATION_RAPPEL",
      destinataire_id: contrat.etablissement_id,
      data: { numero_contrat: contrat.numero_contrat, motif, dpae_numero: contrat.dpae_numero,
              url: "https://www.net-entreprises.fr/declaration-prealable-embauche/",
              echeance_legale_h: 48 },
    }),
  });
  await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify({
      destinataire_id: contrat.etablissement_id,
      type_evenement: "DPAE_ANNULATION_RAPPEL",
      titre: "⚠️ Annulation DPAE à effectuer",
      corps: `Contrat ${contrat.numero_contrat || ""} annulé. Annulez la DPAE sur Net-Entreprises sous 48h.`,
      lien: `/contrat/${contrat_id}`,
    }),
  });

  return { ok: true, resultat: { mode: "OPTION_A_MANUEL", etablissement_id: contrat.etablissement_id } };
}

// ─── Emails + Push (relais simples) ──────────────────────────────────

async function dispatchEmail(admin: any, action: ActionRow): Promise<DispatchResult> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify(action.payload),
  });
  if (res.ok) return { ok: true, resultat: { status: res.status } };
  return { ok: false, erreur: `send-email ${res.status}` };
}

async function dispatchPush(admin: any, action: ActionRow): Promise<DispatchResult> {
  const p = action.payload;
  // Adapter le format pour send-push (peut être appelé avec destinataire_id, type_evenement, titre, corps, data.lien)
  const body: any = {
    destinataire_id: p.destinataire_id,
    titre: p.titre || p.title,
    corps: p.corps || p.body,
    lien: p.lien || p.data?.lien,
    type_evenement: p.type_evenement,
  };
  const res = await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify(body),
  });
  if (res.ok) return { ok: true, resultat: { status: res.status } };
  return { ok: false, erreur: `send-push ${res.status}` };
}

// ─── AVOIR PDF ───────────────────────────────────────────────────────

async function dispatchAvoirPdf(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { mission_id, type, motif_avoir, montant, pourcentage, nouveau_montant, montant_indemnite } = action.payload;
  if (!mission_id) return { ok: false, erreur: "mission_id missing" };

  // Récupérer mission + facture
  const { data: mission } = await admin.from("missions")
    .select("id, intitule, etablissement_id, soignant_assigne_id, debut_le, fin_le, duree_heures, taux_horaire_base")
    .eq("id", mission_id).maybeSingle();
  if (!mission) return { ok: false, erreur: "mission introuvable" };

  // Calculer montant avoir
  let montantHt: number;
  const total = (mission.taux_horaire_base || 0) * (mission.duree_heures || 0);
  if (montant) montantHt = montant;
  else if (pourcentage) montantHt = total * (pourcentage / 100);
  else if (nouveau_montant) montantHt = total - nouveau_montant;
  else if (montant_indemnite) montantHt = montant_indemnite;
  else montantHt = total; // TOTAL par défaut

  // Générer numéro avoir AV-YYYYMM-XXXX
  const date = new Date();
  const yymm = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, "0")}`;
  const numero = `AV-${yymm}-${Math.floor(Math.random() * 9999).toString().padStart(4, "0")}`;

  // HTML simple de l'avoir
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>Avoir ${numero}</title>
<style>body{font-family:Arial;color:#222;line-height:1.6;padding:40px;max-width:800px;margin:0 auto}
h1{color:#d6336c}.box{background:#fef3f7;padding:16px;border-radius:8px;margin:16px 0}</style>
</head><body>
<h1>AVOIR ${numero}</h1>
<p><strong>Date :</strong> ${date.toLocaleDateString("fr-FR")}</p>
<p><strong>Motif :</strong> ${motif_avoir || type || "AJUSTEMENT"}</p>
<div class="box">
<p><strong>Mission :</strong> ${mission.intitule || "—"}</p>
<p><strong>Période :</strong> ${mission.debut_le?.slice(0, 10) || "—"} → ${mission.fin_le?.slice(0, 10) || "—"}</p>
<p><strong>Montant avoir HT :</strong> ${montantHt.toFixed(2)} €</p>
<p><strong>Action source :</strong> ${action.source}</p>
</div>
<p><em>Avoir généré automatiquement suite à ${action.source === "LITIGE_EXEC" ? "résolution d'un litige" : "annulation de mission"}. Document à conserver pour comptabilité.</em></p>
</body></html>`;

  // Hash SHA-256 du PDF (en pratique on stocke le HTML, jsPDF côté front pour PDF binaire)
  const hashBuf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(html));
  const hash = Array.from(new Uint8Array(hashBuf)).map(b => b.toString(16).padStart(2, "0")).join("");

  // Upload Storage bucket avoirs (si existe)
  const path = `avoirs/${mission_id}/${numero}.html`;
  const { error: uploadErr } = await admin.storage.from("jolene-documents")
    .upload(path, new Blob([html], { type: "text/html" }), { upsert: false });
  if (uploadErr && !uploadErr.message?.includes("Bucket not found")) {
    // Si bucket existe mais erreur autre, on log mais continue
    console.warn("[worker] avoir upload warning:", uploadErr.message);
  }

  // INSERT avoirs row
  const { error: insertErr } = await admin.from("avoirs").insert({
    facture_origine_type: "FACTURE_ETAB",
    numero,
    montant_ht: montantHt,
    montant_ttc: montantHt, // exo TVA art. 261-4-1 CGI pour soins
    motif: motif_avoir || (action.source === "LITIGE_EXEC" ? "LITIGE_ACCORD_MUTUEL" : "AUTRE"),
    source_litige_id: action.source === "LITIGE_EXEC" ? action.source_id : null,
    source_mission_id: mission_id,
    pdf_storage_path: path,
    emis_par: "00000000-0000-0000-0000-000000000000",
    details: { type, hash_document: hash, action_payload: action.payload },
  });
  if (insertErr) return { ok: false, erreur: `INSERT avoir failed: ${insertErr.message}` };

  return { ok: true, resultat: { numero, montant_ht: montantHt, path, hash } };
}
