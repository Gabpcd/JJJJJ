import { existsSync, readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

// Règles extraites des composants pour les vecteurs golden iOS (lot 2 W1,
// lot 4 W0). L'exporteur `scripts/mobile/export-golden-vectors.mjs` les charge
// par le type stripping de Node : chaque module (et tout ce qu'il importe) doit
// rester pur — ni React, ni lucide-react, ni client Supabase, ni syntaxe
// TypeScript non effaçable.
const MODULES_GOLDEN = [
  'src/lib/documents-requis.ts',
  'src/lib/presences-soignant-listes.ts',
  'src/lib/raisons-score-matching.ts',
  'src/lib/filtre-paquet-swipe.ts',
  'src/lib/statut-litige-regles.ts',
];

// Seul module pur hors de `src/lib` déjà chargé par l'exporteur golden (lot 1).
const PLANNING_CANDIDAT = 'src/components/planning/planning-candidat.ts';

const RACINE = process.cwd();
const IMPORT = /^\s*(import|export)\s+(type\s+)?[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm;

function cible(depuis: string, specifier: string): string | null {
  if (specifier.startsWith('@/lib/')) return `src/lib/${specifier.slice('@/lib/'.length)}.ts`;
  if (specifier.startsWith('./') || specifier.startsWith('../')) {
    return relative(RACINE, resolve(RACINE, dirname(depuis), `${specifier}.ts`));
  }
  return null;
}

function anomalies(module: string, vus = new Set<string>()): string[] {
  if (vus.has(module)) return [];
  vus.add(module);
  if (!existsSync(resolve(RACINE, module))) return [`${module} : introuvable`];
  const source = readFileSync(resolve(RACINE, module), 'utf8');
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
    erreurs.push(...anomalies(fichier, vus));
  }
  return erreurs;
}

describe('règles pures exportées en vecteurs golden iOS', () => {
  it.each(MODULES_GOLDEN)('%s ne dépend que de règles pures', (module) => {
    expect(anomalies(module)).toEqual([]);
  });

  it('la garde détecte un import interdit', () => {
    expect(anomalies('src/lib/statutLitige.ts')).toEqual([
      'src/lib/statutLitige.ts : import « lucide-react » hors des règles pures',
    ]);
  });
});
