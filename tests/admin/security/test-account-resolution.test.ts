import { describe, expect, it, vi } from 'vitest';
import {
  resolveOperationalTestAccount,
  resolveOperationalTestSource,
} from '../../../supabase/functions/_shared/test-account';

type QueryResult = {
  data: unknown;
  error: { message: string } | null;
};

function queryBuilder(result: QueryResult) {
  const builder: any = {};
  builder.select = vi.fn(() => builder);
  builder.eq = vi.fn(() => builder);
  builder.maybeSingle = vi.fn(async () => result);
  builder.then = (
    onFulfilled: (value: QueryResult) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ) => Promise.resolve(result).then(onFulfilled, onRejected);
  return builder;
}

function fakeClient(results: {
  soignant?: QueryResult;
  etablissement?: QueryResult;
  membres?: QueryResult;
  admin?: QueryResult;
  missions?: QueryResult;
  litiges?: QueryResult;
}) {
  const builders = {
    soignants: queryBuilder(results.soignant ?? { data: null, error: null }),
    etablissements: queryBuilder(
      results.etablissement ?? { data: null, error: null },
    ),
    membres_etablissement: queryBuilder(
      results.membres ?? { data: [], error: null },
    ),
    equipe_admin: queryBuilder(results.admin ?? { data: null, error: null }),
    missions: queryBuilder(results.missions ?? { data: null, error: null }),
    litiges: queryBuilder(results.litiges ?? { data: null, error: null }),
  };
  return {
    client: {
      from: vi.fn((table: keyof typeof builders) => builders[table]),
    },
    builders,
  };
}

describe('resolveOperationalTestAccount', () => {
  it('classe un profil soignant ou établissement direct selon son marqueur', async () => {
    const testClient = fakeClient({
      soignant: { data: { est_compte_test: true }, error: null },
    });
    await expect(
      resolveOperationalTestAccount(testClient.client as never, crypto.randomUUID()),
    ).resolves.toEqual({ ok: true, isTest: true });

    const realClient = fakeClient({
      etablissement: { data: { est_compte_test: false }, error: null },
    });
    await expect(
      resolveOperationalTestAccount(realClient.client as never, crypto.randomUUID()),
    ).resolves.toEqual({ ok: true, isTest: false });
  });

  it('dérive un membre actif de son établissement et neutralise le multi-rattachement', async () => {
    const { client, builders } = fakeClient({
      membres: {
        data: [
          {
            etablissement_id: crypto.randomUUID(),
            etablissements: { est_compte_test: false },
          },
          {
            etablissement_id: crypto.randomUUID(),
            etablissements: { est_compte_test: true },
          },
        ],
        error: null,
      },
    });

    await expect(
      resolveOperationalTestAccount(client as never, crypto.randomUUID()),
    ).resolves.toEqual({ ok: true, isTest: true });
    expect(builders.membres_etablissement.eq).toHaveBeenCalledWith('actif', true);
  });

  it('autorise explicitement un administrateur actif comme compte réel', async () => {
    const { client, builders } = fakeClient({
      admin: { data: { actif: true }, error: null },
    });

    await expect(
      resolveOperationalTestAccount(client as never, crypto.randomUUID()),
    ).resolves.toEqual({ ok: true, isTest: false });
    expect(builders.equipe_admin.eq).toHaveBeenCalledWith('actif', true);
  });

  it('échoue fermé pour un UUID sans profil, rattachement ni admin actif', async () => {
    const { client } = fakeClient({});
    const result = await resolveOperationalTestAccount(
      client as never,
      crypto.randomUUID(),
    );

    expect(result.ok).toBe(false);
    expect(result).toEqual({
      ok: false,
      error: 'compte opérationnel inconnu',
    });
  });

  it('échoue fermé si une relation membre ou une lecture est incohérente', async () => {
    const missingEstablishment = fakeClient({
      membres: {
        data: [{
          etablissement_id: crypto.randomUUID(),
          etablissements: null,
        }],
        error: null,
      },
    });
    await expect(
      resolveOperationalTestAccount(
        missingEstablishment.client as never,
        crypto.randomUUID(),
      ),
    ).resolves.toEqual({
      ok: false,
      error: 'classification établissement incomplète',
    });

    const readFailure = fakeClient({
      admin: { data: null, error: { message: 'indisponible' } },
    });
    await expect(
      resolveOperationalTestAccount(readFailure.client as never, crypto.randomUUID()),
    ).resolves.toEqual({ ok: false, error: 'indisponible' });
  });
});

describe('resolveOperationalTestSource', () => {
  it('neutralise une source mission/litige test même pour un destinataire réel', async () => {
    const missionId = crypto.randomUUID();
    const etablissementId = crypto.randomUUID();
    const litigeId = crypto.randomUUID();
    const { client } = fakeClient({
      litiges: { data: { mission_id: missionId }, error: null },
      missions: {
        data: {
          etablissement_id: etablissementId,
          soignant_assigne_id: null,
        },
        error: null,
      },
      etablissement: {
        data: { est_compte_test: true },
        error: null,
      },
    });

    await expect(
      resolveOperationalTestSource(client as never, {
        litige_id: litigeId,
      }),
    ).resolves.toEqual({ ok: true, isTest: true });
  });

  it('autorise une mission réelle résolue canoniquement', async () => {
    const missionId = crypto.randomUUID();
    const { client } = fakeClient({
      missions: {
        data: {
          etablissement_id: crypto.randomUUID(),
          soignant_assigne_id: null,
        },
        error: null,
      },
      etablissement: {
        data: { est_compte_test: false },
        error: null,
      },
    });

    await expect(
      resolveOperationalTestSource(client as never, {
        data: { mission_id: missionId },
      }),
    ).resolves.toEqual({ ok: true, isTest: false });
  });

  it('échoue fermé sur une source invalide ou introuvable', async () => {
    const { client } = fakeClient({});
    await expect(
      resolveOperationalTestSource(client as never, {
        mission_id: 'pas-un-uuid',
      }),
    ).resolves.toEqual({
      ok: false,
      error: 'identifiant source invalide',
    });

    await expect(
      resolveOperationalTestSource(client as never, {
        litige_id: crypto.randomUUID(),
      }),
    ).resolves.toEqual({
      ok: false,
      error: 'source litige introuvable',
    });
  });
});
