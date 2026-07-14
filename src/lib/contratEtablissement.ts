export type EtatContratEtablissement = {
  contrat_service_signe?: boolean | null;
  /** Ancien statut de validation d'un PDF téléversé, non bloquant depuis D9. */
  contrat_valide?: boolean | null;
};

/**
 * Source canonique du droit de publier une mission.
 *
 * Le backend (`fn_blocage_publication_etab`) exige une signature de contrat de
 * service active. L'ancien champ `contrat_valide` ne doit donc jamais être
 * utilisé comme équivalent, même lorsqu'il vaut true.
 */
export function contratServiceEstSigne(
  etablissement: EtatContratEtablissement | null | undefined,
): boolean {
  return etablissement?.contrat_service_signe === true;
}
