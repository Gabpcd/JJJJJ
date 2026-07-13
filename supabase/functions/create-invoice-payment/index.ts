import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

async function findMatchingPaymentIntent(
  stripe: Stripe,
  factureId: string,
  customerId?: string | null,
) {
  try {
    const result = await stripe.paymentIntents.search({
      query: `metadata['facture_id']:'${factureId}'`,
      limit: 10,
    });

    const exactMatch = result.data
      .filter((intent) => intent.metadata?.facture_id === factureId)
      .sort((a, b) => b.created - a.created)[0];
    if (exactMatch) return exactMatch;
  } catch (error) {
    console.warn("create-invoice-payment: payment intent search unavailable", error);
  }

  if (!customerId) return null;

  const intents = await stripe.paymentIntents.list({ customer: customerId, limit: 20 });
  return intents.data
    .filter((intent) => intent.metadata?.facture_id === factureId)
    .sort((a, b) => b.created - a.created)[0] ?? null;
}

async function findMatchingCheckoutSession(
  stripe: Stripe,
  factureId: string,
  customerId: string,
) {
  const sessions = await stripe.checkout.sessions.list({ customer: customerId, limit: 100 });
  return sessions.data
    .filter((session) => (
      session.client_reference_id === factureId
      || session.metadata?.facture_id === factureId
    ))
    .sort((a, b) => b.created - a.created)[0] ?? null;
}

// Les retours Stripe restent sur une URL web HTTPS. L'origine CORS native est
// gérée séparément par le helper partagé et ne doit jamais devenir un
// `return_url` capacitor:// ou https://localhost.
function getApplicationReturnOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  let step = 'init';

  try {
    step = '1_auth_header';
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.error("[create-invoice-payment] step=1 No Authorization header");
      return new Response(JSON.stringify({ error: "Non authentifié — header manquant" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '2_auth_user';
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: { user } } = await supabaseClient.auth.getUser(token);
    if (!user?.email) {
      console.error("[create-invoice-payment] step=2 User not authenticated");
      return new Response(JSON.stringify({ error: "Non authentifié" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '3_parse_body';
    const body = await req.json();
    const { facture_id, embedded } = body;
    if (!facture_id) {
      return new Response(JSON.stringify({ error: "facture_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`[create-invoice-payment] step=3 user=${user.id}, facture=${facture_id}, embedded=${!!embedded}`);

    step = '4_fetch_facture';
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    const { data: facture, error: errF } = await supabaseAdmin
      .from("factures")
      .select("id, numero_facture, montant_ttc, nombre_missions, statut, etablissement_id, stripe_payment_intent_id, etablissements(nom, email_contact, stripe_customer_id)")
      .eq("id", facture_id)
      .single();

    if (errF || !facture) {
      console.error("[create-invoice-payment] step=4 Facture introuvable", errF);
      return new Response(JSON.stringify({ error: "Facture introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`[create-invoice-payment] step=4 facture statut=${facture.statut} montant=${facture.montant_ttc} etab=${facture.etablissement_id}`);

    step = '5_ownership';
    const { data: userData } = await supabaseAdmin.auth.admin.getUserById(user.id);
    const userEtabId = userData?.user?.app_metadata?.etablissement_id || user.id;

    if (userEtabId !== facture.etablissement_id) {
      console.error(`[create-invoice-payment] step=5 ownership mismatch user_etab=${userEtabId} facture_etab=${facture.etablissement_id}`);
      return new Response(JSON.stringify({ error: "Accès interdit : cette facture ne vous appartient pas" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const statutsPayables = ["EMISE", "EN_RETARD"];
    if (!statutsPayables.includes(facture.statut)) {
      const dejaPayee = facture.statut === "PAYEE";
      return new Response(JSON.stringify({
        error: dejaPayee
          ? "Facture déjà payée"
          : "Cette facture ne peut pas être payée dans son état actuel",
        status: facture.statut,
      }), {
        status: dejaPayee ? 400 : 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '6_stripe_init';
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      console.error("[create-invoice-payment] step=6 STRIPE_SECRET_KEY not set");
      return new Response(JSON.stringify({ error: "Configuration Stripe manquante" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    assertStripeSecretMode(stripeKey);

    // Pas de apiVersion pinned : utiliser celle liée à la clé (safe, évite les versions inventées)
    const stripe = new Stripe(stripeKey);

    step = '7_customer';
    let customerId = (facture.etablissements as any)?.stripe_customer_id;
    console.log(`[create-invoice-payment] step=7 customerId initial=${customerId ?? 'null'}`);
    if (!customerId) {
      const customers = await stripe.customers.list({ email: user.email, limit: 1 });
      if (customers.data.length > 0) {
        customerId = customers.data[0].id;
        console.log(`[create-invoice-payment] step=7 customer found by email: ${customerId}`);
      } else {
        const customer = await stripe.customers.create(
          {
            email: user.email,
            name: (facture.etablissements as any)?.nom,
            metadata: { etablissement_id: facture.etablissement_id },
          },
          { idempotencyKey: `invoice_customer_${facture.etablissement_id}` },
        );
        customerId = customer.id;
        console.log(`[create-invoice-payment] step=7 customer created: ${customerId}`);
      }

      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", facture.etablissement_id);
    }

    step = '8_search_intent';
    const existingIntent = await findMatchingPaymentIntent(stripe, facture.id, customerId);

    if (existingIntent?.status === "succeeded") {
      const { data: factureSynchronisee, error: syncError } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "PAYEE",
          date_paiement: new Date(existingIntent.created * 1000).toISOString(),
          stripe_payment_intent_id: existingIntent.id,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", facture.id)
        .in("statut", ["EMISE", "EN_RETARD"])
        .select("id")
        .maybeSingle();

      if (syncError) {
        throw new Error(`Impossible de synchroniser la facture payée: ${syncError.message}`);
      }

      if (!factureSynchronisee) {
        const { data: factureActuelle, error: factureActuelleError } = await supabaseAdmin
          .from("factures")
          .select("statut")
          .eq("id", facture.id)
          .maybeSingle();

        if (factureActuelleError) {
          console.error("create-invoice-payment: lost CAS state lookup failed", factureActuelleError);
        }

        const { error: auditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: facture.etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "FACTURE_PAIEMENT_CHECKOUT_CAS_PERDU",
          p_type_ressource: "facture",
          p_id_ressource: facture.id,
          p_cle_s3: null,
          p_details: {
            raison: "statut_modifie_concurremment",
            statut_initial: facture.statut,
            statut_actuel: factureActuelle?.statut ?? "inconnu",
            stripe_payment_intent: existingIntent.id,
          },
          p_ip: null,
          p_navigateur: "edge-function/create-invoice-payment",
        });

        if (auditError) {
          console.error("create-invoice-payment: lost CAS audit failed", auditError);
        }

        throw new Error(
          `PaymentIntent réussi impossible à rapprocher avec la facture ${facture.id}`,
        );
      }

      return new Response(JSON.stringify({ error: "Facture déjà payée", status: "PAYEE" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (existingIntent && ["processing", "requires_capture", "requires_action", "requires_confirmation"].includes(existingIntent.status)) {
      return new Response(JSON.stringify({ error: "Un paiement est déjà en cours pour cette facture", status: existingIntent.status }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '8b_search_checkout';
    const existingSession = await findMatchingCheckoutSession(stripe, facture.id, customerId);
    let checkoutIdempotencyKey = `invoice_checkout_${facture.id}`;
    const intentTerminalConnu = !!existingIntent
      && ["canceled", "requires_payment_method"].includes(existingIntent.status);

    if (existingSession?.status === "open" && existingSession.expires_at * 1000 > Date.now()) {
      // Reprise de la même tentative : aucune nouvelle Session ni nouveau PI.
      return new Response(JSON.stringify({
        url: existingSession.url,
        client_secret: existingSession.client_secret || null,
        resumed: true,
      }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        status: 200,
      });
    }

    if (existingSession?.status === "complete" && !intentTerminalConnu) {
      return new Response(JSON.stringify({
        error: "Un paiement Checkout a déjà été validé et reste en cours de rapprochement",
        status: "complete",
      }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        status: 409,
      });
    }

    if (existingSession) {
      // Session expirée (ou encore marquée open après expires_at) : on la rend
      // explicitement inutilisable, puis on avance la version de façon stable.
      if (existingSession.status === "open") {
        await stripe.checkout.sessions.expire(existingSession.id);
      }
      checkoutIdempotencyKey = `invoice_checkout_${facture.id}_after_${existingSession.id}`;
    } else if (existingIntent && ["canceled", "requires_payment_method"].includes(existingIntent.status)) {
      checkoutIdempotencyKey = `invoice_checkout_${facture.id}_after_${existingIntent.id}`;
    } else if (facture.stripe_payment_intent_id) {
      // Une référence DB orpheline reste une version déterministe ; elle ne doit
      // jamais forcer la réutilisation éternelle de la première clé Stripe.
      checkoutIdempotencyKey = `invoice_checkout_${facture.id}_after_${facture.stripe_payment_intent_id}`;
    }

    const montantCents = Math.round((facture.montant_ttc ?? 0) * 100);
    if (montantCents <= 0) {
      return new Response(JSON.stringify({ error: "Montant de la facture invalide" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '9_checkout';
    const appUrl = getApplicationReturnOrigin(req);

    console.log(`[create-invoice-payment] step=9 creating checkout, amount=${facture.montant_ttc}, customer=${customerId}, embedded=${!!embedded}`);

    const sessionParams: any = {
      customer: customerId,
      client_reference_id: facture.id,
      line_items: [
        {
          price_data: {
            currency: "eur",
            product_data: {
              name: `Facture ${facture.numero_facture}`,
              description: `Commission Jolene — ${facture.nombre_missions ?? 0} missions`,
            },
            unit_amount: montantCents,
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      metadata: { facture_id: facture.id },
      payment_intent_data: {
        metadata: { facture_id: facture.id },
        description: `Facture ${facture.numero_facture}`,
        // Stripe : statement_descriptor doit contenir au moins 1 lettre Latin, 5-22 chars, pas de caractères spéciaux.
        // "JOLENE" suffit — pas de suffix (qui doit aussi respecter les règles Latin + ne pas dépasser combiné).
        statement_descriptor: "JOLENE",
      },
    };

    if (embedded) {
      sessionParams.ui_mode = "embedded";
      sessionParams.return_url = `${appUrl}/etablissement/facturation?paiement=succes&session_id={CHECKOUT_SESSION_ID}`;
    } else {
      sessionParams.success_url = `${appUrl}/etablissement/facturation?paiement=succes`;
      sessionParams.cancel_url = `${appUrl}/etablissement/facturation`;
    }

    const session = await stripe.checkout.sessions.create(sessionParams, {
      idempotencyKey: checkoutIdempotencyKey,
    });

    const { error: updateError } = await supabaseAdmin
      .from("factures")
      .update({
        stripe_payment_intent_id: session.payment_intent as string,
        stripe_hosted_url: session.url ?? null,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture_id);

    if (updateError) {
      console.error("create-invoice-payment: facture update failed", updateError);
      // Non-blocking: session was created, log the issue but continue
    }

    console.log(`[create-invoice-payment] step=10 session created, id=${session.id}, payment_intent=${session.payment_intent}, client_secret=${!!session.client_secret}, url=${session.url}`);

    return new Response(JSON.stringify({
      url: session.url,
      client_secret: session.client_secret || null,
    }), {
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    // Expose error message (Stripe errors ne sont pas sensibles, aident le debug)
    const err = error as any;
    const message = err?.message ?? String(error);
    const stripeCode = err?.code ?? null;
    const stripeType = err?.type ?? null;
    const stripeParam = err?.param ?? null;

    console.error(`[create-invoice-payment] step=${step} ERROR: ${message}`, {
      code: stripeCode,
      type: stripeType,
      param: stripeParam,
      stack: err?.stack?.slice(0, 500),
    });

    return new Response(JSON.stringify({
      error: message,
      failed_at_step: step,
      stripe_code: stripeCode,
      stripe_type: stripeType,
      stripe_param: stripeParam,
    }), {
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      status: 500,
    });
  }
});
