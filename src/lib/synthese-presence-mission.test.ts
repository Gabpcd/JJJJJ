import { describe, expect, it } from 'vitest';
import { construireSynthesePresenceMission } from './synthese-presence-mission';

describe('construireSynthesePresenceMission', () => {
  it('additionne uniquement les créneaux EFFECTIF fermés', () => {
    const synthese = construireSynthesePresenceMission([
      { debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { debut: '2026-07-06T08:15:00+02:00', fin: '2026-07-06T14:15:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
      { debut: '2026-07-31T08:00:00+02:00', fin: null, est_pause: false, type_creneau: 'EFFECTIF' },
      { debut: '2026-07-06T12:00:00+02:00', fin: '2026-07-06T12:30:00+02:00', est_pause: true, type_creneau: 'EFFECTIF' },
    ], new Date('2026-09-01T08:00:00+02:00'));

    expect(synthese.minutesPlanifiees).toBe(16 * 60);
    expect(synthese.minutesTravaillees).toBe(6 * 60);
    expect(synthese.effectifsOuverts).toHaveLength(1);
    expect(synthese.validationPossible).toBe(false);
  });

  it('ne permet la validation qu’après le dernier prévu, sans effectif ouvert', () => {
    const creneaux = [
      { debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
    ];

    expect(construireSynthesePresenceMission(
      creneaux,
      new Date('2026-07-31T12:00:00+02:00'),
    ).validationPossible).toBe(false);
    expect(construireSynthesePresenceMission(
      creneaux,
      new Date('2026-08-31T16:01:00+02:00'),
    ).validationPossible).toBe(true);
  });
});
