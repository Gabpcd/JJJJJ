import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('Expo receives the fixed loopback experience at its single initial launch', () => {
  const runner = readFileSync(new URL('./run-pilot-ci.mjs', import.meta.url), 'utf8');
  const swift = readFileSync(new URL('../ios-ui-tests/NativePilotUITests/NativePilotTests.swift', import.meta.url), 'utf8');
  const runnerValues = [...runner.matchAll(/\bconst expoUrl = ['"]([^'"]+)['"]/g)];
  assert.equal(runnerValues.length, 1, 'one runner URL');
  assert.equal(runnerValues[0][1], 'exp://127.0.0.1:8090');
  assert.match(runner, /\['simctl', 'launch', device, appId, '--initialUrl', expoUrl\]/, 'the prepared URL is passed to the existing launch');
  assert.doesNotMatch(runner, /\[['"]simctl['"],\s*['"]openurl['"]/, 'no separate external URL-opening transaction');
  assert.doesNotMatch(swift, /\bapp\.open\(/, 'XCTest must not reopen the experience while attaching accessibility');
});
