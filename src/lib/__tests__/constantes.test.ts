import { describe, it, expect } from 'vitest';
import { PROFESSIONS, CONTRATS, TYPES_ETABLISSEMENT, PROFESSIONS_NON_LIBERAL, PROFESSIONS_SANS_RPPS, PROFESSIONS_PHARMACIE, peutExercerLiberal, peutExercer, typesEtablissementCompatiblesLiberal } from '../constantes';

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

  describe('PROFESSIONS_NON_LIBERAL', () => {
    it('should be a subset of PROFESSIONS', () => {
      const allValeurs = PROFESSIONS.map(p => p.valeur);
      for (const p of PROFESSIONS_NON_LIBERAL) {
        expect(allValeurs).toContain(p);
      }
    });

    it('should include AUXILIAIRE_PUERICULTURE (PR 2 Sprint 1)', () => {
      expect(PROFESSIONS_NON_LIBERAL).toContain('AUXILIAIRE_PUERICULTURE');
    });
  });

  describe('peutExercerLiberal (PR 2 Sprint 1)', () => {
    it('IDE libéral autorisé en CABINET_IDEL uniquement', () => {
      expect(peutExercerLiberal('IDE', 'CABINET_IDEL')).toBe(true);
      expect(peutExercerLiberal('IDE', 'EHPAD')).toBe(false);
      expect(peutExercerLiberal('IDE', 'CLINIQUE_PRIVEE')).toBe(false);
      expect(peutExercerLiberal('IDE', 'HOPITAL_PUBLIC')).toBe(false);
    });

    it('MEDECIN libéral autorisé en CABINET_MEDICAL, CLINIQUE_PRIVEE, EHPAD, SSIAD, HAD, CENTRE_SANTE, MAS, FAM', () => {
      expect(peutExercerLiberal('MEDECIN', 'CABINET_MEDICAL')).toBe(true);
      expect(peutExercerLiberal('MEDECIN', 'CLINIQUE_PRIVEE')).toBe(true);
      expect(peutExercerLiberal('MEDECIN', 'EHPAD')).toBe(true);
      expect(peutExercerLiberal('MEDECIN', 'HOPITAL_PUBLIC')).toBe(false);
      expect(peutExercerLiberal('MEDECIN', 'CABINET_IDEL')).toBe(false);
    });

    it('DENTISTE libéral autorisé en CABINET_DENTAIRE uniquement', () => {
      expect(peutExercerLiberal('DENTISTE', 'CABINET_DENTAIRE')).toBe(true);
      expect(peutExercerLiberal('DENTISTE', 'CABINET_MEDICAL')).toBe(false);
      expect(peutExercerLiberal('DENTISTE', 'CLINIQUE_PRIVEE')).toBe(false);
    });

    it('AS, AES, AUX_PUERICULTURE jamais libéral', () => {
      expect(peutExercerLiberal('AS', 'EHPAD')).toBe(false);
      expect(peutExercerLiberal('AES', 'MAS')).toBe(false);
      expect(peutExercerLiberal('AUXILIAIRE_PUERICULTURE', 'EHPAD')).toBe(false);
    });

    it('IBODE/IADE/DIETETICIEN bloqués (PROFESSIONS_NON_LIBERAL)', () => {
      expect(peutExercerLiberal('IBODE', 'CLINIQUE_PRIVEE')).toBe(false);
      expect(peutExercerLiberal('IADE', 'HOPITAL_PUBLIC')).toBe(false);
      expect(peutExercerLiberal('DIETETICIEN', 'CABINET_MEDICAL')).toBe(false);
    });

    it('ORTHOPHONISTE/ERGOTHERAPEUTE/PSYCHOMOTRICIEN libéral dans leur cabinet dédié', () => {
      expect(peutExercerLiberal('ORTHOPHONISTE', 'CABINET_ORTHO')).toBe(true);
      expect(peutExercerLiberal('ORTHOPHONISTE', 'EHPAD')).toBe(false);
      expect(peutExercerLiberal('ERGOTHERAPEUTE', 'CABINET_ERGO')).toBe(true);
      expect(peutExercerLiberal('ERGOTHERAPEUTE', 'HAD')).toBe(true);
      expect(peutExercerLiberal('PSYCHOMOTRICIEN', 'CABINET_PSYCHOMOT')).toBe(true);
      expect(peutExercerLiberal('PSYCHOMOTRICIEN', 'HAD')).toBe(true);
    });
  });

  describe('peutExercer (mode salarié vs libéral)', () => {
    it('SALARIE compatible avec tous types (par défaut)', () => {
      expect(peutExercer('IDE', 'SALARIE', 'EHPAD')).toBe(true);
      expect(peutExercer('IDE', 'CDD', 'CLINIQUE_PRIVEE')).toBe(true);
      expect(peutExercer('AS', 'VACATION', 'HOPITAL_PUBLIC')).toBe(true);
    });

    it('LIBERAL délègue à peutExercerLiberal', () => {
      expect(peutExercer('IDE', 'LIBERAL', 'EHPAD')).toBe(false);
      expect(peutExercer('IDE', 'LIBERAL', 'CABINET_IDEL')).toBe(true);
    });

    it('MIXTE délègue à peutExercerLiberal aussi', () => {
      expect(peutExercer('MEDECIN', 'MIXTE', 'CLINIQUE_PRIVEE')).toBe(true);
      expect(peutExercer('MEDECIN', 'MIXTE', 'CABINET_IDEL')).toBe(false);
    });
  });

  describe('typesEtablissementCompatiblesLiberal', () => {
    it('renvoie la liste pour MEDECIN', () => {
      const list = typesEtablissementCompatiblesLiberal('MEDECIN');
      expect(list).toContain('CABINET_MEDICAL');
      expect(list).toContain('EHPAD');
      expect(list).not.toContain('HOPITAL_PUBLIC');
    });

    it('renvoie [] pour AS', () => {
      expect(typesEtablissementCompatiblesLiberal('AS')).toEqual([]);
    });
  });

  describe('PROFESSIONS_PHARMACIE', () => {
    it('should contain PHARMACIEN and PREPARATEUR_PHARMA', () => {
      expect(PROFESSIONS_PHARMACIE).toEqual(['PHARMACIEN', 'PREPARATEUR_PHARMA']);
    });
  });
});
