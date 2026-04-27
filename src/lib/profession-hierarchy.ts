/**
 * Hiérarchie professionnelle : règles de compatibilité soignant ↔ mission.
 *
 * Mirror exact de la fonction SQL fn_soignant_compatible_mission appliquée
 * côté backend par fn_postuler_mission. Sert à élargir le filtre des missions
 * visibles côté soignant pour inclure celles auxquelles il peut candidater
 * via la hiérarchie pro (IBODE/IADE peuvent faire IDE ; IDE peut faire
 * IBODE/IADE si accepte_non_specialises).
 */

/**
 * Construit un filtre supabase-js `.or()` pour récupérer toutes les missions
 * matchables par un soignant de la profession donnée.
 *
 * - Match strict (profession = X)
 * - Plus, pour IDE/IBODE/IADE, les missions hiérarchiquement compatibles avec
 *   la condition `accepte_non_specialises=true` quand la mission est plus
 *   spécialisée que le soignant.
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

  // IDE peut candidater à mission IBODE/IADE si accepte_non_specialises=true
  if (soignantProfession === 'IDE') {
    return 'profession_requise.eq.IDE,and(profession_requise.in.(IBODE,IADE),accepte_non_specialises.eq.true)';
  }

  // Autres professions : pas de hiérarchie, match strict uniquement
  return null;
}
