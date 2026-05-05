/**
 * chorus-pro-verify — Vérifie un numéro de structure Chorus Pro via l'API PISTE.
 *
 * Appelé depuis ChorusConfigEtabDialog (admin) et ChorusConfig (établissement)
 * pour valider en temps réel que le numéro de structure saisi existe sur Chorus Pro.
 *
 * Body : { identifiant: string }
 * Réponse : { found: boolean, structure?: { designation, siret, ... }, error?: string }
 *
 * Auth : JWT authenticated (admin OU établissement via RPC check).
 */

import { getPisteConfig, getAccessToken, rechercherStructure } from '../_shared/piste-client.ts';
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
    // Auth : vérifier que le caller est authentifié
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Non authentifié' }), { status: 401, headers });
    }

    // Vérifier que l'utilisateur est admin ou établissement via Supabase
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

    // Parse body
    const body = await req.json().catch(() => ({}));
    const identifiant = body.identifiant?.toString().trim();
    if (!identifiant) {
      return new Response(JSON.stringify({ error: 'identifiant requis' }), { status: 400, headers });
    }

    // PISTE config
    const config = getPisteConfig();
    if (!config) {
      return new Response(JSON.stringify({
        found: false,
        error: 'Credentials PISTE non configurés — vérification impossible',
        simulation: true,
      }), { status: 200, headers });
    }

    // OAuth2 token
    const token = await getAccessToken(config);

    // Rechercher la structure
    const result = await rechercherStructure(config, token, identifiant);

    if (!result.ok) {
      return new Response(JSON.stringify({
        found: false,
        error: `API Chorus Pro erreur (HTTP ${result.data?.status || 'unknown'})`,
      }), { status: 200, headers });
    }

    if (!result.found) {
      return new Response(JSON.stringify({
        found: false,
        error: `Structure "${identifiant}" introuvable sur Chorus Pro`,
      }), { status: 200, headers });
    }

    const s = result.structure;
    return new Response(JSON.stringify({
      found: true,
      structure: {
        designationStructure: s?.designationStructure,
        identifiantStructure: s?.identifiantStructure,
        siret: s?.siret,
        adresse: s?.adressePostale,
        typeIdentifiant: s?.typeIdentifiantStructure,
        actif: s?.structureActive,
      },
    }), { status: 200, headers });

  } catch (err) {
    console.error('[chorus-pro-verify]', err);
    return new Response(JSON.stringify({
      found: false,
      error: err instanceof Error ? err.message : 'Erreur interne',
    }), { status: 500, headers });
  }
});
