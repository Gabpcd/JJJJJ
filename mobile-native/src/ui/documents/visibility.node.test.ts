import assert from 'node:assert/strict';
import test from 'node:test';
import { advanceDocumentVisibility } from './visibility';

test('a batched inactive/active round trip preserves the need to reload journal and dossier', () => {
  const rendered = { active: true, revision: 0 };
  // Native events revoke synchronous mutation access before React renders again.
  const inactive = advanceDocumentVisibility(rendered, false);
  const resumed = advanceDocumentVisibility(inactive, true);
  assert.equal(resumed.active, rendered.active);
  assert.notEqual(resumed.revision, rendered.revision);
  assert.equal(resumed.revision, 2);
});

test('repeated notifications in the same visibility state do not invalidate an ongoing read', () => {
  const background = { active: false, revision: 1 };
  assert.equal(advanceDocumentVisibility(background, false), background);
  const resumed = advanceDocumentVisibility(background, true);
  assert.equal(advanceDocumentVisibility(resumed, true), resumed);
});
