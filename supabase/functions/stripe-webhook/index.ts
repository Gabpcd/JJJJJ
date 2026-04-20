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

            // [CP-STRIPE-2 H1/H7/H14] Propagation du paiement vers factures_honoraires :
            // - stripe_payment_intent_id rempli pour les avoirs AUTO_STRIPE futurs
            // - transition statut EMISE/EN_RETARD → PAYEE
            // - invoke send-email PAIEMENT_RAPIDE_RECU (notif soignant)
            // Le guard `in statut EMISE/EN_RETARD` couvre H4 pour la facture honoraires
            // (une facture ANNULEE/REMPLACEE ne peut pas repasser PAYEE par ce chemin).
            const factureHonorairesId = session.metadata?.facture_honoraires_id;
            if (factureHonorairesId && paymentIntentId) {
              const { data: factureUpdated, error: factureError } = await supabaseAdmin
                .from("factures_honoraires")
                .update({
                  stripe_payment_intent_id: paymentIntentId,
                  statut: "PAYEE",
                  date_paiement: new Date().toISOString().split("T")[0],
                })
                .eq("id", factureHonorairesId)
                .in("statut", ["EMISE", "EN_RETARD"])
                .select("id, numero_facture, montant_ttc, soignant_id, mission_id")
                .maybeSingle();

              if (factureError) {
                console.error("factures_honoraires update failed:", factureError);
              } else if (!factureUpdated) {
                console.warn(
                  `CONNECT webhook: facture_honoraires ${factureHonorairesId} not in EMISE/EN_RETARD, skipped`
                );
                await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
                  p_acteur_id: "00000000-0000-0000-0000-000000000000",
                  p_type_acteur: "SYSTEME",
                  p_action: "FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE",
                  p_type_ressource: "facture_honoraires",
                  p_id_ressource: factureHonorairesId,
                  p_cle_s3: null,
                  p_details: {
                    raison: "statut_non_modifiable",
                    mission_id: missionId,
                    stripe_payment_intent_id: paymentIntentId,
                    stripe_session_id: session.id,
                  },
                  p_ip: null,
                  p_navigateur: "stripe-webhook",
                });
              } else {
                // Invoke send-email PAIEMENT_RAPIDE_RECU (non-bloquant)
                try {
                  const { data: soignantRow } = await supabaseAdmin
                    .from("soignants")
                    .select("prenom")
                    .eq("id", factureUpdated.soignant_id)
                    .maybeSingle();
                  const { data: soignantUser } = await supabaseAdmin.auth.admin.getUserById(
                    factureUpdated.soignant_id
                  );
                  const soignantEmail = soignantUser?.user?.email;
                  const { data: missionDetail } = await supabaseAdmin
                    .from("missions")
                    .select("intitule, etablissements(nom)")
                    .eq("id", factureUpdated.mission_id)
                    .maybeSingle();

                  if (soignantEmail) {
                    await supabaseAdmin.functions.invoke("send-email", {
                      body: {
                        type: "PAIEMENT_RAPIDE_RECU",
                        destinataire_id: factureUpdated.soignant_id,
                        destinataire_email: soignantEmail,
                        data: {
                          soignant_prenom: soignantRow?.prenom || "",
                          montant_ttc: Number(factureUpdated.montant_ttc).toFixed(2),
                          numero_facture: factureUpdated.numero_facture,
                          mission_intitule: missionDetail?.intitule || "",
                          etablissement_nom:
                            (missionDetail?.etablissements as { nom?: string } | null)?.nom || "",
                          contexte: "CONNECT_MISSION_PAYMENT",
                        },
                      },
                    });
                  }
                } catch (emailErr) {
                  // Non-bloquant — le paiement et la mise à jour facture restent valides
                  console.error("send-email PAIEMENT_RAPIDE_RECU failed:", emailErr);
                }
                console.log(
                  `factures_honoraires ${factureHonorairesId} marked PAYEE for mission ${missionId}`
                );
              }
            } else {
              console.warn(
                `CONNECT webhook: missing facture_honoraires_id or payment_intent_id (session ${session.id})`
              );
            }

            // RGPD Art. 32 : audit du transfert financier (Stripe Connect mission payment)
            await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
              p_acteur_id: soignantId || "00000000-0000-0000-0000-000000000000",
              p_type_acteur: "SYSTEME",
              p_action: "FINANCE_TRANSFER_CONNECT",
              p_type_ressource: "mission",
              p_id_ressource: missionId,
              p_cle_s3: null,
              p_details: {
                stripe_transfer_id: transfer.id,
                stripe_charge_id: chargeId,
                stripe_payment_intent_id: paymentIntentId,
                stripe_session_id: session.id,
                soignant_id: soignantId,
                connected_account_id: connectedAccountId,
                facture_honoraires_id: factureHonorairesId || null,
                montant_cents: soignantCents,
                devise: "eur",
              },
              p_ip: null,
              p_navigateur: "stripe-webhook",
            });

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

      // [CP-STRIPE-3 H4] Update facture to PAYEE avec guard statut explicite.
      // Autrefois : .neq("statut", "PAYEE") — laissait passer ANNULEE/REMPLACEE/BROUILLON
      // qui pouvaient être marqués PAYEE si un webhook arrivait après annulation admin.
      // Désormais : .in("statut", ["EMISE","EN_RETARD"]) bloque ces cas ; si 0 row updated,
      // on logue une anomalie (webhook idempotent, on ne throw pas — le paiement Stripe
      // est déjà capturé côté Stripe, on ne peut pas le refuser rétroactivement).
      const { data: factureUpdated, error: updateErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "PAYEE",
          date_paiement: new Date().toISOString(),
          stripe_payment_intent_id: session.payment_intent as string,
          stripe_hosted_url: session.url,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", factureId)
        .in("statut", ["EMISE", "EN_RETARD"])
        .select("id, numero_facture, etablissement_id, montant_ttc")
        .maybeSingle();

      if (updateErr) {
        console.error("Erreur mise à jour facture:", updateErr);
        throw updateErr;
      }

      if (!factureUpdated) {
        // Anomalie : paiement Stripe capturé mais facture dans statut invalide
        // (ANNULEE/REMPLACEE/BROUILLON). Le paiement est côté Stripe mais rien
        // ne peut être comptabilisé côté plateforme. À investiguer manuellement.
        console.warn(
          `FACTURE webhook: facture ${factureId} not in EMISE/EN_RETARD, skipped (status may be ANNULEE/REMPLACEE)`
        );
        const { data: factureInvalide } = await supabaseAdmin
          .from("factures")
          .select("statut, etablissement_id")
          .eq("id", factureId)
          .maybeSingle();
        await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: factureInvalide?.etablissement_id || "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE",
          p_type_ressource: "facture",
          p_id_ressource: factureId,
          p_cle_s3: null,
          p_details: {
            raison: "statut_non_modifiable",
            statut_actuel: factureInvalide?.statut || "inconnu",
            stripe_session_id: session.id,
            stripe_payment_intent: session.payment_intent,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });
        return new Response(JSON.stringify({ received: true, skipped: "facture_statut_invalide" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // Alias pour la suite du bloc (audit + email) — factureUpdated tient déjà
      // numero_facture, etablissement_id, montant_ttc grâce au .select() ci-dessus.
      const facture = factureUpdated;

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
          // Fetch the etablissement before updating to capture it in audit
          const { data: mission } = await supabaseAdmin
            .from("missions")
            .select("etablissement_id")
            .eq("id", missionId)
            .single();

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

          // RGPD Art. 32 : audit du prélèvement SEPA
          if (mission?.etablissement_id) {
            await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
              p_acteur_id: mission.etablissement_id,
              p_type_acteur: "SYSTEME",
              p_action: "FINANCE_SEPA_CAPTURE",
              p_type_ressource: "mission",
              p_id_ressource: missionId,
              p_cle_s3: null,
              p_details: {
                stripe_charge_id: charge.id,
                montant_cents: charge.amount,
                devise: charge.currency,
                payment_method: "sepa_debit",
              },
              p_ip: null,
              p_navigateur: "stripe-webhook",
            });
          }

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
