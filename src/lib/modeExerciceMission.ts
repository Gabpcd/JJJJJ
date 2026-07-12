export type NiveauModeExercice = 'AUTORISE' | 'NON_PROPOSE' | 'BLOQUE';

export interface ModeExerciceMission {
  niveau: NiveauModeExercice;
  categorie: 'cabinet_liberal' | 'prive' | 'centre_sante' | 'public';
  source_libelle: string;
  source_force: 'JUGE' | 'DOCTRINE' | 'LEGAL' | 'CONFORMITE_JOLENE';
  source_url: string | null;
}

export interface ModeExerciceRpcParams {
  p_profession: string;
  p_type_etab: string;
  p_finess_secteur: string | null;
}

/**
 * Construit l'appel matrice depuis la profession REQUISE PAR LA MISSION.
 * La profession ou les diplômes du profil soignant n'entrent jamais ici.
 */
export function paramsModeExerciceMission(
  professionRequise: string,
  typeEtablissement: string,
  estSecteurPublic: boolean,
): ModeExerciceRpcParams {
  return {
    p_profession: professionRequise,
    p_type_etab: typeEtablissement,
    p_finess_secteur: estSecteurPublic ? 'PUBLIC' : null,
  };
}

export function liberalEstProposable(mode: ModeExerciceMission | null): boolean {
  return mode?.niveau === 'AUTORISE';
}
