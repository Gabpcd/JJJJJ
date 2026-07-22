import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714072000_securiser_file_revue_manuelle_admin.sql',
  'utf8',
);
const page = readFileSync('src/pages/admin/AdminRevuesManuelles.tsx', 'utf8');
const app = readFileSync('src/App.tsx', 'utf8');
const navigation = readFileSync('src/lib/adminNavigation.ts', 'utf8');
const siretEdge = readFileSync('supabase/functions/verify-siret/index.ts', 'utf8');
const workflow = readFileSync('.github/workflows/validate-pr.yml', 'utf8');

describe('file admin de revue manuelle durable', () => {
  it('n’expose que des RPC AAL2, admin valide et une projection minimale', () => {
    expect(migration).toContain("auth.jwt() ->> 'aal'");
    expect(migration.match(/public\.est_admin_valide\(\)/g)?.length).toBeGreaterThanOrEqual(2);
    expect(migration).toContain('REVOKE ALL ON TABLE public.file_revue_manuelle FROM anon, authenticated');
    expect(migration).toContain('REVOKE ALL ON TABLE private.revue_manuelle_decisions');
    expect(migration).toContain('fn_admin_lister_revues_manuelles');
    expect(migration).not.toContain('raw_user_meta_data');
  });

  it('ferme les courses avec verrou, jeton CAS et verdict idempotent unique', () => {
    expect(migration).toContain('revue_id uuid PRIMARY KEY');
    expect(migration).toContain('FOR UPDATE');
    expect(migration).toContain('fn_jeton_cas_revue_manuelle');
    expect(migration).toContain("USING ERRCODE = '40001'");
    expect(migration).toContain("'idempotent', true");
    expect(migration).toContain("statut = 'RESOLU_MANUELLEMENT'");
  });

  it('traite uniquement les trois trous et redirige les workflows spécialisés', () => {
    for (const service of [
      'VERIFY_RIB_ETABLISSEMENT',
      'VERIFY_FINESS_RECOUPEMENT',
      'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE',
    ]) {
      expect(migration).toContain(service);
      expect(page).toContain(service);
    }
    expect(migration).toContain('workflow specialise');
    expect(migration).toContain("'/admin/moderation?onglet=documents'");
    expect(migration).toContain("'/admin/verification-etablissements'");
    expect(migration).toContain("'/admin/heures-externes'");
    expect(migration.indexOf("f.service_en_echec ILIKE '%HEURES%'"))
      .toBeLessThan(migration.indexOf(
        "WHEN f.type_entite = 'SOIGNANT'\n          THEN '/admin/utilisateurs/'",
      ));
  });

  it('lie les verdicts aux preuves courantes et journalise dans l’allowlist', () => {
    expect(migration).toContain('verification_source_version_apres_verdict');
    expect(migration).toContain('rib_verifie_s3_key');
    expect(migration).toContain('rib_verifie_source_version');
    expect(migration).toContain("FROM storage.objects o");
    expect(migration).toContain("v_rib_sha256, '') !~ '^[0-9a-f]{64}$'");
    expect(migration).toContain('storage_object_id');
    expect(migration).toContain('donnees_officielles_candidat');
    expect(migration).toContain("statut_verification = 'EN_COURS'");
    expect(migration).toContain('peut_publier_missions = false');
    expect(migration).toContain('profil_modifie_le');
    expect(migration).toContain('preuve_identite_document_id');
    expect(migration).toContain('siret_liberal_preuve_identite_document_id');
    expect(migration).toContain("siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'");
    expect(migration).toContain('siret_liberal_preuve_siret = v_siret_candidat');
    expect(migration).toContain('d.revoque_le IS NULL');
    expect(migration).toContain('d.valide_jusqua > current_date');
    expect(migration).toContain('v_identite_object_id');
    expect(migration).toContain('v_identite_object_updated_at');
    expect(migration).toContain('fn_empreinte_preuve_identite_siret');
    expect(migration).toContain('fn_preuve_identite_siret_manuelle_courante');
    expect(migration).toContain('trg_invalider_preuve_siret_identite_update');
    expect(migration).toContain('trg_invalider_preuve_siret_identite_delete');
    expect(migration).toContain('SIRET_LIBERAL_PREUVE_IDENTITE_OBSOLETE');
    expect(migration).toContain("siret_liberal_source_verification = 'REGISTRE_OFFICIEL'");
    expect(migration).toContain("v_soignant.coherence_identite IS DISTINCT FROM 'COHERENT'");
    expect(migration).toContain("v_soignant.coherence_details ->> 'document_id'");
    expect(migration).toContain("'ADMIN_ACTION'");
    expect(migration).toContain("'DECISION_REVUE_MANUELLE'");
    expect(migration).not.toContain("p_action := 'DECISION_REVUE_MANUELLE'");
  });

  it('enrichit le snapshot SIRET officiel avant toute décision humaine', () => {
    expect(siretEdge).toContain('profil_modifie_le: soignant.modifie_le');
    expect(siretEdge).toContain('raison_sociale_officielle: result.raison_sociale');
    expect(siretEdge).toContain('siret_officiel_actif: result.est_actif');
    expect(siretEdge).toContain('activite_officielle_sante: result.est_sante');
  });

  it('rend l’interface accessible, fail-closed et raccordée', () => {
    expect(page).toContain('setRevues([])');
    expect(page).toContain('erreurChargement ?');
    expect(page).toContain('role="alert"');
    expect(page).toContain('Réessayer');
    expect(page).toContain("window.open('about:blank', '_blank')");
    expect(page).toContain('preview.opener = null');
    expect(page).toContain('createSignedUrl');
    expect(page).toContain('min-h-[44px]');
    expect(page).toContain('Donnée de test');
    expect(migration).toContain('est_compte_test');
    expect(app).toContain('path="/admin/revues-manuelles"');
    expect(navigation).toContain("route: '/admin/revues-manuelles'");
    expect(workflow).toContain('tests/admin/security/manual-review-admin-queue.test.sql');
  });

  it('isole chaque recette SQL dans son propre savepoint', () => {
    expect(workflow).toContain('savepoint="jolene_sql_test_${test_index}"');
    expect(workflow).toContain("printf 'SAVEPOINT %s;\\n' \"$savepoint\"");
    expect(workflow).toContain(
      "printf 'ROLLBACK TO SAVEPOINT %s;\\n' \"$savepoint\"",
    );
    expect(workflow).toContain(
      "printf 'RELEASE SAVEPOINT %s;\\n' \"$savepoint\"",
    );
  });
});
