// Signaux publics BOAMP — avis nommés de mise à disposition, intérim ou
// remplacement de personnel médical/paramédical. Aucun contact n'est envoyé.

import {
  getServiceRoleClient,
  verifyAdminOrServiceRole,
} from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import {
  BOAMP_SOURCE_CODE,
  type BoampRecord,
  mapperAvisBoamp,
} from "./mapping.ts";

const SOURCE_PAGE = "https://www.data.gouv.fr/datasets/boamp";
const API_URL =
  "https://boamp-datadila.opendatasoft.com/api/explore/v2.1/catalog/datasets/boamp/records";
const PAGE_SIZE = 100;
const MAX_PAGES = 20;
const BATCH_SIZE = 100;

type BoampApiResponse = {
  total_count?: number;
  results?: BoampRecord[];
};

export function queryActiveAvis(now: Date): string {
  const today = now.toISOString().slice(0, 10);
  return `(datelimitereponse >= now() OR (datelimitereponse is null AND datefindiffusion >= date'${today}')) ` +
    `AND (nature is null OR nature != "ATTRIBUTION") AND (` +
    `search(donnees, "79624000") OR search(donnees, "79625000") ` +
    `OR search(objet, "personnel médical") OR search(objet, "personnel paramédical") ` +
    `OR search(objet, "personnel medico social") OR search(objet, "intérim médical") ` +
    `OR search(objet, "intérim paramédical") OR search(objet, "personnel infirmier") ` +
    `OR search(objet, "aide-soignant") OR search(objet, "remplacement de personnel médical")` +
    `)`;
}

async function fetchJsonWithRetry(url: URL): Promise<BoampApiResponse> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(30_000),
      });
      if (response.ok) {
        const payload = await response.json() as BoampApiResponse;
        if (!Array.isArray(payload.results)) {
          throw new Error("Réponse BOAMP sans tableau results");
        }
        return payload;
      }
      if (response.status !== 429 && response.status < 500) {
        throw new Error(`API BOAMP indisponible (${response.status})`);
      }
      lastError = new Error(
        `API BOAMP temporairement indisponible (${response.status})`,
      );
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
    }
    if (attempt < 2) {
      await new Promise((resolve) => setTimeout(resolve, 500 * (2 ** attempt)));
    }
  }
  throw lastError || new Error("API BOAMP indisponible");
}

async function fetchActiveAvis(now: Date): Promise<BoampRecord[]> {
  const records = new Map<string, BoampRecord>();
  let offset = 0;
  let total = Number.POSITIVE_INFINITY;

  for (let page = 0; page < MAX_PAGES && offset < total; page += 1) {
    const url = new URL(API_URL);
    url.searchParams.set(
      "select",
      [
        "idweb",
        "objet",
        "dateparution",
        "datefindiffusion",
        "datelimitereponse",
        "nomacheteur",
        "titulaire",
        "code_departement",
        "code_departement_prestation",
        "nature",
        "nature_libelle",
        "procedure_libelle",
        "source_schema",
        "descripteur_libelle",
        "url_avis",
        "donnees",
      ].join(","),
    );
    url.searchParams.set("where", queryActiveAvis(now));
    url.searchParams.set("order_by", "dateparution DESC,idweb ASC");
    url.searchParams.set("limit", String(PAGE_SIZE));
    url.searchParams.set("offset", String(offset));

    const payload = await fetchJsonWithRetry(url);
    total = Number.isFinite(Number(payload.total_count))
      ? Number(payload.total_count)
      : 0;
    const pageRecords = payload.results || [];
    for (const record of pageRecords) {
      const id = typeof record.idweb === "string" ? record.idweb.trim() : "";
      if (id) records.set(id, record);
    }
    offset += pageRecords.length;
    if (pageRecords.length === 0) break;
  }

  if (offset < total) {
    throw new Error(
      `Volume BOAMP inattendu (${total} avis) : import interrompu avant toute expiration`,
    );
  }
  return [...records.values()];
}

export async function handleBoampImport(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Methode non autorisee" }, 405);
  }

  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

  const admin = getServiceRoleClient();
  const now = new Date();
  const nowIso = now.toISOString();
  let runId: string | null = null;
  let read = 0;
  let accepted = 0;
  let imported = 0;
  let expired = 0;

  try {
    const { data: run, error: runError } = await admin.from("sourcing_imports")
      .insert({
        source_code: BOAMP_SOURCE_CODE,
        cible: "ETABLISSEMENT",
        statut: "EN_COURS",
        source_url: SOURCE_PAGE,
        details: {
          dataset: "boamp",
          api: API_URL,
          filtres: [
            "CPV 79624000/79625000",
            "personnel médical/paramédical explicite",
          ],
          silencieux: true,
          contact_automatique: false,
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
    if (runError || !run?.id) {
      throw new Error(runError?.message || "Journal BOAMP non créé");
    }
    runId = run.id;

    const avis = await fetchActiveAvis(now);
    read = avis.length;
    const rows = avis.flatMap((record) => mapperAvisBoamp(record, now));
    accepted = new Set(rows.map((row) => row.details.avis_boamp_id)).size;

    for (let index = 0; index < rows.length; index += BATCH_SIZE) {
      const { data, error } = await admin.rpc("fn_acquisition_upsert_signaux", {
        p_rows: rows.slice(index, index + BATCH_SIZE),
      });
      if (error) throw new Error(error.message);
      imported += Number(data) || 0;
    }

    // Ne jamais expirer les signaux d'une autre source. Les avis BOAMP sont
    // retirés du radar uniquement quand leur échéance officielle est passée.
    const { count: expiredCount, error: expireError } = await admin
      .from("acquisition_signaux")
      .update({ statut: "EXPIRE", maj_le: nowIso }, { count: "exact" })
      .eq("source_code", BOAMP_SOURCE_CODE)
      .in("statut", ["NOUVEAU", "QUALIFIE", "CRM"])
      .not("expire_le", "is", null)
      .lt("expire_le", nowIso);
    if (expireError) throw new Error(expireError.message);
    expired = expiredCount || 0;

    const latestPublished = avis
      .map((record) =>
        typeof record.dateparution === "string" ? record.dateparution : null
      )
      .filter((date): date is string => Boolean(date))
      .sort()
      .at(-1);
    const details = {
      dataset: "boamp",
      read,
      accepted,
      rejected: read - accepted,
      signals: rows.length,
      expired,
      silencieux: true,
      contact_automatique: false,
    };
    const message =
      `${accepted} avis pertinents, ${rows.length} signaux, ${expired} expirés`;

    const [journalUpdate, sourceUpdate] = await Promise.all([
      admin.from("sourcing_imports").update({
        statut: "TERMINE",
        source_maj_le: latestPublished
          ? new Date(`${latestPublished}T00:00:00Z`).toISOString()
          : null,
        termine_le: nowIso,
        lignes_lues: read,
        lignes_importees: imported,
        details,
      }).eq("id", runId),
      admin.from("acquisition_sources").update({
        actif: true,
        automatique: true,
        dernier_import_le: nowIso,
        dernier_statut: "OK",
        dernier_message: message,
        maj_le: nowIso,
      }).eq("code", BOAMP_SOURCE_CODE),
    ]);
    if (journalUpdate.error) throw new Error(journalUpdate.error.message);
    if (sourceUpdate.error) throw new Error(sourceUpdate.error.message);

    return jsonResponse(req, {
      success: true,
      read,
      accepted,
      rejected: read - accepted,
      signals: rows.length,
      imported,
      expired,
      contacted: 0,
      contact_automatique: false,
    });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Erreur BOAMP inconnue";
    const updates: Array<PromiseLike<unknown>> = [];
    if (runId) {
      updates.push(
        admin.from("sourcing_imports").update({
          statut: "ERREUR",
          termine_le: new Date().toISOString(),
          lignes_lues: read,
          lignes_importees: imported,
          erreur: message.slice(0, 1000),
          details: {
            read,
            accepted,
            expired,
            silencieux: true,
            contact_automatique: false,
          },
        }).eq("id", runId),
      );
    }
    updates.push(
      admin.from("acquisition_sources").update({
        dernier_statut: "ERREUR",
        dernier_message: message.slice(0, 500),
        maj_le: new Date().toISOString(),
      }).eq("code", BOAMP_SOURCE_CODE),
    );
    await Promise.allSettled(updates);
    return jsonResponse(req, {
      error: message,
      read,
      imported,
      expired,
      contacted: 0,
      contact_automatique: false,
    }, 500);
  }
}

if (import.meta.main) Deno.serve(handleBoampImport);
