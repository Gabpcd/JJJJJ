// @vitest-environment node
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const script = path.resolve('scripts/ci/prepare-staging-api-env.mjs');
let directory: string;
let preload: string;
let envFile: string;
let canary: string;

beforeEach(async () => {
  directory = await realpath(await mkdtemp(path.join(tmpdir(), 'jolene-staging-env-unit-')));
  canary = `runtime-canary-${randomBytes(24).toString('hex')}`;
  envFile = path.join(directory, 'github-env');
  preload = path.join(directory, 'fetch-fixture.mjs');
  // Installed before the production script; no call can reach the real fetch.
  // These are newly generated synthetic strings, never credentials from the host.
  await writeFile(preload, `
    import { writeFileSync } from 'node:fs';
    globalThis.fetch = async (url, options) => {
      writeFileSync(process.env.TEST_FETCH_RECEIPT, JSON.stringify({
        called: true,
        stagingOnly: url === 'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/api-keys',
        syntheticAuthorization: options.headers.Authorization === 'Bearer ' + process.env.STAGING_SUPABASE_ACCESS_TOKEN,
      }));
      if (process.env.TEST_MODE === 'network') throw new Error(process.env.TEST_CANARY);
      if (process.env.TEST_MODE === 'malformed') return new Response(process.env.TEST_CANARY + '{', { status: 200 });
      return new Response(JSON.stringify([
        { name: 'anon', api_key: process.env.TEST_CANARY + '-anon' },
        { name: 'service_role', api_key: process.env.TEST_CANARY + '-service' },
      ]), { status: 200 });
    };
  `, { mode: 0o600 });
});
afterEach(async () => { await rm(directory, { recursive: true, force: true }); });

function run(mode: string) {
  return spawnSync(process.execPath, ['--import', pathToFileURL(preload).href, script], {
    cwd: directory,
    encoding: 'utf8', timeout: 10_000,
    // Deliberately do not inherit process.env or any production secret.
    env: {
      STAGING_SUPABASE_PROJECT_REF: 'mejpriaetwgtcstbgfid',
      STAGING_SUPABASE_ACCESS_TOKEN: `${canary}-access`,
      GITHUB_ENV: envFile,
      TEST_CANARY: canary,
      TEST_MODE: mode,
      TEST_FETCH_RECEIPT: path.join(directory, 'fetch-receipt.json'),
    },
  });
}

describe('sorties publiques de la résolution des accès staging', () => {
  it.each(['malformed', 'network', 'filesystem'])('ferme l’erreur %s sans publier son extrait, message ou stack', async mode => {
    if (mode === 'filesystem') {
      // EISDIR would otherwise expose this synthetic path in its exception.
      envFile = path.join(directory, canary);
      await mkdir(envFile);
    }
    const result = run(mode);
    expect(result.error).toBeUndefined();
    expect(result.status).toBe(1);
    expect(result.stdout).toBe('');
    expect(result.stderr.trim()).toBe('STAGING_API_ENV_FAILED');
    expect(result.stdout + result.stderr).not.toContain(canary);
    expect(result.stderr).not.toMatch(/SyntaxError|TypeError|EISDIR|\bat\s|https?:/);
    expect(JSON.parse(await readFile(path.join(directory, 'fetch-receipt.json'), 'utf8'))).toEqual({
      called: true, stagingOnly: true, syntheticAuthorization: true,
    });
  });

  it('conserve le protocole add-mask puis GITHUB_ENV sur le chemin nominal synthétique', async () => {
    const result = run('normal');
    expect(result.error).toBeUndefined();
    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    // add-mask must contain the value: GitHub consumes this workflow command.
    // This test does NOT claim that the raw command stream has no plaintext.
    expect(result.stdout.trim().split('\n')).toEqual([
      `::add-mask::${canary}-anon`,
      `::add-mask::${canary}-service`,
      'Accès staging résolus ; production exclue.',
    ]);
    expect(await readFile(envFile, 'utf8')).toBe([
      'STAGING_SUPABASE_URL=https://mejpriaetwgtcstbgfid.supabase.co',
      `STAGING_SUPABASE_ANON_KEY=${canary}-anon`,
      `STAGING_SUPABASE_SERVICE_ROLE_KEY=${canary}-service`,
      '',
    ].join('\n'));
    expect(result.stdout + result.stderr).not.toContain(`${canary}-access`);
  });
});
