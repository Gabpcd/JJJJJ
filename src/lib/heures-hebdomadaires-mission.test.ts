import { describe, expect, it } from 'vitest';
import {
  additionnerHeuresParSemaine,
  additionnerHeuresSalarieesParSemaine,
  heuresMissionParSemaine,
  missionComptePourPlafond48h,
  missionPlafond48hConditionnel,
  planningMissionHebdomadaireDisponible,
  type CreneauMissionPourCalculHebdomadaire,
  type MissionPourCalculHebdomadaire,
} from './heures-hebdomadaires-mission';

const mission: MissionPourCalculHebdomadaire = {
  id: 'mission-ete',
  debut_le: '2026-07-20T13:00:00+02:00',
  fin_le: '2026-07-31T21:00:00+02:00',
  duree_heures: 80,
};

function creneau(jour: string, type = 'PREVISIONNEL'): CreneauMissionPourCalculHebdomadaire {
  return {
    mission_id: mission.id,
    debut: `${jour}T13:00:00+02:00`,
    fin: `${jour}T21:00:00+02:00`,
    est_pause: false,
    type_creneau: type,
  };
}

describe('heuresMissionParSemaine', () => {
  it('répartit la mission IDE du 20 au 31 juillet en 40 h + 40 h', () => {
    const jours = [
      '2026-07-20', '2026-07-21', '2026-07-22', '2026-07-23', '2026-07-24',
      '2026-07-27', '2026-07-28', '2026-07-29', '2026-07-30', '2026-07-31',
    ];

    expect(heuresMissionParSemaine(mission, jours.map((jour) => creneau(jour))))
      .toMatchObject([
        { cleSemaine: '2026-07-20', heures: 40 },
        { cleSemaine: '2026-07-27', heures: 40 },
      ]);
  });

  it('ne double pas les heures effectives quand le prévisionnel existe', () => {
    const resultat = heuresMissionParSemaine(mission, [
      creneau('2026-07-20'),
      creneau('2026-07-20', 'EFFECTIF'),
    ]);
    expect(resultat).toMatchObject([{ cleSemaine: '2026-07-20', heures: 8 }]);
  });

  it('retient les heures effectives d\'une mission terminée', () => {
    const resultat = heuresMissionParSemaine(
      { ...mission, statut: 'TERMINEE' },
      [
        creneau('2026-07-20'),
        {
          ...creneau('2026-07-20', 'EFFECTIF'),
          fin: '2026-07-20T20:00:00+02:00',
        },
      ],
    );
    expect(resultat).toMatchObject([{ cleSemaine: '2026-07-20', heures: 7 }]);
  });

  it('scinde un créneau de nuit qui franchit le lundi', () => {
    const resultat = heuresMissionParSemaine(
      { ...mission, debut_le: '2026-07-26T20:00:00+02:00', fin_le: '2026-07-27T08:00:00+02:00', duree_heures: 12 },
      [{
        mission_id: mission.id,
        debut: '2026-07-26T20:00:00+02:00',
        fin: '2026-07-27T08:00:00+02:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      }],
    );
    expect(resultat).toMatchObject([
      { cleSemaine: '2026-07-20', heures: 4 },
      { cleSemaine: '2026-07-27', heures: 8 },
    ]);
  });

  it('additionne les missions existantes semaine par semaine', () => {
    const autre = { ...mission, id: 'mission-existante', duree_heures: 8 };
    const resultat = additionnerHeuresParSemaine(
      [mission, autre],
      [
        creneau('2026-07-20'),
        { ...creneau('2026-07-20'), mission_id: autre.id },
      ],
    );
    expect(resultat.get('2026-07-20')?.heures).toBe(16);
  });

  it('ne rabat pas une mission multi-créneaux sur ses 80 h globales si les créneaux manquent', () => {
    expect(heuresMissionParSemaine({ ...mission, nb_creneaux: 10 }, [])).toEqual([]);
  });

  it('exclut une pause explicite du compteur de complétude et des heures', () => {
    const travail = creneau('2026-07-20');
    const secondTravail = creneau('2026-07-21');
    const pause: CreneauMissionPourCalculHebdomadaire = {
      mission_id: mission.id,
      debut: '2026-07-20T16:00:00+02:00',
      fin: '2026-07-20T16:30:00+02:00',
      est_pause: true,
      type_creneau: 'PREVISIONNEL',
    };
    const missionAvecPause = { ...mission, nb_creneaux: 2 };

    expect(planningMissionHebdomadaireDisponible(missionAvecPause, [travail, pause])).toBe(false);
    expect(heuresMissionParSemaine(missionAvecPause, [travail, pause])).toEqual([]);
    expect(planningMissionHebdomadaireDisponible(missionAvecPause, [travail, secondTravail, pause])).toBe(true);
    expect(heuresMissionParSemaine(missionAvecPause, [travail, secondTravail, pause]))
      .toMatchObject([{ cleSemaine: '2026-07-20', heures: 16 }]);
  });

  it('applique le même ordre de résolution du régime que le SQL', () => {
    expect(missionComptePourPlafond48h({ ...mission, type_contrat_recherche: 'LIBERAL' })).toBe(false);
    expect(missionComptePourPlafond48h({ ...mission, type_contrat_recherche: 'TOUS' })).toBe(true);
    expect(missionComptePourPlafond48h({
      ...mission,
      type_contrat_applique: 'LIBERAL',
      choix_contrat_soignant: 'SALARIE',
      type_contrat_recherche: 'SALARIE',
    })).toBe(false);
    expect(missionComptePourPlafond48h({
      ...mission,
      choix_contrat_soignant: ' liberal ',
      type_contrat_recherche: 'SALARIE',
    })).toBe(false);
    expect(missionComptePourPlafond48h({
      ...mission,
      choix_contrat_soignant: ' ',
      type_contrat_recherche: 'LIBERAL',
    })).toBe(false);
  });

  it('exclut les missions libérales des heures existantes du plafond salarié', () => {
    const salariee = { ...mission, id: 'mission-salariee', type_contrat_applique: 'SALARIE' };
    const liberale = { ...mission, id: 'mission-liberale', type_contrat_applique: 'LIBERAL' };
    const resultat = additionnerHeuresSalarieesParSemaine(
      [salariee, liberale],
      [
        { ...creneau('2026-07-20'), mission_id: salariee.id },
        { ...creneau('2026-07-20'), mission_id: liberale.id },
      ],
    );

    expect(resultat.get('2026-07-20')?.heures).toBe(8);
  });

  it('identifie uniquement une candidate TOUS sans choix comme conditionnelle', () => {
    expect(missionPlafond48hConditionnel({ ...mission, type_contrat_recherche: 'TOUS' })).toBe(true);
    expect(missionPlafond48hConditionnel({
      ...mission,
      type_contrat_recherche: 'TOUS',
      choix_contrat_soignant: 'LIBERAL',
    })).toBe(false);
    expect(missionPlafond48hConditionnel({
      ...mission,
      type_contrat_recherche: 'TOUS',
      type_contrat_applique: 'SALARIE',
    })).toBe(false);
    expect(missionPlafond48hConditionnel({ ...mission, type_contrat_recherche: 'SALARIE' })).toBe(false);
  });
});
