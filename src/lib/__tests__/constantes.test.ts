import { describe, it, expect } from 'vitest';
import { PROFESSIONS, CONTRATS, TYPES_ETABLISSEMENT, PROFESSIONS_SANS_RPPS, PROFESSIONS_PHARMACIE } from '../constantes';

describe('constantes', () => {
  describe('PROFESSIONS', () => {
    it('should have 17 professions (PR 2 Sprint 1 — added DENTISTE + AUXILIAIRE_PUERICULTURE)', () => {
      expect(PROFESSIONS).toHaveLength(17);
    });

    it('should include DENTISTE and AUXILIAIRE_PUERICULTURE', () => {
      const valeurs = PROFESSIONS.map(p => p.valeur);
      expect(valeurs).toContain('DENTISTE');
      expect(valeurs).toContain('AUXILIAIRE_PUERICULTURE');
    });

    it('each profession should have valeur and label', () => {
      for (const p of PROFESSIONS) {
        expect(p.valeur).toBeTruthy();
        expect(p.label).toBeTruthy();
        expect(typeof p.valeur).toBe('string');
        expect(typeof p.label).toBe('string');
      }
    });

    it('should have unique valeurs', () => {
      const valeurs = PROFESSIONS.map(p => p.valeur);
      expect(new Set(valeurs).size).toBe(valeurs.length);
    });

    it('should include critical professions', () => {
      const valeurs = PROFESSIONS.map(p => p.valeur);
      expect(valeurs).toContain('IDE');
      expect(valeurs).toContain('AS');
      expect(valeurs).toContain('MEDECIN');
      expect(valeurs).toContain('PHARMACIEN');
      expect(valeurs).toContain('SAGE_FEMME');
    });
  });

  describe('CONTRATS', () => {
    it('should have 4 contract types', () => {
      expect(CONTRATS).toHaveLength(4);
    });

    it('should include CDD and LIBERAL', () => {
      const valeurs = CONTRATS.map(c => c.valeur);
      expect(valeurs).toContain('CDD');
      expect(valeurs).toContain('LIBERAL');
    });

    it('should NOT include CDDU (refactored to CDD in PR 1 Sprint 1)', () => {
      const valeurs = CONTRATS.map(c => c.valeur);
      expect(valeurs).not.toContain('CDDU');
    });

    it('présente la vacation comme un CDD court', () => {
      expect(CONTRATS.find(c => c.valeur === 'VACATION')?.label).toBe('CDD court');
    });
  });

  describe('TYPES_ETABLISSEMENT', () => {
    it('should have 20 establishment types (PR 2 Sprint 1 — added ESPIC + 8 CABINET_*)', () => {
      expect(TYPES_ETABLISSEMENT).toHaveLength(20);
    });

    it('should include EHPAD and HOPITAL_PUBLIC', () => {
      const valeurs = TYPES_ETABLISSEMENT.map(t => t.valeur);
      expect(valeurs).toContain('EHPAD');
      expect(valeurs).toContain('HOPITAL_PUBLIC');
      expect(valeurs).toContain('PHARMACIE_OFFICINE');
    });

    it('should include ESPIC and all 8 CABINET_* types', () => {
      const valeurs = TYPES_ETABLISSEMENT.map(t => t.valeur);
      expect(valeurs).toContain('ESPIC');
      expect(valeurs).toContain('CABINET_MEDICAL');
      expect(valeurs).toContain('CABINET_DENTAIRE');
      expect(valeurs).toContain('CABINET_IDEL');
      expect(valeurs).toContain('CABINET_SAGE_FEMME');
      expect(valeurs).toContain('CABINET_KINE');
      expect(valeurs).toContain('CABINET_ORTHO');
      expect(valeurs).toContain('CABINET_ERGO');
      expect(valeurs).toContain('CABINET_PSYCHOMOT');
    });
  });

  describe('PROFESSIONS_SANS_RPPS', () => {
    it('should contain AS, AES and AUXILIAIRE_PUERICULTURE (professions sans RPPS)', () => {
      expect(PROFESSIONS_SANS_RPPS).toEqual(['AS', 'AES', 'AUXILIAIRE_PUERICULTURE']);
    });

    it('should be a subset of PROFESSIONS', () => {
      const allValeurs = PROFESSIONS.map(p => p.valeur);
      for (const p of PROFESSIONS_SANS_RPPS) {
        expect(allValeurs).toContain(p);
      }
    });
  });

  describe('PROFESSIONS_PHARMACIE', () => {
    it('should contain PHARMACIEN and PREPARATEUR_PHARMA', () => {
      expect(PROFESSIONS_PHARMACIE).toEqual(['PHARMACIEN', 'PREPARATEUR_PHARMA']);
    });
  });
});
