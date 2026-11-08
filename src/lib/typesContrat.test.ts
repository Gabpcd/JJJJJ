import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
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

// ── Test-garde : aucune surface web ne re-décide localement les contrats salariés ──
// (principe « filtre centralisé » du CLAUDE.md). Interdits hors src/lib/typesContrat.ts :
//  1. un littéral tableau ou Set qui contient 'CDD' avec 'SALARIE', 'CDDU' ou 'VACATION',
//     sauf les listes « tous types » qui contiennent aussi 'LIBERAL' ;
//  2. startsWith('CDD…') (attrape CDD et CDDU mais oublie VACATION) ;
//  3. type_contrat ==/=== /!=/!== 'CDD' | 'CDDU' | 'VACATION' | 'SALARIE', sauf la liste
//     blanche du modèle employeur CDD ci-dessous.
// Les commentaires sont ignorés : un commentaire peut citer l'ancienne règle. Seuls
// sont retirés les commentaires de bloc ouverts en début de ligne ou après « { » (JSX)
// et les commentaires de ligne en début de ligne ou précédés d'un espace, pour ne pas
// confondre « image/* » ou « https:// » dans une chaîne avec un commentaire.
const SALARIES_HORS_CDD = ['SALARIE', 'CDDU', 'VACATION'];

function retirerCommentaires(source: string): string {
  return source
    .replace(/(^|\{)[ \t]*\/\*[\s\S]*?\*\//gm, (_tout, avant: string) => avant)
    .replace(/(^|[ \t])\/\/.*$/gm, (_tout, avant: string) => avant);
}

function violationsListeSalariee(source: string): string[] {
  const code = retirerCommentaires(source);
  const violations: string[] = [];
  for (const [litteral, contenu] of code.matchAll(/\[([^[\]]*)\]/g)) {
    const valeurs = [...contenu.matchAll(/(['"`])([A-Z_]+)\1/g)].map(([, , valeur]) => valeur);
    if (valeurs.includes('CDD') && valeurs.some(v => SALARIES_HORS_CDD.includes(v)) && !valeurs.includes('LIBERAL')) {
      violations.push(litteral.replace(/\s+/g, ' '));
    }
  }
  for (const [appel] of code.matchAll(/startsWith\(\s*['"`]CDD/g)) violations.push(appel);
  for (const [comparaison] of code.matchAll(/type_contrat\s*[!=]==?\s*(['"`])(CDD|CDDU|VACATION|SALARIE)\1/g)) {
    violations.push(comparaison);
  }
  return violations;
}

// Modèle employeur CDD (data-jolene-cdd="employeur-v1") : flux propre au CDD de droit
// commun (préparation du texte par l'employeur), pas une règle « contrat salarié ».
// Chaque entrée doit exister exactement autant de fois qu'indiqué (liste non périmée).
const LISTE_BLANCHE: { fichier: string; extrait: string; occurrences: number; motif: string }[] = [
  { fichier: 'src/pages/ContratMission.tsx', extrait: "type_contrat === 'CDD'", occurrences: 3,
    motif: 'cddSansOriginal, préparation du CDD employeur et texteEmployeur (modèle employeur-v1)' },
];

describe('garde — détecteur de liste salariée locale', () => {
  it.each([
    ['B1 AdminContrats (VACATION oublié)', "(c.type_contrat?.startsWith('CDD') || c.type_contrat === 'SALARIE')"],
    ['ancienne règle DPAE', "['CDD', 'SALARIE'].includes(typeContrat)"],
    ['ancienne règle des préférences', "contrats.some(contrat => ['CDD','VACATION','SALARIE'].includes(contrat))"],
    ['Set salarié local', "const CONTRATS_SALARIES = new Set(['CDD', 'VACATION', 'SALARIE']);"],
    ['comparaison VACATION', "if (contrat.type_contrat !== 'VACATION') return null;"],
    ['comparaison CDD hors liste blanche', 'const cdd = contrat.type_contrat == "CDD";'],
  ])('attrape %s', (_cas, source) => {
    expect(violationsListeSalariee(source)).not.toEqual([]);
  });

  it.each([
    ['liste « tous types »', "if (!soignant) return ['CDD', 'VACATION', 'LIBERAL', 'SALARIE'];"],
    ['source unique', 'estContratSalarie(contrat.type_contrat)'],
    ['régime de mission', "mission.type_contrat_applique === 'SALARIE'"],
    ['commentaire de ligne', "  // ancienne règle : ['CDD', 'SALARIE'].includes(type)"],
    ['commentaire JSX', "{/* type_contrat === 'SALARIE' */}"],
    ['commentaire de bloc', "/**\n * Avant : c.type_contrat?.startsWith('CDD') || c.type_contrat === 'SALARIE'\n */"],
    ['URL et motif de fichier', "const a = 'https://x.invalid//CDD'; const b = 'image/*'; const c = ['CDD'];"],
  ])('laisse passer %s', (_cas, source) => {
    expect(violationsListeSalariee(source)).toEqual([]);
  });
});

describe('garde — aucune liste salariée locale dans src/', () => {
  const racineDepot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const fichiers = (dossier: string): string[] => readdirSync(dossier).flatMap(nom => {
    const chemin = join(dossier, nom);
    if (statSync(chemin).isDirectory()) return nom === '__tests__' ? [] : fichiers(chemin);
    return /\.(ts|tsx)$/.test(nom) && !/\.(test|spec)\.(ts|tsx)$/.test(nom) ? [chemin] : [];
  });
  const sources = fichiers(join(racineDepot, 'src'))
    .map(chemin => ({ chemin: relative(racineDepot, chemin).split('\\').join('/'), texte: readFileSync(chemin, 'utf8') }))
    .filter(s => !['src/lib/typesContrat.ts', 'src/integrations/supabase/types.ts'].includes(s.chemin));

  it('ne trouve aucune règle salariée locale hors liste blanche', () => {
    const trouvees = sources.flatMap(({ chemin, texte }) => {
      const blanches = LISTE_BLANCHE.filter(b => b.fichier === chemin).map(b => b.extrait);
      return violationsListeSalariee(texte).filter(v => !blanches.includes(v)).map(v => `${chemin} : ${v}`);
    });
    expect(trouvees).toEqual([]);
  });

  it.each(LISTE_BLANCHE)('liste blanche à jour : $fichier ($motif)', ({ fichier, extrait, occurrences }) => {
    const source = sources.find(s => s.chemin === fichier);
    expect(source?.texte).toContain('data-jolene-cdd');
    expect(violationsListeSalariee(source?.texte ?? '').filter(v => v === extrait)).toHaveLength(occurrences);
  });

  it.each([
    'src/components/DPAEStatus.tsx',
    'src/components/BandeauRappelDPAE.tsx',
    'src/pages/ContratMission.tsx',
    'src/pages/admin/AdminDetailContrat.tsx',
    'src/pages/admin/AdminContrats.tsx',
    'src/lib/preferencesModesExercice.ts',
  ])('%s lit la source unique', chemin => {
    const source = sources.find(s => s.chemin === chemin);
    expect(source?.texte).toContain("from '@/lib/typesContrat'");
    expect(source?.texte).toContain('estContratSalarie(');
  });
});
