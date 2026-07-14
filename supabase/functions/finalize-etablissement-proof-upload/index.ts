import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { canManageEstablishment } from '../_shared/etablissement-auth.ts';
import { corsHeaders } from '../_shared/cors.ts';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MIME_TYPES = new Set(['application/pdf', 'image/jpeg', 'image/png', 'image/webp']);
const IDENTITY_TYPES = new Set(['CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR']);
const FUNCTION_TYPES = new Set([
  'ATTESTATION_EMPLOYEUR',
  'DELEGATION_SIGNATURE',
  'FICHE_POSTE',
  'CONTRAT_TRAVAIL',
  'DECISION_NOMINATION',
]);

type ReplacementResult = {
  success?: boolean;
  ancienne_s3_key?: string | null;
  verification_source_version?: number;
  error?: string;
};

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return json(405, { error: 'Méthode non autorisée' });

  const auth = await verifyUserOrServiceRole(req);
  if (!auth.ok) return json(auth.status, { error: auth.error });

  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  if (!body) return json(400, { error: 'Corps JSON invalide' });

  const etablissementId = String(body.etablissement_id || '').trim();
  const preuve = String(body.preuve || '').trim().toUpperCase();
  const nouvelleCle = String(body.nouvelle_s3_key || '').trim();
  const typeMime = String(body.type_mime || '').trim().toLowerCase();
  const typeDocument = String(body.type_document || '').trim().toUpperCase();
  const versionAttendue = Number(body.version_attendue);
  const representantNom = typeof body.representant_nom === 'string'
    ? body.representant_nom.trim()
    : null;
  const representantPrenom = typeof body.representant_prenom === 'string'
    ? body.representant_prenom.trim()
    : null;

  if (!UUID_RE.test(etablissementId) || !['IDENTITE', 'FONCTION'].includes(preuve)) {
    return json(400, { error: 'Établissement ou type de preuve invalide' });
  }
  if (!Number.isSafeInteger(versionAttendue) || versionAttendue < 0) {
    return json(400, { error: 'Version de dossier invalide; rechargez la page' });
  }
  if (!nouvelleCle.startsWith(`${etablissementId}/`)
      || nouvelleCle.includes('..')
      || nouvelleCle.includes('\\')) {
    return json(400, { error: 'Chemin de preuve invalide' });
  }
  if (!MIME_TYPES.has(typeMime)
      || (preuve === 'IDENTITE' && !IDENTITY_TYPES.has(typeDocument))
      || (preuve === 'FONCTION' && !FUNCTION_TYPES.has(typeDocument))) {
    return json(400, { error: 'Format ou type documentaire invalide' });
  }
  if (preuve === 'IDENTITE' && (!representantNom || !representantPrenom)) {
    return json(400, { error: 'Nom et prénom du représentant requis' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseUrl || !serviceKey) {
    return json(503, { error: 'Configuration serveur incomplète' });
  }
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  if (!auth.isServiceRole
      && !(await canManageEstablishment(admin, auth.userId, etablissementId))) {
    const adminAuth = await verifyAdminOrServiceRole(req);
    if (!adminAuth.ok) return json(403, { error: 'Non autorisé pour cet établissement' });
  }

  const nettoyerNouvellePreuve = async () => {
    const { error } = await admin.storage.from('jolene-documents').remove([nouvelleCle]);
    if (error) {
      console.error('[finalize-etablissement-proof-upload] cleanup nouvelle preuve', error.message);
    }
    return !error;
  };

  const { data, error } = await admin.rpc('fn_remplacer_preuve_etablissement', {
    p_etablissement_id: etablissementId,
    p_preuve: preuve,
    p_nouvelle_s3_key: nouvelleCle,
    p_type_mime: typeMime,
    p_type_document: typeDocument,
    p_version_attendue: versionAttendue,
    p_representant_nom: representantNom,
    p_representant_prenom: representantPrenom,
    p_acteur_id: auth.userId,
  });

  const result = data as ReplacementResult | null;
  if (error || result?.success !== true) {
    const nettoyee = await nettoyerNouvellePreuve();
    const conflit = error?.code === '40001';
    return json(conflit ? 409 : 400, {
      ok: false,
      code: conflit ? 'SOURCE_CHANGED' : 'DATABASE_REPLACEMENT_FAILED',
      error: error?.message || result?.error || 'Remplacement documentaire impossible',
      nouvelle_preuve_nettoyee: nettoyee,
    });
  }

  let anciennePreuveNettoyee = true;
  const ancienneCle = typeof result.ancienne_s3_key === 'string'
    ? result.ancienne_s3_key
    : null;
  if (ancienneCle && ancienneCle !== nouvelleCle) {
    const { error: cleanupError } = await admin.storage
      .from('jolene-documents')
      .remove([ancienneCle]);
    if (cleanupError) {
      anciennePreuveNettoyee = false;
      console.error('[finalize-etablissement-proof-upload] cleanup ancienne preuve', cleanupError.message);
    }
  }

  return json(200, {
    ok: true,
    ancienne_preuve_nettoyee: anciennePreuveNettoyee,
    verification_source_version: result.verification_source_version,
  });
});
