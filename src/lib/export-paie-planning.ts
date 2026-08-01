import {
  construirePlanningCandidat,
  type CreneauMissionCandidat,
  type MissionPlanningCandidat,
} from '@/components/planning/planning-candidat';
import {
  instantDateHeureParis,
  instantJolene,
} from '@/lib/date-heure-paris';

const MS_HEURE = 3_600_000;

export interface PresenceExportPaie {
  valide_par_etablissement?: boolean | null;
  valide_auto_72h_le?: string | null;
  valide_le?: string | null;
}

export interface MissionExportPaieSource extends MissionPlanningCandidat {
  id: string;
  statut: string;
  intitule?: string | null;
  soignant_assigne_id?: string | null;
  taux_horaire_base?: number | string | null;
  presences?: PresenceExportPaie[] | null;
  duree_heures?: number | string | null;
  heures_nuit?: number | string | null;
  heures_dimanche?: number | string | null;
  heures_ferie?: number | string | null;
  montant_majoration_nuit?: number | string | null;
  montant_majoration_dimanche?: number | string | null;
  montant_majoration_ferie?: number | string | null;
  montant_ifm?: number | string | null;
  montant_icp?: number | string | null;
  total_brut?: number | string | null;
  net_a_payer?: number | string | null;
  net_estime?: number | string | null;
  [cle: string]: unknown;
}

export interface CreneauExportPaie {
  debut: string;
  fin: string;
  duree_heures: number;
}

export type MissionExportPaiePeriode<T extends MissionExportPaieSource = MissionExportPaieSource> = T & {
  creneaux_export: CreneauExportPaie[];
  duree_heures: number;
  planning_source: 'EFFECTIF' | 'PREVISIONNEL_VALIDE';
  ratio_periode: number;
};

export interface BornesMoisPaie {
  debut: Date;
  fin: Date;
}

export function bornesMoisPaieParis(annee: number, mois: number): BornesMoisPaie {
  if (!Number.isInteger(annee) || !Number.isInteger(mois) || mois < 1 || mois > 12) {
    throw new RangeError('Période de paie invalide.');
  }

  const debut = instantDateHeureParis({
    annee,
    mois,
    jour: 1,
    heure: 0,
    minute: 0,
    seconde: 0,
  });
  const dateMoisSuivant = new Date(Date.UTC(annee, mois, 1, 12));
  const fin = instantDateHeureParis({
    annee: dateMoisSuivant.getUTCFullYear(),
    mois: dateMoisSuivant.getUTCMonth() + 1,
    jour: 1,
    heure: 0,
    minute: 0,
    seconde: 0,
  });
  return { debut, fin };
}

function presenceValidee(mission: MissionExportPaieSource): boolean {
  return (mission.presences ?? []).some((presence) => (
    presence.valide_par_etablissement === true
    || Boolean(presence.valide_auto_72h_le)
    || Boolean(presence.valide_le)
  ));
}

function nombre(value: unknown): number {
  const resultat = Number(value ?? 0);
  return Number.isFinite(resultat) ? resultat : 0;
}

function arrondir(value: number, decimales = 2): number {
  const facteur = 10 ** decimales;
  return Math.round((value + Number.EPSILON) * facteur) / facteur;
}

function proratiser(value: unknown, ratio: number): number {
  return arrondir(nombre(value) * ratio);
}

function planningReference(
  mission: MissionExportPaieSource,
  creneaux: CreneauMissionCandidat[],
): {
  creneaux: Array<{ debut: string; fin: string }>;
  creneauxOuverts: CreneauMissionCandidat[];
  dureeTotale: number;
  source: 'EFFECTIF' | 'PREVISIONNEL_VALIDE';
} {
  const effectifs = creneaux.filter((creneau) => (
    creneau.mission_id === mission.id
    && creneau.type_creneau === 'EFFECTIF'
    && !creneau.est_pause
  ));
  const effectifsFermes = effectifs.filter((creneau) => Boolean(creneau.fin));
  const effectifsOuverts = effectifs.filter((creneau) => !creneau.fin);

  if (mission.statut === 'EN_COURS') {
    const planningPrevisionnel = construirePlanningCandidat(mission, creneaux);
    if (!planningPrevisionnel.exact) {
      throw new Error(`Le planning exact de la mission « ${String(mission.intitule ?? mission.id)} » est incomplet.`);
    }
    const dureeTotale = planningPrevisionnel.creneaux.reduce((total, creneau) => (
      total + (instantJolene(creneau.fin!).getTime() - instantJolene(creneau.debut).getTime()) / MS_HEURE
    ), 0);
    return {
      creneaux: effectifsFermes.map((creneau) => ({ debut: creneau.debut, fin: creneau.fin! })),
      creneauxOuverts: effectifsOuverts,
      dureeTotale,
      source: 'EFFECTIF',
    };
  }

  const planningPrevisionnel = construirePlanningCandidat(mission, creneaux);
  const attendus = Number(mission.nb_creneaux ?? 0);

  // Dès qu'un pointage EFFECTIF existe, le planning théorique ne doit jamais
  // remplacer silencieusement le travail réellement constaté. Les créneaux
  // ouverts sont gardés séparément afin de bloquer uniquement leur période.
  if (effectifs.length > 0) {
    const effectifsComplets = effectifsOuverts.length === 0
      && (attendus <= 0 || effectifsFermes.length === attendus);
    if (!effectifsComplets && !planningPrevisionnel.exact) {
      throw new Error(`Le planning exact de la mission « ${String(mission.intitule ?? mission.id)} » est incomplet.`);
    }
    const dureeTotale = (effectifsComplets ? effectifsFermes : planningPrevisionnel.creneaux)
      .reduce((total, creneau) => (
        total + (instantJolene(creneau.fin!).getTime() - instantJolene(creneau.debut).getTime()) / MS_HEURE
      ), 0);
    return {
      creneaux: effectifsFermes.map((creneau) => ({ debut: creneau.debut, fin: creneau.fin! })),
      creneauxOuverts: effectifsOuverts,
      dureeTotale,
      source: 'EFFECTIF',
    };
  }

  const planning = planningPrevisionnel;

  if (!planning.exact || planning.creneaux.some((creneau) => !creneau.fin)) {
    throw new Error(`Le planning exact de la mission « ${String(mission.intitule ?? mission.id)} » est incomplet.`);
  }

  const creneauxReference = planning.creneaux.map((creneau) => ({
      debut: creneau.debut,
      fin: creneau.fin!,
    }));
  return {
    creneaux: creneauxReference,
    creneauxOuverts: effectifsOuverts,
    dureeTotale: creneauxReference.reduce((total, creneau) => (
      total + (instantJolene(creneau.fin).getTime() - instantJolene(creneau.debut).getTime()) / MS_HEURE
    ), 0),
    source: 'PREVISIONNEL_VALIDE',
  };
}

function clipperCreneau(
  creneau: { debut: string; fin: string },
  bornes: BornesMoisPaie,
): CreneauExportPaie | null {
  const debut = instantJolene(creneau.debut);
  const fin = instantJolene(creneau.fin);
  if (fin <= debut) throw new Error('Un créneau de paie possède une durée invalide.');

  const debutClippe = new Date(Math.max(debut.getTime(), bornes.debut.getTime()));
  const finClippee = new Date(Math.min(fin.getTime(), bornes.fin.getTime()));
  if (finClippee <= debutClippe) return null;

  return {
    debut: debutClippe.toISOString(),
    fin: finClippee.toISOString(),
    duree_heures: arrondir((finClippee.getTime() - debutClippe.getTime()) / MS_HEURE, 4),
  };
}

/**
 * Ventile une mission terminée sur le mois civil français sélectionné.
 * Aucune donnée persistée n'est modifiée : les montants de période sont des
 * copies calculées au même prorata horaire que le moteur de facturation.
 */
export function construireExportPaiePeriode<T extends MissionExportPaieSource>(
  missions: T[],
  creneaux: CreneauMissionCandidat[],
  annee: number,
  mois: number,
): Array<MissionExportPaiePeriode<T>> {
  const bornes = bornesMoisPaieParis(annee, mois);

  return missions.flatMap((mission) => {
    const debutMission = mission.debut_le ? instantJolene(mission.debut_le) : null;
    const finMission = mission.fin_le ? instantJolene(mission.fin_le) : null;
    if (!debutMission || !finMission || finMission <= bornes.debut || debutMission >= bornes.fin) {
      return [];
    }

    const reference = planningReference(mission, creneaux);
    const dureeTotale = reference.dureeTotale;
    if (!Number.isFinite(dureeTotale) || dureeTotale <= 0) {
      throw new Error(`La durée exacte de la mission « ${String(mission.intitule ?? mission.id)} » est invalide.`);
    }

    const creneauxPeriode = reference.creneaux
      .map((creneau) => clipperCreneau(creneau, bornes))
      .filter((creneau): creneau is CreneauExportPaie => creneau !== null);
    const pointageOuvertDansPeriode = reference.creneauxOuverts.some((creneau) => {
      const debut = instantJolene(creneau.debut);
      return debut < bornes.fin && debut >= bornes.debut;
    });
    if (pointageOuvertDansPeriode) {
      throw new Error(`Un pointage de la mission « ${String(mission.intitule ?? mission.id)} » est encore ouvert sur la période.`);
    }
    if (creneauxPeriode.length === 0) return [];
    if (!presenceValidee(mission)) {
      throw new Error(`La présence de la mission « ${String(mission.intitule ?? mission.id)} » n'est pas validée.`);
    }

    const dureePeriode = creneauxPeriode.reduce((total, creneau) => total + creneau.duree_heures, 0);
    const ratio = Math.min(1, Math.max(0, dureePeriode / dureeTotale));
    const majorationNonVentilable = [
      mission.heures_nuit,
      mission.heures_dimanche,
      mission.heures_ferie,
      mission.montant_majoration_nuit,
      mission.montant_majoration_dimanche,
      mission.montant_majoration_ferie,
    ].some((value) => nombre(value) !== 0);
    if (majorationNonVentilable && (ratio < 1 - 1e-9 || creneauxPeriode.length > 1)) {
      throw new Error(
        `Les majorations de la mission « ${String(mission.intitule ?? mission.id)} » ne peuvent pas être attribuées de façon fiable à ce mois.`,
      );
    }
    return [{
      ...mission,
      duree_heures: arrondir(dureePeriode, 4),
      heures_nuit: nombre(mission.heures_nuit),
      heures_dimanche: nombre(mission.heures_dimanche),
      heures_ferie: nombre(mission.heures_ferie),
      montant_majoration_nuit: nombre(mission.montant_majoration_nuit),
      montant_majoration_dimanche: nombre(mission.montant_majoration_dimanche),
      montant_majoration_ferie: nombre(mission.montant_majoration_ferie),
      montant_ifm: proratiser(mission.montant_ifm, ratio),
      montant_icp: proratiser(mission.montant_icp, ratio),
      total_brut: proratiser(mission.total_brut, ratio),
      net_a_payer: mission.net_a_payer == null ? null : proratiser(mission.net_a_payer, ratio),
      net_estime: mission.net_estime == null ? null : proratiser(mission.net_estime, ratio),
      creneaux_export: creneauxPeriode,
      planning_source: reference.source,
      ratio_periode: ratio,
    }];
  });
}

/** Ventile un montant en centimes sans perdre le reliquat d'arrondi. */
export function repartirMontantParCreneau(
  montant: number,
  creneaux: CreneauExportPaie[],
): number[] {
  const totalHeures = creneaux.reduce((total, creneau) => total + creneau.duree_heures, 0);
  if (creneaux.length === 0 || totalHeures <= 0) return [];

  const totalCentimes = Math.round(nombre(montant) * 100);
  if (totalCentimes < 0) throw new RangeError('Un montant négatif ne peut pas être ventilé par créneau.');

  const parts = creneaux.map((creneau, index) => {
    const exacte = totalCentimes * creneau.duree_heures / totalHeures;
    const plancher = Math.floor(exacte);
    return { index, plancher, fraction: exacte - plancher };
  });
  const centimes = parts.map((part) => part.plancher);
  let reliquat = totalCentimes - centimes.reduce((total, valeur) => total + valeur, 0);
  const priorite = [...parts].sort((a, b) => b.fraction - a.fraction || a.index - b.index);
  for (let index = 0; index < priorite.length && reliquat > 0; index += 1, reliquat -= 1) {
    centimes[priorite[index].index] += 1;
  }
  return centimes.map((valeur) => valeur / 100);
}
