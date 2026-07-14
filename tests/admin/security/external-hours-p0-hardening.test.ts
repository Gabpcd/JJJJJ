import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read(
  'supabase/migrations/20260714069000_securiser_heures_externes_p0.sql',
);
const edge = read('supabase/functions/verify-heures-externes/index.ts');
const hook = read('src/hooks/useParcoursLiberal.ts');
const adminUi = read('src/pages/admin/AdminHeuresExternes.tsx');
const formUi = read('src/components/parcours-liberal/FormulaireHeuresExternes.tsx');

describe('heures externes — écriture et provenance P0', () => {
  it('retire les écritures client et force une déclaration RPC avec preuve Storage exacte', () => {
    expect(migration).toContain(
      'REVOKE INSERT, UPDATE, DELETE\n  ON public.heures_externes_soignants FROM authenticated',
    );
    expect(migration).toContain('fn_proteger_heures_externes_soignants');
    expect(migration).toContain("o.bucket_id = 'jolene-documents'");
    expect(migration).toContain('o.name = p_attestation_url');
    expect(migration).toContain('o.owner_id = v_uid::text');
    expect(migration).toContain("THEN (o.metadata ->> 'size')::numeric > 0");
    expect(migration).toContain("'statut', 'EN_ATTENTE'");
    expect(hook).toContain("supabase.rpc(\n        'fn_declarer_heures_externes_soignant'");
    expect(hook).not.toContain("from('heures_externes_soignants' as any)\n        .insert");
  });

  it('sérialise chemin et période et refuse le cumul de preuve binaire', () => {
    expect(migration).toContain("hashtextextended('heures-path:' || p_attestation_url, 0)");
    expect(migration).toContain("hashtextextended('heures-soignant:' || v_uid::text, 0)");
    expect(migration).toContain("error_code', 'PERIODE_CHEVAUCHANTE'");
    expect(migration).toContain('uq_heures_externes_preuve_validee');
    expect(migration).toContain("error_code', 'PREUVE_DUPLIQUEE'");
    expect(migration).toContain("error_code', 'PERIODE_DEJA_VALIDEE'");
  });

  it('finalise côté service_role sur le snapshot complet sans branche auto-VALIDE', () => {
    expect(migration).toContain('fn_service_finaliser_heures_externes');
    expect(migration).toContain("auth.jwt() ->> 'role'");
    expect(migration).toContain("current_setting('request.jwt.claim.role', true)");
    expect(migration).toContain('TO service_role;');
    expect(migration).toContain('p_snapshot_source IS DISTINCT FROM v_snapshot');
    expect(migration).toContain('FOR UPDATE');
    expect(migration).toContain("p_verdict NOT IN ('EN_ATTENTE', 'REJETE')");
    expect(migration).toContain('Le verdict automatique ne peut jamais être VALIDE');
    expect(edge).toContain('fn_service_finaliser_heures_externes');
    expect(edge).toContain('const empreintePreuve = await sha256Hex(bytes)');
    expect(edge).not.toMatch(/\.from\("heures_externes_soignants"\)\.update\(/);
    expect(edge).not.toContain('statut = "VALIDE"');
    expect(edge).toContain('Validation humaine requise');
  });

  it('exige AAL2/RBAC, un CAS et une provenance courante avant comptage', () => {
    expect(migration).toContain("COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'");
    expect(migration).toContain('OR NOT public.est_admin_valide()');
    expect(migration).toContain('h.version_source = v_ligne.version_source');
    expect(migration).toContain('private.fn_empreinte_snapshot_heures_externes(h) = v_empreinte_snapshot');
    expect(migration).toContain(
      "h.source_validation_serveur IN ('ADMIN_AAL2', 'ADMIN_LEGACY_AUDITE')",
    );
    expect(migration).toContain(
      'h.empreinte_snapshot_source =\n        private.fn_empreinte_snapshot_heures_externes(h)',
    );
  });

  it('écrit des actions d’audit autorisées sans wrapper qui avale les erreurs', () => {
    expect(migration).toContain("'HEURES_EXTERNES_DECLAREES'");
    expect(migration).toContain("'VERIFICATION_DOCUMENT'");
    expect(migration).toContain("'HEURES_EXTERNES_VALIDATION_MANUELLE'");
    expect(migration).toContain('INSERT INTO public.journaux_audit');
    expect(migration).not.toContain('fn_ecrire_audit_safe');
    expect(edge).not.toContain('HEURES_EXTERNES_VERIFICATION_AUTO');
  });

  it('préserve les lignes historiques sans attestation hebdomadaire ni suppression', () => {
    expect(migration).toContain("source_validation_serveur = 'ADMIN_LEGACY_AUDITE'");
    expect(migration).toContain("j.action = 'HEURES_EXTERNES_VALIDATION_MANUELLE'");
    expect(migration).toContain("admin_historique.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'");
    expect(migration).not.toMatch(/DELETE\s+FROM\s+public\.heures_externes_soignants/i);
    expect(migration).not.toContain('attestation_hebdomadaire');
    expect(migration).not.toContain('pg_cron');
  });

  it('n’annonce jamais une validation IA automatique dans les interfaces', () => {
    expect(adminUi).toContain('toute validation comptabilisée exige votre décision humaine');
    expect(adminUi).not.toContain('valide automatiquement');
    expect(formUi).toContain('validation humaine requise avant comptabilisation');
    expect(formUi).not.toContain('Attestation validée automatiquement');
    expect(formUi).not.toMatch(/res\.verdict === 'VALIDE'/);
  });
});
