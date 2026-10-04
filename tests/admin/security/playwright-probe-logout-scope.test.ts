// @vitest-environment node
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const script = path.resolve('scripts/ci/resolve-playwright-admin-password.mjs');
let directory: string;
let preload: string;
let primary: string;
let fallback: string;
let token: string;
let key: string;

beforeEach(async () => {
  directory = await realpath(await mkdtemp(path.join(tmpdir(), 'jolene-probe-logout-unit-')));
  [primary, fallback, token, key] = Array.from({ length: 4 }, () => randomBytes(24).toString('hex'));
  preload = path.join(directory, 'fetch-fixture.mjs');
  // No real transport is retained. Only request shape and synthetic equality
  // booleans are persisted; this is not a provider session-revocation proof.
  await writeFile(preload, `
    import { writeFileSync } from 'node:fs';
    const calls = [];
    globalThis.fetch = async (url, options = {}) => {
      const parsed = new URL(url);
      const login = parsed.pathname === '/auth/v1/token';
      const logout = parsed.pathname === '/auth/v1/logout';
      const body = login ? JSON.parse(options.body) : null;
      const candidate = body?.password === process.env.TEST_PRIMARY ? 'primary'
        : body?.password === process.env.TEST_FALLBACK ? 'fallback' : null;
      calls.push({
        kind: login ? 'login' : logout ? 'logout' : 'unexpected',
        fixtureOrigin: parsed.origin === 'https://auth-fixture.invalid',
        method: options.method,
        candidate,
        passwordGrant: login && parsed.searchParams.get('grant_type') === 'password',
        localScope: logout && parsed.searchParams.get('scope') === 'local' && [...parsed.searchParams].length === 1,
        probeToken: logout && options.headers.Authorization === 'Bearer ' + process.env.TEST_TOKEN,
        expectedKey: options.headers.apikey === process.env.TEST_KEY,
      });
      writeFileSync(process.env.TEST_RECEIPT, JSON.stringify(calls));
      if (parsed.origin !== 'https://auth-fixture.invalid') throw new Error('UNEXPECTED_ORIGIN');
      if (login) {
        const accepted = process.env.TEST_MODE !== 'denied'
          && !(process.env.TEST_MODE === 'fallback' && candidate === 'primary');
        return new Response(JSON.stringify(accepted ? { access_token: process.env.TEST_TOKEN } : { error: 'fixture_denied' }), { status: accepted ? 200 : 401 });
      }
      if (logout) {
        if (process.env.TEST_MODE === 'logout-error') throw new Error(process.env.TEST_TOKEN);
        return new Response(null, { status: 204 });
      }
      throw new Error('UNEXPECTED_ENDPOINT');
    };
  `, { mode: 0o600 });
});
afterEach(async () => { await rm(directory, { recursive: true, force: true }); });

async function run(mode: string) {
  const result = spawnSync(process.execPath, ['--import', pathToFileURL(preload).href, script], {
    cwd: directory, encoding: 'utf8', timeout: 10_000,
    // Do not inherit any host credential, URL or Node preload.
    env: {
      E2E_SUPABASE_URL: 'https://auth-fixture.invalid', E2E_PUBLISHABLE_KEY: key,
      GITHUB_ENV: path.join(directory, 'github-env'),
      PLAYWRIGHT_ADMIN_EMAIL_PRIMARY: 'fixture-admin@example.invalid',
      PLAYWRIGHT_ADMIN_PASSWORD_PRIMARY: primary,
      PLAYWRIGHT_ADMIN_PASSWORD_FALLBACK: fallback,
      TEST_PRIMARY: primary, TEST_FALLBACK: fallback, TEST_TOKEN: token, TEST_KEY: key,
      TEST_MODE: mode, TEST_RECEIPT: path.join(directory, 'requests.json'),
    },
  });
  expect(result.error).toBeUndefined();
  expect(result.signal).toBeNull();
  expect(result.stdout + result.stderr).not.toContain(token);
  expect(result.stdout + result.stderr).not.toContain(key);
  return { ...result, calls: JSON.parse(await readFile(path.join(directory, 'requests.json'), 'utf8')) };
}

describe('déconnexion des sondes CI limitée à la session de la sonde', () => {
  it.each(['primary', 'fallback'])('ferme une seule session locale avec le token sélectionné (%s)', async mode => {
    const result = await run(mode);
    expect(result.status).toBe(0);
    const logins = result.calls.filter((call: any) => call.kind === 'login');
    expect(logins.map((call: any) => call.candidate)).toEqual(mode === 'fallback' ? ['primary', 'fallback'] : ['primary']);
    expect(logins.every((call: any) => call.fixtureOrigin && call.passwordGrant && call.expectedKey && call.method === 'POST')).toBe(true);
    expect(result.calls.filter((call: any) => call.kind !== 'login')).toEqual([{
      kind: 'logout', fixtureOrigin: true, method: 'POST', candidate: null,
      passwordGrant: false, localScope: true, probeToken: true, expectedKey: true,
    }]);
    const selected = mode === 'fallback' ? fallback : primary;
    expect(result.stdout).toContain(`::add-mask::${selected}`);
    expect(result.stdout).toContain(`Compte admin E2E vérifié via ${mode === 'fallback' ? 'ADMIN_TEST' : 'PLAYWRIGHT_ADMIN'}`);
    const environment = await readFile(path.join(directory, 'github-env'), 'utf8');
    expect(environment).toContain(`PLAYWRIGHT_ADMIN_PASSWORD<<JOLENE_ADMIN_EOF\n${selected}\nJOLENE_ADMIN_EOF\n`);
    expect(environment).not.toContain(token);
  });

  it('ne déconnecte aucun utilisateur si les deux candidats sont refusés', async () => {
    const result = await run('denied');
    expect(result.status).toBe(1);
    expect(result.calls.map((call: any) => call.kind)).toEqual(['login', 'login']);
    await expect(readFile(path.join(directory, 'github-env'))).rejects.toMatchObject({ code: 'ENOENT' });
  });

  it('ne retente pas une déconnexion globale si la fermeture locale échoue', async () => {
    const result = await run('logout-error');
    // Preserve the resolver's existing best-effort cleanup behavior.
    expect(result.status).toBe(0);
    expect(result.calls.map((call: any) => call.kind)).toEqual(['login', 'logout']);
    expect(result.calls[1]).toMatchObject({ localScope: true, probeToken: true });
    expect(result.stderr).toBe('');
  });
});
