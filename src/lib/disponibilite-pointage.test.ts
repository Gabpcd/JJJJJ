import { describe, expect, it } from 'vitest';
import {
  creneauChevauchePeriode,
  evaluerDisponibilitePointage,
  filtrerMissionsEnCours,
  prochainCreneauPointage,
  type CreneauPointage,
} from './disponibilite-pointage';

const creneau = (
  debut: string,
  fin: string | null,
  type_creneau = 'PREVISIONNEL',
): CreneauPointage => ({ debut, fin, type_creneau, est_pause: false });

describe('disponibilité du pointage', () => {
  it('conserve une mission EN_COURS même sans présence legacy', () => {
    const mission = { id: 'mission-longue', statut: 'EN_COURS', presences: [] };

    expect(filtrerMissionsEnCours([mission])).toEqual([mission]);
  });

  it('autorise une arrivée dans les 30 minutes avant un créneau signé', () => {
    const resultat = evaluerDisponibilitePointage({
      creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')],
      contratStatut: 'SIGNE_COMPLET',
      maintenant: new Date('2026-07-31T07:45:00.000Z'),
    });

    expect(resultat.peutPointer).toBe(true);
    expect(resultat.action).toBe('OUVERTURE');
  });

  it('bloque explicitement une mission longue entre deux créneaux', () => {
    const prochain = creneau('2026-08-31T06:00:00.000Z', '2026-08-31T14:00:00.000Z');
    const resultat = evaluerDisponibilitePointage({
      creneaux: [
        creneau('2026-07-06T06:00:00.000Z', '2026-07-06T14:00:00.000Z'),
        prochain,
      ],
      contratStatut: 'SIGNE_COMPLET',
      maintenant: new Date('2026-07-31T12:00:00.000Z'),
    });

    expect(resultat).toMatchObject({
      peutPointer: false,
      motif: 'HORS_CRENEAU',
      prochainCreneau: prochain,
    });
  });

  it('signale le contrat avant toute ouverture', () => {
    const resultat = evaluerDisponibilitePointage({
      creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')],
      contratStatut: null,
      maintenant: new Date('2026-07-31T09:00:00.000Z'),
    });

    expect(resultat.peutPointer).toBe(false);
    expect(resultat.motif).toBe('CONTRAT');
  });

  it('laisse toujours fermer un segment effectif déjà ouvert', () => {
    const resultat = evaluerDisponibilitePointage({
      creneaux: [creneau('2026-07-31T08:00:00.000Z', null, 'EFFECTIF')],
      contratStatut: null,
      maintenant: new Date('2026-07-31T18:00:00.000Z'),
    });

    expect(resultat).toMatchObject({ peutPointer: true, action: 'FERMETURE' });
  });

  it('détecte un créneau qui chevauche la journée et le prochain créneau', () => {
    const nuit = creneau('2026-07-30T20:00:00.000Z', '2026-07-31T06:00:00.000Z');
    const lendemain = creneau('2026-08-01T08:00:00.000Z', '2026-08-01T16:00:00.000Z');

    expect(creneauChevauchePeriode(
      nuit,
      new Date('2026-07-31T00:00:00.000Z'),
      new Date('2026-08-01T00:00:00.000Z'),
    )).toBe(true);
    expect(prochainCreneauPointage([nuit, lendemain], new Date('2026-07-31T12:00:00.000Z')))
      .toBe(lendemain);
  });
});
