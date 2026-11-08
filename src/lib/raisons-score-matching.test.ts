import { describe, expect, it } from 'vitest';
import { RAISON_LABELS, RAISONS_EPINGLEES, raisonsScore } from './raisons-score-matching';

// « Pourquoi 85 ? » de la carte swipe (`CardMissionSwipe.tsx`), extrait tel quel.
describe('raisonsScore — les deux contributeurs les plus parlants', () => {
  it('conserve les libellés et les clés du breakdown v3', () => {
    expect(RAISON_LABELS).toEqual({
      distance: 'proche de chez toi',
      tarif: 'bien payée vs le marché',
      horaire: 'à tes horaires préférés',
      etablissement: 'établissement bien noté',
      urgence: 'mission urgente',
      soignant_fiabilite: 'ton profil correspond',
      connaissance_etab: 'tu connais cet établissement',
      paiement_rapide: 'paiement rapide ⚡',
    });
    expect(RAISONS_EPINGLEES).toEqual(['connaissance_etab', 'paiement_rapide']);
  });

  it('trie les autres raisons par points décroissants et en garde deux', () => {
    expect(raisonsScore({ distance: 10, tarif: 25, horaire: 15, urgence: 5 }))
      .toBe('bien payée vs le marché · à tes horaires préférés');
  });

  it('épingle connaissance_etab et paiement_rapide avant les points, dans cet ordre', () => {
    expect(raisonsScore({ distance: 30, connaissance_etab: 5 }))
      .toBe('tu connais cet établissement · proche de chez toi');
    expect(raisonsScore({ paiement_rapide: 1, distance: 40, connaissance_etab: 1 }))
      .toBe('tu connais cet établissement · paiement rapide ⚡');
    expect(raisonsScore({ paiement_rapide: 2, tarif: 20, horaire: 10 }))
      .toBe('paiement rapide ⚡ · bien payée vs le marché');
  });

  it('n’épingle pas une raison épinglée à zéro', () => {
    expect(raisonsScore({ connaissance_etab: 0, paiement_rapide: 0, horaire: 3 }))
      .toBe('à tes horaires préférés');
  });

  it('ignore les clés inconnues (dont l’ancienne clé fiabilite), les valeurs nulles, négatives ou non numériques', () => {
    expect(raisonsScore({ fiabilite: 50, inconnu: 99, distance: 0, tarif: '30', urgence: -1, horaire: 5 }))
      .toBe('à tes horaires préférés');
    expect(raisonsScore({ soignant_fiabilite: 12, etablissement: 4 }))
      .toBe('ton profil correspond · établissement bien noté');
  });

  it('à égalité de points, garde l’ordre du breakdown', () => {
    expect(raisonsScore({ tarif: 10, distance: 10, horaire: 10 }))
      .toBe('bien payée vs le marché · proche de chez toi');
  });

  it('un breakdown vide ou absent ne donne aucune raison', () => {
    expect(raisonsScore({})).toBe('');
    expect(raisonsScore(null)).toBe('');
    expect(raisonsScore(undefined)).toBe('');
  });
});
