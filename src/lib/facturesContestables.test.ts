import { beforeEach, describe, expect, it, vi } from 'vitest';
import { chargerFacturesContestables } from './facturesContestables';
const mocks = vi.hoisted(() => ({ pages: [] as any[], calls: [] as any[] }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: () => {
  const q: any = {};
  for (const method of ['select', 'eq', 'in', 'order', 'range']) q[method] = (...args: any[]) => { mocks.calls.push([method, ...args]); return q; };
  q.abortSignal = async () => mocks.pages.shift();
  return q;
} } }));
const doc = (id = 'a') => ({ id, mission_id: 'm', numero_facture: `F-${id}`, montant_ttc: 80, statut: 'PAYEE' });
const lire = (id?: string) => chargerFacturesContestables('m', id, new AbortController().signal);
describe('Factures contestables : lecture entière ou refus', () => {
  beforeEach(() => { mocks.pages = []; mocks.calls = []; });
  it('continue malgré une limite PostgREST inférieure à la page demandée', async () => {
    mocks.pages = [{ data: [doc()], count: 2, error: null }, { data: [doc('b')], count: 2, error: null }];
    expect((await lire()).map(d => d.id)).toEqual(['a', 'b']);
    expect(mocks.calls.filter(c => c[0] === 'range')).toEqual([['range', 0, 499], ['range', 1, 500]]);
  });
  it('charge une pièce explicite uniquement dans sa mission, brouillon compris', async () => {
    mocks.pages = [{ data: [{ ...doc(), statut: 'BROUILLON' }], count: 1, error: null }];
    expect((await lire('a'))[0].id).toBe('a');
    expect(mocks.calls).toContainEqual(['eq', 'mission_id', 'm']);
    expect(mocks.calls).toContainEqual(['eq', 'id', 'a']);
  });
  it('accepte uniquement une absence documentée pour un parcours sans pièce imposée', async () => {
    mocks.pages = [{ data: [], count: 0, error: null }]; expect(await lire()).toEqual([]);
    mocks.pages = [{ data: [], count: 0, error: null }]; await expect(lire('a')).rejects.toThrow();
  });
  it.each([
    [{ data: null, error: { code: '42501' }, count: null }],
    [{ data: [doc()], count: null, error: null }],
    [{ data: [], count: 1, error: null }],
    [{ data: [doc()], count: 0, error: null }],
    [{ data: [doc()], count: 2, error: null }, { data: [doc()], count: 2, error: null }],
    [{ data: [doc()], count: 2, error: null }, { data: [doc('b')], count: 3, error: null }],
    [{ data: [{ ...doc(), mission_id: 'autre' }], count: 1, error: null }],
    [{ data: [{ ...doc(), statut: 'REMPLACEE' }], count: 1, error: null }],
    [{ data: [{ ...doc(), montant_ttc: null }], count: 1, error: null }],
    [{ data: [], count: 10001, error: null }],
  ])('refuse un résultat incomplet ou incohérent %#', async (...pages) => {
    mocks.pages = pages; await expect(lire()).rejects.toBeDefined();
  });
  it('refuse une autre pièce malgré une réponse réussie', async () => {
    mocks.pages = [{ data: [doc('b')], count: 1, error: null }]; await expect(lire('a')).rejects.toThrow();
  });
});
