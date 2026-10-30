import { writeFile, unlink, lstat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { parseCohort } from './policy.mjs';

// Only this tiny step receives the GitHub secret, after dependencies are ready.
// No child, network client or build is started here; exceptions never print input.
try {
  if (!process.env.RUNNER_TEMP) throw new Error('INPUT');
  const path = resolve(process.env.RUNNER_TEMP, 'jolene-native-auth-input.private.json');
  if (process.argv[2] === 'cleanup') {
    try { const stat = await lstat(path); if (!stat.isSymbolicLink() && stat.isFile()) await unlink(path); }
    catch (error) { if (error?.code !== 'ENOENT') throw new Error('CLEANUP'); }
  } else {
    const input = process.env.JOLENE_NATIVE_AUTH_COHORT;
    delete process.env.JOLENE_NATIVE_AUTH_COHORT;
    const cohort = parseCohort(input ?? '');
    await writeFile(path, JSON.stringify(cohort), { mode: 0o600, flag: 'wx' });
  }
} catch { process.stderr.write('AUTH_PRIVATE_INPUT_STEP_FAILED\n'); process.exitCode = 1; }
