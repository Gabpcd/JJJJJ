import { describe, expect, it } from 'vitest';
import {
  construireExportPaiePeriode,
  repartirMontantParCreneau,
  type MissionExportPaieSource,
} from './export-paie-planning';

const missionLongue: MissionExportPaieSource = {
  id: 'mission-longue',
  intitule: 'Mission intermittente',
  statut: 'TERMINEE',
  debut_le: '2026-07-06T06:00:00.000Z',
  fin_le: '2026-08-31T14:00:00.000Z',
  nb_creneaux: 2,
  duree_heures: 16,
  total_brut: 1_000,
  montant_ifm: 100,
  montant_icp: 110,
  presences: [{ valide_par_etablissement: true }],
};

const effectifs = [
  {
    id: 'effectif-juillet',
    mission_id: missionLongue.id,
    debut: '2026-07-06T06:00:00.000Z',
    fin: '2026-07-06T14:00:00.000Z',
    est_pause: false,
    type_creneau: 'EFFECTIF',
  },
  {
    id: 'effectif-aout',
    mission_id: missionLongue.id,
    debut: '2026-08-31T06:00:00.000Z',
    fin: '2026-08-31T14:00:00.000Z',
    est_pause: false,
    type_creneau: 'EFFECTIF',
  },
];

const previsionnels = effectifs.map((creneau) => ({
  ...creneau,
  id: creneau.id.replace('effectif', 'prev'),
  type_creneau: 'PREVISIONNEL',
}));

describe('construireExportPaiePeriode', () => {
  for (const nbCreneaux of [0, 1]) {
    for (const statut of ['TERMINEE', 'EN_COURS']) {
      it(`isole deux missions ${statut} avec nb_creneaux=${nbCreneaux}`, () => {
        const missions = [8, 4].map((heures, index): MissionExportPaieSource => ({
          ...missionLongue,
          id: `mission-${index}`,
          statut,
          nb_creneaux: nbCreneaux,
          debut_le: `2026-07-0${index + 6}T06:00:00.000Z`,
          fin_le: `2026-07-0${index + 6}T${String(6 + heures).padStart(2, '0')}:00:00.000Z`,
          total_brut: heures * 50,
        }));
        const prevus = missions.map(m => ({
          mission_id: m.id, debut: m.debut_le!, fin: m.fin_le!,
          est_pause: false, type_creneau: 'PREVISIONNEL',
        }));
        const pointages = statut === 'EN_COURS' ? prevus.map((c, index) => ({
          ...c,
          fin: `2026-07-0${index + 6}T${index === 0 ? '10' : '08'}:00:00.000Z`,
          type_creneau: 'EFFECTIF',
        })) : [];
        // Même lot SQL pour les deux missions.
        const creneaux = [...prevus, ...pointages];
        const resultat = construireExportPaiePeriode(missions, creneaux, 2026, 7);
        expect(resultat.map(m => ({
          id: m.id, heures: m.duree_heures, brut: m.total_brut,
          ratio: m.ratio_periode, source: m.planning_source,
          creneaux: m.creneaux_export.map(c => [c.debut, c.fin]),
        }))).toEqual(missions.map((m, index) => ({
          id: m.id,
          heures: (index === 0 ? 8 : 4) * (statut === 'EN_COURS' ? 0.5 : 1),
          brut: (index === 0 ? 400 : 200) * (statut === 'EN_COURS' ? 0.5 : 1),
          ratio: statut === 'EN_COURS' ? 0.5 : 1,
          source: statut === 'EN_COURS' ? 'EFFECTIF' : 'PREVISIONNEL_VALIDE',
          creneaux: [[m.debut_le, (statut === 'EN_COURS' ? pointages : prevus)[index].fin]],
        })));
        expect(construireExportPaiePeriode(missions, [...creneaux].reverse(), 2026, 7)).toEqual(resultat);
        expect(construireExportPaiePeriode(missions, [
          ...creneaux, { ...prevus[0], mission_id: undefined, fin: null },
        ], 2026, 7)).toEqual(resultat);
      });
    }

    it(`conserve le repli ponctuel propre à chaque mission sans ligne avec nb_creneaux=${nbCreneaux}`, () => {
      const ponctuelle = { ...missionLongue, id: 'ponctuelle', nb_creneaux: nbCreneaux,
        debut_le: effectifs[0].debut, fin_le: effectifs[0].fin, total_brut: 400 };
      const [resultat] = construireExportPaiePeriode([ponctuelle], previsionnels, 2026, 7);
      expect(resultat.creneaux_export).toEqual([{ debut: ponctuelle.debut_le, fin: ponctuelle.fin_le, duree_heures: 8 }]);
      expect(resultat.total_brut).toBe(400);
      expect(resultat.ratio_periode).toBe(1);
    });
  }

  for (const statut of ['TERMINEE', 'EN_COURS']) {
    it(`un créneau étranger ne complète pas le planning manquant d’une mission ${statut}`, () => {
      expect(() => construireExportPaiePeriode([{ ...missionLongue, statut }], [
        previsionnels[0],
        { ...previsionnels[1], mission_id: 'autre-mission' },
        ...(statut === 'EN_COURS' ? [effectifs[0]] : []),
      ], 2026, 7)).toThrow(/planning exact.*incomplet/);
    });
  }

  it('conserve la priorité d’un effectif partiel terminé sans emprunter le planning d’une autre mission', () => {
    const [resultat] = construireExportPaiePeriode([missionLongue], [
      ...previsionnels, effectifs[0],
      { ...previsionnels[0], mission_id: 'autre-mission', fin: null },
    ], 2026, 7);
    expect(resultat.planning_source).toBe('EFFECTIF');
    expect(resultat.duree_heures).toBe(8);
    expect(resultat.total_brut).toBe(500);
    expect(resultat.ratio_periode).toBe(0.5);
  });

  it('ventile une mission intermittente sur ses créneaux effectifs du mois', () => {
    const [juillet] = construireExportPaiePeriode([missionLongue], effectifs, 2026, 7);

    expect(juillet.planning_source).toBe('EFFECTIF');
    expect(juillet.creneaux_export).toEqual([{
      debut: '2026-07-06T06:00:00.000Z',
      fin: '2026-07-06T14:00:00.000Z',
      duree_heures: 8,
    }]);
    expect(juillet.duree_heures).toBe(8);
    expect(juillet.ratio_periode).toBe(0.5);
    expect(juillet.total_brut).toBe(500);
    expect(juillet.montant_ifm).toBe(50);
    expect(juillet.montant_icp).toBe(55);
  });

  it('utilise le planning prévisionnel uniquement lorsqu’il est exact et validé', () => {
    const [juillet] = construireExportPaiePeriode([missionLongue], previsionnels, 2026, 7);
    expect(juillet.planning_source).toBe('PREVISIONNEL_VALIDE');
    expect(juillet.duree_heures).toBe(8);
  });

  it('échoue fermé si la présence n’est pas validée ou si un pointage reste ouvert', () => {
    expect(() => construireExportPaiePeriode([
      { ...missionLongue, presences: [] },
    ], effectifs, 2026, 7)).toThrow(/n'est pas validée/);

    expect(() => construireExportPaiePeriode([missionLongue], [
      ...previsionnels,
      { ...effectifs[0], fin: null },
    ], 2026, 7)).toThrow(/encore ouvert/);
  });

  it('inclut seulement les créneaux effectifs validés déjà passés d’une mission en cours', () => {
    const missionEnCours = { ...missionLongue, statut: 'EN_COURS' };
    const [juillet] = construireExportPaiePeriode(
      [missionEnCours],
      [...previsionnels, effectifs[0]],
      2026,
      7,
    );
    const aout = construireExportPaiePeriode(
      [missionEnCours],
      [...previsionnels, effectifs[0]],
      2026,
      8,
    );

    expect(juillet.planning_source).toBe('EFFECTIF');
    expect(juillet.duree_heures).toBe(8);
    expect(juillet.total_brut).toBe(500);
    expect(aout).toEqual([]);
  });

  it('ne remplace jamais un pointage effectif partiel par tout le prévisionnel terminé', () => {
    const [juillet] = construireExportPaiePeriode(
      [missionLongue],
      [...previsionnels, effectifs[0]],
      2026,
      7,
    );
    const aout = construireExportPaiePeriode(
      [missionLongue],
      [...previsionnels, effectifs[0]],
      2026,
      8,
    );

    expect(juillet.planning_source).toBe('EFFECTIF');
    expect(juillet.duree_heures).toBe(8);
    expect(juillet.total_brut).toBe(500);
    expect(aout).toEqual([]);
  });

  it('bloque une ventilation mensuelle de majorations non attribuables aux créneaux', () => {
    expect(() => construireExportPaiePeriode([{
      ...missionLongue,
      heures_nuit: 4,
      montant_majoration_nuit: 25,
    }], effectifs, 2026, 7)).toThrow(/majorations.*ne peuvent pas être attribuées/i);
  });

  it('bloque aussi des majorations non attribuées entre deux créneaux du même mois', () => {
    const missionDeuxJours: MissionExportPaieSource = {
      ...missionLongue,
      id: 'mission-deux-jours',
      debut_le: '2026-07-06T06:00:00.000Z',
      fin_le: '2026-07-07T22:00:00.000Z',
      heures_nuit: 8,
      montant_majoration_nuit: 40,
    };
    const deuxEffectifs = [
      { ...effectifs[0], mission_id: missionDeuxJours.id },
      {
        ...effectifs[1],
        mission_id: missionDeuxJours.id,
        debut: '2026-07-07T14:00:00.000Z',
        fin: '2026-07-07T22:00:00.000Z',
      },
    ];

    expect(() => construireExportPaiePeriode(
      [missionDeuxJours],
      deuxEffectifs,
      2026,
      7,
    )).toThrow(/majorations.*ne peuvent pas être attribuées/i);
  });

  it('coupe une garde à la frontière du mois civil Europe/Paris', () => {
    const missionNuit: MissionExportPaieSource = {
      ...missionLongue,
      id: 'mission-nuit',
      intitule: 'Garde de nuit',
      debut_le: '2026-07-31T21:30:00.000Z',
      fin_le: '2026-07-31T23:30:00.000Z',
      nb_creneaux: 1,
      duree_heures: 2,
      total_brut: 100,
    };
    const creneau = [{
      id: 'nuit',
      mission_id: missionNuit.id,
      debut: missionNuit.debut_le!,
      fin: missionNuit.fin_le!,
      est_pause: false,
      type_creneau: 'EFFECTIF',
    }];

    const [juillet] = construireExportPaiePeriode([missionNuit], creneau, 2026, 7);
    const [aout] = construireExportPaiePeriode([missionNuit], creneau, 2026, 8);

    expect(juillet.duree_heures).toBe(0.5);
    expect(juillet.creneaux_export[0].fin).toBe('2026-07-31T22:00:00.000Z');
    expect(aout.duree_heures).toBe(1.5);
    expect(aout.creneaux_export[0].debut).toBe('2026-07-31T22:00:00.000Z');
    expect(Number(juillet.total_brut) + Number(aout.total_brut)).toBe(100);
  });
});

describe('repartirMontantParCreneau', () => {
  it("conserve exactement le total malgré l'arrondi en centimes", () => {
    const montants = repartirMontantParCreneau(10, [
      { debut: '2026-08-01T06:00:00Z', fin: '2026-08-01T07:00:00Z', duree_heures: 1 },
      { debut: '2026-08-02T06:00:00Z', fin: '2026-08-02T07:00:00Z', duree_heures: 1 },
      { debut: '2026-08-03T06:00:00Z', fin: '2026-08-03T07:00:00Z', duree_heures: 1 },
    ]);

    expect(montants).toEqual([3.34, 3.33, 3.33]);
    expect(montants.reduce((total, montant) => total + montant, 0)).toBe(10);
  });

  it('ne produit jamais un reliquat négatif pour cinq centimes et dix créneaux', () => {
    const creneaux = Array.from({ length: 10 }, (_, index) => ({
      debut: `2026-08-${String(index + 1).padStart(2, '0')}T06:00:00Z`,
      fin: `2026-08-${String(index + 1).padStart(2, '0')}T07:00:00Z`,
      duree_heures: 1,
    }));
    const montants = repartirMontantParCreneau(0.05, creneaux);

    expect(montants).toEqual([0.01, 0.01, 0.01, 0.01, 0.01, 0, 0, 0, 0, 0]);
    expect(montants.every((montant) => montant >= 0)).toBe(true);
    expect(montants.reduce((total, montant) => total + montant, 0)).toBe(0.05);
  });
});
