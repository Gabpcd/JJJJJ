import { closeSync, constants, fstatSync, lstatSync, openSync, readSync, realpathSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, dirname, resolve } from 'node:path';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_FILE_BYTES = 1_048_576;
const MAX_CAPTURE_BYTES = 262_144;

// Expo SDK 57 PersistentFileLog/UpdatesLogger: exact file only, never the app database.
// Run only after a failed synthetic CI scenario. Reading cannot change its result.
export async function collectExpoUpdatesFailureLog({ env, failed, device, started, directory, run }) {
  if (env?.GITHUB_ACTIONS !== 'true' || env.EXPO_PUBLIC_JOLENE_MODE !== 'demo' || failed !== true
    || !UUID.test(device) || !Number.isFinite(Date.parse(started))) return { expoUpdatesLog: 'not-eligible' };
  let fd;
  try {
    const result = await run('xcrun', ['simctl', 'get_app_container', device, 'host.exp.Exponent', 'data'],
      { timeout: 10_000, allowFailure: true });
    if (result.code !== 0) return { expoUpdatesLog: 'container-unavailable' };
    const container = result.stdout.trim();
    const parent = realpathSync(resolve(homedir(), 'Library/Developer/CoreSimulator/Devices', device,
      'data/Containers/Data/Application'));
    if (dirname(container) !== parent || !UUID.test(basename(container)) || realpathSync(container) !== container
      || !lstatSync(container).isDirectory()) return { expoUpdatesLog: 'container-rejected' };
    const path = resolve(container, 'Library/Application Support/dev.expo.modules.core.logging.expo-updates.txt');
    const stats = lstatSync(path);
    if (!stats.isFile() || stats.isSymbolicLink() || realpathSync(path) !== path
      || stats.size > MAX_FILE_BYTES || stats.mtimeMs < Date.parse(started)) {
      return { expoUpdatesLog: 'file-rejected' };
    }
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const opened = fstatSync(fd);
    if (!opened.isFile() || opened.dev !== stats.dev || opened.ino !== stats.ino || opened.size > MAX_FILE_BYTES) {
      return { expoUpdatesLog: 'file-changed' };
    }
    const start = Math.max(0, opened.size - MAX_CAPTURE_BYTES);
    const buffer = Buffer.alloc(Math.min(opened.size, MAX_CAPTURE_BYTES));
    const bytes = readSync(fd, buffer, 0, buffer.length, start);
    // A truncated first UTF-8/JSON line is discarded; later entries retain their error stack.
    let text = buffer.subarray(0, bytes).toString('utf8');
    if (start > 0) text = text.includes('\n') ? text.slice(text.indexOf('\n') + 1) : '';
    writeFileSync(resolve(directory, 'expo-updates-persistent.log'), text, { flag: 'wx', mode: 0o600 });
    return { expoUpdatesLog: 'captured', bytes: Buffer.byteLength(text), truncated: start > 0 };
  } catch (error) {
    // Do not print paths, token-bearing URLs, or arbitrary error messages into CI output.
    return { expoUpdatesLog: 'unavailable', errorCode: /^[A-Z0-9_]+$/.test(error?.code) ? error.code : 'READ_FAILED' };
  } finally { if (fd !== undefined) closeSync(fd); }
}
