import { describe, it, expect } from 'vitest';
import { PROFESSIONS, CONTRATS, TYPES_ETABLISSEMENT, PROFESSIONS_NON_LIBERAL, PROFESSIONS_SANS_RPPS, PROFESSIONS_PHARMACIE } from '../constantes';

describe('constantes', () => {
  describe('PROFESSIONS', () => {
    it('should have 15 professions', () => {
      expect(PROFESSIONS).toHaveLength(15);
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

    it('should include CDDU and LIBERAL', () => {
      const valeurs = CONTRATS.map(c => c.valeur);
      expect(valeurs).toContain('CDDU');
      expect(valeurs).toContain('LIBERAL');
    });
  });

  describe('TYPES_ETABLISSEMENT', () => {
    it('should have 11 establishment types', () => {
      expect(TYPES_ETABLISSEMENT).toHaveLength(11);
    });

    it('should include EHPAD and HOPITAL_PUBLIC', () => {
      const valeurs = TYPES_ETABLISSEMENT.map(t => t.valeur);
      expect(valeurs).toContain('EHPAD');
      expect(valeurs).toContain('HOPITAL_PUBLIC');
      expect(valeurs).toContain('PHARMACIE_OFFICINE');
    });
  });

  describe('PROFESSIONS_SANS_RPPS', () => {
    it('should only contain AS and AES', () => {
      expect(PROFESSIONS_SANS_RPPS).toEqual(['AS', 'AES']);
    });

    it('should be a subset of PROFESSIONS', () => {
      const allValeurs = PROFESSIONS.map(p => p.valeur);
      for (const p of PROFESSIONS_SANS_RPPS) {
        expect(allValeurs).toContain(p);
      }
    });
  });

  describe('PROFESSIONS_NON_LIBERAL', () => {
    it('should contain 5 professions', () => {
      expect(PROFESSIONS_NON_LIBERAL).toHaveLength(5);
    });
  });

  describe('PROFESSIONS_PHARMACIE', () => {
    it('should contain PHARMACIEN and PREPARATEUR_PHARMA', () => {
      expect(PROFESSIONS_PHARMACIE).toEqual(['PHARMACIEN', 'PREPARATEUR_PHARMA']);
    });
  });
});
