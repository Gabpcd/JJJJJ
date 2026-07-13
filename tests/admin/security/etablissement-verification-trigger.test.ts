import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260713222000_durcir_verifications_preproduction.sql',
  'utf8',
);

function functionBody(name: string): string {
  const start = migration.lastIndexOf(`CREATE OR REPLACE FUNCTION public.${name}`);
  expect(start, `${name} doit être défini dans la migration`).toBeGreaterThanOrEqual(0);
  const end = migration.indexOf('\n$$;', start);
  expect(end, `${name} doit avoir un corps SQL fermé`).toBeGreaterThan(start);
  return migration.slice(start, end + 4);
}

describe('établissement — remplacement sûr des sources de vérification', () => {
  it('retire tout EXECUTE implicite aux fonctions SECURITY DEFINER de trigger', () => {
    for (const signature of [
      'fn_proteger_verification_siret_liberal()',
      'fn_proteger_ecriture_document_soignant()',
      'fn_verrouiller_reference_justificatif()',
      'fn_invalider_verifications_etablissement()',
    ]) {
      expect(migration).toMatch(new RegExp(
        `REVOKE ALL ON FUNCTION public\\.${signature.replace(/[()]/g, '\\$&')}\\s+FROM PUBLIC, anon, authenticated;`,
        'i',
      ));
    }
  });

  it('normalise les sources avant le protector selon l’ordre des triggers PostgreSQL', () => {
    const invalidatorTrigger = migration.indexOf(
      'CREATE TRIGGER trg_invalider_verifications_etablissement',
    );
    const protectorDefinition = migration.lastIndexOf(
      'CREATE OR REPLACE FUNCTION public.fn_protect_etablissement_commercial',
    );

    expect(invalidatorTrigger).toBeGreaterThan(0);
    expect(protectorDefinition).toBeGreaterThan(invalidatorTrigger);
    expect('trg_invalider_verifications_etablissement'.localeCompare(
      'trg_protect_etablissement_commercial',
    )).toBeLessThan(0);
  });

  it('révoque chaque verdict documentaire et le droit de publication', () => {
    const invalidator = functionBody('fn_invalider_verifications_etablissement()');

    for (const token of [
      'v_identite_changee',
      'v_justificatif_change',
      'v_rib_change',
      'v_contrat_change',
      'v_finess_change',
      'v_siret_change',
      'NEW.representant_identite_verifiee := false',
      'NEW.justificatif_fonction_verifie := false',
      'NEW.rib_ia_resultat := NULL',
      'NEW.contrat_valide := false',
      'NEW.finess_verifie := false',
      'NEW.siret_verifie := false',
      'NEW.peut_publier_missions := false',
      "WHEN OLD.statut_verification IN ('VERIFIE', 'REJETE') THEN 'EN_COURS'",
    ]) {
      expect(invalidator).toContain(token);
    }
  });

  it('protège verdicts, résultats, dates et statut avant tout bypass interne', () => {
    const protector = functionBody('fn_protect_etablissement_commercial()');
    const internalMarker = protector.indexOf("current_setting('app.internal_operation'");
    const verificationGuard = protector.indexOf(
      "Écriture directe du verdict identité interdite",
    );

    expect(verificationGuard).toBeGreaterThan(0);
    expect(internalMarker).toBeGreaterThan(verificationGuard);
    for (const field of [
      'representant_identite_verifiee',
      'representant_identite_resultat_ia',
      'justificatif_fonction_verifie',
      'justificatif_fonction_resultat_ia',
      'rib_ia_coherent',
      'rib_ia_verifie_le',
      'contrat_valide',
      'contrat_ia_resultat',
      'finess_verifie',
      'finess_verifie_le',
      'siret_verifie',
      'siret_verifie_le',
      'rattachement_verifie',
      'statut_verification',
      'peut_publier_missions',
      'contrat_service_signe',
      'contrat_service_signe_le',
    ]) {
      expect(protector).toContain(`NEW.${field}`);
      expect(protector).toContain(`OLD.${field}`);
    }
    expect(protector).toContain('v_rattachement_invalide :=');
    expect(protector).toContain('IF v_rattachement_invalide THEN');
  });

  it('lie le contrat de service à la preuve active sans GUC client', () => {
    const signer = functionBody(
      'fn_signer_contrat_service(\n  p_version text,',
    );
    const revoker = functionBody('fn_revoquer_contrat_service(p_motif text)');
    const protector = functionBody('fn_protect_etablissement_commercial()');

    expect(signer).toContain('RETURNING signed_at INTO v_signature_le');
    expect(signer).toContain('contrat_service_signe_le = v_signature_le');
    expect(signer).not.toContain("set_config('app.internal_operation'");
    expect(revoker).not.toContain("set_config('app.internal_operation'");
    expect(protector).toContain('WHERE etablissement_id = NEW.id AND revoked_at IS NULL');
    expect(protector).toContain("État du contrat de service sans preuve active");
    expect(protector).toContain("Révocation de rattachement non canonique");
    expect(protector).toContain(
      "WHEN NOT v_source_changee\n              AND OLD.statut_verification = 'VERIFIE' THEN 'EN_COURS'",
    );
  });
});
