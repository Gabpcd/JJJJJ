import { describe, expect, it } from 'vitest';
import { decrireAccordAccepte } from '@/lib/litigeResolutionUi';

describe('LitigeResolutionModal — aperçu de l’accord accepté', () => {
  it('annonce la compensation financière au lieu d’une clôture sans impact', () => {
    const messages = decrireAccordAccepte({
      type: 'COMPENSATION_PARTIELLE',
      modifications: { pourcentage_compensation: 10 },
      justification: 'Accord accepté par les deux parties.',
    });

    expect(messages.join(' ')).toContain('compensation de 10 %');
    expect(messages.join(' ')).not.toContain('Aucun ajustement financier');
  });

  it('annonce le montant TTC exact convenu', () => {
    expect(decrireAccordAccepte({
      type: 'MODIFICATION_MONTANT',
      modifications: { montant_total_corrige: 450 },
      justification: 'Montant validé.',
    })).toContain('Accord accepté : montant final convenu à 450 € TTC.');
  });
});
