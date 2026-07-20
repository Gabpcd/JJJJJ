// Import de la réexposition officielle FINESS data.gouv dans
// prospects_etablissements. Le fichier stable est actualisé par data.gouv à
// chaque publication ministérielle ; aucune URL datée n'est figée ici.
// Cette fonction ne contacte jamais les prospects.
// Déclenchement : POST { offset?: number, run_id?: uuid } + Bearer service_role/vault.

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";

const FICHIER = "https://data-pipeline-open.s3.sbg.io.cloud.ovh.net/finess/finess_etablissements.csv";
const SOURCE_PAGE = "https://www.data.gouv.fr/datasets/reexposition-des-donnees-finess";
// Passes courtes pour ne pas saturer la base pendant la première charge.
const TRANCHE = 1024 * 1024;            // 1 Mo par requête Range
const TAILLE_UPSERT = 100;
const BUDGET_MS = 90_000;               // puis auto-relance

// libcategetab / libcategagretab → type Jolene (null = ignoré)
function mapType(libCateg: string, libAgr: string): string | null {
  // On teste les DEUX libellés (catégorie fine + agrégat) — les libellés FINESS
  // n'utilisent pas l'acronyme EHPAD mais « personnes âgées ».
  const s = `${libCateg || ""} ${libAgr || ""}`.toLowerCase();
  if (s.includes("ehpad") || s.includes("personnes âgées") || s.includes("personnes agées") || s.includes("personnes agees")) return "EHPAD";
  if (s.includes("hospitalier") || s.includes("hôpital") || s.includes("hopital") || s.includes("soins de suite") || s.includes("réadaptation")) return "HOPITAL";
  if (s.includes("officine")) return "PHARMACIE";
  if (s.includes("laboratoire")) return "LABO";
  if (s.includes("domicile") || s.includes("ssiad")) return "DOMICILE";
  if (s.includes("handicap") || s.includes("enfance inadaptée") || s.includes("enfance inadaptee")) return "HANDICAP";
  if (s.includes("dialyse")) return "DIALYSE";
  if (s.includes("centre de santé") || s.includes("centre de sante") || s.includes("maison de santé") || s.includes("maison de sante")) return "CENTRE_SANTE";
  // Écoles de formation sanitaire (IFSI, IFAS, instituts paramédicaux) — cible
  // prospection étudiants : BDE, directions, affichage, partenariats stages.
  // Libellés FINESS réels (sondés) : « Ecoles Formant aux Professions Sanitaires »
  // (agrégat « Etablissements de Formation des Personnels Sanitaires ») + polyvalentes.
  // Les écoles purement sociales sont exclues.
  if (s.includes("formant aux professions sanitaires") || s.includes("formation des personnels sanitaires") || s.includes("formation polyvalente")) return "ECOLE_SANTE";
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  let runId: string | null = null;
  try {
    const auth = await verifyAdminOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
    const { offset = 0, run_id = null, lignes_lues = 0, lignes_importees = 0 } = await req.json().catch(() => ({}));

    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    runId = typeof run_id === "string" ? run_id : null;
    if (!runId) {
      const { data: actif } = await admin.from("sourcing_imports")
        .select("id, demarre_le")
        .eq("source_code", "FINESS_DATA_GOUV")
        .eq("statut", "EN_COURS")
        .gte("demarre_le", new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString())
        .order("demarre_le", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (actif?.id) return jsonResponse(req, { success: true, already_running: true, run_id: actif.id });

      const { data: run, error: runErr } = await admin.from("sourcing_imports").insert({
        source_code: "FINESS_DATA_GOUV",
        cible: "ETABLISSEMENT",
        source_url: SOURCE_PAGE,
        details: { fichier: FICHIER, silencieux: true },
      }).select("id").single();
      if (runErr) throw new Error(runErr.message);
      runId = run.id;
    }

    const debut = Date.now();
    let pos = Number(offset) || 0;
    let totalInsere = 0;
    let totalLues = 0;
    let done = false;
    let sourceMajLe: string | null = null;

    while (Date.now() - debut < BUDGET_MS) {
      const r = await fetch(FICHIER, { headers: { Range: `bytes=${pos}-${pos + TRANCHE - 1}` } });
      if (r.status === 416) { done = true; break; }            // au-delà de la fin
      if (!r.ok && r.status !== 206 && r.status !== 200) {
        throw new Error(`Téléchargement FINESS impossible (${r.status}) à l'octet ${pos}`);
      }
      const buf = new Uint8Array(await r.arrayBuffer());
      const lastModified = r.headers.get("last-modified");
      if (lastModified) sourceMajLe = new Date(lastModified).toISOString();
      // Le fichier FINESS est encodé en UTF-8 (vérifié sur les libellés accentués)
      const texte = new TextDecoder("utf-8").decode(buf);
      const finFichier = r.status === 200 || buf.byteLength < TRANCHE;

      // On ne traite que les lignes complètes ; la dernière (partielle) est reportée
      const dernierNL = texte.lastIndexOf("\n");
      if (dernierNL < 0) { pos += buf.byteLength; if (finFichier) done = true; continue; }
      const bloc = texte.slice(0, dernierNL);
      // Avancer du nombre d'OCTETS réellement consommés (UTF-8 multi-octets)
      pos += new TextEncoder().encode(texte.slice(0, dernierNL + 1)).length;

      const lignes = bloc.split("\n");
      const rows: Record<string, unknown>[] = [];
      // Le CSV FINESS contient des champs sur-échappés ("""LE PLA""") : on retire
      // les guillemets parasites et on normalise les espaces sur tout champ texte.
      const nettoie = (s: string) => (s || "").replace(/"/g, "").replace(/\s+/g, " ").trim();
      for (const ligne of lignes) {
        const f = ligne.split(";");
        // Réexposition data.gouv : 35 colonnes, en-tête nofinesset;...
        if (f.length < 35 || f[0] === "nofinesset") continue;
        totalLues++;
        const type = mapType(f[18], f[20]);
        if (!type) continue;
        const finess = (f[0] || "").trim();
        if (!/^\d{9}$/.test(finess)) continue;
        const achemine = (f[14] || "").trim();          // "75014 PARIS"
        const cp = achemine.slice(0, 5);
        const ville = nettoie(achemine.slice(6));
        const adresse = [f[6], f[7], f[8], f[9], f[10]].map(s => nettoie(s)).filter(Boolean).join(" ");
        rows.push({
          finess,
          siret: (f[21] || "").trim() || null,
          nom: nettoie((f[2] || f[3])) || "—",
          type_jolene: type,
          categorie_lib: nettoie(f[18]) || null,
          telephone: (f[15] || "").trim() || null,
          adresse: adresse || null,
          code_postal: /^\d{5}$/.test(cp) ? cp : null,
          ville: ville || null,
          departement: (f[12] || "").trim().toUpperCase() || null,
          source_code: "FINESS_DATA_GOUV",
          source_url: SOURCE_PAGE,
          source_maj_le: sourceMajLe,
        });
      }

      for (let i = 0; i < rows.length; i += TAILLE_UPSERT) {
        const { data: upserts, error } = await admin.rpc("fn_sourcing_upsert_etablissements", {
          p_rows: rows.slice(i, i + TAILLE_UPSERT),
        });
        if (error) throw new Error(`${error.message} (octet ${pos})`);
        totalInsere += Number(upserts) || 0;
      }

      if (finFichier) { done = true; break; }
    }

    if (!done) {
      // Auto-relance pour la suite du fichier — waitUntil garantit que la
      // requête part même après le retour de la réponse.
      const relance = fetch(`${url}/functions/v1/import-finess`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({
          offset: pos,
          run_id: runId,
          lignes_lues: Number(lignes_lues) + totalLues,
          lignes_importees: Number(lignes_importees) + totalInsere,
        }),
      }).catch(() => {});
      (globalThis as any).EdgeRuntime?.waitUntil?.(relance);
    }

    await admin.from("sourcing_imports").update({
      statut: done ? "TERMINE" : "EN_COURS",
      termine_le: done ? new Date().toISOString() : null,
      source_maj_le: sourceMajLe,
      lignes_lues: Number(lignes_lues) + totalLues,
      lignes_importees: Number(lignes_importees) + totalInsere,
    }).eq("id", runId);

    return jsonResponse(req, {
      done,
      run_id: runId,
      next_offset: pos,
      lues_cette_passe: totalLues,
      inserees_cette_passe: totalInsere,
    });
  } catch (e) {
    if (runId) {
      await createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } })
        .from("sourcing_imports")
        .update({ statut: "ERREUR", termine_le: new Date().toISOString(), erreur: ((e as Error)?.message || "erreur").slice(0, 1000) })
        .eq("id", runId);
    }
    return jsonResponse(req, { error: (e as Error)?.message || "erreur" }, 500);
  }
});
