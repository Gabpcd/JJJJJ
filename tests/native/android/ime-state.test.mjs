import test from 'node:test';
import assert from 'node:assert/strict';
import { currentImeShown } from './ime-state.mjs';

test('hidden current IME is not mistaken for an earlier shown history entry', () => {
  assert.equal(currentImeShown('  mInputShown=false\n  mStartInputHistory:\n    mInputShown=true\n  mSoftInputShowHideHistory:\n    mInputShown=true\n'), false);
});
test('shown current IME remains true despite later historical false values', () => {
  assert.equal(currentImeShown('  mInputShown=true\n  mStartInputHistory:\n    mInputShown=false\n'), true);
});
test('missing and ambiguous current fields fail instead of reporting hidden', () => {
  assert.throws(() => currentImeShown('  mStartInputHistory:\n    mInputShown=true\n'));
  assert.throws(() => currentImeShown('  mInputShown=false\n  mInputShown=true\n'));
});
