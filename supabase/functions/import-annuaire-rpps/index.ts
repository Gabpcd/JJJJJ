// deno-lint-ignore-file no-import-prefix no-explicit-any
// Importe l'extraction officielle en libre accès de l'Annuaire Santé (RPPS).
// Elle couvre les professionnels salariés, libéraux et étudiants, avec leur
// structure d'exercice et ses coordonnées publiques. Le traitement est un
// sourcing silencieux : aucune donnée n'est utilisée pour envoyer un message.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import {
  erreurRppsReprenable,
  peutPublierStatutSource,
} from "./helpers.ts";

const FICHIER = "https://www.data.gouv.fr/api/1/datasets/r/fffda7e9-0ea2-4c35-bba0-4496f3af935d";
const SOURCE_PAGE = "https://www.data.gouv.fr/datasets/annuaire-sante-extractions-des-donnees-en-libre-acces-des-professionnels-intervenant-dans-le-systeme-de-sante-rpps";
const SOURCE_CODE = "ANNUAIRE_SANTE_RPPS";
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
// Le watchdog tourne toutes les cinq minutes. Une passe normale dure environ
// vingt secondes : au-delà de ce délai, l'absence de heartbeat signifie que
// l'auto-relance n'est pas partie ou que l'instance Edge a été interrompue.
const HEARTBEAT_STALE_MS = 5 * 60 * 1000;

// Le client service-role n'utilise pas les types générés de l'application dans
// l'Edge Runtime ; le schéma est validé par les migrations et les RPC.
type AdminClient = SupabaseClient<any>;

interface ReponseAvecCorps {
  status: number;
  headers: Headers;
  buffer: Uint8Array;
}

async function fetchAvecCorpsEtTimeout(
  input: string,
  init: RequestInit,
  timeoutMs = 25_000,
): Promise<ReponseAvecCorps> {
  const controleur = new AbortController();
  const minuteur = setTimeout(() => controleur.abort(), timeoutMs);
  try {
    const response = await fetch(input, { ...init, signal: controleur.signal });
    if (response.status === 416) {
      if (response.body) await response.body.cancel().catch(() => undefined);
      return { status: response.status, headers: response.headers, buffer: new Uint8Array() };
    }
    // L'export officiel supporte Range. Accepter un 200 téléchargerait le
    // fichier national complet (plus de 800 Mo) dans une seule instance Edge.
    if (!response.ok || response.status !== 206) {
      if (response.body) await response.body.cancel().catch(() => undefined);
      throw new Error(`Téléchargement Annuaire Santé impossible (${response.status}, Range ignorée)`);
    }
    // Le minuteur reste actif pendant la lecture : fetch() peut résoudre dès
    // les en-têtes alors que le CDN coupe ensuite le corps de la tranche.
    const buffer = new Uint8Array(await response.arrayBuffer());
    return { status: response.status, headers: response.headers, buffer };
  } finally {
    clearTimeout(minuteur);
  }
}

async function majSource(
  admin: AdminClient,
  runId: string | null,
  valeurs: Record<string, unknown>,
): Promise<void> {
  try {
    if (runId) {
      const { data: runLePlusRecent, error: runLePlusRecentErr } = await admin
        .from("sourcing_imports")
        .select("id")
        .eq("source_code", SOURCE_CODE)
        .order("demarre_le", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (runLePlusRecentErr) {
        // Le suivi ne doit ni interrompre l'import, ni publier un statut
        // possiblement obsolète lorsque l'ordre des runs est inconnu.
        console.error("ordre runs RPPS:", runLePlusRecentErr.message);
        return;
      }
      if (!peutPublierStatutSource(runId, runLePlusRecent?.id ?? null)) return;
    }

    const { error } = await admin.from("acquisition_sources").update({
      actif: true,
      automatique: true,
      ...valeurs,
      maj_le: new Date().toISOString(),
    }).eq("code", SOURCE_CODE);
    if (error) console.error("acquisition_sources RPPS:", error.message);
  } catch (error) {
    // Le suivi du radar ne doit jamais interrompre l'import officiel lui-même.
    console.error("suivi acquisition_sources RPPS:", (error as Error).message);
  }
}

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
  let repriseSourceMajLe: string | null = null;
  let reprisesTimeout = 0;

  try {
    const body = await req.json().catch(() => ({}));
    const watchdog = body.watchdog === true;
    let offset = Number(body.offset) || 0;
    let luesAvant = Number(body.lignes_lues) || 0;
    let importeesAvant = Number(body.lignes_importees) || 0;
    let sourceMajAvant = typeof body.source_maj_le === "string" ? body.source_maj_le : null;
    repriseSourceMajLe = sourceMajAvant;
    reprisesTimeout = Number(body.reprises_timeout) || 0;
    runId = typeof body.run_id === "string" ? body.run_id : null;

    if (!runId) {
      const { data: actif, error: actifErr } = await admin.from("sourcing_imports")
        .select("id, demarre_le, details, lignes_lues, lignes_importees, source_maj_le")
        .eq("source_code", SOURCE_CODE)
        .eq("statut", "EN_COURS")
        .order("demarre_le", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (actifErr) throw new Error(actifErr.message);

      if (actif?.id) {
        const detailsActif = actif.details as Record<string, unknown> | null;
        const heartbeatBrut = typeof detailsActif?.heartbeat_le === "string"
          ? detailsActif.heartbeat_le
          : actif.demarre_le;
        const heartbeatMs = Date.parse(heartbeatBrut || "");
        const stale = !Number.isFinite(heartbeatMs) || Date.now() - heartbeatMs > HEARTBEAT_STALE_MS;

        if (!stale) {
          return jsonResponse(req, {
            success: true,
            already_running: true,
            run_id: actif.id,
            heartbeat_le: heartbeatBrut,
          });
        }

        // Une instance Edge peut être coupée entre deux auto-relances. Le
        // watchdog reprend alors le même run et le dernier curseur validé ; il
        // ne crée jamais un second import concurrent.
        if (detailsActif?.fichier === FICHIER) {
          runId = actif.id;
          offset = Number(detailsActif.next_offset) || 0;
          luesAvant = Number(actif.lignes_lues) || 0;
          importeesAvant = Number(actif.lignes_importees) || 0;
          reprisesTimeout = Number(detailsActif.reprise_timeout) || 0;
          sourceMajAvant = typeof detailsActif.source_maj_le === "string"
            ? detailsActif.source_maj_le
            : typeof actif.source_maj_le === "string"
            ? actif.source_maj_le
            : null;
          repriseSourceMajLe = sourceMajAvant;
        }
      }

      // Un clic/cron après une coupure réseau reprend la dernière exécution au
      // curseur validé, à condition qu'elle concerne exactement le même
      // fichier officiel. Il n'y a donc jamais besoin de rescanner 812 Mo.
      if (!runId) {
        const { data: interrompu, error: interrompuErr } = await admin.from("sourcing_imports")
          .select("id, details, lignes_lues, lignes_importees, source_maj_le, erreur")
          .eq("source_code", SOURCE_CODE)
          .eq("statut", "ERREUR")
          .gte("demarre_le", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
          .order("demarre_le", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (interrompuErr) throw new Error(interrompuErr.message);
        const detailsInterrompu = interrompu?.details as Record<string, unknown> | null;
        const erreurInterrompue = typeof interrompu?.erreur === "string" ? interrompu.erreur : "";

        // Un watchdog ne réessaie que les incidents transitoires ; un clic
        // admin peut toujours reprendre explicitement un run en erreur.
        if (
          interrompu?.id &&
          detailsInterrompu?.fichier === FICHIER &&
          (!watchdog || erreurRppsReprenable(erreurInterrompue))
        ) {
          runId = interrompu.id;
          offset = Number(detailsInterrompu.next_offset) || 0;
          luesAvant = Number(interrompu.lignes_lues) || 0;
          importeesAvant = Number(interrompu.lignes_importees) || 0;
          reprisesTimeout = Number(detailsInterrompu.reprise_timeout) || 0;
          sourceMajAvant = typeof detailsInterrompu.source_maj_le === "string"
            ? detailsInterrompu.source_maj_le
            : typeof interrompu.source_maj_le === "string"
            ? interrompu.source_maj_le
            : null;
          repriseSourceMajLe = sourceMajAvant;
        }
      }

      if (runId) {
        const heartbeatLe = new Date().toISOString();
        const { error: repriseErr } = await admin.from("sourcing_imports").update({
          statut: "EN_COURS",
          termine_le: null,
          erreur: null,
          details: {
            fichier: FICHIER,
            silencieux: true,
            contact_automatique: false,
            format: "PS_LibreAcces_Personne_activite",
            next_offset: offset,
            heartbeat_le: heartbeatLe,
            source_maj_le: sourceMajAvant,
            reprise_timeout: reprisesTimeout,
            reprise_watchdog: watchdog,
          },
        }).eq("id", runId);
        if (repriseErr) throw new Error(repriseErr.message);
      } else if (watchdog) {
        // Le watchdog assure uniquement la continuité d'un import existant.
        // Une source à jour/idle reste idle jusqu'au prochain lancement hebdo
        // ou manuel : aucun import national n'est créé toutes les cinq minutes.
        return jsonResponse(req, {
          success: true,
          idle: true,
          started: false,
          contacted: 0,
          contact_automatique: false,
        });
      } else {
        const heartbeatLe = new Date().toISOString();
        const { data: run, error: runErr } = await admin.from("sourcing_imports").insert({
          source_code: SOURCE_CODE,
          cible: "SOIGNANT",
          source_url: SOURCE_PAGE,
          details: {
            fichier: FICHIER,
            silencieux: true,
            contact_automatique: false,
            format: "PS_LibreAcces_Personne_activite",
            next_offset: 0,
            heartbeat_le: heartbeatLe,
          },
        }).select("id").single();
        if (runErr) throw new Error(runErr.message);
        runId = run.id;
      }
    }

    repriseOffset = offset;
    repriseLues = luesAvant;
    repriseImportees = importeesAvant;

    const heartbeatInitial = new Date().toISOString();
    const { error: heartbeatErr } = await admin.from("sourcing_imports").update({
      details: {
        fichier: FICHIER,
        silencieux: true,
        contact_automatique: false,
        format: "PS_LibreAcces_Personne_activite",
        next_offset: offset,
        heartbeat_le: heartbeatInitial,
        source_maj_le: sourceMajAvant,
        reprise_timeout: reprisesTimeout,
      },
    }).eq("id", runId);
    if (heartbeatErr) throw new Error(heartbeatErr.message);
    await majSource(admin, runId, {
      dernier_statut: "OK",
      dernier_message: `Import RPPS en cours — ${luesAvant} lignes lues, ${importeesAvant} ajoutees`,
    });

    const debut = Date.now();
    let pos = offset;
    let totalLues = 0;
    let totalImportees = 0;
    let done = false;
    let sourceMajLe: string | null = sourceMajAvant;
    let dernierHeartbeatMs = Date.now();

    while (Date.now() - debut < BUDGET_MS) {
      const { status, headers, buffer } = await fetchAvecCorpsEtTimeout(FICHIER, {
        headers: { Range: `bytes=${pos}-${pos + TRANCHE - 1}` },
      });
      if (status === 416) { done = true; break; }

      const lastModified = headers.get("last-modified");
      if (lastModified) sourceMajLe = new Date(lastModified).toISOString();
      repriseSourceMajLe = sourceMajLe;
      const texte = new TextDecoder("utf-8").decode(buffer);
      const finFichier = buffer.byteLength < TRANCHE;
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
      // Une tranche qui a expiré est rejouée avec des lots progressivement
      // divisés (25, 12, 6, 3, 1). Une ligne/index atypique ne peut ainsi plus
      // bloquer l'ensemble du référentiel national.
      const tailleUpsertEffective = Math.max(
        1,
        Math.floor(TAILLE_UPSERT / (2 ** reprisesTimeout)),
      );
      for (let i = 0; i < rows.length; i += tailleUpsertEffective) {
        const { data: upserts, error } = await admin.rpc("fn_sourcing_upsert_soignants", {
          p_rows: rows.slice(i, i + tailleUpsertEffective),
        });
        if (error) throw new Error(error.message);
        totalImportees += Number(upserts) || 0;

        // Une grosse tranche peut dépasser le budget nominal lorsque la base
        // est chargée. Le heartbeat garde alors le lease vivant sans avancer
        // le curseur tant que toute la tranche n'est pas validée.
        if (Date.now() - dernierHeartbeatMs >= 60_000) {
          const heartbeatLe = new Date().toISOString();
          const { error: heartbeatLongErr } = await admin.from("sourcing_imports").update({
            details: {
              fichier: FICHIER,
              silencieux: true,
              contact_automatique: false,
              format: "PS_LibreAcces_Personne_activite",
              next_offset: repriseOffset,
              heartbeat_le: heartbeatLe,
              source_maj_le: sourceMajLe,
              reprise_timeout: reprisesTimeout,
            },
          }).eq("id", runId);
          if (heartbeatLongErr) throw new Error(heartbeatLongErr.message);
          dernierHeartbeatMs = Date.now();
        }
      }

      // Le curseur ne progresse qu'une fois toute la tranche écrite. Si une
      // requête suivante expire, la reprise rejoue au plus cette tranche ; les
      // doublons sont ignorés par la fonction SQL idempotente.
      repriseOffset = pos;
      repriseLues = luesAvant + totalLues;
      repriseImportees = importeesAvant + totalImportees;
      reprisesTimeout = 0;
      const heartbeatLe = new Date().toISOString();
      const { error: progressionErr } = await admin.from("sourcing_imports").update({
        lignes_lues: repriseLues,
        lignes_importees: repriseImportees,
        details: {
          fichier: FICHIER,
          silencieux: true,
          contact_automatique: false,
          format: "PS_LibreAcces_Personne_activite",
          next_offset: repriseOffset,
          heartbeat_le: heartbeatLe,
          source_maj_le: sourceMajLe,
          reprise_timeout: 0,
        },
      }).eq("id", runId);
      if (progressionErr) throw new Error(progressionErr.message);
      dernierHeartbeatMs = Date.now();
      await majSource(admin, runId, {
        dernier_statut: "OK",
        dernier_message: `Import RPPS en cours — ${repriseLues} lignes lues, ${repriseImportees} ajoutees`,
      });
      if (finFichier) { done = true; break; }
    }

    const compteurs = {
      lignes_lues: luesAvant + totalLues,
      lignes_importees: importeesAvant + totalImportees,
    };
    const etatLe = new Date().toISOString();
    const { error: etatErr } = await admin.from("sourcing_imports").update({
      statut: done ? "TERMINE" : "EN_COURS",
      termine_le: done ? etatLe : null,
      source_maj_le: sourceMajLe,
      ...compteurs,
      details: {
        fichier: FICHIER,
        silencieux: true,
        contact_automatique: false,
        format: "PS_LibreAcces_Personne_activite",
        next_offset: pos,
        heartbeat_le: etatLe,
        source_maj_le: sourceMajLe,
        reprise_timeout: 0,
      },
    }).eq("id", runId);
    if (etatErr) throw new Error(etatErr.message);

    await majSource(admin, runId, done
      ? {
        dernier_import_le: etatLe,
        dernier_statut: "OK",
        dernier_message: `Import RPPS termine — ${compteurs.lignes_lues} lignes lues, ${compteurs.lignes_importees} ajoutees`,
      }
      : {
        dernier_statut: "OK",
        dernier_message: `Import RPPS en cours — ${compteurs.lignes_lues} lignes lues, ${compteurs.lignes_importees} ajoutees`,
      });

    if (!done) {
      const relance = fetch(`${url}/functions/v1/import-annuaire-rpps`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({
          offset: pos,
          run_id: runId,
          source_maj_le: sourceMajLe,
          reprises_timeout: 0,
          ...compteurs,
        }),
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
      contacted: 0,
      contact_automatique: false,
      ...compteurs,
    });
  } catch (error) {
    const message = (error as Error).message;
    if (runId && erreurRppsReprenable(message) && reprisesTimeout < MAX_REPRISES_TIMEOUT) {
      const prochainEssai = reprisesTimeout + 1;
      const heartbeatLe = new Date().toISOString();
      const { error: retryErr } = await admin.from("sourcing_imports").update({
        statut: "EN_COURS",
        termine_le: null,
        erreur: null,
        lignes_lues: repriseLues,
        lignes_importees: repriseImportees,
        details: {
          fichier: FICHIER,
          silencieux: true,
          contact_automatique: false,
          format: "PS_LibreAcces_Personne_activite",
          next_offset: repriseOffset,
          heartbeat_le: heartbeatLe,
          source_maj_le: repriseSourceMajLe,
          reprise_timeout: prochainEssai,
        },
      }).eq("id", runId);
      if (retryErr) console.error("heartbeat reprise RPPS:", retryErr.message);
      await majSource(admin, runId, {
        dernier_statut: "OK",
        dernier_message: `Import RPPS en reprise automatique (${prochainEssai}/${MAX_REPRISES_TIMEOUT})`,
      });

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
            source_maj_le: repriseSourceMajLe,
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
        contacted: 0,
        contact_automatique: false,
      }, 202);
    }

    if (runId) {
      const erreurLe = new Date().toISOString();
      await admin.from("sourcing_imports").update({
        statut: "ERREUR",
        termine_le: erreurLe,
        erreur: message.slice(0, 1000),
        lignes_lues: repriseLues,
        lignes_importees: repriseImportees,
        details: {
          fichier: FICHIER,
          silencieux: true,
          contact_automatique: false,
          format: "PS_LibreAcces_Personne_activite",
          next_offset: repriseOffset,
          heartbeat_le: erreurLe,
          source_maj_le: repriseSourceMajLe,
          reprise_timeout: reprisesTimeout,
        },
      }).eq("id", runId);
    }
    await majSource(admin, runId, {
      dernier_statut: "ERREUR",
      dernier_message: message.slice(0, 500),
    });
    return jsonResponse(req, {
      error: message,
      contacted: 0,
      contact_automatique: false,
    }, 500);
  }
});
