export const PROFESSIONS = [
  { valeur: 'IDE', label: "Infirmier(ère) Diplômé(e) d'État (IDE)" },
  { valeur: 'AS', label: 'Aide-Soignant(e) (AS)' },
  { valeur: 'AES', label: 'Accompagnant Éducatif et Social (AES)' },
  { valeur: 'AUXILIAIRE_PUERICULTURE', label: 'Auxiliaire de puériculture' },
  { valeur: 'IBODE', label: 'Infirmier(ère) de Bloc Opératoire (IBODE)' },
  { valeur: 'IADE', label: 'Infirmier(ère) Anesthésiste (IADE)' },
  { valeur: 'SAGE_FEMME', label: 'Sage-Femme' },
  { valeur: 'KINE', label: 'Kinésithérapeute' },
  { valeur: 'MEDECIN', label: 'Médecin' },
  { valeur: 'DENTISTE', label: 'Chirurgien-Dentiste' },
  { valeur: 'PHARMACIEN', label: 'Pharmacien(ne)' },
  { valeur: 'MANIPULATEUR_RADIO', label: 'Manipulateur Radio' },
  { valeur: 'PREPARATEUR_PHARMA', label: 'Préparateur en Pharmacie' },
  { valeur: 'DIETETICIEN', label: 'Diététicien(ne)' },
  { valeur: 'ERGOTHERAPEUTE', label: 'Ergothérapeute' },
  { valeur: 'PSYCHOMOTRICIEN', label: 'Psychomotricien(ne)' },
  { valeur: 'ORTHOPHONISTE', label: 'Orthophoniste' },
] as const;

export const CONTRATS = [
  { valeur: 'CDD', label: 'Contrat à Durée Déterminée (CDD)' },
  { valeur: 'VACATION', label: 'CDD court' },
  { valeur: 'LIBERAL', label: 'Libéral' },
  { valeur: 'SALARIE', label: 'Salarié' },
] as const;

export const TYPES_ETABLISSEMENT = [
  { valeur: 'HOPITAL_PUBLIC', label: 'Hôpital Public' },
  { valeur: 'ESPIC', label: 'ESPIC (Étab. de Santé Privé d\'Intérêt Collectif)' },
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
  // Cabinets libéraux (PR 2 Sprint 1 — exercice libéral remplacement)
  { valeur: 'CABINET_MEDICAL', label: 'Cabinet médical (libéral)' },
  { valeur: 'CABINET_DENTAIRE', label: 'Cabinet dentaire (libéral)' },
  { valeur: 'CABINET_IDEL', label: 'Cabinet IDEL (libéral)' },
  { valeur: 'CABINET_SAGE_FEMME', label: 'Cabinet sage-femme (libéral)' },
  { valeur: 'CABINET_KINE', label: 'Cabinet kinésithérapie (libéral)' },
  { valeur: 'CABINET_ORTHO', label: 'Cabinet orthophonie (libéral)' },
  { valeur: 'CABINET_ERGO', label: 'Cabinet ergothérapie (libéral)' },
  { valeur: 'CABINET_PSYCHOMOT', label: 'Cabinet psychomotricité (libéral)' },
] as const;

// Professions sans numéro d'identification professionnelle (RPPS).
// Vérification par diplôme + CNI uniquement (ADELI obsolète depuis 2024).
// AUXILIAIRE_PUERICULTURE : DEAP, exercice sous supervision, non inscrite au RPPS.
export const PROFESSIONS_SANS_RPPS = ['AS', 'AES', 'AUXILIAIRE_PUERICULTURE'];

// RPPS EXIGÉ à l'inscription : professions « Ordre historique » dont le RPPS est
// ancien et connu/utilisé au quotidien (prescriptions). Pour les AUTRES professions
// à RPPS (IDE + paramédicaux migrés vers le RPPS seulement en 2021-2024), le numéro
// est souvent inconnu → RPPS optionnel, le DIPLÔME sert de preuve (vérif différée).
export const PROFESSIONS_RPPS_REQUIS = ['MEDECIN', 'DENTISTE', 'SAGE_FEMME', 'PHARMACIEN'];

// Professions limitées pour pharmacies
export const PROFESSIONS_PHARMACIE = ['PHARMACIEN', 'PREPARATEUR_PHARMA'];

export const BADGES_STATUT: Record<string, { label: string; classes: string }> = {
  'OUVERTE': { label: 'Ouverte', classes: 'bg-primary/10 text-primary' },
  'ASSIGNEE': { label: 'Assignée', classes: 'bg-warning/10 text-warning' },
  'EN_COURS': { label: 'En cours', classes: 'bg-info/10 text-info' },
  'TERMINEE': { label: 'Terminée', classes: 'bg-success/10 text-success' },
  'EXPIREE': { label: 'Expirée (non pourvue)', classes: 'bg-amber-500/10 text-amber-600 dark:text-amber-400' },
  'ANNULEE_PAR_ETABLISSEMENT': { label: 'Annulée', classes: 'bg-muted text-muted-foreground' },
  'ANNULEE_PAR_SOIGNANT': { label: 'Annulée (soignant)', classes: 'bg-destructive/10 text-destructive' },
  'ABSENCE': { label: 'Absence', classes: 'bg-destructive/20 text-destructive' },
  'LITIGE': { label: 'Litige', classes: 'bg-warning/10 text-warning' },
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
    case 'LIBERAL': return { label: '🏥 Libéral', classes: 'bg-rose/10 text-rose' };
    case 'SALARIE': return { label: '💼 Salarié', classes: 'bg-primary/10 text-primary' };
    default: return { label: '👥 Tous profils', classes: 'bg-muted text-muted-foreground' };
  }
}

export function getTypeContratRechercheBadge(type: string): { label: string; classes: string } {
  switch (type) {
    case 'LIBERAL': return { label: '🏥 Libéral', classes: 'bg-rose/10 text-rose' };
    case 'SALARIE': return { label: '💼 Salarié', classes: 'bg-primary/10 text-primary' };
    default: return { label: '👥 Tous profils', classes: 'bg-muted text-muted-foreground' };
  }
}

export function missionCompatibleContrat(pref: ContratPreference | string, typesContratSoignant: string[]): boolean {
  if (!pref || pref === 'TOUS') return true;
  if (pref === 'LIBERAL') return typesContratSoignant.includes('LIBERAL');
  // Contrat salarié = CDD uniquement.
  if (pref === 'SALARIE') return typesContratSoignant.some(t => ['CDD', 'VACATION', 'SALARIE'].includes(t));
  return true;
}

/** Parse the types_contrat_acceptes (JSON array or comma-separated) or fall back to type_exercice/type_contrat. Returns all types if nothing defined (profil incomplet). */
export function getTypesContratSoignant(soignant: { type_contrat?: string | null; types_contrat_acceptes?: string | null; type_exercice?: string | null } | null | undefined): string[] {
  if (!soignant) return ['CDD', 'VACATION', 'LIBERAL', 'SALARIE'];
  if (soignant.types_contrat_acceptes) {
    // Handle both JSON array and comma-separated string
    const raw = soignant.types_contrat_acceptes.trim();
    if (raw.startsWith('[')) {
      try {
        const arr = JSON.parse(raw);
        if (Array.isArray(arr) && arr.length > 0) return arr;
      } catch { /* fallback to comma split */ }
    }
    // Comma-separated: "CDD,LIBERAL"
    const parts = raw.split(',').map(s => s.trim()).filter(Boolean);
    if (parts.length > 0) return parts;
  }
  // Fallback based on type_exercice
  if (soignant.type_exercice === 'MIXTE') return ['CDD', 'LIBERAL'];
  if (soignant.type_exercice === 'LIBERAL') return ['LIBERAL'];
  return soignant.type_contrat ? [soignant.type_contrat] : ['CDD', 'VACATION', 'LIBERAL', 'SALARIE'];
}

// ── Parrainage établissement (7f-3) ────────────────────────────────────────
// Constantes extraites de PageParrainageEtablissement (étaient en dur en tête
// de fichier). Un seul code de parrainage par établissement (code unique).
// Modèle actuel : récompense forfaitaire à la validation (100 € de commission
// encaissée du filleul). Les paliers GMV (50 €/500 € + 150 €/2000 €) sont une
// évolution de logique d'argent réservée à une PR backend dédiée (règles ①②).
export const PARRAINAGE_ETAB_CAP = 10;
export const PARRAINAGE_ETAB_SEUIL_AMBASSADEUR = 3;
export const PARRAINAGE_ETAB_RECOMPENSE_EUR = 50;
