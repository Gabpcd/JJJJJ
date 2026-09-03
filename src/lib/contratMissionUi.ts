const VARIABLE_CONTRAT = /\{\{\s*[^}]+\s*\}\}/;

export function contientVariablesContratNonRendues(html?: string | null): boolean {
  return VARIABLE_CONTRAT.test(html || '');
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
