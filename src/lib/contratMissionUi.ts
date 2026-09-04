const VARIABLE_CONTRAT = /\{\{\s*[^}]+\s*\}\}/;

export function contientVariablesContratNonRendues(html?: string | null): boolean {
  return VARIABLE_CONTRAT.test(html || '');
}

export function contratNecessiteRenduServeur(
  html?: string | null,
  storagePath?: string | null,
): boolean {
  const contenu = html || '';
  return !storagePath
    || contientVariablesContratNonRendues(contenu)
    || contenu.includes('majorations légales incluses (nuit ≥ 25%')
    || contenu.includes('10h/jour (L3121-18)')
    || /né\(e\) le \d{4}-\d{2}-\d{2}/.test(contenu);
}

export function choisirContenuContratAffiche(
  contenuServeur?: string | null,
  contenuReconstitue?: string | null,
): string {
  if (contenuServeur && !contientVariablesContratNonRendues(contenuServeur)) {
    return contenuServeur;
  }
  return contenuReconstitue || '';
}
