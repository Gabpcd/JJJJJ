export const TYPES_DOCUMENTS: Record<string, string> = {
  'CARTE_IDENTITE': 'Carte d\'identité / Passeport',
  'PASSEPORT': 'Passeport',
  'TITRE_SEJOUR': 'Titre de séjour',
  'DIPLOME': 'Diplôme d\'État',
  'ATTESTATION_SCOLARITE': 'Attestation de scolarité / passage en année supérieure (étudiant)',
  'LICENCE_REMPLACEMENT': 'Licence de remplacement (interne en médecine — Ordre des médecins)',
  'RPPS_ADELI': 'Attestation RPPS / ADELI',
  'RCP_ASSURANCE': 'Assurance RCP',
  'VACCINATIONS': 'Carnet de vaccination',
  'CASIER_JUDICIAIRE': 'Extrait de casier judiciaire',
  'RIB': 'RIB',
  'KBIS': 'KBIS',
  'ATTESTATION_URSSAF': 'Attestation URSSAF',
  'AUTORISATION_EXERCICE': 'Autorisation d\'exercice',
  'MEDECINE_TRAVAIL': 'Médecine du travail',
  'FORMATION_OBLIGATOIRE': 'Formation obligatoire',
  'AUTRE': 'Autre document',
};

/** Types de documents exclus du téléversement (attestation sur l'honneur à la place) */
export const TYPES_DOCUMENTS_EXCLUS_UPLOAD: string[] = ['VACCINATIONS', 'MEDECINE_TRAVAIL'];

export const STATUTS_VERIFICATION: Record<string, { label: string; couleur: string }> = {
  'EN_ATTENTE': { label: 'En attente de vérification', couleur: 'bg-amber-100 text-amber-700' },
  'VERIFIE': { label: 'Vérifié ✓', couleur: 'bg-emerald-100 text-emerald-700' },
  'REJETE': { label: 'Rejeté ✗', couleur: 'bg-red-100 text-red-700' },
  'EXPIRE': { label: 'Expiré ⏰', couleur: 'bg-red-200 text-red-800' },
  'REVUE_MANUELLE_REQUISE': { label: 'En cours de vérification', couleur: 'bg-blue-100 text-blue-700' },
  'API_INDISPONIBLE': { label: 'Vérification temporairement indisponible', couleur: 'bg-gray-100 text-gray-600' },
};
