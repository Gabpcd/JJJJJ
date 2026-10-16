import { describe, expect, it } from 'vitest';
import { etatVersementConnect, lireVersementsConnect } from './connectPayoutUi';

const row = { id: 'trace-1', mission_id: 'mission-1', statut: 'TRANSFERE', montant_soignant: '80.00',
  stripe_payout_id: null, standard_payout_state: 'WAITING', paye_le: null };
describe('preuve de versement bancaire', () => {
  it.each([
    { statut: 'PAYE', standard_payout_state: null },
    { statut: 'PAYE', standard_payout_state: 'PAID' },
    { statut: 'TRANSFERE', standard_payout_state: 'PAID', stripe_payout_id: 'po_fixture', paye_le: '2026-10-16T12:00:00Z' },
    { standard_payout_state: 'SUBMITTED' },
  ])('ne fabrique pas une confirmation à partir de champs incomplets ou contradictoires', fields => {
    const [parsed] = lireVersementsConnect([{ ...row, ...fields }]);
    expect(etatVersementConnect(parsed).paid).toBe(false);
    expect(etatVersementConnect(parsed).label).not.toBe('Versement bancaire confirmé');
  });
  it('refuse les états inconnus et les montants invalides', () => {
    expect(() => lireVersementsConnect([{ ...row, standard_payout_state: 'CREATING' }])).toThrow();
    expect(() => lireVersementsConnect([{ ...row, montant_soignant: NaN }])).toThrow();
    expect(() => lireVersementsConnect([{ ...row, montant_soignant: -80 }])).toThrow();
  });
});
