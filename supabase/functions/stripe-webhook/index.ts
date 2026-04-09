import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "https://jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
    apiVersion: "2025-08-27.basil",
  });

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  try {
    // Verify Stripe signature
    const body = await req.text();
    const signature = req.headers.get("stripe-signature");
    if (!signature) {
      return new Response(JSON.stringify({ error: "Missing stripe-signature header" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    if (!webhookSecret) {
      console.error("STRIPE_WEBHOOK_SECRET not configured");
      return new Response(JSON.stringify({ error: "Webhook secret not configured" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
    } catch (err) {
      console.error("Signature verification failed:", err);
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`Stripe webhook received: ${event.type}`);

    // Handle checkout.session.completed
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const metadataType = session.metadata?.type;

      // ── Connect mission payment flow ──
      if (metadataType === "CONNECT_MISSION_PAYMENT") {
        // Verify payment actually succeeded before creating transfer
        if (session.payment_status !== "paid") {
          console.warn(`CONNECT_MISSION_PAYMENT session ${session.id} not paid (status: ${session.payment_status}), skipping transfer`);
          return new Response(JSON.stringify({ received: true, skipped: "not_paid" }), {
            status: 200,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          });
        }

        const missionId = session.metadata?.mission_id;
        const soignantId = session.metadata?.soignant_id;
        const connectedAccountId = session.metadata?.connected_account_id;
        const soignantCents = parseInt(session.metadata?.soignant_cents || "0", 10);

        if (missionId && connectedAccountId && soignantCents > 0) {
          try {
            const transfer = await stripe.transfers.create({
              amount: soignantCents,
              currency: "eur",
              destination: connectedAccountId,
              transfer_group: `mission_${missionId}`,
              metadata: { mission_id: missionId, soignant_id: soignantId || "" },
            });

            // Get the actual charge ID from the payment intent
            const paymentIntentId = typeof session.payment_intent === "string" ? session.payment_intent : null;
            let chargeId: string | null = null;
            if (paymentIntentId) {
              try {
                const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
                chargeId = pi.latest_charge ? (typeof pi.latest_charge === "string" ? pi.latest_charge : pi.latest_charge.id) : null;
              } catch { /* fallback to payment_intent id */ }
            }

            await supabaseAdmin
              .from("stripe_transfers")
              .update({
                statut: "TRANSFERE",
                stripe_transfer_id: transfer.id,
                stripe_charge_id: chargeId || paymentIntentId,
                stripe_payment_intent_id: paymentIntentId,
                transfere_le: new Date().toISOString(),
              })
              .eq("mission_id", missionId);

            // Mark mission: soignant paid via Connect + commission included in same payment
            await supabaseAdmin
              .from("missions")
              .update({
                mode_paiement_soignant: "STRIPE_CONNECT",
                commission_facturee: true,
                modifie_le: new Date().toISOString(),
              })
              .eq("id", missionId);

            console.log(`Connect transfer ${transfer.id} created for mission ${missionId}`);
          } catch (transferErr) {
            console.error("Connect transfer failed:", transferErr);
            await supabaseAdmin
              .from("stripe_transfers")
              .update({ statut: "ECHOUE", modifie_le: new Date().toISOString() })
              .eq("mission_id", missionId);
          }
        }

        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // ── Standard facture payment flow ──
      const factureId = session.metadata?.facture_id;

      if (!factureId) {
        console.warn("checkout.session.completed sans facture_id dans metadata");
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // C2: Idempotency guard — skip if already PAYEE
      const { data: existingFacture } = await supabaseAdmin
        .from("factures")
        .select("statut")
        .eq("id", factureId)
        .single();

      if (existingFacture?.statut === "PAYEE") {
        console.log(`Facture ${factureId} already PAYEE, skipping duplicate webhook`);
        return new Response(JSON.stringify({ received: true, skipped: "already_paid" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // Update facture to PAYEE
      const { error: updateErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "PAYEE",
          date_paiement: new Date().toISOString(),
          stripe_payment_intent_id: session.payment_intent as string,
          stripe_hosted_url: session.url,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", factureId)
        .neq("statut", "PAYEE");

      if (updateErr) {
        console.error("Erreur mise à jour facture:", updateErr);
        throw updateErr;
      }

      // Get facture details for audit
      const { data: facture } = await supabaseAdmin
        .from("factures")
        .select("numero_facture, etablissement_id, montant_ttc")
        .eq("id", factureId)
        .single();

      // Write audit log
      if (facture) {
        await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: facture.etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "FINANCE_FACTURE_PAYEE",
          p_type_ressource: "facture",
          p_id_ressource: factureId,
          p_cle_s3: null,
          p_details: {
            numero_facture: facture.numero_facture,
            montant_ttc: facture.montant_ttc,
            stripe_session_id: session.id,
            stripe_payment_intent: session.payment_intent,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });

        // M6: Send FACTURE_PAYEE email
        {
          const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
          const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
          await fetch(`${supabaseUrl}/functions/v1/send-email`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${serviceRoleKey}`,
            },
            body: JSON.stringify({
              type: "FACTURE_PAYEE",
              destinataire_id: facture.etablissement_id,
              data: {
                numero: facture.numero_facture,
                montant_ttc: (facture.montant_ttc ?? 0).toFixed(2),
                date_paiement: new Date().toLocaleDateString("fr-FR"),
                facture_id: factureId,
              },
            }),
          }).catch((err: unknown) => console.error("Email FACTURE_PAYEE error:", err));
        }
      }
    }

    // Handle payment_intent.succeeded (backup reconciliation)
    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      let factureId = paymentIntent.metadata?.facture_id;

      if (!factureId) {
        const { data: factureByPaymentIntent } = await supabaseAdmin
          .from("factures")
          .select("id")
          .eq("stripe_payment_intent_id", paymentIntent.id)
          .maybeSingle();

        factureId = factureByPaymentIntent?.id;
      }

      if (factureId) {
        await supabaseAdmin
          .from("factures")
          .update({
            statut: "PAYEE",
            date_paiement: new Date().toISOString(),
            stripe_payment_intent_id: paymentIntent.id,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", factureId)
          .neq("statut", "PAYEE");
      } else {
        console.warn(`payment_intent.succeeded without facture mapping: ${paymentIntent.id}`);
      }
    }

    // Handle SEPA debit charge succeeded
    if (event.type === "charge.succeeded") {
      const charge = event.data.object as Stripe.Charge;
      if (charge.payment_method_details?.type === "sepa_debit") {
        const missionId = charge.metadata?.mission_id;
        if (missionId) {
          await supabaseAdmin
            .from("paiements_mission")
            .update({
              statut: "CAPTURE",
              capture_le: new Date().toISOString(),
              stripe_charge_id: charge.id,
            })
            .eq("mission_id", missionId)
            .eq("statut", "EN_ATTENTE");

          // Mark commission as invoiced
          await supabaseAdmin
            .from("missions")
            .update({ commission_facturee: true, modifie_le: new Date().toISOString() })
            .eq("id", missionId);

          console.log(`SEPA charge captured for mission ${missionId}`);
        }
      }
    }

    // Handle invoice.payment_failed
    if (event.type === "invoice.payment_failed") {
      const invoice = event.data.object as Stripe.Invoice;
      const stripeInvoiceId = invoice.id;

      const { error: failErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "EN_RETARD",
          modifie_le: new Date().toISOString(),
        })
        .eq("stripe_invoice_id", stripeInvoiceId);

      if (failErr) {
        console.error("Erreur mise à jour facture en retard:", failErr);
      }
    }

    // Handle checkout.session.expired — clean up EN_ATTENTE transfers
    if (event.type === "checkout.session.expired") {
      const expiredSession = event.data.object as Stripe.Checkout.Session;
      const expiredMissionId = expiredSession.metadata?.mission_id;
      const expiredType = expiredSession.metadata?.type;

      if (expiredType === "CONNECT_MISSION_PAYMENT" && expiredMissionId) {
        // Reset the transfer so user can retry
        await supabaseAdmin
          .from("stripe_transfers")
          .update({ statut: "ECHOUE", erreur: "Checkout expiré", modifie_le: new Date().toISOString() })
          .eq("mission_id", expiredMissionId)
          .eq("statut", "EN_ATTENTE");

        console.log(`Connect checkout expired for mission ${expiredMissionId}, transfer reset to ECHOUE`);
      }

      // For facture payments, just log — the facture stays EMISE
      const expiredFactureId = expiredSession.metadata?.facture_id;
      if (expiredFactureId) {
        console.log(`Facture checkout expired for ${expiredFactureId}`);
      }
    }

    // Handle account.updated (Connect onboarding status)
    if (event.type === "account.updated") {
      const account = event.data.object as Stripe.Account;
      const accountId = account.id;

      let statut = "EN_COURS";
      if (account.details_submitted && account.charges_enabled && account.payouts_enabled) {
        statut = "COMPLET";
      } else if (account.requirements?.disabled_reason) {
        statut = "SUSPENDU";
      }

      let ibanLast4: string | null = null;
      if (account.external_accounts?.data?.length) {
        const bankAccount = account.external_accounts.data[0];
        if ("last4" in bankAccount) {
          ibanLast4 = bankAccount.last4 as string;
        }
      }

      await supabaseAdmin
        .from("stripe_connect_onboarding")
        .update({
          statut,
          charges_enabled: account.charges_enabled ?? false,
          payouts_enabled: account.payouts_enabled ?? false,
          details_submitted: account.details_submitted ?? false,
          iban_last4: ibanLast4,
          modifie_le: new Date().toISOString(),
        })
        .eq("stripe_account_id", accountId);

      console.log(`Connect account ${accountId} updated to ${statut}`);
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("Erreur stripe-webhook:", message);
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
