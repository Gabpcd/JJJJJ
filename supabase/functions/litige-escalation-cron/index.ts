// litige-escalation-cron
//
// Cron quotidien (08h UTC) qui appelle les 4 RPCs du système litiges :
//   1. fn_auto_creation_litiges_presence()
//   2. fn_envoyer_rappels_litiges()
//   3. fn_litiges_escalader_auto()
//   4. fn_alerter_mediation_prioritaire()
//
// Auth : Bearer <service_role_key> (cf. pattern email-cron).
// Pas de body requis.
//
// Déploiement : cf. docs/cron-litiges.md.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Auth résiliente : accepte legacy JWT (KEY env) ou nouveau secret asymétrique
// (sb_secret_…) stocké en vault. Cf. docs/audit-infrastructure-production.md.
let _vaultSecret: string | null = null;
async function getVaultSecret(sb: any): Promise<string> {
  if (_vaultSecret) return _vaultSecret;
  const env = Deno.env.get("SUPABASE_SECRET_KEY") || Deno.env.get("SB_SECRET_KEY") || "";
  if (env) { _vaultSecret = env; return env; }
  try {
    const { data } = await sb.rpc('fn_lire_secret_cron');
    if (data) { _vaultSecret = data; return data; }
  } catch { /* ignore */ }
  return "";
}

Deno.serve(async (req) => {
  try {
    const sb = createClient(URL, KEY);

    // Auth service_role : legacy JWT OU vault secret
    const authHeader = req.headers.get("Authorization") || "";
    const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    const vaultSecret = await getVaultSecret(sb);
    const validBearers = [KEY, vaultSecret].filter(Boolean);
    if (!bearer || !validBearers.includes(bearer)) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const results: Record<string, unknown> = {};
    const t0 = Date.now();

    // Ordre d'exécution important :
    //   1. Auto-création AVANT rappels (pour que les nouveaux litiges
    //      n'échappent pas aux rappels).
    //   2. Rappels AVANT escalade (pour laisser une dernière chance).
    //   3. Escalade AVANT alerte médiation (même raison).

    try {
      const { data: r1, error: e1 } = await sb.rpc("fn_auto_creation_litiges_presence");
      if (e1) throw e1;
      results.auto_creation = r1;
    } catch (err) {
      console.error("fn_auto_creation_litiges_presence error:", err);
      results.auto_creation_error = (err as Error).message;
    }

    try {
      const { data: r2, error: e2 } = await sb.rpc("fn_envoyer_rappels_litiges");
      if (e2) throw e2;
      results.rappels = r2;
    } catch (err) {
      console.error("fn_envoyer_rappels_litiges error:", err);
      results.rappels_error = (err as Error).message;
    }

    try {
      const { data: r3, error: e3 } = await sb.rpc("fn_litiges_escalader_auto");
      if (e3) throw e3;
      results.escalade = r3;
    } catch (err) {
      console.error("fn_litiges_escalader_auto error:", err);
      results.escalade_error = (err as Error).message;
    }

    try {
      const { data: r4, error: e4 } = await sb.rpc("fn_alerter_mediation_prioritaire");
      if (e4) throw e4;
      results.mediation_prioritaire = r4;
    } catch (err) {
      console.error("fn_alerter_mediation_prioritaire error:", err);
      results.mediation_prioritaire_error = (err as Error).message;
    }

    // ── 5. Regen PDF/XML pour les factures flag pdf_a_regenerer=TRUE (CP-LITIGES-6) ──
    try {
      const { data: pending } = await sb.rpc("fn_lister_factures_a_regenerer", { p_limit: 50 });
      let regen_ok = 0, regen_fail = 0;
      for (const row of (pending || []) as Array<{ id: string; numero_facture: string; type_document: string }>) {
        try {
          await sb.functions.invoke("generate-invoice", {
            body: {
              facture_id: row.id,
              service_role_reason: `cron_auto_generation`,
            },
          });
          regen_ok++;
        } catch (e) {
          console.error(`regen ${row.numero_facture} failed:`, e);
          regen_fail++;
        }
      }
      results.regen = { ok: regen_ok, fail: regen_fail, total: (pending || []).length };
    } catch (err) {
      console.error("regen scan error:", err);
      results.regen_error = (err as Error).message;
    }

    const duration_ms = Date.now() - t0;
    console.log("litige-escalation-cron done:", { duration_ms, results });

    return new Response(
      JSON.stringify({ success: true, duration_ms, results }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("litige-escalation-cron fatal:", err);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
