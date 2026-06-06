// verify-finess — Vérification FINESS établissement via l'API FHIR Annuaire Santé
// (ressource Organization). Même gateway / même clé ESANTE_FHIR_API_KEY que verify-rpps.
//
// Validé sur l'API réelle (AP-HP Pitié-Salpêtrière) :
//   - Système d'identifiant FINESS : https://finess.esante.gouv.fr (valeur = 9 chiffres).
//   - Organization (entité géographique) renvoie : name (raison sociale officielle),
//     active, address, type (catégorie TRE_R66 + secteur TRE_R02 + ESPIC), partOf (EJ).
//   - Aucun représentant nominatif (contact: []). Le FINESS confirme la STRUCTURE,
//     pas la personne (le rattachement personne se fait via INSEE dirigeants / email / admin).
//
// Auth : verify_jwt=false (registre public, appelé à l'inscription sans session, comme
// verify-rpps). Écriture finess_verifie UNIQUEMENT si appelé avec la service-role key.

import { createClient } from 'npm:@supabase/supabase-js@2';

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') || '';
  const allowed =
    origin === 'https://jolene.app' || origin === 'https://app.jolene.app' ||
    origin === 'https://www.jolene.app' || origin === 'http://localhost:5173' ||
    origin === 'http://localhost:8080';
  return {
    'Access-Control-Allow-Origin': allowed ? origin : 'https://jolene.app',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

async function fetchWithTimeout(url: string, init: RequestInit, ms: number): Promise<Response> {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(t);
  }
}

const GATEWAY = 'https://gateway.api.esante.gouv.fr/fhir/v2/Organization';
const FINESS_SYSTEM = 'https://finess.esante.gouv.fr';
const SYS_SECTEUR = 'TRE_R02-SecteurActivite';
const SYS_CATEGORIE = 'TRE_R66-CategorieEtablissement';

interface FinessResult {
  trouve: boolean;
  raison_sociale?: string | null;
  actif?: boolean;
  adresse?: { ligne?: string; ville?: string; cp?: string } | null;
  categorie_code?: string | null;
  categorie_label?: string | null;
  secteur_code?: string | null;
  secteur_label?: string | null;
  est_public?: boolean;
  ej_reference?: string | null;
}

async function queryFiness(finess: string, apiKey: string): Promise<FinessResult> {
  // Recherche par identifier système+valeur (précis). FHIR accepte aussi la valeur seule.
  const identifier = `${FINESS_SYSTEM}|${finess}`;
  const url = `${GATEWAY}?identifier=${encodeURIComponent(identifier)}`;
  const r = await fetchWithTimeout(url, {
    headers: { 'Accept': 'application/fhir+json', 'ESANTE-API-KEY': apiKey },
  }, 9000);
  if (!r.ok) {
    const body = await r.text();
    throw new Error(`Annuaire Sante indisponible (HTTP ${r.status}): ${body.slice(0, 200)}`);
  }
  const bundle = await r.json();
  if (!bundle.entry || bundle.entry.length === 0) return { trouve: false };
  const org = bundle.entry[0].resource;

  const adresse = org.address?.[0]
    ? { ligne: (org.address[0].line || []).join(' '), ville: org.address[0].city, cp: org.address[0].postalCode }
    : null;

  let categorie_code: string | null = null, categorie_label: string | null = null;
  let secteur_code: string | null = null, secteur_label: string | null = null;
  for (const t of org.type || []) {
    for (const c of t.coding || []) {
      const sys = String(c.system || '');
      if (sys.includes(SYS_CATEGORIE) && !categorie_code) { categorie_code = c.code; categorie_label = c.display; }
      if (sys.includes(SYS_SECTEUR) && !secteur_code) { secteur_code = c.code; secteur_label = c.display; }
    }
  }
  const est_public = secteur_code === 'SA01' || /public/i.test(secteur_label || '');

  return {
    trouve: true,
    raison_sociale: org.name || null,
    actif: org.active !== false,
    adresse,
    categorie_code, categorie_label,
    secteur_code, secteur_label,
    est_public,
    ej_reference: org.partOf?.reference || null,
  };
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  try {
    const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
    const body = await req.json().catch(() => ({}));

    if (body?.warm === true) {
      return json(200, { warm: true, configured: !!apiKey, endpoint: GATEWAY });
    }

    const finess = String(body?.finess || '').replace(/\D/g, '').trim();
    if (!finess || finess.length !== 9) {
      return json(400, { ok: false, error: 'FINESS invalide : 9 chiffres attendus.' });
    }

    // Dégradation gracieuse si la clé n'est pas configurée (vérif différée)
    if (!apiKey) {
      return json(200, { ok: false, fhir_indisponible: true, source: 'Format FINESS valide - vérification ANS différée' });
    }

    let result: FinessResult;
    try {
      result = await queryFiness(finess, apiKey);
    } catch (e) {
      return json(200, { ok: false, fhir_indisponible: true, source: 'Annuaire Santé indisponible', detail: String(e).slice(0, 200) });
    }

    if (!result.trouve) {
      return json(200, { ok: true, trouve: false, message: 'FINESS introuvable dans l\'Annuaire Santé.' });
    }

    // Écriture finess_verifie : uniquement appel service-role + etablissement_id fourni.
    const authHeader = req.headers.get('Authorization') || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const etablissementId = body?.etablissement_id ? String(body.etablissement_id) : '';
    let ecrit = false;
    if (token && serviceRoleKey && token === serviceRoleKey && etablissementId && result.actif) {
      const admin = createClient(Deno.env.get('SUPABASE_URL')!, serviceRoleKey);
      const { error } = await admin.from('etablissements').update({
        finess: finess,
        finess_verifie: true,
        finess_verifie_le: new Date().toISOString(),
        finess_raison_sociale: result.raison_sociale,
        finess_categorie: result.categorie_label,
        finess_secteur: result.secteur_label,
        finess_est_public: result.est_public ?? null,
      } as Record<string, unknown>).eq('id', etablissementId);
      ecrit = !error;
    }

    return json(200, {
      ok: true,
      trouve: true,
      finess,
      verifie: result.actif === true,
      ecrit,
      raison_sociale: result.raison_sociale,
      actif: result.actif,
      adresse: result.adresse,
      categorie: result.categorie_label,
      secteur: result.secteur_label,
      est_public: result.est_public,
      source: 'FHIR Annuaire Santé v2 (Organization)',
    });
  } catch (e) {
    return json(200, { ok: false, fhir_indisponible: true, source: 'Erreur appel FHIR', detail: String(e).slice(0, 200) });
  }
});
