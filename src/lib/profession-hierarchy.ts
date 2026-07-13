/**
 * Hiérarchie professionnelle : règles de compatibilité soignant ↔ mission.
 *
 * Mirror exact de la fonction SQL fn_soignant_compatible_mission appliquée
 * côté backend par fn_postuler_mission. Sert à élargir le filtre des missions
 * visibles côté soignant pour inclure celles auxquelles il peut candidater
 * via la hiérarchie pro (IBODE/IADE peuvent faire IDE). La profession requise
 * reste stricte pour une mission IADE ou IBODE.
 */

/**
 * Construit un filtre supabase-js `.or()` pour récupérer toutes les missions
 * matchables par un soignant de la profession donnée.
 *
 * - Match strict (profession = X)
 * - Plus, pour IBODE/IADE, les missions IDE couvertes par leur diplôme initial.
 *
 * Retourne null si la profession est non reconnue ou ne nécessite pas de
 * filtre élargi (le caller utilisera alors `.eq('profession_requise', X)`).
 */
export function getMissionsCompatiblesFilter(soignantProfession: string | null | undefined): string | null {
  if (!soignantProfession) return null;

  // IBODE / IADE peuvent toujours candidater à mission IDE (pas de flag requis)
  if (soignantProfession === 'IBODE' || soignantProfession === 'IADE') {
    return `profession_requise.eq.${soignantProfession},profession_requise.eq.IDE`;
  }

  // Autres professions : pas de hiérarchie, match strict uniquement
  return null;
}

export type MatchType = 'EXACT' | 'HIERARCHIE_NATURELLE' | 'SPECIALITE_SOUPLE';

export interface MatchInfo {
  type: MatchType;
  /** Libellé court à afficher dans un badge */
  badgeLabel: string;
  /** Tailwind classes à appliquer au badge */
  badgeClasses: string;
  /** Tooltip / description longue */
  tooltip: string;
}

/**
 * Détermine la nature du match entre soignant et mission. Mirror local de la
 * règle métier fn_soignant_compatible_mission, utilisé pour afficher un badge
 * contextuel sur les cartes mission côté soignant.
 *
 * Retourne null si la mission est en match exact + sans spécialité (cas
 * trivial — pas besoin de badge).
 */
export function getMissionMatchInfo(
  soignantProfession: string | null | undefined,
  soignantSpecialite: string | null | undefined,
  missionProfession: string | null | undefined,
  missionSpecialite: string | null | undefined,
  accepteNonSpecialises: boolean | null | undefined,
): MatchInfo | null {
  if (!soignantProfession || !missionProfession) return null;

  // Cas hiérarchie naturelle : IBODE/IADE sur mission IDE
  if (missionProfession === 'IDE' && (soignantProfession === 'IBODE' || soignantProfession === 'IADE')) {
    return {
      type: 'HIERARCHIE_NATURELLE',
      badgeLabel: '↓ Mission IDE — accessible',
      badgeClasses: 'bg-success/10 text-success',
      tooltip: `Votre diplôme ${soignantProfession} couvre les missions IDE.`,
    };
  }

  // Cas spécialité souple : médecin sans la spécialité requise mais accepté
  if (
    missionProfession === 'MEDECIN' &&
    soignantProfession === 'MEDECIN' &&
    missionSpecialite &&
    accepteNonSpecialises !== false &&
    (soignantSpecialite || '') !== missionSpecialite
  ) {
    return {
      type: 'SPECIALITE_SOUPLE',
      badgeLabel: '🩺 Spécialité souhaitée — ouverte',
      badgeClasses: 'bg-violet-500/10 text-violet-700 dark:text-violet-300',
      tooltip: `L'établissement préfère un médecin spécialisé mais accepte les généralistes.`,
    };
  }

  return null;
}

/** Une mission IADE ou IBODE exige le diplôme spécialisé correspondant. */
export function professionMissionExigeSpecialisationExacte(
  professionRequise: string | null | undefined,
): boolean {
  return professionRequise === 'IADE' || professionRequise === 'IBODE';
}
