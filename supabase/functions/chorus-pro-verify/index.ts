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
    const identifiant = body.identifiant?.toString().trim();
    if (!identifiant) {
      return new Response(JSON.stringify({ error: 'identifiant requis' }), { status: 400, headers });
    }

    const config = getPisteConfig();
    if (!config) {
      return new Response(JSON.stringify({
        found: false,
        error: 'Credentials PISTE non configurés — vérification impossible',
        simulation: true,
      }), { status: 200, headers });
    }

    const token = await getAccessToken(config);

    // Action 1 : vérifier que la structure existe
    const searchResult = await rechercherStructure(config, token, identifiant);
    if (!searchResult.ok || !searchResult.found) {
      return new Response(JSON.stringify({
        found: false,
        error: `Structure "${identifiant}" introuvable sur Chorus Pro`,
      }), { status: 200, headers });
    }

    const s = searchResult.structure;
    const result: any = {
      found: true,
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
      error: err instanceof Error ? err.message : 'Erreur interne',
    }), { status: 500, headers });
  }
});
