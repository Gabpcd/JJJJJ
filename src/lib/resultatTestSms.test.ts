import { describe, expect, it } from 'vitest';
import { resultatTestSms } from './resultatTestSms';

describe('résultat du test SMS administrateur', () => {
  it('distingue acceptation fournisseur et réception sur le téléphone', () => {
    const resultat = resultatTestSms({ success: true, sid: 'SM-test' });
    expect(resultat.etat).toBe('accepte');
    expect(resultat.detail).toContain('réception sur le téléphone reste à confirmer');
  });
  it.each([null, {}, { success: true }, { sid: 'SM-test' }, { success: true, sid: ' ' }])(
    'ne transforme pas une réponse incomplète en succès : %j', reponse => {
      expect(resultatTestSms(reponse).etat).toBe('incertain');
    },
  );
  it.each([
    { success: true, skipped: true, sid: 'SM-test' },
    { success: true, configured: false },
    { success: false, error: 'Demande refusée', sid: 'SM-test' },
  ])('ne valide pas un envoi ignoré ou refusé : %j', reponse => {
    expect(resultatTestSms(reponse).etat).toBe('non-envoye');
  });
  it('préserve un résultat ambigu sans inciter à renvoyer', () => {
    const resultat = resultatTestSms({ success: false, pending: true, sid: 'SM-test' });
    expect(resultat.etat).toBe('incertain');
    expect(resultat.detail).toContain('Ne relancez pas');
  });
  it('ne reproduit pas une réponse inconnue pouvant contenir des données privées', () => {
    expect(resultatTestSms({ diagnostic: 'DONNEE_PRIVEE' }).detail).not.toContain('DONNEE_PRIVEE');
  });
});
