/**
 * escrow-release — Escrow 7b-D PR 5
 *
 * Consumer de escrow_release_queue (enfilée par le trigger présences PR 2 quand
 * la validation est complète). Déclenche le VIREMENT au soignant.
 *
 * Double condition A3 avant tout payout :
 *   1. présences validées → garanti par l'enqueue (le trigger ne pousse que
 *      quand le gate 7b-B est satisfait) ;
 *   2. fonds `available` sur le solde connecté du soignant (le débit SEPA doit
 *      être settled) → vérifié ici via balance.retrieve(stripeAccount). Sinon :
 *      retry avec backoff, le payout attend.
 *
 * Payout manuel sur le compte connecté (les comptes sont en
 * payouts.schedule.interval=manual depuis la PR 1) : rien ne part sans cet
 * appel. La création Stripe laisse l'escrow RELEASE_PLANIFIE ; seul le webhook
 * Connect payout.paid confirme PAYE et incrémente la confiance. Un payout créé
 * est initialement pending et peut encore échouer plusieurs jours plus tard.
 *
 * Auth : Bearer service_role (env) ou secret vault (pg_cron).
 * NO-OP si flag ⚡ = 0 (escrow_release_queue vide).
 */
import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import {
  type EscrowPayoutExpectation,
  requireExactEscrowPayout,
} from "../_shared/stripe-escrow-payout.ts";

let _vaultSecret: string | null = null;
async function bearerAutorise(req: Request, admin: any): Promise<boolean> {
  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return false;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (svc && bearer === svc) return true;
  if (_vaultSecret) return bearer === _vaultSecret;
  try {
    const { data } = await admin.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _vaultSecret = data; return bearer === data; }
  } catch { /* ignore */ }
  return false;
}

const BACKOFF_MS = 30 * 60 * 1000; // 30 min entre 2 essais si fonds pas encore dispo

// Audit DIRECT en table (pas via le rpc fn_ecrire_audit_safe) : le binding
// PostgREST de ce RPC à 9 paramètres sérialise les uuid en « null » →
// « invalid input syntax for type uuid » → l'audit edge échouait
// silencieusement (trou d'observabilité prod découvert par la recette escrow,
// run #11 du 09/07/2026). Le service_role bypasse la RLS : l'insert direct est
// fiable. Les fonctions DB (triggers, RPC SQL) continuent d'utiliser le wrapper.
async function auditEscrow(admin: any, action: string, missionId: string | null, details: unknown) {
  const { error } = await admin.from("journaux_audit").insert({
    acteur_id: "00000000-0000-0000-0000-000000000000",
    type_acteur: "SYSTEME",
    action,
    type_ressource: "mission",
    id_ressource: missionId,
    cle_s3_ressource: null,
    details: details ?? null,
    ip_acteur: null,
    navigateur_acteur: "escrow-release",
  });
  if (error) throw new Error(`audit escrow-release insert: ${error.message}`);
}

async function findEscrowPayoutsByMetadata(
  stripe: Stripe,
  stripeAccount: string,
  paiementEscrowId: string,
): Promise<Stripe.Payout[]> {
  const matches: Stripe.Payout[] = [];
  let startingAfter: string | undefined;
  while (true) {
    const page = await stripe.payouts.list(
      {
        limit: 100,
        ...(startingAfter ? { starting_after: startingAfter } : {}),
      },
      { stripeAccount },
    );
    matches.push(...page.data.filter(
      (payout) => payout.metadata?.paiement_escrow_id === paiementEscrowId,
    ));
    if (!page.has_more) break;
    const last = page.data.at(-1);
    if (!last) throw new Error("ESCROW_PAYOUT_PAGINATION_INCOMPLETE");
    startingAfter = last.id;
  }
  return matches;
}

function selectEscrowPayoutForRecovery(
  payouts: Stripe.Payout[],
  expected: EscrowPayoutExpectation,
): Stripe.Payout | null {
  for (const payout of payouts) requireExactEscrowPayout(payout, expected);
  const actifs = payouts.filter((payout) =>
    ["pending", "in_transit", "paid"].includes(payout.status)
  );
  if (actifs.length > 1) {
    throw new Error(`ESCROW_PAYOUT_DUPLICATE_ACTIVE:${actifs.map((p) => p.id).join(",")}`);
  }
  if (actifs.length === 1) return actifs[0];
  return [...payouts].sort((a, b) => b.created - a.created)[0] || null;
}

async function persistExactEscrowPayout(
  admin: any,
  expected: EscrowPayoutExpectation,
  payout: Stripe.Payout,
): Promise<void> {
  requireExactEscrowPayout(payout, expected);
  const maintenant = new Date().toISOString();
  const { data, error } = await admin
    .from("paiements_escrow")
    .update({
      statut: "RELEASE_PLANIFIE",
      stripe_payout_id: payout.id,
      available_on: maintenant,
      disponible_le: maintenant,
      release_planifie_le: maintenant,
      erreur: null,
      modifie_le: maintenant,
    })
    .eq("id", expected.paiementEscrowId)
    .in("statut", ["DEBITE", "RELEASE_PLANIFIE"])
    .or(`stripe_payout_id.is.null,stripe_payout_id.eq.${payout.id}`)
    .select("id")
    .maybeSingle();
  if (error) throw new Error(`persistance payout impossible: ${error.message}`);
  if (data) return;

  const { data: current, error: currentError } = await admin
    .from("paiements_escrow")
    .select("statut, stripe_payout_id")
    .eq("id", expected.paiementEscrowId)
    .maybeSingle();
  if (
    currentError
    || !current
    || !["RELEASE_PLANIFIE", "PAYE"].includes(current.statut)
    || current.stripe_payout_id !== payout.id
  ) {
    throw new Error(
      `persistance payout concurrente impossible: ${currentError?.message || "identité divergente"}`,
    );
  }
}

Deno.serve(async (req) => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  if (!(await bearerAutorise(req, admin))) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
  try {
    assertStripeSecretMode(stripeKey);
  } catch {
    return new Response(JSON.stringify({ error: "stripe_not_configured" }), { status: 503 });
  }
  const stripe = new Stripe(stripeKey, {
    apiVersion: "2026-02-25.clover",
  });

  const { data: dus, error: dusErr } = await admin.rpc("fn_escrow_releases_a_traiter", { p_limit: 50 });
  if (dusErr) {
    return new Response(JSON.stringify({ error: dusErr.message }), { status: 500 });
  }

  const rows = (dus as any[]) || [];
  let planifies = 0, attente_fonds = 0, ignores = 0, echecs = 0;

  for (const rel of rows) {
    let releaseReservee = false;
    let repriseAmbigue = false;
    let payoutCallStarted = false;
    let payoutObserve: Stripe.Payout | null = null;
    let stripeAccount: string | null = null;
    const payoutExpected: EscrowPayoutExpectation = {
      paiementEscrowId: rel.paiement_escrow_id,
      missionId: rel.mission_id,
      soignantId: rel.soignant_id,
      amountCents: Number(rel.honoraires_cents),
    };
    // Lock optimiste avec lease : un EN_COURS abandonné par un crash redevient
    // récupérable une fois prochaine_tentative_le échue.
    const leaseJusqua = new Date(Date.now() + BACKOFF_MS).toISOString();
    const { data: locked } = await admin
      .from("escrow_release_queue")
      .update({ statut: "EN_COURS", prochaine_tentative_le: leaseJusqua })
      .eq("id", rel.queue_id)
      .in("statut", ["EN_ATTENTE", "EN_COURS"])
      .lte("prochaine_tentative_le", new Date().toISOString())
      .select("id")
      .maybeSingle();
    if (!locked) { ignores++; continue; }

    try {
      // La valeur renvoyée par la RPC peut devenir obsolète entre la sélection
      // et le verrou de file. La ligne exacte fait foi avant tout appel Stripe.
      const { data: escrowCourant, error: escrowCourantErr } = await admin
        .from("paiements_escrow")
        .select("statut, stripe_payout_id")
        .eq("id", rel.paiement_escrow_id)
        .maybeSingle();
      if (escrowCourantErr || !escrowCourant) {
        throw new Error(`escrow introuvable: ${escrowCourantErr?.message || rel.paiement_escrow_id}`);
      }

      // Escrow déjà payé/annulé entre-temps → clôture idempotente de la file.
      if (escrowCourant.statut === "PAYE") {
        await admin.from("escrow_release_queue")
          .update({ statut: "TRAITE", traite_le: new Date().toISOString() })
          .eq("id", rel.queue_id);
        ignores++;
        continue;
      }
      if (["REMBOURSE", "DISPUTE", "ECHOUE"].includes(escrowCourant.statut)) {
        await admin.from("escrow_release_queue")
          .update({ statut: "ECHEC", erreur: `escrow ${escrowCourant.statut}`, traite_le: new Date().toISOString() })
          .eq("id", rel.queue_id);
        echecs++;
        continue;
      }
      if (!["DEBITE", "RELEASE_PLANIFIE"].includes(escrowCourant.statut)) {
        // Défense en profondeur : la RPC SQL filtre déjà strictement DEBITE.
        // On ne promeut surtout jamais INITIE depuis ce consumer.
        await admin.from("escrow_release_queue")
          .update({
            statut: "EN_ATTENTE",
            prochaine_tentative_le: new Date(Date.now() + BACKOFF_MS).toISOString(),
            erreur: `escrow non débité (${escrowCourant.statut})`,
          })
          .eq("id", rel.queue_id);
        ignores++;
        continue;
      }
      repriseAmbigue = escrowCourant.statut === "RELEASE_PLANIFIE"
        || Boolean(escrowCourant.stripe_payout_id);
      let escrowStatutCourant = escrowCourant.statut;

      // Compte connecté du soignant.
      const { data: onboarding } = await admin
        .from("stripe_connect_onboarding")
        .select("stripe_account_id, statut")
        .eq("soignant_id", rel.soignant_id)
        .maybeSingle();
      if (!onboarding?.stripe_account_id || onboarding.statut !== "COMPLET") {
        await admin.from("escrow_release_queue")
          .update(repriseAmbigue
            ? {
              statut: "EN_ATTENTE",
              tentatives: Math.min((rel.tentatives ?? 0) + 1, 4),
              prochaine_tentative_le: new Date(Date.now() + BACKOFF_MS).toISOString(),
              erreur: "compte connecté non COMPLET — payout à réconcilier",
            }
            : {
              statut: "ECHEC",
              erreur: "compte connecté non COMPLET",
              traite_le: new Date().toISOString(),
            })
          .eq("id", rel.queue_id);
        if (repriseAmbigue) ignores++;
        else echecs++;
        continue;
      }
      const acct = onboarding.stripe_account_id;
      stripeAccount = acct;

      if (!Number.isSafeInteger(payoutExpected.amountCents) || payoutExpected.amountCents <= 0) {
        throw new Error("ESCROW_PAYOUT_INVALID_AMOUNT");
      }

      // Une tentative terminale connue reçoit une nouvelle version
      // déterministe. Une tentative encore active est récupérée, jamais doublée.
      let payoutIdempotencyKey = `release_${rel.paiement_escrow_id}`;
      let precedent: Stripe.Payout | null = null;
      if (escrowCourant.stripe_payout_id) {
        precedent = await stripe.payouts.retrieve(
          escrowCourant.stripe_payout_id,
          { stripeAccount: acct },
        );
        requireExactEscrowPayout(precedent, payoutExpected);
      } else {
        // Crash possible entre payouts.create et le CAS local : parcourir toute
        // la collection du compte connecté et récupérer uniquement l'identité
        // metadata exacte avant d'envisager une nouvelle création.
        precedent = selectEscrowPayoutForRecovery(
          await findEscrowPayoutsByMetadata(
            stripe,
            acct,
            rel.paiement_escrow_id,
          ),
          payoutExpected,
        );
      }

      if (precedent) {
        payoutObserve = precedent;
        await persistExactEscrowPayout(admin, payoutExpected, precedent);
        if (["pending", "in_transit", "paid"].includes(precedent.status)) {
          if (precedent.status === "paid") {
            const { error: confirmationErr } = await admin.rpc("fn_escrow_confirmer_payout", {
              p_paiement_escrow_id: rel.paiement_escrow_id,
              p_stripe_payout_id: precedent.id,
              p_stripe_account_id: acct,
              p_paye_le: new Date(precedent.arrival_date * 1000).toISOString(),
            });
            if (confirmationErr) throw confirmationErr;
          }
          ignores++;
          continue;
        }

        // On ne revient à DEBITE qu'après observation certaine d'un payout
        // terminal failed/canceled et avec un CAS sur son identifiant exact.
        const { data: terminalReouvert, error: terminalReouvertError } = await admin
          .from("paiements_escrow")
          .update({
            statut: "DEBITE",
            stripe_payout_id: null,
            release_planifie_le: null,
            erreur: `Payout ${precedent.status} ${precedent.id} — nouvelle version autorisée`,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", rel.paiement_escrow_id)
          .eq("statut", "RELEASE_PLANIFIE")
          .eq("stripe_payout_id", precedent.id)
          .select("id")
          .maybeSingle();
        if (terminalReouvertError || !terminalReouvert) {
          throw new Error(
            `réouverture payout terminal impossible: ${terminalReouvertError?.message || "état concurrent"}`,
          );
        }
        escrowStatutCourant = "DEBITE";
        repriseAmbigue = false;
        payoutIdempotencyKey = `release_${rel.paiement_escrow_id}_after_${precedent.id}`;
        // Le terminal est certain et son ID vient d'être archivé dans l'erreur :
        // la future persistance doit pouvoir lier le nouveau payout, et un échec
        // pré-appel ne doit pas re-promouvoir l'ancien terminal.
        payoutObserve = null;
      }

      // A3 condition 2 : fonds `available` sur le solde connecté ?
      const balance = await stripe.balance.retrieve({ stripeAccount: acct });
      const availEur = (balance.available || []).find((b: any) => b.currency === "eur");
      const availableCents = availEur?.amount ?? 0;

      if (availableCents < rel.honoraires_cents) {
        // Fonds pas encore settled → DISPONIBLE pas atteint. Retry plus tard.
        await admin
          .from("escrow_release_queue")
          .update({
            statut: "EN_ATTENTE",
            tentatives: (rel.tentatives ?? 0) + 1,
            prochaine_tentative_le: new Date(Date.now() + BACKOFF_MS).toISOString(),
            erreur: `fonds insuffisants (available ${availableCents} < ${rel.honoraires_cents})`,
          })
          .eq("id", rel.queue_id);
        await auditEscrow(admin, "ESCROW_RELEASE_ATTENTE_FONDS", rel.mission_id,
          { paiement_escrow_id: rel.paiement_escrow_id, available_cents: availableCents, requis_cents: rel.honoraires_cents });
        attente_fonds++;
        continue;
      }

      // Réservation atomique immédiatement avant Stripe : seule la transition
      // DEBITE -> RELEASE_PLANIFIE est autorisée. Un second worker perd le CAS.
      if (escrowStatutCourant === "DEBITE") {
        const maintenant = new Date().toISOString();
        const { data: reservee, error: reserveeErr } = await admin
          .from("paiements_escrow")
          .update({
            statut: "RELEASE_PLANIFIE",
            available_on: maintenant,
            disponible_le: maintenant,
            release_planifie_le: maintenant,
            modifie_le: maintenant,
          })
          .eq("id", rel.paiement_escrow_id)
          .eq("statut", "DEBITE")
          .select("id")
          .maybeSingle();
        if (reserveeErr || !reservee) {
          throw new Error(`réservation release impossible: ${reserveeErr?.message || "transition concurrente"}`);
        }
        releaseReservee = true;
      }

      // PAYOUT manuel sur le compte connecté (idempotency key = release id).
      payoutCallStarted = true;
      const payout = await stripe.payouts.create(
        {
          amount: rel.honoraires_cents,
          currency: "eur",
          metadata: {
            type: "ESCROW_RELEASE",
            paiement_escrow_id: rel.paiement_escrow_id,
            mission_id: rel.mission_id,
            soignant_id: rel.soignant_id,
          },
        },
        { stripeAccount: acct, idempotencyKey: payoutIdempotencyKey },
      );
      payoutObserve = requireExactEscrowPayout(payout, payoutExpected);
      await persistExactEscrowPayout(admin, payoutExpected, payoutObserve);
      releaseReservee = false;

      if (!["pending", "in_transit", "paid"].includes(payoutObserve.status)) {
        throw new Error(`ESCROW_PAYOUT_TERMINAL_AT_CREATION:${payoutObserve.status}`);
      }

      // La file reste EN_COURS : elle sera clôturée atomiquement par
      // fn_escrow_confirmer_payout ou fn_escrow_echouer_payout au webhook.
      try {
        await auditEscrow(admin, "ADMIN_ACTION", rel.mission_id, {
          evenement: "ESCROW_RELEASE_INITIE",
          paiement_escrow_id: rel.paiement_escrow_id,
          stripe_payout_id: payoutObserve.id,
          stripe_payout_status: payoutObserve.status,
          honoraires_cents: rel.honoraires_cents,
          destination: acct,
        });
      } catch (auditError) {
        console.error("escrow-release: audit post-payout non bloquant", auditError);
      }
      planifies++;
    } catch (err: any) {
      const code = err?.code || err?.raw?.code || null;
      let msg = err?.message || String(err);
      const postPayoutAmbigu = payoutCallStarted || payoutObserve !== null || repriseAmbigue;

      // Après l'appel Stripe (ou lors de la reprise d'un RELEASE_PLANIFIE), ne
      // jamais revenir à DEBITE. On tente d'abord de retrouver puis rattacher le
      // payout exact ; à défaut la file reste rejouable sans borne terminale.
      if (postPayoutAmbigu && stripeAccount) {
        try {
          const recovered = payoutObserve || selectEscrowPayoutForRecovery(
            await findEscrowPayoutsByMetadata(
              stripe,
              stripeAccount,
              rel.paiement_escrow_id,
            ),
            payoutExpected,
          );
          if (recovered) {
            payoutObserve = requireExactEscrowPayout(recovered, payoutExpected);
            await persistExactEscrowPayout(admin, payoutExpected, payoutObserve);
            if (["pending", "in_transit", "paid"].includes(payoutObserve.status)) {
              if (payoutObserve.status === "paid") {
                const { error: confirmationErr } = await admin.rpc(
                  "fn_escrow_confirmer_payout",
                  {
                    p_paiement_escrow_id: rel.paiement_escrow_id,
                    p_stripe_payout_id: payoutObserve.id,
                    p_stripe_account_id: stripeAccount,
                    p_paye_le: new Date(payoutObserve.arrival_date * 1000).toISOString(),
                  },
                );
                if (confirmationErr) throw confirmationErr;
              }
              await admin.from("escrow_release_queue")
                .update({ statut: "EN_COURS", erreur: null })
                .eq("id", rel.queue_id);
              planifies++;
              continue;
            }
          }
        } catch (recoveryError) {
          msg = `${msg} — recovery: ${
            recoveryError instanceof Error ? recoveryError.message : String(recoveryError)
          }`;
        }
      }

      // Rollback autorisé uniquement si ce worker vient de réserver DEBITE et
      // qu'aucun appel Stripe n'a commencé. Il est interdit après ambiguïté.
      if (releaseReservee && !postPayoutAmbigu) {
        const { error: rollbackErr } = await admin
          .from("paiements_escrow")
          .update({ statut: "DEBITE", modifie_le: new Date().toISOString() })
          .eq("id", rel.paiement_escrow_id)
          .eq("statut", "RELEASE_PLANIFIE");
        if (rollbackErr) console.error(`escrow-release rollback=${rollbackErr.message}`);
      }
      await admin
        .from("escrow_release_queue")
        .update({
          statut: postPayoutAmbigu
            ? "EN_ATTENTE"
            : (rel.tentatives ?? 0) + 1 >= 5 ? "ECHEC" : "EN_ATTENTE",
          tentatives: postPayoutAmbigu
            ? Math.min((rel.tentatives ?? 0) + 1, 4)
            : (rel.tentatives ?? 0) + 1,
          prochaine_tentative_le: new Date(Date.now() + BACKOFF_MS).toISOString(),
          erreur: `${code || "erreur"} — ${msg}`.substring(0, 500),
        })
        .eq("id", rel.queue_id);
      console.error(`escrow-release mission=${rel.mission_id} code=${code} msg=${msg}`);
      echecs++;
    }
  }

  return new Response(
    JSON.stringify({ ok: true, examined: rows.length, planifies, payes: 0, attente_fonds, echecs, ignores }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
