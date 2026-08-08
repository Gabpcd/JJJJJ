import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { applyRateLimit } from '../_shared/rate-limit.ts';
import {
  MANDAT_FACTURATION_VERSION,
  buildMandatFacturationTexte,
  hashMandatTexte,
  type StatutTvaHonoraires,
} from '../_shared/invoicing-mandate.ts';

const STATUTS_TVA = new Set([
  'FRANCHISE_EN_BASE',
  'REDEVABLE_TVA',
]);

function clientIp(req: Request): { ip: string; source: string } {
  const cf = req.headers.get('cf-connecting-ip')?.trim();
  if (cf) return { ip: cf, source: 'cf-connecting-ip' };
  const forwarded = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  if (forwarded) return { ip: forwarded, source: 'x-forwarded-for' };
  const real = req.headers.get('x-real-ip')?.trim();
  if (real) return { ip: real, source: 'x-real-ip' };
  return { ip: 'unknown', source: 'indisponible' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') {
    return jsonResponse(req, { success: false, error: 'Methode non autorisee' }, 405);
  }

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { success: false, error: auth.error }, auth.status);
    if (auth.isServiceRole || !auth.userId) {
      return jsonResponse(req, { success: false, error: 'Signature personnelle uniquement' }, 403);
    }

    const ip = clientIp(req);
    if (applyRateLimit('sign-invoicing-mandate', `${auth.userId}:${ip.ip}`, { max: 5, windowMs: 60_000 })) {
      return jsonResponse(req, { success: false, error: 'Trop de tentatives. Reessayez dans une minute.' }, 429);
    }

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || typeof body !== 'object') {
      return jsonResponse(req, { success: false, error: 'Corps JSON invalide' }, 400);
    }
    const version = typeof body.version === 'string' ? body.version : '';
    const contenuHash = typeof body.contenu_hash === 'string' ? body.contenu_hash : '';
    const contenuTexte = typeof body.contenu_texte === 'string' ? body.contenu_texte : '';
    const statutTva = typeof body.statut_tva_honoraires === 'string'
      ? body.statut_tva_honoraires
      : '';

    if (version !== MANDAT_FACTURATION_VERSION) {
      return jsonResponse(req, { success: false, error: 'VERSION_MANDAT_INVALIDE' }, 409);
    }
    if (!/^[a-f0-9]{64}$/.test(contenuHash)) {
      return jsonResponse(req, { success: false, error: 'HASH_MANDAT_INVALIDE' }, 400);
    }
    if (contenuTexte.length < 1000 || contenuTexte.length > 60_000) {
      return jsonResponse(req, { success: false, error: 'CONTENU_MANDAT_INVALIDE' }, 400);
    }
    if (!STATUTS_TVA.has(statutTva)) {
      return jsonResponse(req, { success: false, error: 'STATUT_TVA_INVALIDE' }, 400);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(req, { success: false, error: 'Configuration serveur incomplete' }, 500);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Le navigateur ne décide jamais du texte qu'il signe. Le serveur recharge
    // le profil, reconstruit la version canonique affichée et refuse le moindre
    // écart de texte ou de hash avant d'enregistrer la preuve.
    const { data: profile, error: profileError } = await admin
      .from('soignants')
      .select('prenom, nom, email, profession, numero_rpps, numero_adeli, siret_liberal, adresse_rue, adresse_code_postal, adresse_ville, numero_tva')
      .eq('id', auth.userId)
      .is('supprime_le', null)
      .maybeSingle();
    if (profileError || !profile) {
      return jsonResponse(req, { success: false, error: 'SOIGNANT_INTROUVABLE' }, 404);
    }
    const contenuCanonique = buildMandatFacturationTexte({
      ...profile,
      statut_tva_honoraires: statutTva as StatutTvaHonoraires,
    });
    const hashCanonique = await hashMandatTexte(contenuCanonique);
    if (contenuTexte !== contenuCanonique || contenuHash !== hashCanonique) {
      return jsonResponse(req, {
        success: false,
        error: 'CONTENU_MANDAT_NON_CANONIQUE',
        message: 'Le mandat a changé. Rechargez la page avant de signer.',
      }, 409);
    }

    const { data, error } = await admin.rpc('fn_signer_mandat_facturation_serveur', {
      p_soignant_id: auth.userId,
      p_version: version,
      p_ip: ip.ip === 'unknown' ? null : ip.ip,
      p_ip_source: ip.source,
      p_user_agent: req.headers.get('user-agent') || null,
      p_contenu_hash: contenuHash,
      p_contenu_texte: contenuTexte,
      p_statut_tva_honoraires: statutTva,
    });
    if (error) {
      console.error('[sign-invoicing-mandate] rpc error', error.code, error.message);
      return jsonResponse(req, { success: false, error: 'SIGNATURE_MANDAT_INDISPONIBLE' }, 500);
    }
    if (!data || (data as Record<string, unknown>).success !== true) {
      return jsonResponse(req, data || { success: false, error: 'SIGNATURE_REFUSEE' }, 409);
    }

    return jsonResponse(req, {
      ...(data as Record<string, unknown>),
      ip_address: ip.ip === 'unknown' ? null : ip.ip,
    });
  } catch (error) {
    console.error('[sign-invoicing-mandate] unexpected error', error);
    return jsonResponse(req, { success: false, error: 'Erreur interne' }, 500);
  }
});
