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
  { valeur: 'PHARMACIE_OFFICINE', label: 'Pharmacie d\'Officine' },
] as const;

// Professions NON éligibles au libéral
export const PROFESSIONS_NON_LIBERAL = ['PHARMACIEN', 'PREPARATEUR_PHARMA', 'AS', 'AES', 'MANIPULATEUR_RADIO'];

// Professions sans RPPS (ADELI uniquement)
export const PROFESSIONS_SANS_RPPS = ['AS', 'AES'];

// Professions limitées pour pharmacies
export const PROFESSIONS_PHARMACIE = ['PHARMACIEN', 'PREPARATEUR_PHARMA'];

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

// ─── Contract type tags in mission description ───
export type ContratPreference = 'TOUS' | 'SALARIE' | 'LIBERAL';

export function extraireContratPreference(description: string | null): ContratPreference {
  if (!description) return 'TOUS';
  const match = description.match(/\[CONTRAT:(TOUS|SALARIE|LIBERAL)\]/);
  return (match?.[1] as ContratPreference) || 'TOUS';
}

export function injecterContratTag(description: string, pref: ContratPreference): string {
  // Remove existing tag
  const cleaned = description.replace(/\[CONTRAT:(TOUS|SALARIE|LIBERAL)\]\s*/g, '').trim();
  if (pref === 'TOUS') return cleaned; // no tag needed for default
  return `[CONTRAT:${pref}] ${cleaned}`.trim();
}

export function getContratBadge(pref: ContratPreference): { label: string; classes: string } {
  switch (pref) {
    case 'LIBERAL': return { label: '🏥 Libéral', classes: 'bg-purple-100 text-purple-700' };
    case 'SALARIE': return { label: '💼 Salarié', classes: 'bg-primary/10 text-primary' };
    default: return { label: '👥 Tous profils', classes: 'bg-muted text-muted-foreground' };
  }
}

export function getTypeContratRechercheBadge(type: string): { label: string; classes: string } {
  switch (type) {
    case 'LIBERAL': return { label: '🏥 Libéral', classes: 'bg-purple-100 text-purple-700' };
    case 'SALARIE': return { label: '💼 Salarié', classes: 'bg-primary/10 text-primary' };
    default: return { label: '👥 Tous profils', classes: 'bg-muted text-muted-foreground' };
  }
}

export function missionCompatibleContrat(pref: ContratPreference | string, typesContratSoignant: string[]): boolean {
  if (!pref || pref === 'TOUS') return true;
  if (pref === 'LIBERAL') return typesContratSoignant.includes('LIBERAL');
  if (pref === 'SALARIE') return typesContratSoignant.some(t => ['CDDU', 'CDDU_USAGE', 'VACATION', 'SALARIE'].includes(t));
  return true;
}

/** Parse the types_contrat_acceptes (JSON array or comma-separated) or fall back to type_exercice/type_contrat */
export function getTypesContratSoignant(soignant: { type_contrat?: string | null; types_contrat_acceptes?: string | null; type_exercice?: string | null }): string[] {
  if (soignant.types_contrat_acceptes) {
    // Handle both JSON array and comma-separated string
    const raw = soignant.types_contrat_acceptes.trim();
    if (raw.startsWith('[')) {
      try {
        const arr = JSON.parse(raw);
        if (Array.isArray(arr) && arr.length > 0) return arr;
      } catch { /* fallback to comma split */ }
    }
    // Comma-separated: "CDDU,LIBERAL"
    const parts = raw.split(',').map(s => s.trim()).filter(Boolean);
    if (parts.length > 0) return parts;
  }
  // Fallback based on type_exercice
  if (soignant.type_exercice === 'MIXTE') return ['CDDU', 'LIBERAL'];
  if (soignant.type_exercice === 'LIBERAL') return ['LIBERAL'];
  return soignant.type_contrat ? [soignant.type_contrat] : ['CDDU'];
}
