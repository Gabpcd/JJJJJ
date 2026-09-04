import { describe, expect, it } from 'vitest';
import { formatDureeCompacte } from './format-mission';

describe('formatDureeCompacte', () => {
  it('affiche le total réel d’un planning multi-créneaux sans inventer une durée par jour', () => {
    expect(formatDureeCompacte({
      debut_le: '2026-09-03T19:00:00+02:00',
      fin_le: '2026-09-04T19:00:00+02:00',
      duree_heures: 13,
      nb_creneaux: 2,
    })).toBe('2 créneaux · 13 h au total');
  });

  it('conserve une unité en jours pour une ancienne mission sans créneaux datés', () => {
    expect(formatDureeCompacte({
      debut_le: '2026-09-03T07:00:00+02:00',
      fin_le: '2026-09-04T19:00:00+02:00',
      duree_heures: 24,
      nb_creneaux: null,
    })).toBe('2 jours · 24 h au total');
  });

  it('reste compact pour une mission sur une seule journée', () => {
    expect(formatDureeCompacte({
      debut_le: '2026-09-03T08:00:00+02:00',
      fin_le: '2026-09-03T15:30:00+02:00',
      duree_heures: 7.5,
      nb_creneaux: 1,
    })).toBe('7,5h');
  });
});
