import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const documentsMigration = readFileSync(
  'supabase/migrations/20260714060000_securiser_remplacement_documents_rib_et_validation_etablissements.sql',
  'utf8',
);
const startGateMigration = readFileSync(
  'supabase/migrations/20260714065000_securiser_documents_rib_et_demarrage_missions.sql',
  'utf8',
);
const rppsDiplomaMigration = readFileSync(
  'supabase/migrations/20260802055000_aligner_dispense_diplome_rpps.sql',
  'utf8',
);
const documentsPage = readFileSync('src/pages/DocumentsSoignant.tsx', 'utf8');
const activationChecklist = readFileSync(
  'src/components/dashboard/ChecklistActivation.tsx',
  'utf8',
);
const externalHours = readFileSync('src/components/ImportHeuresExternes.tsx', 'utf8');
const paymentsSection = readFileSync('src/components/profil-soignant/SectionPaiements.tsx', 'utf8');
const verifier = readFileSync('supabase/functions/verify-document/index.ts', 'utf8');
const externalisationWorker = readFileSync(
  'supabase/functions/process-externalisation-actions/index.ts',
  'utf8',
);

describe('remplacement de preuve sans effacer les données existantes', () => {
  it('conserve les lignes historiques et remplace les nouveaux dépôts sous verrou', () => {
    expect(documentsMigration).toContain('revoque_le timestamptz');
    expect(documentsMigration).toContain('remplace_par_document_id uuid');
    expect(startGateMigration).toContain('pg_advisory_xact_lock');
    expect(startGateMigration).toContain("revoque_raison = 'REMPLACEMENT'");
    expect(startGateMigration).toContain('remplace_par_document_id = NEW.id');
    expect(startGateMigration).toContain(
      "set_config('jolene.document_server_update', 'true', true)",
    );
    expect(startGateMigration).toContain('v_document_server_update_precedent');
    expect(startGateMigration).not.toContain('WITH classees AS');
    expect(startGateMigration).not.toContain('uq_documents_soignants_preuve_courante');
    expect(startGateMigration).not.toMatch(
      /UPDATE public\.documents_soignants ds\s+SET supprime_le/,
    );
  });

  it('passe tous les téléversements applicatifs par une transaction serveur', () => {
    expect(documentsPage).toContain("supabase.rpc('fn_remplacer_document_soignant'");
    expect(documentsPage).not.toContain("from('documents_soignants').insert");
    expect(externalHours).toContain("supabase.rpc('fn_declarer_heures_externes_avec_document'");
    expect(externalHours).not.toContain("from('documents_soignants').insert");
    expect(externalHours).not.toContain("from('heures_externes').insert");
  });
});

describe('dispense documentaire RPPS et spécialité exacte', () => {
  it('dispense du diplôme uniquement quand le RPPS est validé par l’API', () => {
    expect(documentsPage).toContain("rppsVerifie && d.type_document === 'DIPLOME'");
    expect(documentsPage).toContain('PROFESSIONS_SANS_RPPS.includes');
    expect(documentsPage).toContain("registreProfessionnelVerifie && d.type_document === 'RPPS_ADELI'");
    expect(documentsPage).not.toMatch(
      /adeliVerifie\s*&&\s*d\.type_document\s*===\s*['"]DIPLOME['"]/,
    );
    expect(activationChecklist).toContain(
      "identiteVerifiee && d.type_document === 'RPPS_ADELI'",
    );
    expect(activationChecklist).toContain(
      "rppsVerifie && d.type_document === 'DIPLOME'",
    );
    expect(rppsDiplomaMigration).toContain(
      "drp.type_document = 'DIPLOME' AND v_rpps_verifie",
    );
    expect(rppsDiplomaMigration).toContain(
      "profession::text NOT IN ('AS', 'AES', 'AUXILIAIRE_PUERICULTURE')",
    );
    expect(rppsDiplomaMigration).not.toMatch(
      /drp\.type_document = 'DIPLOME' AND v_identifiant_officiel/,
    );
    expect(rppsDiplomaMigration).toContain(
      'PERFORM public.fn_calculer_tous_documents_valides(v_soignant_id)',
    );
    expect(rppsDiplomaMigration).toContain(
      'WHEN (OLD.rpps_verifie IS DISTINCT FROM NEW.rpps_verifie)',
    );
    expect(rppsDiplomaMigration).toContain(
      'PERFORM public.fn_calculer_tous_documents_valides(NEW.id)',
    );
    expect(documentsMigration).toContain("'DIPLOME'::public.type_document");
    expect(documentsMigration).toContain('true,');
  });

  it('refuse un diplôme IDE pour un profil IADE ou IBODE', () => {
    const gate = rppsDiplomaMigration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_documents_ok_pour_mission[\s\S]*?\$function\$;/,
    )?.[0] ?? '';
    expect(gate).toContain("v_profession NOT IN ('IADE', 'IBODE')");
    expect(gate).toContain("ds.resultat_ia->>'profession_certifiee'");
    expect(gate).toContain('= v_profession::text');
    expect(verifier).toContain('diplomaMatchesDeclaredProfession(');
  });
});

describe('RIB prouvé et décaissement fail-closed', () => {
  it('lie l’IBAN ressaisi au RIB courant sans persister l’IBAN complet dans le verdict IA', () => {
    expect(verifier).toContain('analysisPersisted.iban_preuve_hash_v1 = await sha256Hex(');
    expect(verifier).toContain('`${normalizedIban}:${document_id}`');
    expect(documentsMigration).toContain("v_rib.resultat_ia->>'iban_preuve_hash_v1'");
    expect(documentsMigration).toContain('iban_source_document_id = v_rib.id');
    expect(documentsMigration).toContain('fn_coordonnees_bancaires_soignant_verifiees');
  });

  it('n’affiche plus un ancien IBAN brut comme vérifié', () => {
    expect(paymentsSection).toContain('current.iban_verifie');
    expect(paymentsSection).toContain('RIB vérifié requis');
    expect(paymentsSection).toContain("navigate('/soignant/documents')");
  });

  it('ne lit plus d’IBAN brut dans le worker financier', () => {
    expect(externalisationWorker).not.toContain('iban_virement');
    expect(externalisationWorker).not.toContain('dispatchVersementSwan');
    expect(externalisationWorker).toContain('PARRAINAGE_TRAITEMENT_MANUEL_REQUIS');
    expect(externalisationWorker).toContain('REMBOURSEMENT_AVOIR_MANUEL_REQUIS');
  });
});

describe('TOCTOU au démarrage de mission', () => {
  it('revalide contrat et preuves au premier pointage, au passage EN_COURS et à la génération des codes', () => {
    expect(startGateMigration).toContain('fn_exiger_conformite_demarrage_mission');
    expect(startGateMigration).toContain("cm.statut = 'SIGNE_COMPLET'");
    expect(startGateMigration).toContain('public.fn_documents_ok_pour_mission(p_soignant_id, v_regime)');
    expect(startGateMigration).toContain('ORDER BY ds.id\n  FOR SHARE');
    expect(startGateMigration).toContain('ORDER BY cm.id\n  FOR SHARE');
    expect(startGateMigration).toContain('trg_01_exiger_conformite_premier_pointage');
    expect(startGateMigration).toContain('trg_01_exiger_conformite_mission_en_cours');
    expect(startGateMigration).toContain('trg_01_exiger_conformite_qr_mission');
    expect(startGateMigration).toContain('trg_01_exiger_conformite_code_secours_mission');
  });

  it('refuse un INSERT PostgREST déjà affecté ou dans un état historique', () => {
    expect(startGateMigration).toContain('trg_00_verrouiller_etat_initial_mission');
    expect(startGateMigration).toContain('BEFORE INSERT ON public.missions');
    expect(startGateMigration).toContain("NEW.statut IS DISTINCT FROM 'OUVERTE'");
    expect(startGateMigration).toContain('NEW.soignant_assigne_id IS NOT NULL');
    expect(startGateMigration).toContain(
      'Une mission doit être créée OUVERTE et sans soignant affecté.',
    );
  });
});
