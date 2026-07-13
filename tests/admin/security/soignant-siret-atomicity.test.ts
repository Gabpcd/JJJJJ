import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const edge = readFileSync(
  'supabase/functions/verify-siret/index.ts',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260713228000_durcir_atomicite_siret_soignant.sql',
  'utf8',
);

describe('SIRET libéral soignant — identité atomique', () => {
  it('refuse une vérification sans date de naissance', () => {
    expect(edge).toContain('if (!dateProfil) return false');
    expect(edge).toContain('if (!soignant.date_naissance)');
    expect(edge).toContain("code: 'IDENTITE_INCOMPLETE'");
    expect(migration).toContain('p_expected_date_naissance IS NULL');
    expect(migration).toContain("USING ERRCODE = '22023'");
  });

  it('ne valide jamais un homonyme quand le registre ne publie ni date ni année de naissance', () => {
    expect(edge).toContain('if (!anneeOfficielle) return null');
    expect(edge).not.toContain('return !anneeOfficielle ||');
    expect(edge).toContain('identiteSansNaissanceOfficielle = true');
    expect(edge).toContain("code: 'IDENTITE_NON_CONFIRMABLE'");
    expect(edge).toContain('coherence_identite: null');
    expect(edge).toContain('return nomEiCorrespond ? null : false');
  });

  it('finalise via une RPC sous verrou au lieu d’une écriture directe', () => {
    expect(edge).toContain("'fn_appliquer_verification_siret_soignant'");
    expect(edge).toContain('p_expected_siret_liberal: soignant.siret_liberal');
    expect(edge).toContain('p_expected_date_naissance: soignant.date_naissance');
    expect(edge).toContain("code: 'VERIFICATION_SOURCE_CHANGED'");
    expect(edge).not.toMatch(
      /from\(['"]soignants['"]\)\.update\([\s\S]*?siret_liberal_verifie:\s*true/,
    );
    expect(migration).toContain('FOR UPDATE');
  });

  it('compare chaque trait ayant servi au rapprochement avant activation', () => {
    for (const comparison of [
      'v_soignant.prenom IS DISTINCT FROM p_expected_prenom',
      'v_soignant.nom IS DISTINCT FROM p_expected_nom',
      'v_soignant.date_naissance IS DISTINCT FROM p_expected_date_naissance',
      'v_soignant.siret_liberal IS DISTINCT FROM p_expected_siret_liberal',
      'v_soignant.statut_liberal IS DISTINCT FROM p_expected_statut_liberal',
      'v_soignant.type_contrat IS DISTINCT FROM p_expected_type_contrat',
    ]) {
      expect(migration).toContain(comparison);
    }
    expect(migration).toContain('RETURN false');
    expect(migration).toContain('siret_liberal_coherence_identite = true');
  });

  it('réserve la finalisation au service role', () => {
    expect(migration).toContain("<> 'service_role'");
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_appliquer_verification_siret_soignant\([\s\S]*FROM PUBLIC, anon, authenticated;/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_appliquer_verification_siret_soignant\([\s\S]*TO service_role;/,
    );
  });
});
