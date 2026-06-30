import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * SEPA Auto-Charge: called by cron (service_role) or admin manually.
 * For each EMISE facture of a SEPA-enabled établissement,
 * creates a PaymentIntent and charges the default SEPA payment method.
 */
Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "https://jolene.app",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    // Auth: service_role only (cron) or admin
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders });

    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const token = authHeader.replace("Bearer ", "");

    // Allow service_role or authenticated admin
    let isAuthorized = false;
    if (token === serviceRoleKey) {
      isAuthorized = true;
    } else {
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { data: { user } } = await supabaseAuth.auth.getUser(token);
      if (user) {
        const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
        const { data: userData } = await supabaseAdmin.auth.admin.getUserById(user.id);
        isAuthorized = userData?.user?.app_metadata?.role === "ADMIN_PLATEFORME";
      }
    }

    if (!isAuthorized) {
      return new Response(JSON.stringify({ error: "Réservé aux administrateurs" }), { status: 403, headers: corsHeaders });
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      return new Response(JSON.stringify({ error: "STRIPE_SECRET_KEY manquante" }), { status: 500, headers: corsHeaders });
    }
    const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });

    // Get all EMISE factures for SEPA-enabled establishments.
    // Idempotence : on EXCLUT les factures déjà tentées (stripe_payment_intent_id
    // renseigné) — un prélèvement SEPA reste « processing » plusieurs jours et la
    // facture demeure EMISE jusqu'au webhook payment_intent.succeeded → PAYEE. Sans
    // ce garde-fou, une exécution quotidienne re-prélèverait la même facture (double
    // débit). Un échec passe la facture en EN_RETARD (donc plus EMISE) → pas de retry ici.
    const { data: factures, error: fetchErr } = await supabaseAdmin
      .from("factures")
      .select("id, numero_facture, montant_ttc, etablissement_id, etablissements(nom, stripe_customer_id, stripe_sepa_payment_method_id, mode_paiement_commission)")
      .eq("statut", "EMISE")
      .is("stripe_payment_intent_id", null);

    if (fetchErr) {
      return new Response(JSON.stringify({ error: "Erreur chargement factures", details: fetchErr.message }), { status: 500, headers: corsHeaders });
    }

    // Filter to SEPA-enabled only
    const sepaFactures = (factures || []).filter((f: any) => {
      const etab = f.etablissements;
      return etab?.mode_paiement_commission === "SEPA_DEBIT"
        && etab?.stripe_customer_id
        && etab?.stripe_sepa_payment_method_id;
    });

    let charged = 0;
    let failed = 0;
    const results: any[] = [];

    for (const f of sepaFactures) {
      const etab = (f as any).etablissements;
      const amountCents = Math.round((f.montant_ttc ?? 0) * 100);
      if (amountCents <= 0) continue;

      try {
        const paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: "eur",
          customer: etab.stripe_customer_id,
          payment_method: etab.stripe_sepa_payment_method_id,
          confirm: true,
          off_session: true,
          mandate_data: {
            customer_acceptance: {
              type: "offline",
            },
          },
          description: `Facture ${f.numero_facture} — Commission Jolene`,
          statement_descriptor: "JOLENE",
          metadata: {
            facture_id: f.id,
            etablissement_id: f.etablissement_id,
            type: "SEPA_COMMISSION",
          },
        });

        // Update facture with payment intent
        await supabaseAdmin.from("factures").update({
          stripe_payment_intent_id: paymentIntent.id,
          modifie_le: new Date().toISOString(),
        }).eq("id", f.id);

        // If payment succeeded immediately (rare for SEPA, usually processing)
        if (paymentIntent.status === "succeeded") {
          await supabaseAdmin.from("factures").update({
            statut: "PAYEE",
            date_paiement: new Date().toISOString(),
            modifie_le: new Date().toISOString(),
          }).eq("id", f.id);
        }

        charged++;
        results.push({ facture: f.numero_facture, status: paymentIntent.status, pi: paymentIntent.id });
      } catch (stripeErr: any) {
        failed++;
        results.push({ facture: f.numero_facture, error: stripeErr.message });

        // Mark as EN_RETARD if payment failed
        await supabaseAdmin.from("factures").update({
          statut: "EN_RETARD",
          modifie_le: new Date().toISOString(),
        }).eq("id", f.id);
      }
    }

    return new Response(JSON.stringify({
      success: true,
      total_sepa_factures: sepaFactures.length,
      charged,
      failed,
      results,
    }), { status: 200, headers: corsHeaders });
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("sepa-auto-charge error:", msg);
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders });
  }
});
