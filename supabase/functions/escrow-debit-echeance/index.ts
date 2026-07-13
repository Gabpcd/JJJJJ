/**
 * escrow-debit-echeance — Escrow 7b-D PR 3
 *
 * Déclenché par pg_cron (toutes les heures). Crée la DESTINATION CHARGE Stripe
 * de chaque paiement escrow INITIE arrivé à échéance (debit_prevu_le <= now).
 *
 * Modèle destination charge (invariant : aucun fonds de mission ne stationne
 * sur le solde plateforme de Jolene) :
 *   - charge sur le mandat SEPA de l'établissement (off_session, mandate_data
 *     offline — même pattern que sepa-auto-charge, éprouvé en prod)
 *   - transfer_data[destination] = compte connecté du soignant
 *   - application_fee_amount = commission (seule part qui revient à Jolene)
 *   - PAS de on_behalf_of : le mandat SEPA signé par l'étab (setup-sepa) nomme
 *     JOLENE comme créancier — avec on_behalf_of, Stripe exige un mandat au
 *     nom du compte connecté et n'en trouve pas (« no existing mandate was
 *     found », recette run #7 du 09/07). Le marchand du débit est Jolene ;
 *   → les honoraires vont quand même DIRECTEMENT au solde connecté du soignant.
 *
 * La charge SEPA passe en `processing` puis `succeeded` (J+quelques jours) :
 * ce webhook (stripe-webhook, branche ESCROW_MISSION_PAYMENT) fait passer
 * paiements_escrow INITIE → DEBITE. Le release (payout) attend en plus que les
 * fonds soient `available` sur le solde connecté (A3, consumer PR 5).
 *
 * Auth : Bearer service_role (env) ou secret vault sb_secret_* (pg_cron),
 * cf. CLAUDE.md « Auth crons pg_cron ».
 *
 * NO-OP si feature_paiement_rapide_actif = 0 : aucun paiements_escrow n'existe
 * (le trigger de création est gaté par le même flag).
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

// Audit DIRECT en table (pas via le rpc fn_ecrire_audit_safe) : le binding
// PostgREST de ce RPC 9-params sérialise les uuid en « null » → l'audit edge
// échouait silencieusement (trou d'observabilité prod, recette escrow run #11).
// service_role bypasse la RLS. Les fonctions DB gardent le wrapper.
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
      navigateur_acteur: "escrow-debit-echeance",
    });
    if (error) console.error("audit escrow-debit insert:", error.message);
  } catch (e) { console.error("audit escrow-debit throw:", e); }
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

  // TODO(Lot 14) — Débit complémentaire heures supplémentaires : c'est ICI la
  // mécanique. Quand la validation étab (déclencheur, PresencesEtablissement /
  // fn_valider_presence) constate effectif > prévisionnel sur une mission ⚡,
  // enfiler un débit SEPA du delta sur le MÊME mandat (delta × taux +
  // majorations, commission 15 %), en cycle escrow propre lié à la mission.
  // Aujourd'hui l'escrow ne couvre que le prévisionnel figé à la confirmation
  // (règle #11, aucun top-up). Cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md §9.3.

  // Débits à échéance (INITIE, debit_prevu_le <= now, < 3 tentatives).
  const { data: dus, error: dusErr } = await admin.rpc("fn_escrow_debits_a_echeance", { p_limit: 50 });
  if (dusErr) {
    return new Response(JSON.stringify({ error: dusErr.message }), { status: 500 });
  }

  const rows = (dus as any[]) || [];
  let debites = 0, echoues = 0, ignores = 0;

  for (const esc of rows) {
    try {
      // Relire les données fraîches nécessaires (montants déjà figés dans esc).
      const { data: etab } = await admin
        .from("etablissements")
        .select("stripe_customer_id, stripe_sepa_payment_method_id, mode_paiement_commission")
        .eq("id", esc.etablissement_id)
        .maybeSingle();

      const { data: onboarding } = await admin
        .from("stripe_connect_onboarding")
        .select("stripe_account_id, statut")
        .eq("soignant_id", esc.soignant_id)
        .maybeSingle();

      // Garde-fous : mandat SEPA + compte connecté complet. Si l'un manque
      // (mandat révoqué, onboarding incomplet), on abandonne proprement cette
      // ligne → régime standard (marquée ECHOUE, pas de retry infini).
      if (!etab?.stripe_customer_id || !etab?.stripe_sepa_payment_method_id
          || etab.mode_paiement_commission !== "SEPA_DEBIT") {
        await admin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: esc.id, p_type_incident: "ECHEC",
          p_detail: "Mandat SEPA établissement absent au moment du débit",
        });
        echoues++;
        continue;
      }
      if (!onboarding?.stripe_account_id || onboarding.statut !== "COMPLET") {
        await admin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: esc.id, p_type_incident: "ECHEC",
          p_detail: "Compte Stripe Connect soignant non COMPLET au moment du débit",
        });
        echoues++;
        continue;
      }

      let debitIdempotencyKey = `escrow_debit_${esc.id}`;
      if (esc.stripe_payment_intent_id) {
        const precedent = await stripe.paymentIntents.retrieve(esc.stripe_payment_intent_id);
        if (precedent.status === "succeeded") {
          const chargeId = precedent.latest_charge
            ? (typeof precedent.latest_charge === "string" ? precedent.latest_charge : precedent.latest_charge.id)
            : null;
          const { data: recupere } = await admin
            .from("paiements_escrow")
            .update({
              statut: "DEBITE",
              stripe_charge_id: chargeId,
              debite_le: new Date().toISOString(),
              erreur: null,
              modifie_le: new Date().toISOString(),
            })
            .eq("id", esc.id)
            .eq("statut", "INITIE")
            .eq("stripe_payment_intent_id", precedent.id)
            .select("id")
            .maybeSingle();
          if (recupere) debites++;
          else ignores++;
          continue;
        }
        if (!["canceled", "requires_payment_method"].includes(precedent.status)) {
          // processing/requires_action : une opération Stripe existe déjà.
          ignores++;
          continue;
        }
        // Le précédent PI est certain et terminal : une nouvelle tentative a
        // une clé fraîche mais déterministe. Deux workers créent donc le même PI.
        debitIdempotencyKey = `escrow_debit_${esc.id}_after_${precedent.id}`;
      }

      // Claim optimiste : un seul worker compte et lance cette tentative.
      const { data: tentativeReservee, error: tentativeErr } = await admin
        .from("paiements_escrow")
        .update({ tentatives_debit: (esc.tentatives_debit ?? 0) + 1, derniere_tentative_le: new Date().toISOString() })
        .eq("id", esc.id)
        .eq("statut", "INITIE")
        .eq("tentatives_debit", esc.tentatives_debit ?? 0)
        .select("id")
        .maybeSingle();
      if (tentativeErr) throw tentativeErr;
      if (!tentativeReservee) {
        ignores++;
        continue;
      }

      // DESTINATION CHARGE — un rejeu ambigu conserve la même clé ; seul un PI
      // terminal et connu fait avancer la version déterministe ci-dessus.
      const pi = await stripe.paymentIntents.create({
        amount: esc.montant_total_cents,
        currency: "eur",
        customer: etab.stripe_customer_id,
        payment_method: etab.stripe_sepa_payment_method_id,
        payment_method_types: ["sepa_debit"],
        confirm: true,
        off_session: true,
        mandate_data: { customer_acceptance: { type: "offline" } },
        application_fee_amount: esc.commission_cents,
        transfer_data: { destination: onboarding.stripe_account_id },
        transfer_group: `mission_${esc.mission_id}`,
        statement_descriptor: "JOLENE",
        metadata: {
          type: "ESCROW_MISSION_PAYMENT",
          paiement_escrow_id: esc.id,
          mission_id: esc.mission_id,
          soignant_id: esc.soignant_id,
          etablissement_id: esc.etablissement_id,
          honoraires_cents: String(esc.honoraires_cents),
          commission_cents: String(esc.commission_cents),
          methode_debit: esc.methode_debit,
        },
      }, { idempotencyKey: debitIdempotencyKey });

      // SEPA : `processing` (débit initié, settlement en cours). Le passage
      // DEBITE se fait sur payment_intent.succeeded (webhook). On enregistre le
      // PI et l'exposition (A2) dès l'initiation du débit.
      await admin
        .from("paiements_escrow")
        .update({
          stripe_payment_intent_id: pi.id,
          erreur: null,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", esc.id)
        .eq("statut", "INITIE");

      await admin.rpc("fn_escrow_enregistrer_exposition", { p_paiement_escrow_id: esc.id });

      await auditEscrow(admin, "ESCROW_DEBIT_INITIE", esc.mission_id, {
        paiement_escrow_id: esc.id,
        stripe_payment_intent_id: pi.id,
        pi_status: pi.status,
        methode_debit: esc.methode_debit,
        total_cents: esc.montant_total_cents,
        honoraires_cents: esc.honoraires_cents,
        commission_cents: esc.commission_cents,
        destination: onboarding.stripe_account_id,
      });
      debites++;
    } catch (err: any) {
      const code = err?.code || err?.raw?.code || null;
      const msg = err?.message || String(err);
      const failedIntent = err?.payment_intent ?? err?.raw?.payment_intent;
      const failedIntentId = typeof failedIntent === "string" ? failedIntent : failedIntent?.id;
      if (failedIntentId) {
        // Une erreur de confirmation peut néanmoins contenir un PI Stripe
        // certain. Le conserver permet au passage suivant de distinguer le
        // rejeu ambigu d'une vraie génération terminale suivante.
        await admin
          .from("paiements_escrow")
          .update({
            stripe_payment_intent_id: failedIntentId,
            erreur: `${code || "erreur"} — ${msg}`.substring(0, 500),
            modifie_le: new Date().toISOString(),
          })
          .eq("id", esc.id)
          .eq("statut", "INITIE");
      }
      // Après 3 tentatives, on gèle + relance J+3 (incident). Avant, on laisse
      // la ligne INITIE pour un retry au prochain passage du cron.
      if ((esc.tentatives_debit ?? 0) + 1 >= 3) {
        await admin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: esc.id, p_type_incident: "ECHEC",
          p_detail: `${code || "erreur"} — ${msg}`.substring(0, 500),
        });
        echoues++;
      } else {
        await admin
          .from("paiements_escrow")
          .update({ erreur: `${code || "erreur"} — ${msg}`.substring(0, 500), modifie_le: new Date().toISOString() })
          .eq("id", esc.id);
        ignores++;
      }
      console.error(`escrow-debit-echeance mission=${esc.mission_id} code=${code} msg=${msg}`);
    }
  }

  return new Response(
    JSON.stringify({ ok: true, examined: rows.length, debites, echoues, retry_plus_tard: ignores }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
