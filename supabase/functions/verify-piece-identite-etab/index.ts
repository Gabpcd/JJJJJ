// verify-piece-identite-etab — Vérification de la pièce d'identité du REPRÉSENTANT
// d'un établissement, par réutilisation du MÊME mécanisme que verify-document soignant
// (Anthropic Vision, formats JPG/PNG/PDF, PDF en type "document", extraction nom/prénom
// + comparaison). Isolé du verify-document soignant (critique) pour ne pas le déstabiliser.
//
// Flux : l'établissement a téléversé la pièce dans jolene-documents et renseigné
// representant_nom/prenom. Cette fonction télécharge le fichier, demande à l'IA d'en
// extraire le nom, compare au représentant déclaré, écrit representant_identite_verifiee
// si VERIFIE + nom concordant, puis évalue le rattachement adaptatif.

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
const TYPE_LABELS: Record<string, string> = {
  CARTE_IDENTITE: "Carte d'identité ou Passeport",
  PASSEPORT: 'Passeport',
  TITRE_SEJOUR: 'Titre de séjour',
};

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

    // Autorisation : service-role OU membre PROPRIETAIRE/ADMIN de l'établissement.
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
      .select('representant_nom, representant_prenom, representant_piece_s3_key, representant_piece_type_mime, representant_piece_type_document')
      .eq('id', etablissementId).maybeSingle();
    if (etabErr || !etab) return json(404, { error: 'Établissement introuvable' });
    const e = etab as Record<string, any>;
    if (!e.representant_piece_s3_key) return json(400, { error: 'Aucune pièce d\'identité téléversée' });
    if (!e.representant_nom) return json(400, { error: 'Nom du représentant non renseigné' });
    if (e.representant_piece_type_mime && !ALLOWED_MIME.includes(e.representant_piece_type_mime)) {
      return json(200, { ok: true, verdict: 'REJETE', motif: `Type de fichier non autorisé: ${e.representant_piece_type_mime}` });
    }

    // Téléchargement du fichier
    const { data: file, error: dlErr } = await admin.storage.from('jolene-documents').download(e.representant_piece_s3_key);
    if (dlErr || !file) return json(200, { ok: false, error: 'Fichier introuvable dans le stockage' });
    const base64 = toBase64(await file.arrayBuffer());
    const mime = e.representant_piece_type_mime || 'image/jpeg';
    const isPdf = mime === 'application/pdf';

    const typeLabel = TYPE_LABELS[e.representant_piece_type_document] || "Pièce d'identité";
    const nomComplet = `${e.representant_prenom || ''} ${e.representant_nom}`.trim();

    const systemPrompt = `Tu es un vérificateur de pièces d'identité. Analyse le document et réponds UNIQUEMENT en JSON valide:
{
  "type_correspond": true/false,
  "type_detecte": "string",
  "date_expiration": "YYYY-MM-DD" ou null,
  "nom_correspond": true/false/null,
  "nom_extrait": "le nom de famille lu sur le document" ou null,
  "prenom_extrait": "le prénom lu sur le document" ou null,
  "document_lisible": true/false,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "indices_falsification": ["liste des indices de falsification/retouche détectés"] ou [],
  "motif_rejet": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- verdict = "VERIFIE" si c'est bien une pièce d'identité officielle (CNI, passeport, titre de séjour), lisible, confiance HAUTE.
- verdict = "EN_ATTENTE" si doute ou confiance MOYENNE.
- verdict = "REJETE" si ce n'est pas une pièce d'identité, illisible/tronquée, ou confiance FAIBLE.
- nom_correspond : compare le nom/prénom du document au nom du représentant fourni (tolère casse/accents/ordre).
- DÉTECTION DE FALSIFICATION : examine les signes de retouche/montage (polices incohérentes,
  bords de texte flous/pixellisés autour des nom/dates/numéros, photo recollée, zones recouvertes,
  arrière-plan altéré). Liste tout signe dans "indices_falsification". Au moindre indice sérieux,
  verdict = "EN_ATTENTE" et motif_rejet = "Indices de falsification détectés".`;

    const userMessage = `Document déclaré comme: "${typeLabel}"
Nom du représentant déclaré: "${nomComplet}"

Analyse ce document et vérifie sa conformité + la concordance du nom.`;

    const content: any[] = [{ type: 'text', text: userMessage }];
    content.push(isPdf
      ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: base64 } }
      : { type: 'image', source: { type: 'base64', media_type: mime, data: base64 } });

    const aiController = new AbortController();
    const aiTimeout = setTimeout(() => aiController.abort(), 20_000);
    const ai = await appelerAnthropic({
      apiKey: anthropicKey,
      system: systemPrompt,
      content,
      maxTokens: 1000,
      signal: aiController.signal,
    });
    clearTimeout(aiTimeout);

    // status 0 = erreur réseau / abort (timeout) interceptée par le module partagé.
    if (ai.status === 0) {
      const estTimeout = aiController.signal.aborted;
      await admin.from('etablissements').update({
        representant_identite_resultat_ia: { erreur_anthropic: { status: estTimeout ? 'timeout' : 'network', at: new Date().toISOString() } },
      }).eq('id', etablissementId);
      return json(200, { ok: true, verdict: 'EN_ATTENTE', reason: estTimeout ? 'AI timeout' : 'AI network error' });
    }

    if (!ai.ok) {
      await admin.from('etablissements').update({
        representant_identite_resultat_ia: { erreur_anthropic: { status: ai.status, body_excerpt: ai.body.slice(0, 1000), at: new Date().toISOString() } },
      }).eq('id', etablissementId);
      return json(200, { ok: false, verdict: 'EN_ATTENTE', error: `Anthropic ${ai.status}` });
    }

    const aiJson = ai.data;
    const text = (aiJson?.content || []).map((c: any) => c?.text || '').join('\n');
    const result = parseJsonFromText(text) || {};
    // GATE FALSIFICATION : tout indice de retouche → revue humaine (jamais VERIFIE auto).
    const indicesFalsif = Array.isArray(result.indices_falsification) ? result.indices_falsification : [];
    const verdict = (result.verdict === 'VERIFIE' && indicesFalsif.length > 0) ? 'EN_ATTENTE' : (result.verdict || 'EN_ATTENTE');
    const nomCorrespond = result.nom_correspond === true;
    const identiteVerifiee = verdict === 'VERIFIE' && nomCorrespond;

    await admin.from('etablissements').update({
      representant_identite_verifiee: identiteVerifiee,
      representant_identite_verifiee_le: identiteVerifiee ? new Date().toISOString() : null,
      representant_identite_resultat_ia: result,
    }).eq('id', etablissementId);

    // Évalue le rattachement adaptatif (AUTO_DIRIGEANT / EMAIL_PRO / ADMIN)
    let rattachement: any = null;
    try {
      const { data: rat } = await admin.rpc('fn_evaluer_rattachement_etablissement', { p_etablissement_id: etablissementId });
      rattachement = rat;
    } catch { /* non bloquant */ }

    return json(200, {
      ok: true,
      verdict,
      nom_correspond: nomCorrespond,
      nom_extrait: result.nom_extrait ?? null,
      prenom_extrait: result.prenom_extrait ?? null,
      identite_verifiee: identiteVerifiee,
      rattachement,
    });
  } catch (e) {
    return json(200, { ok: false, error: String(e).slice(0, 300) });
  }
});
