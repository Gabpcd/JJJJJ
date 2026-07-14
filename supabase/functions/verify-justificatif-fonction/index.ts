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
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { canManageEstablishment } from '../_shared/etablissement-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import {
  corporateNameMatches,
  normalizeProfessionalIdentifier,
  personNameMatches,
  strictAiVerificationQuality,
  validateDocumentFile,
} from '../_shared/verification-rules.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { resolveEstablishmentReview } from '../_shared/establishment-review.ts';

type EstablishmentReviewClient = Parameters<typeof resolveEstablishmentReview>[0];

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

  let failureAdmin: EstablishmentReviewClient | null = null;
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
    failureAdmin = admin as unknown as EstablishmentReviewClient;
    failureEtablissementId = etablissementId;

    if (!auth.isServiceRole) {
      if (applyRateLimit('verify-justificatif-fonction', getClientIp(req), { max: 8, windowMs: 60_000 })) {
        return json(429, { ok: false, code: 'RATE_LIMITED', error: 'Trop de vérifications. Réessayez dans une minute.' });
      }
      if (!(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return json(403, { ok: false, code: 'FORBIDDEN', error: 'Non autorisé pour cet établissement' });
      }
    }

    const { data: etab, error: etabErr } = await admin.from('etablissements')
      .select('verification_source_version, nom, siret, siret_raison_sociale, finess_raison_sociale, representant_nom, representant_prenom, justificatif_fonction_s3_key, justificatif_fonction_type, justificatif_fonction_type_mime')
      .eq('id', etablissementId).maybeSingle();
    if (etabErr) {
      console.error('[verify-justificatif-fonction] lecture établissement', etabErr.code || etabErr.message);
      return json(503, { ok: false, code: 'ETABLISSEMENT_READ_FAILED', error: 'Vérification temporairement indisponible' });
    }
    if (!etab) return json(404, { ok: false, code: 'ETABLISSEMENT_NOT_FOUND', error: 'Établissement introuvable' });
    const e = etab as Record<string, any>;
    failureSourceSnapshot = {
      verification_source_version: Number(e.verification_source_version),
      justificatif_fonction_s3_key: e.justificatif_fonction_s3_key ?? null,
      justificatif_fonction_type: e.justificatif_fonction_type ?? null,
      justificatif_fonction_type_mime: e.justificatif_fonction_type_mime ?? null,
      representant_nom: e.representant_nom ?? null,
      representant_prenom: e.representant_prenom ?? null,
      nom: e.nom ?? null,
      siret: e.siret ?? null,
      siret_raison_sociale: e.siret_raison_sociale ?? null,
      finess_raison_sociale: e.finess_raison_sociale ?? null,
    };
    const appliquerVerdict = async (verifie: boolean, resultat: Record<string, unknown>) => {
      if (!auth.isServiceRole && !(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return false;
      }
      const { data, error } = await admin.rpc(
        'fn_appliquer_verification_fonction_etablissement',
        {
          p_etablissement_id: etablissementId,
          p_version_attendue: Number(e.verification_source_version),
          p_justificatif_s3_key: e.justificatif_fonction_s3_key ?? null,
          p_justificatif_type: e.justificatif_fonction_type ?? null,
          p_justificatif_type_mime: e.justificatif_fonction_type_mime ?? null,
          p_representant_nom: e.representant_nom ?? null,
          p_representant_prenom: e.representant_prenom ?? null,
          p_nom_etablissement: e.nom ?? null,
          p_siret: e.siret ?? null,
          p_siret_raison_sociale: e.siret_raison_sociale ?? null,
          p_finess_raison_sociale: e.finess_raison_sociale ?? null,
          p_verifie: verifie,
          p_resultat: resultat,
        },
      );
      if (error) throw new Error(`Persistance atomique justificatif impossible: ${error.code || error.message}`);
      return data === true;
    };
    const sourceChangee = () => json(409, {
      ok: false,
      code: 'VERIFICATION_SOURCE_CHANGED',
      error: 'Le justificatif ou le profil a changé pendant la vérification. Relancez le contrôle.',
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
          p_service: 'VERIFY_JUSTIFICATIF_FONCTION',
          p_source_snapshot: failureSourceSnapshot,
          p_motif: motif,
          p_cause: cause,
          p_resultat: resultat,
        },
      );
      const payload = data && typeof data === 'object' ? data as Record<string, unknown> : {};
      if (error) {
        console.error('[verify-justificatif-fonction] revue atomique', error.code || error.message);
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
    if (!e.justificatif_fonction_s3_key) {
      return json(400, { ok: false, code: 'DOCUMENT_REQUIRED', error: 'Aucun justificatif de fonction téléversé' });
    }
    const justificatifPath = String(e.justificatif_fonction_s3_key);
    const proprietairesAutorises = new Set(
      [etablissementId, auth.userId].filter((value): value is string => !!value),
    );
    const cheminAutorise = !justificatifPath.includes('..')
      && !justificatifPath.includes('\\')
      && [...proprietairesAutorises].some((ownerId) => justificatifPath.startsWith(`${ownerId}/`));
    if (!cheminAutorise) return json(403, { ok: false, code: 'DOCUMENT_PATH_FORBIDDEN', error: 'Chemin de justificatif non autorisé' });
    if (!e.representant_nom || !e.representant_prenom) {
      return json(400, { ok: false, code: 'REPRESENTATIVE_IDENTITY_REQUIRED', error: 'Nom et prénom du représentant requis' });
    }
    const { data: file, error: dlErr } = await admin.storage.from('jolene-documents').download(justificatifPath);
    if (dlErr || !file) {
      return mettreEnRevue(
        'Le justificatif téléversé est momentanément inaccessible ; une revue humaine a été enregistrée.',
        'STORAGE_READ_FAILED',
      );
    }
    const arrayBuffer = await file.arrayBuffer();
    const fileValidation = validateDocumentFile(
      new Uint8Array(arrayBuffer),
      e.justificatif_fonction_type_mime,
    );
    if (!fileValidation.ok) {
      const motifs: Record<string, string> = {
        EMPTY: 'Le justificatif de fonction est vide.',
        TOO_LARGE: 'Le justificatif de fonction dépasse 10 Mo.',
        UNSUPPORTED_MIME: 'Le type MIME déclaré du justificatif est absent ou non autorisé.',
        INVALID_SIGNATURE: 'Le contenu du justificatif ne correspond pas à son type MIME déclaré.',
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

    const nomComplet = `${e.representant_prenom || ''} ${e.representant_nom}`.trim();

    const systemPrompt = `Tu es un vérificateur de justificatifs de fonction pour une marketplace de santé.
Le document doit prouver qu'une personne physique est habilitée à représenter un établissement de santé
(elle n'est pas forcément le dirigeant : RH, chef de service, délégataire). Réponds UNIQUEMENT en JSON valide:
{
  "est_justificatif_fonction": true/false,
  "type_detecte": "ATTESTATION_EMPLOYEUR" | "DELEGATION_SIGNATURE" | "FICHE_POSTE" | "CONTRAT_TRAVAIL" | "DECISION_NOMINATION" | "AUTRE" | null,
  "nom_correspond": true/false/null,
  "nom_extrait": "le nom de la personne lu sur le document" ou null,
  "prenom_extrait": "le prénom de la personne lu sur le document" ou null,
  "fonction_detectee": "la fonction/le poste mentionné" ou null,
  "autorise_representation": true/false/null,
  "etablissement_correspond": true/false/null,
  "etablissement_extrait": "le nom de l'établissement lu sur le document" ou null,
  "siret_extrait": "les 14 chiffres du SIRET lu sur le document" ou null,
  "document_lisible": true/false,
  "document_complet": true/false,
  "score_confiance": 0-100,
  "confiance": "HAUTE"/"MOYENNE"/"FAIBLE",
  "indices_falsification": ["liste des indices de falsification/retouche"] ou [],
  "motif_rejet": null ou "string",
  "verdict": "VERIFIE"/"EN_ATTENTE"/"REJETE"
}
Règles:
- verdict = "VERIFIE" UNIQUEMENT pour une délégation de signature/pouvoir ou une décision de nomination explicite,
  officielle et lisible, confiance HAUTE, qui autorise bien la représentation, avec nom_correspond = true
  (la personne déclarée) et etablissement_correspond = true (le bon établissement).
- Une attestation employeur, fiche de poste ou contrat de travail prouve un emploi mais pas, à elle seule,
  le pouvoir de représenter l'établissement : verdict = "EN_ATTENTE" pour revue humaine.
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
      return mettreEnRevue(
        estTimeout
          ? 'L’analyse automatique a dépassé le délai prévu ; le document a été transmis en revue humaine.'
          : 'L’analyse automatique est momentanément indisponible ; le document a été transmis en revue humaine.',
        estTimeout ? 'AI_TIMEOUT' : 'AI_NETWORK_ERROR',
        { erreur_anthropic: { status: estTimeout ? 'timeout' : 'network', at: new Date().toISOString() } },
      );
    }
    clearTimeout(aiTimeout);

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
    const personneMatch = personNameMatches(
      e.representant_nom,
      e.representant_prenom,
      result.nom_extrait,
      result.prenom_extrait,
    );
    const nomsOfficiels = [e.siret_raison_sociale, e.finess_raison_sociale, e.nom].filter(Boolean);
    const etablissementNomMatch = nomsOfficiels.some((nomAttendu) =>
      corporateNameMatches(nomAttendu, result.etablissement_extrait) === true
    );
    const siretExtrait = normalizeProfessionalIdentifier(result.siret_extrait);
    const siretMatch = siretExtrait.length === 14
      ? siretExtrait === normalizeProfessionalIdentifier(e.siret)
      : null;
    // Un SIRET explicitement lu et contradictoire est toujours bloquant, même
    // si le nom commercial ressemble à celui de l'établissement.
    const etablissementDeterministe = siretMatch !== false && (etablissementNomMatch || siretMatch === true);
    const typeHabilitant = ['DELEGATION_SIGNATURE', 'DECISION_NOMINATION'].includes(String(result.type_detecte || ''));
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
    if (siretMatch === false) {
      verdict = 'REJETE';
      motif = "Le SIRET lu sur le justificatif contredit le SIRET vérifié de l'établissement.";
    }
    if (verdict === 'VERIFIE' && (
      result.est_justificatif_fonction !== true || result.document_lisible !== true ||
      result.document_complet !== true || !quality.highConfidence ||
      result.nom_correspond !== true || personneMatch !== true ||
      result.etablissement_correspond !== true || !etablissementDeterministe ||
      !typeHabilitant || result.autorise_representation !== true
    )) {
      verdict = 'EN_ATTENTE';
      motif = personneMatch === false || result.nom_correspond === false
        ? "Le justificatif ne correspond pas au représentant déclaré."
        : (siretMatch === false || result.etablissement_correspond === false)
          ? "Le justificatif ne correspond pas à l'établissement déclaré."
          : !typeHabilitant || result.autorise_representation !== true
            ? "Le document prouve peut-être un emploi, mais pas un pouvoir explicite de représentation : revue manuelle requise."
            : "Le lien entre la personne, sa fonction et l'établissement doit être confirmé manuellement.";
    }
    const justificatifVerifie = verdict === 'VERIFIE'
      && result.nom_correspond === true
      && personneMatch === true
      && result.etablissement_correspond === true
      && etablissementDeterministe
      && typeHabilitant
      && result.autorise_representation === true;

    const resultatPersistant = {
      verdict_final: verdict,
      motif,
      type_detecte: result.type_detecte ?? null,
      autorise_representation: result.autorise_representation === true,
      nom_extrait: result.nom_extrait ?? null,
      prenom_extrait: result.prenom_extrait ?? null,
      fonction_detectee: result.fonction_detectee ?? null,
      etablissement_extrait: result.etablissement_extrait ?? null,
      siret_extrait: siretExtrait || null,
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

    const applique = await appliquerVerdict(justificatifVerifie, resultatPersistant);
    if (!applique) return sourceChangee();

    if (justificatifVerifie) {
      await resolveEstablishmentReview(
        admin as unknown as EstablishmentReviewClient,
        etablissementId,
        'VERIFY_JUSTIFICATIF_FONCTION',
      );
    }

    // Ré-évalue le rattachement adaptatif (→ JUSTIFICATIF si OK).
    let rattachement: any = null;
    try {
      const { data: rat, error: ratError } = await admin.rpc('fn_evaluer_rattachement_etablissement', { p_etablissement_id: etablissementId });
      if (ratError) throw ratError;
      rattachement = rat;
    } catch (ratError) { console.error('[verify-justificatif-fonction] rattachement', String(ratError)); }

    return json(200, {
      ok: true,
      verdict,
      motif,
      nom_correspond: result.nom_correspond ?? null,
      etablissement_correspond: result.etablissement_correspond ?? null,
      fonction_detectee: result.fonction_detectee ?? null,
      justificatif_verifie: justificatifVerifie,
      rattachement,
    });
  } catch (e) {
    console.error('[verify-justificatif-fonction] erreur inattendue', String(e).slice(0, 300));
    if (failureAdmin && failureEtablissementId && failureSourceSnapshot) {
      try {
        const { data, error } = await failureAdmin.rpc(
          'fn_mettre_preuve_etablissement_en_revue_atomique',
          {
            p_etablissement_id: failureEtablissementId,
            p_service: 'VERIFY_JUSTIFICATIF_FONCTION',
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
        console.error('[verify-justificatif-fonction] revue après erreur', String(reviewError));
      }
    }
    return json(500, { ok: false, code: 'INTERNAL_ERROR', error: 'Vérification temporairement indisponible. Réessayez.' });
  }
});
