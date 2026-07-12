import { describe, it, expect } from 'vitest';
import { VILLES_SEO, PROFESSIONS_SEO, getVilleBySlug, getProfessionBySlug } from '../seo-data';

describe('VILLES_SEO', () => {
  it('should have 100 cities', () => {
    expect(VILLES_SEO).toHaveLength(100);
  });

  it('each city should have slug, nom, departement', () => {
    for (const v of VILLES_SEO) {
      expect(v.slug).toBeTruthy();
      expect(v.nom).toBeTruthy();
      expect(v.departement).toMatch(/^(\d{2,3}|2A|2B)$/);
    }
  });

  it('should have unique slugs', () => {
    const slugs = VILLES_SEO.map(v => v.slug);
    expect(new Set(slugs).size).toBe(slugs.length);
  });

  it('should include Paris, Lyon, Marseille', () => {
    const slugs = VILLES_SEO.map(v => v.slug);
    expect(slugs).toContain('paris');
    expect(slugs).toContain('lyon');
    expect(slugs).toContain('marseille');
  });
});

describe('PROFESSIONS_SEO', () => {
  it('should have 15 professions', () => {
    expect(PROFESSIONS_SEO).toHaveLength(15);
  });

  it('each profession should have slug, description, salaire_moyen', () => {
    for (const p of PROFESSIONS_SEO) {
      expect(p.slug).toBeTruthy();
      expect(p.description.length).toBeGreaterThan(20);
      expect(p.salaire_moyen).toMatch(/\d+.*€\/h/);
    }
  });

  it('ne promet aucun remplacement de titulaire d’officine', () => {
    const pharmacien = PROFESSIONS_SEO.find((p) => p.valeur === 'PHARMACIEN');
    const manipulateur = PROFESSIONS_SEO.find((p) => p.valeur === 'MANIPULATEUR_RADIO');

    expect(pharmacien?.description).toContain('PUI');
    expect(pharmacien?.description).toContain('n’est pas proposé');
    expect(manipulateur?.description).toContain('exclusivement en contrat salarié');
  });
});

describe('getVilleBySlug', () => {
  it('should find Paris', () => {
    const v = getVilleBySlug('paris');
    expect(v?.nom).toBe('Paris');
    expect(v?.departement).toBe('75');
  });

  it('should return undefined for unknown slug', () => {
    expect(getVilleBySlug('atlantis')).toBeUndefined();
  });
});

describe('getProfessionBySlug', () => {
  it('should find IDE', () => {
    const p = getProfessionBySlug('infirmier-ide');
    expect(p?.valeur).toBe('IDE');
  });

  it('should return undefined for unknown slug', () => {
    expect(getProfessionBySlug('astronaute')).toBeUndefined();
  });
});
