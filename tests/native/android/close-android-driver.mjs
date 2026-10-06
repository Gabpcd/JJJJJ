import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { performance } from 'node:perf_hooks';

const execute = promisify(execFile);
const fixturePackage = 'app.jolene.recette';
const driverPackage = 'com.microsoft.playwright.androiddriver';
const driverSocket = '@playwright_android_driver_socket';
const processMarker = '\nJOLENE_DRIVER_PROCESS_READ_COMPLETE\n';
const socketMarker = '\nJOLENE_DRIVER_SOCKET_READ_COMPLETE\n';
const processCommand = "ps -A -o PID,NAME && printf '\\nJOLENE_DRIVER_PROCESS_READ_COMPLETE\\n'";
const socketCommand = "cat /proc/net/unix && printf '\\nJOLENE_DRIVER_SOCKET_READ_COMPLETE\\n'";

function fail(code) { throw Object.assign(new Error(code), { code }); }
function closedCode(error) {
  if (error?.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') return 'OUTPUT_LIMIT';
  if (error?.code === 'DEADLINE' || error?.killed === true) return 'TIMEOUT';
  if (['INVALID_CONTEXT', 'INVALID_PROJECTION', 'APP_PROCESS_CHANGED',
    'DRIVER_NOT_OWNED', 'DRIVER_PROCESS_REMAINS', 'DRIVER_SOCKET_REMAINS'].includes(error?.code)) return error.code;
  if (error?.code === 'ENOENT') return 'TOOL_MISSING';
  return 'COMMAND_FAILED';
}

function processes(stdout) {
  if (typeof stdout !== 'string' || !stdout.endsWith(processMarker)) fail('INVALID_PROJECTION');
  const [header, ...lines] = stdout.slice(0, -processMarker.length).trim().split(/\r?\n/);
  if (!/^\s*PID\s+NAME\s*$/.test(header)) fail('INVALID_PROJECTION');
  return lines.map(line => {
    const match = /^\s*([1-9]\d*)\s+(\S+)\s*$/.exec(line);
    if (!match) fail('INVALID_PROJECTION');
    return { pid: match[1], name: match[2] };
  });
}
function driverProcess(name) {
  return [driverPackage, driverPackage + '.test'].some(pkg => name === pkg || name.startsWith(pkg + ':'));
}
function sameApp(rows, expectedPid) {
  const app = rows.filter(row => row.name === fixturePackage);
  if (app.length !== 1 || app[0].pid !== expectedPid) fail('APP_PROCESS_CHANGED');
}
function socketAbsent(stdout) {
  if (typeof stdout !== 'string' || !stdout.endsWith(socketMarker)) fail('INVALID_PROJECTION');
  const [header, ...lines] = stdout.slice(0, -socketMarker.length).trim().split(/\r?\n/);
  if (!/^Num\s+RefCount\s+Protocol\s+Flags\s+Type\s+St\s+Inode\s+Path\s*$/.test(header)) fail('INVALID_PROJECTION');
  for (const line of lines) {
    const match = /^\s*[\da-f]+:\s+[\da-f]+\s+[\da-f]+\s+[\da-f]+\s+[\da-f]+\s+[\da-f]+\s+\d+(?:\s+(.*\S))?\s*$/i.exec(line);
    if (!match) fail('INVALID_PROJECTION');
    if (match[1] === driverSocket) return false;
  }
  return true;
}

/** Terminal cleanup only. The driver was installed by this scenario on its
 * dedicated fixture emulator; no UI action or assertion is repeated here. */
export async function closeAndroidDriver(serial, { expectedPid, driverAttempted, closeClient,
  run = execute, now = () => performance.now(), budgetMs = 30000,
  pause = ms => new Promise(resolve => setTimeout(resolve, ms)) } = {}) {
  const result = { schema: 1, status: 'FAILED', phase: 'context', code: 'INVALID_CONTEXT',
    clientClosed: false, driverStopRequested: false, driverProcessesAbsent: false,
    driverSocketAbsent: false, originalProcessPreserved: false };
  const deadline = now() + budgetMs;
  let phase = 'context', firstFailure;
  const budget = limit => {
    const remaining = Math.floor(Math.min(limit, deadline - now()));
    if (remaining <= 0) fail('DEADLINE');
    return remaining;
  };
  const adb = args => run('adb', ['-s', serial, ...args], {
    encoding: 'utf8', timeout: budget(5000), killSignal: 'SIGKILL', maxBuffer: 1024 * 1024,
  });
  const remember = error => { firstFailure ??= { phase, code: closedCode(error) }; };
  try {
    if (typeof serial !== 'string' || !/^[\w.:-]+$/.test(serial)
      || typeof expectedPid !== 'string' || !/^[1-9]\d*$/.test(expectedPid)
      || typeof driverAttempted !== 'boolean' || typeof closeClient !== 'function' || typeof pause !== 'function'
      || !Number.isInteger(budgetMs) || budgetMs < 1 || budgetMs > 30000) fail('INVALID_CONTEXT');
    phase = 'close-client';
    let timer;
    try {
      await Promise.race([Promise.resolve().then(closeClient), new Promise((_, reject) => {
        timer = setTimeout(() => reject(Object.assign(new Error('DEADLINE'), { code: 'DEADLINE' })), budget(5000));
      })]);
      result.clientClosed = true;
    } catch (error) { remember(error); }
    finally { clearTimeout(timer); }

    // Even a failed client close must not prevent bounded cleanup of the
    // owned driver. Its failure remains the final result, however.
    phase = 'before-app-check';
    const before = processes((await adb(['shell', processCommand])).stdout);
    sameApp(before, expectedPid);
    if (!driverAttempted && before.some(row => driverProcess(row.name))) fail('DRIVER_NOT_OWNED');
    if (driverAttempted) {
      phase = 'driver-package-check';
      const installed = (await adb(['shell', 'pm', 'list', 'packages', driverPackage])).stdout;
      if (typeof installed !== 'string') fail('INVALID_PROJECTION');
      const packages = installed.trim() ? installed.trim().split(/\r?\n/) : [];
      if (packages.some(line => !/^package:[\w.]+$/.test(line))) fail('INVALID_PROJECTION');
      if (packages.includes('package:' + driverPackage)) {
        phase = 'stop-driver';
        await adb(['shell', 'am', 'force-stop', driverPackage]);
        result.driverStopRequested = true;
      } else if (before.some(row => driverProcess(row.name))) fail('DRIVER_NOT_OWNED');
    }
    // am force-stop peut revenir avant la disparition de la socket Unix.
    // Attendre sa fermeture effective, sans rejouer l'UI ni redémarrer l'app.
    // Le nombre de sondes ET le budget total restent bornés ; aucune erreur
    // ADB, projection invalide ou substitution du processus app n'est ignorée.
    for (let attempt = 0; attempt < 20; attempt++) {
      phase = 'driver-socket-absence';
      result.driverSocketAbsent = socketAbsent((await adb(['shell', socketCommand])).stdout);
      phase = 'driver-process-absence';
      const after = processes((await adb(['shell', processCommand])).stdout);
      result.originalProcessPreserved = false;
      sameApp(after, expectedPid);
      result.originalProcessPreserved = true;
      result.driverProcessesAbsent = !after.some(row => driverProcess(row.name));
      if (result.driverSocketAbsent && result.driverProcessesAbsent) break;
      if (attempt === 19) {
        phase = result.driverSocketAbsent ? 'driver-process-absence' : 'driver-socket-absence';
        fail(result.driverSocketAbsent ? 'DRIVER_PROCESS_REMAINS' : 'DRIVER_SOCKET_REMAINS');
      }
      await pause(budget(100));
    }
    // A completion that lost a delayed timer race must still respect budget.
    budget(1);
    if (!firstFailure) {
      result.status = 'COMPLETE'; result.phase = 'complete'; result.code = 'NONE';
    }
  } catch (error) { remember(error); }
  if (firstFailure) Object.assign(result, firstFailure);
  return result;
}

export async function finalizeAndroidDriver(serial, options, record) {
  const result = await closeAndroidDriver(serial, options);
  try { await record(result); }
  catch { throw new Error('ANDROID_DRIVER_CLEANUP_RECEIPT_FAILED'); }
  if (result.status !== 'COMPLETE') throw new Error('ANDROID_DRIVER_CLEANUP_FAILED');
}
