import { genererIdTerminal } from './terminal';

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
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      sauvegarderLocal({
        missionId, type,
        horodatage: new Date().toISOString(),
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        precision: pos.coords.accuracy,
        idTerminal: genererIdTerminal(),
        presenceId,
      });
    },
    () => {
      sauvegarderLocal({
        missionId, type,
        horodatage: new Date().toISOString(),
        lat: null, lng: null, precision: null,
        idTerminal: genererIdTerminal(),
        presenceId,
      });
    }
  );
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
