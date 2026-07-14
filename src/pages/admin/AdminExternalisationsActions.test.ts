import { describe, expect, it } from 'vitest';
import { libelleStatutExternalisation, libelleTypeExternalisation } from '@/lib/adminExternalisations';

describe('libellés des externalisations', () => {
  it('présente les statuts techniques en français', () => {
    expect(libelleStatutExternalisation('PENDING')).toBe('En attente');
    expect(libelleStatutExternalisation('PENDING_AIFE')).toBe('En attente AIFE');
    expect(libelleStatutExternalisation('ERROR')).toBe('En échec');
  });

  it('présente les types connus et garde un repli lisible', () => {
    expect(libelleTypeExternalisation('STRIPE_REFUND_PARTIEL')).toBe('Remboursement Stripe partiel');
    expect(libelleTypeExternalisation('ACTION_INCONNUE')).toBe('action inconnue');
  });
});
