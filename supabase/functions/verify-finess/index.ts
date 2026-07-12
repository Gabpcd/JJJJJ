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

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
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
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);
  const ip = getClientIp(req);
  if (applyRateLimit('verify-finess', ip, { max: 10, windowMs: 60_000 })) {
    return jsonResponse(req, { ok: false, code: 'RATE_LIMITED', error: 'Trop de verifications.' }, 429);
  }

  try {
    const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);

    if (body?.warm === true) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return jsonResponse(req, { error: adminAuth.error }, adminAuth.status);
      return jsonResponse(req, { warm: true, configured: !!apiKey, endpoint: GATEWAY });
    }

    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    if (!serviceRoleKey || !supabaseUrl) return jsonResponse(req, { error: 'Service indisponible' }, 503);
    const authHeader = req.headers.get('Authorization') || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    const isServiceRole = token === serviceRoleKey;
    if (!isServiceRole) {
      const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
      const { data: allowed, error: rateError } = await admin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(ip === 'unknown'
          ? `unknown|${(req.headers.get('user-agent') || '').slice(0, 160)}`
          : ip),
        p_action: 'edge_verify_finess',
        p_max_tentatives: 30,
        p_fenetre_secondes: 600,
      });
      if (rateError) return jsonResponse(req, { error: 'Service temporairement indisponible' }, 503);
      if (allowed !== true) return jsonResponse(req, { code: 'RATE_LIMITED', error: 'Quota de verification atteint' }, 429);
    }

    const finess = String(body?.finess || '').replace(/\D/g, '').trim();
    if (!finess || finess.length !== 9) {
      return jsonResponse(req, { ok: false, error: 'FINESS invalide : 9 chiffres attendus.' }, 400);
    }

    // Dégradation gracieuse si la clé n'est pas configurée (vérif différée)
    if (!apiKey) {
      return jsonResponse(req, { ok: false, fhir_indisponible: true, source: 'Format FINESS valide - vérification ANS différée' });
    }

    let result: FinessResult;
    try {
      result = await queryFiness(finess, apiKey);
    } catch (e) {
      console.error('[verify-finess] Annuaire Sante indisponible', e instanceof Error ? e.message : String(e));
      return jsonResponse(req, { ok: false, fhir_indisponible: true, source: 'Annuaire Santé indisponible' });
    }

    if (!result.trouve) {
      return jsonResponse(req, { ok: true, trouve: false, message: 'FINESS introuvable dans l\'Annuaire Santé.' });
    }

    // Écriture finess_verifie : autorisée si l'appelant est
    //   (a) la service-role key (inscription, crons), OU
    //   (b) un membre PROPRIETAIRE/ADMIN_GROUPE de l'établissement (UI de vérification).
    // L'écriture s'appuie TOUJOURS sur le résultat FHIR vérifié server-side (result.actif),
    // jamais sur une affirmation du client.
    const etablissementId = body?.etablissement_id ? String(body.etablissement_id) : '';
    let ecrit = false;

    let autorise = false;
    if (token && serviceRoleKey && token === serviceRoleKey) {
      autorise = true; // service-role
    } else if (token && etablissementId) {
      // Vérifier l'appartenance via la service-role (le client n'a pas accès direct)
      try {
        const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data: { user } } = await userClient.auth.getUser();
        if (user) {
          const adminCheck = createClient(supabaseUrl, serviceRoleKey);
          const { data: membre } = await adminCheck.from('membres_etablissement')
            .select('role').eq('etablissement_id', etablissementId).eq('user_id', user.id)
            .eq('actif', true).maybeSingle();
          // Repli : un ADMIN_ETABLISSEMENT dont l'id == etablissement_id (compte legacy
          // sans ligne membres) est propriétaire de fait.
          autorise = (!!membre && ['PROPRIETAIRE', 'ADMIN_GROUPE'].includes((membre as Record<string, string>).role))
            || user.id === etablissementId;
        }
      } catch { /* non autorisé */ }
    }

    if (autorise && etablissementId && result.actif) {
      const admin = createClient(supabaseUrl, serviceRoleKey);
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

      // Réévaluer le rattachement adaptatif après mise à jour FINESS
      if (!error) {
        try { await admin.rpc('fn_evaluer_rattachement_etablissement', { p_etablissement_id: etablissementId }); } catch { /* non bloquant */ }
      }
    }

    return jsonResponse(req, {
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
    console.error('[verify-finess] erreur', e instanceof Error ? e.message : String(e));
    return jsonResponse(req, { ok: false, fhir_indisponible: true, source: 'Erreur appel FHIR' });
  }
});
