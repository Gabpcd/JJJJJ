import { documentsComplementairesVisibles } from '../../../../src/lib/documents-complementaires';
import { diplomeCompatibleProfession, TYPES_DOCUMENTS, TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '../../../../src/lib/documents';
import type { CaregiverDocument, DocumentDossier, DocumentRequirement } from '../../workflows/documents/types';

export const documentTitle = (type: string) => TYPES_DOCUMENTS[type] ?? type;
export const displayDate = (value: string | null) => value && Number.isFinite(Date.parse(value))
  ? new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Paris' }).format(new Date(value)) : null;
const dateIsFuture = (value: string | null, now: number) => !value || (Number.isFinite(Date.parse(value)) && Date.parse(value) > now);

/** Presentation only: this count never grants eligibility to apply or accept a mission. */
export function documentProgress(dossier: DocumentDossier, now: number) {
  const required = dossier.requirements.filter(rule => rule.est_critique);
  const valid = required.filter(rule => dossier.documents.some(doc => doc.type_document === rule.type_document
    && doc.statut_verification === 'VERIFIE' && dateIsFuture(doc.valide_jusqua, now)
    && (rule.type_document !== 'DIPLOME' || diplomeCompatibleProfession(dossier.profile?.profession, doc.profession_certifiee))));
  return { total: required.length, valid: valid.length,
    next: required.find(rule => !valid.some(done => done.type_document === rule.type_document)) ?? null };
}

export function documentPresentation(doc: CaregiverDocument, profession: string | null, now: number) {
  // A rejection remains a rejection even if an extracted expiry is also in the past.
  if (doc.statut_verification === 'REJETE') return { label: 'Rejeté', tone: 'danger' as const, reverify: true, review: true,
    explanation: `Document non valide${doc.motif_rejet ? ` — ${doc.motif_rejet}` : ''}. Tu peux le remplacer ou demander une revue humaine.` };
  if (doc.statut_verification === 'EXPIRE' || (doc.valide_jusqua && Number.isFinite(Date.parse(doc.valide_jusqua)) && Date.parse(doc.valide_jusqua) <= now)) {
    return { label: 'Expiré', tone: 'danger' as const, reverify: true, review: false,
      explanation: 'Ce document doit être renouvelé. Tu peux téléverser un document récent.' };
  }
  if (doc.type_document === 'DIPLOME' && doc.statut_verification === 'VERIFIE' && !diplomeCompatibleProfession(profession, doc.profession_certifiee)) {
    return { label: 'Qualification à confirmer', tone: 'pending' as const, reverify: true, review: false,
      explanation: `La qualification ${profession ?? ''} n’est pas confirmée par ce diplôme. Tu peux le remplacer ou demander une nouvelle vérification.` };
  }
  switch (doc.statut_verification) {
    case 'VERIFIE': return { label: 'Vérifié', tone: 'success' as const, reverify: false, review: false, explanation: null };
    case 'EN_ATTENTE': return { label: 'En attente de vérification', tone: 'pending' as const, reverify: true, review: true,
      explanation: 'Analyse non conclue — revue humaine disponible.' };
    case 'REVUE_MANUELLE_REQUISE': return { label: 'En cours de vérification', tone: 'pending' as const, reverify: true, review: false,
      explanation: 'Demande reçue — en attente d’attribution à un membre de l’équipe pour la revue humaine.' };
    case 'API_INDISPONIBLE': return { label: 'Vérification temporairement indisponible', tone: 'pending' as const, reverify: true, review: true,
      explanation: 'Tu peux réessayer la vérification ou demander une revue humaine.' };
    default: return { label: 'Statut à actualiser', tone: 'pending' as const, reverify: false, review: false,
      explanation: 'Le statut reçu n’est pas reconnu par cet écran. Actualise pour vérifier le dossier.' };
  }
}

/** Includes the same additional student documents as the current web screen. */
export function documentRows(dossier: DocumentDossier): DocumentRequirement[] {
  const rows = dossier.requirements.filter(rule => !TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(rule.type_document));
  const unique = new Map(rows.map(row => [row.type_document, row]));
  if (dossier.profile) {
    const visibles = documentsComplementairesVisibles(dossier.profile);
    const extras = [
      ['ATTESTATION_SCOLARITE', 'L’analyse prépare ton dossier, puis l’équipe Jolene contrôle les crédits, stages, unités d’enseignement et attestations exigés avant d’ouvrir une pré-éligibilité.'],
      ['LICENCE_REMPLACEMENT', 'Interne ? Téléverse ta licence de remplacement délivrée par le Conseil de l’Ordre : elle est contrôlée avant tout accès aux remplacements de médecin.'],
      ['CARTE_ORDRE', 'Tu es désormais médecin inscrit à l’Ordre ? Ajoute l’attestation précisant ta qualification pour que l’équipe mette à jour ton parcours après vérification.'],
    ];
    for (const [type, description] of extras) if ((type === 'ATTESTATION_SCOLARITE' ? visibles.scolarite : type === 'LICENCE_REMPLACEMENT' ? visibles.licence : visibles.qualification) && !unique.has(type)) unique.set(type, {
      id: `additional-${type}`, profession: dossier.profile.profession ?? '', type_document: type, description,
      a_expiration: type !== 'CARTE_ORDRE', duree_validite_mois: null, est_critique: false, type_exercice_requis: 'TOUS',
    });
  }
  return [...unique.values()].sort((a, b) => Number(b.est_critique) - Number(a.est_critique));
}
