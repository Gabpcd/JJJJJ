import { describe, expect, it } from 'vitest';
import {
  filtrerPaquetSwipe,
  missionCorrespondProfessionInscription,
  missionPasseFiltrePaquet,
  type FiltrePaquetSwipe,
} from './filtre-paquet-swipe';

// Prédicat du paquet de swipe (`VueSwipeMissions.tsx`, chips rapides 6c.1)
// extrait tel quel. Les missions de test sont ponctuelles (plage contractuelle
// de moins de 24 h) : leur planning est exact sans ligne de créneau.
const offre = (mission_id: string, extra: Record<string, unknown> = {}) => ({
  mission_id,
  profession_requise: 'IDE',
  etablissement_ville: 'Paris',
  etablissement_code_postal: '75016',
  distance_km: 5,
  taux_horaire_base: 30,
  type_contrat_recherche: 'TOUS',
  est_urgente: false,
  // Mercredi 4 novembre 2026, 8 h → 16 h à Paris.
  debut_le: '2026-11-04T07:00:00Z',
  fin_le: '2026-11-04T15:00:00Z',
  ...extra,
});

const filtre = (extra: Partial<FiltrePaquetSwipe> = {}): FiltrePaquetSwipe => ({
  urgentesOnly: false,
  horaire: 'TOUS',
  profession: '',
  ville: '',
  rayonKm: 50,
  tauxMin: 0,
  typeContrat: 'TOUS',
  ...extra,
});

const ids = (missions: Array<{ mission_id: string }>) => missions.map((m) => m.mission_id);

describe('filtrerPaquetSwipe', () => {
  it('sans filtre, rend le paquet tel quel (même référence)', () => {
    const paquet = [offre('a'), offre('b')];
    expect(filtrerPaquetSwipe(paquet, undefined, null)).toBe(paquet);
    expect(filtrerPaquetSwipe(paquet, null, 'IDE')).toBe(paquet);
  });

  it('un filtre neutre garde toutes les missions dans l’ordre du paquet', () => {
    const paquet = [offre('b'), offre('a'), offre('c')];
    expect(ids(filtrerPaquetSwipe(paquet, filtre(), null))).toEqual(['b', 'a', 'c']);
  });
});

describe('missionPasseFiltrePaquet — profession', () => {
  const paquet = [
    offre('ide', { profession_requise: 'IDE' }),
    offre('iade', { profession_requise: 'IADE' }),
    offre('ibode', { profession_requise: 'IBODE' }),
    offre('sf', { profession_requise: 'SAGE_FEMME' }),
  ];

  it('hors parcours : profession exacte si choisie, toutes sinon', () => {
    expect(ids(filtrerPaquetSwipe(paquet, filtre(), null))).toEqual(['ide', 'iade', 'ibode', 'sf']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ profession: 'IDE' }), null))).toEqual(['ide']);
  });

  it('parcours d’inscription : hiérarchie naturelle depuis la profession du compte', () => {
    expect(ids(filtrerPaquetSwipe(paquet, filtre(), 'IADE'))).toEqual(['ide', 'iade']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre(), 'IDE'))).toEqual(['ide']);
  });

  it('parcours d’inscription : la profession choisie prime, et un compte sans profession voit tout', () => {
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ profession: 'SAGE_FEMME' }), 'IADE'))).toEqual(['sf']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre(), ''))).toEqual(['ide', 'iade', 'ibode', 'sf']);
  });

  it('missionCorrespondProfessionInscription garde les cas de l’exploration', () => {
    expect(missionCorrespondProfessionInscription('IDE', '', 'IADE')).toBe(true);
    expect(missionCorrespondProfessionInscription('IADE', '', 'IDE')).toBe(false);
    expect(missionCorrespondProfessionInscription('IDE', 'SAGE_FEMME', 'IADE')).toBe(false);
    expect(missionCorrespondProfessionInscription('SAGE_FEMME', 'SAGE_FEMME', 'IADE')).toBe(true);
    expect(missionCorrespondProfessionInscription('KINE', '', '')).toBe(true);
  });
});

describe('missionPasseFiltrePaquet — lieu, rayon, taux', () => {
  it('ville : sous-chaîne de la ville ou début du code postal, sans casse ni espaces autour', () => {
    const paquet = [
      offre('paris', {}),
      offre('lyon', { etablissement_ville: 'Lyon', etablissement_code_postal: '69003' }),
      offre('sans-lieu', { etablissement_ville: null, etablissement_code_postal: null }),
    ];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ ville: '  PAR ' }), null))).toEqual(['paris']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ ville: '690' }), null))).toEqual(['lyon']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ ville: '016' }), null))).toEqual([]);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ ville: '   ' }), null))).toEqual(['paris', 'lyon', 'sans-lieu']);
  });

  it('rayon : distance inconnue acceptée, limite incluse', () => {
    const paquet = [
      offre('inconnue', { distance_km: null }),
      offre('limite', { distance_km: 10 }),
      offre('loin', { distance_km: 10.5 }),
    ];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ rayonKm: 10 }), null))).toEqual(['inconnue', 'limite']);
  });

  it('taux minimum : ignoré à 0, sinon taux absent vaut 0 et la limite est incluse', () => {
    const paquet = [
      offre('absent', { taux_horaire_base: null }),
      offre('egal', { taux_horaire_base: 30 }),
      offre('dessous', { taux_horaire_base: 29.99 }),
    ];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ tauxMin: 0 }), null))).toEqual(['absent', 'egal', 'dessous']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ tauxMin: 30 }), null))).toEqual(['egal']);
  });
});

describe('missionPasseFiltrePaquet — contrat, urgence, horaires', () => {
  it('type de contrat : CDD écarte le libéral, LIBERAL écarte le salarié, une mission TOUS passe toujours', () => {
    const paquet = [
      offre('salarie', { type_contrat_recherche: 'SALARIE' }),
      offre('liberal', { type_contrat_recherche: 'LIBERAL' }),
      offre('tous', { type_contrat_recherche: 'TOUS' }),
    ];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ typeContrat: 'CDD' }), null))).toEqual(['salarie', 'tous']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ typeContrat: 'LIBERAL' }), null))).toEqual(['liberal', 'tous']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ typeContrat: 'TOUS' }), null))).toEqual(['salarie', 'liberal', 'tous']);
  });

  it('urgentes seulement', () => {
    const paquet = [offre('normale'), offre('urgente', { est_urgente: true })];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ urgentesOnly: true }), null))).toEqual(['urgente']);
  });

  it('horaires : jour, nuit et week-end dérivés du planning exact', () => {
    const jour = offre('jour');
    // Samedi 7 novembre 2026, 21 h → dimanche 7 h à Paris.
    const nuitWeekend = offre('nuit-weekend', { debut_le: '2026-11-07T20:00:00Z', fin_le: '2026-11-08T06:00:00Z' });
    const inexacte = offre('inexacte', { erreur_planning: true });
    const paquet = [jour, nuitWeekend, inexacte];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ horaire: 'TOUS' }), null))).toEqual(['jour', 'nuit-weekend', 'inexacte']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ horaire: 'JOUR' }), null))).toEqual(['jour']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ horaire: 'NUIT' }), null))).toEqual(['nuit-weekend']);
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ horaire: 'WEEKEND' }), null))).toEqual(['nuit-weekend']);
    expect(missionPasseFiltrePaquet(inexacte, filtre({ horaire: 'NUIT' }), null)).toBe(false);
  });

  it('tous les critères se cumulent', () => {
    const paquet = [
      offre('ok', { est_urgente: true, distance_km: 3, taux_horaire_base: 40 }),
      offre('pas-urgente', { distance_km: 3, taux_horaire_base: 40 }),
      offre('trop-loin', { est_urgente: true, distance_km: 30, taux_horaire_base: 40 }),
    ];
    expect(ids(filtrerPaquetSwipe(paquet, filtre({ urgentesOnly: true, rayonKm: 10, tauxMin: 35, ville: 'paris' }), null)))
      .toEqual(['ok']);
  });
});
