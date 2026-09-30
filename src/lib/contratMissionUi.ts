const VARIABLE_CONTRAT = /\{\{\s*[^}]+\s*\}\}/;

type PreuveSignature = {
  statut?: string | null;
  signature_soignant?: boolean | null;
  signature_etablissement?: boolean | null;
  signature_soignant_le?: string | null;
  signature_etablissement_le?: string | null;
};

export function contratPossedeSignature(contrat?: PreuveSignature | null): boolean {
  return /^SIGNE/.test(contrat?.statut || '') || contrat?.signature_soignant === true
    || contrat?.signature_etablissement === true || !!contrat?.signature_soignant_le
    || !!contrat?.signature_etablissement_le;
}

export function contientVariablesContratNonRendues(html?: string | null): boolean {
  return VARIABLE_CONTRAT.test(html || '');
}

export function contratNecessiteRenduServeur(
  _html?: string | null,
  storagePath?: string | null,
  contrat?: PreuveSignature | null,
): boolean {
  // Un changement de template ne justifie jamais de réécrire un document figé.
  return !storagePath && !contratPossedeSignature(contrat);
}

export function choisirContenuContratAffiche(
  contenuServeur?: string | null,
  contenuReconstitue?: string | null,
  conserverOriginal = false,
): string {
  if (conserverOriginal) return contenuServeur || '';
  if (contenuServeur && !contientVariablesContratNonRendues(contenuServeur)) {
    return contenuServeur;
  }
  return contenuReconstitue || '';
}
