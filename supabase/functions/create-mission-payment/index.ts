import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

class RetryablePaymentPersistenceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RetryablePaymentPersistenceError";
  }
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

  const supabaseAnon = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  );
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Non autorisé — header manquant" }), {
      status: 401,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }

  try {
    // Authenticate
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseAnon.auth.getUser(token);
    if (authError || !user?.email) {
      return new Response(JSON.stringify({ error: "Non authentifié" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => null) as { mission_id?: unknown } | null;
    const mission_id = typeof body?.mission_id === "string" ? body.mission_id : "";
    if (!mission_id) {
      return new Response(JSON.stringify({ error: "mission_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Verify ownership via JWT user role
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: userRole, error: userRoleError } = await supabaseUser.rpc("fn_get_my_role");
    if (userRoleError) {
      throw new Error(`Lecture du rôle établissement impossible: ${userRoleError.message}`);
    }
    const userEtabId = userRole?.etablissement_id;

    // Get mission + establishment
    const { data: mission, error: errM } = await supabaseAdmin
      .from("missions")
      .select(
        "id, intitule, statut, soignant_assigne_id, montant_commission_ttc, etablissement_id, etablissements(nom, email_contact, stripe_customer_id, mode_paiement_commission)"
      )
      .eq("id", mission_id)
      .maybeSingle();

    if (errM) throw new Error(`Lecture mission impossible: ${errM.message}`);
    if (!mission) {
      return new Response(JSON.stringify({ error: "Mission introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Ownership check
    if (!userEtabId || userEtabId !== mission.etablissement_id) {
      return new Response(
        JSON.stringify({ error: "Accès interdit" }),
        { status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // Cette autorisation précède exactement l'acceptation d'une candidature.
    // Une mission déjà attribuée, annulée ou expirée ne doit jamais créer ni
    // réutiliser une retenue Stripe.
    if (mission.statut !== "OUVERTE" || mission.soignant_assigne_id !== null) {
      return new Response(JSON.stringify({
        error: "MISSION_STATE_CHANGED",
        message: "La mission n’est plus ouverte ou a déjà été attribuée. Actualisez la liste des candidatures.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const etab = (mission as any).etablissements;
    if (etab?.mode_paiement_commission !== "STRIPE_RESERVATION") {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Mode de paiement non Stripe" }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const commissionTTC = (mission as any).montant_commission_ttc;
    if (!commissionTTC || commissionTTC <= 0) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Pas de commission" }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const amountCents = Math.round(commissionTTC * 100);

    const enregistrerPaiement = async (
      paymentIntentId: string,
      statut: "EN_ATTENTE" | "AUTORISE" | "ECHOUE",
    ) => {
      const { data, error } = await supabaseAdmin.rpc(
        "fn_enregistrer_reservation_paiement_mission",
        {
          p_mission_id: mission.id,
          p_etablissement_id: mission.etablissement_id,
          p_montant_ht: commissionTTC / 1.2,
          p_montant_tva: commissionTTC - commissionTTC / 1.2,
          p_montant_ttc: commissionTTC,
          p_stripe_payment_intent_id: paymentIntentId,
          p_statut: statut,
        },
      );
      if (error) {
        throw new Error(`Persistance atomique du paiement impossible: ${error.message}`);
      }
      const resultat = data as { success?: boolean; error_code?: string } | null;
      if (resultat?.success !== true) {
        throw new Error(`Persistance atomique refusée: ${resultat?.error_code || "REPONSE_INVALIDE"}`);
      }
    };

    // Idempotency: check if payment already exists for this mission
    const { data: existingPayment, error: existingPaymentError } = await supabaseAdmin
      .from("paiements_mission")
      .select("id, statut, stripe_payment_intent_id, cree_le")
      .eq("mission_id", mission.id)
      .maybeSingle();
    if (existingPaymentError) {
      throw new Error(`Lecture paiement mission impossible: ${existingPaymentError.message}`);
    }

    // Initialize Stripe
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
    assertStripeSecretMode(stripeKey);
    const stripe = new Stripe(stripeKey, {
      apiVersion: "2025-08-27.basil",
    });

    let paymentIdempotencyKey = `mission_payment_${mission.id}`;
    if (existingPayment?.stripe_payment_intent_id) {
      const precedent = await stripe.paymentIntents.retrieve(existingPayment.stripe_payment_intent_id);
      const precedentCustomerId = typeof precedent.customer === "string"
        ? precedent.customer
        : precedent.customer?.id;
      if (
        precedent.amount !== amountCents
        || precedent.currency !== "eur"
        || precedent.capture_method !== "manual"
        || precedent.metadata?.mission_id !== mission.id
        || precedent.metadata?.etablissement_id !== mission.etablissement_id
        || precedent.metadata?.type !== "commission_reservation"
        || !etab?.stripe_customer_id
        || precedentCustomerId !== etab.stripe_customer_id
      ) {
        throw new Error("Le PaymentIntent existant ne correspond pas exactement à cette mission");
      }
      if (existingPayment.statut === "REMBOURSE") {
        throw new Error("Une réservation remboursée ne peut pas être recréée sur une mission ouverte");
      }
      if (existingPayment.statut === "CAPTURE" && precedent.status !== "succeeded") {
        throw new Error(`Paiement marqué CAPTURE mais Stripe est ${precedent.status}`);
      }
      if (
        existingPayment.statut === "AUTORISE"
        && !["requires_capture", "succeeded"].includes(precedent.status)
      ) {
        throw new Error(`Paiement marqué AUTORISE mais Stripe est ${precedent.status}`);
      }
      if (precedent.status === "requires_capture" || precedent.status === "succeeded") {
        const statutReel = precedent.status === "requires_capture" ? "AUTORISE" : "CAPTURE";
        if (statutReel === "AUTORISE") {
          // Ce second appel intervient notamment après stripe.confirmPayment :
          // la mission est reverrouillée avant que l'autorisation soit reconnue.
          await enregistrerPaiement(precedent.id, "AUTORISE");
        } else {
          const { data: paiementSynchronise, error: paiementSynchroniseError } = await supabaseAdmin
            .from("paiements_mission")
            .update({ statut: statutReel })
            .eq("id", existingPayment.id)
            .eq("stripe_payment_intent_id", precedent.id)
            .select("id")
            .maybeSingle();
          if (paiementSynchroniseError || !paiementSynchronise) {
            throw new Error(
              `Synchronisation paiement Stripe impossible: ${paiementSynchroniseError?.message || "ligne absente"}`,
            );
          }
        }
        return new Response(
          JSON.stringify({
            success: true,
            reconciled: true,
            reason: "Paiement Stripe déjà enregistré",
            statut: statutReel,
          }),
          { headers: { ...corsHeaders(req), "Content-Type": "application/json" } },
        );
      }

      if (
        precedent.status !== "canceled"
        && (
          existingPayment.statut === "EN_ATTENTE"
          || [
            "processing",
            "requires_action",
            "requires_confirmation",
            "requires_payment_method",
          ].includes(precedent.status)
        )
      ) {
        // Réexposer un client_secret est une nouvelle action sensible : le RPC
        // reverrouille la mission et remet une ancienne tentative ECHOUE en attente.
        await enregistrerPaiement(precedent.id, "EN_ATTENTE");
        // Un PI non terminal doit être repris côté client, pas remplacé.
        return new Response(
          JSON.stringify({
            success: true,
            auto_charged: false,
            resumed: true,
            client_secret: precedent.client_secret,
            payment_intent_id: precedent.id,
            amount: commissionTTC,
          }),
          { headers: { ...corsHeaders(req), "Content-Type": "application/json" } },
        );
      }

      // ECHOUE côté métier ou canceled côté Stripe : version suivante stable.
      paymentIdempotencyKey = `mission_payment_${mission.id}_after_${precedent.id}`;
    } else if (existingPayment) {
      if (["AUTORISE", "CAPTURE", "REMBOURSE"].includes(existingPayment.statut)) {
        throw new Error("Paiement mission terminal sans référence Stripe");
      }
      // Une ligne ECHOUE sans ressource Stripe est une tentative abandonnée.
      paymentIdempotencyKey = `mission_payment_${mission.id}_after_${existingPayment.id}`;
    }

    // Get or create Stripe customer
    let customerId = etab?.stripe_customer_id;
    if (!customerId) {
      const customers = await stripe.customers.list({ email: user.email, limit: 1 });
      if (customers.data.length > 0) {
        customerId = customers.data[0].id;
      } else {
        const customer = await stripe.customers.create(
          {
            email: user.email,
            name: etab?.nom,
            metadata: { etablissement_id: mission.etablissement_id },
          },
          { idempotencyKey: `mission_customer_${mission.etablissement_id}` },
        );
        customerId = customer.id;
      }
      const { data: customerPersisted, error: customerPersistError } = await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", mission.etablissement_id)
        .select("id")
        .maybeSingle();
      if (customerPersistError || !customerPersisted) {
        throw new Error(
          `Persistance client Stripe impossible: ${customerPersistError?.message || "établissement absent"}`,
        );
      }
    }

    // Check for saved default payment method
    const customer = await stripe.customers.retrieve(customerId);
    const defaultPM =
      typeof customer !== "string" && !customer.deleted
        ? (customer.invoice_settings?.default_payment_method as string) || null
        : null;

    const compenserIntentNonDurable = async (
      paymentIntent: Stripe.PaymentIntent,
      cause: unknown,
    ): Promise<never> => {
      let annule = paymentIntent.status === "canceled";
      let compensationError: unknown = null;
      try {
        if (!annule) {
          if (paymentIntent.status === "succeeded") {
            throw new Error("PaymentIntent déjà capturé — annulation automatique impossible");
          }
          const canceled = await stripe.paymentIntents.cancel(
            paymentIntent.id,
            { cancellation_reason: "abandoned" },
            { idempotencyKey: `cancel_${paymentIntent.id}_persistence_failure` },
          );
          annule = canceled.status === "canceled";
        }
      } catch (error) {
        compensationError = error;
        try {
          const current = await stripe.paymentIntents.retrieve(paymentIntent.id);
          annule = current.status === "canceled";
        } catch (retrieveError) {
          compensationError = retrieveError;
        }
      }

      const { error: statutError } = await supabaseAdmin
        .from("paiements_mission")
        .update({ statut: "ECHOUE" })
        .eq("mission_id", mission.id)
        .eq("stripe_payment_intent_id", paymentIntent.id);
      if (statutError) {
        console.error("create-mission-payment: marquage compensation impossible", statutError.message);
      }

      const causeMessage = cause instanceof Error ? cause.message : String(cause);
      const compensationMessage = compensationError instanceof Error
        ? compensationError.message
        : compensationError ? String(compensationError) : null;
      const { error: auditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: mission.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: annule ? "MISSION_PAYMENT_PERSISTENCE_COMPENSATED" : "MISSION_PAYMENT_COMPENSATION_FAILED",
        p_type_ressource: "mission",
        p_id_ressource: mission.id,
        p_cle_s3: null,
        p_details: {
          stripe_payment_intent_id: paymentIntent.id,
          persistence_error: causeMessage.substring(0, 500),
          compensation_succeeded: annule,
          compensation_error: compensationMessage?.substring(0, 500) || null,
        },
        p_ip: null,
        p_navigateur: "create-mission-payment",
      });
      if (auditError) {
        console.error("create-mission-payment: audit compensation impossible", auditError.message);
      }

      throw new RetryablePaymentPersistenceError(
        annule
          ? "PaymentIntent annulé après échec de persistance"
          : "PaymentIntent non durable et compensation Stripe non confirmée",
      );
    };

    const enregistrerErreurStripe = async (error: unknown) => {
      const stripeError = error as {
        payment_intent?: string | Stripe.PaymentIntent;
        raw?: { payment_intent?: string | Stripe.PaymentIntent };
      };
      const intent = stripeError.payment_intent ?? stripeError.raw?.payment_intent;
      if (!intent) return;
      const intentId = typeof intent === "string" ? intent : intent?.id;
      if (!intentId) return;
      try {
        await enregistrerPaiement(intentId, "ECHOUE");
      } catch (persistenceError) {
        const paymentIntent = typeof intent === "string"
          ? await stripe.paymentIntents.retrieve(intent)
          : intent;
        await compenserIntentNonDurable(paymentIntent, persistenceError);
      }
    };

    if (defaultPM) {
      // Auto-authorize with saved card
      let paymentIntent: Stripe.PaymentIntent;
      try {
        paymentIntent = await stripe.paymentIntents.create(
          {
            amount: amountCents,
            currency: "eur",
            customer: customerId,
            payment_method: defaultPM,
            capture_method: "manual", // authorize only, capture on TERMINEE
            confirm: true,
            off_session: true,
            description: `Commission mission: ${(mission as any).intitule}`,
            statement_descriptor: "JOLENE",
            metadata: {
              mission_id: mission.id,
              etablissement_id: mission.etablissement_id,
              type: "commission_reservation",
            },
          },
          { idempotencyKey: paymentIdempotencyKey },
        );
      } catch (error) {
        await enregistrerErreurStripe(error);
        throw error;
      }

      if (paymentIntent.status !== "requires_capture") {
        await compenserIntentNonDurable(
          paymentIntent,
          new Error(`Statut Stripe inattendu après autorisation: ${paymentIntent.status}`),
        );
      }

      // Le succès n'est rendu à la UI qu'après persistance transactionnelle de
      // l'autorisation et revalidation de l'état exact de la mission.
      try {
        await enregistrerPaiement(paymentIntent.id, "AUTORISE");
      } catch (persistenceError) {
        await compenserIntentNonDurable(paymentIntent, persistenceError);
      }

      return new Response(
        JSON.stringify({ success: true, auto_charged: true, payment_intent_id: paymentIntent.id }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    } else {
      // No saved card → return client_secret for manual card entry
      let paymentIntent: Stripe.PaymentIntent;
      try {
        paymentIntent = await stripe.paymentIntents.create(
          {
            amount: amountCents,
            currency: "eur",
            customer: customerId,
            capture_method: "manual",
            description: `Commission mission: ${(mission as any).intitule}`,
            statement_descriptor: "JOLENE",
            metadata: {
              mission_id: mission.id,
              etablissement_id: mission.etablissement_id,
              type: "commission_reservation",
            },
            setup_future_usage: "off_session", // Save card for future
          },
          { idempotencyKey: paymentIdempotencyKey },
        );
      } catch (error) {
        await enregistrerErreurStripe(error);
        throw error;
      }

      if (![
        "requires_payment_method",
        "requires_confirmation",
        "requires_action",
      ].includes(paymentIntent.status)) {
        await compenserIntentNonDurable(
          paymentIntent,
          new Error(`Statut Stripe inattendu avant saisie carte: ${paymentIntent.status}`),
        );
      }

      // Aucun client_secret n'est exposé tant que la tentative n'est pas
      // durable et liée à une mission encore OUVERTE/non attribuée.
      try {
        await enregistrerPaiement(paymentIntent.id, "EN_ATTENTE");
      } catch (persistenceError) {
        await compenserIntentNonDurable(paymentIntent, persistenceError);
      }

      return new Response(
        JSON.stringify({
          success: true,
          auto_charged: false,
          client_secret: paymentIntent.client_secret,
          payment_intent_id: paymentIntent.id,
          amount: commissionTTC,
        }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }
  } catch (error: unknown) {
    console.error("Erreur create-mission-payment:", error instanceof Error ? error.message : error);
    if (error instanceof RetryablePaymentPersistenceError) {
      return new Response(
        JSON.stringify({
          error: "PAYMENT_PERSISTENCE_FAILED",
          message: "Le paiement n’a pas été enregistré. Aucun débit ne doit être poursuivi ; réessayez dans quelques instants.",
          retryable: true,
        }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" }, status: 503 },
      );
    }
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" }, status: 500 }
    );
  }
});
