export const LITIGE_ADMIN_TYPES = [
  { value: 'DESACCORD_HEURES_POINTAGE', label: 'Heures ou pointage' },
  { value: 'DESACCORD_MONTANT_FACTURE', label: 'Montant ou facture' },
  { value: 'NON_PAIEMENT', label: 'Paiement non reçu' },
  { value: 'FRAIS_COMPLEMENTAIRES', label: 'Frais complémentaires' },
  { value: 'ABSENCE_SOIGNANT', label: 'Absence du soignant' },
  { value: 'RETARD_IMPORTANT', label: 'Retard important' },
  { value: 'DEPART_ANTICIPE', label: 'Départ anticipé' },
  { value: 'CONDITIONS_MISSION_NON_RESPECTEES', label: 'Conditions de mission' },
  { value: 'SECURITE_DANGER', label: 'Sécurité ou danger' },
  { value: 'COMPORTEMENT_SOIGNANT', label: 'Comportement du soignant' },
  { value: 'COMPORTEMENT_ETABLISSEMENT', label: "Comportement de l’établissement" },
  { value: 'AUTRE', label: 'Autre' },
] as const;

export type LitigeAdminType = (typeof LITIGE_ADMIN_TYPES)[number]['value'];
