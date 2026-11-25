import { describe, expect, it } from 'vitest';
import {
  messageTauxSousMinimum,
  minimumSalarieApplicable,
  montantFrancais,
  normaliserTauxMinimumSalarie,
  TAUX_HORAIRE_MINIMUM_SALARIE_REPLI,
  tauxSousMinimumSalarie,
} from '@/lib/tauxHoraireMinimumSalarie';

describe('taux horaire minimal d\'une mission salariée', () => {
  it('repli = SMIC horaire brut au 1er juin 2026', () => {
    expect(TAUX_HORAIRE_MINIMUM_SALARIE_REPLI).toBe(12.31);
  });

  it('message exact, montant à la française', () => {
    expect(messageTauxSousMinimum(12.31)).toBe("Le taux horaire doit être d'au moins 12,31 €/h.");
    expect(messageTauxSousMinimum(12.5)).toBe("Le taux horaire doit être d'au moins 12,50 €/h.");
    expect(montantFrancais(1234.5)).toBe('1234,50');
  });

  it('refuse 12,30 et accepte 12,31 en SALARIE et en TOUS ; libéral non concerné', () => {
    for (const contrat of ['SALARIE', 'TOUS'] as const) {
      expect(tauxSousMinimumSalarie(12.3, contrat, 12.31)).toBe(true);
      expect(tauxSousMinimumSalarie(12.31, contrat, 12.31)).toBe(false);
      expect(tauxSousMinimumSalarie(40, contrat, 12.31)).toBe(false);
    }
    expect(minimumSalarieApplicable('LIBERAL')).toBe(false);
    expect(tauxSousMinimumSalarie(10, 'LIBERAL', 12.31)).toBe(false);
  });

  it('saisie vide ou nulle : champ obligatoire, pas un taux sous le plancher', () => {
    expect(tauxSousMinimumSalarie(0, 'SALARIE', 12.31)).toBe(false);
    expect(tauxSousMinimumSalarie(Number.NaN, 'SALARIE', 12.31)).toBe(false);
  });

  it('modification : mission existante inchangée non bloquée, changement de taux ou de contrat contrôlé', () => {
    const source = { taux: 11.5, contrat: 'SALARIE' as const };
    expect(tauxSousMinimumSalarie(11.5, 'SALARIE', 12.31, source)).toBe(false);
    expect(tauxSousMinimumSalarie(12, 'SALARIE', 12.31, source)).toBe(true);
    expect(tauxSousMinimumSalarie(11.5, 'TOUS', 12.31, source)).toBe(true);
    expect(tauxSousMinimumSalarie(10, 'LIBERAL', 12.31, { taux: 10, contrat: 'LIBERAL' })).toBe(false);
  });

  it('valeur du serveur, repli si absente ou illisible', () => {
    expect(normaliserTauxMinimumSalarie(12.5)).toBe(12.5);
    expect(normaliserTauxMinimumSalarie('12.31')).toBe(12.31);
    for (const v of [null, undefined, '', 'abc', 0, -1, Number.NaN, {}]) {
      expect(normaliserTauxMinimumSalarie(v)).toBe(12.31);
    }
  });
});
