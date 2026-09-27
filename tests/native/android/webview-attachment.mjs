import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export function inspectWebViewOwner(processDump, socketDump, pkg) {
  const lines = processDump.trim().split(/\r?\n/).map((line) => line.trim().split(/\s+/));
  const [header, ...rows] = lines;
  const pidColumn = header.indexOf('PID');
  const parentColumn = header.indexOf('PPID');
  const nameColumn = header.indexOf('NAME');
  assert(pidColumn >= 0 && parentColumn >= 0 && nameColumn >= 0, 'Unrecognized Android ps columns');
  const processes = rows.filter((row) => /^\d+$/.test(row[pidColumn] ?? '')).map((row) => ({
    pid: Number(row[pidColumn]), parentPid: Number(row[parentColumn]), name: row.slice(nameColumn).join(' '),
  }));
  const owners = processes.filter((process) => process.name === pkg);
  assert(owners.length <= 1, 'Ambiguous main application process');
  const sockets = [...new Set(socketDump.split(/\r?\n/).map((line) => line.trim().split(/\s+/).at(-1))
    .filter((name) => /^@webview_devtools_remote_\d+$/.test(name ?? '')).map((name) => name.slice(1)))];
  const owner = owners[0];
  const socketName = owner ? sockets.find((name) => name === `webview_devtools_remote_${owner.pid}`) : undefined;
  return { owner: owner ?? null, sockets,
    // Include potential PID/PPID collisions in the metadata, never command arguments.
    relatedProcesses: owner ? processes.filter((process) => process.pid === owner.pid || process.parentPid === owner.pid) : [],
    target: owner && socketName ? { pid: owner.pid, socketName } : null };
}

/** Only startup discovery is polled; a failed CDP attachment or test is never retried. */
export async function attachNativeWebView({ device, shell, record, pkg, timeoutMs = 45_000,
  pollMs = 500, now = Date.now, pause = delay }) {
  const start = now();
  let lastObservation;
  let phase = 'discovery';
  try {
    while (now() - start < timeoutMs) {
      const processDump = await shell('ps -A');
      const socketDump = await shell('cat /proc/net/unix');
      const observation = inspectWebViewOwner(processDump, socketDump, pkg);
      observation.discoveredByPlaywright = device.webViews().map((view) => ({ pid: view.pid(), pkg: view.pkg() }));
      if (observation.target) {
        // A PID can disappear/restart between snapshots. Confirm its main
        // process name directly before selecting the observed exact socket.
        const command = await shell(`cat /proc/${observation.target.pid}/cmdline`);
        observation.ownerNameVerified = command.split('\0')[0] === pkg;
      }
      const serialized = JSON.stringify(observation);
      if (serialized !== lastObservation) {
        await record({ phase, elapsedMs: now() - start, ...observation });
        lastObservation = serialized;
      }
      if (observation.target && observation.ownerNameVerified) {
        phase = 'socket-selection';
        const { pid, socketName } = observation.target;
        await record({ phase, elapsedMs: now() - start, pid, socketName });
        // Playwright's package lookup uses a substring grep over ps. Selecting
        // the independently verified socket avoids relying on that heuristic.
        // We do not assert it caused a past failure without captured evidence.
        const view = await device.webView({ socketName }, { timeout: 5_000 });
        assert.equal(view.pid(), pid, 'Selected WebView must have the verified application PID');
        phase = 'cdp-attachment';
        await record({ phase, elapsedMs: now() - start, pid, reportedPackage: view.pkg() });
        const page = await view.page();
        // Reject a PID replacement during connection, before any UI gesture.
        const current = inspectWebViewOwner(await shell('ps -A'), await shell('cat /proc/net/unix'), pkg);
        assert.deepEqual(current.target, observation.target, 'Application WebView changed during attachment');
        assert.equal((await shell(`cat /proc/${pid}/cmdline`)).split('\0')[0], pkg);
        await record({ phase: 'attached', elapsedMs: now() - start, pid, socketName });
        return page;
      }
      await pause(Math.min(pollMs, Math.max(0, timeoutMs - (now() - start))));
    }
    throw new Error(`No verified ${pkg} WebView socket within ${timeoutMs}ms`);
  } catch (error) {
    await record({ phase: 'failed', during: phase, elapsedMs: now() - start, message: error.message });
    throw error;
  }
}
