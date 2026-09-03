import { describe, expect, it } from 'vitest';
import { construireHistoriqueEffectifsSansPresence } from './presencesSoignantUi';

describe('historique des présences soignant', () => {
  it('rend visible une mission historique alimentée uniquement par les segments effectifs', () => {
    const resultat = construireHistoriqueEffectifsSansPresence({
      missions: [{
        id: 'mission-longue',
        intitule: 'Mission longue',
        etablissement_id: 'etab-1',
        statut: 'TERMINEE',
      }],
      presences: [],
      creneauxParMission: {
        'mission-longue': [
          { id: 'prevu', debut: '2026-07-06T06:00:00Z', fin: '2026-07-06T14:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' },
          { id: 'effectif', debut: '2026-07-06T06:00:00Z', fin: '2026-07-06T14:00:00Z', est_pause: false, type_creneau: 'EFFECTIF' },
        ],
      },
      etablissements: { 'etab-1': { nom: 'Clinique Test' } },
      soignantId: 'soignant-1',
    });

    expect(resultat).toEqual([
      expect.objectContaining({
        id: 'effectifs-mission-mission-longue',
        mission_id: 'mission-longue',
        origine_effectifs_sans_presence: true,
        pointage_arrivee_le: '2026-07-06T06:00:00Z',
        pointage_depart_le: '2026-07-06T14:00:00Z',
        missions: expect.objectContaining({
          etablissements: { nom: 'Clinique Test' },
        }),
      }),
    ]);
  });

  it('ne duplique ni une présence existante ni une mission sans segment effectif fermé', () => {
    const resultat = construireHistoriqueEffectifsSansPresence({
      missions: [{ id: 'avec-presence' }, { id: 'sans-effectif' }],
      presences: [{ mission_id: 'avec-presence' }],
      creneauxParMission: {
        'avec-presence': [{ debut: '2026-07-06T06:00:00Z', fin: '2026-07-06T14:00:00Z', est_pause: false, type_creneau: 'EFFECTIF' }],
        'sans-effectif': [{ debut: '2026-07-07T06:00:00Z', fin: '2026-07-07T14:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' }],
      },
      etablissements: {},
      soignantId: 'soignant-1',
    });

    expect(resultat).toEqual([]);
  });
});
