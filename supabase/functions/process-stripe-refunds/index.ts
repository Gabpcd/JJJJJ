// process-stripe-refunds (SQUELETTE — T13)
//
// Cron qui consommera la table stripe_refunds_queue pour exécuter les
// remboursements Stripe après émission d'avoirs en mode AUTO_STRIPE.
//
// État actuel : HEARTBEAT uniquement — ne consomme PAS encore la queue.
// Sera finalisé en Sub-PR 3 consolidation Stripe Connect, après T12
// (câblage stripe_payment_intent_id sur factures_honoraires).
//
// Cf. /docs/tech-debt.md § T13 pour le plan d'activation.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (authHeader !== `Bearer ${KEY}`) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const sb = createClient(URL, KEY);

    // Heartbeat : on se contente de lire la queue pour remonter le nombre
    // d'avoirs en attente. Aucune action Stripe pour l'instant.
    const { count, error } = await sb
      .from("stripe_refunds_queue")
      .select("*", { count: "exact", head: true })
      .eq("statut", "EN_ATTENTE");

    if (error) {
      console.error("stripe_refunds_queue read error:", error);
      return new Response(
        JSON.stringify({ error: "Lecture queue impossible", details: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log("process-stripe-refunds heartbeat:", {
      timestamp: new Date().toISOString(),
      pending_count: count ?? 0,
      status: "SKELETON_NOT_PROCESSING",
      next_step: "T13 — implementer refunds.create() et mise à jour queue",
    });

    return new Response(
      JSON.stringify({
        success: true,
        status: "heartbeat",
        pending_count: count ?? 0,
        note: "SKELETON — not processing refunds yet (cf. tech-debt T13).",
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("process-stripe-refunds fatal:", err);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
