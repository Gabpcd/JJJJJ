import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { constants } from 'node:fs';
import { open, unlink } from 'node:fs/promises';
import { resolve } from 'node:path';

// A preceding tiny Actions step stages the temporary secret in RUNNER_TEMP.
// The emulator action and its child processes never inherit the secret itself.
let credential;
try {
  if (!process.env.RUNNER_TEMP) throw new Error('INPUT');
  const path = resolve(process.env.RUNNER_TEMP, 'jolene-native-auth-input.private.json');
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o777) !== 0o600 || stat.uid !== process.getuid()
      || stat.size < 1 || stat.size > 8192) throw new Error('INPUT');
    credential = await file.readFile();
  } finally { await file.close(); }
  await unlink(path);
} catch { process.stderr.write('AUTH_PRIVATE_INPUT_REQUIRED\n'); process.exitCode = 1; }
if (credential?.length) {
  const child = spawn(process.execPath, [fileURLToPath(new URL('./run.mjs', import.meta.url))], {
    env: process.env, stdio: ['pipe', 'inherit', 'inherit'],
  });
  child.once('error', () => { process.stderr.write('AUTH_RUNNER_START_FAILED\n'); process.exitCode = 1; });
  child.stdin.on('error', () => { /* Child already failed closed; no payload logging. */ });
  child.stdin.end(credential, () => credential.fill(0));
  child.once('close', code => { process.exitCode = code === 0 ? 0 : 1; });
}
