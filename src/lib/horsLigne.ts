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

export function stockerPointageHorsLigne(
  missionId: string,
  type: 'arrivee' | 'depart',
  presenceId?: string,
  utiliserGps = false,
) {
  if (!utiliserGps) {
    sauvegarderLocal({
      missionId, type,
      horodatage: new Date().toISOString(),
      lat: null, lng: null, precision: null,
      idTerminal: genererIdTerminal(),
      presenceId,
    });
    return;
  }

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
  const existants = lirePointagesValides();
  existants.push(pointage);
  // Une file locale courte évite de conserver indéfiniment des coordonnées GPS
  // sur un appareil partagé. Les plus anciennes sont abandonnées en premier.
  localStorage.setItem('pointages_hors_ligne', JSON.stringify(existants.slice(-20)));
}

export function getPointagesEnAttente(): PointageHorsLigne[] {
  const valides = lirePointagesValides();
  localStorage.setItem('pointages_hors_ligne', JSON.stringify(valides));
  return valides;
}

function lirePointagesValides(): PointageHorsLigne[] {
  try {
    const valeur = JSON.parse(localStorage.getItem('pointages_hors_ligne') || '[]');
    if (!Array.isArray(valeur)) return [];
    const limite = Date.now() - 24 * 60 * 60 * 1000;
    return valeur.filter((pointage): pointage is PointageHorsLigne =>
      pointage != null
      && typeof pointage.missionId === 'string'
      && (pointage.type === 'arrivee' || pointage.type === 'depart')
      && typeof pointage.horodatage === 'string'
      && new Date(pointage.horodatage).getTime() >= limite,
    );
  } catch {
    return [];
  }
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
