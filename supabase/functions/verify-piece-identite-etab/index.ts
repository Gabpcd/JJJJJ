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
import {
  openEstablishmentReview,
  resolveEstablishmentReview,
} from '../_shared/establishment-review.ts';

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

  let failureAdmin: Parameters<typeof openEstablishmentReview>[0] | null = null;
  let failureEtablissementId = '';
  let failureSourceSnapshot: Record<string, unknown> | null = null;

  try {
    if (req.method !== 'POST') {
      return json(405, { ok: false, code: 'METHOD_NOT_ALLOWED', error: 'Méthode non autorisée' });
    }
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return json(auth.status, { ok: false, code: 'UNAUTHORIZED', error: auth.error });
    const body = await req.json().catch(() => ({}));
    if (body?.warm === true) {
      if (!auth.isServiceRole) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return json(adminAuth.status, { ok: false, code: 'FORBIDDEN', error: adminAuth.error });
      }
      return json(200, { ok: true, warm: true, configured: !!Deno.env.get('ANTHROPIC_API_KEY') });
    }

    const etablissementId = String(body?.etablissement_id || '').trim();
    if (!etablissementId) return json(400, { ok: false, code: 'ETABLISSEMENT_ID_REQUIRED', error: 'etablissement_id requis' });

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!supabaseUrl || !serviceKey) {
      return json(503, { ok: false, code: 'SERVER_NOT_CONFIGURED', error: 'Service temporairement indisponible' });
    }
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    failureAdmin = admin as unknown as Parameters<typeof openEstablishmentReview>[0];
    failureEtablissementId = etablissementId;

    if (!auth.isServiceRole) {
      if (applyRateLimit('verify-piece-identite-etab', getClientIp(req), { max: 8, windowMs: 60_000 })) {
        return json(429, { ok: false, code: 'RATE_LIMITED', error: 'Trop de vérifications. Réessayez dans une minute.' });
      }
      if (!(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return json(403, { ok: false, code: 'FORBIDDEN', error: 'Non autorisé pour cet établissement' });
      }
    }

    const { data: etab, error: etabErr } = await admin.from('etablissements')
      .select('verification_source_version, representant_nom, representant_prenom, representant_piece_s3_key, representant_piece_type_mime, representant_piece_type_document')
      .eq('id', etablissementId).maybeSingle();
    if (etabErr) {
      console.error('[verify-piece-identite-etab] lecture établissement', etabErr.code || etabErr.message);
      return json(503, { ok: false, code: 'ETABLISSEMENT_READ_FAILED', error: 'Vérification temporairement indisponible' });
    }
    if (!etab) return json(404, { ok: false, code: 'ETABLISSEMENT_NOT_FOUND', error: 'Établissement introuvable' });
    const e = etab as Record<string, any>;
    failureSourceSnapshot = {
      verification_source_version: Number(e.verification_source_version),
      representant_piece_s3_key: e.representant_piece_s3_key ?? null,
      representant_piece_type_mime: e.representant_piece_type_mime ?? null,
      representant_piece_type_document: e.representant_piece_type_document ?? null,
      representant_nom: e.representant_nom ?? null,
      representant_prenom: e.representant_prenom ?? null,
    };
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
    const mettreEnRevue = async (
      motif: string,
      cause: string,
      resultat: Record<string, unknown> = {},
    ): Promise<Response> => {
      if (!auth.isServiceRole && !(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return json(403, { ok: false, code: 'AUTHORIZATION_CHANGED', error: 'Autorisation modifiée pendant la vérification.' });
      }
      const { data, error } = await admin.rpc(
        'fn_mettre_preuve_etablissement_en_revue_atomique',
        {
          p_etablissement_id: etablissementId,
          p_service: 'VERIFY_PIECE_IDENTITE_ETAB',
          p_source_snapshot: failureSourceSnapshot,
          p_motif: motif,
          p_cause: cause,
          p_resultat: resultat,
        },
      );
      const payload = data && typeof data === 'object' ? data as Record<string, unknown> : {};
      if (error) {
        console.error('[verify-piece-identite-etab] revue atomique', error.code || error.message);
        return json(503, {
          ok: false,
          code: 'REVIEW_QUEUE_FAILED',
          error: 'La vérification automatique a échoué et la revue n’a pas pu être enregistrée. Réessayez.',
        });
      }
      if (payload.success !== true) return sourceChangee();
      return json(202, {
        ok: true,
        verdict: 'EN_ATTENTE',
        motif,
        revue_manuelle: true,
        revue_id: payload.revue_id,
      });
    };
    if (!e.representant_piece_s3_key) {
      return json(400, { ok: false, code: 'DOCUMENT_REQUIRED', error: 'Aucune pièce d\'identité téléversée' });
    }
    const piecePath = String(e.representant_piece_s3_key);
    const proprietairesAutorises = new Set(
      [etablissementId, auth.userId].filter((value): value is string => !!value),
    );
    const cheminAutorise = !piecePath.includes('..')
      && !piecePath.includes('\\')
      && [...proprietairesAutorises].some((ownerId) => piecePath.startsWith(`${ownerId}/`));
    if (!cheminAutorise) return json(403, { ok: false, code: 'DOCUMENT_PATH_FORBIDDEN', error: 'Chemin de pièce d\'identité non autorisé' });
    if (!e.representant_nom || !e.representant_prenom) {
      return json(400, { ok: false, code: 'REPRESENTATIVE_IDENTITY_REQUIRED', error: 'Nom et prénom du représentant requis' });
    }
    // Téléchargement du fichier
    const { data: file, error: dlErr } = await admin.storage.from('jolene-documents').download(piecePath);
    if (dlErr || !file) {
      return mettreEnRevue(
        'La pièce téléversée est momentanément inaccessible ; une revue humaine a été enregistrée.',
        'STORAGE_READ_FAILED',
      );
    }
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

    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!anthropicKey) {
      return mettreEnRevue(
        'L’analyse automatique est momentanément indisponible ; le document a été transmis en revue humaine.',
        'AI_NOT_CONFIGURED',
      );
    }

    const typeLabel = TYPE_LABELS[e.representant_piece_type_document] || "Pièce d'identité";
    const nomComplet = `${e.representant_prenom || ''} ${e.representant_nom}`.trim();

    const systemPrompt = `Tu es un vérificateur de pièces d'identité. Analyse le document et réponds UNIQUEMENT en JSON valide:
{
  "type_correspond": true/false,
  "type_detecte": "string",
  "date_naissance": "YYYY-MM-DD" ou null,
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
      return mettreEnRevue(
        estTimeout
          ? 'L’analyse automatique a dépassé le délai prévu ; le document a été transmis en revue humaine.'
          : 'L’analyse automatique est momentanément indisponible ; le document a été transmis en revue humaine.',
        estTimeout ? 'AI_TIMEOUT' : 'AI_NETWORK_ERROR',
        { erreur_anthropic: { status: estTimeout ? 'timeout' : 'network', at: new Date().toISOString() } },
      );
    }

    if (!ai.ok) {
      return mettreEnRevue(
        'L’analyse automatique est momentanément indisponible ; le document a été transmis en revue humaine.',
        'AI_UPSTREAM_ERROR',
        { erreur_anthropic: { status: ai.status, at: new Date().toISOString() } },
      );
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
    const dateNaissance = normalizeIsoCivilDate(result.date_naissance);
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

    const resultatPersistant = {
      verdict_final: verdict,
      motif,
      type_correspond: result.type_correspond === true,
      nom_extrait: result.nom_extrait ?? null,
      prenom_extrait: result.prenom_extrait ?? null,
      date_naissance_extraite: dateNaissance,
      date_expiration: dateExpiration,
      document_lisible: result.document_lisible === true,
      document_complet: result.document_complet === true,
      score_confiance: quality.score,
      confiance: quality.confidence,
      antifraude_complete: quality.antifraudComplete,
      indices_falsification_count: indicesFalsif.length,
      regle_version: '2026-07-14',
    };

    if (verdict === 'EN_ATTENTE') {
      return mettreEnRevue(
        motif || 'Le document doit être confirmé par l’équipe Jolene avant validation.',
        'AI_REQUIRES_HUMAN_REVIEW',
        resultatPersistant,
      );
    }

    const applique = await appliquerVerdict(identiteVerifiee, resultatPersistant);
    if (!applique) return sourceChangee();

    if (identiteVerifiee) {
      await resolveEstablishmentReview(
        admin,
        etablissementId,
        'VERIFY_PIECE_IDENTITE_ETAB',
      );
    }

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
      date_naissance_extraite: dateNaissance,
      identite_verifiee: identiteVerifiee,
      rattachement,
    });
  } catch (e) {
    console.error('[verify-piece-identite-etab] erreur inattendue', String(e).slice(0, 300));
    if (failureAdmin && failureEtablissementId && failureSourceSnapshot) {
      try {
        const { data, error } = await failureAdmin.rpc(
          'fn_mettre_preuve_etablissement_en_revue_atomique',
          {
            p_etablissement_id: failureEtablissementId,
            p_service: 'VERIFY_PIECE_IDENTITE_ETAB',
            p_source_snapshot: failureSourceSnapshot,
            p_motif: 'La vérification automatique a rencontré une erreur inattendue ; une revue humaine a été enregistrée.',
            p_cause: 'UNEXPECTED_ERROR',
            p_resultat: {},
          },
        );
        const payload = data && typeof data === 'object' ? data as Record<string, unknown> : {};
        if (error || payload.success !== true) throw error || new Error('Revue atomique non appliquée');
        return json(202, {
          ok: true,
          verdict: 'EN_ATTENTE',
          motif: 'La vérification automatique a rencontré une erreur ; le document est en revue humaine.',
          revue_manuelle: true,
          revue_id: payload.revue_id,
        });
      } catch (reviewError) {
        console.error('[verify-piece-identite-etab] revue après erreur', String(reviewError));
      }
    }
    return json(500, { ok: false, code: 'INTERNAL_ERROR', error: 'Vérification temporairement indisponible. Réessayez.' });
  }
});
