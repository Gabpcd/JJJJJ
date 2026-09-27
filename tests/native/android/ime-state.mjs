import assert from 'node:assert/strict';

/** Android 15 dumps the current state before mStartInputHistory.
 * The history also contains mInputShown=true after the keyboard has closed.
 * Source: AOSP InputMethodManagerService.dump and ImeVisibilityStateComputer.dump.
 */
export function currentImeShown(dump) {
  const current = dump.split(/^\s*mStartInputHistory:/m)[0];
  const values = [...current.matchAll(/^\s*mInputShown=(true|false)\s*$/gm)];
  assert.equal(values.length, 1, 'Expected exactly one current Android IME visibility field');
  return values[0][1] === 'true';
}
