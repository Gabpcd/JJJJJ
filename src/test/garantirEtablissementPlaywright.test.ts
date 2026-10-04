import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it, vi } from 'vitest';
import { FIXTURES } from '../../scripts/lib/playwright-fixtures.mjs';
import { synchroniserAuthEtablissementPlaywright } from '../../e2e/helpers/garantir-etablissement-playwright';

function creerClientUpdateUser(
  erreurs: Array<null | { message: string; status?: number; code?: string }>,
) {
  const updateUserById = vi.fn(async () => ({ error: erreurs.shift() ?? null }));
  const userId = '00000000-0000-4000-8000-000000000001';
  const admin = {
    rpc: vi.fn(async () => ({ data: userId, error: null })),
    from: (table: string) => {
      const chain: any = {
        select: () => chain, eq: () => chain,
        maybeSingle: async () => ({ data: { id: userId, est_compte_test: true }, error: null }),
        limit: async () => ({ data: [], error: null }),
        then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(resolve),
      };
      return chain;
    },
    auth: { admin: { updateUserById, getUserById: vi.fn(async () => ({ data: { user: {
      id: userId, email: FIXTURES.etab.email, app_metadata: { role: FIXTURES.etab.role },
    } }, error: null })) } },
  } as unknown as SupabaseClient;
  return { admin, updateUserById };
}

describe('synchroniserAuthEtablissementPlaywright', () => {
  it('réessaie une panne Auth transitoire puis continue', async () => {
    const { admin, updateUserById } = creerClientUpdateUser([
      { message: '{}', status: 504, code: 'request_timeout' },
      null,
    ]);
    const attendre = vi.fn(async () => undefined);

    await expect(
      synchroniserAuthEtablissementPlaywright(admin, '00000000-0000-4000-8000-000000000001', 'a'.repeat(64), attendre),
    ).resolves.toBeUndefined();

    expect(updateUserById).toHaveBeenCalledTimes(2);
    expect(attendre).toHaveBeenCalledWith(2_000);
  });

  it('échoue immédiatement sur un refus non transitoire', async () => {
    const { admin, updateUserById } = creerClientUpdateUser([
      { message: 'Forbidden', status: 403, code: 'forbidden' },
    ]);
    const attendre = vi.fn(async () => undefined);

    await expect(
      synchroniserAuthEtablissementPlaywright(admin, '00000000-0000-4000-8000-000000000001', 'a'.repeat(64), attendre),
    ).rejects.toThrow('"status":403');

    expect(updateUserById).toHaveBeenCalledTimes(1);
    expect(attendre).not.toHaveBeenCalled();
  });

  it('conserve le diagnostic après trois pannes transitoires', async () => {
    const { admin, updateUserById } = creerClientUpdateUser([
      { message: 'context deadline exceeded', status: 504, code: 'request_timeout' },
      { message: 'context deadline exceeded', status: 504, code: 'request_timeout' },
      { message: 'context deadline exceeded', status: 504, code: 'request_timeout' },
    ]);
    const attendre = vi.fn(async () => undefined);

    await expect(
      synchroniserAuthEtablissementPlaywright(admin, '00000000-0000-4000-8000-000000000001', 'a'.repeat(64), attendre),
    ).rejects.toThrow('"code":"request_timeout"');

    expect(updateUserById).toHaveBeenCalledTimes(3);
    expect(attendre).toHaveBeenNthCalledWith(1, 2_000);
    expect(attendre).toHaveBeenNthCalledWith(2, 5_000);
  });
});
