import { extraireContratPreference, getTypesContratSoignant, missionCompatibleContrat } from '../../../src/lib/constantes';
import { filtrerMissionsPlaywright } from '../../../src/lib/donnees-test';
import { calculerDistanceKm } from '../../../src/lib/geo';
import { getMissionsCompatiblesFilter } from '../../../src/lib/profession-hierarchy';
import { construirePlanningCandidat, planningCorrespondAuFiltre } from '../../../src/components/planning/planning-candidat';
import type { EtablissementSummary, Mission, MissionFilters, MissionReadContext, MissionRecord, MissionSlot, SoignantProfile } from './types';

export { getMissionsCompatiblesFilter };

export function throwIfAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    const error = new Error('Chargement annulé');
    error.name = 'AbortError';
    throw error;
  }
}

export function validateContext(context: MissionReadContext): void {
  if (!context.userId || context.profile.id !== context.userId || !context.profile.profession) {
    throw new Error('Le profil soignant ne correspond pas à la session. Reconnectez-vous.');
  }
}

export function defaultFilters(profile: SoignantProfile): MissionFilters {
  return {
    ville: '', profession: '', rayonKm: profile.rayon_deplacement_km || 50,
    tauxMin: profile.taux_horaire_minimum || 0, urgentesOnly: false,
    typeContrat: 'TOUS', horaire: 'TOUS',
  };
}

export function enrichMission(
  record: MissionRecord,
  context: MissionReadContext,
  establishment: EtablissementSummary | null,
  slots: MissionSlot[],
): Mission {
  const planning = construirePlanningCandidat(record, slots);
  return {
    ...record,
    etablissements: establishment,
    distance_km: calculerDistanceKm(context.profile.adresse_lat, context.profile.adresse_lng,
      establishment?.adresse_lat ?? null, establishment?.adresse_lng ?? null),
    creneaux_planifies: slots.length ? slots : planning.creneaux,
    planning_exact: planning.exact,
    erreur_planning: false,
  };
}

/** These are the existing web presentation filters, not substitutes for RLS. */
export function filterMissions(missions: Mission[], context: MissionReadContext, input: MissionFilters = {}): Mission[] {
  const filters = { ...defaultFilters(context.profile), ...input };
  const city = (filters.ville ?? '').trim().toLowerCase();
  const profession = filters.profession || context.profile.profession;
  const compatible = !filters.profession && (profession === 'IADE' || profession === 'IBODE')
    ? [profession, 'IDE'] : [profession];
  return filtrerMissionsPlaywright(missions, context.email).filter((mission) => {
    if (!compatible.includes(mission.profession_requise)) return false;
    if (filters.etablissementId && mission.etablissement_id !== filters.etablissementId) return false;
    if (filters.urgentesOnly && !mission.est_urgente) return false;
    if ((filters.tauxMin ?? 0) > 0 && Number(mission.taux_horaire_base ?? 0) < filters.tauxMin!) return false;
    if (city && !(mission.etablissements?.adresse_ville ?? '').toLowerCase().includes(city)
      && !(mission.etablissements?.adresse_code_postal ?? '').toLowerCase().startsWith(city)) return false;
    if (mission.distance_km !== null && mission.distance_km > filters.rayonKm!) return false;
    const contract = mission.type_contrat_recherche || extraireContratPreference(mission.description);
    if (!missionCompatibleContrat(contract, getTypesContratSoignant(context.profile))) return false;
    if (filters.typeContrat === 'CDD' && contract === 'LIBERAL') return false;
    if (filters.typeContrat === 'LIBERAL' && contract === 'SALARIE') return false;
    return planningCorrespondAuFiltre(mission, filters.horaire ?? 'TOUS');
  }).sort((a, b) => (a.distance_km ?? 999) - (b.distance_km ?? 999));
}
