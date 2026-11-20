import { describe, expect, it } from 'vitest';
import {
  aggregateBmoRecords,
  type BmoRecord,
} from '../../supabase/functions/_shared/bmo-acquisition.ts';

/**
 * Le module Edge est exécuté tel quel (alias `npm:fflate@0.8.2` dans vitest.config.ts) :
 * son test Deno voisin n'est pas lancé par la CI.
 *
 * Règle vérifiée : la part « jugés difficiles » d'un département n'est publiée que si
 * aucun bassin d'emploi ne masque ses projets ou sa part. Les agents de croissance ne
 * citent la donnée que si la part existe (`bmo_difficulte_pct IS NOT NULL`) : une part
 * calculée sur les seuls bassins publiés partait donc dans des brouillons de prospection.
 */
const ligne = (
  departement: string,
  projects: number | null,
  difficult: number | null,
  seasonal: number | null = 0,
  code = 'V0X60',
): BmoRecord => ({ year: 2026, code, label: 'Aides-soignants', departement, projects, difficult, seasonal });

const as = (records: BmoRecord[], departement: string) =>
  aggregateBmoRecords(records).find((r) => r.departement === departement && r.profession === 'AS');

describe('import BMO — part des projets jugés difficiles', () => {
  it('calcule la part sur le département entier quand aucun bassin n’est masqué', () => {
    const r = as([ligne('92', 100, 20), ligne('92', 300, 60, 30)], '92');
    expect(r?.bmo_projets_recrutement).toBe(400);
    expect(r?.bmo_difficulte_pct).toBe(20);
    expect(r?.bmo_saisonnier_pct).toBe(7.5);
  });

  it('ne publie aucune part dès qu’un bassin masque sa part de projets difficiles', () => {
    // Ancien calcul : 74 / 100 = 74 %, en ignorant les 871 projets du bassin masqué.
    const r = as([ligne('56', 100, 74), ligne('56', 871, null)], '56');
    expect(r?.bmo_projets_recrutement).toBe(971);
    expect(r?.bmo_difficulte_pct).toBeNull();
    expect(r?.bmo_saisonnier_pct).toBe(0);
  });

  it('ne publie aucune part dès qu’un bassin masque son nombre de projets', () => {
    const r = as([ligne('29', 50, 25, 5), ligne('29', null, null, null)], '29');
    expect(r?.bmo_projets_recrutement).toBe(50);
    expect(r?.bmo_difficulte_pct).toBeNull();
    expect(r?.bmo_saisonnier_pct).toBeNull();
  });

  it('ne publie aucune part quand les projets sont masqués alors que la part difficile est publiée', () => {
    // Sans ce cas, la part vaudrait 30 / 50 = 60 % : les 5 projets difficiles du bassin masqué
    // seraient rapportés à un total qui ne compte pas ce bassin.
    const r = as([ligne('22', 50, 25, 5), ligne('22', null, 5, 1)], '22');
    expect(r?.bmo_projets_recrutement).toBe(50);
    expect(r?.bmo_difficulte_pct).toBeNull();
    expect(r?.bmo_saisonnier_pct).toBeNull();
  });

  it('un bassin masqué dans un département ne retire pas la part du département voisin', () => {
    const records = [ligne('56', 100, 74), ligne('56', 871, null), ligne('35', 200, 100), ligne('35', 200, 60)];
    expect(as(records, '56')?.bmo_difficulte_pct).toBeNull();
    expect(as(records, '35')?.bmo_difficulte_pct).toBe(40);
  });

  it('traite la part saisonnière indépendamment de la part difficile', () => {
    const r = as([ligne('35', 200, 100, null), ligne('35', 200, 60, 10)], '35');
    expect(r?.bmo_difficulte_pct).toBe(40);
    expect(r?.bmo_saisonnier_pct).toBeNull();
  });

  it('ne fabrique pas de part sur un département sans projet', () => {
    const r = as([ligne('48', 0, 0)], '48');
    expect(r?.bmo_projets_recrutement).toBe(0);
    expect(r?.bmo_difficulte_pct).toBeNull();
  });

  it('applique la même règle aux catégories agrégées (infirmiers et sages-femmes)', () => {
    const rows = aggregateBmoRecords([
      ligne('69', 120, 60, 0, 'V1X80'),
      ligne('69', 80, null, 0, 'V1X80'),
    ]);
    expect(rows.map((r) => r.profession).sort()).toEqual(['IDE', 'SAGE_FEMME']);
    expect(rows.every((r) => r.bmo_projets_recrutement === 200 && r.bmo_difficulte_pct === null)).toBe(true);
  });
});
