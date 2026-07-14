import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(join(process.cwd(), path), 'utf8');

const migration = read(
  'supabase/migrations/20260714065000_securiser_documents_rib_et_demarrage_missions.sql',
);
const moderation = read(
  'supabase/migrations/20260714062000_securiser_moderation_documents_soignants.sql',
);
const establishmentReview = read(
  'supabase/migrations/20260714063000_securiser_revue_etablissements.sql',
);
const verifyDocument = read('supabase/functions/verify-document/index.ts');
const documentsUi = read('src/pages/DocumentsSoignant.tsx');
const hoursUi = read('src/components/ImportHeuresExternes.tsx');
const establishmentUi = read('src/pages/ActiverEtablissement.tsx');

describe('documents, RIB et TOCTOU de démarrage', () => {
  it('remplace une preuve atomiquement sans détruire son historique', () => {
    expect(migration).toContain('DROP TRIGGER IF EXISTS trg_05_bloquer_retrait_preuve_mission_active');
    expect(migration).not.toContain('uq_documents_soignants_preuve_courante');
    expect(migration).toContain('remplace_par_document_id = NEW.id');
    expect(migration).toContain('revoque_raison = \'REMPLACEMENT\'');
    expect(migration).toContain(
      "set_config('jolene.document_server_update', 'true', true)",
    );
    expect(migration).toContain('v_document_server_update_precedent');
    expect(migration).toContain('fn_remplacer_document_soignant');
    expect(migration).toContain("'error_code', 'DOCUMENT_INACTIF'");
    expect(documentsUi).toContain("supabase.rpc('fn_remplacer_document_soignant'");
    expect(documentsUi).not.toContain("from('documents_soignants').insert(");
  });

  it('rend la déclaration heures + justificatif transactionnelle', () => {
    expect(migration).toContain('fn_declarer_heures_externes_avec_document');
    expect(migration).toContain("PERFORM pg_advisory_xact_lock(hashtextextended('heures:'");
    expect(hoursUi).toContain("supabase.rpc('fn_declarer_heures_externes_avec_document'");
    expect(hoursUi).not.toContain("from('heures_externes').insert(");
    expect(hoursUi).not.toContain("from('documents_soignants').insert(");
  });

  it('bloque chaque voie de démarrage tant que contrat et preuves ne sont pas courants', () => {
    expect(migration).toContain('fn_exiger_conformite_demarrage_mission');
    expect(migration).toContain("cm.statut = 'SIGNE_COMPLET'");
    expect(migration).toContain('fn_documents_ok_pour_mission(p_soignant_id, v_regime)');
    expect(migration).toContain('ORDER BY ds.id\n  FOR SHARE');
    expect(migration).toContain('ORDER BY cm.id\n  FOR SHARE');
    expect(migration).toContain('trg_01_exiger_conformite_premier_pointage');
    expect(migration).toContain('trg_01_exiger_conformite_mission_en_cours');
    expect(migration).toContain('trg_01_exiger_conformite_qr_mission');
    expect(migration).toContain('trg_01_exiger_conformite_code_secours_mission');
    expect(migration).toContain('trg_00_verrouiller_etat_initial_mission');
    expect(migration).toContain("NEW.statut IS DISTINCT FROM 'OUVERTE'");
    expect(migration).toContain('NEW.soignant_assigne_id IS NOT NULL');
    expect(migration).toContain("v_role = 'service_role'");
    expect(migration).toContain("ERRCODE = '23514'");
    for (const rpc of [
      'fn_pointer_arrivee',
      'fn_valider_scan_qr',
      'fn_valider_code_secours',
      'fn_scanner_code_pointage',
      'fn_generer_qr_mission',
      'fn_generer_code_secours_mission',
    ]) expect(migration).toContain(rpc);
  });

  it('crée une vraie revue idempotente pour tous les résultats non concluants', () => {
    expect(migration).toContain('uq_file_revue_document_active');
    expect(migration).toContain('fn_document_marquer_revue_manuelle');
    expect(verifyDocument).toContain('markDocumentForManualReview');
    expect(verifyDocument).toContain('AI_TIMEOUT');
    expect(verifyDocument).toContain('AI_NETWORK_ERROR');
    expect(verifyDocument).toContain('AI_PARSE_ERROR');
    expect(verifyDocument).toContain('UNHANDLED_VERIFICATION_ERROR');
    expect(documentsUi).toContain('Demander une revue humaine');
    expect(documentsUi).toContain('Demande reçue — en attente d’attribution');
  });

  it('lie le virement à la version exacte du RIB et de l’identité', () => {
    expect(migration).toContain('iban_identite_document_id');
    expect(migration).toContain('iban_source_s3_cle');
    expect(migration).toContain('iban_empreinte_sha256');
    expect(migration).toContain('fn_lier_iban_verifie_document');
    expect(migration).toContain('fn_coordonnees_bancaires_soignant_verifiees');
    expect(migration).toContain("ds.statut_verification = 'VERIFIE'");
    expect(migration).toContain('ds.revoque_le IS NULL');
    expect(migration).toContain('fn_consulter_rib_soignant');
    expect(migration).toContain('fn_peut_lire_objet_jolene');
    expect(migration).toContain('fn_peut_gerer_objet_jolene');
    expect(migration.match(/public\.fn_compte_auth_actif\(\)/g)?.length).toBeGreaterThanOrEqual(2);
    expect(verifyDocument).toContain('p_expected_s3_cle: doc.s3_cle');
  });

  it('permet la modération RIB sans persister ni auditer l’IBAN complet', () => {
    expect(moderation).toContain("'iban_preuve_hash_v1', CASE");
    expect(moderation).toContain("v_iban_normalise || ':' || v_doc.id::text");
    expect(moderation).toContain('public.fn_lier_iban_verifie_document(');
    expect(moderation).toContain("- 'iban_extrait'");
    expect(moderation).toContain("'iban_last4', v_iban_last4");
    const auditBlock = moderation.match(
      /INSERT INTO public\.journaux_audit[\s\S]*?'decision', 'VALIDER'[\s\S]*?\);/,
    )?.[0] ?? '';
    expect(auditBlock).not.toContain("'iban', v_iban");
  });

  it('révoque le verdict RIB établissement après le protector anti-forge', () => {
    expect(migration).toMatch(
      /CREATE TRIGGER trg_zz_invalider_provenance_rib_etablissement\s+BEFORE UPDATE OF rib_s3_key, nom, siret, siret_raison_sociale,/,
    );
    expect('trg_zz_invalider_provenance_rib_etablissement'.localeCompare(
      'trg_protect_etablissement_commercial',
    )).toBeGreaterThan(0);
    expect(migration).toContain('NEW.nom IS DISTINCT FROM OLD.nom');
    expect(migration).toContain('NEW.finess_raison_sociale IS DISTINCT FROM OLD.finess_raison_sociale');
    expect(migration).toContain('NEW.rib_ia_coherent := NULL');
    expect(migration).toContain('NEW.rib_verifie_s3_key := NULL');
    expect(migration).toContain('rib_verifie_source_version = CASE WHEN p_coherent IS TRUE THEN p_version_attendue + 1');
  });

  it('refuse la lecture bancaire à un JWT dont le compte a été désactivé', () => {
    const consulter = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_consulter_mon_iban\(\)[\s\S]*?\$function\$;/,
    )?.[0] ?? '';
    expect(consulter).toContain('NOT public.fn_compte_auth_actif()');
  });

  it('conserve la file établissement AAL2 définie avant 65000', () => {
    expect(establishmentReview).toContain('fn_admin_lister_etablissements_a_verifier');
    expect(establishmentReview).toContain('est_admin_valide()');
    expect(migration).not.toContain(
      'CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements_a_verifier',
    );
  });

  it('ne masque plus FINESS et refuse les faux succès HTTP 200', () => {
    expect(establishmentUi).toContain('const verificationEtablissementOk = rattachOk && finessOk');
    expect(establishmentUi).toContain('{verificationEtablissementOk ? (');
    expect(establishmentUi.match(/data\?\.ok !== true/g)?.length).toBeGreaterThanOrEqual(2);
    expect(establishmentUi).toContain('Une revue humaine est nécessaire');
  });
});
