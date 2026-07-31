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

export function filtrerMissionsEnCours<T extends { statut: string }>(missions: T[]): T[] {
  // Ne pas dépendre de `presences`, désormais legacy : une mission longue peut
  // être EN_COURS entre deux créneaux sans présence ouverte.
  return missions.filter((mission) => mission.statut === 'EN_COURS');
}

const TRENTE_MINUTES = 30 * 60_000;

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

export function creneauChevauchePeriode(
  creneau: CreneauPointage,
  debutPeriode: Date,
  finPeriode: Date,
): boolean {
  if (creneau.type_creneau !== 'PREVISIONNEL' || creneau.est_pause || !creneau.fin) {
    return false;
  }

  return new Date(creneau.debut).getTime() < finPeriode.getTime()
    && new Date(creneau.fin).getTime() >= debutPeriode.getTime();
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
    const ouvertureMs = new Date(creneau.debut).getTime() - TRENTE_MINUTES;
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
