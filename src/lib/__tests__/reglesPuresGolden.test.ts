import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';

// Règles extraites des composants pour les vecteurs golden iOS (lot 2 W1,
// lot 4 W0). L'exporteur `scripts/mobile/export-golden-vectors.mjs` les charge
// par le type stripping de Node : chaque module (et tout ce qu'il importe) doit
// rester pur — ni React, ni lucide-react, ni client Supabase, ni syntaxe
// TypeScript non effaçable.
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
const PLANNING_CANDIDAT = 'src/components/planning/planning-candidat.ts';

const RACINE = process.cwd();
const IMPORT = /^\s*(import|export)\s+(type\s+)?[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm;

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
  const source = lire(module);
  if (source === null) return [`${module} : introuvable`];
  const erreurs: string[] = [];
  if (/^\s*(export\s+)?(declare\s+)?(const\s+)?enum\s/m.test(source)) erreurs.push(`${module} : enum`);
  if (/^\s*(export\s+)?namespace\s+\w+/m.test(source)) erreurs.push(`${module} : namespace`);
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

function chargerSousNode(_racineSrc: string, _modules: string[]): Record<string, Chargement> {
  throw new Error('chargement réel sous Node : à implémenter');
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
