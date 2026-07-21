// Radar de demande Jolene — import silencieux des offres actives France Travail.
//
// Cette fonction ne contacte ni les employeurs ni les soignants. Elle ne cree
// que des signaux internes visibles par l'admin. L'API France Travail requiert
// une habilitation et deux secrets Edge : FRANCE_TRAVAIL_CLIENT_ID et
// FRANCE_TRAVAIL_CLIENT_SECRET.

import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";

const SOURCE_CODE = "FRANCE_TRAVAIL_OFFRES";
const SOURCE_PAGE = "https://www.data.gouv.fr/dataservices/api-offres-demploi";
const TOKEN_URL = "https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=/partenaire";
const SEARCH_URL = "https://api.francetravail.io/partenaire/offresdemploi/v2/offres/search";
const SCOPE = "api_offresdemploiv2 o2dsoffre";
const RANGE = "0-149";

const RECHERCHES = [
  "infirmier",
  "aide soignant",
  "auxiliaire puericulture",
  "accompagnant educatif social",
  "sage femme",
  "kinesitherapeute",
  "manipulateur radiologie",
  "preparateur pharmacie",
  "ergotherapeute",
  "psychomotricien",
  "orthophoniste",
  "dieteticien",
] as const;

type FranceTravailOffer = {
  id?: string;
  intitule?: string;
  description?: string;
  dateCreation?: string;
  dateActualisation?: string;
  nombrePostes?: number;
  typeContrat?: string;
  typeContratLibelle?: string;
  romeLibelle?: string;
  appellationlibelle?: string;
  lieuTravail?: {
    libelle?: string;
    codePostal?: string;
    commune?: string;
  };
  entreprise?: {
    nom?: string;
    siret?: string;
    entrepriseAdaptee?: boolean;
  };
  origineOffre?: {
    urlOrigine?: string;
    origine?: string;
  };
};

function normaliser(value: string | null | undefined): string {
  return (value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function mapperProfession(offre: FranceTravailOffer): string | null {
  const texte = normaliser([
    offre.intitule,
    offre.romeLibelle,
    offre.appellationlibelle,
  ].filter(Boolean).join(" "));

  if (/infirmier.*anesthes|iade/.test(texte)) return "IADE";
  if (/bloc operatoire|ibode/.test(texte)) return "IBODE";
  if (/auxiliaire.*puericulture/.test(texte)) return "AUXILIAIRE_PUERICULTURE";
  if (/aide.*soignant/.test(texte)) return "AS";
  if (/accompagnant.*educatif.*social|\baes\b/.test(texte)) return "AES";
  if (/sage.*femme/.test(texte)) return "SAGE_FEMME";
  if (/masseur.*kinesitherapeute|kinesitherapeute/.test(texte)) return "KINE";
  if (/manipulateur.*(radio|electroradiologie)/.test(texte)) return "MANIPULATEUR_RADIO";
  if (/preparateur.*pharmacie/.test(texte)) return "PREPARATEUR_PHARMA";
  if (/pharmacien/.test(texte)) return "PHARMACIEN";
  if (/ergotherapeute/.test(texte)) return "ERGOTHERAPEUTE";
  if (/psychomotricien/.test(texte)) return "PSYCHOMOTRICIEN";
  if (/orthophoniste/.test(texte)) return "ORTHOPHONISTE";
  if (/dieteticien/.test(texte)) return "DIETETICIEN";
  if (/chirurgien.*dentiste|dentiste/.test(texte)) return "DENTISTE";
  if (/\bmedecin\b/.test(texte)) return "MEDECIN";
  if (/\binfirmier/.test(texte)) return "IDE";
  return null;
}

function departementDepuisCodePostal(codePostal: string | null | undefined): string | null {
  const cp = (codePostal || "").replace(/\D/g, "");
  if (!/^\d{5}$/.test(cp)) return null;
  return cp.startsWith("97") || cp.startsWith("98") ? cp.slice(0, 3) : cp.slice(0, 2);
}

function scoreDemande(offre: FranceTravailOffer): number {
  const contrat = normaliser(`${offre.typeContrat || ""} ${offre.typeContratLibelle || ""}`);
  const date = new Date(offre.dateActualisation || offre.dateCreation || 0).getTime();
  const ageJours = Number.isFinite(date) ? Math.max(0, (Date.now() - date) / 86_400_000) : 999;
  const postes = Math.max(1, Number(offre.nombrePostes) || 1);
  const contratCourt = /cdd|interim|temporaire|saisonnier/.test(contrat);
  return Math.min(100, Math.round(
    45
    + (ageJours <= 7 ? 20 : ageJours <= 30 ? 10 : 0)
    + (contratCourt ? 15 : 0)
    + Math.min(postes - 1, 10) * 2,
  ));
}

export function mapperOffre(offre: FranceTravailOffer) {
  const profession = mapperProfession(offre);
  const id = (offre.id || "").trim();
  const intitule = (offre.intitule || "").trim();
  const nom = (offre.entreprise?.nom || "Employeur non communique").trim();
  if (!id || !intitule || !profession) return null;

  const siret = (offre.entreprise?.siret || "").replace(/\D/g, "");
  return {
    source_code: SOURCE_CODE,
    source_id: id,
    source_url: offre.origineOffre?.urlOrigine
      || `https://candidat.francetravail.fr/offres/recherche/detail/${encodeURIComponent(id)}`,
    finess: null,
    siret: /^\d{14}$/.test(siret) ? siret : null,
    nom_etablissement: nom,
    intitule,
    profession,
    departement: departementDepuisCodePostal(offre.lieuTravail?.codePostal),
    ville: offre.lieuTravail?.libelle || null,
    type_contrat: offre.typeContratLibelle || offre.typeContrat || null,
    publie_le: offre.dateCreation || null,
    expire_le: null,
    volume_estime: Math.max(1, Number(offre.nombrePostes) || 1),
    score_demande: scoreDemande(offre),
    details: {
      date_actualisation: offre.dateActualisation || null,
      code_postal: offre.lieuTravail?.codePostal || null,
      commune: offre.lieuTravail?.commune || null,
      rome: offre.romeLibelle || null,
      origine: offre.origineOffre?.origine || "France Travail",
      silencieux: true,
      contact_automatique: false,
    },
  };
}

async function obtenirJeton(clientId: string, clientSecret: string): Promise<string> {
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
    scope: SCOPE,
  });
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new Error(`Authentification France Travail impossible (${response.status})`);
  }
  return payload.access_token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") return jsonResponse(req, { error: "Methode non autorisee" }, 405);

  let runId: string | null = null;
  const admin = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
    { auth: { persistSession: false } },
  );

  try {
    const auth = await verifyAdminOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

    const clientId = Deno.env.get("FRANCE_TRAVAIL_CLIENT_ID") || "";
    const clientSecret = Deno.env.get("FRANCE_TRAVAIL_CLIENT_SECRET") || "";
    if (!clientId || !clientSecret) {
      await admin.from("acquisition_sources").update({
        actif: false,
        dernier_statut: "NON_CONFIGURE",
        dernier_message: "Habilitation ou secrets France Travail manquants",
        maj_le: new Date().toISOString(),
      }).eq("code", SOURCE_CODE);
      return jsonResponse(req, {
        success: false,
        configured: false,
        imported: 0,
        contacted: 0,
        error: "Configurer FRANCE_TRAVAIL_CLIENT_ID et FRANCE_TRAVAIL_CLIENT_SECRET",
      }, 424);
    }

    const { data: run, error: runError } = await admin.from("sourcing_imports").insert({
      source_code: SOURCE_CODE,
      cible: "ETABLISSEMENT",
      statut: "EN_COURS",
      source_url: SOURCE_PAGE,
      details: { silencieux: true, contact_automatique: false, recherches: RECHERCHES },
    }).select("id").single();
    if (runError) throw new Error(runError.message);
    runId = run.id;

    const jeton = await obtenirJeton(clientId, clientSecret);
    const offres = new Map<string, FranceTravailOffer>();
    let lues = 0;

    for (const motsCles of RECHERCHES) {
      const url = new URL(SEARCH_URL);
      url.searchParams.set("motsCles", motsCles);
      url.searchParams.set("range", RANGE);
      url.searchParams.set("sort", "1");
      const response = await fetch(url, {
        headers: {
          Authorization: `Bearer ${jeton}`,
          Accept: "application/json",
        },
      });
      if (response.status === 204) continue;
      if (!response.ok) throw new Error(`Recherche France Travail impossible (${response.status}) pour ${motsCles}`);
      const payload = await response.json().catch(() => ({}));
      const resultats = Array.isArray(payload.resultats) ? payload.resultats as FranceTravailOffer[] : [];
      lues += resultats.length;
      for (const offre of resultats) {
        if (offre.id) offres.set(offre.id, offre);
      }
      // Sous la limite officielle de 10 appels/s et sans auto-relance recursive.
      await new Promise((resolve) => setTimeout(resolve, 125));
    }

    const rows = [...offres.values()].map(mapperOffre).filter((row) => row !== null);
    let imported = 0;
    for (let i = 0; i < rows.length; i += 100) {
      const { data, error } = await admin.rpc("fn_acquisition_upsert_signaux", {
        p_rows: rows.slice(i, i + 100),
      });
      if (error) throw new Error(error.message);
      imported += Number(data) || 0;
    }

    const now = new Date().toISOString();
    await Promise.all([
      admin.from("sourcing_imports").update({
        statut: "TERMINE",
        termine_le: now,
        lignes_lues: lues,
        lignes_importees: imported,
      }).eq("id", runId),
      admin.from("acquisition_sources").update({
        actif: true,
        automatique: true,
        dernier_import_le: now,
        dernier_statut: "OK",
        dernier_message: `${imported} signaux rapproches`,
        maj_le: now,
      }).eq("code", SOURCE_CODE),
    ]);

    return jsonResponse(req, {
      success: true,
      configured: true,
      read: lues,
      imported,
      contacted: 0,
      contact_automatique: false,
    });
  } catch (error) {
    const message = (error as Error)?.message || "Erreur inconnue";
    if (runId) {
      await admin.from("sourcing_imports").update({
        statut: "ERREUR",
        termine_le: new Date().toISOString(),
        erreur: message.slice(0, 1000),
      }).eq("id", runId);
    }
    await admin.from("acquisition_sources").update({
      dernier_statut: "ERREUR",
      dernier_message: message.slice(0, 500),
      maj_le: new Date().toISOString(),
    }).eq("code", SOURCE_CODE);
    return jsonResponse(req, { error: message, imported: 0, contacted: 0 }, 500);
  }
});
