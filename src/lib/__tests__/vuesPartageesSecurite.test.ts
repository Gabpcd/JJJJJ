import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const nomsVues = [
  'vue_soignants_etablissement',
  'vue_etablissements_soignant',
] as const;

function fichiersRecursifs(dossier: string): string[] {
  return readdirSync(dossier).flatMap((nom) => {
    const chemin = join(dossier, nom);
    return statSync(chemin).isDirectory() ? fichiersRecursifs(chemin) : [chemin];
  });
}

describe('suppression des vues de partage SECURITY DEFINER', () => {
  it('les supprime sans cascade dans la migration corrective', () => {
    const migration = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260713171136_supprimer_vues_partagees_inutilisees.sql',
      ),
      'utf8',
    );

    for (const vue of nomsVues) {
      expect(migration).toContain(`DROP VIEW IF EXISTS public.${vue} RESTRICT;`);
    }
    const suppressions = migration
      .split('\n')
      .filter((ligne) => ligne.startsWith('DROP VIEW'))
      .join('\n');
    expect(suppressions).not.toMatch(/\bCASCADE\b/i);
  });

  it('confirme qu’aucun code runtime ne consomme ces vues', () => {
    const racine = process.cwd();
    const dossiersRuntime = ['src', 'supabase/functions', 'scripts', 'e2e']
      .map((dossier) => resolve(racine, dossier));
    const references = dossiersRuntime
      .flatMap(fichiersRecursifs)
      .filter((fichier) => {
        if (fichier.endsWith('vuesPartageesSecurite.test.ts')) return false;
        const contenu = readFileSync(fichier, 'utf8');
        return nomsVues.some((vue) => contenu.includes(vue));
      });

    expect(references).toEqual([]);
  });
});
