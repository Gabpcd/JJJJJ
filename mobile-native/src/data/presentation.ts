import { formatParis } from '../../../src/lib/date-heure-paris';
import { getLabelProfession } from '../../../src/lib/constantes';
import type { Mission } from './types';

export { defaultFilters } from './business';

const euros = (value: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(value);

export function getProfessionLabel(code: string): string {
  return getLabelProfession(code);
}

export function getMissionRemuneration(mission: Mission): string {
  if (mission.mode_remuneration === 'RETROCESSION') {
    return `Rétrocession ${mission.retrocession_pct ?? '—'} % des honoraires`;
  }
  const rate = mission.taux_horaire_base;
  return rate === null ? 'Taux non renseigné' : `${euros(Number(rate))}/h`;
}

export function formatMissionPeriod(mission: Mission): string {
  const start = formatParis(mission.debut_le, 'dd/MM/yyyy');
  const end = formatParis(mission.fin_le, 'dd/MM/yyyy');
  if (start === end && mission.planning_exact && mission.creneaux_planifies.length === 1) {
    const slot = mission.creneaux_planifies[0];
    return `${start} · ${formatParis(slot.debut, 'HH:mm')}–${slot.fin ? formatParis(slot.fin, 'HH:mm') : '—'}`;
  }
  return `${start === end ? start : `${start} → ${end}`} · ${mission.planning_exact
    ? `${mission.creneaux_planifies.length} créneau${mission.creneaux_planifies.length > 1 ? 'x' : ''}`
    : 'planning à confirmer'}`;
}
