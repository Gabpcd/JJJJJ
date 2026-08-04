export type NiveauModeExercice = 'AUTORISE' | 'NON_PROPOSE' | 'BLOQUE';

export interface ModeExerciceMission {
  niveau: NiveauModeExercice;
  categorie: 'cabinet_liberal' | 'prive' | 'centre_sante' | 'public';
  source_libelle: string;
  source_force: 'JUGE' | 'DOCTRINE' | 'LEGAL' | 'CONFORMITE_JOLENE';
  source_url: string | null;
  source_url_complementaire?: string | null;
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

/**
 * `NON_PROPOSE` ne favorise aucun régime et n'est pas une interdiction.
 * Seule une cellule `BLOQUE` retire réellement le choix libéral.
 */
export function liberalEstSelectionnable(
  mode: ModeExerciceMission | null,
  profession?: string | null,
): boolean {
  if (profession && ['IADE', 'IBODE'].includes(profession) && mode?.niveau !== 'AUTORISE') {
    return false;
  }
  return mode !== null && mode.niveau !== 'BLOQUE';
}

/**
 * Libellé explicite du lien affiché sur les deux surfaces de publication.
 * L'URL reste fournie par la matrice serveur ; ce mapping évite qu'une source
 * juridique primaire soit présentée sous un libellé générique ou ambigu.
 */
type SourcesModeExercice = Pick<ModeExerciceMission, 'source_url'> &
  Partial<Pick<ModeExerciceMission, 'source_force' | 'source_url_complementaire'>>;

export interface LienSourceModeExercice {
  href: string;
  libelle: string;
}

function libellePourUrlSource(url: string, sourceForce?: ModeExerciceMission['source_force']): string {
  if (url.includes('courrierconjointministeres_30decembre2021_')) {
    return 'Lire la lettre D21-031940 (texte original)';
  }

  if (url.includes('CETATEXT000051156546')) {
    if (sourceForce === 'DOCTRINE') {
      return 'Lire l’arrêt n°491128 — cas aide-soignant uniquement';
    }
    return 'Lire l’arrêt n°491128 sur Légifrance';
  }
  if (url.includes('LEGIARTI000033621093')) {
    return 'Lire l’article L.4351-1 sur Légifrance';
  }
  if (url.includes('LEGIARTI000047567923')) {
    return 'Lire l’article L.6323-1-5 sur Légifrance';
  }

  return 'Consulter la source officielle';
}

/** Renvoie tous les textes encodés par la cellule, dans l'ordre de preuve. */
export function liensSourcesModeExercice(mode: SourcesModeExercice): LienSourceModeExercice[] {
  const urls = [mode.source_url, mode.source_url_complementaire]
    .filter((url): url is string => Boolean(url));

  return [...new Set(urls)].map((href) => ({
    href,
    libelle: libellePourUrlSource(href, mode.source_force),
  }));
}

/** Compatibilité pour les consommateurs qui n'affichent que le premier lien. */
export function libelleLienSourceModeExercice(mode: SourcesModeExercice): string {
  return liensSourcesModeExercice(mode)[0]?.libelle ?? 'Consulter la source officielle';
}
