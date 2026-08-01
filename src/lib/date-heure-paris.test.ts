import { describe, expect, it } from 'vitest';
import {
  ajouterJoursCivilsParis,
  debutJourParis,
  formatParis,
  instantJolene,
  instantDepuisSaisieParis,
} from './date-heure-paris';

describe('date-heure-paris', () => {
  it('conserve un affichage Europe/Paris stable quel que soit le fuseau du processus', () => {
    expect(formatParis('2026-08-31T06:00:00.000Z', "EEEE d MMMM yyyy 'à' HH:mm"))
      .toBe('lundi 31 août 2026 à 08:00');
    expect(instantDepuisSaisieParis('2026-08-31T08:00').toISOString())
      .toBe('2026-08-31T06:00:00.000Z');
  });

  it('interprète un ISO sans offset comme une heure murale de Paris', () => {
    expect(formatParis('2026-08-31T08:00:00', "EEEE d MMMM yyyy 'à' HH:mm"))
      .toBe('lundi 31 août 2026 à 08:00');
    expect(instantJolene('2026-08-31T08:00:00').toISOString())
      .toBe('2026-08-31T06:00:00.000Z');
    expect(formatParis('2026-08-31T08:00:00.250', 'HH:mm:ss'))
      .toBe('08:00:00');
  });

  it('ne normalise pas 01:30 Paris dans le trou DST du fuseau Europe/London', () => {
    // Sous TZ=Europe/London, `new Date(2026, 2, 29, 1, 30)` devient 02:30 car
    // 01:30 n'existe pas localement. Le formateur ne doit jamais créer cette
    // Date locale : l'instant ci-dessous vaut bien 01:30 à Paris.
    expect(formatParis('2026-03-29T00:30:00.000Z', 'EEEE d MMMM yyyy · HH:mm'))
      .toBe('dimanche 29 mars 2026 · 01:30');
  });

  it('respecte les jours civils de 23 h et 25 h aux changements DST', () => {
    const debutJourCourt = debutJourParis('2026-03-29T12:00:00.000Z');
    const finJourCourt = ajouterJoursCivilsParis(debutJourCourt, 1);
    expect((finJourCourt.getTime() - debutJourCourt.getTime()) / 3_600_000).toBe(23);

    const debutJourLong = debutJourParis('2026-10-25T12:00:00.000Z');
    const finJourLong = ajouterJoursCivilsParis(debutJourLong, 1);
    expect((finJourLong.getTime() - debutJourLong.getTime()) / 3_600_000).toBe(25);
  });

  it("rejette explicitement une heure de Paris inexistante au passage a l'heure d'ete", () => {
    expect(() => instantDepuisSaisieParis('2026-03-29T02:30')).toThrow(
      /Date\/heure inexistante dans le fuseau Europe\/Paris/,
    );
  });

  it("rejette une heure d'hiver répétée sans offset explicite", () => {
    expect(() => instantDepuisSaisieParis('2026-10-25T02:30')).toThrow('ambiguë');
  });

  it("accepte les heures qui encadrent le passage a l'heure d'ete", () => {
    expect(instantDepuisSaisieParis('2026-03-29T01:59').toISOString())
      .toBe('2026-03-29T00:59:00.000Z');
    expect(instantDepuisSaisieParis('2026-03-29T03:00').toISOString())
      .toBe('2026-03-29T01:00:00.000Z');
  });
});
