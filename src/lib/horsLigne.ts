import { genererIdTerminal } from './terminal';
import { getCurrentPosition } from './geoloc';

export interface PointageHorsLigne {
  missionId: string;
  type: 'arrivee' | 'depart';
  horodatage: string;
  lat: number | null;
  lng: number | null;
  precision: number | null;
  idTerminal: string;
  presenceId?: string;
}

export function stockerPointageHorsLigne(missionId: string, type: 'arrivee' | 'depart', presenceId?: string) {
  // Sprint 4 PR 5 : wrapper unifié Capacitor/web — natif si app, web sinon
  getCurrentPosition({ enableHighAccuracy: true, timeout: 10000 })
    .then((result) => {
      sauvegarderLocal({
        missionId, type,
        horodatage: new Date().toISOString(),
        lat: result.coords.latitude,
        lng: result.coords.longitude,
        precision: result.coords.accuracy,
        idTerminal: genererIdTerminal(),
        presenceId,
      });
    })
    .catch(() => {
      sauvegarderLocal({
        missionId, type,
        horodatage: new Date().toISOString(),
        lat: null, lng: null, precision: null,
        idTerminal: genererIdTerminal(),
        presenceId,
      });
    });
}

function sauvegarderLocal(pointage: PointageHorsLigne) {
  const existants = JSON.parse(localStorage.getItem('pointages_hors_ligne') || '[]');
  existants.push(pointage);
  localStorage.setItem('pointages_hors_ligne', JSON.stringify(existants));
}

export function getPointagesEnAttente(): PointageHorsLigne[] {
  return JSON.parse(localStorage.getItem('pointages_hors_ligne') || '[]');
}

export function clearPointagesEnAttente() {
  localStorage.removeItem('pointages_hors_ligne');
}

/** Replace localStorage with only the failed pointages (for partial sync) */
export function sauvegarderPointagesRestants(pointages: PointageHorsLigne[]) {
  if (pointages.length === 0) {
    localStorage.removeItem('pointages_hors_ligne');
  } else {
    localStorage.setItem('pointages_hors_ligne', JSON.stringify(pointages));
  }
}
