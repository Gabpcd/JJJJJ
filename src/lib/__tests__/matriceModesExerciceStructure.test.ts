import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260712161000_finaliser_matrice_modes_exercice.sql'),
  'utf8',
);
const constantes = readFileSync(resolve(process.cwd(), 'src/lib/constantes.ts'), 'utf8');
const formulaire = readFileSync(resolve(process.cwd(), 'src/components/FormulaireMission.tsx'), 'utf8');

describe('encodage table des modes d’exercice', () => {
  it('résout la mission depuis profession_requise et la table', () => {
    expect(migration).toContain('NEW.profession_requise::text');
    expect(migration).toContain('public.fn_mode_exercice(');
    expect(migration).toContain("v_mode->>'niveau' <> 'AUTORISE'");
  });

  it('applique le défaut NON_PROPOSE et ne seede aucune cellule publique', () => {
    expect(migration).toContain("'niveau', 'NON_PROPOSE'");
    expect(migration).toContain('aucune cellule "public"');
    expect(migration).not.toMatch(/ARRAY\[[^\]]*'public'[^\]]*\]\s+c;/);
  });

  it('contient les wordings validés avec leur force de source', () => {
    expect(migration).toContain("Conseil d''État, 11/02/2025, n°491128");
    expect(migration).toContain('lettre interministérielle du 30 décembre 2021, n° D21-031940');
    expect(migration).toContain('art. L.6323-1-5 du code de la santé publique');
    expect(migration).toContain("'JUGE'");
    expect(migration).toContain("'DOCTRINE'");
    expect(migration).toContain("'CONFORMITE_JOLENE'");
  });

  it('supprime la matrice juridique TypeScript en dur', () => {
    expect(constantes).not.toContain('LIBERAL_COMPATIBILITY');
    expect(constantes).not.toContain('PROFESSIONS_NON_LIBERAL');
    expect(constantes).not.toContain('peutExercerLiberal');
    expect(formulaire).toContain('useModeExerciceMission');
    expect(formulaire).toContain('modeExerciceMission.source_libelle');
  });
});
