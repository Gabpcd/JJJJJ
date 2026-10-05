import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

export const fixturePackage = 'app.jolene.recette';
export const launcherPackage = 'com.google.android.apps.nexuslauncher';
const launcherComponent = `${launcherPackage}/.NexusLauncherActivity`;
// Start without -W: readiness is established below by ten seconds of observed
// native focus. A synchronous activity wait can outlast the adb command budget
// before the bounded readiness loop gets a chance to observe the launcher.

export function inspectAndroidWindows(dump) {
  const focus = [...dump.matchAll(/^\s*mCurrentFocus=(.+)$/gm)].map((match) => match[1].trim());
  assert.equal(focus.length, 1, 'Expected one emulator display focus state');
  // AOSP AppNotRespondingDialog sets this window title with the process name;
  // it is independent of the translated user-facing "is not responding" text.
  const errors = [...dump.matchAll(/\b(Application Not Responding|Application Error): ([\w.:]+)/g)]
    .map((match) => ({ kind: match[1], pkg: match[2] }));
  const unique = [...new Map(errors.map((error) => [`${error.kind}:${error.pkg}`, error])).values()];
  return { focus: focus[0], errors: unique };
}

function hasComponentFocus(state, component) {
  return state.focus.startsWith('Window{') && state.focus.endsWith(` ${component}}`);
}

export function requireAppWindow(dump) {
  const state = inspectAndroidWindows(dump);
  assert.deepEqual(state.errors, [], 'Android error dialog obstructs the app; never suppress app errors');
  assert(hasComponentFocus(state, `${fixturePackage}/app.jolene.android.MainActivity`), 'Jolene must own native window focus before interaction');
  return state;
}

export async function preflightEmulator({ shell, record, now = Date.now, pause = delay,
  timeoutMs = 60_000, stableMs = 10_000, recoveryGraceMs = 10_000 }) {
  const start = now();
  let recoveredAt = null;
  let recoveryCleared = false;
  let stableSince = null;
  let requestedHome = false;
  try {
    // This entire recovery phase precedes APK installation. It cannot dismiss
    // a Jolene failure or replay a scenario: an existing app aborts preflight.
    // Unlike `pm path` on a missing package, this query succeeds when absent.
    assert.equal((await shell(`pm list packages ${fixturePackage}`)).trim(), '', 'Preflight requires a fresh emulator before Jolene installation');
    await record({ phase: 'before-installation', elapsedMs: now() - start, fixtureInstalled: false });
    while (now() - start < timeoutMs) {
      const windowDump = await shell('dumpsys window');
      const state = inspectAndroidWindows(windowDump);
      await record({ phase: 'observe', elapsedMs: now() - start, ...state, windowDump });
      if (state.errors.length) {
        stableSince = null;
        assert(state.errors.length === 1 && state.errors[0].pkg === launcherPackage
          && state.errors[0].kind === 'Application Not Responding', 'Unexpected Android error dialog; no recovery allowed');
        if (recoveredAt !== null) {
          assert(!recoveryCleared && now() - recoveredAt < recoveryGraceMs, 'Pixel Launcher ANR persisted or recurred after one recovery');
        } else {
          assert.equal((await shell(`pm list packages ${fixturePackage}`)).trim(), '', 'Never recover after Jolene is installed');
          const lastAnr = await shell('dumpsys activity lastanr');
          await record({ phase: 'launcher-anr-before-installation', elapsedMs: now() - start, ...state, lastAnr });
          // Only the observed Pixel Launcher, once. No ANR setting is changed.
          await shell(`am force-stop ${launcherPackage}`);
          recoveredAt = now();
          await shell(`am start -n ${launcherComponent}`);
          requestedHome = true;
          await record({ phase: 'launcher-restarted-once', elapsedMs: now() - start });
        }
      } else {
        if (recoveredAt !== null) recoveryCleared = true;
        const homeFocused = hasComponentFocus(state, launcherComponent)
          || hasComponentFocus(state, `${launcherPackage}/${launcherPackage}.NexusLauncherActivity`);
        if (homeFocused) {
          stableSince ??= now();
          if (now() - stableSince >= stableMs) {
            await record({ phase: 'ready-before-installation', elapsedMs: now() - start,
              stableMs: now() - stableSince, recoveries: recoveredAt === null ? 0 : 1 });
            return;
          }
        } else {
          stableSince = null;
          if (!requestedHome) {
            await shell(`am start -n ${launcherComponent}`);
            requestedHome = true;
          }
        }
      }
      await pause(Math.min(1000, Math.max(0, timeoutMs - (now() - start))));
    }
    throw new Error(`Emulator did not reach stable Launcher focus within ${timeoutMs}ms`);
  } catch (error) {
    await record({ phase: 'failed', elapsedMs: now() - start, message: error.message });
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.equal(process.env.CI, 'true');
  assert.equal(process.env.NATIVE_RECETTE, '1');
  const output = 'test-results/android-native';
  await mkdir(output, { recursive: true });
  const exec = promisify(execFile);
  const entries = [];
  await preflightEmulator({
    shell: async (command) => (await exec('adb', ['shell', command], { timeout: 10_000, maxBuffer: 4 * 1024 * 1024 })).stdout,
    record: async (entry) => {
      entries.push({ at: new Date().toISOString(), ...entry });
      await writeFile(`${output}/emulator-preflight.json`, JSON.stringify(entries, null, 2));
    },
  });
}
