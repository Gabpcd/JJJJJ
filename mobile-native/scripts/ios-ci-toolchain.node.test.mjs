import { test } from 'node:test';
import assert from 'node:assert/strict';
import { selectIosCiSimulator, verifyIosCiXcode } from './ios-ci-toolchain.mjs';

const runtime = version => ({ version, buildversion: version === '26.4.1' ? '23E254a' : '23F77',
  identifier: version === '26.4.1' ? 'com.apple.CoreSimulator.SimRuntime.iOS-26-4' : 'com.apple.CoreSimulator.SimRuntime.iOS-26-5', isAvailable: true });
const phone = { name: 'iPhone 17', udid: 'A0000000-0000-0000-0000-000000000001', isAvailable: true };
const tablet = { name: 'iPad (A16)', udid: 'A0000000-0000-0000-0000-000000000002', isAvailable: true };
const inventory = { [runtime('26.4.1').identifier]: [phone, tablet], [runtime('26.5').identifier]: [phone] };

test('a hosted image update cannot silently move either device family to its newest runtime', () => {
  for (const family of ['iphone', 'ipad']) {
    const selected = selectIosCiSimulator([runtime('26.5'), runtime('26.4.1')], inventory, family);
    assert.equal(selected.runtime.version, '26.4.1');
    assert.equal(selected.device, family === 'iphone' ? phone : tablet);
  }
});

test('missing, unavailable or ambiguous pinned runtime fails instead of selecting another version', () => {
  for (const runtimes of [[runtime('26.5')], [{ ...runtime('26.4.1'), isAvailable: false }], [runtime('26.4.1'), runtime('26.4.1')]]) {
    assert.throws(() => selectIosCiSimulator(runtimes, inventory, 'iphone'), /absent ou ambigu/);
  }
});

test('a missing family, invalid device or unknown family cannot select an unintended simulator', () => {
  assert.throws(() => selectIosCiSimulator([runtime('26.4.1')], { [runtime('26.4.1').identifier]: [phone] }, 'ipad'));
  assert.throws(() => selectIosCiSimulator([runtime('26.4.1')], { [runtime('26.4.1').identifier]: [{ ...phone, udid: 'physical-device' }] }, 'iphone'));
  assert.throws(() => selectIosCiSimulator([runtime('26.4.1')], inventory, 'watch'));
});

test('Xcode provenance is exact and rejects the moving hosted default', () => {
  assert.equal(verifyIosCiXcode('Xcode 26.4.1\nBuild version 17E202\n').runtime, '26.4.1');
  for (const version of ['Xcode 26.6\nBuild version 17F113', 'Xcode 26.4.1\nBuild version 17E999', '']) {
    assert.throws(() => verifyIosCiXcode(version), /sans repli/);
  }
});
