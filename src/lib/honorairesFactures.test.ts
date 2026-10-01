import { beforeEach, describe, expect, it, vi } from 'vitest';
const transport = vi.hoisted(() => ({ pages: [] as any[], ranges: [] as number[][], actor: '' }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  from: vi.fn((table: string) => {
    expect(table).toBe('factures_honoraires');
    const query: any = {
      select: vi.fn((_fields: string, options: unknown) => { expect(options).toEqual({ count: 'exact' }); return query; }),
      eq: vi.fn((column: string, value: string) => { expect(column).toBe('soignant_id'); transport.actor = value; return query; }),
      order: vi.fn((column: string) => { expect(column).toBe('id'); return query; }),
      range: vi.fn((start: number, end: number) => { transport.ranges.push([start, end]); return Promise.resolve(transport.pages.shift()); }),
    }; return query;
  }),
} }));
import { chargerHonorairesFactures, resumerHonorairesFactures } from './honorairesFactures';

const doc = (id: string, overrides: Record<string, unknown> = {}) => ({
  id, soignant_id: 'synthese-soignant', mission_id: 'mission', type_document: 'FACTURE',
  statut: 'EMISE', montant_ttc: 80, date_emission: '2026-10-01', ...overrides,
});
beforeEach(() => { transport.pages = []; transport.ranges = []; transport.actor = ''; });

describe('honoraires facturés, distincts du planning et des encaissements', () => {
  it('remplacement 60 + période suivante 80 = 140, jamais ancien 80 ni budget 160', () => {
    expect(resumerHonorairesFactures([
      doc('ancienne', { statut: 'REMPLACEE' }), doc('rectificative', { montant_ttc: 60 }), doc('suivante'),
      doc('annulee', { statut: 'ANNULEE' }), doc('erreur', { statut: 'ERREUR_GENERATION' }), doc('brouillon', { statut: 'BROUILLON' }),
    ])).toEqual({ montant: 140, nombre: 2 });
  });
  it('déduit un avoir émis ou remboursé, sans confondre facturé et payé', () => {
    expect(resumerHonorairesFactures([
      doc('payee', { statut: 'PAYEE' }), doc('avoir', { type_document: 'AVOIR', statut: 'REMBOURSE', montant_ttc: 20 }),
      doc('suivante'), doc('avoir-brouillon', { type_document: 'AVOIR', statut: 'BROUILLON', montant_ttc: 25 }),
    ])).toEqual({ montant: 140, nombre: 3 });
  });
  it('respecte les mois d’émission 60/80, sans répartir un global 140 en 70/70', () => {
    const documents = [doc('septembre', { montant_ttc: 60, date_emission: '2026-09-30' }), doc('octobre')];
    expect(resumerHonorairesFactures(documents, '2026-09').montant).toBe(60);
    expect(resumerHonorairesFactures(documents, '2026-10').montant).toBe(80);
    expect(resumerHonorairesFactures(documents, '2026-11')).toEqual({ montant: 0, nombre: 0 });
  });
  it('additionne les centimes exacts', () => {
    expect(resumerHonorairesFactures([doc('a', { montant_ttc: 0.1 }), doc('b', { montant_ttc: 0.2 })]).montant).toBe(0.3);
  });
});

describe('chargement financier exhaustif', () => {
  it('continue après une page plafonnée et contrôle le nombre final', async () => {
    transport.pages = [
      { data: [doc('a')], count: 3, error: null },
      { data: [doc('b'), doc('c')], count: 3, error: null },
    ];
    expect((await chargerHonorairesFactures('synthese-soignant')).map(x => x.id)).toEqual(['a', 'b', 'c']);
    expect(transport.ranges).toEqual([[0, 499], [1, 500]]);
    expect(transport.actor).toBe('synthese-soignant');
  });
  it('accepte une absence de documents prouvée', async () => {
    transport.pages = [{ data: [], count: 0, error: null }];
    expect(await chargerHonorairesFactures('synthese-soignant')).toEqual([]);
  });
  for (const [nom, pages] of Object.entries({
    tronque: [{ data: [doc('a')], count: 2 }, { data: [], count: 2 }],
    duplique: [{ data: [doc('a')], count: 2 }, { data: [doc('a')], count: 2 }],
    change: [{ data: [doc('a')], count: 2 }, { data: [doc('b')], count: 3 }],
    sansCompte: [{ data: [doc('a')], count: null }],
    autreActeur: [{ data: [doc('a', { soignant_id: 'autre' })], count: 1 }],
    montantAbsent: [{ data: [doc('a', { montant_ttc: null })], count: 1 }],
    montantVide: [{ data: [doc('a', { montant_ttc: '' })], count: 1 }],
    montantBooleen: [{ data: [doc('a', { montant_ttc: true })], count: 1 }],
    montantInvalide: [{ data: [doc('a', { montant_ttc: NaN })], count: 1 }],
    dateInvalide: [{ data: [doc('a', { date_emission: '2026-02-30' })], count: 1 }],
    statutInconnu: [{ data: [doc('a', { statut: 'INCONNU' })], count: 1 }],
    typeInconnu: [{ data: [doc('a', { type_document: 'AUTRE' })], count: 1 }],
    erreurTransport: [{ error: new Error('Lecture refusée'), data: null, count: null }],
  })) it(`refuse un total ${nom}`, async () => {
    transport.pages = pages;
    await expect(chargerHonorairesFactures('synthese-soignant')).rejects.toThrow();
  });
});
