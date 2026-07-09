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
 * appel. Au succès : paiements_escrow → PAYE + compteur de confiance A2.
 *
 * Auth : Bearer service_role (env) ou secret vault (pg_cron).
 * NO-OP si flag ⚡ = 0 (escrow_release_queue vide).
 */
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

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

  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
    apiVersion: "2025-08-27.basil",
  });

  const { data: dus, error: dusErr } = await admin.rpc("fn_escrow_releases_a_traiter", { p_limit: 50 });
  if (dusErr) {
    return new Response(JSON.stringify({ error: dusErr.message }), { status: 500 });
  }

  const rows = (dus as any[]) || [];
  let payes = 0, attente_fonds = 0, ignores = 0, echecs = 0;

  for (const rel of rows) {
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
      // Escrow déjà payé/annulé entre-temps → clôture idempotente de la file.
      if (rel.escrow_statut === "PAYE") {
        await admin.from("escrow_release_queue")
          .update({ statut: "TRAITE", traite_le: new Date().toISOString() })
          .eq("id", rel.queue_id);
        ignores++;
        continue;
      }
      if (["REMBOURSE", "DISPUTE", "ECHOUE"].includes(rel.escrow_statut)) {
        await admin.from("escrow_release_queue")
          .update({ statut: "ECHEC", erreur: `escrow ${rel.escrow_statut}`, traite_le: new Date().toISOString() })
          .eq("id", rel.queue_id);
        echecs++;
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

      // A3 condition 2 : fonds `available` sur le solde connecté ?
      const balance = await stripe.balance.retrieve({ stripeAccount: acct });
      const availEur = (balance.available || []).find((b: any) => b.currency === "eur");
      const availableCents = availEur?.amount ?? 0;

      if (availableCents < rel.honoraires_cents) {
        // Fonds pas encore settled → DISPONIBLE pas atteint. Retry plus tard.
        await admin
          .from("paiements_escrow")
          .update({ statut: "DEBITE", modifie_le: new Date().toISOString() })
          .eq("id", rel.paiement_escrow_id)
          .eq("statut", "INITIE"); // no-op si déjà DEBITE
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

      // Fonds dispo → DISPONIBLE puis RELEASE_PLANIFIE.
      await admin
        .from("paiements_escrow")
        .update({
          statut: "RELEASE_PLANIFIE",
          available_on: new Date().toISOString(),
          disponible_le: new Date().toISOString(),
          release_planifie_le: new Date().toISOString(),
          modifie_le: new Date().toISOString(),
        })
        .eq("id", rel.paiement_escrow_id);

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
        { stripeAccount: acct, idempotencyKey: `release_${rel.paiement_escrow_id}` },
      );

      await admin
        .from("paiements_escrow")
        .update({
          statut: "PAYE",
          stripe_payout_id: payout.id,
          paye_le: new Date().toISOString(),
          modifie_le: new Date().toISOString(),
        })
        .eq("id", rel.paiement_escrow_id);

      // Compteur de confiance A2 (plafond relevé après N missions sans incident).
      await admin.rpc("fn_escrow_incrementer_confiance", { p_etablissement_id: rel.etablissement_id });

      await admin
        .from("escrow_release_queue")
        .update({ statut: "TRAITE", traite_le: new Date().toISOString(), erreur: null })
        .eq("id", rel.queue_id);

      await auditEscrow(admin, "ESCROW_RELEASE_PAYE", rel.mission_id, {
        paiement_escrow_id: rel.paiement_escrow_id,
        stripe_payout_id: payout.id,
        honoraires_cents: rel.honoraires_cents,
        destination: acct,
      });
      payes++;
    } catch (err: any) {
      const code = err?.code || err?.raw?.code || null;
      const msg = err?.message || String(err);
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
    JSON.stringify({ ok: true, examined: rows.length, payes, attente_fonds, echecs, ignores }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
