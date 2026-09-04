import { describe, expect, it } from 'vitest';
import {
  ajouterRepliMissionPonctuelle,
  creneauChevauchePeriode,
  creneauxPrevisionnels,
  choisirContratPointage,
  evaluerDisponibilitePointage,
  evaluerClotureAdminMission,
  evaluerTerminaisonMission,
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
  it('utilise la plage globale uniquement pour une mission ponctuelle sans créneau', () => {
    const ponctuelle = ajouterRepliMissionPonctuelle([], {
      id: 'ponctuelle',
      debut_le: '2026-07-31T08:00:00+02:00',
      fin_le: '2026-07-31T16:00:00+02:00',
    });
    const longue = ajouterRepliMissionPonctuelle([], {
      id: 'longue',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-08-31T16:00:00+02:00',
    });

    expect(creneauxPrevisionnels(ponctuelle)).toHaveLength(1);
    expect(longue).toEqual([]);
  });

  it('privilégie le contrat signé et ignore les anciennes versions annulées', () => {
    expect(choisirContratPointage([
      { id: 'annule', statut: 'ANNULE', cree_le: '2026-07-31T10:00:00Z' },
      { id: 'attente', statut: 'EN_ATTENTE_SIGNATURES', cree_le: '2026-07-30T10:00:00Z' },
      { id: 'signe', statut: 'SIGNE_COMPLET', cree_le: '2026-07-01T10:00:00Z' },
    ])?.id).toBe('signe');
  });

  it('conserve une mission EN_COURS même sans présence legacy', () => {
    const mission = { id: 'mission-longue', statut: 'EN_COURS', presences: [] };

    expect(filtrerMissionsEnCours([mission])).toEqual([mission]);
  });

  it('autorise une arrivée dans les 15 minutes avant un créneau signé', () => {
    const resultat = evaluerDisponibilitePointage({
      creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')],
      contratStatut: 'SIGNE_COMPLET',
      maintenant: new Date('2026-07-31T07:45:00.000Z'),
    });

    expect(resultat.peutPointer).toBe(true);
    expect(resultat.action).toBe('OUVERTURE');
  });

  it('n’affiche pas un pointage que le serveur refuserait avant H-15', () => {
    const resultat = evaluerDisponibilitePointage({
      creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')],
      contratStatut: 'SIGNE_COMPLET',
      maintenant: new Date('2026-07-31T07:44:59.000Z'),
    });

    expect(resultat).toMatchObject({ peutPointer: false, motif: 'HORS_CRENEAU' });
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

  it('refuse de terminer tant qu’un segment effectif reste ouvert', () => {
    const resultat = evaluerTerminaisonMission({
      creneaux: [
        creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z'),
        creneau('2026-07-31T08:05:00.000Z', null, 'EFFECTIF'),
      ],
      finMission: '2026-07-31T16:00:00.000Z',
      maintenant: new Date('2026-07-31T17:00:00.000Z'),
    });

    expect(resultat).toMatchObject({ peutTerminer: false, motif: 'SEGMENT_OUVERT' });
  });

  it('autorise la terminaison après le dernier créneau et un départ fermé', () => {
    const resultat = evaluerTerminaisonMission({
      creneaux: [
        creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z'),
        creneau('2026-07-31T08:05:00.000Z', '2026-07-31T15:55:00.000Z', 'EFFECTIF'),
      ],
      finMission: '2026-07-31T16:00:00.000Z',
      maintenant: new Date('2026-07-31T17:00:00.000Z'),
    });

    expect(resultat).toMatchObject({ peutTerminer: true, motif: null });
  });

  it('priorise un segment ouvert sur la date du dernier créneau', () => {
    const resultat = evaluerTerminaisonMission({
      creneaux: [
        creneau('2026-09-03T17:00:00.000Z', '2026-09-03T18:00:00.000Z'),
        creneau('2026-09-04T05:00:00.000Z', '2026-09-04T17:00:00.000Z'),
        creneau('2026-09-03T17:05:00.000Z', null, 'EFFECTIF'),
      ],
      finMission: '2026-09-04T17:00:00.000Z',
      maintenant: new Date('2026-09-03T17:30:00.000Z'),
    });

    expect(resultat).toMatchObject({ peutTerminer: false, motif: 'SEGMENT_OUVERT' });
  });

  it('réserve la clôture anticipée à un admin intervenant sur un litige actif', () => {
    const terminaison = evaluerTerminaisonMission({
      creneaux: [
        creneau('2026-09-03T17:00:00.000Z', '2026-09-03T18:00:00.000Z'),
        creneau('2026-09-04T05:00:00.000Z', '2026-09-04T17:00:00.000Z'),
        creneau('2026-09-03T17:05:00.000Z', '2026-09-03T17:25:00.000Z', 'EFFECTIF'),
      ],
      finMission: '2026-09-04T17:00:00.000Z',
      maintenant: new Date('2026-09-03T17:30:00.000Z'),
    });

    expect(evaluerClotureAdminMission({ terminaison, estAdmin: true, litigeActif: true }))
      .toMatchObject({ peutTerminer: true, clotureAnticipee: true, motif: null });
    expect(evaluerClotureAdminMission({ terminaison, estAdmin: false, litigeActif: true }))
      .toMatchObject({ peutTerminer: false, clotureAnticipee: false, motif: 'AVANT_DERNIER_CRENEAU' });
    expect(evaluerClotureAdminMission({ terminaison, estAdmin: true, litigeActif: false }))
      .toMatchObject({ peutTerminer: false, clotureAnticipee: false, motif: 'AVANT_DERNIER_CRENEAU' });
  });
});
