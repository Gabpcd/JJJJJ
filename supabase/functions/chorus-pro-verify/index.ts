/**
 * chorus-pro-verify — Vérifie une structure + ses services via l'API Chorus Pro.
 *
 * Actions :
 * - { identifiant }                → vérifie que la structure existe
 * - { identifiant, detail: true }  → + paramétrage (code service obligatoire ?)
 * - { identifiant, services: true } → + liste des codes service disponibles
 * - { identifiant, code_service }  → vérifie qu'un code service précis est valide
 *
 * Auth : JWT authenticated (admin ou établissement).
 *
 * Diagnostic : chaque réponse porte un objet `diagnostic` (env PISTE, OAuth ok,
 * code HTTP Chorus) pour distinguer « SIRET réellement introuvable » (HTTP 200,
 * liste vide) d'« erreur d'habilitation/scope PISTE » (HTTP 401/403). Sans ça,
 * les deux cas s'affichaient identiquement « introuvable » et masquaient la vraie
 * cause.
 */

import {
  getPisteConfig, getAccessToken,
  rechercherStructure, consulterStructure, rechercherServicesStructure, consulterService,
} from '../_shared/piste-client.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': req.headers.get('origin') || '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Content-Type': 'application/json',
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  const headers = corsHeaders(req);

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Non authentifié' }), { status: 401, headers });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } },
    );
    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Session invalide' }), { status: 401, headers });
    }
    const role = user.app_metadata?.role;
    if (role !== 'ADMIN_PLATEFORME' && role !== 'ADMIN_ETABLISSEMENT') {
      return new Response(JSON.stringify({ error: 'Accès réservé admin / établissement' }), { status: 403, headers });
    }

    const body = await req.json().catch(() => ({}));
    // Normalisation : Chorus attend un identifiant SANS espaces ni séparateurs
    // (SIRET = 14 chiffres collés). Un SIRET collé/saisi avec des espaces
    // ("818 613 663 00017") était envoyé tel quel et toujours "introuvable".
    const identifiant = (body.identifiant?.toString() ?? '').replace(/[\s.\-]/g, '').trim();
    if (!identifiant) {
      return new Response(JSON.stringify({ error: 'identifiant requis' }), { status: 400, headers });
    }

    const config = getPisteConfig();
    if (!config) {
      return new Response(JSON.stringify({
        found: false,
        error: 'Credentials PISTE non configurés côté serveur — vérification impossible.',
        simulation: true,
      }), { status: 200, headers });
    }

    const diagnostic: Record<string, unknown> = { env: config.env, oauth_ok: false };

    // OAuth PISTE — isolé pour distinguer un échec d'authentification d'un
    // simple "structure introuvable".
    let token: string;
    try {
      token = await getAccessToken(config);
      diagnostic.oauth_ok = true;
    } catch (oauthErr) {
      return new Response(JSON.stringify({
        found: false,
        apiError: true,
        error: `Connexion à PISTE (OAuth) échouée : ${oauthErr instanceof Error ? oauthErr.message : 'erreur inconnue'}. Vérifiez les identifiants/scopes PISTE.`,
        diagnostic,
      }), { status: 200, headers });
    }

    // Action 1 : vérifier que la structure existe
    const searchResult = await rechercherStructure(config, token, identifiant);
    diagnostic.piste_http_status = searchResult.status;

    if (!searchResult.ok) {
      // Chorus a répondu mais avec une erreur HTTP (401/403 = habilitation/scope,
      // 400 = format, 5xx = indispo). Ce N'EST PAS un "introuvable".
      const hint = searchResult.status === 401 || searchResult.status === 403
        ? "L'application PISTE n'est pas (encore) habilitée pour « rechercherStructure » sur cet environnement."
        : searchResult.status === 400
          ? 'Requête refusée par Chorus Pro (format identifiant).'
          : 'Service Chorus Pro momentanément indisponible.';
      return new Response(JSON.stringify({
        found: false,
        apiError: true,
        error: `La recherche Chorus Pro a échoué (HTTP ${searchResult.status}). ${hint}`,
        diagnostic,
      }), { status: 200, headers });
    }

    if (!searchResult.found) {
      // HTTP 200 + liste vide = la structure n'existe vraiment pas sur Chorus Pro
      // (rappel : seuls les acheteurs du secteur public y sont enregistrés).
      return new Response(JSON.stringify({
        found: false,
        error: `Structure « ${identifiant} » introuvable sur Chorus Pro. Rappel : seuls les organismes du secteur public y sont enregistrés (le n° attendu est celui du client public facturé).`,
        diagnostic,
      }), { status: 200, headers });
    }

    const s = searchResult.structure;
    const result: any = {
      found: true,
      diagnostic,
      structure: {
        designationStructure: s?.designationStructure,
        identifiantStructure: s?.identifiantStructure,
        siret: s?.siret,
        adresse: s?.adressePostale,
        typeIdentifiant: s?.typeIdentifiantStructure,
        actif: s?.structureActive,
      },
    };

    // Action 2 : paramétrage détaillé (code service obligatoire ?)
    if (body.detail) {
      try {
        const detail = await consulterStructure(config, token, identifiant);
        if (detail.ok) {
          result.parametrage = {
            codeServiceObligatoire: detail.codeServiceObligatoire,
            designation: detail.designation,
            raw: detail.data?.parametrage,
          };
        }
      } catch { /* non bloquant */ }
    }

    // Action 3 : lister les codes service disponibles
    if (body.services) {
      try {
        const svcResult = await rechercherServicesStructure(config, token, identifiant);
        if (svcResult.ok) {
          result.services = svcResult.services;
        }
      } catch { /* non bloquant */ }
    }

    // Action 4 : vérifier un code service précis
    if (body.code_service) {
      try {
        const svcCheck = await consulterService(config, token, identifiant, body.code_service);
        result.service_valide = svcCheck.ok && svcCheck.actif;
        result.service_nom = svcCheck.nom;
        if (!svcCheck.ok || !svcCheck.actif) {
          result.service_erreur = `Code service "${body.code_service}" invalide ou inactif`;
        }
      } catch { /* non bloquant */ }
    }

    return new Response(JSON.stringify(result), { status: 200, headers });

  } catch (err) {
    console.error('[chorus-pro-verify]', err);
    return new Response(JSON.stringify({
      found: false,
      apiError: true,
      error: err instanceof Error ? err.message : 'Erreur interne',
    }), { status: 500, headers });
  }
});
