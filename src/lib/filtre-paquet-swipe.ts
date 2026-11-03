import { getMissionMatchInfo } from '@/lib/profession-hierarchy';
// Import relatif (et non `@/components/…`) : l'exporteur golden ne résout que
// l'alias `@/lib/` ; `planning-candidat.ts` est une règle pure qu'il charge déjà.
import {
  planningCorrespondAuFiltre,
  type FiltreHoraireCandidat,
  type MissionPlanningCandidat,
} from '../components/planning/planning-candidat';

/**
 * Filtre du paquet de swipe (chips rapides 6c.1 : le deck respecte les mêmes
 * filtres 1-tap que la liste), extrait de `VueSwipeMissions.tsx` pour être
 * partagé avec le port natif (vecteurs golden iOS, lot 4 W0). Règle pure.
 */

export interface FiltrePaquetSwipe {
  urgentesOnly: boolean;
  horaire: FiltreHoraireCandidat;
  profession: string;
  ville: string;
  rayonKm: number;
  tauxMin: number;
  typeContrat: string;
}

/** Champs de la carte swipe lus par le filtre. */
export interface MissionPaquetSwipe extends MissionPlanningCandidat {
  profession_requise: string | null;
  etablissement_ville: string | null;
  etablissement_code_postal: string | null;
  distance_km: number | null;
  taux_horaire_base: number | null;
  type_contrat_recherche: string | null;
  est_urgente: boolean;
}

/** Exploration avant inscription : la profession choisie prime, sinon celle du
 *  compte avec sa hiérarchie naturelle (IADE/IBODE → missions IDE). */
export function missionCorrespondProfessionInscription(requise: string, selection: string, compte: string) {
  if (selection) return requise === selection;
  return !compte || requise === compte
    || getMissionMatchInfo(compte, null, requise, null, true)?.type === 'HIERARCHIE_NATURELLE';
}

/**
 * `professionParcours` : `null` hors parcours d'inscription, sinon la
 * profession du compte en cours d'inscription (chaîne vide si inconnue).
 */
export function missionPasseFiltrePaquet(
  m: MissionPaquetSwipe,
  filtreDeck: FiltrePaquetSwipe,
  professionParcours: string | null,
): boolean {
  if (professionParcours != null ? !missionCorrespondProfessionInscription(m.profession_requise, filtreDeck.profession, professionParcours)
    : filtreDeck.profession && m.profession_requise !== filtreDeck.profession) return false;
  const ville = filtreDeck.ville.trim().toLowerCase();
  if (ville) {
    const missionVille = (m.etablissement_ville || '').toLowerCase();
    const codePostal = (m.etablissement_code_postal || '').toLowerCase();
    if (!missionVille.includes(ville) && !codePostal.startsWith(ville)) return false;
  }
  if (m.distance_km != null && m.distance_km > filtreDeck.rayonKm) return false;
  if (filtreDeck.tauxMin > 0 && (m.taux_horaire_base ?? 0) < filtreDeck.tauxMin) return false;
  if (filtreDeck.typeContrat === 'CDD' && m.type_contrat_recherche === 'LIBERAL') return false;
  if (filtreDeck.typeContrat === 'LIBERAL' && m.type_contrat_recherche === 'SALARIE') return false;
  if (filtreDeck.urgentesOnly && !m.est_urgente) return false;
  if (!planningCorrespondAuFiltre(m, filtreDeck.horaire)) return false;
  return true;
}

/** Sans filtre, le paquet est rendu tel quel (même référence). */
export function filtrerPaquetSwipe<T extends MissionPaquetSwipe>(
  paquet: T[],
  filtreDeck: FiltrePaquetSwipe | null | undefined,
  professionParcours: string | null,
): T[] {
  if (!filtreDeck) return paquet;
  return paquet.filter((m) => missionPasseFiltrePaquet(m, filtreDeck, professionParcours));
}
