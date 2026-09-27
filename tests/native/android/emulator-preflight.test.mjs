import test from 'node:test';
import assert from 'node:assert/strict';
import { fixturePackage, launcherPackage, inspectAndroidWindows, preflightEmulator,
  requireAppWindow } from './emulator-preflight.mjs';

const homeComponent = `${launcherPackage}/${launcherPackage}.NexusLauncherActivity`;
const appComponent = `${fixturePackage}/app.jolene.android.MainActivity`;
const windowDump = (title) => `WINDOW MANAGER WINDOWS\n  mCurrentFocus=Window{abc u0 ${title}}\n`;
const home = windowDump(homeComponent);
const noFocus = 'WINDOW MANAGER WINDOWS\n  mCurrentFocus=null\n';
const anr = (pkg = launcherPackage) => windowDump(`Application Not Responding: ${pkg}`);
const stopLauncher = `am force-stop ${launcherPackage}`;
const startLauncher = `am start -W -n ${launcherPackage}/.NexusLauncherActivity`;

function fixture({ windows = () => home, packages = () => '', failCommand } = {}) {
  let time = 0;
  let packageReads = 0;
  const commands = [];
  const records = [];
  const shell = async (command) => {
    commands.push(command);
    if (command === failCommand) throw new Error('adb unavailable');
    if (command === `pm list packages ${fixturePackage}`) return packages(++packageReads);
    if (command === 'dumpsys window') return windows(time);
    if (command === 'dumpsys activity lastanr') return 'ANR before fixture installation';
    if (command === startLauncher || command === stopLauncher) return '';
    throw new Error(`Unexpected command: ${command}`);
  };
  return { commands, records, run: (options = {}) => preflightEmulator({ shell,
    record: async (entry) => { records.push(entry); }, now: () => time,
    pause: async (ms) => { time += ms; }, ...options }) };
}

test('identifies exact ANR process names and deduplicates repeated window references', () => {
  const dump = `${anr()}  Window #0 Window{abc u0 Application Not Responding: ${launcherPackage}}\n`;
  assert.deepEqual(inspectAndroidWindows(dump).errors,
    [{ kind: 'Application Not Responding', pkg: launcherPackage }]);
  assert.equal(inspectAndroidWindows(anr(`${launcherPackage}:remote`)).errors[0].pkg, `${launcherPackage}:remote`);
  assert.deepEqual(inspectAndroidWindows(home).errors, []);
  assert.throws(() => inspectAndroidWindows('unrecognized output'), /one emulator display/);
  assert.throws(() => inspectAndroidWindows(`${home}${home}`), /one emulator display/);
});

test('requires the exact app window with no Android error before the first gesture', () => {
  assert.equal(requireAppWindow(windowDump(appComponent)).errors.length, 0);
  for (const dump of [home, noFocus, windowDump(`${appComponent}Other`),
    windowDump(`other.${appComponent}`), `${windowDump(appComponent)}${anr().split('\n')[1].replace('mCurrentFocus=', 'Window #0 ')}`]) {
    assert.throws(() => requireAppWindow(dump));
  }
  assert.throws(() => requireAppWindow(anr(fixturePackage)), /never suppress app errors/);
});

test('waits for ten continuous seconds of launcher focus without any recovery', async () => {
  const f = fixture();
  await f.run();
  assert.deepEqual(f.records.at(-1), { phase: 'ready-before-installation', elapsedMs: 10_000,
    stableMs: 10_000, recoveries: 0 });
  assert.equal(f.commands.filter((cmd) => cmd.startsWith('am ')).length, 0);
});

test('restarts the stability interval when native focus is lost', async () => {
  const f = fixture({ windows: (time) => time === 5000 ? noFocus : home });
  await f.run();
  assert.equal(f.records.at(-1).elapsedMs, 16_000);
  assert.equal(f.commands.filter((cmd) => cmd === startLauncher).length, 1);
  assert.equal(f.commands.includes(stopLauncher), false);
});

test('refuses an already installed fixture before inspecting or changing the emulator', async () => {
  const f = fixture({ packages: () => `package:${fixturePackage}\n` });
  await assert.rejects(f.run(), /fresh emulator before Jolene installation/);
  assert.deepEqual(f.commands, [`pm list packages ${fixturePackage}`]);
  assert.equal(f.records.at(-1).phase, 'failed');
});

test('archives and recovers only the observed launcher ANR once before installation', async () => {
  const f = fixture({ windows: (time) => time < 2000 ? anr() : home });
  await f.run();
  assert.deepEqual(f.commands.slice(0, 6), [`pm list packages ${fixturePackage}`, 'dumpsys window',
    `pm list packages ${fixturePackage}`, 'dumpsys activity lastanr', stopLauncher, startLauncher]);
  assert.equal(f.commands.filter((cmd) => cmd === stopLauncher).length, 1);
  assert.equal(f.commands.filter((cmd) => cmd === startLauncher).length, 1);
  assert.equal(f.records.find((entry) => entry.phase === 'launcher-anr-before-installation').lastAnr,
    'ANR before fixture installation');
  assert.deepEqual(f.records.at(-1), { phase: 'ready-before-installation', elapsedMs: 12_000,
    stableMs: 10_000, recoveries: 1 });
});

test('never recovers an app ANR, another process, launcher subprocess or crash', async () => {
  for (const dump of [anr(fixturePackage), anr('com.android.systemui'), anr(`${launcherPackage}:remote`),
    windowDump(`Application Error: ${launcherPackage}`), `${anr()}Window #0 Application Error: other.app`]) {
    const f = fixture({ windows: () => dump });
    await assert.rejects(f.run(), /Unexpected Android error/);
    assert.equal(f.commands.some((cmd) => cmd.startsWith('am ')), false);
  }
});

test('rechecks fixture absence immediately before launcher recovery', async () => {
  const f = fixture({ packages: (read) => read === 1 ? '' : `package:${fixturePackage}`,
    windows: () => anr() });
  await assert.rejects(f.run(), /Never recover after Jolene is installed/);
  assert.equal(f.commands.includes(stopLauncher), false);
});

test('fails a persistent launcher ANR after the bounded grace without a second recovery', async () => {
  const f = fixture({ windows: () => anr() });
  await assert.rejects(f.run(), /persisted or recurred/);
  assert.equal(f.records.at(-1).elapsedMs, 10_000);
  assert.equal(f.commands.filter((cmd) => cmd === stopLauncher).length, 1);
});

test('fails any recurring launcher ANR after it cleared, even if home never gained focus', async () => {
  for (const cleared of [home, noFocus]) {
    const f = fixture({ windows: (time) => time === 1000 ? cleared : anr() });
    await assert.rejects(f.run(), /persisted or recurred/);
    assert.equal(f.records.at(-1).elapsedMs, 2000);
    assert.equal(f.commands.filter((cmd) => cmd === stopLauncher).length, 1);
  }
});

test('times out without native focus and requests home at most once', async () => {
  const f = fixture({ windows: () => noFocus });
  await assert.rejects(f.run(), /stable Launcher focus within 60000ms/);
  assert.equal(f.records.at(-1).elapsedMs, 60_000);
  assert.equal(f.commands.filter((cmd) => cmd === startLauncher).length, 1);
  assert.equal(f.commands.includes(stopLauncher), false);
});

test('propagates Android diagnostic failures instead of retrying or suppressing them', async () => {
  const f = fixture({ failCommand: 'dumpsys window' });
  await assert.rejects(f.run(), /adb unavailable/);
  assert.equal(f.commands.filter((cmd) => cmd === 'dumpsys window').length, 1);
  assert.equal(f.records.at(-1).phase, 'failed');
});
