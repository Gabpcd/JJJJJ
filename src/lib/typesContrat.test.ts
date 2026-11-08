import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { TYPES_CONTRAT_SALARIES, estContratSalarie } from './typesContrat';

// CDDU et VACATION sont des contrats salariés, au même titre que CDD et SALARIE :
// DPAE obligatoire (C. trav. art. L.1221-10, R.1221-1 s.), CDD d'usage = CDD
// (art. L.1242-2 3° et D.1242-1). Décision du 08/11/2026.
describe('types de contrat salariés — source unique', () => {
  it('liste exactement CDD, SALARIE, CDDU et VACATION', () => {
    expect([...TYPES_CONTRAT_SALARIES].sort()).toEqual(['CDD', 'CDDU', 'SALARIE', 'VACATION']);
  });

  it.each(['CDD', 'SALARIE', 'CDDU', 'VACATION'])('%s est un contrat salarié', type => {
    expect(estContratSalarie(type)).toBe(true);
  });

  it.each(['REMPLACEMENT_LIBERAL', 'LIBERAL', 'MIXTE', 'TOUS', 'cddu', ' CDDU', '', null, undefined])(
    '%s n’est pas un contrat salarié', type => {
      expect(estContratSalarie(type as string | null | undefined)).toBe(false);
    });

  it('la liste ne peut pas être modifiée à l’exécution', () => {
    expect(Object.isFrozen(TYPES_CONTRAT_SALARIES)).toBe(true);
  });
});

// Test-garde : aucune surface web ne doit re-décider localement la liste des
// contrats salariés (principe « filtre centralisé » du CLAUDE.md). L'ancienne
// règle locale ['CDD', 'SALARIE'] oubliait CDDU et VACATION.
describe('garde — aucune liste salariée locale dans src/', () => {
  const racine = resolve(process.cwd(), 'src');
  const fichiers = (dossier: string): string[] => readdirSync(dossier).flatMap(nom => {
    const chemin = join(dossier, nom);
    if (statSync(chemin).isDirectory()) return nom === '__tests__' ? [] : fichiers(chemin);
    return /\.(ts|tsx)$/.test(nom) && !/\.(test|spec)\.(ts|tsx)$/.test(nom) ? [chemin] : [];
  });
  const sources = fichiers(racine)
    .filter(chemin => !chemin.endsWith(join('integrations', 'supabase', 'types.ts')))
    .map(chemin => ({ chemin: relative(process.cwd(), chemin), texte: readFileSync(chemin, 'utf8') }));

  it('ne contient plus la paire littérale CDD/SALARIE comme règle salariée', () => {
    const paire = /\[\s*(['"])CDD\1\s*,\s*(['"])SALARIE\2\s*\]|\[\s*(['"])SALARIE\3\s*,\s*(['"])CDD\4\s*\]/;
    const ouExclusif = /type_contrat\s*===\s*(['"])CDD\1\s*\|\|\s*[\w.?]*type_contrat\s*===\s*(['"])SALARIE\2/;
    expect(sources.filter(s => paire.test(s.texte) || ouExclusif.test(s.texte)).map(s => s.chemin)).toEqual([]);
  });

  it.each([
    'src/components/DPAEStatus.tsx',
    'src/components/BandeauRappelDPAE.tsx',
    'src/pages/ContratMission.tsx',
    'src/pages/admin/AdminDetailContrat.tsx',
    'src/lib/preferencesModesExercice.ts',
  ])('%s lit la source unique', chemin => {
    const source = sources.find(s => s.chemin === chemin);
    expect(source?.texte).toContain("from '@/lib/typesContrat'");
    expect(source?.texte).toContain('estContratSalarie(');
  });
});
