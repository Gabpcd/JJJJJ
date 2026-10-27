import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('XCTest and Metro use the same fixed loopback experience URL', () => {
  const runner = readFileSync(new URL('./run-pilot-ci.mjs', import.meta.url), 'utf8');
  const swift = readFileSync(new URL('../ios-ui-tests/NativePilotUITests/NativePilotTests.swift', import.meta.url), 'utf8');
  const runnerValues = [...runner.matchAll(/\bconst expoUrl = ['"]([^'"]+)['"]/g)];
  const swiftValues = [...swift.matchAll(/\blet expoExperienceURL = "([^"]+)"/g)];
  assert.equal(runnerValues.length, 1, 'one runner URL');
  assert.equal(swiftValues.length, 1, 'one XCTest URL');
  assert.equal(runnerValues[0][1], 'exp://127.0.0.1:8090');
  assert.equal(swiftValues[0][1], runnerValues[0][1]);
  assert.doesNotMatch(runner, /\[['"]simctl['"],\s*['"]openurl['"]/, 'iOS opens the local URL inside XCTest, not via an external simctl transaction');
});
