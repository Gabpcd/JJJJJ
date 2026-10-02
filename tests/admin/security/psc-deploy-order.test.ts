// @vitest-environment node
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';

// Exécute la boucle réelle avec un transport local factice. Aucun CLI Supabase,
// credential ou réseau : seuls des répertoires synthétiques temporaires existent.
function deploiement(callbackEchoue: boolean, staging = false) {
  const source = readFileSync(staging
    ? '.github/workflows/deploy-supabase-staging.yml'
    : '.github/workflows/deploy-supabase.yml', 'utf8');
  const debut = staging
    ? source.indexOf('          for dir in */; do', source.indexOf('      - name: Deploy every function from supabase/functions'))
    : source.indexOf('          failed_fns=""');
  const fin = source.indexOf('\n        env:', debut);
  expect(debut).toBeGreaterThan(0);
  expect(fin).toBeGreaterThan(debut);
  const boucle = source.slice(debut, fin).replace(/^          /gm, '');
  const dossier = mkdtempSync(join(tmpdir(), 'jolene-psc-deploy-order-'));
  try {
    for (const name of ['aaa-other', 'psc-authorize', 'psc-callback', 'zzz-other']) {
      mkdirSync(join(dossier, name));
      writeFileSync(join(dossier, name, 'index.ts'), '// fixture');
    }
    const programme = `set -${staging ? 'e' : ''}uo pipefail
      deploy_with_retry() {
        printf 'APPEL:%s\\n' "$1"
        if [ "$1" = "psc-callback" ] && [ "$CALLBACK_ECHOUE" = "1" ]; then return 1; fi
        return 0
      }
      supabase() {
        if [ "$1" != "functions" ] || [ "$2" != "deploy" ]; then return 42; fi
        deploy_with_retry "$3"
      }
      ${boucle}`;
    const result = spawnSync('/bin/bash', ['-c', programme], {
      cwd: dossier, encoding: 'utf8', env: { CALLBACK_ECHOUE: callbackEchoue ? '1' : '0', SUPABASE_PROJECT_REF: 'fixture-locale-sans-droit' },
    });
    if (result.error) throw result.error;
    return { status: result.status, appels: [...result.stdout.matchAll(/^APPEL:(.+)$/gm)].map(m => m[1]) };
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
}

it('publie le callback compatible avant authorize, une seule fois chacun', () => {
  expect(deploiement(false)).toEqual({
    status: 0, appels: ['aaa-other', 'psc-callback', 'psc-authorize', 'zzz-other'],
  });
});

it('un échec callback interdit authorize, conserve les autres déploiements et rend le job rouge', () => {
  expect(deploiement(true)).toEqual({
    status: 1, appels: ['aaa-other', 'psc-callback', 'zzz-other'],
  });
});


it('staging publie aussi le callback avant authorize, sans deuxième callback', () => {
  expect(deploiement(false, true)).toEqual({
    status: 0, appels: ['aaa-other', 'psc-callback', 'psc-authorize', 'zzz-other'],
  });
});

it('staging arrête la boucle si callback échoue, sans jamais publier authorize', () => {
  expect(deploiement(true, true)).toEqual({
    status: 1, appels: ['aaa-other', 'psc-callback'],
  });
});
