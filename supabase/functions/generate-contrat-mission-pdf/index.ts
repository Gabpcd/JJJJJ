// Edge function : generate-contrat-mission-pdf (PR 3 Sprint 2)
//
// Rend le HTML final d'un contrat à partir du template + données mission,
// le stocke dans le bucket Supabase Storage `contrats-signes`, et met à
// jour contrats_mission avec storage_path + hash_document SHA-256.
//
// MVP : stocke HTML (text/html). Le PDF binaire est généré côté frontend
// via jspdf (déjà installé) au moment du téléchargement par l'utilisateur.
// Le hash signé via OTP couvre le HTML rendu (preuve d'intégrité).
//
// Input  : POST { contrat_id: uuid }
// Output : { success, storage_path, hash_document, signed_url, ttl }
//
// Auth : appelé soit par l'étab/soignant (vérification RPC), soit par le
// trigger d'acceptation candidature (service_role). On utilise le client
// service_role pour bypasser RLS au moment du write (insertion Storage),
// mais on garde une vérification d'autorisation par RPC `est_admin()` ou
// `mon_etablissement_id()`.

import { createClient } from 'npm:@supabase/supabase-js@2';
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
    soignant_date_naissance: escapeHtml(soignant?.date_naissance),
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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
  }

  try {
    const body = await req.json();
    const contratId = body?.contrat_id as string | undefined;
    if (!contratId) {
      return new Response(JSON.stringify({ error: 'contrat_id requis' }),
        { status: 400, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authHeader = req.headers.get('Authorization') || '';

    // Client utilisateur (RLS) pour la vérif d'autorisation
    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    const isService = !user && authHeader.includes(serviceKey);

    if (!user && !isService) {
      return new Response(JSON.stringify({ error: 'Non authentifié' }),
        { status: 401, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    // Client service_role pour les writes Storage + table
    const admin = createClient(supabaseUrl, serviceKey);

    // Récupérer le contrat + mission + soignant + étab
    const { data: contrat, error: contratErr } = await admin
      .from('contrats_mission')
      .select('*')
      .eq('id', contratId)
      .single();

    if (contratErr || !contrat) {
      return new Response(JSON.stringify({ error: 'Contrat introuvable' }),
        { status: 404, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    // Vérif d'autorisation (sauf service)
    if (!isService && user) {
      const allowed = contrat.soignant_id === user.id || contrat.etablissement_id === user.id;
      if (!allowed) {
        // Si non, vérifier mon_etablissement_id via RPC
        const { data: rpc } = await userClient.rpc('fn_contrat_storage_path' as any, { p_contrat_id: contratId });
        if (!(rpc as any)?.success) {
          return new Response(JSON.stringify({ error: 'Non autorisé' }),
            { status: 403, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
        }
      }
    }

    const [missionRes, soignantRes, etabRes, templateRes] = await Promise.all([
      admin.from('missions').select('*').eq('id', contrat.mission_id).maybeSingle(),
      admin.from('soignants').select('*').eq('id', contrat.soignant_id).maybeSingle(),
      admin.from('etablissements').select('*').eq('id', contrat.etablissement_id).maybeSingle(),
      admin.from('templates_contrat').select('contenu_html, nom, version')
        .eq('type_contrat', contrat.type_contrat)
        .eq('est_actif', true)
        .order('version', { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

    if (!templateRes.data?.contenu_html) {
      return new Response(JSON.stringify({
        error: `Aucun template actif pour type_contrat=${contrat.type_contrat}`,
      }), { status: 422, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    const vars = buildVariables(contrat, missionRes.data, soignantRes.data, etabRes.data);
    const corpsRendu = replaceTemplate(templateRes.data.contenu_html, vars);
    const documentComplet = wrapInDocument(corpsRendu, contrat.numero_contrat || contrat.id);
    const hash = await sha256Hex(documentComplet);

    // Upload Storage
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    const path = `${contratId}/${ts}.html`;
    const { error: uploadErr } = await admin.storage
      .from('contrats-signes')
      .upload(path, new Blob([documentComplet], { type: 'text/html' }), {
        contentType: 'text/html',
        upsert: false,
      });
    if (uploadErr) {
      return new Response(JSON.stringify({ error: 'Erreur upload : ' + uploadErr.message }),
        { status: 500, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    // Update contrats_mission
    await admin.from('contrats_mission').update({
      contenu_html: documentComplet,
      storage_path: path,
      hash_document: hash,
      template_slug: contrat.type_contrat,
      contenu_html_rendu_le: new Date().toISOString(),
    }).eq('id', contratId);

    // Generate signed URL (24h)
    const { data: signed } = await admin.storage
      .from('contrats-signes')
      .createSignedUrl(path, 24 * 3600);

    return new Response(JSON.stringify({
      success: true,
      contrat_id: contratId,
      storage_path: path,
      hash_document: hash,
      signed_url: signed?.signedUrl,
      ttl_seconds: 24 * 3600,
      template_nom: templateRes.data.nom,
      template_version: templateRes.data.version,
    }), { status: 200, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err?.message || 'Erreur interne' }),
      { status: 500, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
  }
});
