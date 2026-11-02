import { describe, expect, it } from 'vitest';
import { construireListesPresences, regrouperCreneauxParMission } from './presences-soignant-listes';

// Cas reconstitués depuis `PresencesSoignant.tsx` (listes Aujourd'hui, À venir,
// Actives) avant leur extraction. Horloge explicite : lundi 2 novembre 2026,
// 10 h à Paris (UTC+1). Aujourd'hui = [2026-11-01T23:00Z, 2026-11-02T23:00Z[.
const MAINTENANT = new Date('2026-11-02T09:00:00Z');

const prevu = (id: string, debut: string, fin: string | null, extra: Record<string, unknown> = {}) => ({
  id, debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL', ...extra,
});
const effectif = (id: string, debut: string, fin: string | null, extra: Record<string, unknown> = {}) => ({
  id, debut, fin, est_pause: false, type_creneau: 'EFFECTIF', ...extra,
});
const mission = (id: string, statut: string, debut_le: string, fin_le: string, extra: Record<string, unknown> = {}) => ({
  id, intitule: `Mission ${id}`, statut, debut_le, fin_le, duree_heures: 7, etablissement_id: 'etab-1', ...extra,
});
const ids = (liste: Array<{ id: string }>) => liste.map((m) => m.id);

describe('regrouperCreneauxParMission', () => {
  it('regroupe les créneaux par mission en conservant leur ordre', () => {
    const groupes = regrouperCreneauxParMission([
      { ...prevu('a1', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'), mission_id: 'a' },
      { ...prevu('b1', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z'), mission_id: 'b' },
      { ...prevu('a2', '2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z'), mission_id: 'a' },
    ]);
    expect(Object.keys(groupes)).toEqual(['a', 'b']);
    expect(groupes.a.map((c) => c.id)).toEqual(['a1', 'a2']);
    expect(groupes.b.map((c) => c.id)).toEqual(['b1']);
  });

  it('une liste absente donne un regroupement vide', () => {
    expect(regrouperCreneauxParMission(null)).toEqual({});
    expect(regrouperCreneauxParMission(undefined)).toEqual({});
  });
});

describe('construireListesPresences — Aujourd’hui', () => {
  it('garde une mission avec un créneau prévisionnel du jour civil de Paris', () => {
    const listes = construireListesPresences({
      missions: [mission('du-jour', 'ASSIGNEE', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')],
      creneauxParMission: { 'du-jour': [prevu('c', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')] },
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(ids(listes.missionsAujourdhui)).toEqual(['du-jour']);
    expect(ids(listes.missionsAVenir)).toEqual([]);
  });

  it('garde une mission avec un segment EFFECTIF ouvert, même sans créneau du jour', () => {
    const listes = construireListesPresences({
      missions: [mission('segment-ouvert', 'EN_COURS', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z')],
      creneauxParMission: {
        'segment-ouvert': [
          effectif('e', '2026-11-01T07:00:00Z', null),
          prevu('p', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z'),
        ],
      },
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(ids(listes.missionsAujourdhui)).toEqual(['segment-ouvert']);
    expect(ids(listes.missionsEnCours)).toEqual(['segment-ouvert']);
  });

  it('ignore une pause ouverte, un segment fermé et une pause prévue du jour', () => {
    const listes = construireListesPresences({
      missions: [mission('pauses', 'EN_COURS', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z')],
      creneauxParMission: {
        pauses: [
          effectif('pause-ouverte', '2026-11-02T08:00:00Z', null, { est_pause: true }),
          effectif('ferme', '2026-11-02T07:00:00Z', '2026-11-02T08:00:00Z'),
          prevu('pause-prevue', '2026-11-02T11:00:00Z', '2026-11-02T12:00:00Z', { est_pause: true }),
        ],
      },
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(ids(listes.missionsAujourdhui)).toEqual([]);
  });

  it('borne le jour à minuit Paris : un créneau qui finit à minuit hier ou commence à minuit demain n’est pas du jour', () => {
    const listes = construireListesPresences({
      missions: [
        mission('fini-minuit', 'ASSIGNEE', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
        mission('commence-demain', 'ASSIGNEE', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
        mission('chevauche-minuit', 'ASSIGNEE', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
      ],
      creneauxParMission: {
        'fini-minuit': [prevu('a', '2026-11-01T15:00:00Z', '2026-11-01T23:00:00Z')],
        'commence-demain': [prevu('b', '2026-11-02T23:00:00Z', '2026-11-03T07:00:00Z')],
        'chevauche-minuit': [prevu('c', '2026-11-01T20:00:00Z', '2026-11-02T06:00:00Z')],
      },
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(ids(listes.missionsAujourdhui)).toEqual(['chevauche-minuit']);
    expect(ids(listes.missionsAVenir)).toEqual(['commence-demain']);
  });

  it('suit le jour civil de Paris et non celui d’UTC', () => {
    // 2026-11-02T23:30Z = mardi 3 novembre 00 h 30 à Paris.
    const listes = construireListesPresences({
      missions: [mission('mardi', 'ASSIGNEE', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')],
      creneauxParMission: { mardi: [prevu('m', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')] },
      contrats: [],
      maintenant: new Date('2026-11-02T23:30:00Z'),
    });
    expect(ids(listes.missionsAujourdhui)).toEqual(['mardi']);
    expect(ids(listes.missionsAVenir)).toEqual([]);
  });

  it('une mission ponctuelle sans créneau reçoit sa plage contractuelle comme créneau du jour', () => {
    const listes = construireListesPresences({
      missions: [mission('ponctuelle', 'ASSIGNEE', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')],
      creneauxParMission: {},
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(ids(listes.missionsAujourdhui)).toEqual(['ponctuelle']);
    expect(listes.missionsAujourdhui[0].creneaux).toEqual([{
      id: 'mission-ponctuelle-ponctuelle',
      debut: '2026-11-02T07:00:00Z',
      fin: '2026-11-02T15:00:00Z',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }]);
  });
});

describe('construireListesPresences — À venir', () => {
  it('affiche le prochain créneau à partir de demain et sa durée', () => {
    const listes = construireListesPresences({
      missions: [
        mission('segment-ouvert', 'EN_COURS', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
        mission('jeudi', 'ASSIGNEE', '2026-11-05T07:00:00Z', '2026-11-05T19:00:00Z', { duree_heures: 99 }),
      ],
      creneauxParMission: {
        'segment-ouvert': [
          prevu('hier', '2026-11-01T07:00:00Z', '2026-11-01T15:00:00Z'),
          prevu('jour', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'),
          prevu('apres', '2026-11-04T07:00:00Z', '2026-11-04T11:00:00Z'),
          prevu('demain', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z'),
        ],
        jeudi: [prevu('j', '2026-11-05T07:00:00Z', '2026-11-05T19:00:00Z')],
      },
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(listes.missionsAVenir.map((m) => [m.id, m.dateAffichage, m.prochainCreneau?.id, m.dureeAffichageHeures])).toEqual([
      ['segment-ouvert', '2026-11-03T07:00:00Z', 'demain', 8],
      ['jeudi', '2026-11-05T07:00:00Z', 'j', 12],
    ]);
  });

  it('une mission ASSIGNEE sans créneau prévisionnel est « planning à confirmer », après les missions datées', () => {
    const listes = construireListesPresences({
      missions: [
        mission('longue-sans-creneau', 'ASSIGNEE', '2026-11-10T07:00:00Z', '2026-11-20T15:00:00Z'),
        mission('en-cours-sans-creneau', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z'),
        mission('incomplete', 'ASSIGNEE', '2026-11-10T07:00:00Z', '2026-11-20T15:00:00Z'),
        mission('datee', 'ASSIGNEE', '2026-11-09T07:00:00Z', '2026-11-09T15:00:00Z'),
      ],
      creneauxParMission: {
        incomplete: [prevu('sans-fin', '2026-11-10T07:00:00Z', null)],
        datee: [prevu('d', '2026-11-09T07:00:00Z', '2026-11-09T15:00:00Z')],
      },
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(listes.missionsAVenir.map((m) => [m.id, m.dateAffichage, m.planningAConfirmer ?? false])).toEqual([
      ['datee', '2026-11-09T07:00:00Z', false],
      ['longue-sans-creneau', null, true],
      ['incomplete', null, true],
    ]);
    const aConfirmer = listes.missionsAVenir[1];
    expect(aConfirmer.prochainCreneau).toBeNull();
    expect(aConfirmer.dureeAffichageHeures).toBeNull();
    expect(ids(listes.missionsEnCours)).toEqual(['en-cours-sans-creneau']);
  });

  it('trie par date croissante et coupe à 20 missions', () => {
    const missions = Array.from({ length: 22 }, (_, i) => {
      const jour = String(25 - i).padStart(2, '0');
      return mission(`m-${jour}`, 'ASSIGNEE', `2026-11-${jour}T07:00:00Z`, `2026-11-${jour}T15:00:00Z`);
    });
    missions.push(mission('a-confirmer', 'ASSIGNEE', '2026-12-01T07:00:00Z', '2026-12-10T15:00:00Z'));
    const listes = construireListesPresences({ missions, creneauxParMission: {}, contrats: [], maintenant: MAINTENANT });
    expect(listes.missionsAVenir).toHaveLength(20);
    expect(ids(listes.missionsAVenir)).toEqual(
      Array.from({ length: 20 }, (_, i) => `m-${String(4 + i).padStart(2, '0')}`),
    );
  });
});

describe('construireListesPresences — Actives, contrats et enrichissement', () => {
  it('les missions actives sont les missions EN_COURS, sans dépendre des présences', () => {
    const listes = construireListesPresences({
      missions: [
        mission('a', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z'),
        mission('b', 'ASSIGNEE', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'),
        mission('c', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z'),
      ],
      creneauxParMission: {},
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(ids(listes.missionsEnCours)).toEqual(['a', 'c']);
  });

  it('choisit le contrat de pointage par mission (signé complet d’abord, terminaux exclus)', () => {
    const listes = construireListesPresences({
      missions: [],
      creneauxParMission: {},
      contrats: [
        { id: 'annule', mission_id: 'm1', statut: 'ANNULE', cree_le: '2026-10-20T00:00:00Z' },
        { id: 'envoye', mission_id: 'm1', statut: 'ENVOYE', cree_le: '2026-10-10T00:00:00Z' },
        { id: 'signe', mission_id: 'm1', statut: 'SIGNE_COMPLET', cree_le: '2026-09-01T00:00:00Z' },
        { id: 'ancien', mission_id: 'm2', statut: 'EN_ATTENTE_SIGNATURE', cree_le: '2026-10-01T00:00:00Z' },
        { id: 'recent', mission_id: 'm2', statut: 'EN_ATTENTE_SIGNATURE', cree_le: '2026-10-15T00:00:00Z' },
        { id: 'expire', mission_id: 'm3', statut: 'EXPIRE', cree_le: '2026-10-15T00:00:00Z' },
      ],
      maintenant: MAINTENANT,
    });
    expect(Object.fromEntries(Object.entries(listes.contrats).map(([m, c]) => [m, c.id]))).toEqual({
      m1: 'signe',
      m2: 'recent',
    });
  });

  it('enrichit chaque mission de ses créneaux et de son établissement, sans perdre ses champs', () => {
    const listes = construireListesPresences({
      missions: [
        mission('connue', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z', { service: 'Urgences' }),
        mission('inconnue', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z', { etablissement_id: 'etab-2' }),
      ],
      creneauxParMission: { connue: [effectif('e', '2026-11-02T07:00:00Z', null)] },
      contrats: [],
      maintenant: MAINTENANT,
      etablissements: { 'etab-1': { nom: 'Clinique Test' } },
    });
    const [connue, inconnue] = listes.missionsEnCours;
    expect(connue).toMatchObject({
      id: 'connue',
      service: 'Urgences',
      etablissements: { nom: 'Clinique Test' },
      creneaux: [expect.objectContaining({ id: 'e' })],
    });
    expect(inconnue.etablissements).toBeNull();
    expect(inconnue.creneaux).toEqual([]);
  });

  it('sans carte d’établissements, le nom reste inconnu (null)', () => {
    const listes = construireListesPresences({
      missions: [mission('m', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z')],
      creneauxParMission: {},
      contrats: [],
      maintenant: MAINTENANT,
    });
    expect(listes.missionsEnCours[0].etablissements).toBeNull();
  });
});
