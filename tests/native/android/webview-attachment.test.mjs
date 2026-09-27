import test from 'node:test';
import assert from 'node:assert/strict';
import { attachNativeWebView, inspectWebViewOwner } from './webview-attachment.mjs';

const pkg = 'app.jolene.recette';
const header = 'USER PID PPID VSZ RSS WCHAN ADDR S NAME';
const processes = `${header}\nu0_a209 2433 361 100 10 0 0 S ${pkg}\n`
  + 'u0_a209 2645 2433 100 10 0 0 S crashpad_handler\n'
  + 'u0_a222 12433 361 100 10 0 0 S unrelated.app\n';
const sockets = 'Num RefCount Protocol Flags Type St Inode Path\n'
  + '000 2 0 10000 1 1 900 @webview_devtools_remote_2433\n'
  + '000 2 0 10000 1 1 901 @webview_devtools_remote_12433\n';

test('selects exact application PID, not a matching PPID or substring', () => {
  const result = inspectWebViewOwner(processes, sockets, pkg);
  assert.deepEqual(result.target, { pid: 2433, socketName: 'webview_devtools_remote_2433' });
  assert.equal(result.relatedProcesses.length, 2);
  assert.equal(result.relatedProcesses[1].name, 'crashpad_handler');
});

test('does not infer a target from an unrelated socket, partial name or missing app', () => {
  assert.equal(inspectWebViewOwner(processes, sockets.replace('@webview_devtools_remote_2433', '@other_2433'), pkg).target, null);
  assert.equal(inspectWebViewOwner(processes.replace(pkg, `${pkg}:other`), sockets, pkg).target, null);
  assert.equal(inspectWebViewOwner(header, sockets, pkg).target, null);
});

test('rejects ambiguous main processes and unrecognized ps format', () => {
  assert.throws(() => inspectWebViewOwner(`${processes}u0_a209 9876 361 100 10 0 0 S ${pkg}\n`, sockets, pkg), /Ambiguous/);
  assert.throws(() => inspectWebViewOwner('PID COMMAND\n2433 app.jolene.recette', sockets, pkg), /Unrecognized/);
});

function fixture({ delayed = false, command = pkg, viewPid = 2433, pageFailure = false, changedAfterAttach = false } = {}) {
  let time = 0;
  let connected = false;
  const records = [];
  const selectors = [];
  let pageCalls = 0;
  const page = { fixture: true };
  const view = { pid: () => viewPid, pkg: () => 'crashpad_handler', page: async () => {
    pageCalls++;
    if (pageFailure) throw new Error('CDP connection refused');
    connected = true;
    return page;
  } };
  const device = { webViews: () => delayed && time < 1000 ? [] : [view], webView: async (selector, options) => {
    selectors.push({ selector, options }); return view;
  } };
  const shell = async (cmd) => {
    if (cmd === 'ps -A') return delayed && time < 1000 || connected && changedAfterAttach ? header : processes;
    if (cmd === 'cat /proc/net/unix') return sockets;
    if (cmd === 'cat /proc/2433/cmdline') return `${command}\0`;
    throw new Error(`Unexpected shell command: ${cmd}`);
  };
  return { records, selectors, page, pageCalls: () => pageCalls,
    run: () => attachNativeWebView({ device, shell, pkg, timeoutMs: 2000, pollMs: 500,
      now: () => time, pause: async (ms) => { time += ms; }, record: async (record) => { records.push(record); } }) };
}

test('waits for observable owner and selects its exact socket despite misleading SDK package metadata', async () => {
  const f = fixture({ delayed: true });
  assert.equal(await f.run(), f.page);
  assert.deepEqual(f.selectors, [{ selector: { socketName: 'webview_devtools_remote_2433' }, options: { timeout: 5000 } }]);
  assert.equal(f.records[0].owner, null);
  assert.equal(f.records.at(-1).phase, 'attached');
  assert.equal(f.records.at(-1).elapsedMs, 1000);
  assert.equal(f.pageCalls(), 1);
});

test('refuses wrong proc cmdline and expires without attachment or gesture', async () => {
  const f = fixture({ command: 'other.app' });
  await assert.rejects(f.run(), /No verified/);
  assert.equal(f.selectors.length, 0);
  assert.equal(f.pageCalls(), 0);
  assert.equal(f.records[0].ownerNameVerified, false);
  assert.equal(f.records.at(-1).elapsedMs, 2000);
  assert.equal(f.records.at(-1).during, 'discovery');
});

test('refuses a WebView whose PID differs from the verified socket owner', async () => {
  const f = fixture({ viewPid: 12433 });
  await assert.rejects(f.run(), /verified application PID/);
  assert.equal(f.pageCalls(), 0);
  assert.equal(f.records.at(-1).during, 'socket-selection');
});

test('does not retry a CDP attachment failure or a changed process after attachment', async () => {
  const failure = fixture({ pageFailure: true });
  await assert.rejects(failure.run(), /CDP connection refused/);
  assert.equal(failure.pageCalls(), 1);
  assert.equal(failure.selectors.length, 1);
  assert.equal(failure.records.at(-1).during, 'cdp-attachment');
  const changed = fixture({ changedAfterAttach: true });
  await assert.rejects(changed.run(), /changed during attachment/);
  assert.equal(changed.pageCalls(), 1);
  assert.equal(changed.records.at(-1).phase, 'failed');
});
