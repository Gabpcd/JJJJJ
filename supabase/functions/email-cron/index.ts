import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
serve(async () => {
  try {
    const sb = createClient(URL, KEY);
    const results: Record<string, number> = {};
    const { data: r1 } = await sb.rpc("fn_email_rappels_j1");
    let c = 0;
    for (const r of r1 || []) { await sb.functions.invoke("send-email", { body: { type: "RAPPEL_MISSION", destinataire_id: r.soignant_id, data: { prenom: r.prenom, mission: r.mission, etablissement: r.etablissement, heure_debut: r.heure_debut } } }); c++; }
    results.rappels_j1 = c;
    const { data: v2 } = await sb.rpc("fn_verifier_documents_expirants");
    results.docs_expirants = v2 || 0;
    const { data: v3 } = await sb.rpc("fn_auto_facturation_mensuelle");
    results.factures = v3 || 0;
    const { data: v4 } = await sb.rpc("fn_purger_gps_ancien");
    results.purge_gps = v4 || 0;
    const { data: v5 } = await sb.rpc("fn_nettoyer_tokens_push");
    results.tokens_push = v5 || 0;
    return new Response(JSON.stringify({ success: true, results }), { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": (Deno.env.get("APP_URL") || "https://app.jolene.app") } });
  } catch (err) {
    console.error("email-cron error:", err);
    return new Response(JSON.stringify({ error: "Erreur interne", details: String(err) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
