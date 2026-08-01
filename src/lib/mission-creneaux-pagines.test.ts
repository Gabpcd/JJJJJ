import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  reponses: [] as Array<{ data: unknown[] | null; error: unknown; count: number | null }>,
  ranges: [] as Array<[number, number]>,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: vi.fn(() => {
      const builder: Record<string, any> = {};
      for (const methode of ['select', 'in', 'eq', 'order', 'abortSignal']) {
        builder[methode] = vi.fn(() => builder);
      }
      builder.range = vi.fn((debut: number, fin: number) => {
        mocks.ranges.push([debut, fin]);
        return builder;
      });
      builder.then = (resoudre: (valeur: unknown) => unknown, rejeter: (raison: unknown) => unknown) => (
        Promise.resolve(mocks.reponses.shift()).then(resoudre, rejeter)
      );
      return builder;
    }),
  },
}));

import { chargerCreneauxMissionsPagines } from './mission-creneaux-pagines';

function creneau(id: string) {
  return {
    id,
    mission_id: 'mission-1',
    debut: `2026-08-0${id}T08:00:00+02:00`,
    fin: `2026-08-0${id}T16:00:00+02:00`,
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  };
}

describe('chargerCreneauxMissionsPagines', () => {
  beforeEach(() => {
    mocks.reponses.length = 0;
    mocks.ranges.length = 0;
  });

  it('continue jusqu’au count exact lorsque PostgREST tronque une page', async () => {
    mocks.reponses.push(
      { data: [creneau('1'), creneau('2')], error: null, count: 3 },
      { data: [creneau('3')], error: null, count: 3 },
    );

    const resultat = await chargerCreneauxMissionsPagines(['mission-1'], { taillePage: 2 });

    expect(resultat.map((item) => item.id)).toEqual(['1', '2', '3']);
    expect(mocks.ranges).toEqual([[0, 1], [2, 3]]);
  });

  it('échoue fermé si une page manque avant le total annoncé', async () => {
    mocks.reponses.push(
      { data: [creneau('1')], error: null, count: 2 },
      { data: [], error: null, count: 2 },
    );

    await expect(
      chargerCreneauxMissionsPagines(['mission-1'], { taillePage: 1 }),
    ).rejects.toThrow(/incomplet/i);
  });

  it('échoue fermé si le count exact est indisponible', async () => {
    mocks.reponses.push({ data: [], error: null, count: null });

    await expect(chargerCreneauxMissionsPagines(['mission-1']))
      .rejects.toThrow(/nombre total/i);
  });

  it('échoue fermé si deux pages se chevauchent partiellement', async () => {
    mocks.reponses.push(
      { data: [creneau('1'), creneau('2')], error: null, count: 4 },
      { data: [creneau('2'), creneau('3')], error: null, count: 4 },
    );

    await expect(
      chargerCreneauxMissionsPagines(['mission-1'], { taillePage: 2 }),
    ).rejects.toThrow(/manquants ou dupliqu/i);
  });
});
