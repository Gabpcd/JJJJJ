import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { chaineStatique, importsStatiques, scriptsHtml, verifier } from '../../scripts/ci/verifier-premier-chargement.mjs';

/** Écrit un faux dossier de build. `fichiers` : nom → code. */
function dist(fichiers, { precharges = ['vendor-react-a.js'] } = {}) {
  const racine = mkdtempSync(path.join(tmpdir(), 'premier-chargement-'));
  mkdirSync(path.join(racine, 'assets'));
  for (const [nom, code] of Object.entries(fichiers)) writeFileSync(path.join(racine, 'assets', nom), code);
  writeFileSync(path.join(racine, 'index.html'), `${precharges.map((f) => `<link rel="modulepreload" crossorigin href="/assets/${f}">`).join('')}<script type="module" crossorigin src="/assets/index-1.js"></script>`);
  return racine;
}
const SAIN = {
  'index-1.js': 'import{a}from"./vendor-react-a.js";const pdf=()=>import("./vendor-pdf-z.js");',
  'vendor-react-a.js': '',
  'LayoutApp-1.js': 'import{a}from"./vendor-react-a.js";import{c}from"./vendor-commun-c.js";',
  'vendor-commun-c.js': '',
  'vendor-pdf-z.js': 'x'.repeat(10),
  'vendor-charts-y.js': '',
  'MesGains-1.js': 'import{p}from"./vendor-pdf-z.js";',
};
const avec = (changements, options) => {
  const racine = dist({ ...SAIN, ...changements }, options);
  try { return verifier(racine, options); } finally { rmSync(racine, { recursive: true, force: true }); }
};

test('les imports statiques sont suivis, pas les imports dynamiques', () => {
  const entree = 'import{a as b}from"./vendor-react-abc.js";import"./effets-1.js";export{c}from"./partage-2.js";const x=()=>import("./vendor-pdf-zzz.js");';
  assert.deepEqual(importsStatiques(entree).sort(), ['effets-1.js', 'partage-2.js', 'vendor-react-abc.js']);
  const fichiers = { 'index-1.js': entree, 'vendor-react-abc.js': '', 'effets-1.js': 'import{v}from"./vendor-charts-9.js";', 'partage-2.js': '', 'vendor-charts-9.js': '', 'vendor-pdf-zzz.js': '' };
  const chaine = chaineStatique(['index-1.js'], (nom) => fichiers[nom]);
  assert.equal(chaine.includes('vendor-charts-9.js'), true, 'une bibliothèque importée par un intermédiaire est vue');
  assert.equal(chaine.includes('vendor-pdf-zzz.js'), false, 'un import dynamique ne compte pas');
});

test('l\'entrée et les préchargements sont lus dans la page', () => {
  const html = '<link rel="modulepreload" crossorigin href="/assets/vendor-react-abc.js"><script type="module" crossorigin src="/assets/index-1.js"></script>';
  assert.deepEqual(scriptsHtml(html), { entrees: ['index-1.js'], precharges: ['vendor-react-abc.js'] });
});

test('un build sain passe : une bibliothèque lourde chargée à la demande ou par son écran ne gêne pas', () => {
  const r = avec({});
  assert.deepEqual(r.erreurs, []);
  assert.deepEqual(r.chaine, ['index-1.js', 'vendor-react-a.js']);
});

test('une bibliothèque lourde dans la chaîne de l\'entrée fait échouer, même par un intermédiaire', () => {
  const r = avec({ 'index-1.js': 'import{a}from"./vendor-react-a.js";import{u}from"./utils-1.js";', 'utils-1.js': 'import{clsx}from"./vendor-charts-y.js";' });
  assert.equal(r.erreurs.length, 1);
  assert.match(r.erreurs[0], /vendor-charts-y\.js chargé\(s\) par toutes les pages/);
});

test('une bibliothèque lourde dans le cadre des espaces connectés fait échouer', () => {
  const r = avec({ 'LayoutApp-1.js': 'import{a}from"./vendor-react-a.js";import{i}from"./vendor-pdf-z.js";' });
  assert.equal(r.erreurs.length, 1);
  assert.match(r.erreurs[0], /vendor-pdf-z\.js chargé\(s\) par LayoutApp/);
});

test('le cadre surveillé doit exister : un renommage ne rend pas la garde muette', () => {
  const sansCadre = { ...SAIN }; delete sansCadre['LayoutApp-1.js'];
  const racine = dist(sansCadre);
  try { assert.match(verifier(racine).erreurs.join(' '), /aucun bloc LayoutApp-\*\.js/); } finally { rmSync(racine, { recursive: true, force: true }); }
});

test('la garde se contrôle elle-même : témoin absent ou préchargement non retrouvé', () => {
  assert.match(avec({ 'index-1.js': 'const rien=1;' }).erreurs.join(' '), /vendor-react est absent de la chaîne/);
  assert.match(avec({ 'autre-9.js': '' }, { precharges: ['vendor-react-a.js', 'autre-9.js'] }).erreurs.join(' '), /préchargés par la page mais absents de la chaîne lue : autre-9\.js/);
});

test('le budget ne s\'applique que s\'il est demandé', () => {
  assert.deepEqual(avec({}).erreurs, []);
  assert.deepEqual(avec({}, { budget: 1_000_000 }).erreurs, []);
  const r = avec({}, { budget: 10 });
  assert.equal(r.erreurs.length, 1);
  assert.match(r.erreurs[0], /octets compressés, budget 10/);
});

test('sans page d\'entrée, la garde échoue franchement', () => {
  const racine = mkdtempSync(path.join(tmpdir(), 'premier-chargement-'));
  try { assert.throws(() => verifier(racine), /aucune page d'entrée/); } finally { rmSync(racine, { recursive: true, force: true }); }
});
