import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

const API_KEY_RE = /^sd_(?:live|test)_[a-zA-Z0-9]{24,80}$/;
const API_SECRET_RE = /^[a-fA-F0-9]{64}$/;
const PROFESSIONS = new Set([
  'IDE', 'AS', 'AES', 'IBODE', 'IADE', 'SAGE_FEMME', 'KINE', 'MEDECIN',
  'PHARMACIEN', 'MANIPULATEUR_RADIO', 'PREPARATEUR_PHARMA', 'DIETETICIEN',
  'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE', 'DENTISTE',
  'AUXILIAIRE_PUERICULTURE',
]);
const STATUTS = new Set(['BROUILLON', 'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE', 'LITIGE', 'EXPIREE']);

function constantTimeEqual(a: string, b: string): boolean {
  const aa = new TextEncoder().encode(a.toLowerCase());
  const bb = new TextEncoder().encode(b.toLowerCase());
  const max = Math.max(aa.length, bb.length);
  let diff = aa.length ^ bb.length;
  for (let i = 0; i < max; i++) diff |= (aa[i] || 0) ^ (bb[i] || 0);
  return diff === 0;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function hasPermission(permissions: unknown, expected: string): boolean {
  return Array.isArray(permissions) && permissions.includes(expected);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);

  try {
    if (!['GET', 'POST'].includes(req.method)) {
      return jsonResponse(req, { error: 'Methode non autorisee' }, 405);
    }

    const apiKey = (req.headers.get('x-api-key') || '').trim();
    const apiSecret = (req.headers.get('x-api-secret') || '').trim();
    if (!API_KEY_RE.test(apiKey) || !API_SECRET_RE.test(apiSecret)) {
      // Meme cout de hash pour limiter les differences de timing entre header
      // absent, cle inconnue et secret incorrect.
      await sha256Hex(apiSecret || '0'.repeat(64));
      return jsonResponse(req, { error: 'Identifiants API invalides' }, 401);
    }

    const ip = getClientIp(req);
    const keyFingerprint = (await sha256Hex(apiKey)).slice(0, 20);
    if (applyRateLimit('api-v1', `${keyFingerprint}:${ip}`, { max: 120, windowMs: 60_000 })) {
      return jsonResponse(req, { error: 'Limite de requetes atteinte' }, 429);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(req, { error: 'Service indisponible' }, 503);
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const { data: key, error: keyError } = await supabase
      .from('api_keys')
      .select('id, etablissement_id, groupe_sante_id, cle_secret_hash, permissions, expire_le, actif')
      .eq('cle_api', apiKey)
      .eq('actif', true)
      .maybeSingle();

    const candidateHash = await sha256Hex(apiSecret);
    let secretValide = false;
    if (key?.cle_secret_hash && /^[a-f0-9]{64}$/i.test(key.cle_secret_hash)) {
      secretValide = constantTimeEqual(candidateHash, key.cle_secret_hash);
    } else if (key?.cle_secret_hash?.startsWith('$2')) {
      // Compatibilite temporaire des quelques hashes bcrypt historiques. La
      // RPC est service_role-only et ne retourne jamais le hash ni le secret.
      const { data: legacy } = await supabase.rpc('fn_verifier_api_key', {
        p_cle_api: apiKey,
        p_cle_secret: apiSecret,
      });
      secretValide = (legacy as Record<string, unknown> | null)?.valid === true;
    }

    if (keyError || !key || !secretValide) {
      return jsonResponse(req, { error: 'Identifiants API invalides' }, 401);
    }
    if (key.expire_le && new Date(key.expire_le).getTime() <= Date.now()) {
      return jsonResponse(req, { error: 'Cle API expiree' }, 403);
    }
    const etabId = key.etablissement_id;
    if (!etabId) {
      return jsonResponse(req, { error: 'Cle API non rattachee a un etablissement' }, 403);
    }

    const { data: rateAllowed, error: rateError } = await supabase.rpc('fn_verifier_rate_limit', {
      p_cle: key.id,
      p_action: 'api_v1_authenticated',
      p_max_tentatives: 2000,
      p_fenetre_secondes: 3600,
    });
    if (rateError || rateAllowed !== true) {
      return jsonResponse(req, { error: 'Quota horaire atteint' }, 429);
    }
    await supabase.from('api_keys').update({ derniere_utilisation: new Date().toISOString() }).eq('id', key.id);

    const url = new URL(req.url);
    const path = url.pathname.replace(/.*\/api-v1/, '') || '/';
    const limitRaw = Number(url.searchParams.get('limit') || '100');
    const limit = Number.isInteger(limitRaw) ? Math.max(1, Math.min(limitRaw, 100)) : 100;

    if (req.method === 'GET' && path === '/missions') {
      if (!hasPermission(key.permissions, 'missions:read')) {
        return jsonResponse(req, { error: 'Permission missions:read requise' }, 403);
      }
      const statut = url.searchParams.get('statut');
      if (statut && !STATUTS.has(statut)) return jsonResponse(req, { error: 'Statut invalide' }, 400);
      let query = supabase
        .from('missions')
        .select('id, intitule, profession_requise, service, debut_le, fin_le, taux_horaire_base, statut, soignant_assigne_id')
        .eq('etablissement_id', etabId);
      if (statut) query = query.eq('statut', statut);
      const { data, error } = await query.order('debut_le', { ascending: false }).limit(limit);
      if (error) {
        console.error('[api-v1] GET missions', error.message);
        return jsonResponse(req, { error: 'Erreur requete' }, 500);
      }
      return jsonResponse(req, { missions: data || [], count: data?.length || 0 });
    }

    if (req.method === 'POST' && path === '/missions') {
      if (!hasPermission(key.permissions, 'missions:write')) {
        return jsonResponse(req, { error: 'Permission missions:write requise' }, 403);
      }
      const body = await req.json().catch(() => null) as Record<string, unknown> | null;
      if (!body || Array.isArray(body)) return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);

      const intitule = typeof body.intitule === 'string' ? body.intitule.trim() : '';
      const profession = typeof body.profession_requise === 'string' ? body.profession_requise.trim().toUpperCase() : '';
      const service = typeof body.service === 'string' ? body.service.trim() : null;
      const debut = typeof body.debut_le === 'string' ? new Date(body.debut_le) : null;
      const fin = typeof body.fin_le === 'string' ? new Date(body.fin_le) : null;
      const taux = typeof body.taux_horaire_base === 'number' ? body.taux_horaire_base : Number(body.taux_horaire_base);

      if (intitule.length < 3 || intitule.length > 160) return jsonResponse(req, { error: 'intitule invalide' }, 400);
      if (!PROFESSIONS.has(profession)) return jsonResponse(req, { error: 'profession_requise invalide' }, 400);
      if (service && service.length > 120) return jsonResponse(req, { error: 'service trop long' }, 400);
      if (!debut || !fin || !Number.isFinite(debut.getTime()) || !Number.isFinite(fin.getTime()) || fin <= debut) {
        return jsonResponse(req, { error: 'Dates invalides' }, 400);
      }
      if (fin.getTime() - debut.getTime() > 31 * 24 * 3600 * 1000) {
        return jsonResponse(req, { error: 'Duree maximale depassee' }, 400);
      }
      if (!Number.isFinite(taux) || taux <= 0 || taux > 1000) {
        return jsonResponse(req, { error: 'taux_horaire_base invalide' }, 400);
      }

      const { data, error } = await supabase.from('missions').insert({
        etablissement_id: etabId,
        intitule,
        profession_requise: profession,
        service: service || null,
        debut_le: debut.toISOString(),
        fin_le: fin.toISOString(),
        taux_horaire_base: taux,
      }).select('id, intitule, statut').single();
      if (error) {
        console.error('[api-v1] POST missions', error.message);
        return jsonResponse(req, { error: 'Creation refusee par les regles metier' }, 422);
      }
      return jsonResponse(req, { mission: data }, 201);
    }

    if (req.method === 'GET' && path === '/presences') {
      if (!hasPermission(key.permissions, 'presences:read')) {
        return jsonResponse(req, { error: 'Permission presences:read requise' }, 403);
      }
      const { data: missionIds, error: missionsError } = await supabase
        .from('missions').select('id').eq('etablissement_id', etabId).limit(1000);
      if (missionsError) return jsonResponse(req, { error: 'Erreur requete' }, 500);
      const ids = (missionIds || []).map((mission) => mission.id);
      if (ids.length === 0) return jsonResponse(req, { presences: [], count: 0 });
      const { data, error } = await supabase
        .from('presences')
        .select('id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le, valide_par_etablissement, methode_pointage_arrivee')
        .in('mission_id', ids)
        .order('pointage_arrivee_le', { ascending: false })
        .limit(limit);
      if (error) return jsonResponse(req, { error: 'Erreur requete' }, 500);
      return jsonResponse(req, { presences: data || [], count: data?.length || 0 });
    }

    if (req.method === 'GET' && path === '/factures') {
      if (!hasPermission(key.permissions, 'factures:read')) {
        return jsonResponse(req, { error: 'Permission factures:read requise' }, 403);
      }
      const { data, error } = await supabase
        .from('factures')
        .select('id, numero_facture, statut, montant_ht, montant_tva, montant_ttc, cree_le')
        .eq('etablissement_id', etabId)
        .order('cree_le', { ascending: false })
        .limit(Math.min(limit, 50));
      if (error) return jsonResponse(req, { error: 'Erreur requete' }, 500);
      return jsonResponse(req, { factures: data || [], count: data?.length || 0 });
    }

    return jsonResponse(req, {
      error: 'Endpoint non trouve',
      endpoints: ['GET /missions', 'POST /missions', 'GET /presences', 'GET /factures'],
      documentation: 'https://jolene.app/aide/api',
    }, 404);
  } catch (error) {
    console.error('[api-v1] erreur', error);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: corsHeaders(req),
    });
  }
});
