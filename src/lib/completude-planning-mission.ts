import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { instantJolene } from '@/lib/date-heure-paris';

interface MissionAvecPlanningAttendu {
  id?: string;
  debut_le: string;
  fin_le: string;
  nb_creneaux?: number | null;
}

export interface CompletudePlanningMission {
  complet: boolean;
  creneauxPlanifies: CreneauPointage[];
  nombrePlanifie: number;
  dureeTotaleHeures: number;
}

function creneauValide(creneau: CreneauPointage): boolean {
  if (!creneau.fin) return false;
  try {
    const debutMs = instantJolene(creneau.debut).getTime();
    const finMs = instantJolene(creneau.fin).getTime();
    return Number.isFinite(debutMs) && Number.isFinite(finMs) && finMs > debutMs;
  } catch {
    return false;
  }
}

/**
 * Vérifie qu'un planning peut être utilisé comme source contractuelle.
 *
 * Pour les missions récentes, `nb_creneaux` doit correspondre exactement aux
 * lignes PREVISIONNEL de travail reçues. Le seul repli autorisé concerne les
 * anciennes missions ponctuelles (24 h maximum) sans aucune ligne détaillée.
 * Un résultat partiel n'est jamais exposé comme un planning valide.
 */
export function analyserCompletudePlanningMission(
  mission: MissionAvecPlanningAttendu,
  creneaux: CreneauPointage[] = [],
): CompletudePlanningMission {
  const bruts = creneaux.filter((creneau) => (
    creneau.type_creneau === 'PREVISIONNEL' && !creneau.est_pause
  ));
  const nombreAttendu = Number(mission.nb_creneaux);
  const nombreAttenduVerifiable = Number.isInteger(nombreAttendu) && nombreAttendu > 0;

  let candidats: CreneauPointage[] = [];
  let complet = false;

  if (nombreAttenduVerifiable) {
    candidats = creneauxPrevisionnels(bruts);
    complet = bruts.length === nombreAttendu
      && candidats.length === nombreAttendu
      && bruts.every(creneauValide);
  } else if (bruts.length === 0) {
    candidats = creneauxPrevisionnels(ajouterRepliMissionPonctuelle([], mission));
    complet = candidats.length === 1 && candidats.every(creneauValide);
  }

  if (!complet) {
    return {
      complet: false,
      creneauxPlanifies: [],
      nombrePlanifie: 0,
      dureeTotaleHeures: 0,
    };
  }

  const dureeTotaleHeures = candidats.reduce((total, creneau) => (
    total + (instantJolene(creneau.fin!).getTime() - instantJolene(creneau.debut).getTime()) / 3_600_000
  ), 0);

  return {
    complet: true,
    creneauxPlanifies: candidats,
    nombrePlanifie: candidats.length,
    dureeTotaleHeures,
  };
}
