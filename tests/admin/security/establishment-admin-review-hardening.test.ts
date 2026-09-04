import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../..');
const migration = readFileSync(
  resolve(root, 'supabase/migrations/20260714063000_securiser_revue_etablissements.sql'),
  'utf8',
);
const adminPage = readFileSync(
  resolve(root, 'src/pages/admin/AdminVerificationEtablissements.tsx'),
  'utf8',
);
const finalizer = readFileSync(
  resolve(root, 'supabase/functions/finalize-etablissement-proof-upload/index.ts'),
  'utf8',
);
const identityVerifier = readFileSync(
  resolve(root, 'supabase/functions/verify-piece-identite-etab/index.ts'),
  'utf8',
);

describe('revue admin établissement durcie', () => {
  it('conserve dans la file les dossiers automatiquement rattachés mais non finalisés', () => {
    expect(migration).toContain("COALESCE(e.statut_verification, 'EN_ATTENTE') IN ('EN_ATTENTE', 'EN_COURS')");
    expect(migration).not.toMatch(/COALESCE\(e\.rattachement_verifie,\s*false\)\s*=\s*false/);
    expect(adminPage).toContain('y compris les dossiers dont le rattachement automatique est déjà prêt');
  });

  it('impose AAL2, RBAC, CAS et audit aux décisions par preuve', () => {
    expect(migration).toContain('fn_admin_decider_preuve_etablissement');
    expect(migration).toContain("COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'");
    expect(migration).toContain('NOT public.est_admin_valide()');
    expect(migration).toContain('verification_source_version IS DISTINCT FROM p_version_attendue');
    expect(migration).toContain('v_source_s3_key IS DISTINCT FROM p_source_s3_key_attendue');
    expect(migration).toContain('INSERT INTO public.etablissement_preuve_audit');
    expect(migration).toContain("'source_snapshot', v_snapshot");
  });

  it('sépare les décisions identité/fonction de la finalisation globale', () => {
    expect(adminPage).toContain("demanderDecisionPreuve(etab, 'IDENTITE', 'APPROUVER')");
    expect(adminPage).toContain("demanderDecisionPreuve(etab, 'FONCTION', 'REJETER')");
    expect(adminPage).toContain('executer: () => deciderPreuve(etab, preuve, decision)');
    expect(adminPage).toContain('fn_admin_finaliser_verification_etablissement');
    expect(adminPage).toContain('disabled={!peutFinaliser || actionKey !== null}');
    expect(migration).toContain('Recalcule toujours le rattachement');
  });

  it('recoupe la naissance pièce-registre et bloque une divergence', () => {
    expect(identityVerifier).toContain('"date_naissance": "YYYY-MM-DD" ou null');
    expect(identityVerifier).toContain('date_naissance_extraite: dateNaissance');
    expect(migration).toContain('private.fn_rapprocher_naissance_representant');
    expect(migration).toContain("IN ('DIVERGE', 'PIECE_NON_LUE')");
    expect(adminPage).toContain('Date pièce ↔ registre');
  });

  it('nettoie le bon blob autour de la transaction de remplacement', () => {
    const rpcPosition = finalizer.indexOf("admin.rpc('fn_remplacer_preuve_etablissement'");
    const cleanupNewPosition = finalizer.indexOf('const nettoyee = await nettoyerNouvellePreuve()', rpcPosition);
    const cleanupOldPosition = finalizer.indexOf(".remove([ancienneCle])", rpcPosition);
    expect(rpcPosition).toBeGreaterThan(0);
    expect(cleanupNewPosition).toBeGreaterThan(rpcPosition);
    expect(cleanupOldPosition).toBeGreaterThan(rpcPosition);
    expect(migration).toContain("p_preuve, 'REMPLACEMENT'");
  });
});
