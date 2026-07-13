import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260713225000_durcir_atomicite_verifications_etablissement.sql',
  'utf8',
);

const edge = (name: string) => readFileSync(
  `supabase/functions/${name}/index.ts`,
  'utf8',
);

function rpcBody(name: string): string {
  const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  expect(start, `${name} doit exister`).toBeGreaterThanOrEqual(0);
  const end = migration.indexOf('\n$$;', start);
  expect(end, `${name} doit être fermé`).toBeGreaterThan(start);
  return migration.slice(start, end + 4);
}

describe('établissement — verdicts externes atomiques et anti-TOCTOU', () => {
  it('versionne chaque UPDATE sans accepter une version fournie par le client', () => {
    expect(migration).toContain(
      'ADD COLUMN IF NOT EXISTS verification_source_version bigint NOT NULL DEFAULT 0',
    );
    expect(migration).toContain(
      'NEW.verification_source_version := OLD.verification_source_version + 1',
    );
    expect(migration).toContain(
      'REVOKE UPDATE (verification_source_version) ON public.etablissements FROM anon, authenticated',
    );
    expect(migration).toContain(
      'CREATE TRIGGER trg_00_versionner_verifications_etablissement',
    );
  });

  it.each([
    'fn_appliquer_verification_identite_etablissement',
    'fn_appliquer_verification_fonction_etablissement',
    'fn_appliquer_verification_rib_etablissement',
    'fn_appliquer_verification_contrat_etablissement',
    'fn_appliquer_verification_siret_etablissement',
    'fn_appliquer_verification_finess_etablissement',
  ])('%s verrouille, compare la version et échoue fermé', (name) => {
    const sql = rpcBody(name);
    expect(sql).toContain("<> 'service_role'");
    expect(sql).toContain('FOR UPDATE');
    expect(sql).toContain(
      'v_etab.verification_source_version IS DISTINCT FROM p_version_attendue',
    );
    expect(sql).toContain('RETURN false');
    expect(sql).toContain('RETURN true');
  });

  it('lie chaque verdict documentaire à tous les champs utilisés pour le calcul', () => {
    const identite = rpcBody('fn_appliquer_verification_identite_etablissement');
    for (const field of [
      'representant_piece_s3_key',
      'representant_piece_type_mime',
      'representant_piece_type_document',
      'representant_nom',
      'representant_prenom',
    ]) expect(identite).toContain(`v_etab.${field} IS DISTINCT FROM`);

    const fonction = rpcBody('fn_appliquer_verification_fonction_etablissement');
    for (const field of [
      'justificatif_fonction_s3_key',
      'justificatif_fonction_type',
      'justificatif_fonction_type_mime',
      'representant_nom',
      'representant_prenom',
      'nom',
      'siret',
      'siret_raison_sociale',
      'finess_raison_sociale',
    ]) expect(fonction).toContain(`v_etab.${field} IS DISTINCT FROM`);

    const rib = rpcBody('fn_appliquer_verification_rib_etablissement');
    for (const field of [
      'rib_s3_key',
      'nom',
      'siret_raison_sociale',
      'finess_raison_sociale',
    ]) expect(rib).toContain(`v_etab.${field} IS DISTINCT FROM`);

    const contrat = rpcBody('fn_appliquer_verification_contrat_etablissement');
    for (const field of [
      'contrat_url',
      'nom',
      'siret',
      'siret_raison_sociale',
      'finess_raison_sociale',
      'representant_nom',
      'representant_prenom',
    ]) expect(contrat).toContain(`v_etab.${field} IS DISTINCT FROM`);
  });

  it('remplace le FINESS et son verdict sous le même verrou transactionnel', () => {
    const finess = rpcBody('fn_appliquer_verification_finess_etablissement');
    expect(finess).toContain('v_etab.finess IS DISTINCT FROM p_finess_source_attendu');
    expect(finess).toContain('IF v_etab.finess IS DISTINCT FROM p_finess_nouveau THEN');
    expect(finess).toContain('SET finess = p_finess_nouveau');
    expect(finess).toContain('SET finess_verifie = COALESCE(p_verifie, false)');
  });

  it.each([
    ['verify-piece-identite-etab', 'fn_appliquer_verification_identite_etablissement'],
    ['verify-justificatif-fonction', 'fn_appliquer_verification_fonction_etablissement'],
    ['verify-rib-etablissement', 'fn_appliquer_verification_rib_etablissement'],
    ['verify-contrat-etablissement', 'fn_appliquer_verification_contrat_etablissement'],
    ['verify-siret', 'fn_appliquer_verification_siret_etablissement'],
    ['verify-finess', 'fn_appliquer_verification_finess_etablissement'],
  ])('%s transmet le snapshot à sa RPC atomique', (name, rpc) => {
    const source = edge(name);
    expect(source).toContain('verification_source_version');
    expect(source).toContain(rpc);
    expect(source).toContain('p_version_attendue');
    expect(source).toContain('VERIFICATION_SOURCE_CHANGED');
  });

  it('prend les snapshots SIRET/FINESS avant les appels aux registres', () => {
    const siret = edge('verify-siret');
    expect(siret.indexOf(".select('verification_source_version, siret')"))
      .toBeLessThan(siret.indexOf('fetch(rechercheUrl'));

    const finess = edge('verify-finess');
    expect(finess.indexOf('verification_source_version, nom, finess, siret'))
      .toBeLessThan(finess.indexOf('result = await queryFiness'));
  });

  it('ne réécrit plus directement les verdicts IA établissement', () => {
    for (const name of [
      'verify-piece-identite-etab',
      'verify-justificatif-fonction',
      'verify-rib-etablissement',
      'verify-contrat-etablissement',
    ]) {
      const source = edge(name);
      expect(source).not.toMatch(/from\(["']etablissements["']\)\.update\(/);
    }
  });

  it('refuse les chemins identité/fonction hors établissement ou utilisateur appelant', () => {
    for (const name of ['verify-piece-identite-etab', 'verify-justificatif-fonction']) {
      const source = edge(name);
      const download = source.indexOf("storage.from('jolene-documents').download");
      expect(source).toContain('[etablissementId, auth.userId]');
      expect(source).toContain(".includes('..')");
      expect(source).toContain(".includes('\\\\')");
      expect(source).toContain('startsWith(`${ownerId}/`)');
      expect(source.indexOf('if (!cheminAutorise)')).toBeLessThan(download);
    }
  });

  it('garde register-etablissement sans fenêtre locale : résultats et profil sont insérés ensemble', () => {
    const register = edge('register-etablissement');
    const siretCall = register.indexOf('await querySiretInscription(siret)');
    const finessCall = register.indexOf('await queryFinessInscription(finess, finessApiKey)');
    const insert = register.indexOf(".from('etablissements')\n      .insert(insertPayload)");
    expect(siretCall).toBeGreaterThan(0);
    expect(finessCall).toBeGreaterThan(siretCall);
    expect(insert).toBeGreaterThan(finessCall);
    expect(register.slice(finessCall, insert)).not.toContain(".from('etablissements')");
  });
});
