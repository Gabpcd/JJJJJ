import { describe, expect, it } from 'vitest';
import { calculerSemainesAttestationProposition } from './semaines-attestation-proposition';
import type {
  CreneauMissionPourCalculHebdomadaire,
  MissionPourCalculHebdomadaire,
} from './heures-hebdomadaires-mission';

const candidate: MissionPourCalculHebdomadaire = {
  id: 'candidate',
  debut_le: '2026-07-20T08:00:00+02:00',
  fin_le: '2026-07-31T16:00:00+02:00',
  duree_heures: 80,
  nb_creneaux: 10,
  type_contrat_applique: 'SALARIE',
};

function creneau(missionId: string, jour: string): CreneauMissionPourCalculHebdomadaire {
  return {
    mission_id: missionId,
    debut: `${jour}T08:00:00+02:00`,
    fin: `${jour}T16:00:00+02:00`,
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  };
}

describe('calculerSemainesAttestationProposition', () => {
  it('ventile la proposition et les missions existantes sur chaque semaine exacte', () => {
    const jours = [
      '2026-07-20', '2026-07-21', '2026-07-22', '2026-07-23', '2026-07-24',
      '2026-07-27', '2026-07-28', '2026-07-29', '2026-07-30', '2026-07-31',
    ];
    const existante: MissionPourCalculHebdomadaire = {
      id: 'existante',
      debut_le: '2026-07-27T18:00:00+02:00',
      fin_le: '2026-07-28T02:00:00+02:00',
      duree_heures: 8,
      nb_creneaux: 1,
      statut: 'ASSIGNEE',
      type_contrat_applique: 'SALARIE',
    };

    const resultat = calculerSemainesAttestationProposition(
      candidate,
      [existante],
      [
        ...jours.map((jour) => creneau(candidate.id, jour)),
        {
          ...creneau(existante.id, '2026-07-27'),
          debut: existante.debut_le,
          fin: existante.fin_le,
        },
      ],
    );

    expect(resultat).toEqual({
      ok: true,
      semaines: [
        { semaineISO: '2026-07-20', heuresJoleneSemaine: 40 },
        { semaineISO: '2026-07-27', heuresJoleneSemaine: 48 },
      ],
    });
  });

  it('refuse le repli sur les 80 heures globales sans créneaux datés', () => {
    expect(calculerSemainesAttestationProposition(candidate, [], []))
      .toMatchObject({ ok: false, semaines: [] });
  });
});
