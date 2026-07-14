import { describe, expect, it } from 'vitest';
import { contratServiceEstSigne } from './contratEtablissement';

describe('contratServiceEstSigne', () => {
  it('autorise un contrat de service réellement signé', () => {
    expect(contratServiceEstSigne({ contrat_service_signe: true })).toBe(true);
  });

  it("n'assimile jamais l'ancienne validation du PDF à une signature", () => {
    expect(contratServiceEstSigne({
      contrat_service_signe: false,
      contrat_valide: true,
    })).toBe(false);
  });

  it('échoue de façon sûre lorsque le champ canonique manque', () => {
    expect(contratServiceEstSigne({ contrat_valide: true })).toBe(false);
    expect(contratServiceEstSigne(undefined)).toBe(false);
  });
});
