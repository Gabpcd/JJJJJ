// litige-escalation-cron
//
// Cron quotidien (horaire piloté par pg_cron) qui appelle les 4 RPCs du
// système litiges :
//   1. fn_auto_creation_litiges_presence()
//   2. fn_envoyer_rappels_litiges()
//   3. fn_litiges_escalader_auto()
//   4. fn_alerter_mediation_prioritaire()
//
// Auth : secret d'automatisation dédié Vault, avec compatibilité transitoire
// service_role centralisée dans _shared/cron-service-auth.ts.
// Pas de body requis.
//
// Déploiement : cf. docs/cron-litiges.md.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  cronAuthErrorResponse,
  cronAuthProbeResponse,
  isCronAuthProbe,
  verifyCronServiceAuth,
} from "../_shared/cron-service-auth.ts";

const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
  try {
    const sb = createClient(URL, KEY, { auth: { persistSession: false } });
    const auth = await verifyCronServiceAuth(req, sb);
    if (!auth.ok) return cronAuthErrorResponse(auth);
    if (isCronAuthProbe(req)) return cronAuthProbeResponse(auth);

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
      const { data: pending, error: pendingError } = await sb.rpc(
        "fn_lister_factures_a_regenerer",
        { p_limit: 50 },
      );
      if (pendingError) {
        throw new Error(
          `fn_lister_factures_a_regenerer: ${pendingError.message}`,
        );
      }
      let regen_ok = 0, regen_fail = 0;
      let regen_test_skipped = 0;
      for (const row of (pending || []) as Array<{ id: string; numero_facture: string; type_document: string }>) {
        try {
          const { data: facture, error: factureError } = await sb
            .from("factures_honoraires")
            .select("mission_id")
            .eq("id", row.id)
            .maybeSingle();
          if (factureError || !facture?.mission_id) {
            throw new Error(
              `classification facture impossible: ${factureError?.message || row.id}`,
            );
          }
          const { data: missionReelle, error: missionReelleError } = await sb.rpc(
            "fn_mission_est_reelle_pour_service",
            { p_mission_id: facture.mission_id },
          );
          if (missionReelleError) {
            throw new Error(
              `classification mission impossible: ${missionReelleError.message}`,
            );
          }
          if (missionReelle !== true) {
            regen_test_skipped++;
            continue;
          }
          const { data: generated, error: generationError } =
            await sb.functions.invoke(
              "generate-invoice",
              {
                body: {
                  facture_id: row.id,
                  service_role_reason: `cron_auto_generation`,
                },
              },
            );
          if (generationError) {
            throw new Error(
              `generate-invoice invoke: ${generationError.message}`,
            );
          }
          if (
            generated?.success !== true ||
            generated?.mode !== "regen" ||
            generated?.facture_id !== row.id
          ) {
            throw new Error(
              `generate-invoice réponse invalide: ${
                generated?.error || JSON.stringify(generated)
              }`,
            );
          }
          regen_ok++;
        } catch (e) {
          console.error(`regen ${row.numero_facture} failed:`, e);
          regen_fail++;
        }
      }
      results.regen = {
        ok: regen_ok,
        fail: regen_fail,
        test_skipped: regen_test_skipped,
        total: (pending || []).length,
      };
    } catch (err) {
      console.error("regen scan error:", err);
      results.regen_error = (err as Error).message;
    }

    const duration_ms = Date.now() - t0;
    const failures = Object.keys(results).filter((key) => key.endsWith("_error"));
    const regen = results.regen as { fail?: number } | undefined;
    if ((regen?.fail ?? 0) > 0) failures.push("regen");
    const success = failures.length === 0;
    console.log("litige-escalation-cron done:", {
      request_id: requestId,
      success,
      failures,
      duration_ms,
      results,
    });

    return new Response(
      JSON.stringify({ success, request_id: requestId, failures, duration_ms, results }),
      {
        status: success ? 200 : 500,
        headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
      },
    );
  } catch (err) {
    console.error("litige-escalation-cron fatal:", { request_id: requestId, error: err });
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue.", request_id: requestId }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
