// verify-justificatif-fonction — Vérification IA du JUSTIFICATIF DE FONCTION du
// représentant NON-DIRIGEANT d'un établissement (RH, chef de service, délégataire).
// Même mécanisme que verify-piece-identite-etab (Anthropic Vision, JPG/PNG/PDF).
//
// L'IA confirme que le document : (1) est bien un justificatif de fonction
// (attestation employeur, délégation de signature, fiche de poste, décision de
// nomination, contrat de travail), (2) mentionne le représentant déclaré,
// (3) mentionne l'établissement (nom / SIRET), (4) est authentique. Si oui →
// justificatif_fonction_verifie = true puis ré-évalue le rattachement (→ JUSTIFICATIF).

import { createClient } from 'npm:@supabase/supabase-js@2';
import { appelerAnthropic } from "../_shared/anthropic.ts";

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

const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf'];

function parseJsonFromText(text: string): any | null {
  try { return JSON.parse(text); } catch { /* try to extract */ }
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try { return JSON.parse(text.slice(start, end + 1)); } catch { /* ignore */ }
  }
  return null;
}

function toBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  try {
    const body = await req.json().catch(() => ({}));
    if (body?.warm === true) return json(200, { warm: true });

    const etablissementId = String(body?.etablissement_id || '').trim();
    if (!etablissementId) return json(400, { error: 'etablissement_id requis' });

    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) return json(401, { error: 'Non autorisé' });
    const token = authHeader.slice(7);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    const isServiceRole = token === serviceKey;

    // Autorisation : service-role OU membre PROPRIETAIRE/ADMIN_GROUPE de l'établissement.
    if (!isServiceRole) {
      const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: { user } } = await userClient.auth.getUser();
      if (!user) return json(401, { error: 'Session invalide' });
      const { data: membre } = await admin.from('membres_etablissement')
        .select('role').eq('etablissement_id', etablissementId).eq('user_id', user.id).eq('actif', true).maybeSingle();
      const okRole = membre && ['PROPRIETAIRE', 'ADMIN_GROUPE'].includes((membre as any).role);
      if (!okRole) return json(403, { error: 'Non autorisé pour cet établissement' });
    }

    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) return json(200, { ok: false, error: 'ANTHROPIC_API_KEY non configurée' });

    const { data: etab, error: etabErr } = await admin.from('etablissements')
      .select('nom, siret, representant_nom, representant_prenom, justificatif_fonction_s3_key, justificatif_fonction_type, justificatif_fonction_type_mime')
      .eq('id', etablissementId).maybeSingle();
    if (etabErr || !etab) return json(404, { error: 'Établissement introuvable' });
    const e = etab as Record<string, any>;
    if (!e.justificatif_fonction_s3_key) return json(400, { error: 'Aucun justificatif de fonction téléversé' });
    if (!e.representant_nom) return json(400, { error: 'Nom du représentant non renseigné' });
    if (e.justificatif_fonction_type_mime && !ALLOWED_MIME.includes(e.justificatif_fonction_type_mime)) {
      return json(200, { ok: true, verdict: 'REJETE', motif: `Type de fichier non autorisé: ${e.justificatif_fonction_type_mime}` });
    }

    const { data: file, error: dlErr } = await admin.storage.from('jolene-documents').download(e.justificatif_fonction_s3_key);
    if (dlErr || !file) return json(200, { ok: false, error: 'Fichier introuvable dans le stockage' });
    const base64 = toBase64(await file.arrayBuffer());
    const mime = e.justificatif_fonction_type_mime || 'image/jpeg';
    const isPdf = mime === 'application/pdf';

    const nomComplet = `${e.representant_prenom || ''} ${e.representant_nom}`.trim();

    const systemPrompt = `Tu es un vérificateur de justificatifs de fonction pour une marketplace de santé.
Le document doit prouver qu'une personne physique est habilitée à représenter un établissement de santé
(elle n'est pas forcément le dirigeant : RH, chef de service, délégataire). Réponds UNIQUEMENT en JSON valide:
{
  "est_justificatif_fonction": true/false,
  "type_detecte": "ATTESTATION_EMPLOYEUR" | "DELEGATION_SIGNATURE" | "FICHE_POSTE" | "CONTRAT_TRAVAIL" | "DECISION_NOMINATION" | "AUTRE" | null,
  "nom_correspond": true/false/null,
  "nom_extrait": "le nom de la personne lu sur le document" ou null,
  "fonction_detectee": "la fonction/le poste mentionné" ou null,
  "etablissement_correspond": true/false/null,
  "etablissement_extrait": "le nom de l'établissement lu sur le document" ou null,
  "document_lisible": true/false,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "indices_falsification": ["liste des indices de falsification/retouche"] ou [],
  "motif_rejet": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- verdict = "VERIFIE" UNIQUEMENT si : c'est bien un justificatif de fonction officiel, lisible, confiance HAUTE,
  ET nom_correspond = true (la personne déclarée), ET etablissement_correspond = true (le bon établissement).
- verdict = "EN_ATTENTE" si doute, confiance MOYENNE, ou un seul des deux liens (personne/établissement) est confirmé.
- verdict = "REJETE" si ce n'est pas un justificatif de fonction, illisible, ou confiance FAIBLE.
- nom_correspond : compare au représentant déclaré (tolère casse/accents/ordre).
- etablissement_correspond : compare au nom et/ou SIRET de l'établissement fournis (tolère nom commercial vs raison sociale).
- DÉTECTION DE FALSIFICATION : examine retouche/montage (polices incohérentes, bords flous autour des noms/dates,
  zones recouvertes, tampon/signature recollés). Au moindre indice sérieux, verdict = "EN_ATTENTE" et motif_rejet renseigné.`;

    const userMessage = `Représentant déclaré: "${nomComplet}"
Établissement: "${e.nom || ''}"${e.siret ? ` (SIRET ${e.siret})` : ''}
Type de document déclaré: "${e.justificatif_fonction_type || 'Justificatif de fonction'}"

Analyse ce document : est-ce un justificatif de fonction valide, qui rattache bien cette personne à cet établissement ?`;

    const content: any[] = [{ type: 'text', text: userMessage }];
    content.push(isPdf
      ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: base64 } }
      : { type: 'image', source: { type: 'base64', media_type: mime, data: base64 } });

    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 20_000);
    let ai;
    try {
      ai = await appelerAnthropic({
        apiKey: anthropicKey,
        system: systemPrompt,
        content,
        maxTokens: 1000,
        signal: aiController.signal,
      });
    } catch (err) {
      clearTimeout(aiTimeout);
      const estTimeout = (err as any)?.name === 'AbortError';
      await admin.from('etablissements').update({
        justificatif_fonction_resultat_ia: { erreur_anthropic: { status: estTimeout ? 'timeout' : 'network', at: new Date().toISOString() } },
      }).eq('id', etablissementId);
      return json(200, { ok: true, verdict: 'EN_ATTENTE', reason: estTimeout ? 'AI timeout' : 'AI network error' });
    }
    clearTimeout(aiTimeout);

    if (!ai.ok) {
      await admin.from('etablissements').update({
        justificatif_fonction_resultat_ia: { erreur_anthropic: { status: ai.status, body_excerpt: ai.body.slice(0, 1000), at: new Date().toISOString() } },
      }).eq('id', etablissementId);
      return json(200, { ok: false, verdict: 'EN_ATTENTE', error: `Anthropic ${ai.status}` });
    }

    const aiJson = ai.data;
    const text = (aiJson?.content || []).map((c: any) => c?.text || '').join('\n');
    const result = parseJsonFromText(text) || {};
    // GATE FALSIFICATION : tout indice de retouche → revue humaine (jamais VERIFIE auto).
    const indicesFalsif = Array.isArray(result.indices_falsification) ? result.indices_falsification : [];
    const verdict = (result.verdict === 'VERIFIE' && indicesFalsif.length > 0) ? 'EN_ATTENTE' : (result.verdict || 'EN_ATTENTE');
    const justificatifVerifie = verdict === 'VERIFIE'
      && result.nom_correspond === true
      && result.etablissement_correspond === true;

    await admin.from('etablissements').update({
      justificatif_fonction_verifie: justificatifVerifie,
      justificatif_fonction_verifie_le: justificatifVerifie ? new Date().toISOString() : null,
      justificatif_fonction_resultat_ia: result,
    }).eq('id', etablissementId);

    // Ré-évalue le rattachement adaptatif (→ JUSTIFICATIF si OK).
    let rattachement: any = null;
    try {
      const { data: rat } = await admin.rpc('fn_evaluer_rattachement_etablissement', { p_etablissement_id: etablissementId });
      rattachement = rat;
    } catch { /* non bloquant */ }

    return json(200, {
      ok: true,
      verdict,
      nom_correspond: result.nom_correspond ?? null,
      etablissement_correspond: result.etablissement_correspond ?? null,
      fonction_detectee: result.fonction_detectee ?? null,
      justificatif_verifie: justificatifVerifie,
      rattachement,
    });
  } catch (e) {
    return json(200, { ok: false, error: String(e).slice(0, 300) });
  }
});
