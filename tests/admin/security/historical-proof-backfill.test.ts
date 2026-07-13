import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713224000_revalider_preuves_historiques_reelles.sql'),
  'utf8',
);

describe('revalidation des preuves historiques', () => {
  it('préserve explicitement les deux comptes utilisés pour les captures stores', () => {
    expect(migration).toContain("lower(u.email) = 'marie.lefevre@jolene-demo.dev'");
    expect(migration).toContain("lower(u.email) = 'etab@jolene.app'");
    expect(migration.match(/SET est_compte_test = true/g)).toHaveLength(2);
    expect(migration).toContain('DISABLE TRIGGER trg_invalider_verifications_etablissement');
    expect(migration).toContain('ENABLE TRIGGER trg_invalider_verifications_etablissement');
    expect(migration).toContain('DISABLE TRIGGER trg_auto_valider_etablissement');
    expect(migration).toContain('ENABLE TRIGGER trg_auto_valider_etablissement');
  });

  it('exclut les comptes test de chaque déclassement de preuve', () => {
    expect(migration.match(/COALESCE\([es]\.est_compte_test, false\) IS FALSE/g)).toHaveLength(3);
  });

  it('ne supprime ni compte ni document', () => {
    expect(migration).not.toMatch(/\bDELETE\s+FROM\b/i);
    expect(migration).not.toMatch(/\bTRUNCATE\b/i);
  });

  it('dérive le contrôle d’identité du type de preuve sans imposer un prénom aux documents corporate', () => {
    const identityGate = migration.match(
      /ds\.type_document(?:::text)? IN \([\s\S]*?'CERTIFICAT_TRAVAIL'[\s\S]*?AND \([\s\S]*?ds\.coherence_nom IS NOT TRUE[\s\S]*?\n\s*\)/,
    )?.[0];

    expect(identityGate).toBeDefined();
    expect(identityGate).not.toContain("'RIB'");
    expect(identityGate).not.toContain("'KBIS'");
    expect(identityGate).not.toContain("'ATTESTATION_URSSAF'");
    expect(identityGate).not.toContain("'RCP_ASSURANCE'");
    expect(identityGate).not.toContain("'NOTE_HONORAIRES'");
  });

  it('conserve la compatibilité diplôme IDE prouvée par une spécialisation IADE ou IBODE', () => {
    expect(migration).toContain("s.profession = 'IDE'");
    expect(migration).toContain("IN ('IADE', 'IBODE')");
    expect(migration).not.toContain("s.profession IN ('IADE', 'IBODE')");
  });

  it('compare chaque attestation au registre qu’elle annonce, même si les deux numéros existent', () => {
    expect(migration).toContain("WHEN 'RPPS' THEN COALESCE(s.numero_rpps, '')");
    expect(migration).toContain("WHEN 'ADELI' THEN COALESCE(s.numero_adeli, '')");
    expect(migration).not.toContain('COALESCE(s.numero_rpps, s.numero_adeli');
  });

  it('révoque les anciens droits étudiant/licence et recalcule seulement les comptes réels', () => {
    expect(migration).toContain("ds.type_document::text = 'ATTESTATION_SCOLARITE'");
    expect(migration).toContain("ds.type_document::text = 'LICENCE_REMPLACEMENT'");
    expect(migration).toContain("COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'");
    expect(migration).toContain('PERFORM public.fn_recalculer_preuves_etudiant(v_soignant_id)');
    expect(migration).toContain('WHERE s.est_compte_test IS FALSE');
  });
});
