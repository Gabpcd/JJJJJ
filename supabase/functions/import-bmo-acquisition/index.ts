// deno-lint-ignore-file no-import-prefix no-explicit-any
// Import silencieux des tensions BMO officielles France Travail.
// Cette fonction ne declenche aucun email, SMS, appel, notification ou action
// CRM. Elle ne fait qu'alimenter le radar interne departement x profession.

import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.99.2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import {
  aggregateBmoRecords,
  BMO_SOURCE_URL,
  mapBmoCode,
  parseBmoWorkbook,
} from "../_shared/bmo-acquisition.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";

const SOURCE_CODE = "BMO_FRANCE_TRAVAIL";
const SOURCE_PAGE =
  "https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo";
const FETCH_TIMEOUT_MS = 60_000;
const RPC_BATCH_SIZE = 200;

function normaliseHttpDate(value: string | null): string | null {
  const timestamp = Date.parse(value || "");
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

async function updateSource(
  admin: SupabaseClient<any>,
  values: Record<string, unknown>,
): Promise<void> {
  const { error } = await admin.from("acquisition_sources").update({
    ...values,
    maj_le: new Date().toISOString(),
  }).eq("code", SOURCE_CODE);
  if (error) console.error("acquisition_sources BMO:", error.message);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Methode non autorisee" }, 405);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
    { auth: { persistSession: false } },
  );
  let runId: string | null = null;

  try {
    const auth = await verifyAdminOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

    const { data: run, error: runError } = await admin.from("sourcing_imports")
      .insert({
        source_code: SOURCE_CODE,
        cible: "ETABLISSEMENT",
        statut: "EN_COURS",
        source_url: BMO_SOURCE_URL,
        details: {
          silencieux: true,
          contact_automatique: false,
          source_primaire: SOURCE_PAGE,
          codes_bmo: [
            "V0X60",
            "V1X80",
            "T2B60",
            "V2X90",
            "V2X91",
            "V3X70",
            "V3X80",
            "V4X84",
          ],
        },
      }).select("id").single();
    if (runError?.code === "23505") {
      return jsonResponse(req, {
        success: true,
        already_running: true,
        imported: 0,
        contacted: 0,
        contact_automatique: false,
      }, 202);
    }
    if (runError) throw new Error(runError.message);
    runId = run.id;

    const response = await fetch(BMO_SOURCE_URL, {
      headers: {
        Accept:
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/octet-stream;q=0.9",
        "User-Agent": "Jolene-Acquisition-Radar/1.0 (+https://jolene.app)",
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      redirect: "follow",
    });
    if (!response.ok) {
      throw new Error(`Telechargement BMO impossible (${response.status})`);
    }

    const sourceLastModified = normaliseHttpDate(
      response.headers.get("last-modified"),
    );
    const records = parseBmoWorkbook(
      new Uint8Array(await response.arrayBuffer()),
    );
    const rows = aggregateBmoRecords(
      records,
      BMO_SOURCE_URL,
      sourceLastModified,
    );
    let imported = 0;
    for (let index = 0; index < rows.length; index += RPC_BATCH_SIZE) {
      const batch = rows.slice(index, index + RPC_BATCH_SIZE);
      const { data, error } = await admin.rpc("fn_acquisition_upsert_bmo", {
        p_rows: batch,
      });
      if (error) throw new Error(error.message);
      imported += Number(data) || 0;
    }

    const now = new Date().toISOString();
    const years = [...new Set(records.map((record) => record.year))].sort();
    const professions = [
      ...new Set(
        records.flatMap((record) =>
          mapBmoCode(record.code).map((mapping) => mapping.profession)
        ),
      ),
    ].sort();
    const { error: runUpdateError } = await admin.from("sourcing_imports")
      .update({
        statut: "TERMINE",
        termine_le: now,
        source_maj_le: sourceLastModified,
        lignes_lues: records.length,
        lignes_importees: imported,
        details: {
          silencieux: true,
          contact_automatique: false,
          contacted: 0,
          source_primaire: SOURCE_PAGE,
          annees: years,
          professions,
          territoires_calcules: rows.length,
        },
      }).eq("id", runId);
    if (runUpdateError) throw new Error(runUpdateError.message);

    await updateSource(admin, {
      actif: true,
      automatique: true,
      dernier_import_le: now,
      dernier_statut: "OK",
      dernier_message: `${rows.length} tensions territoriales BMO calculees`,
    });

    return jsonResponse(req, {
      success: true,
      read: records.length,
      computed: rows.length,
      imported,
      years,
      professions,
      contacted: 0,
      contact_automatique: false,
    });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Erreur BMO inconnue";
    if (runId) {
      await admin.from("sourcing_imports").update({
        statut: "ERREUR",
        termine_le: new Date().toISOString(),
        erreur: message.slice(0, 1000),
      }).eq("id", runId);
    }
    await updateSource(admin, {
      dernier_statut: "ERREUR",
      dernier_message: message.slice(0, 500),
    });
    return jsonResponse(req, {
      error: message,
      imported: 0,
      contacted: 0,
      contact_automatique: false,
    }, 500);
  }
});
