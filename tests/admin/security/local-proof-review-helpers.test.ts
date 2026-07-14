import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migrationPath =
  'supabase/migrations/20260714066000_helpers_revue_et_revocation.sql';
const migration = readFileSync(migrationPath, 'utf8');
const supabaseConfig = readFileSync('supabase/config.toml', 'utf8');
const outsideFunctionBodies = migration
  .split('$$')
  .filter((_, index) => index % 2 === 0)
  .join('\n');

function functionBlock(name: string): string {
  const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}`);
  const end = migration.indexOf('\n$$;', start);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(end).toBeGreaterThan(start);
  return migration.slice(start, end + 4);
}

describe('helpers locaux de revue et de révocation', () => {
  it('ne crée aucune revalidation automatique ni cible réseau', () => {
    expect(migration).not.toContain('revalidations_statuts_officiels');
    expect(migration).not.toContain('cron.schedule');
    expect(migration).not.toContain('net.http_post');
    expect(migration).not.toContain('supabase.co');
    expect(migration).not.toContain('CREATE TABLE');
    expect(outsideFunctionBodies).not.toMatch(/\b(INSERT|UPDATE|DELETE)\s+public\.[a-z_]+/i);

    expect(existsSync('supabase/functions/revalidate-official-statuses/index.ts')).toBe(false);
    expect(existsSync('supabase/functions/_shared/official-revalidation.ts')).toBe(false);
    expect(existsSync(
      'supabase/migrations/20260714066000_revalider_statuts_officiels_periodiquement.sql',
    )).toBe(false);
    expect(supabaseConfig).not.toContain('[functions.revalidate-official-statuses]');
  });

  it.each([
    'fn_ouvrir_revue_verification_etablissement',
    'fn_resoudre_revue_verification_etablissement',
    'fn_ouvrir_revue_siret_liberal_soignant',
    'fn_revoquer_siret_liberal_soignant',
  ])('%s reste strictement réservé au service', (name) => {
    const block = functionBlock(name);
    expect(block).toContain('SECURITY DEFINER');
    expect(block).toContain("<> 'service_role'");
    expect(block).toContain("session_user NOT IN ('postgres', 'supabase_admin')");
    expect(migration).toMatch(
      new RegExp(
        `REVOKE ALL ON FUNCTION public\\.${name}\\([\\s\\S]*?FROM PUBLIC, anon, authenticated;`,
      ),
    );
    expect(migration).toMatch(
      new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${name}\\([\\s\\S]*?TO service_role;`),
    );
  });

  it('protège le rejet global par AAL2, RBAC, CAS et audit', () => {
    const block = functionBlock('fn_admin_rejeter_dossier_etablissement');
    expect(block).toContain('SECURITY DEFINER');
    expect(block).toContain("COALESCE(auth.jwt()->>'aal', '') IS DISTINCT FROM 'aal2'");
    expect(block).toContain('NOT public.est_admin_valide()');
    expect(block).toContain('verification_source_version IS DISTINCT FROM p_version_attendue');
    expect(block).toContain("peut_publier_missions = false");
    expect(block).toContain('INSERT INTO public.etablissement_preuve_audit');
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_admin_rejeter_dossier_etablissement\([\s\S]*?FROM PUBLIC, anon;/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_admin_rejeter_dossier_etablissement\([\s\S]*?TO authenticated;/,
    );
  });

  it('révoque un SIRET uniquement si le profil courant porte encore l’identifiant attendu', () => {
    const block = functionBlock('fn_revoquer_siret_liberal_soignant');
    expect(block).toContain('FOR UPDATE');
    expect(block).toContain('v_soignant.siret_liberal IS DISTINCT FROM p_siret_attendu');
    expect(block).toContain('siret_liberal_verifie = false');
    expect(block).toContain('tous_documents_valides = false');
    expect(block).toContain("'sous_action', 'REVOQUER_SIRET_LIBERAL'");
    expect(block).toContain("'siret_last4', right(p_siret_attendu, 4)");
    expect(block).toContain("v_audit @> '{\"success\": true}'::jsonb");
    expect(block).toContain('public.fn_calculer_tous_documents_valides(p_soignant_id)');
  });

  it('ouvre une revue SIRET idempotente sans révoquer une preuve sur absence de traits civils', () => {
    const block = functionBlock('fn_ouvrir_revue_siret_liberal_soignant');
    expect(block).toContain("v_code <> 'IDENTITE_NON_CONFIRMABLE'");
    expect(block).toContain('pg_advisory_xact_lock');
    expect(block).toContain("service_en_echec = 'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE'");
    expect(block).toContain("statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')");
    expect(block).not.toContain('UPDATE public.soignants');
  });
});
