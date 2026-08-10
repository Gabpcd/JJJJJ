import { describe, expect, it } from 'vitest';
import { calculerBucketAnnulation } from './AnnulationCandidatureTimer';

const H = 3_600_000;

describe('calculerBucketAnnulation', () => {
  it('sépare les règles ASAP et ordinaires sans chevauchement', () => {
    expect(calculerBucketAnnulation(H, 1.5 * H, true)).toMatchObject({ points: -25, motif: 'ASAP_ANNULEE_APRES_FENETRE' });
    expect(calculerBucketAnnulation(H, 1.5 * H, false)).toMatchObject({ points: -10, motif: 'ANNULATION_1_12H' });
  });

  it('ne qualifie de no-show qu’une mission commencée', () => {
    expect(calculerBucketAnnulation(H, 45 * 60_000, false)).toMatchObject({ points: -30, motif: 'ANNULATION_MOINS_1H', signalement: false });
    expect(calculerBucketAnnulation(5 * 60_000, -1, true)).toMatchObject({ points: -30, motif: 'NO_SHOW', signalement: true });
  });

  it('borne exactement 2 h, 12 h et 24 h', () => {
    expect(calculerBucketAnnulation(H, 2 * H, true).points).toBe(-10);
    expect(calculerBucketAnnulation(H, 12 * H, false).points).toBe(-5);
    expect(calculerBucketAnnulation(H, 24 * H, false)).toMatchObject({ libre: true, points: 0, motif: 'neutre_delai_long' });
  });
});
