import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { runInNewContext } from 'node:vm';

test('real signup audit uses runtime cryptographic entropy and an accepted password shape', () => {
  const source = readFileSync(new URL('../../e2e/non-regression/signup-series-c-audit.spec.ts', import.meta.url), 'utf8');
  assert.match(source, /import\s*\{\s*randomBytes\s*\}\s*from\s*'node:crypto'/);
  const declarations = [...source.matchAll(/^const PASSWORD = (.+);$/gm)];
  assert.equal(declarations.length, 1);
  const expression = declarations[0][1];
  assert.match(expression, /randomBytes\(24\)/);
  assert.doesNotMatch(expression, /process\.env|Math\.random|Date\.now/);
  const generated = new Set();
  for (let i = 0; i < 64; i++) {
    const value = runInNewContext(expression, { randomBytes });
    assert.equal(typeof value, 'string');
    assert.ok(value.length >= 48 && value.length <= 72);
    for (const rule of [/[A-Z]/, /[a-z]/, /[0-9]/, /[^a-zA-Z0-9]/]) assert.equal(rule.test(value), true);
    generated.add(value);
  }
  assert.equal(generated.size, 64);
  assert.match(source, /getByLabel\('Mot de passe', \{ exact: true \}\)\.fill\(PASSWORD\)/);
});

test('visibility-only password canary is never submitted or used as an account credential', () => {
  const source = readFileSync(new URL('../../e2e/inscription.spec.ts', import.meta.url), 'utf8');
  const start = source.indexOf("test('permet de vérifier son mot de passe sans le saisir deux fois'");
  assert.ok(start >= 0);
  const block = source.slice(start, source.indexOf('\n  });', start));
  assert.match(block, /fill\('Visibilite-Synthetique!42'\)/);
  assert.doesNotMatch(block, /signUp|signIn|request\.|fetch\(|submit|Créer mon compte/);
  assert.equal([...block.matchAll(/\.click\(/g)].length, 2);
  assert.match(block, /Afficher le mot de passe/);
  assert.match(block, /Masquer le mot de passe/);
});
