// Enrichissement emails + téléphones des prospects depuis l'Annuaire Santé
// (API FHIR ANS, clé ESANTE_FHIR_API_KEY déjà configurée — même API que
// verify-rpps). Étabs : Organization par FINESS exact et unique. Soignants :
// Practitioner par RPPS exact — on n'enrichit QUE si le match est non ambigu,
// jamais de donnée rapprochée au seul nom. email/telephone remplis
// UNIQUEMENT s'ils sont vides (une saisie manuelle n'est jamais écrasée).
// enrichi_le posé dans tous les cas pour avancer par tranches relançables.
// Réservé ADMIN_PLATEFORME.

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const FHIR_BASE = "https://gateway.api.esante.gouv.fr/fhir/v2";
const IDNPS_SYSTEM = "urn:oid:1.2.250.1.71.4.2.1";
// L'API FHIR v2.1 publie le système FINESS en HTTPS. Le profil historique de
// l'Annuaire Santé utilisait la même URI en HTTP : ce sont les deux seules
// formes admises, sans détection partielle du namespace.
const SYSTEMES_FINESS_ACCEPTES = new Set([
  "https://finess.esante.gouv.fr",
  "http://finess.esante.gouv.fr",
]);

interface Telecoms { email: string | null; telephone: string | null }

interface ProspectAEnrichir {
  identifiant: string;
  finess?: string | null;
  cle?: string | null;
  nom?: string | null;
  prenom?: string | null;
  numero_rpps?: string | null;
  email?: string | null;
  telephone?: string | null;
}

interface ResultatEnrichissement {
  identifiant: string;
  email: string | null;
  telephone: string | null;
  termine: boolean;
}

interface ReponseFhir {
  exploitable: boolean;
  bundle: Record<string, unknown> | null;
}

interface IdentifiantFhir {
  system?: string | null;
  value?: string | null;
}

interface OrganisationFhir {
  resourceType?: string | null;
  identifier?: IdentifiantFhir[];
  telecom?: any[];
  contact?: Array<{ telecom?: any[] }>;
}

interface PraticienFhir {
  resourceType?: string | null;
  id?: string | null;
  identifier?: IdentifiantFhir[];
  telecom?: any[];
}

function champEstVide(value: unknown): boolean {
  return value == null || String(value).trim() === "";
}

function estIdentifiantFinessExact(
  identifiant: IdentifiantFhir,
  finess: string,
): boolean {
  const systeme = String(identifiant?.system ?? "").trim();
  const valeur = String(identifiant?.value ?? "").trim();
  return SYSTEMES_FINESS_ACCEPTES.has(systeme) && valeur === finess;
}

function organisationsFinessExactes(
  bundle: Record<string, unknown> | null,
  finess: string,
): OrganisationFhir[] {
  const entries = Array.isArray(bundle?.entry) ? bundle.entry : [];
  return (entries as Array<{ resource?: OrganisationFhir }>)
    .map((entry) => entry?.resource)
    .filter((resource): resource is OrganisationFhir =>
      resource?.resourceType === "Organization"
      && (resource.identifier ?? []).some((identifiant) =>
        estIdentifiantFinessExact(identifiant, finess)
      )
    );
}

function praticiensRppsExacts(
  bundle: Record<string, unknown> | null,
  rpps: string,
): PraticienFhir[] {
  const valeurAttendue = `8${rpps}`;
  const entries = Array.isArray(bundle?.entry) ? bundle.entry : [];
  return (entries as Array<{ resource?: PraticienFhir }>)
    .map((entry) => entry?.resource)
    .filter((resource): resource is PraticienFhir =>
      resource?.resourceType === "Practitioner"
      && (resource.identifier ?? []).some((identifiant) =>
        String(identifiant?.system ?? "").trim().replace(/\/$/, "").toLowerCase() === IDNPS_SYSTEM
        && String(identifiant?.value ?? "").trim() === valeurAttendue
      )
    );
}

/** Extrait le premier email et téléphone d'une liste telecom FHIR. */
function extraireTelecom(telecom: any[] | undefined, acc: Telecoms): Telecoms {
  for (const t of telecom ?? []) {
    const v = String(t?.value ?? "").trim();
    if (!v) continue;
    if (!acc.email && t.system === "email" && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) acc.email = v.toLowerCase();
    if (!acc.telephone && (t.system === "phone" || t.system === "sms")) {
      const telephone = v.replace(/[^\d+]/g, "");
      if (telephone.replace(/\D/g, "").length >= 9) acc.telephone = telephone;
    }
  }
  return acc;
}

async function fhir(path: string, apiKey: string): Promise<ReponseFhir> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const r = await fetch(`${FHIR_BASE}${path}`, {
      headers: { "Accept": "application/fhir+json", "ESANTE-API-KEY": apiKey },
      signal: ctrl.signal,
    });
    if (!r.ok) return { exploitable: false, bundle: null };
    const payload = await r.json();
    if (!payload || typeof payload !== "object" || payload.resourceType !== "Bundle") {
      return { exploitable: false, bundle: null };
    }
    return { exploitable: true, bundle: payload as Record<string, unknown> };
  } catch {
    // Une panne, un timeout ou une reponse illisible ne doit jamais marquer le
    // prospect comme enrichi : la RPC de terminaison liberera sa reclamation.
    return { exploitable: false, bundle: null };
  } finally {
    clearTimeout(timer);
  }
}

/** Execute au plus `concurrence` enrichissements simultanement. */
async function avecConcurrenceBornee<T, R>(
  elements: T[],
  concurrence: number,
  traiter: (element: T) => Promise<R>,
): Promise<R[]> {
  const resultats = new Array<R>(elements.length);
  let prochain = 0;

  async function worker(): Promise<void> {
    while (true) {
      const index = prochain++;
      if (index >= elements.length) return;
      resultats[index] = await traiter(elements[index]);
    }
  }

  const workers = Array.from(
    { length: Math.min(Math.max(concurrence, 1), elements.length) },
    () => worker(),
  );
  await Promise.all(workers);
  return resultats;
}

async function enrichirProspect(
  prospect: ProspectAEnrichir,
  cible: "ETABLISSEMENT" | "SOIGNANT",
  apiKey: string,
): Promise<{ resultat: ResultatEnrichissement; ambigu: boolean }> {
  const acc: Telecoms = { email: null, telephone: null };
  let termine = true;
  let ambigu = false;

  try {
    if (cible === "ETABLISSEMENT") {
      const finess = String(prospect.finess ?? prospect.identifiant ?? "").trim();
      if (/^\d{9}$/.test(finess)) {
        // La recherche FHIR par valeur retourne les différents systèmes qui
        // portent cette valeur. Le filtre client strict ci-dessous n'accepte
        // que les namespaces FINESS officiels et la valeur à 9 chiffres exacte.
        const reponse = await fhir(`/Organization?identifier=${encodeURIComponent(finess)}`, apiKey);
        termine = reponse.exploitable;
        if (reponse.exploitable) {
          const correspondances = organisationsFinessExactes(reponse.bundle, finess);
          if (correspondances.length === 1) {
            // Ne jamais fusionner plusieurs Organization : les coordonnées ne
            // sont copiées que depuis l'unique ressource prouvée par le FINESS.
            const organisation = correspondances[0];
            extraireTelecom(organisation.telecom, acc);
            for (const contact of organisation.contact ?? []) {
              extraireTelecom(contact?.telecom, acc);
              if (acc.email && acc.telephone) break;
            }
          } else if (correspondances.length > 1) {
            ambigu = true;
          }
        }
      }
    } else {
      const rppsBrut = String(prospect.numero_rpps ?? "").trim();
      const rpps = /^8\d{11}$/.test(rppsBrut) ? rppsBrut.slice(1) : rppsBrut;
      if (/^\d{11}$/.test(rpps)) {
        // L'identifiant national d'un professionnel est exposé dans IDNPS sous
        // la forme typeIdNat(8) + RPPS. La requête ET le filtre local imposent
        // le namespace canonique afin d'écarter tout autre identifiant égal.
        const identifiantRpps = `${IDNPS_SYSTEM}|8${rpps}`;
        const reponse = await fhir(
          `/Practitioner?identifier=${encodeURIComponent(identifiantRpps)}`,
          apiKey,
        );
        termine = reponse.exploitable;

        if (reponse.exploitable) {
          const correspondances = praticiensRppsExacts(reponse.bundle, rpps);

          if (correspondances.length === 1) {
            const praticien = correspondances[0];
            extraireTelecom(praticien?.telecom, acc);

            if ((!acc.email || !acc.telephone) && praticien?.id) {
              const roles = await fhir(
                `/PractitionerRole?practitioner=${encodeURIComponent(praticien.id)}`,
                apiKey,
              );
              if (!roles.exploitable) {
                termine = false;
              } else {
                const roleEntries = Array.isArray(roles.bundle?.entry) ? roles.bundle.entry : [];
                for (const entry of roleEntries as any[]) {
                  extraireTelecom(entry?.resource?.telecom, acc);
                  if (acc.email && acc.telephone) break;
                }
              }
            }
          } else if (correspondances.length > 1) {
            ambigu = true;
          }
        }
      } else {
        // Sans identifiant national, un homonyme unique dans une réponse ne
        // constitue pas une preuve d'identité suffisante pour copier ses
        // coordonnées professionnelles.
        termine = true;
      }
    }
  } catch {
    // Protection supplementaire : une anomalie sur un prospect ne bloque pas
    // le lot et laisse ce prospect reessayable.
    termine = false;
  }

  return {
    resultat: {
      identifiant: String(prospect.identifiant),
      // Envoyer uniquement les nouvelles valeurs. La RPC utilise en plus
      // COALESCE pour qu'une saisie manuelle concurrente reste prioritaire.
      email: acc.email && champEstVide(prospect.email) ? acc.email : null,
      telephone: acc.telephone && champEstVide(prospect.telephone) ? acc.telephone : null,
      termine,
    },
    ambigu,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    // Auth standard : JWT admin OU service_role/sb_secret_* (fallback vault
    // géré par le helper — piège pg_cron documenté CLAUDE.md)
    const authResult = await verifyAdminOrServiceRole(req);
    if (!authResult.ok) {
      return new Response(JSON.stringify({ error: authResult.error }), { status: authResult.status, headers: corsHeaders(req) });
    }
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const apiKey = Deno.env.get("ESANTE_FHIR_API_KEY") || "";
    if (!apiKey) return new Response(JSON.stringify({ error: "ESANTE_FHIR_API_KEY non configurée." }), { status: 500, headers: corsHeaders(req) });

    const { cible, departement, limite } = await req.json().catch(() => ({}));
    if (!["ETABLISSEMENT", "SOIGNANT"].includes(cible)) {
      return new Response(JSON.stringify({ error: "cible invalide (ETABLISSEMENT|SOIGNANT)" }), { status: 400, headers: corsHeaders(req) });
    }
    const max = Math.min(Math.max(Math.floor(Number(limite) || 40), 1), 60);

    // La reclamation est atomique cote Postgres (SKIP LOCKED + bail). Deux
    // executions cron/manuelles ne peuvent donc plus traiter les memes lignes.
    const { data: candidats, error: reclamationErreur } = await admin.rpc(
      "fn_reclamer_prospects_enrichissement",
      {
        p_cible: cible,
        p_departement: departement ? String(departement).toUpperCase() : null,
        p_limite: max,
      },
    );
    if (reclamationErreur) {
      return new Response(JSON.stringify({ error: reclamationErreur.message }), { status: 500, headers: corsHeaders(req) });
    }

    const prospects = Array.isArray(candidats) ? candidats as ProspectAEnrichir[] : [];
    if (!prospects.length) {
      return new Response(JSON.stringify({ success: true, traites: 0, emails: 0, telephones: 0, restants: 0, message: "Tous les prospects ont déjà été passés à l'Annuaire." }), { headers: corsHeaders(req) });
    }

    const enrichissements = await avecConcurrenceBornee(
      prospects,
      6,
      (prospect) => enrichirProspect(prospect, cible as "ETABLISSEMENT" | "SOIGNANT", apiKey),
    );
    const resultats = enrichissements.map(({ resultat }) => resultat);
    const ambigus = enrichissements.filter(({ ambigu }) => ambigu).length;

    // Une seule ecriture en lot remplace les PATCH PostgREST ligne par ligne.
    // Les resultats `termine=false` liberent leur reclamation sans enrichi_le.
    const { data: bilan, error: terminaisonErreur } = await admin.rpc(
      "fn_terminer_prospects_enrichissement",
      { p_cible: cible, p_resultats: resultats },
    );
    if (terminaisonErreur) {
      return new Response(JSON.stringify({ error: terminaisonErreur.message }), { status: 500, headers: corsHeaders(req) });
    }

    const stats = bilan && typeof bilan === "object" ? bilan as Record<string, unknown> : {};
    const traites = Number(stats.traites ?? resultats.filter((r) => r.termine).length);
    const emails = Number(stats.emails ?? resultats.filter((r) => Boolean(r.email)).length);
    const telephones = Number(stats.telephones ?? resultats.filter((r) => Boolean(r.telephone)).length);

    // Ne jamais lancer un count exact de toute la file ici : la table RPPS
    // dépasse le million de lignes et ce comptage répété saturait PostgREST.
    // Une tranche pleine suffit à signaler qu'une autre passe est probablement
    // utile ; la passe suivante conclura proprement avec traites=0 si nécessaire.
    const resteATraiter = prospects.length === max;
    return new Response(JSON.stringify({
      success: true,
      traites,
      emails,
      telephones,
      ambigus,
      restants: null,
      reste_a_traiter: resteATraiter,
      mode_silencieux: true,
    }), { headers: corsHeaders(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});
