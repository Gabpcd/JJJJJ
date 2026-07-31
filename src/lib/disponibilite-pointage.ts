export interface CreneauPointage {
  id?: string;
  debut: string;
  fin: string | null;
  est_pause: boolean;
  type_creneau: string;
}

export interface DisponibilitePointage {
  peutPointer: boolean;
  action: 'OUVERTURE' | 'FERMETURE' | null;
  motif: 'CONTRAT' | 'HORS_CRENEAU' | 'AUCUN_CRENEAU' | null;
  creneauCourant: CreneauPointage | null;
  prochainCreneau: CreneauPointage | null;
}

export interface ContratPointage {
  id: string;
  statut: string;
  cree_le?: string | null;
  mission_id?: string;
}

export interface EtatTerminaisonMission {
  peutTerminer: boolean;
  motif: 'AVANT_DERNIER_CRENEAU' | 'SEGMENT_OUVERT' | 'AUCUN_DEPART' | 'PLANNING_INCOMPLET' | null;
  finReference: Date;
}

interface PeriodeMissionPointage {
  id?: string;
  debut_le: string;
  fin_le: string;
}

const STATUTS_CONTRAT_TERMINAUX = new Set([
  'ANNULE',
  'EXPIRE',
  'REFUSE',
  'RUPTURE_ETAB',
  'RUPTURE_SOIGNANT',
]);

export function choisirContratPointage<T extends ContratPointage>(contrats: T[]): T | undefined {
  return [...contrats]
    .filter((contrat) => !STATUTS_CONTRAT_TERMINAUX.has(contrat.statut))
    .sort((a, b) => {
      const prioriteA = a.statut === 'SIGNE_COMPLET' ? 1 : 0;
      const prioriteB = b.statut === 'SIGNE_COMPLET' ? 1 : 0;
      if (prioriteA !== prioriteB) return prioriteB - prioriteA;
      return new Date(b.cree_le ?? 0).getTime() - new Date(a.cree_le ?? 0).getTime();
    })[0];
}

export function filtrerMissionsEnCours<T extends { statut: string }>(missions: T[]): T[] {
  // Ne pas dépendre de `presences`, désormais legacy : une mission longue peut
  // être EN_COURS entre deux créneaux sans présence ouverte.
  return missions.filter((mission) => mission.statut === 'EN_COURS');
}

export const FENETRE_OUVERTURE_POINTAGE_MINUTES = 15;
const FENETRE_OUVERTURE_POINTAGE_MS = FENETRE_OUVERTURE_POINTAGE_MINUTES * 60_000;

export function creneauxPrevisionnels(
  creneaux: CreneauPointage[] = [],
): CreneauPointage[] {
  return creneaux
    .filter((creneau) => (
      creneau.type_creneau === 'PREVISIONNEL'
      && !creneau.est_pause
      && Boolean(creneau.fin)
    ))
    .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
}

/**
 * Les missions ponctuelles créées par l'ancien RPC ne possèdent pas toujours
 * de ligne PREVISIONNEL. Leur plage globale (24 h maximum) est alors le seul
 * horaire contractuel disponible. Une mission longue n'est jamais étalée par
 * défaut : sans créneaux détaillés, son planning reste à confirmer.
 */
export function ajouterRepliMissionPonctuelle(
  creneaux: CreneauPointage[] = [],
  mission: PeriodeMissionPointage,
): CreneauPointage[] {
  if (creneauxPrevisionnels(creneaux).length > 0) return creneaux;

  const debutMs = new Date(mission.debut_le).getTime();
  const finMs = new Date(mission.fin_le).getTime();
  const dureeMs = finMs - debutMs;
  if (!Number.isFinite(dureeMs) || dureeMs <= 0 || dureeMs > 24 * 60 * 60_000) {
    return creneaux;
  }

  return [
    ...creneaux,
    {
      id: `mission-ponctuelle-${mission.id ?? mission.debut_le}`,
      debut: mission.debut_le,
      fin: mission.fin_le,
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    },
  ];
}

export function creneauChevauchePeriode(
  creneau: CreneauPointage,
  debutPeriode: Date,
  finPeriode: Date,
): boolean {
  if (creneau.type_creneau !== 'PREVISIONNEL' || creneau.est_pause || !creneau.fin) {
    return false;
  }

  return new Date(creneau.debut).getTime() < finPeriode.getTime()
    && new Date(creneau.fin).getTime() > debutPeriode.getTime();
}

export function prochainCreneauPointage(
  creneaux: CreneauPointage[] = [],
  maintenant = new Date(),
): CreneauPointage | null {
  const maintenantMs = maintenant.getTime();
  return creneauxPrevisionnels(creneaux)
    .find((creneau) => new Date(creneau.fin!).getTime() >= maintenantMs)
    ?? null;
}

export function evaluerDisponibilitePointage({
  creneaux,
  contratStatut,
  maintenant = new Date(),
}: {
  creneaux: CreneauPointage[];
  contratStatut?: string | null;
  maintenant?: Date;
}): DisponibilitePointage {
  const segmentOuvert = creneaux
    .filter((creneau) => (
      creneau.type_creneau === 'EFFECTIF'
      && !creneau.est_pause
      && !creneau.fin
    ))
    .sort((a, b) => new Date(b.debut).getTime() - new Date(a.debut).getTime())[0];

  // Un départ doit toujours rester possible si une arrivée a déjà été enregistrée.
  if (segmentOuvert) {
    return {
      peutPointer: true,
      action: 'FERMETURE',
      motif: null,
      creneauCourant: segmentOuvert,
      prochainCreneau: null,
    };
  }

  const planifies = creneauxPrevisionnels(creneaux);
  const maintenantMs = maintenant.getTime();
  const creneauCourant = planifies.find((creneau) => {
    const ouvertureMs = new Date(creneau.debut).getTime() - FENETRE_OUVERTURE_POINTAGE_MS;
    const finMs = new Date(creneau.fin!).getTime();
    return maintenantMs >= ouvertureMs && maintenantMs <= finMs;
  }) ?? null;
  const prochainCreneau = planifies.find(
    (creneau) => new Date(creneau.debut).getTime() > maintenantMs,
  ) ?? null;

  if (contratStatut !== 'SIGNE_COMPLET') {
    return {
      peutPointer: false,
      action: null,
      motif: 'CONTRAT',
      creneauCourant,
      prochainCreneau,
    };
  }

  if (creneauCourant) {
    return {
      peutPointer: true,
      action: 'OUVERTURE',
      motif: null,
      creneauCourant,
      prochainCreneau,
    };
  }

  return {
    peutPointer: false,
    action: null,
    motif: planifies.length > 0 ? 'HORS_CRENEAU' : 'AUCUN_CRENEAU',
    creneauCourant: null,
    prochainCreneau,
  };
}

export function evaluerTerminaisonMission({
  creneaux,
  finMission,
  presences = [],
  maintenant = new Date(),
}: {
  creneaux: CreneauPointage[];
  finMission: string;
  presences?: Array<{ pointage_depart_le?: string | null }>;
  maintenant?: Date;
}): EtatTerminaisonMission {
  const planningIncomplet = creneaux.some((creneau) => (
    creneau.type_creneau === 'PREVISIONNEL'
    && !creneau.est_pause
    && !creneau.fin
  ));
  const finsPlanifiees = creneauxPrevisionnels(creneaux)
    .map((creneau) => new Date(creneau.fin!).getTime())
    .filter(Number.isFinite);
  const finReferenceMs = finsPlanifiees.length > 0
    ? Math.max(...finsPlanifiees)
    : new Date(finMission).getTime();
  const finReference = new Date(finReferenceMs);

  if (planningIncomplet) {
    return { peutTerminer: false, motif: 'PLANNING_INCOMPLET', finReference };
  }
  if (!Number.isFinite(finReferenceMs) || maintenant.getTime() < finReferenceMs) {
    return { peutTerminer: false, motif: 'AVANT_DERNIER_CRENEAU', finReference };
  }

  const effectifs = creneaux.filter((creneau) => (
    creneau.type_creneau === 'EFFECTIF' && !creneau.est_pause
  ));
  if (effectifs.some((creneau) => !creneau.fin)) {
    return { peutTerminer: false, motif: 'SEGMENT_OUVERT', finReference };
  }
  const departEnregistre = effectifs.some((creneau) => Boolean(creneau.fin))
    || presences.some((presence) => Boolean(presence.pointage_depart_le));
  if (!departEnregistre) {
    return { peutTerminer: false, motif: 'AUCUN_DEPART', finReference };
  }
  return { peutTerminer: true, motif: null, finReference };
}
