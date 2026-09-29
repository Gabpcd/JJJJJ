import { readdirSync, readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { parse } from 'acorn';

// Check emitted code, after lowering, bundling and minification. A build target
// alone did not prevent keepNames from emitting a Safari-16.4 static block.
const root = path.resolve(process.argv[2] || 'dist');
const files = [];
function visit(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) visit(file);
    else if (entry.isFile() && /\.m?js$/.test(file)) files.push(file);
  }
}
visit(path.join(root, 'assets'));
if (files.length === 0) throw new Error('Aucun JavaScript compilé à vérifier.');
const firebase = path.join(root, 'firebase-messaging-sw.js');
if (existsSync(firebase)) files.push(firebase);
let failures = 0;
for (const file of files) {
  try { parse(readFileSync(file, 'utf8'), { ecmaVersion: 2020, sourceType: 'module' }); }
  catch (error) { failures++; console.error(`${path.relative(root, file)} : syntaxe incompatible ES2020 (${error.message}).`); }
}
// Versioned PDF image decoders under pdfjs-assets/ are third-party resources,
// not Vite output; their Safari-15 syntax is reviewed when the version changes.
if (failures) process.exitCode = 1;
else console.log(`${files.length} fichiers JavaScript compilés : syntaxe ES2020 vérifiée (y compris les workers).`);
