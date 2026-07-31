import {
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';

const MINUTE_MS = 60_000;

export interface SynthesePresenceMission {
  previsionnels: CreneauPointage[];
  effectifsFermes: CreneauPointage[];
  effectifsOuverts: CreneauPointage[];
  minutesPlanifiees: number;
  minutesTravaillees: number;
  dernierPrevisionnelFin: Date | null;
  planningTermine: boolean;
  validationPossible: boolean;
}

function dureeMinutes(creneau: CreneauPointage): number {
  if (!creneau.fin) return 0;
  const debut = new Date(creneau.debut).getTime();
  const fin = new Date(creneau.fin).getTime();
  if (!Number.isFinite(debut) || !Number.isFinite(fin) || fin <= debut) return 0;
  return (fin - debut) / MINUTE_MS;
}

/**
 * Synthèse canonique d'une mission pointée.
 *
 * Les champs de `presences` ne représentent que la première arrivée et le
 * dernier départ d'une mission. Ils incluent donc les jours de repos d'une
 * mission multi-créneaux et ne doivent jamais servir à calculer du temps
 * travaillé. Seuls les créneaux EFFECTIF fermés sont additionnés ici.
 */
export function construireSynthesePresenceMission(
  creneaux: CreneauPointage[] = [],
  maintenant = new Date(),
): SynthesePresenceMission {
  const previsionnels = creneauxPrevisionnels(creneaux);
  const effectifs = creneaux
    .filter((creneau) => creneau.type_creneau === 'EFFECTIF' && !creneau.est_pause)
    .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
  const effectifsFermes = effectifs.filter((creneau) => Boolean(creneau.fin));
  const effectifsOuverts = effectifs.filter((creneau) => !creneau.fin);
  const dernierPrevisionnel = previsionnels.at(-1) ?? null;
  const dernierPrevisionnelFin = dernierPrevisionnel?.fin
    ? new Date(dernierPrevisionnel.fin)
    : null;
  const planningTermine = Boolean(
    dernierPrevisionnelFin
    && Number.isFinite(dernierPrevisionnelFin.getTime())
    && maintenant.getTime() >= dernierPrevisionnelFin.getTime(),
  );

  return {
    previsionnels,
    effectifsFermes,
    effectifsOuverts,
    minutesPlanifiees: previsionnels.reduce((total, creneau) => total + dureeMinutes(creneau), 0),
    minutesTravaillees: effectifsFermes.reduce((total, creneau) => total + dureeMinutes(creneau), 0),
    dernierPrevisionnelFin,
    planningTermine,
    validationPossible: planningTermine
      && effectifsOuverts.length === 0
      && effectifsFermes.length > 0,
  };
}

export function formatDureeMinutes(minutes: number): string {
  const heures = Math.floor(minutes / 60);
  const reste = Math.round(minutes % 60);
  return `${heures}h${String(reste).padStart(2, '0')}`;
}
