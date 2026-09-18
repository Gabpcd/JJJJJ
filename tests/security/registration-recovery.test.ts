import { webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it, vi } from 'vitest';

type AccountType = 'SOIGNANT' | 'ETABLISSEMENT' | 'ADMIN';
type BusinessRole = 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' | 'ADMIN_PLATEFORME';
type Handler = (request: Request) => Promise<Response>;
type Result = { data: unknown; error: { code: string } | null };

const endpoints = [
  {
    name: 'register-soignant',
    accountType: 'SOIGNANT' as const,
    role: 'SOIGNANT' as const,
    profileTable: 'soignants',
    validBody: { prenom: 'Camille', nom: 'Test', profession: 'AS', dateNaissance: '1990-01-01' },
  },
  {
    name: 'register-etablissement',
    accountType: 'ETABLISSEMENT' as const,
    role: 'ADMIN_ETABLISSEMENT' as const,
    profileTable: 'etablissements',
    validBody: { nom: 'Résidence test', siret: '73282932000074', type: 'EHPAD', adresse_ville: 'Lyon' },
  },
];

/**
 * Exécute les vrais handlers et leurs helpers partagés, sans serveur Deno ni
 * réseau. Seules les frontières Auth, PostgREST et registre SIRET sont simulées.
 * Le modèle de réservation reprend les réponses des RPC SQL ; les tests SQL
 * restent responsables de vérifier leur implémentation et leurs ACL.
 */
function harness(endpoint: typeof endpoints[number], options: {
  progressive?: boolean;
  draftReadErrors?: number;
  finalization?: 'success' | 'committed_response_lost' | 'first_attempt_unavailable' | 'unavailable';
  existingRole?: BusinessRole;
} = {}) {
  const roleType = (role: BusinessRole): AccountType => role === 'SOIGNANT'
    ? 'SOIGNANT' : role === 'ADMIN_PLATEFORME' ? 'ADMIN' : 'ETABLISSEMENT';
  const userId = '69000000-0000-4000-8000-000000000003';
  const state = {
    authExists: true,
    draftExists: options.progressive !== false,
    profileExists: !!options.existingRole,
    role: options.existingRole ?? null as BusinessRole | null,
    accountType: options.existingRole ? roleType(options.existingRole)
      : options.progressive === false ? null : endpoint.accountType as AccountType | null,
    finalizedAt: options.existingRole ? '2026-01-01T00:00:00Z' : null as string | null,
    claim: null as string | null,
  };
  let draftReadErrors = options.draftReadErrors ?? 0;
  let finalizationResponsesLost = options.finalization === 'committed_response_lost' ? 1 : 0;
  let finalizationAttemptsFailed = options.finalization === 'first_attempt_unavailable' ? 1 : 0;
  const ok = (data: unknown = null): Result => ({ data, error: null });
  const failure = (): Result => ({ data: null, error: { code: 'FETCH_ERROR' } });
  const user = () => ({
    id: userId,
    email: 'registration-recovery@test.invalid',
    app_metadata: state.role ? { role: state.role } : {},
  });

  const deleteAuth = vi.fn(async () => {
    state.authExists = false;
    state.draftExists = false;
    state.profileExists = false;
    state.role = null;
    state.accountType = null;
    state.finalizedAt = null;
    state.claim = null;
    return ok();
  });
  const deleteProfile = vi.fn(async () => {
    state.profileExists = false;
    return ok();
  });
  const rpc = vi.fn(async (name: string, args: Record<string, string> = {}) => {
    if (name === 'fn_reserver_type_compte') {
      if (!state.authExists) return ok({ allowed: false, code: 'ACCOUNT_AUTH_INACTIVE' });
      if (state.accountType && state.accountType !== args.p_type_compte) {
        return ok({ allowed: false, code: 'ACCOUNT_TYPE_MISMATCH' });
      }
      if (state.profileExists) return ok({ allowed: false, code: 'ACCOUNT_ALREADY_REGISTERED' });
      if (state.finalizedAt) return ok({ allowed: false, code: 'ACCOUNT_REGISTRATION_INCOMPLETE' });
      if (state.claim && state.claim !== args.p_claim_token) {
        return ok({ allowed: false, code: 'ACCOUNT_REGISTRATION_IN_PROGRESS' });
      }
      state.accountType = args.p_type_compte as AccountType;
      state.claim = args.p_claim_token;
      return ok({ allowed: true, fresh: state.role === null, type_compte: state.accountType });
    }
    if (name === 'fn_finaliser_type_compte') {
      if (options.finalization === 'unavailable' || finalizationAttemptsFailed-- > 0) return failure();
      if (!state.profileExists || state.claim !== args.p_claim_token) return ok(false);
      state.finalizedAt = new Date().toISOString();
      state.claim = null;
      if (finalizationResponsesLost-- > 0) return failure();
      return ok(true);
    }
    if (name === 'fn_liberer_inscription_progressive') {
      if (state.claim === args.p_claim_token && !state.finalizedAt) state.claim = null;
      return ok();
    }
    if (name === 'fn_planifier_serie_onboarding') return ok(true);
    throw new Error(`Unexpected RPC: ${name}`);
  });

  const admin = {
    auth: { admin: {
      deleteUser: deleteAuth,
      updateUserById: vi.fn(async (_id: string, payload: { app_metadata: { role: BusinessRole } }) => {
        state.role = payload.app_metadata.role;
        return { data: { user: user() }, error: null };
      }),
    } },
    rpc,
    from: (table: string) => ({
      select: () => {
        const read = async (): Promise<Result> => {
          if (table === 'parcours_inscription') {
            if (draftReadErrors-- > 0) return failure();
            return ok(state.draftExists ? { user_id: userId } : null);
          }
          if (table === 'types_comptes_auth') return ok({
            user_id: userId,
            type_compte: state.accountType,
            finalise_le: state.finalizedAt,
            claim_token: state.claim,
          });
          if (table === endpoint.profileTable) return ok(state.profileExists ? { id: userId } : null);
          throw new Error(`Unexpected SELECT: ${table}`);
        };
        const query = {
          eq: (_column: string, _value: unknown) => query,
          maybeSingle: read,
          single: read,
        };
        return query;
      },
      insert: async () => {
        if (table === endpoint.profileTable) state.profileExists = true;
        else if (table !== 'journaux_audit') throw new Error(`Unexpected INSERT: ${table}`);
        return ok();
      },
      delete: () => ({ eq: async () => {
        if (table !== endpoint.profileTable) throw new Error(`Unexpected DELETE: ${table}`);
        return deleteProfile();
      } }),
    }),
    functions: { invoke: vi.fn(async () => ok()) },
  };
  let handler: Handler | undefined;
  const env: Record<string, string> = {
    SUPABASE_URL: 'https://registration.test.invalid',
    SUPABASE_ANON_KEY: 'test-anon',
    SUPABASE_SERVICE_ROLE_KEY: 'test-service',
  };
  const moduleCache = new Map<string, { exports: Record<string, unknown> }>();
  const load = (path: string): Record<string, unknown> => {
    const cached = moduleCache.get(path);
    if (cached) return cached.exports;
    const module = { exports: {} };
    moduleCache.set(path, module);
    const compiled = ts.transpileModule(readFileSync(path, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
    }).outputText;
    runInNewContext(compiled, {
      module,
      exports: module.exports,
      require: (specifier: string) => {
        if (specifier.startsWith('npm:@supabase/supabase-js@')) return {
          createClient: (_url: string, key: string) => key === env.SUPABASE_SERVICE_ROLE_KEY
            ? admin : { auth: { getUser: async () => ({ data: { user: user() }, error: null }) } },
        };
        if (!specifier.startsWith('.')) throw new Error(`Unexpected import: ${specifier}`);
        return load(resolve(dirname(path), specifier));
      },
      Deno: { env: { get: (key: string) => env[key] }, serve: (callback: Handler) => { handler = callback; } },
      console: { log: vi.fn(), warn: vi.fn(), error: vi.fn() },
      crypto: webcrypto,
      Request, Response, Headers, URL, AbortController, AbortSignal, setTimeout, clearTimeout,
      fetch: vi.fn(async (url: string) => {
        if (!url.startsWith('https://recherche-entreprises.api.gouv.fr/')) {
          throw new Error(`Unexpected network request: ${url}`);
        }
        return Response.json({ results: [] });
      }),
    }, { filename: path });
    return module.exports;
  };
  load(resolve(process.cwd(), `supabase/functions/${endpoint.name}/index.ts`));
  if (!handler) throw new Error('The Edge Function did not register a handler');
  const invoke = handler;
  return {
    state, rpc, deleteAuth, deleteProfile,
    request: (body: unknown = endpoint.validBody) => invoke(new Request(`https://registration.test.invalid/${endpoint.name}`, {
      method: 'POST',
      headers: { Authorization: 'Bearer test-session', 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })),
  };
}

describe.each(endpoints)('$name — reprise de l’inscription', (endpoint) => {
  it('réconcilie une finalisation committée dont la réponse a été perdue', async () => {
    const h = harness(endpoint, { finalization: 'committed_response_lost' });
    const response = await h.request();
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ ok: true });
    expect(h.state).toMatchObject({ authExists: true, profileExists: true, role: endpoint.role, claim: null });
    expect(h.state.finalizedAt).not.toBeNull();
    expect(h.deleteAuth).not.toHaveBeenCalled();
    expect(h.deleteProfile).not.toHaveBeenCalled();
  });

  it('réessaie une finalisation non committée après une indisponibilité transitoire', async () => {
    const h = harness(endpoint, { finalization: 'first_attempt_unavailable' });
    expect((await h.request()).status).toBe(200);
    expect(h.state).toMatchObject({ authExists: true, profileExists: true, role: endpoint.role, claim: null });
    expect(h.state.finalizedAt).not.toBeNull();
    expect(h.deleteAuth).not.toHaveBeenCalled();
    expect(h.deleteProfile).not.toHaveBeenCalled();
  });

  it('garde le profil et Auth lorsque la finalisation reste indisponible', async () => {
    const h = harness(endpoint, { finalization: 'unavailable' });
    const response = await h.request();
    expect(response.status).toBeGreaterThanOrEqual(500);
    expect(h.state).toMatchObject({ authExists: true, profileExists: true, role: endpoint.role });
    expect(h.deleteAuth).not.toHaveBeenCalled();
    expect(h.deleteProfile).not.toHaveBeenCalled();
  });

  it.each([true, false])('libère le claim après erreur de lecture, puis permet la reprise (progressif=%s)', async (progressive) => {
    const h = harness(endpoint, { progressive, draftReadErrors: 1 });
    expect((await h.request()).status).toBe(503);
    expect(h.state).toMatchObject({ authExists: true, profileExists: false, claim: null });
    expect(h.deleteAuth).not.toHaveBeenCalled();
    expect((await h.request()).status).toBe(200);
    expect(h.state).toMatchObject({ authExists: true, profileExists: true, role: endpoint.role });
  });

  it('conserve le compte progressif après validation invalide et accepte une correction', async () => {
    const h = harness(endpoint);
    expect((await h.request({})).status).toBe(400);
    expect(h.state).toMatchObject({ authExists: true, draftExists: true, profileExists: false, role: null, claim: null });
    expect(h.deleteAuth).not.toHaveBeenCalled();
    expect((await h.request()).status).toBe(200);
  });

  it('conserve la compensation historique après validation invalide sans brouillon', async () => {
    const h = harness(endpoint, { progressive: false });
    expect((await h.request({})).status).toBe(400);
    expect(h.deleteAuth).toHaveBeenCalledExactlyOnceWith('69000000-0000-4000-8000-000000000003');
    expect(h.state).toMatchObject({ authExists: false, profileExists: false });
  });

  it.each<BusinessRole>(['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME'])('ne supprime jamais un compte existant %s', async (existingRole) => {
    const h = harness(endpoint, { existingRole });
    const response = await h.request({});
    expect(response.status).toBe(409);
    expect(h.state).toMatchObject({ authExists: true, profileExists: true, role: existingRole });
    expect(h.deleteAuth).not.toHaveBeenCalled();
    expect(h.deleteProfile).not.toHaveBeenCalled();
  });
});
