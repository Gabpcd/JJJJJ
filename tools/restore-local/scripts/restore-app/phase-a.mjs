#!/usr/bin/env node
import { phaseFailure } from './failure.mjs';
import { readFileSync, writeFileSync, mkdirSync, existsSync, lstatSync, renameSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { main as bootstrap } from '../restore/bootstrap.mjs';
import { compareInventories } from '../restore/extensions.mjs';
import { requireExistingRefusal } from '../restore/ci-guard.mjs';
import { source, recoverySource, ROOT } from './identity.mjs';
import { preparePlan } from './local-runtime.mjs';
import { runPhaseA } from './phase-a-core.mjs';
import { closedFailure } from './projection.mjs';

const required = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
const PRIVATE_MODE = 0o600;
const PUBLIC_FILES = new Set(['identity.json', 'units.json', 'bootstrap-proof.json', 'phase-a.json',
  'diagnostic.json', 'cleanup.json', 'cleanup-again.json', 'absence.json']);
let stage = 'identity', activePaths;
function checkedDirectory(path) {
  if (!existsSync(path)) mkdirSync(path, { mode: 0o700 });
  required(lstatSync(path).isDirectory() && !lstatSync(path).isSymbolicLink() && realpathSync(path) === path
    && (lstatSync(path).mode & 0o077) === 0, 'PHASE_A_DIRECTORY_REFUSED');
}
function save(path, value) {
  if (existsSync(path)) required(lstatSync(path).isFile() && !lstatSync(path).isSymbolicLink() && lstatSync(path).nlink === 1, 'PHASE_A_FILE_REFUSED');
  const temporary = path + '.writing';
  writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { mode: PRIVATE_MODE, flag: 'wx' });
  renameSync(temporary, path);
}
function publicSave(name, value) {
  required(PUBLIC_FILES.has(name), 'PHASE_A_PUBLIC_PATH_REFUSED');
  save(join(activePaths.proof, name), value);
}
export function parseTap(text, exitCode) {
  const value = key => { const matches = [...text.matchAll(new RegExp('^# ' + key + ' ([0-9]+)$', 'gm'))];
    required(matches.length === 1, 'PHASE_A_UNIT_REPORT'); return Number(matches[0][1]); };
  const counts = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(key => [key, value(key)]));
  required(Number.isSafeInteger(counts.tests) && counts.tests > 0 && counts.tests < 1000 && exitCode === 0
    && counts.pass === counts.tests && ['fail', 'cancelled', 'skipped', 'todo'].every(key => counts[key] === 0), 'PHASE_A_UNIT_FAILURE');
  return { result: 'PURE_NODE_TESTS_PASSED', ...counts, rawLogExported: false };
}
function unitTests(evidence) {
  const tests = evidence.pins.nodeTests;
  required(Array.isArray(tests) && tests.length >= 2 && tests.every(path => evidence.pins.allowedChangedPaths.includes(path)
    || evidence.pins.pinnedFiles.some(file => file.path === path)), 'PHASE_A_TEST_LIST');
  const result = spawnSync(process.execPath, ['--test', '--test-reporter=tap', ...tests], {
    cwd: ROOT, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 120_000,
    env: { PATH: process.env.PATH, HOME: process.env.HOME }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  writeFileSync(join(activePaths.private, 'unit-tests.stdout.private'), result.stdout ?? '', { mode: PRIVATE_MODE, flag: 'wx' });
  writeFileSync(join(activePaths.private, 'unit-tests.stderr.private'), result.stderr ?? '', { mode: PRIVATE_MODE, flag: 'wx' });
  required(!result.error && result.signal === null, 'PHASE_A_UNIT_PROCESS');
  const report = parseTap(result.stdout, result.status); publicSave('units.json', report); return report;
}
export async function main(args, env = process.env) {
  required(args.length === 1 && ['identity', 'units', 'plan', 'bootstrap', 'native', 'diagnose', 'cleanup', 'absence'].includes(args[0]), 'PHASE_A_COMMAND_REFUSED');
  const [command] = args;
  const evidence = ['diagnose', 'cleanup', 'absence'].includes(command) ? recoverySource(env) : source(env);
  checkedDirectory(evidence.privateRoot); checkedDirectory(evidence.proofRoot);
  activePaths = { private: evidence.privateRoot, proof: evidence.proofRoot, stack: join(evidence.privateRoot, 'stack') };
  if (command === 'identity') {
    const report = { result: 'PHASE_A_SOURCE_IDENTITY_PASSED', productSha: evidence.productSha, harnessSha: evidence.harnessSha,
      migrationCount: evidence.migrations.length, qualifiedHarnessSha: evidence.pins.qualifiedHarnessSha,
      phaseBEnabled: false, privateProofOnly: true };
    publicSave('identity.json', report); return report;
  }
  if (command === 'units') { stage = 'units'; return unitTests(evidence); }
  if (command === 'plan') { stage = 'plan'; return preparePlan(activePaths.stack, evidence.run); }
  if (command === 'bootstrap') {
    const passed = [];
    for (const operation of ['preload', 'preflight', 'up', 'inspect']) {
      stage = operation; bootstrap([operation, activePaths.stack]); passed.push(operation);
      publicSave('bootstrap-proof.json', { result: 'NATIVE_BOOTSTRAP_IN_PROGRESS', passed, appOrRestoreProven: false });
    }
    required(requireExistingRefusal(activePaths.stack).result === 'EXISTING_START_REFUSED', 'PHASE_A_REPEATED_START');
    stage = 'extensions';
    const inventory = bootstrap(['extensions', activePaths.stack]);
    const requirements = JSON.parse(readFileSync(new URL('../export/scope.json', import.meta.url))).extensions;
    const comparison = compareInventories(requirements, inventory, evidence.run);
    required(comparison.declarations_compatible === true, 'PHASE_A_EXTENSION_MISMATCH');
    const report = { result: 'NATIVE_BOOTSTRAP_PASSED', passed, repeatedStartRefused: true,
      extensionsExact: true, containers: 10, volumes: 6, networkInternal: true, publishedPorts: 0,
      qualificationDatabase: true, appOrRestoreProven: false };
    publicSave('bootstrap-proof.json', report); return report;
  }
  if (command === 'native') {
    return runPhaseA(evidence, activePaths, value => {
      stage = value.stage; publicSave('phase-a.json', value);
    }, { saveImport: report => save(join(activePaths.private, 'import-qualification.private.json'), report) });
  }
  if (command === 'diagnose') {
    if (!existsSync(join(activePaths.stack, 'manifest.json'))) return { result: 'NO_PLAN' };
    const report = bootstrap(['diagnose', activePaths.stack]);
    publicSave('diagnostic.json', report); return report; // existing closed diagnostics, unchanged
  }
  if (command === 'cleanup') {
    stage = 'cleanup';
    const planned = existsSync(join(activePaths.stack, 'manifest.json'));
    const first = planned ? bootstrap(['down', activePaths.stack]) : bootstrap(['absent', evidence.run]);
    publicSave('cleanup.json', first);
    const second = planned ? bootstrap(['down', activePaths.stack]) : bootstrap(['absent', evidence.run]);
    publicSave('cleanup-again.json', second); return second;
  }
  stage = 'absence';
  const absent = bootstrap(['absent', evidence.run]); publicSave('absence.json', absent); return absent;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { const report = await main(process.argv.slice(2)); process.stdout.write(JSON.stringify({ result: report.result ?? 'PHASE_A_PLAN_CREATED' }) + '\n'); }
  catch (error) {
    const report = closedFailure(error, stage);
    // Never expose Error.message/stack, raw Auth/SQL responses or a bootstrap body.
    if (activePaths) try {
      const file = ['cleanup', 'absence'].includes(stage) ? stage + '.json' : stage === 'units' ? 'units.json' : 'phase-a.json';
      publicSave(file, report);
    } catch { /* stdout remains a constant closed projection even if proof storage fails */ }
    process.stdout.write(JSON.stringify(report) + '\n'); process.exitCode = 1;
  }
}
