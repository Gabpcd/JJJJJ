import { describe, expect, it } from 'vitest';
import {
  calculerHeuresNuitParis,
  datesDansPlage,
  materialiserCreneau,
  materialiserPlanning,
  validerPlanningDates,
  type CreneauPlanningDate,
  type JourPlanningDate,
} from './planning-derive';

function creneau(
  clientId: string,
  heureDebut = '07:00',
  heureFin = '19:00',
  finJourSuivant = false,
): CreneauPlanningDate {
  return { clientId, heureDebut, heureFin, finJourSuivant };
}

function jour(date: string, actif = true, creneaux: CreneauPlanningDate[] = [creneau(date)]): JourPlanningDate {
  return { date, actif, creneaux };
}

describe('planning exact par date', () => {
  it('conserve chaque date réelle et exclut explicitement les dates de repos', () => {
    const dates = datesDansPlage('2026-07-22', '2026-07-29');
    expect(dates).toEqual([
      '2026-07-22', '2026-07-23', '2026-07-24', '2026-07-25',
      '2026-07-26', '2026-07-27', '2026-07-28', '2026-07-29',
    ]);

    const resultat = materialiserPlanning([
      jour('2026-07-22'),
      jour('2026-07-23', false),
      jour('2026-07-29', true, [creneau('dernier', '09:00', '13:00')]),
    ]);
    expect(resultat.map((item) => item.date)).toEqual(['2026-07-22', '2026-07-29']);
  });

  it('autorise plusieurs créneaux non chevauchants sur la même date', () => {
    const planning = [jour('2026-08-03', true, [
      creneau('matin', '07:00', '11:00'),
      creneau('soir', '15:00', '19:00'),
    ])];
    const validation = validerPlanningDates(planning);
    expect(validation.valide).toBe(true);
    expect(materialiserPlanning(planning)).toHaveLength(2);
    expect(validation.semaines[0].totalHeures).toBe(8);
  });

  it('bloque deux créneaux qui se chevauchent', () => {
    const validation = validerPlanningDates([jour('2026-08-03', true, [
      creneau('un', '07:00', '12:00'),
      creneau('deux', '11:30', '16:00'),
    ])]);
    expect(validation.valide).toBe(false);
    expect(validation.erreurs.some((erreur) => erreur.type === 'CHEVAUCHEMENT')).toBe(true);
  });
});

describe('nuits, fuseau Europe/Paris et repos réel', () => {
  it('calcule exactement les fractions de nuit aux bornes 21 h et 06 h', () => {
    expect(calculerHeuresNuitParis([
      { debut: '2026-08-03T18:45:00.000Z', fin: '2026-08-03T19:15:00.000Z' },
      { debut: '2026-08-04T03:45:00.000Z', fin: '2026-08-04T04:15:00.000Z' },
    ])).toBe(0.5);
  });

  it("respecte la durée absolue de la nuit lors du passage à l'heure d'été", () => {
    expect(calculerHeuresNuitParis([
      { debut: '2026-03-28T20:00:00.000Z', fin: '2026-03-29T04:00:00.000Z' },
    ])).toBe(8);
  });

  it('exige explicitement « lendemain » lorsque la fin est avant le début', () => {
    const invalide = materialiserCreneau('2026-08-02', creneau('nuit', '20:00', '08:00', false));
    const valide = materialiserCreneau('2026-08-02', creneau('nuit', '20:00', '08:00', true));
    expect(invalide.valeur).toBeNull();
    expect(valide.valeur?.dateFin).toBe('2026-08-03');
    expect(valide.valeur?.dureeHeures).toBe(12);
  });

  it('détecte le repos insuffisant du dimanche soir au lundi matin', () => {
    const validation = validerPlanningDates([
      jour('2026-08-02', true, [creneau('dimanche-nuit', '20:00', '08:00', true)]),
      jour('2026-08-03', true, [creneau('lundi', '09:00', '17:00')]),
    ]);
    const erreur = validation.erreurs.find((item) => item.type === 'REPOS_11H');
    expect(validation.valide).toBe(false);
    expect(erreur?.datesAffectees).toEqual(['2026-08-02', '2026-08-03']);
    expect(erreur?.message).toContain('1 h');
  });

  it("calcule la durée absolue lors du passage à l'heure d'été à Paris", () => {
    const resultat = materialiserCreneau('2026-03-29', creneau('dst', '01:00', '05:00'));
    expect(resultat.erreur).toBeNull();
    expect(resultat.valeur?.dureeHeures).toBe(3);
    expect(resultat.valeur?.debut).toBe('2026-03-29T00:00:00.000Z');
    expect(resultat.valeur?.fin).toBe('2026-03-29T03:00:00.000Z');
  });

  it("refuse un creneau dont l'heure saisie n'existe pas a Paris", () => {
    const resultat = materialiserCreneau('2026-03-29', creneau('trou-dst', '02:30', '05:00'));

    expect(resultat.valeur).toBeNull();
    expect(resultat.erreur).toContain("n\u2019existe pas à Paris");
    const validation = validerPlanningDates([
      jour('2026-03-29', true, [creneau('trou-dst', '02:30', '05:00')]),
    ]);
    expect(validation.valide).toBe(false);
    expect(validation.erreurs).toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'CRENEAU_INVALIDE', gravite: 'bloquant' }),
    ]));
  });

  it("conserve l'occurrence initiale exacte pendant l'heure répétée d'automne", () => {
    const resultat = materialiserCreneau('2026-10-25', {
      clientId: 'heure-repetee',
      heureDebut: '02:30',
      heureFin: '03:30',
      finJourSuivant: false,
      debutInitial: '2026-10-25T00:30:00.000Z',
      finInitial: '2026-10-25T02:30:00.000Z',
    });

    expect(resultat.erreur).toBeNull();
    expect(resultat.valeur).toEqual(expect.objectContaining({
      debut: '2026-10-25T00:30:00.000Z',
      fin: '2026-10-25T02:30:00.000Z',
      dureeHeures: 2,
    }));
  });

  it("bloque une nouvelle saisie ambiguë pendant l'heure répétée d'automne", () => {
    const resultat = materialiserCreneau('2026-10-25', creneau('heure-repetee-nouvelle', '02:30', '03:30'));

    expect(resultat.valeur).toBeNull();
    expect(resultat.erreur).toContain('existe deux fois');
  });

  it("préserve séparément une borne initiale ambiguë quand l'autre est modifiée", () => {
    const resultat = materialiserCreneau('2026-10-25', {
      clientId: 'heure-repetee-modifiee',
      heureDebut: '02:30',
      heureFin: '04:30',
      finJourSuivant: false,
      debutInitial: '2026-10-25T00:30:00.000Z',
      finInitial: '2026-10-25T02:30:00.000Z',
    });

    expect(resultat.erreur).toBeNull();
    expect(resultat.valeur).toEqual(expect.objectContaining({
      debut: '2026-10-25T00:30:00.000Z',
      fin: '2026-10-25T03:30:00.000Z',
      dureeHeures: 3,
    }));
  });
});

describe('plafond de 48 h par semaine civile réelle', () => {
  it('bloque 50 h réparties sur cinq dates de la même semaine', () => {
    const planning = ['2026-07-20', '2026-07-21', '2026-07-22', '2026-07-23', '2026-07-24']
      .map((date) => jour(date, true, [creneau(date, '07:00', '17:00')]));
    const validation = validerPlanningDates(planning);
    expect(validation.semaines).toHaveLength(1);
    expect(validation.semaines[0].totalHeures).toBe(50);
    expect(validation.semaines[0].depasse48).toBe(true);
    expect(validation.valide).toBe(false);
  });

  it('répartit une garde dimanche→lundi entre les deux semaines civiles', () => {
    const validation = validerPlanningDates([
      jour('2026-08-02', true, [creneau('nuit', '22:00', '06:00', true)]),
    ]);
    expect(validation.semaines.map((semaine) => [semaine.cleLundi, semaine.totalHeures])).toEqual([
      ['2026-07-27', 2],
      ['2026-08-03', 6],
    ]);
  });
});
