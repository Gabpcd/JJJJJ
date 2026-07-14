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
import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  assertStripePaymentInstrumentTenant,
  StripePaymentInstrumentConfigurationError,
} from "../_shared/stripe-payment-instrument.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import {
  requireAcquiredStripeSourceCharge,
  StripeSourceChargeValidationError,
} from "../_shared/stripe-source-charge.ts";

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
  if (error) throw new Error(`audit escrow-debit insert: ${error.message}`);
}

async function auditEscrowNonBloquant(
  admin: any,
  action: string,
  missionId: string | null,
  details: unknown,
) {
  try {
    await auditEscrow(admin, action, missionId, details);
  } catch (error) {
    // Un journal d'audit indisponible ne doit jamais faire régresser un état
    // financier déjà confirmé par Stripe et persisté localement.
    console.error("escrow-debit-echeance: audit non financier indisponible", error);
  }
}

async function marquerEchecDebitEscrow(
  admin: any,
  paiementEscrowId: string,
  detail: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("fn_escrow_marquer_echec_debit", {
    p_paiement_escrow_id: paiementEscrowId,
    p_detail: detail.substring(0, 500),
  });
  if (error) throw new Error(`incident débit escrow: ${error.message}`);
  return data === true;
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
        const incidentCree = await marquerEchecDebitEscrow(
          admin,
          esc.id,
          "Mandat SEPA établissement absent au moment du débit",
        );
        if (incidentCree) echoues++;
        else ignores++;
        continue;
      }
      if (!onboarding?.stripe_account_id || onboarding.statut !== "COMPLET") {
        const incidentCree = await marquerEchecDebitEscrow(
          admin,
          esc.id,
          "Compte Stripe Connect soignant non COMPLET au moment du débit",
        );
        if (incidentCree) echoues++;
        else ignores++;
        continue;
      }

      const totalCents = Number(esc.montant_total_cents);
      const honorairesCents = Number(esc.honoraires_cents);
      const commissionCents = Number(esc.commission_cents);
      if (
        !Number.isSafeInteger(totalCents) || totalCents <= 0
        || !Number.isSafeInteger(honorairesCents) || honorairesCents <= 0
        || !Number.isSafeInteger(commissionCents) || commissionCents < 0
        || honorairesCents + commissionCents !== totalCents
      ) {
        const incidentCree = await marquerEchecDebitEscrow(
          admin,
          esc.id,
          "Montants escrow invalides avant débit Stripe",
        );
        await auditEscrowNonBloquant(admin, "ADMIN_ACTION", esc.mission_id, {
          evenement: "ESCROW_DEBIT_IDENTITE_INCOHERENTE",
          paiement_escrow_id: esc.id,
          raison: "INVALID_AMOUNTS",
        });
        if (incidentCree) echoues++;
        else ignores++;
        continue;
      }

      await assertStripePaymentInstrumentTenant(stripe, {
        etablissementId: esc.etablissement_id,
        customerId: etab.stripe_customer_id,
        paymentMethodId: etab.stripe_sepa_payment_method_id,
        paymentMethodType: "sepa_debit",
      });

      const verifierPaymentIntentEscrow = (intent: Stripe.PaymentIntent) => {
        const customerId = typeof intent.customer === "string"
          ? intent.customer
          : intent.customer?.id || null;
        const destinationId = typeof intent.transfer_data?.destination === "string"
          ? intent.transfer_data.destination
          : intent.transfer_data?.destination?.id || null;
        const incoherences: string[] = [];
        if (intent.amount !== totalCents) incoherences.push("amount");
        if (intent.currency !== "eur") incoherences.push("currency");
        if (customerId !== etab.stripe_customer_id) incoherences.push("customer");
        if (intent.application_fee_amount !== commissionCents) {
          incoherences.push("application_fee_amount");
        }
        if (destinationId !== onboarding.stripe_account_id) {
          incoherences.push("destination");
        }
        if (intent.metadata?.type !== "ESCROW_MISSION_PAYMENT") incoherences.push("type");
        if (intent.metadata?.paiement_escrow_id !== esc.id) incoherences.push("paiement_escrow_id");
        if (intent.metadata?.mission_id !== esc.mission_id) incoherences.push("mission_id");
        if (intent.metadata?.etablissement_id !== esc.etablissement_id) {
          incoherences.push("etablissement_id");
        }
        if (incoherences.length > 0) {
          throw Object.assign(new Error("ESCROW_PAYMENT_INTENT_MISMATCH"), {
            code: "ESCROW_PAYMENT_INTENT_MISMATCH",
            incoherences,
            paymentIntentId: intent.id,
          });
        }
      };

      // L'exposition A2 est idempotente côté SQL (UNIQUE paiement_escrow_id +
      // ON CONFLICT DO NOTHING). Elle doit donc être rejouée à chaque passage
      // qui retrouve un PI processing/succeeded, et toute erreur RPC doit
      // conserver la ligne INITIE pour un nouveau passage du cron.
      const enregistrerExpositionEscrow = async (paymentIntentId: string) => {
        const { error: expositionError } = await admin.rpc(
          "fn_escrow_enregistrer_exposition",
          { p_paiement_escrow_id: esc.id },
        );
        if (expositionError) {
          throw Object.assign(new Error("ESCROW_EXPOSITION_PERSISTENCE_FAILED"), {
            code: "ESCROW_EXPOSITION_PERSISTENCE_FAILED",
            paymentIntentId,
          });
        }
      };

      let debitIdempotencyKey = `escrow_debit_${esc.id}`;
      if (esc.stripe_payment_intent_id) {
        const precedent = await stripe.paymentIntents.retrieve(esc.stripe_payment_intent_id);
        verifierPaymentIntentEscrow(precedent);
        if (precedent.status === "succeeded") {
          const sourceCharge = await requireAcquiredStripeSourceCharge(stripe, precedent, {
            customerId: etab.stripe_customer_id,
            amountCents: totalCents,
            currency: "eur",
          });
          await enregistrerExpositionEscrow(precedent.id);
          const chargeId = sourceCharge.id;
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
        if (precedent.status === "processing") {
          await enregistrerExpositionEscrow(precedent.id);
          ignores++;
          continue;
        }
        if (!["canceled", "requires_payment_method"].includes(precedent.status)) {
          // Un débit SEPA off-session ne peut pas attendre une action client.
          // On le sort de la file sans compter d'exposition financière.
          const incidentCree = await marquerEchecDebitEscrow(
            admin,
            esc.id,
            `Statut Stripe non automatisable: ${precedent.status}`,
          );
          await auditEscrowNonBloquant(admin, "ADMIN_ACTION", esc.mission_id, {
            evenement: "ESCROW_DEBIT_STATUT_INATTENDU",
            paiement_escrow_id: esc.id,
            stripe_payment_intent_id: precedent.id,
            pi_status: precedent.status,
          });
          if (incidentCree) echoues++;
          else ignores++;
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
        amount: totalCents,
        currency: "eur",
        customer: etab.stripe_customer_id,
        payment_method: etab.stripe_sepa_payment_method_id,
        payment_method_types: ["sepa_debit"],
        confirm: true,
        off_session: true,
        mandate_data: { customer_acceptance: { type: "offline" } },
        application_fee_amount: commissionCents,
        transfer_data: { destination: onboarding.stripe_account_id },
        transfer_group: `mission_${esc.mission_id}`,
        statement_descriptor: "JOLENE",
        metadata: {
          type: "ESCROW_MISSION_PAYMENT",
          paiement_escrow_id: esc.id,
          mission_id: esc.mission_id,
          soignant_id: esc.soignant_id,
          etablissement_id: esc.etablissement_id,
          honoraires_cents: String(honorairesCents),
          commission_cents: String(commissionCents),
          methode_debit: esc.methode_debit,
        },
      }, { idempotencyKey: debitIdempotencyKey });
      verifierPaymentIntentEscrow(pi);

      if (!["processing", "succeeded"].includes(pi.status)) {
        let referencePiQuery = admin
          .from("paiements_escrow")
          .update({
            stripe_payment_intent_id: pi.id,
            erreur: `Statut Stripe non automatisable: ${pi.status}`,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", esc.id)
          .eq("statut", "INITIE")
          .eq("tentatives_debit", (esc.tentatives_debit ?? 0) + 1);
        referencePiQuery = esc.stripe_payment_intent_id
          ? referencePiQuery.eq("stripe_payment_intent_id", esc.stripe_payment_intent_id)
          : referencePiQuery.is("stripe_payment_intent_id", null);
        const { data: referencePi, error: referencePiError } = await referencePiQuery
          .select("id")
          .maybeSingle();
        if (referencePiError || !referencePi) {
          throw Object.assign(new Error("ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED"), {
            code: "ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED",
            paymentIntentId: pi.id,
            payment_intent: pi.id,
          });
        }
        const incidentCree = await marquerEchecDebitEscrow(
          admin,
          esc.id,
          `Statut Stripe non automatisable: ${pi.status}`,
        );
        await auditEscrowNonBloquant(admin, "ADMIN_ACTION", esc.mission_id, {
          evenement: "ESCROW_DEBIT_STATUT_INATTENDU",
          paiement_escrow_id: esc.id,
          stripe_payment_intent_id: pi.id,
          pi_status: pi.status,
        });
        if (incidentCree) echoues++;
        else ignores++;
        continue;
      }

      // SEPA : `processing` (débit initié, settlement en cours). Le passage
      // DEBITE se fait sur payment_intent.succeeded (webhook). On enregistre le
      // PI et l'exposition (A2) dès l'initiation du débit.
      let liaisonPiQuery = admin
        .from("paiements_escrow")
        .update({
          stripe_payment_intent_id: pi.id,
          erreur: null,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", esc.id)
        .eq("statut", "INITIE")
        .eq("tentatives_debit", (esc.tentatives_debit ?? 0) + 1);
      liaisonPiQuery = esc.stripe_payment_intent_id
        ? liaisonPiQuery.eq("stripe_payment_intent_id", esc.stripe_payment_intent_id)
        : liaisonPiQuery.is("stripe_payment_intent_id", null);
      const { data: paiementLieAuPi, error: liaisonPiError } = await liaisonPiQuery
        .select("id")
        .maybeSingle();
      if (liaisonPiError || !paiementLieAuPi) {
        throw Object.assign(new Error("ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED"), {
          code: "ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED",
          paymentIntentId: pi.id,
          payment_intent: pi.id,
        });
      }

      const sourceChargeImmediate = pi.status === "succeeded"
        ? await requireAcquiredStripeSourceCharge(stripe, pi, {
          customerId: etab.stripe_customer_id,
          amountCents: totalCents,
          currency: "eur",
        })
        : null;

      await enregistrerExpositionEscrow(pi.id);

      if (pi.status === "succeeded") {
        const chargeId = sourceChargeImmediate!.id;
        const { data: debitConfirme, error: debitConfirmeError } = await admin
          .from("paiements_escrow")
          .update({
            statut: "DEBITE",
            stripe_charge_id: chargeId,
            debite_le: new Date().toISOString(),
            modifie_le: new Date().toISOString(),
          })
          .eq("id", esc.id)
          .eq("statut", "INITIE")
          .eq("stripe_payment_intent_id", pi.id)
          .select("id")
          .maybeSingle();
        if (debitConfirmeError || !debitConfirme) {
          throw Object.assign(new Error("ESCROW_PAYMENT_STATUS_PERSISTENCE_FAILED"), {
            code: "ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED",
            paymentIntentId: pi.id,
          });
        }
      }

      await auditEscrowNonBloquant(admin, "ESCROW_DEBIT_INITIE", esc.mission_id, {
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
      if (
        err instanceof StripePaymentInstrumentConfigurationError
        || err?.code === "ESCROW_PAYMENT_INTENT_MISMATCH"
        || err instanceof StripeSourceChargeValidationError
      ) {
        const raison = err instanceof StripePaymentInstrumentConfigurationError
          ? err.code
          : err instanceof StripeSourceChargeValidationError
          ? "STRIPE_SOURCE_CHARGE_NOT_ACQUIRED"
          : "ESCROW_PAYMENT_INTENT_MISMATCH";
        const incidentCree = await marquerEchecDebitEscrow(
          admin,
          esc.id,
          `Configuration Stripe incohérente: ${raison}`,
        );
        await auditEscrowNonBloquant(admin, "ADMIN_ACTION", esc.mission_id, {
          evenement: "ESCROW_DEBIT_IDENTITE_INCOHERENTE",
          paiement_escrow_id: esc.id,
          stripe_payment_intent_id: err?.paymentIntentId || null,
          raison,
          incoherences: err instanceof StripeSourceChargeValidationError
            ? err.checks.map((check) => `source_charge.${check}`)
            : err?.incoherences || [],
        });
        if (incidentCree) echoues++;
        else ignores++;
        continue;
      }
      const code = err?.code || err?.raw?.code || null;
      const msg = err?.message || String(err);
      const failedIntent = err?.payment_intent
        ?? err?.paymentIntentId
        ?? err?.raw?.payment_intent;
      const failedIntentId = typeof failedIntent === "string" ? failedIntent : failedIntent?.id;
      const erreurPersistanceRetryable = [
        "ESCROW_EXPOSITION_PERSISTENCE_FAILED",
        "ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED",
      ].includes(code || "");

      if (erreurPersistanceRetryable) {
        // Ce n'est pas un échec de débit Stripe : ne jamais geler la ligne ni
        // la sortir de la file au troisième passage. Si Stripe a déjà créé le
        // PI, on tente de restaurer sa liaison avec un CAS exact, puis on remet
        // le compteur sous la borne de sélection pour rejouer l'exposition.
        let retryPersistenceQuery = admin
          .from("paiements_escrow")
          .update({
            ...(failedIntentId ? { stripe_payment_intent_id: failedIntentId } : {}),
            tentatives_debit: Math.min(esc.tentatives_debit ?? 0, 2),
            erreur: `${code} — réconciliation locale à rejouer`.substring(0, 500),
            modifie_le: new Date().toISOString(),
          })
          .eq("id", esc.id)
          .eq("statut", "INITIE");
        if (failedIntentId) {
          retryPersistenceQuery = esc.stripe_payment_intent_id
            ? retryPersistenceQuery.or(
              `stripe_payment_intent_id.eq.${esc.stripe_payment_intent_id},stripe_payment_intent_id.eq.${failedIntentId}`,
            )
            : retryPersistenceQuery.or(
              `stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${failedIntentId}`,
            );
        }
        const { data: retryPersisted, error: retryPersistenceError } =
          await retryPersistenceQuery.select("id").maybeSingle();
        if (retryPersistenceError || !retryPersisted) {
          throw new Error(
            `Escrow retry state persistence failed: ${retryPersistenceError?.message || "row missing"}`,
          );
        }
        ignores++;
        console.error(
          `escrow-debit-echeance mission=${esc.mission_id} code=${code} retry=local_persistence`,
        );
        continue;
      }

      if (failedIntentId) {
        // Une erreur de confirmation peut néanmoins contenir un PI Stripe
        // certain. Le conserver permet au passage suivant de distinguer le
        // rejeu ambigu d'une vraie génération terminale suivante.
        let failedIntentQuery = admin
          .from("paiements_escrow")
          .update({
            stripe_payment_intent_id: failedIntentId,
            erreur: `${code || "erreur"} — ${msg}`.substring(0, 500),
            modifie_le: new Date().toISOString(),
          })
          .eq("id", esc.id)
          .eq("statut", "INITIE");
        failedIntentQuery = esc.stripe_payment_intent_id
          ? failedIntentQuery.eq(
            "stripe_payment_intent_id",
            esc.stripe_payment_intent_id,
          )
          : failedIntentQuery.is("stripe_payment_intent_id", null);
        const { data: failedIntentPersisted, error: failedIntentPersistenceError } =
          await failedIntentQuery.select("id").maybeSingle();
        if (failedIntentPersistenceError || !failedIntentPersisted) {
          throw new Error(
            `Failed Stripe PaymentIntent persistence failed: ${failedIntentPersistenceError?.message || "row missing"}`,
          );
        }
      }
      // Après 3 tentatives, on gèle + relance J+3 (incident). Avant, on laisse
      // la ligne INITIE pour un retry au prochain passage du cron.
      if ((esc.tentatives_debit ?? 0) + 1 >= 3) {
        const incidentCree = await marquerEchecDebitEscrow(
          admin,
          esc.id,
          `${code || "erreur"} — ${msg}`,
        );
        if (incidentCree) echoues++;
        else ignores++;
      } else {
        const { data: retryState, error: retryStateError } = await admin
          .from("paiements_escrow")
          .update({ erreur: `${code || "erreur"} — ${msg}`.substring(0, 500), modifie_le: new Date().toISOString() })
          .eq("id", esc.id)
          .eq("statut", "INITIE")
          .select("id")
          .maybeSingle();
        if (retryStateError || !retryState) {
          throw new Error(
            `Escrow retry error persistence failed: ${retryStateError?.message || "row missing"}`,
          );
        }
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
