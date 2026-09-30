import { describe, expect, it } from 'vitest';
import { choisirContenuContratAffiche, contratNecessiteRenduServeur, contratPossedeSignature, contientVariablesContratNonRendues } from './contratMissionUi';
describe('contratMissionUi', () => {
  it('reconstitue seulement un aperçu non figé, détecte les variables non rendues', () => {
    expect(contientVariablesContratNonRendues('<p>{{motif_cdd}}</p>')).toBe(true);
    expect(choisirContenuContratAffiche('<p>{{motif_cdd}}</p>', '<p>Aperçu</p>')).toBe('<p>Aperçu</p>');
    expect(contratNecessiteRenduServeur('<p>Aperçu</p>', null)).toBe(true);
  });
  it('ne régénère jamais un document stocké pour actualiser ses clauses', () => {
    expect(contratNecessiteRenduServeur('<p>10h/jour (L3121-18)</p>', 'contrat/ancien.html')).toBe(false);
    expect(contratNecessiteRenduServeur('<p>{{motif_cdd}}</p>', 'contrat/ancien.html')).toBe(false);
  });
  it.each([{ statut: 'SIGNE_COMPLET' }, { statut: 'SIGNE_SOIGNANT' }, { signature_soignant: true },
    { signature_etablissement: true }, { signature_soignant_le: '2026-01-01' }, { signature_etablissement_le: '2026-01-01' }])('conserve une preuve signée même sans Storage : %j', contrat => {
    expect(contratPossedeSignature(contrat)).toBe(true);
    expect(contratNecessiteRenduServeur(null, null, contrat)).toBe(false);
    expect(choisirContenuContratAffiche(null, '<p>Nouveau template</p>', true)).toBe('');
    expect(choisirContenuContratAffiche('<p>Original {{variable}}</p>', '<p>Nouveau template</p>', true)).toBe('<p>Original {{variable}}</p>');
  });
});
