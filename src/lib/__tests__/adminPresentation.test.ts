import { describe, expect, it } from 'vitest';
import {
  analyserVettingEtablissement,
  estDonneeTestAdmin,
  formatDureeHeuresAdmin,
  formatEuroAdmin,
  libelleTypeEtablissementAdmin,
  normaliserZero,
  urlAnnuaireEntreprise,
} from '../adminPresentation';

describe('présentation admin Lot 21', () => {
  it('formate les euros en français et supprime le zéro négatif', () => {
    expect(formatEuroAdmin(31)).toBe('31,00 €');
    expect(formatEuroAdmin(-0.001)).toBe('0,00 €');
    expect(normaliserZero(-0)).toBe(0);
  });

  it('présente les durées réelles sans décimales techniques', () => {
    expect(formatDureeHeuresAdmin(0.21)).toBe('13 min');
    expect(formatDureeHeuresAdmin(1.5)).toBe('1 h 30 min');
    expect(formatDureeHeuresAdmin(12)).toBe('12 h');
  });

  it('identifie les seeds Playwright pour les badger sans jamais les masquer', () => {
    expect(estDonneeTestAdmin('[pw-test:match] IDE nuit')).toBe(true);
    expect(estDonneeTestAdmin(['play', 'wright-soignant', '@jolene.app'].join(''))).toBe(true);
    expect(estDonneeTestAdmin('Clinique Saint-Louis')).toBe(false);
  });

  it('mappe les enums établissement vers un libellé humain', () => {
    expect(libelleTypeEtablissementAdmin('CLINIQUE_PRIVEE')).toBe('Clinique Privée');
    expect(libelleTypeEtablissementAdmin('LABO')).toBe('Laboratoire');
  });

  it('signale NAF 62.01Z et SIRET invalide, avec lien officiel pour un SIRET formé', () => {
    const alertes = analyserVettingEtablissement('12345678901234', '62.01Z');
    expect(alertes.map((a) => a.code)).toEqual(['SIRET_INVALIDE', 'NAF_INHABITUEL']);
    expect(alertes[1].message).toContain('62.01Z');
    expect(urlAnnuaireEntreprise('103 305 744 00015')).toBe(
      'https://annuaire-entreprises.data.gouv.fr/etablissement/10330574400015',
    );
  });
});
