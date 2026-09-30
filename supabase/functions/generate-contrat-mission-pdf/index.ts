// Edge function : generate-contrat-mission-pdf (PR 3 Sprint 2)
//
// Rend le HTML final d'un contrat à partir du template + données mission,
// le stocke dans le bucket Supabase Storage `contrats-signes`, et met à
// jour contrats_mission avec storage_path + hash_document SHA-256.
//
// Stocke le document HTML (text/html), conservé comme original du rendu.
// Le hash signé via OTP couvre le HTML rendu (preuve d'intégrité).
//
// Input  : POST { contrat_id: uuid }
// Output : { success, storage_path, hash_document, signed_url, ttl }
//
// Auth : utilisateur autorisé par RPC ; le bypass système historique exige
// exactement la clé service configurée. On utilise le client
// service_role pour bypasser RLS au moment du write (insertion Storage),
// avec une autorisation canonique obligatoire `fn_contrat_storage_path` pour
// chaque utilisateur, renouvelée avant et après les opérations sensibles.

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { corsHeaders } from '../_shared/cors.ts';

const BUSINESS_TIME_ZONE = 'Europe/Paris';

function escapeHtml(s: unknown): string {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatDate(value: any): string {
  if (!value) return '—';
  try {
    const d = new Date(value);
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleString('fr-FR', {
      dateStyle: 'long',
      timeStyle: 'short',
      timeZone: BUSINESS_TIME_ZONE,
    });
  } catch { return '—'; }
}

function formatDateOnly(value: any): string {
  if (!value) return 'non renseignée';
  try {
    const iso = String(value).slice(0, 10);
    const d = new Date(`${iso}T12:00:00Z`);
    if (isNaN(d.getTime())) return 'non renseignée';
    return d.toLocaleDateString('fr-FR', {
      dateStyle: 'long',
      timeZone: BUSINESS_TIME_ZONE,
    });
  } catch { return 'non renseignée'; }
}

function replaceTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, key) => {
    const trimmed = key.trim();
    return Object.prototype.hasOwnProperty.call(vars, trimmed) ? vars[trimmed] : '';
  });
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(buf))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

function buildVariables(contrat: any, mission: any, soignant: any, etab: any): Record<string, string> {
  const adresseEtab = [etab?.adresse_rue, etab?.adresse_code_postal, etab?.adresse_ville]
    .filter(Boolean).join(', ');
  const adresseSoignant = [soignant?.adresse_rue, soignant?.adresse_code_postal, soignant?.adresse_ville]
    .filter(Boolean).join(', ');
  const periodeEssaiJours = Number(contrat?.periode_essai_jours || 1);
  const periodeEssaiLibelle = `${periodeEssaiJours} ${periodeEssaiJours === 1 ? 'jour' : 'jours'}`;

  return {
    numero_contrat: escapeHtml(contrat?.numero_contrat),
    type_contrat: escapeHtml(contrat?.type_contrat),
    etablissement_nom: escapeHtml(etab?.nom),
    etablissement_siret: escapeHtml(etab?.siret),
    etablissement_finess: escapeHtml(etab?.finess),
    etablissement_adresse: escapeHtml(adresseEtab),
    etablissement_ville: escapeHtml(etab?.adresse_ville),
    soignant_nom: escapeHtml(soignant?.nom),
    soignant_prenom: escapeHtml(soignant?.prenom),
    soignant_date_naissance: escapeHtml(formatDateOnly(soignant?.date_naissance)),
    soignant_adresse: escapeHtml(adresseSoignant),
    soignant_rpps: escapeHtml(soignant?.numero_rpps),
    soignant_siret: escapeHtml(soignant?.siret),
    intitule_mission: escapeHtml(mission?.intitule),
    profession: escapeHtml(soignant?.profession),
    debut_le: escapeHtml(formatDate(mission?.debut_le)),
    fin_le: escapeHtml(formatDate(mission?.fin_le)),
    duree_heures: escapeHtml(mission?.duree_heures),
    motif_cdd: escapeHtml(contrat?.motif_cdd || 'remplacement / surcroît temporaire d\'activité'),
    convention_collective: escapeHtml(etab?.convention_collective || 'CCN applicable à l\'établissement'),
    periode_essai_jours: escapeHtml(contrat?.periode_essai_jours || '1'),
    periode_essai_libelle: escapeHtml(periodeEssaiLibelle),
    taux_horaire: mission?.taux_horaire_base != null ? Number(mission.taux_horaire_base).toFixed(2) : '—',
    caisse_retraite: escapeHtml(etab?.caisse_retraite || 'AGIRC-ARRCO'),
    regime_prevoyance: escapeHtml(etab?.regime_prevoyance || 'celui de l\'employeur'),
    date_signature: escapeHtml(new Date().toLocaleDateString('fr-FR', {
      timeZone: BUSINESS_TIME_ZONE,
    })),
  };
}

function wrapInDocument(htmlBody: string, contratNumero: string): string {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8" />
<title>Contrat ${escapeHtml(contratNumero)}</title>
<style>
  body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #0f172a; line-height: 1.6; padding: 40px; max-width: 900px; margin: 0 auto; }
  h1 { color: #d6336c; font-size: 22px; border-bottom: 2px solid #fce7f3; padding-bottom: 8px; }
  h2 { color: #4b1d3a; font-size: 16px; margin-top: 24px; }
  p { margin: 8px 0; }
  strong { color: #1e293b; }
  em { color: #64748b; font-size: 12px; }
  .header-mention { background: #fef3f7; border-left: 4px solid #d6336c; padding: 12px 16px; margin-bottom: 24px; font-size: 13px; }
</style>
</head>
<body>
${htmlBody}
</body>
</html>`;
}

function dejaSigne(contrat: any): boolean {
  return /^SIGNE/.test(contrat.statut || '') || contrat.signature_soignant === true
    || contrat.signature_etablissement === true || !!contrat.signature_soignant_le
    || !!contrat.signature_etablissement_le;
}

Deno.serve(async (req: Request) => {
  const headers = { ...corsHeaders(req), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  const repondre = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return repondre(405, { error: 'Méthode interdite' });
  try {
    const body = await req.json().catch(() => null);
    const contratId = body?.contrat_id;
    if (typeof contratId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(contratId)) {
      return repondre(400, { error: 'Identifiant de contrat invalide' });
    }
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!supabaseUrl || !serviceKey || !anonKey) return repondre(503, { error: 'Service indisponible' });
    const authHeader = req.headers.get('Authorization') || '';
    const options = { auth: { persistSession: false, autoRefreshToken: false } };
    const userClient = createClient(supabaseUrl, anonKey, {
      ...options, global: { headers: { Authorization: authHeader } },
    });
    // L'appel système existant reste distinct ; un fragment de clé n'est jamais une preuve.
    const isService = authHeader === `Bearer ${serviceKey}`;
    if (!isService) {
      const { data, error } = await userClient.auth.getUser();
      if (error || !data.user) return repondre(401, { error: 'Non authentifié' });
    }
    const autoriser = async () => {
      if (isService) return null;
      const { data, error } = await userClient.rpc('fn_contrat_storage_path', { p_contrat_id: contratId });
      if (error || data?.success !== true) throw new Error('CONTRAT_ACCES_REFUSE');
      return data;
    };
    // Même garde pour propriétaire, soignant, membre et administrateur, avant toute lecture privilégiée.
    await autoriser();
    const admin = createClient(supabaseUrl, serviceKey, options);
    const lireContrat = async () => {
      const { data, error } = await admin.from('contrats_mission').select('*').eq('id', contratId).single();
      if (error || !data) throw new Error('CONTRAT_INDISPONIBLE');
      return data;
    };
    const repondreOriginal = async (contrat: any) => {
      const acces = await autoriser();
      if (!contrat.storage_path || !/^[a-f0-9]{64}$/.test(contrat.hash_document || '')) {
        return repondre(409, { error: 'Le document original est indisponible. Aucune régénération automatique n’est possible.' });
      }
      if (acces && (acces.storage_path !== contrat.storage_path || acces.hash_document !== contrat.hash_document)) {
        return repondre(409, { error: 'Le contrat a changé. Rechargez la page.' });
      }
      const { data: signed, error } = await admin.storage.from('contrats-signes').createSignedUrl(contrat.storage_path, 24 * 3600);
      if (error || !signed?.signedUrl) return repondre(503, { error: 'Le document original ne peut pas être ouvert. Réessayez.' });
      // Une fermeture ou révocation pendant l'appel Storage interdit de livrer l'URL.
      const apres = await autoriser();
      if (apres && (apres.storage_path !== contrat.storage_path || apres.hash_document !== contrat.hash_document)) {
        return repondre(409, { error: 'Le contrat a changé. Rechargez la page.' });
      }
      return repondre(200, { success: true, contrat_id: contratId, storage_path: contrat.storage_path,
        hash_document: contrat.hash_document, signed_url: signed.signedUrl, ttl_seconds: 24 * 3600 });
    };
    const contrat = await lireContrat();
    // Une preuve existante est relue, jamais rendue avec le template/profil courant.
    if (dejaSigne(contrat) || contrat.storage_path || contrat.hash_document || contrat.contenu_html_rendu_le) {
      return await repondreOriginal(contrat);
    }
    if (['ANNULE', 'EXPIRE', 'REFUSE'].includes(contrat.statut)) {
      return repondre(409, { error: 'Ce contrat ne peut plus être préparé.' });
    }
    const [missionRes, soignantRes, etabRes, templateRes] = await Promise.all([
      admin.from('missions').select('*').eq('id', contrat.mission_id).maybeSingle(),
      admin.from('soignants').select('*').eq('id', contrat.soignant_id).maybeSingle(),
      admin.from('etablissements').select('*').eq('id', contrat.etablissement_id).maybeSingle(),
      admin.from('templates_contrat').select('contenu_html, nom, version')
        .eq('type_contrat', contrat.type_contrat).eq('est_actif', true)
        .order('version', { ascending: false }).limit(1).maybeSingle(),
    ]);
    if ([missionRes, soignantRes, etabRes, templateRes].some(r => r.error)) {
      return repondre(503, { error: 'La préparation du contrat a échoué. Réessayez.' });
    }
    if (!missionRes.data || !soignantRes.data || !etabRes.data || !templateRes.data?.contenu_html) {
      return repondre(422, { error: 'Les données nécessaires au contrat ne sont pas disponibles.' });
    }
    const vars = buildVariables(contrat, missionRes.data, soignantRes.data, etabRes.data);
    const documentComplet = wrapInDocument(replaceTemplate(templateRes.data.contenu_html, vars), contrat.numero_contrat || contrat.id);
    const hash = await sha256Hex(documentComplet);
    await autoriser();
    const path = `${contratId}/${crypto.randomUUID()}.html`;
    const { error: uploadErr } = await admin.storage.from('contrats-signes')
      .upload(path, new Blob([documentComplet], { type: 'text/html' }), { contentType: 'text/html', upsert: false });
    if (uploadErr) return repondre(503, { error: 'Le document n’a pas pu être enregistré. Réessayez.' });
    await autoriser();
    // Compare-and-set atomique : une signature, un autre rendu ou une réaffectation
    // arrivés pendant Storage empêchent l'écrasement. Aucun cleanup d'objet incertain.
    let update = admin.from('contrats_mission').update({
      contenu_html: documentComplet, storage_path: path, hash_document: hash,
      template_slug: contrat.type_contrat, contenu_html_rendu_le: new Date().toISOString(),
    }).eq('id', contratId);
    for (const champ of ['statut', 'soignant_id', 'etablissement_id', 'mission_id', 'type_contrat',
      'signature_soignant', 'signature_etablissement', 'signature_soignant_le', 'signature_etablissement_le',
      'storage_path', 'hash_document', 'contenu_html_rendu_le', 'contenu_html']) {
      update = contrat[champ] == null ? update.is(champ, null) : update.eq(champ, contrat[champ]);
    }
    const { data: enregistre, error: updateErr } = await update.select('id, storage_path, hash_document').maybeSingle();
    if (updateErr) return repondre(503, { error: 'L’enregistrement du contrat n’a pas été confirmé. Réessayez.' });
    if (!enregistre) return repondre(409, { error: 'Le contrat a changé pendant sa préparation. Rechargez la page.' });
    return await repondreOriginal(enregistre);
  } catch (error) {
    if (error instanceof Error && error.message === 'CONTRAT_ACCES_REFUSE') return repondre(403, { error: 'Accès au contrat refusé.' });
    if (error instanceof Error && error.message === 'CONTRAT_INDISPONIBLE') return repondre(404, { error: 'Contrat indisponible.' });
    return repondre(503, { error: 'Le service contrat est indisponible. Réessayez.' });
  }
});
