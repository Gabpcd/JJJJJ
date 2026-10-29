import test from 'node:test';
import assert from 'node:assert/strict';
import { selectNativeScenario, iosTestMethod, scenarioCaptureNames, CONTRACT_CAPTURES, PRESENCE_CAPTURES } from './native-scenarios.mjs';

test('the default keeps the existing consultation methods and sixteen captures', () => {
  const selected = selectNativeScenario({}, 'ios', 'ipad');
  assert.deepEqual(selected.orientations, ['portrait', 'landscape']);
  assert.equal(iosTestMethod(selected, 'ipad', 'portrait'), 'testPortraitConsultation');
  assert.equal(iosTestMethod(selected, 'ipad', 'landscape'), 'testLandscapeConsultation');
  assert.equal(scenarioCaptureNames(selected, 'ios', 'ipad', 'portrait').length, 16);
  assert.equal(selected.documentScenarioFlag, '0');
});

test('Documents selects one independent method and nine captures per fresh format', () => {
  for (const [platform, family, orientation, method] of [
    ['ios', 'iphone', 'portrait', 'testDocumentsIphonePortrait'],
    ['ios', 'ipad', 'portrait', 'testDocumentsIpadPortrait'],
    ['ios', 'ipad', 'landscape', 'testDocumentsIpadLandscape'],
    ['android', 'iphone', 'portrait', null],
  ]) {
    const selected = selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents', NATIVE_DOCUMENTS_ORIENTATION: orientation }, platform, family);
    assert.deepEqual(selected.orientations, [orientation]);
    assert.equal(selected.flowFile, 'documents-run.yaml');
    assert.equal(selected.documentScenarioFlag, '1');
    if (method) assert.equal(iosTestMethod(selected, family, orientation), method);
    const captures = scenarioCaptureNames(selected, platform, family, orientation);
    assert.equal(captures.length, 9);
    assert.equal(new Set(captures).size, 9);
  }
});

test('incompatible modes and accidental scenario injections fail before tool startup', () => {
  assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'unknown' }, 'ios'));
  assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents', EXPO_PUBLIC_JOLENE_MODE: 'staging' }, 'ios'));
  assert.throws(() => selectNativeScenario({ EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: '1' }, 'ios'));
  assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents', EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: '0' }, 'ios'));
  assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents', NATIVE_DOCUMENTS_ORIENTATION: 'landscape' }, 'ios', 'iphone'));
  assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents', NATIVE_DOCUMENTS_ORIENTATION: 'landscape' }, 'android'));
});

test('Contracts selects one independent method and eight Android captures and nine iOS captures including Home', () => {
  for (const [platform, family, orientation, method, prefix] of [
    ['ios', 'iphone', 'portrait', 'testContractsIphonePortrait', 'iphone-portrait-'],
    ['ios', 'ipad', 'portrait', 'testContractsIpadPortrait', 'ipad-portrait-'],
    ['ios', 'ipad', 'landscape', 'testContractsIpadLandscape', 'ipad-paysage-'],
    ['android', 'iphone', 'portrait', null, ''],
  ]) {
    const selected = selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'contracts', NATIVE_CONTRACTS_ORIENTATION: orientation,
      EXPO_PUBLIC_JOLENE_MODE: 'demo', EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: '1', EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: '0' }, platform, family);
    assert.deepEqual(selected, { name: 'contracts', flowFile: 'contracts-run.yaml', documentScenarioFlag: '0',
      contractScenarioFlag: '1', orientations: [orientation] });
    if (method) assert.equal(iosTestMethod(selected, family, orientation), method);
    const captures = scenarioCaptureNames(selected, platform, family, orientation);
    const expected = [...CONTRACT_CAPTURES];
    if (platform === 'ios') expected.splice(3, 0, 'contrats-home');
    assert.deepEqual(captures, expected.map(name => `${prefix}${name}`));
    assert.equal(new Set(captures).size, platform === 'ios' ? 9 : 8);
    const other = orientation === 'portrait' ? 'landscape' : 'portrait';
    assert.throws(() => scenarioCaptureNames(selected, platform, family, other));
    assert.throws(() => iosTestMethod(selected, family, other));
  }
});

test('Contracts rejects real modes, mixed fixtures and unsupported orientations before tool startup', () => {
  const contract = { NATIVE_PILOT_SCENARIO: 'contracts' };
  for (const mode of ['staging', 'production']) {
    assert.throws(() => selectNativeScenario({ ...contract, EXPO_PUBLIC_JOLENE_MODE: mode }, 'ios'));
  }
  for (const flag of ['0', 'true', '2']) {
    assert.throws(() => selectNativeScenario({ ...contract, EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: flag }, 'ios'));
  }
  assert.throws(() => selectNativeScenario({ ...contract, EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: '1' }, 'ios'));
  assert.throws(() => selectNativeScenario({ ...contract, NATIVE_DOCUMENTS_ORIENTATION: 'portrait' }, 'ios'));
  assert.throws(() => selectNativeScenario({ ...contract, NATIVE_CONTRACTS_ORIENTATION: 'landscape' }, 'ios', 'iphone'));
  assert.throws(() => selectNativeScenario({ ...contract, NATIVE_CONTRACTS_ORIENTATION: 'landscape' }, 'android'));
  assert.throws(() => selectNativeScenario({ ...contract, NATIVE_CONTRACTS_ORIENTATION: 'invalid' }, 'ios', 'ipad'));
  for (const name of ['consultation', 'documents']) {
    assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: name, EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: '1' }, 'ios'));
    assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: name, NATIVE_CONTRACTS_ORIENTATION: 'portrait' }, 'ios'));
  }
});

test('adding Contracts preserves the exact Consultation and Documents manifests', () => {
  assert.deepEqual(selectNativeScenario({}, 'ios', 'ipad'), { name: 'consultation', flowFile: 'consultation.yaml',
    documentScenarioFlag: '0', orientations: ['portrait', 'landscape'] });
  assert.deepEqual(selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents' }, 'android'), { name: 'documents',
    flowFile: 'documents-run.yaml', documentScenarioFlag: '1', orientations: ['portrait'] });
});

test('Presence selects a separate method and all thirteen evidence images on four fresh formats', () => {
  for (const [platform, family, orientation, method, prefix] of [
    ['ios', 'iphone', 'portrait', 'testPresenceIphonePortrait', 'iphone-portrait-'],
    ['ios', 'ipad', 'portrait', 'testPresenceIpadPortrait', 'ipad-portrait-'],
    ['ios', 'ipad', 'landscape', 'testPresenceIpadLandscape', 'ipad-paysage-'],
    ['android', 'iphone', 'portrait', null, ''],
  ]) {
    const selected = selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'presence', NATIVE_PRESENCE_ORIENTATION: orientation,
      EXPO_PUBLIC_JOLENE_MODE: 'demo', EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO: '1' }, platform, family);
    assert.deepEqual(selected, { name: 'presence', flowFile: 'presence-run.yaml', documentScenarioFlag: '0',
      contractScenarioFlag: '0', presenceScenarioFlag: '1', orientations: [orientation] });
    if (method) assert.equal(iosTestMethod(selected, family, orientation), method);
    const captures = scenarioCaptureNames(selected, platform, family, orientation);
    assert.deepEqual(captures, PRESENCE_CAPTURES.map(name => `${prefix}${name}`));
    assert.equal(new Set(captures).size, 13);
    const other = orientation === 'portrait' ? 'landscape' : 'portrait';
    assert.throws(() => scenarioCaptureNames(selected, platform, family, other));
    assert.throws(() => iosTestMethod(selected, family, other));
  }
});

test('Presence refuses real modes, mixed worlds and unsupported orientations before tool startup', () => {
  const presence = { NATIVE_PILOT_SCENARIO: 'presence' };
  for (const mode of ['staging', 'production']) {
    assert.throws(() => selectNativeScenario({ ...presence, EXPO_PUBLIC_JOLENE_MODE: mode }, 'ios'));
  }
  for (const flag of ['0', 'true', '2']) {
    assert.throws(() => selectNativeScenario({ ...presence, EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO: flag }, 'ios'));
  }
  for (const [name, value] of [['EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO', '1'], ['EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO', '1'],
    ['NATIVE_DOCUMENTS_ORIENTATION', 'portrait'], ['NATIVE_CONTRACTS_ORIENTATION', 'portrait']]) {
    assert.throws(() => selectNativeScenario({ ...presence, [name]: value }, 'ios'));
  }
  assert.throws(() => selectNativeScenario({ ...presence, NATIVE_PRESENCE_ORIENTATION: 'landscape' }, 'ios', 'iphone'));
  assert.throws(() => selectNativeScenario({ ...presence, NATIVE_PRESENCE_ORIENTATION: 'landscape' }, 'android'));
  assert.throws(() => selectNativeScenario({ ...presence, NATIVE_PRESENCE_ORIENTATION: 'invalid' }, 'ios', 'ipad'));
  for (const name of ['consultation', 'documents', 'contracts']) {
    assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: name, EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO: '1' }, 'ios'));
    assert.throws(() => selectNativeScenario({ NATIVE_PILOT_SCENARIO: name, NATIVE_PRESENCE_ORIENTATION: 'portrait' }, 'ios'));
  }
});

test('adding Presence preserves exact Consultation, Documents and Contracts manifests', () => {
  assert.deepEqual(selectNativeScenario({}, 'ios', 'ipad'), { name: 'consultation', flowFile: 'consultation.yaml',
    documentScenarioFlag: '0', orientations: ['portrait', 'landscape'] });
  assert.deepEqual(selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'documents' }, 'android'), { name: 'documents',
    flowFile: 'documents-run.yaml', documentScenarioFlag: '1', orientations: ['portrait'] });
  assert.deepEqual(selectNativeScenario({ NATIVE_PILOT_SCENARIO: 'contracts' }, 'ios', 'iphone'), { name: 'contracts',
    flowFile: 'contracts-run.yaml', documentScenarioFlag: '0', contractScenarioFlag: '1', orientations: ['portrait'] });
});
