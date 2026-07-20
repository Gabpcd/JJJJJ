// Importe l'extraction officielle en libre accès de l'Annuaire Santé (RPPS).
// Elle couvre les professionnels salariés, libéraux et étudiants, avec leur
// structure d'exercice et ses coordonnées publiques. Le traitement est un
// sourcing silencieux : aucune donnée n'est utilisée pour envoyer un message.

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";

const FICHIER = "https://www.data.gouv.fr/api/1/datasets/r/fffda7e9-0ea2-4c35-bba0-4496f3af935d";
const SOURCE_PAGE = "https://www.data.gouv.fr/datasets/annuaire-sante-extractions-des-donnees-en-libre-acces-des-professionnels-intervenant-dans-le-systeme-de-sante-rpps";
// Lots volontairement modestes : la première synchronisation ajoute plusieurs
// centaines de milliers de lignes et partage les ressources de la base avec
// l'application. On privilégie des passes courtes et auto-reprises.
const TRANCHE = 1024 * 1024;
// La fonction SQL n'écrit désormais que les nouvelles clés officielles : les
// doublons d'une reprise ou d'une synchronisation hebdomadaire sont ignorés et
// ne réindexent plus toute la table historique.
const TAILLE_UPSERT = 25;
const BUDGET_MS = 20_000;
const MAX_REPRISES_TIMEOUT = 12;

function sansAccents(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

/** Convertit les libellés officiels vers le référentiel de missions Jolene. */
export function mapProfession(libelleProfession: string, savoirFaire = ""): string | null {
  const profession = sansAccents(libelleProfession || "");
  const specialite = sansAccents(savoirFaire || "");
  const ensemble = `${profession} ${specialite}`;

  if (ensemble.includes("infirmier") && (ensemble.includes("anesthes") || ensemble.includes("iade"))) return "IADE";
  if (ensemble.includes("infirmier") && (ensemble.includes("bloc operatoire") || ensemble.includes("ibode"))) return "IBODE";
  if (profession.includes("infirmier")) return "IDE";
  if (profession.includes("aide-soignant")) return "AS";
  if (profession.includes("accompagnant educatif et social") || profession === "aes") return "AES";
  if (profession.includes("auxiliaire de puericulture")) return "AUXILIAIRE_PUERICULTURE";
  if (profession.includes("sage-femme") || profession.includes("sage femme")) return "SAGE_FEMME";
  if (profession.includes("masseur-kinesitherapeute") || profession.includes("kinesitherapeute")) return "KINE";
  if (profession === "medecin" || profession.startsWith("medecin ")) return "MEDECIN";
  if (profession.includes("chirurgien-dentiste") || profession.includes("chirurgien dentiste")) return "DENTISTE";
  if (profession.includes("pharmacien")) return "PHARMACIEN";
  if (profession.includes("manipulateur") && (profession.includes("electroradiologie") || profession.includes("radio"))) return "MANIPULATEUR_RADIO";
  if (profession.includes("preparateur") && profession.includes("pharmacie")) return "PREPARATEUR_PHARMA";
  if (profession.includes("dieteticien")) return "DIETETICIEN";
  if (profession.includes("ergotherapeute")) return "ERGOTHERAPEUTE";
  if (profession.includes("psychomotricien")) return "PSYCHOMOTRICIEN";
  if (profession.includes("orthophoniste")) return "ORTHOPHONISTE";
  return null;
}

function nettoie(value: string | undefined): string {
  return String(value || "").replace(/\r/g, "").replace(/\s+/g, " ").trim();
}

function departementDepuis(cp: string, codeOfficiel: string): string | null {
  const code = nettoie(codeOfficiel).toUpperCase();
  if (code) return code;
  if (!/^\d{5}$/.test(cp)) return null;
  if (cp.startsWith("97") || cp.startsWith("98")) return cp.slice(0, 3);
  return cp.slice(0, 2);
}

interface LigneProspect {
  cle: string;
  nom: string;
  prenom: string | null;
  profession: string;
  enseigne: string | null;
  telephone: string | null;
  email: string | null;
  adresse: string | null;
  code_postal: string | null;
  ville: string | null;
  departement: string | null;
  est_etudiant: boolean;
  numero_rpps: string | null;
  mode_exercice: string | null;
  finess_structure: string | null;
  siret_structure: string | null;
  source_code: "ANNUAIRE_SANTE_RPPS";
  source_url: string;
  source_maj_le: string | null;
}

function fusionne(existing: LigneProspect | undefined, next: LigneProspect): LigneProspect {
  if (!existing) return next;
  const rang = (profession: string) => profession === "IADE" || profession === "IBODE" ? 2 : profession === "IDE" ? 1 : 0;
  return {
    ...existing,
    ...next,
    profession: rang(next.profession) >= rang(existing.profession) ? next.profession : existing.profession,
    telephone: next.telephone || existing.telephone,
    email: next.email || existing.email,
    enseigne: next.enseigne || existing.enseigne,
    adresse: next.adresse || existing.adresse,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  let runId: string | null = null;
  let repriseOffset = 0;
  let repriseLues = 0;
  let repriseImportees = 0;
  let reprisesTimeout = 0;

  try {
    const body = await req.json().catch(() => ({}));
    const offset = Number(body.offset) || 0;
    const luesAvant = Number(body.lignes_lues) || 0;
    const importeesAvant = Number(body.lignes_importees) || 0;
    reprisesTimeout = Number(body.reprises_timeout) || 0;
    repriseOffset = offset;
    repriseLues = luesAvant;
    repriseImportees = importeesAvant;
    runId = typeof body.run_id === "string" ? body.run_id : null;

    if (!runId) {
      const { data: actif } = await admin.from("sourcing_imports")
        .select("id, demarre_le")
        .eq("source_code", "ANNUAIRE_SANTE_RPPS")
        .eq("statut", "EN_COURS")
        .gte("demarre_le", new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString())
        .order("demarre_le", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (actif?.id) return jsonResponse(req, { success: true, already_running: true, run_id: actif.id });

      const { data: run, error: runErr } = await admin.from("sourcing_imports").insert({
        source_code: "ANNUAIRE_SANTE_RPPS",
        cible: "SOIGNANT",
        source_url: SOURCE_PAGE,
        details: { fichier: FICHIER, silencieux: true, format: "PS_LibreAcces_Personne_activite" },
      }).select("id").single();
      if (runErr) throw new Error(runErr.message);
      runId = run.id;
    }

    const debut = Date.now();
    let pos = offset;
    let totalLues = 0;
    let totalImportees = 0;
    let done = false;
    let sourceMajLe: string | null = null;

    while (Date.now() - debut < BUDGET_MS) {
      const response = await fetch(FICHIER, { headers: { Range: `bytes=${pos}-${pos + TRANCHE - 1}` } });
      if (response.status === 416) { done = true; break; }
      if (!response.ok && response.status !== 206 && response.status !== 200) {
        throw new Error(`Téléchargement Annuaire Santé impossible (${response.status})`);
      }

      const lastModified = response.headers.get("last-modified");
      if (lastModified) sourceMajLe = new Date(lastModified).toISOString();
      const buffer = new Uint8Array(await response.arrayBuffer());
      const texte = new TextDecoder("utf-8").decode(buffer);
      const finFichier = response.status === 200 || buffer.byteLength < TRANCHE;
      const dernierNL = texte.lastIndexOf("\n");
      if (dernierNL < 0) {
        pos += buffer.byteLength;
        if (finFichier) done = true;
        continue;
      }

      const bloc = texte.slice(0, dernierNL);
      pos += new TextEncoder().encode(texte.slice(0, dernierNL + 1)).length;
      const prospects = new Map<string, LigneProspect>();

      for (const ligne of bloc.split("\n")) {
        const f = ligne.split("|");
        if (f.length < 56 || f[0] === "Type d'identifiant PP") continue;
        totalLues++;

        const profession = mapProfession(f[10], `${f[14]} ${f[16]}`);
        if (!profession) continue;
        const identifiant = nettoie(f[1]) || nettoie(f[2]);
        const nom = nettoie(f[7]);
        if (!identifiant || !nom) continue;

        const rpps = /^\d{11}$/.test(nettoie(f[1])) ? nettoie(f[1]) : null;
        const siret = /^\d{14}$/.test(nettoie(f[19])) ? nettoie(f[19]) : null;
        const finess = /^\d{9}$/.test(nettoie(f[21])) ? nettoie(f[21]) : null;
        const cp = /^\d{5}$/.test(nettoie(f[35])) ? nettoie(f[35]) : null;
        const site = finess || siret || cp || nettoie(f[23]) || "sans-structure";
        const cle = `ans:${identifiant}:${site}`.toLowerCase().slice(0, 220);
        const telephone = nettoie(f[40]).replace(/[^\d+]/g, "") || nettoie(f[41]).replace(/[^\d+]/g, "") || null;
        const emailBrut = nettoie(f[43]).toLowerCase();
        const email = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(emailBrut) ? emailBrut : null;
        const adresse = [f[26], f[27], f[28], f[29], f[31], f[32], f[33], f[34]].map(nettoie).filter(Boolean).join(" ") || null;
        const categorie = sansAccents(f[12] || "");

        const prospect: LigneProspect = {
          cle,
          nom,
          prenom: nettoie(f[8]) || null,
          profession,
          enseigne: nettoie(f[25]) || nettoie(f[24]) || null,
          telephone: telephone && telephone.replace(/\D/g, "").length >= 9 ? telephone : null,
          email,
          adresse,
          code_postal: cp,
          ville: nettoie(f[37]) || null,
          departement: departementDepuis(cp || "", f[44]),
          est_etudiant: categorie.includes("etudiant") || categorie.includes("formation"),
          numero_rpps: rpps,
          mode_exercice: nettoie(f[18]) || null,
          finess_structure: finess,
          siret_structure: siret,
          source_code: "ANNUAIRE_SANTE_RPPS",
          source_url: SOURCE_PAGE,
          source_maj_le: sourceMajLe,
        };
        prospects.set(cle, fusionne(prospects.get(cle), prospect));
      }

      const rows = [...prospects.values()];
      for (let i = 0; i < rows.length; i += TAILLE_UPSERT) {
        const { data: upserts, error } = await admin.rpc("fn_sourcing_upsert_soignants", {
          p_rows: rows.slice(i, i + TAILLE_UPSERT),
        });
        if (error) throw new Error(error.message);
        totalImportees += Number(upserts) || 0;
      }

      // Le curseur ne progresse qu'une fois toute la tranche écrite. Si une
      // requête suivante expire, la reprise rejoue au plus cette tranche ; les
      // doublons sont ignorés par la fonction SQL idempotente.
      repriseOffset = pos;
      repriseLues = luesAvant + totalLues;
      repriseImportees = importeesAvant + totalImportees;
      reprisesTimeout = 0;
      await admin.from("sourcing_imports").update({
        lignes_lues: repriseLues,
        lignes_importees: repriseImportees,
        details: {
          fichier: FICHIER,
          silencieux: true,
          format: "PS_LibreAcces_Personne_activite",
          next_offset: repriseOffset,
        },
      }).eq("id", runId);
      if (finFichier) { done = true; break; }
    }

    const compteurs = {
      lignes_lues: luesAvant + totalLues,
      lignes_importees: importeesAvant + totalImportees,
    };
    await admin.from("sourcing_imports").update({
      statut: done ? "TERMINE" : "EN_COURS",
      termine_le: done ? new Date().toISOString() : null,
      source_maj_le: sourceMajLe,
      ...compteurs,
    }).eq("id", runId);

    if (!done) {
      const relance = fetch(`${url}/functions/v1/import-annuaire-rpps`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({ offset: pos, run_id: runId, ...compteurs }),
      }).catch(() => undefined);
      (globalThis as any).EdgeRuntime?.waitUntil?.(relance);
    }

    return jsonResponse(req, {
      success: true,
      done,
      run_id: runId,
      next_offset: pos,
      lues_cette_passe: totalLues,
      importees_cette_passe: totalImportees,
      ...compteurs,
    });
  } catch (error) {
    const message = (error as Error).message;
    if (runId && message.includes("statement timeout") && reprisesTimeout < MAX_REPRISES_TIMEOUT) {
      const prochainEssai = reprisesTimeout + 1;
      await admin.from("sourcing_imports").update({
        statut: "EN_COURS",
        termine_le: null,
        erreur: null,
        lignes_lues: repriseLues,
        lignes_importees: repriseImportees,
        details: {
          fichier: FICHIER,
          silencieux: true,
          format: "PS_LibreAcces_Personne_activite",
          next_offset: repriseOffset,
          reprise_timeout: prochainEssai,
        },
      }).eq("id", runId);

      const relance = new Promise((resolve) => setTimeout(resolve, 1_500)).then(() => fetch(
        `${url}/functions/v1/import-annuaire-rpps`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({
            offset: repriseOffset,
            run_id: runId,
            lignes_lues: repriseLues,
            lignes_importees: repriseImportees,
            reprises_timeout: prochainEssai,
          }),
        },
      )).catch(() => undefined);
      (globalThis as any).EdgeRuntime?.waitUntil?.(relance);
      return jsonResponse(req, {
        success: true,
        retrying: true,
        run_id: runId,
        next_offset: repriseOffset,
        reprise_timeout: prochainEssai,
      }, 202);
    }

    if (runId) {
      await admin.from("sourcing_imports").update({
        statut: "ERREUR",
        termine_le: new Date().toISOString(),
        erreur: message.slice(0, 1000),
      }).eq("id", runId);
    }
    return jsonResponse(req, { error: message }, 500);
  }
});
