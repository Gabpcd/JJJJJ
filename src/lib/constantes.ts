export const PROFESSIONS = [
  { valeur: 'IDE', label: "Infirmier(ère) Diplômé(e) d'État (IDE)" },
  { valeur: 'AS', label: 'Aide-Soignant(e) (AS)' },
  { valeur: 'AES', label: 'Accompagnant Éducatif et Social (AES)' },
  { valeur: 'IBODE', label: 'Infirmier(ère) de Bloc Opératoire (IBODE)' },
  { valeur: 'IADE', label: 'Infirmier(ère) Anesthésiste (IADE)' },
  { valeur: 'SAGE_FEMME', label: 'Sage-Femme' },
  { valeur: 'KINE', label: 'Kinésithérapeute' },
  { valeur: 'MEDECIN', label: 'Médecin' },
  { valeur: 'PHARMACIEN', label: 'Pharmacien(ne)' },
  { valeur: 'MANIPULATEUR_RADIO', label: 'Manipulateur Radio' },
  { valeur: 'PREPARATEUR_PHARMA', label: 'Préparateur en Pharmacie' },
  { valeur: 'DIETETICIEN', label: 'Diététicien(ne)' },
  { valeur: 'ERGOTHERAPEUTE', label: 'Ergothérapeute' },
  { valeur: 'PSYCHOMOTRICIEN', label: 'Psychomotricien(ne)' },
  { valeur: 'ORTHOPHONISTE', label: 'Orthophoniste' },
] as const;

export const CONTRATS = [
  { valeur: 'CDDU', label: "CDD d'Usage (CDDU)" },
  { valeur: 'INTERIM', label: 'Intérim' },
  { valeur: 'VACATION', label: 'Vacation' },
  { valeur: 'LIBERAL', label: 'Libéral' },
  { valeur: 'SALARIE', label: 'Salarié' },
] as const;

export const TYPES_ETABLISSEMENT = [
  { valeur: 'HOPITAL_PUBLIC', label: 'Hôpital Public' },
  { valeur: 'CLINIQUE_PRIVEE', label: 'Clinique Privée' },
  { valeur: 'EHPAD', label: 'EHPAD' },
  { valeur: 'SSIAD', label: 'SSIAD' },
  { valeur: 'HAD', label: 'HAD' },
  { valeur: 'CENTRE_SANTE', label: 'Centre de Santé' },
  { valeur: 'LABO', label: 'Laboratoire' },
  { valeur: 'IME', label: 'IME' },
  { valeur: 'MAS', label: 'MAS' },
  { valeur: 'FAM', label: 'FAM' },
] as const;

export const BADGES_STATUT: Record<string, { label: string; classes: string }> = {
  'OUVERTE': { label: 'Ouverte', classes: 'bg-primary/10 text-primary' },
  'ASSIGNEE': { label: 'Assignée', classes: 'bg-warning/10 text-warning' },
  'EN_COURS': { label: 'En cours', classes: 'bg-info/10 text-info' },
  'TERMINEE': { label: 'Terminée', classes: 'bg-success/10 text-success' },
  'ANNULEE_PAR_ETABLISSEMENT': { label: 'Annulée', classes: 'bg-muted text-muted-foreground' },
  'ANNULEE_PAR_SOIGNANT': { label: 'Annulée (soignant)', classes: 'bg-destructive/10 text-destructive' },
  'ABSENCE': { label: 'Absence', classes: 'bg-destructive/20 text-destructive' },
  'LITIGE': { label: 'Litige', classes: 'bg-purple-100 text-purple-700' },
};

export function getLabelProfession(valeur: string): string {
  return PROFESSIONS.find(p => p.valeur === valeur)?.label || valeur;
}

export function getLabelContrat(valeur: string): string {
  return CONTRATS.find(c => c.valeur === valeur)?.label || valeur;
}

export function getLabelTypeEtablissement(valeur: string): string {
  return TYPES_ETABLISSEMENT.find(t => t.valeur === valeur)?.label || valeur;
}
