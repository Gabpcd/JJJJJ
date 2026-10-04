import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync, symlinkSync, linkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EXTERNAL_TAGS, sanitizePrivateHtml, readPrivateAsset } from '../private-app.mjs';

const unchanged = '<link rel="canonical" href="https://jolene.app/" /><link rel="manifest" href="/manifest.json?v=5" />'
  + '<div id="root"></div><script type="module" src="/assets/main.js"></script>';
const original = '<!doctype html><html><head>' + EXTERNAL_TAGS.join('\n') + unchanged + '</head></html>';

test('the exact five external resource hints/styles are removed once; App scripts and metadata are unchanged', () => {
  const converted = sanitizePrivateHtml(original);
  assert.equal(converted, original.replace(EXTERNAL_TAGS.join('\n'), '\n'.repeat(4)));
  assert.ok(converted.includes(unchanged));
});

test('missing, duplicated, already sanitized or changed external tags refuse instead of a broad HTML rewrite', () => {
  for (const html of [original.replace(EXTERNAL_TAGS[0], ''), original + EXTERNAL_TAGS[0], sanitizePrivateHtml(original),
    original.replace('fonts.gstatic.com', 'example.invalid'), original + '<link rel="stylesheet" href="https://example.invalid/a.css">']) {
    assert.throws(() => sanitizePrivateHtml(html), { message: 'RESTORE_PRIVATE_APP_REFUSED' });
  }
});

function corpus(t) {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), 'restore-app-unit-')));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'assets'));
  writeFileSync(join(dir, 'index.html'), sanitizePrivateHtml(original));
  writeFileSync(join(dir, 'assets', 'main.js'), '/* synthetic */');
  writeFileSync(join(dir, 'manifest.json'), '{"name":"Synthetic"}');
  return dir;
}

test('filesystem-only serving reads App routes/assets with GET and HEAD, no socket or listener', t => {
  const dir = corpus(t);
  for (const path of ['/', '/connexion', '/etablissement/missions/synthetic']) {
    const response = readPrivateAsset(dir, path);
    assert.equal(response.status, 200); assert.equal(response.type, 'text/html; charset=utf-8');
    assert.equal(response.body.toString(), sanitizePrivateHtml(original));
  }
  assert.equal(readPrivateAsset(dir, '/assets/main.js').body.toString(), '/* synthetic */');
  assert.equal(readPrivateAsset(dir, '/manifest.json?v=5').status, 200);
  const head = readPrivateAsset(dir, '/assets/main.js', 'HEAD');
  assert.equal(head.status, 200); assert.equal(head.body.length, 0); assert.equal(head.bytes, 15);
});

test('traversal, symlinks, hard links, dotfiles, sourcemaps and unknown assets cannot leave the owned build', t => {
  const dir = corpus(t);
  writeFileSync(join(dir, 'secret.json'), '{}');
  symlinkSync(join(dir, 'secret.json'), join(dir, 'assets', 'linked.json'));
  linkSync(join(dir, 'secret.json'), join(dir, 'assets', 'hard.json'));
  for (const path of ['/../input.json', '/%2e%2e/input.json', '/assets/%252e%252e/input.json', '/assets/..%2finput.json',
    '/assets/linked.json', '/assets/hard.json', '/.env', '/assets/main.js.map', '/assets/missing.js', '//example.invalid/a.js', '/assets\\main.js']) {
    const response = readPrivateAsset(dir, path); assert.equal(response.status, 404); assert.equal(response.body.length, 0);
  }
  assert.equal(readPrivateAsset(dir, '/', 'POST').status, 405);
});

test('an untransformed index is never served; errors do not expose filesystem contents', t => {
  const dir = corpus(t);
  writeFileSync(join(dir, 'index.html'), original);
  assert.deepEqual(readPrivateAsset(dir, '/'), { status: 404, body: Buffer.alloc(0) });
});
