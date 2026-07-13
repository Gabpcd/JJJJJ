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
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

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
  try {
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
    if (error) console.error("audit escrow-release insert:", error.message);
  } catch (e) { console.error("audit escrow-release throw:", e); }
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
    apiVersion: "2025-08-27.basil",
  });

  const { data: dus, error: dusErr } = await admin.rpc("fn_escrow_releases_a_traiter", { p_limit: 50 });
  if (dusErr) {
    return new Response(JSON.stringify({ error: dusErr.message }), { status: 500 });
  }

  const rows = (dus as any[]) || [];
  let planifies = 0, attente_fonds = 0, ignores = 0, echecs = 0;

  for (const rel of rows) {
    let releaseReservee = false;
    // Lock optimiste EN_ATTENTE → EN_COURS.
    const { data: locked } = await admin
      .from("escrow_release_queue")
      .update({ statut: "EN_COURS" })
      .eq("id", rel.queue_id)
      .eq("statut", "EN_ATTENTE")
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
      if (escrowCourant.statut !== "DEBITE") {
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

      // Compte connecté du soignant.
      const { data: onboarding } = await admin
        .from("stripe_connect_onboarding")
        .select("stripe_account_id, statut")
        .eq("soignant_id", rel.soignant_id)
        .maybeSingle();
      if (!onboarding?.stripe_account_id || onboarding.statut !== "COMPLET") {
        await admin.from("escrow_release_queue")
          .update({ statut: "ECHEC", erreur: "compte connecté non COMPLET", traite_le: new Date().toISOString() })
          .eq("id", rel.queue_id);
        echecs++;
        continue;
      }
      const acct = onboarding.stripe_account_id;

      // Une tentative terminale connue reçoit une nouvelle version
      // déterministe. Une tentative encore active est récupérée, jamais doublée.
      let payoutIdempotencyKey = `release_${rel.paiement_escrow_id}`;
      if (escrowCourant.stripe_payout_id) {
        const precedent = await stripe.payouts.retrieve(
          escrowCourant.stripe_payout_id,
          { stripeAccount: acct },
        );
        if (["pending", "in_transit", "paid"].includes(precedent.status)) {
          const maintenant = new Date().toISOString();
          const { data: recupere } = await admin
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
            .eq("stripe_payout_id", precedent.id)
            .select("id")
            .maybeSingle();
          if (!recupere) throw new Error("récupération payout concurrente impossible");

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
        payoutIdempotencyKey = `release_${rel.paiement_escrow_id}_after_${precedent.id}`;
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

      // PAYOUT manuel sur le compte connecté (idempotency key = release id).
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

      const { data: escrowPlanifie, error: escrowPlanifieErr } = await admin
        .from("paiements_escrow")
        .update({
          statut: "RELEASE_PLANIFIE",
          stripe_payout_id: payout.id,
          erreur: null,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", rel.paiement_escrow_id)
        .eq("statut", "RELEASE_PLANIFIE")
        .select("id")
        .maybeSingle();
      if (escrowPlanifieErr || !escrowPlanifie) {
        throw new Error(`persistance payout impossible: ${escrowPlanifieErr?.message || "escrow non modifiable"}`);
      }
      releaseReservee = false;

      // La file reste EN_COURS : elle sera clôturée atomiquement par
      // fn_escrow_confirmer_payout ou fn_escrow_echouer_payout au webhook.
      await auditEscrow(admin, "ESCROW_RELEASE_INITIE", rel.mission_id, {
        paiement_escrow_id: rel.paiement_escrow_id,
        stripe_payout_id: payout.id,
        stripe_payout_status: payout.status,
        honoraires_cents: rel.honoraires_cents,
        destination: acct,
      });
      planifies++;
    } catch (err: any) {
      const code = err?.code || err?.raw?.code || null;
      const msg = err?.message || String(err);
      // Si Stripe a répondu de façon ambiguë, la même clé d'idempotence sera
      // rejouée. Le rollback compare-and-set ne touche jamais PAYE/ECHOUE.
      if (releaseReservee) {
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
          statut: (rel.tentatives ?? 0) + 1 >= 5 ? "ECHEC" : "EN_ATTENTE",
          tentatives: (rel.tentatives ?? 0) + 1,
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
