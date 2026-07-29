import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { writeRequiredFinancialAudit } from "../_shared/financial-audit.ts";
import { mapStripeError } from "../_shared/stripe-errors.ts";
import {
  acquireStripePaymentFlowClaim,
  bindStripePaymentFlowClaimSession,
  releaseStripePaymentFlowClaimForExpiredSession,
} from "../_shared/stripe-payment-flow-claim.ts";
import {
  ensureCanonicalEtablissementCustomer,
  mapStripeCustomerConfigurationError,
} from "../_shared/stripe-customer.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import { requireAcquiredStripeSourceCharge } from "../_shared/stripe-source-charge.ts";
import { resolveOperationalTestAccount } from "../_shared/test-account.ts";

function objectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "id" in value && typeof value.id === "string") {
    return value.id;
  }
  return null;
}

function getApplicationReturnOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  return [
    "https://jolene.app",
    "https://app.jolene.app",
    "https://www.jolene.app",
    "http://localhost:5173",
    "http://localhost:8080",
  ].includes(origin) ? origin : "https://jolene.app";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Méthode non autorisée" }), {
      status: 405,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseAdmin = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  let step = "init";

  try {
    step = "1_auth_header";
    const authHeader = req.headers.get("Authorization");
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) {
      return new Response(JSON.stringify({ error: auth.error }), {
        status: auth.status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    // Ce Checkout engage l'établissement dans un paiement interactif. Les
    // secrets internes n'ont aucun motif de cibler ce point d'entrée public.
    if (auth.isServiceRole || !auth.userId || !authHeader) {
      return new Response(JSON.stringify({ error: "Session utilisateur requise" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    console.log(`[stripe-connect-pay-mission] step=2 user=${auth.userId}`);

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    const body = await req.json().catch(() => null) as {
      mission_id?: unknown;
      facture_honoraire_id?: unknown;
    } | null;
    const mission_id = typeof body?.mission_id === "string" ? body.mission_id : "";
    const requestedFactureHonorairesId = typeof body?.facture_honoraire_id === "string"
      ? body.facture_honoraire_id
      : "";
    if (!mission_id) {
      return new Response(JSON.stringify({ error: "mission_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Fetch mission
    const { data: mission, error: missionError } = await supabaseAdmin
      .from("missions")
      .select(
        "id, etablissement_id, soignant_assigne_id, statut, montant_commission_ttc, net_a_payer, type_contrat_applique, commission_facturee, mode_paiement_soignant, strategie_facturation"
      )
      .eq("id", mission_id)
      .maybeSingle();

    if (missionError) throw new Error(`Lecture mission impossible: ${missionError.message}`);
    if (!mission) {
      return new Response(JSON.stringify({ error: "Mission introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: hasPaymentPermission, error: permissionError } = await supabaseUser.rpc(
      "fn_a_permission_etablissement",
      { p_permission: "paiement", p_etablissement_id: mission.etablissement_id },
    );
    if (permissionError) {
      throw new Error(`Vérification des droits de paiement impossible: ${permissionError.message}`);
    }
    if (hasPaymentPermission !== true) {
      return new Response(
        JSON.stringify({ error: "Vous n'avez pas les droits de paiement sur cet établissement" }),
        {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        },
      );
    }

    const [etablissementTest, soignantTest] = await Promise.all([
      resolveOperationalTestAccount(
        supabaseAdmin,
        mission.etablissement_id,
      ),
      mission.soignant_assigne_id
        ? resolveOperationalTestAccount(
          supabaseAdmin,
          mission.soignant_assigne_id,
        )
        : Promise.resolve({
          ok: false as const,
          error: "soignant non assigné",
        }),
    ]);
    if (!etablissementTest.ok || !soignantTest.ok) {
      return new Response(JSON.stringify({
        error: "TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE",
      }), {
        status: 503,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (etablissementTest.isTest || soignantTest.isTest) {
      return new Response(JSON.stringify({
        error: "TEST_ACCOUNT_PAYMENT_DISABLED",
      }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: requestedFactureHonoraires, error: requestedFactureHonorairesError } =
      requestedFactureHonorairesId
        ? await supabaseAdmin
          .from("factures_honoraires")
          .select("id, statut, montant_ttc, mission_id, soignant_id, etablissement_id, stripe_payment_intent_id, periode_debut, periode_fin, est_facture_finale_mission")
          .eq("id", requestedFactureHonorairesId)
          .maybeSingle()
        : { data: null, error: null };
    if (requestedFactureHonorairesError) {
      throw new Error(`Lecture facture d'honoraires impossible: ${requestedFactureHonorairesError.message}`);
    }
    if (
      requestedFactureHonorairesId
      && (
        !requestedFactureHonoraires
        || requestedFactureHonoraires.mission_id !== mission_id
        || requestedFactureHonoraires.etablissement_id !== mission.etablissement_id
        || requestedFactureHonoraires.soignant_id !== mission.soignant_assigne_id
      )
    ) {
      return new Response(JSON.stringify({ error: "Facture d'honoraires introuvable pour cette mission" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const invoiceScopedPayment = Boolean(requestedFactureHonoraires);
    const weeklyInvoicePayable = Boolean(
      requestedFactureHonoraires
      && mission.strategie_facturation === "HEBDO_ET_FINALE"
      && requestedFactureHonoraires.est_facture_finale_mission === false
      && requestedFactureHonoraires.periode_fin < new Date().toISOString().slice(0, 10)
      && ["EN_COURS", "TERMINEE"].includes(mission.statut),
    );
    if (mission.statut !== "TERMINEE" && !weeklyInvoicePayable) {
      return new Response(
        JSON.stringify({ error: "La mission doit être terminée, ou la facture doit porter sur une semaine close" }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // BUG-UI-OBLIG-1 Fix#3 — défense en profondeur : les missions SALARIE
    // ne peuvent pas être payées via Stripe (bulletin de paie + virement SEPA).
    if (mission.type_contrat_applique !== "LIBERAL") {
      return new Response(
        JSON.stringify({
          error: "CONTRAT_SALARIE_NON_STRIPE",
          message:
            "Les missions en contrat salarié doivent être payées par virement SEPA (bulletin de paie). Utilisez le flux 'Déclarer virement' à la place.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    let paiementFinalQuery = supabaseAdmin
        .from("stripe_transfers")
        .select("id, statut")
        .eq("mission_id", mission_id)
        .in("statut", ["TRANSFERE", "CHARGE_REUSSI", "PAYE"]);
    if (invoiceScopedPayment) {
      paiementFinalQuery = paiementFinalQuery.eq(
        "facture_honoraire_id",
        requestedFactureHonoraires!.id,
      );
    }
    const { data: paiementConnectDejaFinal, error: paiementConnectDejaFinalError } =
      await paiementFinalQuery
        .order("cree_le", { ascending: false })
        .limit(1)
        .maybeSingle();
    if (paiementConnectDejaFinalError) {
      throw new Error(
        `Lecture paiement Connect final impossible: ${paiementConnectDejaFinalError.message}`,
      );
    }
    if (!invoiceScopedPayment && mission.commission_facturee && !paiementConnectDejaFinal) {
      return new Response(JSON.stringify({
        error: "COMMISSION_DEJA_REGLEE",
        message: "La commission de cette mission est déjà facturée ou réglée.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: paiementCommissionActif, error: paiementCommissionActifError } =
      await supabaseAdmin
        .from("paiements_mission")
        .select("id, statut, stripe_payment_intent_id")
        .eq("mission_id", mission_id)
        .in("statut", ["EN_ATTENTE", "AUTORISE", "CAPTURE"])
        .order("cree_le", { ascending: false })
        .limit(1)
        .maybeSingle();
    if (paiementCommissionActifError) {
      throw new Error(
        `Lecture réservation commission impossible: ${paiementCommissionActifError.message}`,
      );
    }
    if (!invoiceScopedPayment && paiementCommissionActif && !paiementConnectDejaFinal) {
      return new Response(JSON.stringify({
        error: "COMMISSION_DEJA_REVENDIQUEE",
        message:
          "La commission possède déjà une autorisation ou un prélèvement en cours. Le paiement groupé Connect est indisponible.",
        status: paiementCommissionActif.statut,
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: etab, error: etabError } = await supabaseAdmin
      .from("etablissements")
      .select("id, stripe_customer_id, nom, email_contact")
      .eq("id", mission.etablissement_id)
      .maybeSingle();

    if (etabError) throw new Error(`Lecture établissement impossible: ${etabError.message}`);
    if (!etab) {
      return new Response(
        JSON.stringify({ error: "Établissement introuvable" }),
        {
          status: 404,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Check soignant is LIBERAL or MIXTE
    const soignantId = mission.soignant_assigne_id;
    const { data: soignant } = await supabaseAdmin
      .from("soignants")
      .select("type_exercice, statut_liberal")
      .eq("id", soignantId)
      .single();

    const soignantEligible = soignant && (
      soignant.type_exercice === "LIBERAL"
      || soignant.type_exercice === "MIXTE"
      || (soignant as any).statut_liberal === "ACTIF"
    );

    if (!soignantEligible && !paiementConnectDejaFinal) {
      return new Response(
        JSON.stringify({
          error:
            "Le paiement Connect est réservé aux soignants en exercice libéral ou mixte",
        }),
        {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Le rapprochement Connect est la source d'idempotence prioritaire. Ce
    // contrôle doit précéder les factures, car celles-ci sont normalement déjà
    // PAYEE après succès : un simple rafraîchissement ne doit alors ni produire
    // une erreur de facture, ni ouvrir une nouvelle tentative de paiement.
    let existingTransferQuery = supabaseAdmin
      .from("stripe_transfers")
      .select(
        "id, statut, cree_le, stripe_checkout_session_id, stripe_payment_intent_id, stripe_transfer_id",
      )
      .eq("mission_id", mission_id);
    if (invoiceScopedPayment) {
      existingTransferQuery = existingTransferQuery.eq(
        "facture_honoraire_id",
        requestedFactureHonoraires!.id,
      );
    }
    const { data: existingTransfer, error: existingTransferError } = await existingTransferQuery
      .order("cree_le", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (existingTransferError) {
      throw new Error(`Lecture paiement Connect impossible: ${existingTransferError.message}`);
    }

    const FENETRE_ORPHELIN_MINUTES = 15;
    let transferStatutCourant: string | null = existingTransfer?.statut ?? null;
    const statutAutoriseNouvelleTentative = !!existingTransfer
      && ["REMBOURSE", "ANNULEE"].includes(existingTransfer.statut);

    // [CP-STRIPE-2 H1/H14] Lookup facture_honoraires liée à la mission.
    // On exige qu'elle existe avant de créer la Checkout Session — ainsi on
    // peut (1) injecter son id dans la metadata Stripe pour que le webhook
    // update le bon row, (2) éviter les sessions orphelines si la facture
    // n'a jamais été générée, (3) supporter les avoirs AUTO_STRIPE futurs
    // qui nécessitent un stripe_payment_intent_id sur la facture d'origine.
    const factureHonoraires = requestedFactureHonoraires || (
      await supabaseAdmin
        .from("factures_honoraires")
        .select("id, statut, montant_ttc, mission_id, soignant_id, etablissement_id, stripe_payment_intent_id, periode_debut, periode_fin, est_facture_finale_mission")
        .eq("mission_id", mission_id)
        .eq("soignant_id", soignantId)
        .eq("etablissement_id", mission.etablissement_id)
        .in("statut", ["EMISE", "EN_RETARD", "PAYEE"])
        .order("date_emission", { ascending: true })
        .limit(1)
        .maybeSingle()
    ).data;

    if (!factureHonoraires) {
      return new Response(
        JSON.stringify({
          error: "FACTURE_NON_GENEREE",
          message:
            "Facture honoraires non générée pour cette mission. Cliquez sur 'Générer facture' avant de payer.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }
    if (
      factureHonoraires.statut === "PAYEE"
      && (
        !paiementConnectDejaFinal
        || factureHonoraires.stripe_payment_intent_id
          !== existingTransfer?.stripe_payment_intent_id
      )
    ) {
      return new Response(JSON.stringify({
        error: "FACTURE_HONORAIRES_DEJA_PAYEE",
        message: "Cette facture d'honoraires est déjà liée à un autre paiement.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // D6 : la facture de commission est liée à la facture d'honoraires exacte.
    // Le fallback mission_id ne sert qu'aux anciennes missions déjà facturées.
    let { data: factureCommission, error: factureCommissionError } = await supabaseAdmin
      .from("factures")
      .select(
        "id, statut, montant_ttc, montant_ht, montant_tva, stripe_payment_intent_id, stripe_hosted_url, mission_id, etablissement_id, facture_honoraire_id",
      )
      .eq("facture_honoraire_id", factureHonoraires.id)
      .eq("type_document", "FACTURE")
      .neq("statut", "ANNULEE")
      .maybeSingle();
    if (!factureCommission && !factureCommissionError && !invoiceScopedPayment) {
      const legacyCommission = await supabaseAdmin
        .from("factures")
        .select(
          "id, statut, montant_ttc, montant_ht, montant_tva, stripe_payment_intent_id, stripe_hosted_url, mission_id, etablissement_id, facture_honoraire_id",
        )
        .eq("mission_id", mission_id)
        .is("facture_honoraire_id", null)
        .eq("type_document", "FACTURE")
        .neq("statut", "ANNULEE")
        .maybeSingle();
      factureCommission = legacyCommission.data;
      factureCommissionError = legacyCommission.error;
    }
    if (!factureCommission && !factureCommissionError) {
      const { error: prepareCommissionError } = await supabaseAdmin.rpc(
        "fn_preparer_facture_commission_periode",
        { p_facture_honoraire_id: factureHonoraires.id },
      );
      if (prepareCommissionError) {
        throw new Error(`Préparation facture commission impossible: ${prepareCommissionError.message}`);
      }
      const preparedCommission = await supabaseAdmin
        .from("factures")
        .select(
          "id, statut, montant_ttc, montant_ht, montant_tva, stripe_payment_intent_id, stripe_hosted_url, mission_id, etablissement_id, facture_honoraire_id",
        )
        .eq("facture_honoraire_id", factureHonoraires.id)
        .eq("type_document", "FACTURE")
        .neq("statut", "ANNULEE")
        .maybeSingle();
      factureCommission = preparedCommission.data;
      factureCommissionError = preparedCommission.error;
    }
    if (factureCommissionError) {
      throw new Error(`Lecture facture commission impossible: ${factureCommissionError.message}`);
    }
    const factureCommissionLieeAuConnectCourant = Boolean(
      factureCommission?.stripe_payment_intent_id
      && factureCommission.stripe_payment_intent_id === existingTransfer?.stripe_payment_intent_id
      && existingTransfer
      && ["EN_ATTENTE", "ECHOUE", "CHARGE_REUSSI", "TRANSFERE", "PAYE"].includes(
        existingTransfer.statut,
      ),
    );
    if (
      factureCommission
      && (
        !["EMISE", "EN_RETARD", "PAYEE"].includes(factureCommission.statut)
        || (factureCommission.stripe_payment_intent_id && !factureCommissionLieeAuConnectCourant)
        || (factureCommission.stripe_hosted_url && !paiementConnectDejaFinal)
      )
    ) {
      return new Response(JSON.stringify({
        error: "COMMISSION_DEJA_FACTUREE_OU_NON_PAYABLE",
        message: "La commission de cette mission ne peut pas être incluse dans un nouveau paiement.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Check soignant has Connect account
    const { data: connectOnboarding } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("stripe_account_id, statut")
      .eq("soignant_id", soignantId)
      .maybeSingle();

    if (
      !connectOnboarding ||
      !connectOnboarding.stripe_account_id
      || (connectOnboarding.statut !== "COMPLET" && !paiementConnectDejaFinal)
    ) {
      return new Response(
        JSON.stringify({
          error: "Le soignant n'a pas de compte Stripe Connect actif",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // BUG-UI-OBLIG-1 Fix#2 — idempotence avec fenêtre de 15 min pour
    // éviter qu'un transfer `EN_ATTENTE` orphelin (Checkout abandonné, session
    // expirée, erreur Stripe non propagée) bloque indéfiniment la re-tentative.
    //   - TRANSFERE / CHARGE_REUSSI / PAYE  : paiement réellement abouti → bloquer.
    //   - EN_ATTENTE < 15 min               : paiement Stripe possiblement en vol → bloquer, message timing.
    //   - EN_ATTENTE >= 15 min              : orphelin → marquer ECHOUE puis laisser repartir une nouvelle session.
    const transferAReutiliserId: string | null = existingTransfer?.id ?? null;

    if (existingTransfer?.statut === "EN_ATTENTE") {
      const ageMs = Date.now() - new Date(existingTransfer.cree_le).getTime();
      const ageMinutes = Math.floor(ageMs / 60000);

      if (ageMinutes < FENETRE_ORPHELIN_MINUTES) {
        const minutesRestantes = FENETRE_ORPHELIN_MINUTES - ageMinutes;
        return new Response(
          JSON.stringify({
            already_paid: true,
            statut: "EN_ATTENTE",
            message: `Paiement en cours de traitement Stripe, réessayez dans ${minutesRestantes} minute${minutesRestantes > 1 ? "s" : ""}.`,
          }),
          {
            status: 200,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          }
        );
      }

      // Orphelin > 15 min : marquer ECHOUE et autoriser une nouvelle session.
      const { data: nettoye, error: nettoyageErr } = await supabaseAdmin
        .from("stripe_transfers")
        .update({
          statut: "ECHOUE",
          erreur: `Orphelin auto-cleanup (>${FENETRE_ORPHELIN_MINUTES} min sans webhook) — BUG-UI-OBLIG-1`,
        })
        .eq("id", existingTransfer.id)
        .eq("statut", "EN_ATTENTE")
        .select("id")
        .maybeSingle();
      if (nettoyageErr) throw nettoyageErr;
      if (!nettoye) {
        return new Response(JSON.stringify({
          already_paid: true,
          statut: "EN_ATTENTE",
          message: "Une autre tentative de paiement est déjà en cours.",
        }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      transferStatutCourant = "ECHOUE";
    }

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
    assertStripeSecretMode(stripeKey);
    const stripe = new Stripe(stripeKey, {
      apiVersion: "2026-02-25.clover",
    });

    const commissionCents = Math.round(Number(factureCommission?.montant_ttc ?? 0) * 100);
    const soignantCents = Math.round(Number(factureHonoraires.montant_ttc ?? 0) * 100);
    const totalCents = commissionCents + soignantCents;
    const factureHonorairesCents = Math.round(Number(factureHonoraires.montant_ttc ?? 0) * 100);
    const factureCommissionCents = factureCommission
      ? Math.round(Number(factureCommission.montant_ttc ?? 0) * 100)
      : commissionCents;
    if (
      !Number.isSafeInteger(commissionCents) || commissionCents <= 0
      || !Number.isSafeInteger(soignantCents) || soignantCents <= 0
      || !Number.isSafeInteger(totalCents) || totalCents <= 0
      || !Number.isSafeInteger(factureHonorairesCents)
      || factureHonorairesCents !== soignantCents
      || !Number.isSafeInteger(factureCommissionCents)
      || factureCommissionCents !== commissionCents
      || (!invoiceScopedPayment && (
        commissionCents !== Math.round(Number(mission.montant_commission_ttc ?? 0) * 100)
        || soignantCents !== Math.round(Number(mission.net_a_payer ?? 0) * 100)
      ))
    ) {
      return new Response(JSON.stringify({
        error: "MONTANTS_PAIEMENT_INCOHERENTS",
        message: "Les montants de la mission et de la facture d'honoraires doivent être vérifiés.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const customerId = await ensureCanonicalEtablissementCustomer(
      stripe,
      supabaseAdmin,
      etab,
    );

    // Une Session Checkout standard embarquée peut ne pas encore avoir de PI ni
    // d'URL persistée. La rechercher directement chez Stripe ferme donc la
    // seconde moitié du verrou d'exclusion entre paiement de facture commission
    // et paiement groupé Connect.
    if (factureCommission) {
      const sessionsCustomer = await stripe.checkout.sessions.list({
        customer: customerId,
        limit: 100,
      });
      const standardInvoiceClaim = sessionsCustomer.data.find((candidate) => (
        candidate.metadata?.facture_id === factureCommission.id
        && ["open", "complete"].includes(candidate.status || "")
      ));
      if (standardInvoiceClaim) {
        return new Response(JSON.stringify({
          error: "PAIEMENT_FACTURE_DEJA_REVENDIQUE",
          message:
            "La commission de cette mission possède déjà une tentative de paiement Stripe.",
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    // Le lookup Stripe précède volontairement l'acquisition : il couvre une
    // Session embedded standard créée avant le déploiement de la table de
    // claims, sans laisser derrière lui un claim CONNECT qui bloquerait ensuite
    // la reprise du Checkout standard. Le CAS par PK mission ferme la course
    // pour toutes les créations nouvelles.
    const paymentFlowClaimExpected = invoiceScopedPayment
      ? {
        mission_id: null,
        facture_id: factureCommission!.id,
        flow: "CONNECT_INVOICE" as const,
        owner_token: `connect-invoice:${factureHonoraires.id}`,
      }
      : {
        mission_id,
        facture_id: null,
        flow: "CONNECT_MISSION" as const,
        owner_token: `connect:${mission_id}`,
      };
    const paymentFlowClaim = await acquireStripePaymentFlowClaim(
      supabaseAdmin,
      paymentFlowClaimExpected,
    );
    const recoveryPaiementFinal = Boolean(
      existingTransfer
      && ["TRANSFERE", "CHARGE_REUSSI", "PAYE"].includes(existingTransfer.statut),
    );
    if (!paymentFlowClaim.acquired && !recoveryPaiementFinal) {
      return new Response(JSON.stringify({
        error: "PAIEMENT_MISSION_DEJA_REVENDIQUE",
        message:
          "Cette mission possède déjà un autre flux de paiement Stripe en cours.",
        claimed_by: paymentFlowClaim.claim.flow,
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const verifierSessionConnect = async (
      session: Stripe.Checkout.Session,
      requireSucceededIntent: boolean,
    ): Promise<string[]> => {
      const incoherences: string[] = [];
      const metadata = session.metadata || {};
      if (objectId(session.customer) !== customerId) incoherences.push("session.customer");
      if (session.currency !== "eur") incoherences.push("session.currency");
      if (session.amount_total !== totalCents) incoherences.push("session.amount_total");
      if (session.client_reference_id !== mission_id) incoherences.push("session.mission_reference");
      if (metadata.type !== "CONNECT_MISSION_PAYMENT") incoherences.push("session.type");
      if (metadata.mission_id !== mission_id) incoherences.push("session.mission_id");
      if (metadata.etablissement_id !== mission.etablissement_id) {
        incoherences.push("session.etablissement_id");
      }
      if (metadata.soignant_id !== soignantId) incoherences.push("session.soignant_id");
      if (metadata.connected_account_id !== connectOnboarding.stripe_account_id) {
        incoherences.push("session.connected_account_id");
      }
      if (metadata.soignant_cents !== String(soignantCents)) {
        incoherences.push("session.soignant_cents");
      }
      if (metadata.commission_cents !== String(commissionCents)) {
        incoherences.push("session.commission_cents");
      }
      if (metadata.facture_honoraires_id !== factureHonoraires.id) {
        incoherences.push("session.facture_honoraires_id");
      }
      if ((metadata.facture_commission_id || "") !== (factureCommission?.id || "")) {
        incoherences.push("session.facture_commission_id");
      }
      if (
        metadata.payment_scope !== (invoiceScopedPayment ? "INVOICE" : "MISSION")
        && (invoiceScopedPayment || metadata.payment_scope !== undefined)
      ) {
        incoherences.push("session.payment_scope");
      }

      const paymentIntentId = objectId(session.payment_intent);
      if (paymentIntentId) {
        const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
        const piMetadata = paymentIntent.metadata || {};
        if (paymentIntent.amount !== totalCents) incoherences.push("payment_intent.amount");
        if (paymentIntent.currency !== "eur") incoherences.push("payment_intent.currency");
        if (objectId(paymentIntent.customer) !== customerId) {
          incoherences.push("payment_intent.customer");
        }
        if (piMetadata.type !== "CONNECT_MISSION_PAYMENT") incoherences.push("payment_intent.type");
        if (piMetadata.mission_id !== mission_id) incoherences.push("payment_intent.mission_id");
        if (piMetadata.etablissement_id !== mission.etablissement_id) {
          incoherences.push("payment_intent.etablissement_id");
        }
        if (piMetadata.connected_account_id !== connectOnboarding.stripe_account_id) {
          incoherences.push("payment_intent.connected_account_id");
        }
        if (piMetadata.soignant_id !== soignantId) {
          incoherences.push("payment_intent.soignant_id");
        }
        if (piMetadata.soignant_cents !== String(soignantCents)) {
          incoherences.push("payment_intent.soignant_cents");
        }
        if (piMetadata.commission_cents !== String(commissionCents)) {
          incoherences.push("payment_intent.commission_cents");
        }
        if (piMetadata.facture_honoraires_id !== factureHonoraires.id) {
          incoherences.push("payment_intent.facture_honoraires_id");
        }
        if ((piMetadata.facture_commission_id || "") !== (factureCommission?.id || "")) {
          incoherences.push("payment_intent.facture_commission_id");
        }
        if (
          piMetadata.payment_scope !== (invoiceScopedPayment ? "INVOICE" : "MISSION")
          && (invoiceScopedPayment || piMetadata.payment_scope !== undefined)
        ) {
          incoherences.push("payment_intent.payment_scope");
        }
        if (
          requireSucceededIntent
          && (paymentIntent.status !== "succeeded" || paymentIntent.amount_received !== totalCents)
        ) {
          incoherences.push("payment_intent.status_or_amount_received");
        }
      } else if (requireSucceededIntent) {
        incoherences.push("payment_intent.missing");
      }

      const { data: missionActuelle, error: missionActuelleError } = await supabaseAdmin
        .from("missions")
        .select(
          "statut, type_contrat_applique, soignant_assigne_id, etablissement_id, montant_commission_ttc, net_a_payer",
        )
        .eq("id", mission_id)
        .maybeSingle();
      if (
        missionActuelleError || !missionActuelle
        || (!invoiceScopedPayment && missionActuelle.statut !== "TERMINEE")
        || (invoiceScopedPayment && !["EN_COURS", "TERMINEE"].includes(missionActuelle.statut))
        || missionActuelle.type_contrat_applique !== "LIBERAL"
        || missionActuelle.soignant_assigne_id !== soignantId
        || missionActuelle.etablissement_id !== mission.etablissement_id
        || (!invoiceScopedPayment
          && Math.round(Number(missionActuelle.montant_commission_ttc ?? 0) * 100) !== commissionCents)
        || (!invoiceScopedPayment
          && Math.round(Number(missionActuelle.net_a_payer ?? 0) * 100) !== soignantCents)
      ) {
        incoherences.push("database.mission_state");
      }
      const { data: factureHonorairesActuelle, error: factureHonorairesActuelleError } =
        await supabaseAdmin
          .from("factures_honoraires")
          .select("statut, montant_ttc, mission_id, soignant_id, etablissement_id, stripe_payment_intent_id")
          .eq("id", factureHonoraires.id)
          .maybeSingle();
      if (
        factureHonorairesActuelleError || !factureHonorairesActuelle
        || !(
          ["EMISE", "EN_RETARD"].includes(factureHonorairesActuelle.statut)
          || (
            factureHonorairesActuelle.statut === "PAYEE"
            && factureHonorairesActuelle.stripe_payment_intent_id === paymentIntentId
          )
        )
        || factureHonorairesActuelle.mission_id !== mission_id
        || factureHonorairesActuelle.soignant_id !== soignantId
        || factureHonorairesActuelle.etablissement_id !== mission.etablissement_id
        || Math.round(Number(factureHonorairesActuelle.montant_ttc ?? 0) * 100) !== soignantCents
      ) {
        incoherences.push("database.facture_honoraires_state");
      }
      const { data: factureCommissionActuelle, error: factureCommissionActuelleError } =
        await supabaseAdmin
          .from("factures")
          .select("id, statut, montant_ttc, stripe_payment_intent_id")
          .eq("id", factureCommission?.id || "00000000-0000-0000-0000-000000000000")
          .eq("type_document", "FACTURE")
          .neq("statut", "ANNULEE")
          .maybeSingle();
      if (
        factureCommissionActuelleError
        || (factureCommission
          ? !factureCommissionActuelle
            || factureCommissionActuelle.id !== factureCommission.id
            || !(
              ["EMISE", "EN_RETARD"].includes(factureCommissionActuelle.statut)
              || (
                factureCommissionActuelle.statut === "PAYEE"
                && factureCommissionActuelle.stripe_payment_intent_id === paymentIntentId
              )
            )
            || Boolean(
              factureCommissionActuelle.stripe_payment_intent_id
              && factureCommissionActuelle.stripe_payment_intent_id !== paymentIntentId,
            )
            || Math.round(Number(factureCommissionActuelle.montant_ttc ?? 0) * 100) !== commissionCents
          : Boolean(factureCommissionActuelle))
      ) {
        incoherences.push("database.facture_commission_state");
      }
      return incoherences;
    };

    const auditerSessionConnectIncoherente = async (
      session: Stripe.Checkout.Session,
      incoherences: string[],
    ) => {
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: mission.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "ADMIN_ACTION",
        p_type_ressource: "mission",
        p_id_ressource: mission_id,
        p_cle_s3: null,
        p_details: {
          evenement: "CONNECT_CHECKOUT_IDENTITE_INCOHERENTE",
          stripe_session_id: session.id,
          incoherences,
        },
        p_ip: null,
        p_navigateur: "stripe-connect-pay-mission",
      }, "Connect checkout mismatch audit failed");
    };

    // Une ligne ECHOUE peut signifier « charge client réussie, transfert
    // Connect échoué ». Dans ce cas, créer un nouveau Checkout redébiterait
    // l'établissement. On rejoue uniquement le transfert, avec la même clé
    // d'idempotence que le webhook, puis on laisse sa réconciliation retryable
    // terminer les écritures locales.
    const relancerTransfertEchoueSansRecharger = async (
      session: Stripe.Checkout.Session,
    ): Promise<boolean> => {
      if (
        !existingTransfer
        || !["ECHOUE", "CHARGE_REUSSI"].includes(transferStatutCourant || "")
      ) return false;

      const paymentIntentId = objectId(session.payment_intent);
      if (!paymentIntentId) {
        throw new Error("Session Connect payée sans PaymentIntent");
      }
      const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      if (
        paymentIntent.status !== "succeeded"
        || paymentIntent.amount !== totalCents
        || paymentIntent.amount_received !== totalCents
        || paymentIntent.currency !== "eur"
        || objectId(paymentIntent.customer) !== customerId
      ) {
        throw new Error("PaymentIntent Connect non réconciliable");
      }

      // Un PaymentIntent reste `succeeded` après un remboursement et peut
      // également avoir été contesté. La Charge source est donc l'autorité
      // finale avant tout transfert Connect : on échoue fermé dès que les
      // fonds ne sont plus acquis ou que son identité comptable diverge.
      const sourceCharge = await requireAcquiredStripeSourceCharge(stripe, paymentIntent, {
        customerId,
        amountCents: totalCents,
        currency: "eur",
      });
      const chargeId = sourceCharge.id;

      const transfer = existingTransfer.stripe_transfer_id
        ? await stripe.transfers.retrieve(existingTransfer.stripe_transfer_id)
        : await stripe.transfers.create({
          amount: soignantCents,
          currency: "eur",
          destination: connectOnboarding.stripe_account_id,
          source_transaction: chargeId,
          transfer_group: invoiceScopedPayment
            ? `facture_${factureHonoraires.id}`
            : `mission_${mission_id}`,
          metadata: { mission_id, soignant_id: soignantId },
        }, { idempotencyKey: `transfer_${session.id}` });
      const destinationId = objectId(transfer.destination);
      const sourceTransactionId = objectId(transfer.source_transaction);
      if (
        transfer.amount !== soignantCents
        || transfer.currency !== "eur"
        || destinationId !== connectOnboarding.stripe_account_id
        || sourceTransactionId !== chargeId
        || transfer.metadata?.mission_id !== mission_id
        || transfer.metadata?.soignant_id !== soignantId
      ) {
        throw new Error("Transfert Connect récupéré incohérent");
      }

      const nowIso = new Date().toISOString();
      const { data: transferRepris, error: transferRepriseError } = await supabaseAdmin
        .from("stripe_transfers")
        .update({
          statut: "TRANSFERE",
          stripe_checkout_session_id: session.id,
          stripe_payment_intent_id: paymentIntentId,
          stripe_charge_id: chargeId,
          stripe_transfer_id: transfer.id,
          transfere_le: nowIso,
          erreur: null,
        })
        .eq("id", existingTransfer.id)
        .eq("statut", transferStatutCourant)
        .eq("montant_soignant", soignantCents / 100)
        .eq("montant_commission", commissionCents / 100)
        .eq("montant_total", totalCents / 100)
        .select("id")
        .maybeSingle();
      if (transferRepriseError) throw transferRepriseError;
      if (!transferRepris) {
        const { data: etatConcurrent, error: etatConcurrentError } = await supabaseAdmin
          .from("stripe_transfers")
          .select(
            "statut, stripe_checkout_session_id, stripe_payment_intent_id, stripe_transfer_id",
          )
          .eq("id", existingTransfer.id)
          .maybeSingle();
        if (
          etatConcurrentError
          || !etatConcurrent
          || !["TRANSFERE", "CHARGE_REUSSI", "PAYE"].includes(etatConcurrent.statut)
          || etatConcurrent.stripe_checkout_session_id !== session.id
          || etatConcurrent.stripe_payment_intent_id !== paymentIntentId
          || etatConcurrent.stripe_transfer_id !== transfer.id
        ) {
          throw etatConcurrentError || new Error("Reprise Connect concurrencée de façon incohérente");
        }
      }

      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: mission.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_TRANSFER_CREATED",
        p_type_ressource: "mission",
        p_id_ressource: mission_id,
        p_cle_s3: null,
        p_details: {
          evenement: "CONNECT_TRANSFER_RETRY_SANS_NOUVELLE_CHARGE",
          stripe_session_id: session.id,
          stripe_payment_intent_id: paymentIntentId,
          stripe_transfer_id: transfer.id,
        },
        p_ip: null,
        p_navigateur: "stripe-connect-pay-mission",
      }, "Connect transfer retry audit failed");
      transferStatutCourant = "TRANSFERE";
      return true;
    };

    const rapprocherSessionConnectPayee = async (
      session: Stripe.Checkout.Session,
    ): Promise<{ transferRetried: boolean; transferId: string }> => {
      const transferRetried = await relancerTransfertEchoueSansRecharger(session);
      const paymentIntentId = objectId(session.payment_intent);
      if (!paymentIntentId) throw new Error("Session Connect payée sans PaymentIntent");
      const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      const sourceCharge = await requireAcquiredStripeSourceCharge(stripe, paymentIntent, {
        customerId,
        amountCents: totalCents,
        currency: "eur",
      });

      const { data: trace, error: traceError } = await supabaseAdmin
        .from("stripe_transfers")
        .select(
          "id, statut, stripe_checkout_session_id, stripe_payment_intent_id, stripe_charge_id, stripe_transfer_id, montant_soignant, montant_commission, montant_total",
        )
        .eq("mission_id", mission_id)
        .eq("stripe_checkout_session_id", session.id)
        .order("cree_le", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (
        traceError || !trace?.stripe_transfer_id
        || !["TRANSFERE", "CHARGE_REUSSI", "PAYE"].includes(trace.statut)
        || trace.stripe_payment_intent_id !== paymentIntentId
        || (trace.stripe_charge_id && trace.stripe_charge_id !== sourceCharge.id)
        || Math.round(Number(trace.montant_soignant) * 100) !== soignantCents
        || Math.round(Number(trace.montant_commission) * 100) !== commissionCents
        || Math.round(Number(trace.montant_total) * 100) !== totalCents
      ) {
        throw new Error(
          `Trace Connect non rapprochable: ${traceError?.message || "identité locale invalide"}`,
        );
      }

      const transfer = await stripe.transfers.retrieve(trace.stripe_transfer_id);
      if (
        transfer.amount !== soignantCents
        || transfer.currency !== "eur"
        || objectId(transfer.destination) !== connectOnboarding.stripe_account_id
        || objectId(transfer.source_transaction) !== sourceCharge.id
        || transfer.metadata?.mission_id !== mission_id
        || transfer.metadata?.soignant_id !== soignantId
        || transfer.reversed
        || transfer.amount_reversed > 0
      ) {
        throw new Error("Transfer Connect non acquis ou incohérent");
      }

      const { data: rapprochement, error: rapprochementError } = await supabaseAdmin.rpc(
        invoiceScopedPayment
          ? "fn_stripe_connect_rapprocher_facture"
          : "fn_stripe_connect_rapprocher_local",
        {
          p_mission_id: mission_id,
          p_soignant_id: soignantId,
          p_etablissement_id: mission.etablissement_id,
          p_facture_honoraires_id: factureHonoraires.id,
          p_facture_commission_id: factureCommission?.id || null,
          p_stripe_checkout_session_id: session.id,
          p_stripe_payment_intent_id: paymentIntentId,
          p_stripe_charge_id: sourceCharge.id,
          p_stripe_transfer_id: transfer.id,
          p_montant_soignant_cts: soignantCents,
          p_montant_commission_cts: commissionCents,
          p_montant_total_cts: totalCents,
          p_rapproche_le: new Date().toISOString(),
        },
      );
      const result = rapprochement as { success?: boolean; error?: string } | null;
      if (rapprochementError || result?.success !== true) {
        throw new Error(
          `Rapprochement Connect local impossible: ${rapprochementError?.message || result?.error || "RPC rejected"}`,
        );
      }
      return { transferRetried, transferId: transfer.id };
    };

    const checkoutScopeId = invoiceScopedPayment ? factureHonoraires.id : mission_id;
    const sessionMatchesScope = (candidate: Stripe.Checkout.Session) => (
      candidate.metadata?.type === "CONNECT_MISSION_PAYMENT"
      && candidate.metadata?.mission_id === mission_id
      && (!invoiceScopedPayment
        || candidate.metadata?.facture_honoraires_id === factureHonoraires.id)
    );
    let checkoutIdempotencyKey = `connect_checkout_${checkoutScopeId}`;
    if (existingTransfer) {
      const versionPrecedente = existingTransfer.stripe_checkout_session_id || existingTransfer.id;
      checkoutIdempotencyKey = `connect_checkout_${checkoutScopeId}_after_${versionPrecedente}`;
    }

    if (existingTransfer?.stripe_checkout_session_id) {
      // Une ancienne session ne doit jamais rester payable en parallèle de la
      // nouvelle. En cas d'indisponibilité Stripe on échoue fermé.
      const precedente = await stripe.checkout.sessions.retrieve(existingTransfer.stripe_checkout_session_id);
      if (precedente.status === "complete") {
        const incoherences = await verifierSessionConnect(precedente, true);
        if (incoherences.length > 0) {
          await auditerSessionConnectIncoherente(precedente, incoherences);
          throw new Error("Session Connect terminée incohérente");
        }
        if (paymentFlowClaim.acquired) {
          await bindStripePaymentFlowClaimSession(
            supabaseAdmin,
            paymentFlowClaimExpected,
            precedente.id,
            paymentFlowClaim.claim.stripe_checkout_session_id,
          );
        }
        const rapprochement = await rapprocherSessionConnectPayee(precedente);
        return new Response(JSON.stringify({
          already_paid: true,
          statut: "RAPPROCHE",
          transfer_retried: rapprochement.transferRetried,
          message: "Le paiement Stripe et ses factures sont rapprochés.",
        }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      if (precedente.status === "open") {
        await stripe.checkout.sessions.expire(precedente.id);
      }
    }

    // La recherche Stripe est indispensable même sans ligne DB : si la
    // création Checkout a réussi puis l'INSERT stripe_transfers a échoué, la
    // clé de base rejouerait sinon éternellement la même Session expirée.
    let sessionCompleteHistorique: Stripe.Checkout.Session | null = null;
    let completeStartingAfter: string | undefined;
    while (!sessionCompleteHistorique) {
      const pageComplete = await stripe.checkout.sessions.list({
        customer: customerId,
        status: "complete",
        limit: 100,
        ...(completeStartingAfter ? { starting_after: completeStartingAfter } : {}),
      });
      sessionCompleteHistorique = pageComplete.data.find(sessionMatchesScope) ?? null;
      if (sessionCompleteHistorique || !pageComplete.has_more) break;
      const last = pageComplete.data.at(-1);
      if (!last) throw new Error("Pagination Checkout Connect incomplète");
      completeStartingAfter = last.id;
    }

    const sessionsConnues = await stripe.checkout.sessions.list({ customer: customerId, limit: 100 });
    const sessionsMission = sessionsConnues.data
      .filter(sessionMatchesScope)
      .sort((a, b) => b.created - a.created);
    const sessionCompleteMission = sessionCompleteHistorique ?? sessionsMission.find(
      (candidate) => candidate.status === "complete",
    ) ?? null;
    const derniereSessionMission = sessionsMission[0] ?? null;

    // Ne jamais se limiter à la dernière tentative : une Session plus récente
    // expirée ne doit pas masquer une charge réussie antérieure sur la mission.
    if (sessionCompleteMission) {
      const incoherences = await verifierSessionConnect(sessionCompleteMission, true);
      if (incoherences.length > 0) {
        await auditerSessionConnectIncoherente(sessionCompleteMission, incoherences);
        throw new Error("Session Connect terminée incohérente");
      }
      if (paymentFlowClaim.acquired) {
        await bindStripePaymentFlowClaimSession(
          supabaseAdmin,
          paymentFlowClaimExpected,
          sessionCompleteMission.id,
          paymentFlowClaim.claim.stripe_checkout_session_id,
        );
      }
      const rapprochement = await rapprocherSessionConnectPayee(sessionCompleteMission);
      return new Response(JSON.stringify({
        already_paid: true,
        statut: "RAPPROCHE",
        transfer_retried: rapprochement.transferRetried,
        message: "Le paiement Stripe et ses factures sont rapprochés.",
      }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (derniereSessionMission) {
      if (
        derniereSessionMission.status === "open"
        && derniereSessionMission.expires_at * 1000 > Date.now()
        && !statutAutoriseNouvelleTentative
      ) {
        const incoherences = await verifierSessionConnect(derniereSessionMission, false);
        if (incoherences.length > 0) {
          await stripe.checkout.sessions.expire(derniereSessionMission.id);
          await releaseStripePaymentFlowClaimForExpiredSession(
            supabaseAdmin,
            paymentFlowClaimExpected.flow,
            derniereSessionMission.id,
          );
          await auditerSessionConnectIncoherente(derniereSessionMission, incoherences);
          return new Response(JSON.stringify({
            error: "CONNECT_CHECKOUT_MISMATCH",
            message: "La tentative de paiement précédente n'est plus valide. Réessayez.",
          }), {
            status: 409,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          });
        }
        await bindStripePaymentFlowClaimSession(
          supabaseAdmin,
          paymentFlowClaimExpected,
          derniereSessionMission.id,
          paymentFlowClaim.claim.stripe_checkout_session_id,
        );
        // Répare la trace DB avant de rendre la Session existante au client.
        const piExistant = typeof derniereSessionMission.payment_intent === "string"
          ? derniereSessionMission.payment_intent
          : derniereSessionMission.payment_intent?.id || null;
        if (transferAReutiliserId) {
          const { data: reprise, error: repriseErr } = await supabaseAdmin
            .from("stripe_transfers")
            .update({
              stripe_checkout_session_id: derniereSessionMission.id,
              stripe_payment_intent_id: piExistant,
              montant_soignant: soignantCents / 100,
              montant_commission: commissionCents / 100,
              montant_total: totalCents / 100,
              statut: "EN_ATTENTE",
              erreur: null,
              cree_le: new Date().toISOString(),
            })
            .eq("id", transferAReutiliserId)
            .eq("statut", transferStatutCourant)
            .select("id")
            .maybeSingle();
          if (repriseErr || !reprise) {
            throw repriseErr || new Error("État Connect modifié pendant la reprise Checkout");
          }
          transferStatutCourant = "EN_ATTENTE";
        } else {
          const { error: repriseErr } = await supabaseAdmin.from("stripe_transfers").insert({
            mission_id,
            facture_id: factureCommission?.id || null,
            facture_honoraire_id: factureHonoraires.id,
            soignant_id: soignantId,
            etablissement_id: mission.etablissement_id,
            montant_soignant: soignantCents / 100,
            montant_commission: commissionCents / 100,
            montant_total: totalCents / 100,
            stripe_checkout_session_id: derniereSessionMission.id,
            stripe_payment_intent_id: piExistant,
            statut: "EN_ATTENTE",
          });
          if (repriseErr && repriseErr.code !== "23505") throw repriseErr;
        }

        const { data: missionReprise, error: missionRepriseErr } = await supabaseAdmin
          .from("missions")
          .update({ mode_paiement_soignant: "STRIPE_CONNECT" })
          .eq("id", mission_id)
          .in("statut", invoiceScopedPayment ? ["EN_COURS", "TERMINEE"] : ["TERMINEE"])
          .eq("type_contrat_applique", "LIBERAL")
          .eq("montant_commission_ttc", mission.montant_commission_ttc)
          .eq("net_a_payer", mission.net_a_payer)
          .select("id")
          .maybeSingle();
        if (missionRepriseErr || !missionReprise) {
          throw missionRepriseErr || new Error("Mission modifiée pendant la reprise Checkout");
        }

        return new Response(JSON.stringify({
          success: true,
          resumed: true,
          client_secret: derniereSessionMission.client_secret,
          total: totalCents / 100,
          commission: commissionCents / 100,
          soignant: soignantCents / 100,
        }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      if (derniereSessionMission.status === "open") {
        await stripe.checkout.sessions.expire(derniereSessionMission.id);
      }
      // Expirée (y compris compensation après INSERT raté) : la génération
      // suivante dépend de l'ID Stripe, donc reste fraîche et concurrent-safe.
      checkoutIdempotencyKey = `connect_checkout_${checkoutScopeId}_after_${derniereSessionMission.id}`;
    }

    // Create Checkout Session (embedded)
    const origin = getApplicationReturnOrigin(req);
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      client_reference_id: mission_id,
      ui_mode: "embedded",
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "eur",
            unit_amount: commissionCents,
            product_data: { name: "Commission Jolene" },
          },
          quantity: 1,
        },
        {
          price_data: {
            currency: "eur",
            unit_amount: soignantCents,
            product_data: { name: "Honoraires soignant" },
          },
          quantity: 1,
        },
      ],
      payment_intent_data: {
        transfer_group: invoiceScopedPayment
          ? `facture_${factureHonoraires.id}`
          : `mission_${mission_id}`,
        statement_descriptor: "JOLENE",
        metadata: {
          type: "CONNECT_MISSION_PAYMENT",
          mission_id,
          etablissement_id: mission.etablissement_id,
          soignant_id: soignantId,
          connected_account_id: connectOnboarding.stripe_account_id,
          soignant_cents: soignantCents.toString(),
          commission_cents: commissionCents.toString(),
          facture_honoraires_id: factureHonoraires.id,
          facture_commission_id: factureCommission?.id || "",
          payment_scope: invoiceScopedPayment ? "INVOICE" : "MISSION",
        },
      },
      metadata: {
        // BUG-BOUCLE-PAIEMENT Fix D.1 — metadata COMPLÈTE niveau session Checkout.
        // Avant ce fix, seuls type/mission_id/facture_honoraires_id étaient au
        // niveau session ; les champs soignant_id/connected_account_id/soignant_cents
        // n'étaient que sur payment_intent_data.metadata. Le webhook lisait
        // session.metadata → condition L93 false → branche CONNECT_MISSION_PAYMENT
        // skippée silencieusement après paiement réussi.
        // Maintenant : redondance sender-side + fallback defensive côté webhook.
        type: "CONNECT_MISSION_PAYMENT",
        mission_id,
        etablissement_id: mission.etablissement_id,
        soignant_id: soignantId,
        connected_account_id: connectOnboarding.stripe_account_id,
        soignant_cents: soignantCents.toString(),
        commission_cents: commissionCents.toString(),
        facture_honoraires_id: factureHonoraires.id,
        facture_commission_id: factureCommission?.id || "",
        payment_scope: invoiceScopedPayment ? "INVOICE" : "MISSION",
      },
      return_url: `${origin}/etablissement/facturation?paiement=succes`,
    }, { idempotencyKey: checkoutIdempotencyKey });

    try {
      await bindStripePaymentFlowClaimSession(
        supabaseAdmin,
        paymentFlowClaimExpected,
        session.id,
        paymentFlowClaim.claim.stripe_checkout_session_id,
      );
    } catch (claimError) {
      await stripe.checkout.sessions.expire(session.id).catch(() => undefined);
      throw claimError;
    }

    const nouvelleSessionIncoherences = await verifierSessionConnect(session, false);
    if (nouvelleSessionIncoherences.length > 0) {
      await stripe.checkout.sessions.expire(session.id);
      await releaseStripePaymentFlowClaimForExpiredSession(
        supabaseAdmin,
        paymentFlowClaimExpected.flow,
        session.id,
      );
      await auditerSessionConnectIncoherente(session, nouvelleSessionIncoherences);
      return new Response(JSON.stringify({
        error: "CONNECT_CHECKOUT_MISMATCH",
        message: "L'état financier a changé pendant la création du paiement. Réessayez.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // [CP-STRIPE-3 H5] Compensation Checkout Session orpheline.
    // Les 2 opérations DB ci-dessous (upsert stripe_transfers + update missions)
    // peuvent échouer APRÈS que la Session Stripe ait été créée. Sans compensation,
    // on laisserait une session payable côté Stripe sans trace DB plateforme.
    //
    // Stratégie : try/catch englobant, si DB écrit échoue → expire la session
    // Stripe (fire-and-forget, on log mais on n'échoue pas si expire échoue).
    //
    // Décision architecturale (Option A, strict) : si malgré l'expire le user
    // complète quand même le paiement (expire a pu échouer), le webhook n'a
    // AUCUN row stripe_transfers correspondant → idempotency check ligne 198
    // ne matche pas mais le webhook part dans la branche CONNECT_MISSION_PAYMENT
    // et tente un stripe.transfers.create(). Le webhook actuel ne crée pas de
    // nouveau row stripe_transfers en secours, donc le paiement reste "dans
    // les mains de Stripe" côté comptable sans qu'il soit rattaché à une
    // mission côté plateforme. C'est intentionnel : on préfère laisser une
    // anomalie visible (audit entry + pas de PAYEE sur factures_honoraires)
    // plutôt qu'un flow miraculeux qui masque le bug DB initial. L'admin
    // intervient manuellement pour réconcilier (via INSERT stripe_transfers
    // ou refund Stripe).
    const paymentIntentId = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id || null;
    let sessionPartageeParConcurrent = false;

    try {
      if (transferAReutiliserId) {
        const { data: transferPersisted, error: updErr } = await supabaseAdmin
          .from("stripe_transfers")
          .update({
            stripe_checkout_session_id: session.id,
            stripe_payment_intent_id: paymentIntentId,
            montant_soignant: soignantCents / 100,
            montant_commission: commissionCents / 100,
            montant_total: totalCents / 100,
            statut: "EN_ATTENTE",
            cree_le: new Date().toISOString(),
          })
          .eq("id", transferAReutiliserId)
          .eq("statut", transferStatutCourant)
          .select("id")
          .maybeSingle();
        if (updErr || !transferPersisted) {
          throw updErr || new Error("État Connect modifié pendant la création Checkout");
        }
        transferStatutCourant = "EN_ATTENTE";
      } else {
        const { error: insErr } = await supabaseAdmin.from("stripe_transfers").insert({
          mission_id,
          facture_id: factureCommission?.id || null,
          facture_honoraire_id: factureHonoraires.id,
          soignant_id: soignantId,
          etablissement_id: mission.etablissement_id,
          montant_soignant: soignantCents / 100,
          montant_commission: commissionCents / 100,
          montant_total: totalCents / 100,
          stripe_checkout_session_id: session.id,
          stripe_payment_intent_id: paymentIntentId,
          statut: "EN_ATTENTE",
        });
        if (insErr?.code === "23505") {
          // Deux appels initiaux reçoivent la même Session grâce à la même clé
          // Stripe. Le perdant du UNIQUE ne doit surtout pas expirer la Session
          // déjà persistée par le gagnant.
          sessionPartageeParConcurrent = true;
          const { data: gagnant, error: gagnantErr } = await supabaseAdmin
            .from("stripe_transfers")
            .select("mission_id, soignant_id, etablissement_id, montant_soignant, montant_commission, montant_total, statut")
            .eq("stripe_checkout_session_id", session.id)
            .maybeSingle();
          if (gagnantErr || !gagnant) {
            throw new Error(`Session concurrente introuvable: ${gagnantErr?.message || session.id}`);
          }
          const identique = gagnant.mission_id === mission_id
            && gagnant.soignant_id === soignantId
            && gagnant.etablissement_id === mission.etablissement_id
            && Math.round(Number(gagnant.montant_soignant) * 100) === soignantCents
            && Math.round(Number(gagnant.montant_commission) * 100) === commissionCents
            && Math.round(Number(gagnant.montant_total) * 100) === totalCents
            && ["EN_ATTENTE", "CHARGE_REUSSI", "TRANSFERE", "PAYE"].includes(gagnant.statut);
          if (!identique) throw new Error("Collision Checkout Session incohérente");
        } else if (insErr) {
          throw insErr;
        }
      }

      // Update mission payment mode
      const { data: missionPersisted, error: missionErr } = await supabaseAdmin
        .from("missions")
        .update({ mode_paiement_soignant: "STRIPE_CONNECT" })
        .eq("id", mission_id)
          .in("statut", invoiceScopedPayment ? ["EN_COURS", "TERMINEE"] : ["TERMINEE"])
        .eq("type_contrat_applique", "LIBERAL")
        .eq("montant_commission_ttc", mission.montant_commission_ttc)
        .eq("net_a_payer", mission.net_a_payer)
        .select("id")
        .maybeSingle();
      if (missionErr || !missionPersisted) {
        throw missionErr || new Error("Mission modifiée pendant la création Checkout");
      }
    } catch (dbErr) {
      // DB écrit échoué post-Checkout Session → compensation
      const dbErrMsg = dbErr instanceof Error ? dbErr.message : String(dbErr);
      console.error("CHECKOUT_CREATED_DB_WRITE_FAILED:", dbErrMsg);

      // Une collision UNIQUE signifie que la même Session appartient déjà au
      // worker gagnant : l'expirer casserait son paiement légitime.
      if (!sessionPartageeParConcurrent) {
        try {
          await stripe.checkout.sessions.expire(session.id);
          await releaseStripePaymentFlowClaimForExpiredSession(
            supabaseAdmin,
            paymentFlowClaimExpected.flow,
            session.id,
          );
          console.log(`Stripe session ${session.id} expired (compensation)`);
        } catch (expireErr) {
          const expireMsg = expireErr instanceof Error ? expireErr.message : String(expireErr);
          console.error(`SESSION_EXPIRE_FAILED for ${session.id}:`, expireMsg);
        }
      }

      // Audit financier obligatoire : l'expiration peut elle-même échouer et
      // laisser une Session payable sans rapprochement local.
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: mission.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "STRIPE_CHECKOUT_ORPHANED_RECOVERED",
        p_type_ressource: "mission",
        p_id_ressource: mission_id,
        p_cle_s3: null,
        p_details: {
          stripe_session_id: session.id,
          stripe_payment_intent_id: paymentIntentId,
          db_error: dbErrMsg,
          compensation_expire_attempted: !sessionPartageeParConcurrent,
          concurrent_session_reused: sessionPartageeParConcurrent,
        },
        p_ip: null,
        p_navigateur: "stripe-connect-pay-mission",
      }, "Connect orphaned checkout audit failed");

      return new Response(
        JSON.stringify({
          error: "CHECKOUT_FAILED_RETRY",
          message: "Paiement impossible, veuillez réessayer dans quelques instants.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        client_secret: session.client_secret,
        total: totalCents / 100,
        commission: commissionCents / 100,
        soignant: soignantCents / 100,
      }),
      {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  } catch (error: unknown) {
    // [CP-STRIPE-6 H9] Mapping typed Stripe errors
    const mapped = mapStripeCustomerConfigurationError(error) || mapStripeError(error);
    console[mapped.logLevel](`[stripe-connect-pay-mission] step=${step} ERROR:`, {
      code: mapped.code,
      raw: error instanceof Error ? error.message : String(error),
    });
    return new Response(
      JSON.stringify({ error: mapped.code, message: mapped.userMessage, failed_at_step: step }),
      {
        status: mapped.status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  }
});
