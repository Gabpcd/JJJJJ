import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { mission_id } = await req.json();
    if (!mission_id) {
      return new Response(JSON.stringify({ error: "mission_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Fetch mission
    const { data: mission } = await supabaseAdmin
      .from("missions")
      .select(
        "id, etablissement_id, soignant_assigne_id, statut, montant_commission_ttc, net_a_payer"
      )
      .eq("id", mission_id)
      .single();

    if (!mission) {
      return new Response(JSON.stringify({ error: "Mission introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (mission.statut !== "TERMINEE") {
      return new Response(
        JSON.stringify({ error: "La mission doit être terminée" }),
        {
          status: 400,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Verify caller is the établissement owner
    const { data: etab } = await supabaseAdmin
      .from("etablissements")
      .select("id, stripe_customer_id, nom, email_contact")
      .eq("id", mission.etablissement_id)
      .single();

    if (!etab) {
      return new Response(
        JSON.stringify({ error: "Établissement introuvable" }),
        {
          status: 404,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Verify user is linked to this établissement via auth metadata
    const { data: adminUserData } = await supabaseAdmin.auth.admin.getUserById(user.id);
    const userEtabId = adminUserData?.user?.app_metadata?.etablissement_id || user.id;

    // Check group membership for the specific establishment's group
    let isGroupAdmin = false;
    if (userEtabId !== mission.etablissement_id && etab) {
      const { data: missionEtab } = await supabaseAdmin
        .from("etablissements")
        .select("groupe_sante_id")
        .eq("id", mission.etablissement_id)
        .single();

      if (missionEtab?.groupe_sante_id) {
        const { data: membership } = await supabaseAdmin
          .from("admins_groupe_sante")
          .select("id")
          .eq("utilisateur_id", user.id)
          .eq("groupe_id", missionEtab.groupe_sante_id)
          .limit(1);

        isGroupAdmin = !!membership && membership.length > 0;
      }
    }

    if (userEtabId !== mission.etablissement_id && !isGroupAdmin) {
      return new Response(
        JSON.stringify({ error: "Vous n'êtes pas autorisé à payer cette mission" }),
        {
          status: 403,
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

    if (!soignantEligible) {
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

    // [CP-STRIPE-2 H1/H14] Lookup facture_honoraires liée à la mission.
    // On exige qu'elle existe avant de créer la Checkout Session — ainsi on
    // peut (1) injecter son id dans la metadata Stripe pour que le webhook
    // update le bon row, (2) éviter les sessions orphelines si la facture
    // n'a jamais été générée, (3) supporter les avoirs AUTO_STRIPE futurs
    // qui nécessitent un stripe_payment_intent_id sur la facture d'origine.
    const { data: factureHonoraires } = await supabaseAdmin
      .from("factures_honoraires")
      .select("id, statut")
      .eq("mission_id", mission_id)
      .eq("soignant_id", soignantId)
      .in("statut", ["EMISE", "EN_RETARD"])
      .order("date_emission", { ascending: true })
      .limit(1)
      .maybeSingle();

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

    // Check soignant has Connect account
    const { data: connectOnboarding } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("stripe_account_id, statut")
      .eq("soignant_id", soignantId)
      .maybeSingle();

    if (
      !connectOnboarding ||
      connectOnboarding.statut !== "COMPLET" ||
      !connectOnboarding.stripe_account_id
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

    // Check idempotency
    const { data: existingTransfer } = await supabaseAdmin
      .from("stripe_transfers")
      .select("id, statut")
      .eq("mission_id", mission_id)
      .maybeSingle();

    if (existingTransfer?.statut === "TRANSFERE" || existingTransfer?.statut === "EN_ATTENTE") {
      return new Response(
        JSON.stringify({
          already_paid: true,
          statut: existingTransfer.statut,
          message: existingTransfer.statut === "TRANSFERE" ? "Ce paiement a déjà été effectué" : "Un paiement est déjà en cours pour cette mission",
        }),
        {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    // Calculate amounts
    const commissionCents = Math.round(
      (mission.montant_commission_ttc || 0) * 100
    );
    const soignantCents = Math.round((mission.net_a_payer || 0) * 100);
    const totalCents = commissionCents + soignantCents;

    // Reuse or create Stripe customer
    let customerId = etab.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        name: etab.nom,
        email: etab.email_contact,
        metadata: { etablissement_id: etab.id },
      });
      customerId = customer.id;
      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", etab.id);
    }

    // Create Checkout Session (embedded)
    const origin = req.headers.get("origin") || "https://jolene.app";
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      ui_mode: "embedded",
      mode: "payment",
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
        transfer_group: `mission_${mission_id}`,
        statement_descriptor: "JOLENE",
        metadata: {
          type: "CONNECT_MISSION_PAYMENT",
          mission_id,
          soignant_id: soignantId,
          connected_account_id: connectOnboarding.stripe_account_id,
          soignant_cents: soignantCents.toString(),
          commission_cents: commissionCents.toString(),
          facture_honoraires_id: factureHonoraires.id,
        },
      },
      metadata: {
        type: "CONNECT_MISSION_PAYMENT",
        mission_id,
        facture_honoraires_id: factureHonoraires.id,
      },
      return_url: `${origin}/etablissement/facturation?paiement=succes`,
    });

    // Upsert stripe_transfers record
    const paymentIntentId = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id || null;
    if (existingTransfer) {
      await supabaseAdmin
        .from("stripe_transfers")
        .update({
          stripe_payment_intent_id: paymentIntentId,
          montant_soignant: soignantCents / 100,
          montant_commission: commissionCents / 100,
          montant_total: totalCents / 100,
          statut: "EN_ATTENTE",
        })
        .eq("id", existingTransfer.id);
    } else {
      await supabaseAdmin.from("stripe_transfers").insert({
        mission_id,
        soignant_id: soignantId,
        etablissement_id: mission.etablissement_id,
        montant_soignant: soignantCents / 100,
        montant_commission: commissionCents / 100,
        montant_total: totalCents / 100,
        stripe_payment_intent_id: paymentIntentId,
        statut: "EN_ATTENTE",
      });
    }

    // Update mission payment mode
    await supabaseAdmin
      .from("missions")
      .update({ mode_paiement_soignant: "STRIPE_CONNECT" })
      .eq("id", mission_id);

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
    console.error("stripe-connect-pay-mission error:", error);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  }
});
