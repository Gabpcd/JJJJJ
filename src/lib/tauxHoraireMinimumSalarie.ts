/**
 * Taux horaire minimal d'une mission salariée ou ouverte à tous les profils (`TOUS`), en euros brut par heure.
 *
 * La valeur de référence est le paramètre serveur `parametres_systeme.taux_horaire_minimum_salarie`, contrôlé à la
 * création et à la modification du taux par le verrou `private.fn_trg_verifier_taux_minimum_salarie` (migration
 * `20261125120000_taux_horaire_minimum_salarie.sql`) et lu par `fn_taux_horaire_minimum_salarie()`. La constante
 * ci-dessous (épinglée à sa ligne par `PublicationPayloadTests` de l'app iOS) n'est qu'un repli d'affichage tant que le
 * serveur n'a pas répondu ; elle ne peut pas diverger de la migration ni de `LibellesWeb.Publication` en silence
 * (garde `tests/node/taux-horaire-minimum-salarie.node.mjs`). Écrite en texte, comme l'était l'attribut `min` du champ,
 * parce que la garde des libellés iOS (`check-textes-juridiques-ios.mjs`) compare des littéraux de texte.
 *
 * Source de la valeur : SMIC horaire brut au 1er juin 2026, arrêté du 22 mai 2026 (JORF n° 0121 du 24 mai 2026).
 * Une mission libérale (honoraires) n'est pas concernée.
 */
export const TAUX_HORAIRE_MINIMUM_SALARIE_REPLI = Number('12.31');

export type ContratMission = 'TOUS' | 'SALARIE' | 'LIBERAL';

/** Valeur rendue par le serveur, ou repli si elle est absente ou illisible. */
export function normaliserTauxMinimumSalarie(valeur: unknown): number {
  const nombre = typeof valeur === 'number' ? valeur : typeof valeur === 'string' ? Number(valeur) : Number.NaN;
  return Number.isFinite(nombre) && nombre > 0 ? nombre : TAUX_HORAIRE_MINIMUM_SALARIE_REPLI;
}

/** Le plancher s'applique à toute mission qui peut être pourvue en salarié : `SALARIE` et `TOUS`. */
export function minimumSalarieApplicable(contrat: ContratMission): boolean {
  return contrat !== 'LIBERAL';
}

/**
 * Taux saisi (strictement positif) inférieur au plancher d'une mission salariée ou `TOUS`. En modification, une
 * mission existante dont ni le taux ni le type de contrat ne changent n'est pas bloquée : même règle que le verrou
 * serveur, qui ne contrôle une mise à jour que lorsqu'elle touche l'un de ces deux champs.
 */
export function tauxSousMinimumSalarie(
  taux: number,
  contrat: ContratMission,
  minimum: number,
  source?: { taux: number; contrat: ContratMission } | null,
): boolean {
  if (source && source.taux === taux && source.contrat === contrat) return false;
  return minimumSalarieApplicable(contrat) && Number.isFinite(taux) && taux > 0 && taux < minimum;
}

/** Montant à la française, deux décimales, sans séparateur de milliers : 12.31 → « 12,31 ». */
export function montantFrancais(valeur: number): string {
  return valeur.toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2, useGrouping: false });
}

/** Message affiché sous le champ et renvoyé par le serveur (même texte que l'app iOS). */
export function messageTauxSousMinimum(minimum: number): string {
  return `Le taux horaire doit être d'au moins ${montantFrancais(minimum)} €/h.`;
}
