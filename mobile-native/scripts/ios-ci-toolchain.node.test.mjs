import { test } from 'node:test';
import assert from 'node:assert/strict';
import { selectIosCiSimulator, verifyIosCiXcode } from './ios-ci-toolchain.mjs';

const runtime = version => ({ version, buildversion: version === '26.2' ? '23C54' : '23F77',
  identifier: version === '26.2' ? 'com.apple.CoreSimulator.SimRuntime.iOS-26-2' : 'com.apple.CoreSimulator.SimRuntime.iOS-26-5', isAvailable: true });
const phone = { name: 'iPhone 17', udid: 'A0000000-0000-0000-0000-000000000001', isAvailable: true };
const tablet = { name: 'iPad (A16)', udid: 'A0000000-0000-0000-0000-000000000002', isAvailable: true };
const inventory = { [runtime('26.2').identifier]: [phone, tablet], [runtime('26.5').identifier]: [phone] };

test('a hosted image update cannot silently move either device family to its newest runtime', () => {
  for (const family of ['iphone', 'ipad']) {
    const selected = selectIosCiSimulator([runtime('26.5'), runtime('26.2')], inventory, family);
    assert.equal(selected.runtime.version, '26.2');
    assert.equal(selected.device, family === 'iphone' ? phone : tablet);
  }
});

test('missing, unavailable or ambiguous pinned runtime fails instead of selecting another version', () => {
  for (const runtimes of [[runtime('26.5')], [{ ...runtime('26.2'), isAvailable: false }], [runtime('26.2'), runtime('26.2')]]) {
    assert.throws(() => selectIosCiSimulator(runtimes, inventory, 'iphone'), /absent ou ambigu/);
  }
});

test('a missing family, invalid device or unknown family cannot select an unintended simulator', () => {
  assert.throws(() => selectIosCiSimulator([runtime('26.2')], { [runtime('26.2').identifier]: [phone] }, 'ipad'));
  assert.throws(() => selectIosCiSimulator([runtime('26.2')], { [runtime('26.2').identifier]: [{ ...phone, udid: 'physical-device' }] }, 'iphone'));
  assert.throws(() => selectIosCiSimulator([runtime('26.2')], inventory, 'watch'));
});

test('Xcode provenance is exact and rejects the moving hosted default', () => {
  assert.equal(verifyIosCiXcode('Xcode 26.4.1\nBuild version 17E202\n').runtime, '26.2');
  for (const version of ['Xcode 26.6\nBuild version 17F113', 'Xcode 26.2\nBuild version 17C52', 'Xcode 26.4.1\nBuild version 17E999', '']) {
    assert.throws(() => verifyIosCiXcode(version), /sans repli/);
  }
});


test('device selection is the fixed model, never the first sorted model or an ambiguous duplicate', () => {
  const otherPhone = { ...phone, name: 'iPhone 16e', udid: 'A0000000-0000-0000-0000-000000000003' };
  const id = runtime('26.2').identifier;
  assert.equal(selectIosCiSimulator([runtime('26.2')], { [id]: [otherPhone, phone, tablet] }, 'iphone').device, phone);
  assert.throws(() => selectIosCiSimulator([runtime('26.2')], { [id]: [otherPhone, tablet] }, 'iphone'), /absent ou ambigu/);
  assert.throws(() => selectIosCiSimulator([runtime('26.2')], { [id]: [phone, { ...phone, udid: otherPhone.udid }] }, 'iphone'), /absent ou ambigu/);
});
