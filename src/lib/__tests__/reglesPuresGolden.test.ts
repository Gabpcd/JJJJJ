import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, describe, expect, it } from 'vitest';

// Règles extraites des composants pour les vecteurs golden iOS (lot 2 W1,
// lot 4 W0). L'exporteur `scripts/mobile/export-golden-vectors.mjs` les charge
// par le type stripping de Node : chaque module (et tout ce qu'il importe) doit
// rester pur — ni React, ni lucide-react, ni client Supabase, ni syntaxe
// TypeScript non effaçable. Deux gardes complémentaires :
// - lecture statique de la fermeture des imports : dépendances autorisées,
//   aucun import à effet de bord, aucun import() dynamique ni require ;
// - chargement réel sous Node avec la résolution du hook de l'exporteur
//   (lot 1 T2) : seul ce chargement voit un import d'interface sans `type`
//   (« does not provide an export named »), que `tsc` laisse passer sans
//   `verbatimModuleSyntax`, et toute syntaxe non effaçable.
// Exports attendus de chaque module, triés comme `Object.keys(…).sort()`.
const MODULES_GOLDEN: Record<string, string[]> = {
  'src/lib/documents-requis.ts': ['documentValidePourExigence', 'filtrerDocumentsRequis'],
  'src/lib/presences-soignant-listes.ts': ['construireListesPresences', 'regrouperCreneauxParMission'],
  'src/lib/raisons-score-matching.ts': ['RAISONS_EPINGLEES', 'RAISON_LABELS', 'raisonsScore'],
  'src/lib/filtre-paquet-swipe.ts': [
    'filtrerPaquetSwipe', 'missionCorrespondProfessionInscription', 'missionPasseFiltrePaquet',
  ],
  'src/lib/statut-litige-regles.ts': [
    'estResolu', 'peutConfirmerAccord', 'peutProposerMediation', 'statutLitigeRegle',
  ],
};

// Seul module pur hors de `src/lib` déjà chargé par l'exporteur golden (lot 1).
// Il est atteint par un import relatif (`filtre-paquet-swipe.ts`) : le hook de
// l'exporteur refuse tout alias `@/components/`. Exception temporaire, à lever
// quand le hook autorisera exactement ce module (lot 1 T2) ou quand
// `planning-candidat.ts` sera déplacé sous `src/lib`.
const PLANNING_CANDIDAT = 'src/components/planning/planning-candidat.ts';

const RACINE = process.cwd();
const IMPORT = /^\s*(import|export)\s+(type\s+)?[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm;
const IMPORT_EFFET_DE_BORD = /^\s*import\s*['"]([^'"]+)['"]/gm;
const IMPORT_DYNAMIQUE = /(^|[^\w$.])import\s*\(/;
const REQUIRE = /(^|[^\w$.])require\s*\(/;
// Caractères après lesquels une barre oblique ouvre un motif, pas une division.
const AVANT_MOTIF = new Set(['', '(', ',', '=', ':', '[', '!', '&', '|', '?', '{', '}', ';', '\n']);

/**
 * Retire les commentaires (sauts de ligne conservés). Avec `chaines: false`,
 * vide aussi le contenu des chaînes, gabarits et motifs : un `import(` ou un
 * `require(` cité dans un texte n'est pas du code. Les spécificateurs d'import
 * se lisent sur la version qui garde les chaînes.
 */
function sansCommentaires(source: string, { chaines = true } = {}): string {
  let sortie = '';
  let precedent = '';
  let i = 0;
  const vider = (morceau: string) => morceau.replace(/[^\n]/g, ' ');
  while (i < source.length) {
    const c = source[i];
    const suivant = source[i + 1] ?? '';
    if (c === '/' && suivant === '*') {
      const fin = source.indexOf('*/', i + 2);
      const bloc = source.slice(i, fin < 0 ? source.length : fin + 2);
      sortie += vider(bloc);
      i += bloc.length;
      continue;
    }
    if (c === '/' && suivant === '/') {
      const fin = source.indexOf('\n', i);
      i = fin < 0 ? source.length : fin;
      continue;
    }
    const motif = c === '/' && AVANT_MOTIF.has(precedent);
    if (c === "'" || c === '"' || c === '`' || motif) {
      let j = i + 1;
      let classe = false;
      while (j < source.length) {
        const d = source[j];
        if (d === '\\') { j += 2; continue; }
        if (motif && d === '[') classe = true;
        else if (motif && d === ']') classe = false;
        else if (d === (motif ? '/' : c) && !classe) break;
        else if (d === '\n' && c !== '`') break;
        j += 1;
      }
      const litteral = source.slice(i, j + 1);
      sortie += chaines ? litteral : c + vider(litteral.slice(1, -1)) + litteral.slice(-1);
      precedent = c === '/' ? 'motif' : 'chaine';
      i = j + 1;
      continue;
    }
    sortie += c;
    if (c === '\n' || !/\s/.test(c)) precedent = c;
    i += 1;
  }
  return sortie;
}

type Lecteur = (module: string) => string | null;

const lireDisque: Lecteur = (module) => {
  const chemin = resolve(RACINE, module);
  return existsSync(chemin) ? readFileSync(chemin, 'utf8') : null;
};

function cible(depuis: string, specifier: string): string | null {
  if (specifier.startsWith('@/lib/')) return `src/lib/${specifier.slice('@/lib/'.length)}.ts`;
  if (specifier.startsWith('./') || specifier.startsWith('../')) {
    return relative(RACINE, resolve(RACINE, dirname(depuis), `${specifier}.ts`));
  }
  return null;
}

function anomalies(module: string, lire: Lecteur = lireDisque, vus = new Set<string>()): string[] {
  if (vus.has(module)) return [];
  vus.add(module);
  const brut = lire(module);
  if (brut === null) return [`${module} : introuvable`];
  const source = sansCommentaires(brut);
  const code = sansCommentaires(brut, { chaines: false });
  const erreurs: string[] = [];
  if (/^\s*(export\s+)?(declare\s+)?(const\s+)?enum\s/m.test(code)) erreurs.push(`${module} : enum`);
  if (/^\s*(export\s+)?namespace\s+\w+/m.test(code)) erreurs.push(`${module} : namespace`);
  if (IMPORT_DYNAMIQUE.test(code)) erreurs.push(`${module} : import() dynamique`);
  if (REQUIRE.test(code)) erreurs.push(`${module} : require`);
  for (const [, specifier] of source.matchAll(IMPORT_EFFET_DE_BORD)) {
    erreurs.push(`${module} : import à effet de bord « ${specifier} »`);
  }
  for (const [, , typeSeul, specifier] of source.matchAll(IMPORT)) {
    if (typeSeul) continue;
    const fichier = cible(module, specifier);
    const autorise = fichier !== null
      && (fichier.startsWith('src/lib/') || fichier === PLANNING_CANDIDAT);
    if (!autorise) {
      erreurs.push(`${module} : import « ${specifier} » hors des règles pures`);
      continue;
    }
    erreurs.push(...anomalies(fichier, lire, vus));
  }
  return erreurs;
}

type Chargement = { exports: string[] } | { erreur: string };

// Résolution du hook de l'exporteur golden (lot 1 T2, `module.register()`) :
// `@/lib/<module>` → `src/lib/<module>.ts`, tout autre alias `@/` refusé,
// import relatif sans extension d'un module `.ts` de `src/` complété en `.ts`.
// Plus strict que l'exporteur : un paquet npm est refusé (aucun n'est attendu
// dans la fermeture d'une règle golden de ces lots).
const HOOK_RESOLUTION = `
let racineSrc = null;
const AVEC_EXTENSION = /\\.[cm]?[jt]sx?$/;
export async function initialize(donnees) {
  racineSrc = donnees.racineSrc;
}
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith('@/')) {
    if (!specifier.startsWith('@/lib/')) {
      throw new Error('alias « ' + specifier + ' » refusé depuis ' + context.parentURL);
    }
    const cible = new URL(specifier.slice(2) + (AVEC_EXTENSION.test(specifier) ? '' : '.ts'), racineSrc);
    return nextResolve(cible.href, context);
  }
  if (specifier.startsWith('./') || specifier.startsWith('../')) {
    const parentTs = typeof context.parentURL === 'string'
      && context.parentURL.startsWith(racineSrc) && context.parentURL.endsWith('.ts');
    return nextResolve(specifier + (parentTs && !AVEC_EXTENSION.test(specifier) ? '.ts' : ''), context);
  }
  if (/^(file|data|node):/.test(specifier)) return nextResolve(specifier, context);
  throw new Error('paquet « ' + specifier + ' » refusé depuis ' + context.parentURL);
}
`;

/** Charge chaque module dans un processus Node neuf (type stripping natif). */
function chargerSousNode(racineSrc: string, modules: string[]): Record<string, Chargement> {
  // Chemin réel : Node résout les liens symboliques (`/var` → `/private/var`
  // sous macOS) avant de passer `parentURL` au hook.
  const urlRacine = pathToFileURL(`${realpathSync(racineSrc)}/`).href;
  const programme = `
    import { register } from 'node:module';
    register('data:text/javascript,' + encodeURIComponent(${JSON.stringify(HOOK_RESOLUTION)}), {
      parentURL: ${JSON.stringify(urlRacine)},
      data: { racineSrc: ${JSON.stringify(urlRacine)} },
    });
    const resultats = {};
    for (const [module, url] of ${JSON.stringify(modules.map((m) => [m, pathToFileURL(m).href]))}) {
      try {
        resultats[module] = { exports: Object.keys(await import(url)).sort() };
      } catch (erreur) {
        resultats[module] = { erreur: String(erreur?.message ?? erreur) };
      }
    }
    console.log(JSON.stringify(resultats));
  `;
  const typeStripping = (process.features as { typescript?: unknown }).typescript ? [] : ['--experimental-strip-types'];
  const sortie = execFileSync(
    process.execPath,
    [...typeStripping, '--no-warnings', '--input-type=module', '-e', programme],
    { encoding: 'utf8', timeout: 20_000 },
  );
  return JSON.parse(sortie.trim().split('\n').pop() ?? '{}');
}

/** Lecteur de sources en mémoire pour éprouver la garde statique. */
const virtuel = (sources: Record<string, string>): Lecteur => (module) => sources[module] ?? null;

describe('règles pures exportées en vecteurs golden iOS', () => {
  it.each(Object.keys(MODULES_GOLDEN))('%s ne dépend que de règles pures', (module) => {
    expect(anomalies(module)).toEqual([]);
  });

  it('chaque module se charge sous Node avec la résolution de l’exporteur et expose ses règles', () => {
    const chargements = chargerSousNode(resolve(RACINE, 'src'), Object.keys(MODULES_GOLDEN).map((m) => resolve(RACINE, m)));
    expect(Object.fromEntries(Object.keys(MODULES_GOLDEN).map((m) => [m, chargements[resolve(RACINE, m)]])))
      .toEqual(Object.fromEntries(Object.entries(MODULES_GOLDEN).map(([m, exports]) => [m, { exports }])));
  });
});

describe('la garde statique détecte', () => {
  it('un import interdit', () => {
    expect(anomalies('src/lib/statutLitige.ts')).toEqual([
      'src/lib/statutLitige.ts : import « lucide-react » hors des règles pures',
    ]);
  });

  it('un import interdit dans une dépendance transitive', () => {
    expect(anomalies('src/lib/a.ts', virtuel({
      'src/lib/a.ts': "import { b } from './b';\nexport const a = b;\n",
      'src/lib/b.ts': "import { createClient } from '@supabase/supabase-js';\nexport const b = createClient;\n",
    }))).toEqual(['src/lib/b.ts : import « @supabase/supabase-js » hors des règles pures']);
  });

  it('un import à effet de bord, sans from', () => {
    expect(anomalies('src/lib/a.ts', virtuel({
      'src/lib/a.ts': "import 'react';\nimport \"./polyfill\";\nexport const a = 1;\n",
    }))).toEqual([
      'src/lib/a.ts : import à effet de bord « react »',
      'src/lib/a.ts : import à effet de bord « ./polyfill »',
    ]);
  });

  it('un import() dynamique', () => {
    expect(anomalies('src/lib/a.ts', virtuel({
      'src/lib/a.ts': "export async function a() {\n  const { supabase } = await import('@/integrations/supabase/client');\n  return supabase;\n}\n",
    }))).toEqual(['src/lib/a.ts : import() dynamique']);
  });

  it('un require', () => {
    expect(anomalies('src/lib/a.ts', virtuel({
      'src/lib/a.ts': "const React = require('react');\nexport const a = React;\n",
    }))).toEqual(['src/lib/a.ts : require']);
  });

  it('sans faux positif dans les commentaires ni les chaînes', () => {
    expect(anomalies('src/lib/a.ts', virtuel({
      'src/lib/a.ts': [
        "// import('react') et require('react') : seulement mentionnés",
        "/* import 'react';",
        "   require('react') */",
        "export const texte = \"import('react') ou require('x')\";",
        "export const gabarit = `import 'react';`;",
        'export const motif = /require\\(/;',
        'export const meta = import.meta;',
        '',
      ].join('\n'),
    }))).toEqual([]);
  });

  it('un import après une chaîne contenant // ou un motif contenant une apostrophe', () => {
    expect(anomalies('src/lib/a.ts', virtuel({
      'src/lib/a.ts': [
        "export const lien = 'https://exemple.test';",
        "const apostrophe = /'/;",
        "import 'react';",
        "import { useState } from 'react';",
        'export const a = apostrophe;',
        '',
      ].join('\n'),
    }))).toEqual([
      'src/lib/a.ts : import à effet de bord « react »',
      'src/lib/a.ts : import « react » hors des règles pures',
    ]);
  });
});

describe('le chargement réel sous Node détecte', () => {
  const dossiers: string[] = [];
  afterAll(() => dossiers.forEach((d) => rmSync(d, { recursive: true, force: true })));

  /** Écrit des modules dans un `src/` temporaire et les charge sous Node. */
  function charger(sources: Record<string, string>, entree: string): Chargement {
    const src = join(mkdtempSync(join(tmpdir(), 'regles-pures-golden-')), 'src');
    dossiers.push(dirname(src));
    for (const [chemin, contenu] of Object.entries(sources)) {
      mkdirSync(dirname(join(src, chemin)), { recursive: true });
      writeFileSync(join(src, chemin), contenu);
    }
    return chargerSousNode(src, [join(src, entree)])[join(src, entree)];
  }

  it('un import d’interface sans le mot-clé type, que tsc laisse passer', () => {
    const forme = 'export interface Forme { cote: number }\nexport const UNITE = 1;\n';
    expect(charger({
      'lib/forme.ts': forme,
      'lib/aire.ts': "import { Forme, UNITE } from './forme';\nexport const aire = (f: Forme) => f.cote * f.cote * UNITE;\n",
    }, 'lib/aire.ts')).toEqual({ erreur: expect.stringContaining("does not provide an export named 'Forme'") });
    expect(charger({
      'lib/forme.ts': forme,
      'lib/aire.ts': "import { type Forme, UNITE } from './forme';\nexport const aire = (f: Forme) => f.cote * f.cote * UNITE;\n",
    }, 'lib/aire.ts')).toEqual({ exports: ['aire'] });
  });

  it('un alias @/ autre que @/lib/ et un paquet npm, comme le hook de l’exporteur', () => {
    expect(charger({
      'lib/a.ts': "import { x } from '@/components/x';\nexport const a = x;\n",
      'components/x.ts': 'export const x = 1;\n',
    }, 'lib/a.ts')).toEqual({ erreur: expect.stringContaining('alias « @/components/x » refusé') });
    expect(charger({
      'lib/a.ts': "import 'react';\nexport const a = 1;\n",
    }, 'lib/a.ts')).toEqual({ erreur: expect.stringContaining('paquet « react » refusé') });
    expect(charger({
      'lib/a.ts': "import { b } from '@/lib/b';\nexport const a = b;\n",
      'lib/b.ts': 'export const b = 2;\n',
    }, 'lib/a.ts')).toEqual({ exports: ['a'] });
  });

  it('une syntaxe TypeScript non effaçable', () => {
    expect(charger({
      'lib/a.ts': 'export enum Couleur { Rouge }\n',
    }, 'lib/a.ts')).toEqual({ erreur: expect.stringMatching(/enum|strip-only|UNSUPPORTED_TYPESCRIPT_SYNTAX/i) });
  });
});
