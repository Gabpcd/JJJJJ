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
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { canManageEstablishment } from '../_shared/etablissement-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import {
  normalizeIsoCivilDate,
  personNameMatches,
  strictAiVerificationQuality,
  validateDocumentFile,
} from '../_shared/verification-rules.ts';
import { corsHeaders } from '../_shared/cors.ts';

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
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return json(auth.status, { error: auth.error });
    const body = await req.json().catch(() => ({}));
    if (body?.warm === true) {
      if (!auth.isServiceRole) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return json(adminAuth.status, { error: adminAuth.error });
      }
      return json(200, { warm: true, configured: !!Deno.env.get('ANTHROPIC_API_KEY') });
    }

    const etablissementId = String(body?.etablissement_id || '').trim();
    if (!etablissementId) return json(400, { error: 'etablissement_id requis' });

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    if (!auth.isServiceRole) {
      if (applyRateLimit('verify-piece-identite-etab', getClientIp(req), { max: 8, windowMs: 60_000 })) {
        return json(429, { error: 'Trop de vérifications. Réessayez dans une minute.' });
      }
      if (!(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return json(403, { error: 'Non autorisé pour cet établissement' });
      }
    }

    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) return json(200, { ok: false, error: 'ANTHROPIC_API_KEY non configurée' });

    const { data: etab, error: etabErr } = await admin.from('etablissements')
      .select('verification_source_version, representant_nom, representant_prenom, representant_piece_s3_key, representant_piece_type_mime, representant_piece_type_document')
      .eq('id', etablissementId).maybeSingle();
    if (etabErr || !etab) return json(404, { error: 'Établissement introuvable' });
    const e = etab as Record<string, any>;
    const appliquerVerdict = async (verifie: boolean, resultat: Record<string, unknown>) => {
      if (!auth.isServiceRole && !(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return false;
      }
      const { data, error } = await admin.rpc(
        'fn_appliquer_verification_identite_etablissement',
        {
          p_etablissement_id: etablissementId,
          p_version_attendue: Number(e.verification_source_version),
          p_piece_s3_key: e.representant_piece_s3_key ?? null,
          p_piece_type_mime: e.representant_piece_type_mime ?? null,
          p_piece_type_document: e.representant_piece_type_document ?? null,
          p_representant_nom: e.representant_nom ?? null,
          p_representant_prenom: e.representant_prenom ?? null,
          p_verifie: verifie,
          p_resultat: resultat,
        },
      );
      if (error) throw new Error(`Persistance atomique identité impossible: ${error.code || error.message}`);
      return data === true;
    };
    const sourceChangee = () => json(409, {
      ok: false,
      code: 'VERIFICATION_SOURCE_CHANGED',
      error: 'La pièce ou le profil a changé pendant la vérification. Relancez le contrôle.',
    });
    if (!e.representant_piece_s3_key) return json(400, { error: 'Aucune pièce d\'identité téléversée' });
    const piecePath = String(e.representant_piece_s3_key);
    const proprietairesAutorises = new Set(
      [etablissementId, auth.userId].filter((value): value is string => !!value),
    );
    const cheminAutorise = !piecePath.includes('..')
      && !piecePath.includes('\\')
      && [...proprietairesAutorises].some((ownerId) => piecePath.startsWith(`${ownerId}/`));
    if (!cheminAutorise) return json(403, { error: 'Chemin de pièce d\'identité non autorisé' });
    if (!e.representant_nom || !e.representant_prenom) {
      return json(400, { error: 'Nom et prénom du représentant requis' });
    }
    // Téléchargement du fichier
    const { data: file, error: dlErr } = await admin.storage.from('jolene-documents').download(piecePath);
    if (dlErr || !file) return json(200, { ok: false, error: 'Fichier introuvable dans le stockage' });
    const arrayBuffer = await file.arrayBuffer();
    const fileValidation = validateDocumentFile(
      new Uint8Array(arrayBuffer),
      e.representant_piece_type_mime,
    );
    if (!fileValidation.ok) {
      const motifs: Record<string, string> = {
        EMPTY: "La pièce d'identité est vide.",
        TOO_LARGE: "La pièce d'identité dépasse 10 Mo.",
        UNSUPPORTED_MIME: "Le type MIME déclaré de la pièce d'identité est absent ou non autorisé.",
        INVALID_SIGNATURE: "Le contenu de la pièce d'identité ne correspond pas à son type MIME déclaré.",
      };
      const motif = motifs[fileValidation.code];
      const applique = await appliquerVerdict(false, {
        verdict_final: 'REJETE',
        motif,
        controle_fichier: fileValidation.code,
        regle_version: '2026-07-14',
      });
      if (!applique) return sourceChangee();
      return json(200, { ok: true, verdict: 'REJETE', motif });
    }
    const base64 = toBase64(arrayBuffer);
    const mime = fileValidation.mime;
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
  "document_complet": true/false,
  "score_confiance": 0-100,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "indices_falsification": ["liste des indices de falsification/retouche détectés"] ou [],
  "motif_rejet": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- verdict = "VERIFIE" si c'est bien une pièce d'identité officielle (CNI, passeport, titre de séjour), lisible, complète, non expirée et confiance HAUTE.
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
      const applique = await appliquerVerdict(false, {
        erreur_anthropic: { status: estTimeout ? 'timeout' : 'network', at: new Date().toISOString() },
      });
      if (!applique) return sourceChangee();
      return json(200, { ok: true, verdict: 'EN_ATTENTE', reason: estTimeout ? 'AI timeout' : 'AI network error' });
    }

    if (!ai.ok) {
      const applique = await appliquerVerdict(false, {
        erreur_anthropic: { status: ai.status, body_excerpt: ai.body.slice(0, 1000), at: new Date().toISOString() },
      });
      if (!applique) return sourceChangee();
      return json(200, { ok: false, verdict: 'EN_ATTENTE', error: `Anthropic ${ai.status}` });
    }

    const aiJson = ai.data;
    const text = (aiJson?.content || []).map((c: any) => c?.text || '').join('\n');
    const result = parseJsonFromText(text) || {};
    // GATE FALSIFICATION : la liste doit être explicitement présente et bien formée.
    const quality = strictAiVerificationQuality(result);
    const indicesFalsif = quality.indicators;
    const nomDeterministe = personNameMatches(
      e.representant_nom,
      e.representant_prenom,
      result.nom_extrait,
      result.prenom_extrait,
    );
    const dateExpiration = normalizeIsoCivilDate(result.date_expiration);
    const expiree = dateExpiration !== null && dateExpiration < new Date().toISOString().slice(0, 10);
    const verdictsAutorises = new Set(['VERIFIE', 'EN_ATTENTE', 'REJETE']);
    let verdict = typeof result.verdict === 'string' && verdictsAutorises.has(result.verdict)
      ? result.verdict
      : 'EN_ATTENTE';
    let motif = typeof result.motif_rejet === 'string' ? result.motif_rejet : null;

    if (verdict === 'VERIFIE' && !quality.antifraudComplete) {
      verdict = 'EN_ATTENTE';
      motif = 'Le contrôle antifraude est absent ou mal formé — vérification manuelle requise.';
    } else if (verdict === 'VERIFIE' && indicesFalsif.length > 0) {
      verdict = 'EN_ATTENTE';
      motif = 'Indices de falsification détectés — vérification manuelle requise.';
    }
    if (verdict === 'VERIFIE' && (
      result.type_correspond !== true || result.document_lisible !== true ||
      result.document_complet !== true || !quality.highConfidence ||
      result.nom_correspond !== true || nomDeterministe !== true || dateExpiration === null
    )) {
      verdict = 'EN_ATTENTE';
      motif = nomDeterministe === false || result.nom_correspond === false
        ? "Le nom de la pièce ne correspond pas au représentant déclaré."
        : dateExpiration === null
          ? "La date d'expiration n'a pas pu être lue : vérification manuelle requise."
          : "L'identité, le type ou la lisibilité doit être confirmé manuellement.";
    }
    if (verdict === 'VERIFIE' && expiree) {
      verdict = 'REJETE';
      motif = "La pièce d'identité est expirée.";
    }

    const nomCorrespond = result.nom_correspond === true && nomDeterministe === true;
    const identiteVerifiee = verdict === 'VERIFIE' && nomCorrespond;

    const applique = await appliquerVerdict(identiteVerifiee, {
        verdict_final: verdict,
        motif,
        type_correspond: result.type_correspond === true,
        nom_extrait: result.nom_extrait ?? null,
        prenom_extrait: result.prenom_extrait ?? null,
        date_expiration: dateExpiration,
        document_lisible: result.document_lisible === true,
        document_complet: result.document_complet === true,
        score_confiance: quality.score,
        confiance: quality.confidence,
        antifraude_complete: quality.antifraudComplete,
        indices_falsification_count: indicesFalsif.length,
        regle_version: '2026-07-14',
    });
    if (!applique) return sourceChangee();

    // Évalue le rattachement adaptatif (AUTO_DIRIGEANT / EMAIL_PRO / ADMIN)
    let rattachement: any = null;
    try {
      const { data: rat, error: ratError } = await admin.rpc('fn_evaluer_rattachement_etablissement', { p_etablissement_id: etablissementId });
      if (ratError) throw ratError;
      rattachement = rat;
    } catch (ratError) { console.error('[verify-piece-identite-etab] rattachement', String(ratError)); }

    return json(200, {
      ok: true,
      verdict,
      motif,
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
