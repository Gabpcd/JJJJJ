import { execFile } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { fixturePackage, requireAppWindow } from './emulator-preflight.mjs';

const temporaryXml = '/data/local/tmp/jolene-recette-accessibility.xml';
const driverPackage = 'com.microsoft.playwright.androiddriver';
const markerNames = ['greetingFull', 'greetingPart', 'welcomePart', 'soignantExplanation', 'etabPrepareMission'];
const markerFields = ['text', 'desc', 'fixtureText', 'fixtureDesc', 'visibleFixtureText', 'visibleFixtureDesc'];
const parser = fileURLToPath(new URL('./project_accessibility.py', import.meta.url));

function execute(file, args, options) {
  const { input, ...settings } = options;
  return new Promise((resolve, reject) => {
    const child = execFile(file, args, settings, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
    child.stdin.on('error', () => {}); // A killed bounded parser may close stdin first.
    child.stdin.end(input);
  });
}

function closedCode(error) {
  if (error?.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') return 'OUTPUT_LIMIT';
  if (error?.code === 'DEADLINE' || error?.killed === true) return 'TIMEOUT';
  if (error?.code === 'INVALID_CONTEXT') return 'INVALID_CONTEXT';
  if (error?.code === 'INVALID_PROJECTION') return 'INVALID_PROJECTION';
  if (error?.code === 'ENOENT') return 'TOOL_MISSING';
  if (error?.code === 'ERR_ASSERTION') return 'APP_STATE_CHANGED';
  return 'COMMAND_FAILED';
}

function fail(code) { throw Object.assign(new Error(code), { code }); }
function keysAre(value, keys) {
  return value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}
function validateProjection(value) {
  if (!keysAre(value, ['schema', 'fixturePackagePresent', 'fixtureVisibleBoundsPresent', 'markers'])
    || value.schema !== 1 || typeof value.fixturePackagePresent !== 'boolean'
    || typeof value.fixtureVisibleBoundsPresent !== 'boolean' || !keysAre(value.markers, markerNames)) fail('INVALID_PROJECTION');
  for (const marker of markerNames) {
    const record = value.markers[marker];
    if (!keysAre(record, markerFields) || markerFields.some(key => typeof record[key] !== 'boolean')) fail('INVALID_PROJECTION');
    for (const field of ['Text', 'Desc']) {
      if (record['fixture' + field] && (!record[field.toLowerCase()] || !value.fixturePackagePresent)) fail('INVALID_PROJECTION');
      if (record['visibleFixture' + field] && (!record['fixture' + field] || !value.fixtureVisibleBoundsPresent)) fail('INVALID_PROJECTION');
    }
  }
  return value;
}

/** Terminal diagnostic only. No app action, selector fallback or scenario retry.
 * Raw XML exists only in the disposable emulator and bounded process memory. */
export async function captureAccessibility(serial, { expectedPid, closeClient, run = execute, now = () => performance.now(), budgetMs = 45000 } = {}) {
  const deadline = now() + budgetMs;
  let phase = 'context', ownedFile = false, projection;
  const result = { schema: 1, status: 'FAILED', phase, code: 'INVALID_CONTEXT',
    clientClosed: false, driverStopped: false, originalProcessPreserved: false, cleanup: 'NOT_CREATED' };
  const budget = (limit) => {
    const remaining = Math.floor(Math.min(limit, deadline - now()));
    if (remaining <= 0) fail('DEADLINE');
    return remaining;
  };
  const adb = (args, limit = 5000, encoding = 'utf8') => run('adb', ['-s', serial, ...args], {
    encoding, timeout: budget(limit), killSignal: 'SIGKILL', maxBuffer: 1024 * 1024,
  });
  const sameApp = async () => {
    const { stdout: pid } = await adb(['shell', 'pidof', fixturePackage]);
    if (pid.trim() !== expectedPid) fail('ERR_ASSERTION');
    const { stdout: windows } = await adb(['shell', 'dumpsys', '-t', '3', 'window']);
    requireAppWindow(windows);
  };
  try {
    if (!Number.isInteger(budgetMs) || budgetMs < 1 || budgetMs > 45000) fail('INVALID_CONTEXT');
    if (typeof serial !== 'string' || !/^[\w.:-]+$/.test(serial) || typeof expectedPid !== 'string'
      || !/^[1-9]\d*$/.test(expectedPid) || typeof closeClient !== 'function') fail('INVALID_CONTEXT');
    phase = 'close-client';
    let timer;
    try {
      await Promise.race([Promise.resolve().then(closeClient), new Promise((_, reject) => {
        timer = setTimeout(() => reject(Object.assign(new Error('DEADLINE'), { code: 'DEADLINE' })), budget(5000));
      })]);
    } finally { clearTimeout(timer); }
    result.clientClosed = true;
    phase = 'before-app-check';
    await sameApp();
    phase = 'stop-driver';
    await adb(['shell', 'am', 'force-stop', driverPackage]);
    result.driverStopped = true;
    phase = 'temporary-file-absence';
    await adb(['shell', 'test', '!', '-e', temporaryXml]);
    // Once absence is proved, cleanup covers partial writes and dump failure too.
    ownedFile = true;
    phase = 'screen-size';
    const { stdout: size } = await adb(['shell', 'wm', 'size']);
    const match = /^Physical size: ([1-9]\d{0,4})x([1-9]\d{0,4})(?:\r?\nOverride size: ([1-9]\d{0,4})x([1-9]\d{0,4}))?\r?\n?$/.exec(size);
    if (!match) fail('INVALID_PROJECTION');
    const width = match[3] ?? match[1], height = match[4] ?? match[2];
    phase = 'dump';
    // Android's own timeout bounds the remote process; host timeout is separate.
    if (deadline - now() < 18000) fail('DEADLINE');
    await adb(['shell', 'timeout', '-s', 'KILL', '15', 'uiautomator', 'dump', temporaryXml], 18000);
    phase = 'read';
    const { stdout: xml } = await adb(['exec-out', 'cat', temporaryXml], 5000, null);
    phase = 'project';
    const { stdout } = await run('python3', [parser, width, height], {
      input: xml, encoding: 'utf8', timeout: budget(3000), killSignal: 'SIGKILL', maxBuffer: 8192,
    });
    try { projection = validateProjection(JSON.parse(stdout)); }
    catch { fail('INVALID_PROJECTION'); }
    phase = 'after-app-check';
    await sameApp();
    result.originalProcessPreserved = true;
    result.status = 'COMPLETE'; result.phase = 'complete'; result.code = 'NONE';
  } catch (error) {
    result.phase = phase; result.code = closedCode(error);
  } finally {
    if (ownedFile) {
      try {
        // Cleanup has its own 5 s reserve after the diagnostic budget expires.
        await run('adb', ['-s', serial, 'shell', 'rm', '-f', temporaryXml], {
          encoding: 'utf8', timeout: 5000, killSignal: 'SIGKILL', maxBuffer: 8192,
        });
        result.cleanup = 'REMOVED';
      } catch {
        result.cleanup = 'FAILED'; result.status = 'FAILED'; result.phase = 'cleanup'; result.code = 'CLEANUP_FAILED';
      }
    }
  }
  if (result.status === 'COMPLETE') result.projection = projection;
  return result;
}
