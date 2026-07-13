import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713222000_durcir_verifications_preproduction.sql'),
  'utf8',
);
const profileMigration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713223000_durcir_identite_soignant_documents.sql'),
  'utf8',
);

function sourceFunctionBody(source: string, name: string, nextMarker: string): string {
  const start = source.indexOf(`CREATE OR REPLACE FUNCTION public.${name}`);
  const end = source.indexOf(nextMarker, start);
  expect(start, `${name} doit exister`).toBeGreaterThanOrEqual(0);
  expect(end, `borne de fin de ${name}`).toBeGreaterThan(start);
  return source.slice(start, end);
}

function functionBody(name: string, nextMarker: string): string {
  return sourceFunctionBody(migration, name, nextMarker);
}

describe('activation libérale — preuve serveur et gates canoniques', () => {
  it('définit une preuve unique exigeant statut, SIRET, date et cohérence identité', () => {
    const helper = functionBody(
      'fn_soignant_liberal_actif_verifie',
      'CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission',
    );

    expect(helper).toContain("COALESCE(s.type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')");
    expect(helper).toContain("s.statut_liberal = 'ACTIF'");
    expect(helper).toContain("s.siret_liberal ~ '^[0-9]{14}$'");
    expect(helper).toContain('s.siret_liberal_verifie IS TRUE');
    expect(helper).toContain('s.siret_liberal_verifie_le IS NOT NULL');
    expect(helper).toContain('s.siret_liberal_coherence_identite IS TRUE');
  });

  it('branche cette preuve dans la résolution, les documents et l’affectation', () => {
    const resolver = functionBody(
      'fn_resoudre_contrat_mission',
      'CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission',
    );
    const documents = functionBody(
      'fn_documents_ok_pour_mission',
      'CREATE OR REPLACE FUNCTION public.fn_calculer_tous_documents_valides',
    );
    const assignment = functionBody(
      'dec_verifier_eligibilite_liberal',
      '-- Répare l\'audit de demande de revue',
    );

    expect(resolver).toContain('v_liberal_verifie := public.fn_soignant_liberal_actif_verifie');
    expect(resolver).toContain("v_choix := 'SALARIE'");
    expect(documents).toContain('NOT public.fn_soignant_liberal_actif_verifie(p_soignant_id)');
    expect(assignment).toContain('public.fn_soignant_liberal_actif_verifie(NEW.soignant_assigne_id)');
    expect(assignment).toContain("public.fn_documents_ok_pour_mission(NEW.soignant_assigne_id, 'LIBERAL')");
    expect(assignment).toContain('NEW.profession_requise::text');
    expect(assignment).toContain('public.fn_mode_exercice(');
    expect(migration).toMatch(
      /CREATE TRIGGER dec_eligibilite_liberal\s+BEFORE INSERT OR UPDATE ON public\.missions/i,
    );
  });

  it('ferme le bypass p_type_exercice de la RPC de profil', () => {
    expect(profileMigration).toContain('type_exercice = COALESCE(p_type_exercice, type_exercice)');

    const transition = functionBody(
      'fn_verrouiller_transition_liberale',
      'DROP TRIGGER IF EXISTS trg_00_verrouiller_transition_liberale',
    );
    expect(transition).toContain("current_setting('jolene.liberal_transition', true)");
    expect(transition).not.toContain("current_setting('jolene.system_update', true)");
    expect(transition).toContain("NEW.type_exercice IN ('LIBERAL', 'MIXTE')");
    expect(transition).toContain("OLD.statut_liberal = 'ACTIF'");
    expect(transition).toContain('OLD.siret_liberal_verifie IS TRUE');
    expect(transition).toContain('OLD.siret_liberal_coherence_identite IS TRUE');
    expect(migration).toMatch(
      /CREATE TRIGGER trg_00_verrouiller_transition_liberale\s+BEFORE UPDATE ON public\.soignants/i,
    );
  });

  it('rend l’enregistrement SIRET idempotent et verrouille un statut ACTIF', () => {
    const register = functionBody(
      'fn_enregistrer_siret_liberal',
      '-- Protection symétrique ADELI/RPPS',
    );

    expect(register).toContain('FOR UPDATE');
    expect(register).toContain('v_soignant.siret_liberal IS NOT DISTINCT FROM v_siret');
    expect(register).toContain("v_soignant.statut_liberal = 'ACTIF'");
    expect(register).toContain("'SIRET_LIBERAL_ACTIF_VERROUILLE'");
    expect(register.indexOf("v_soignant.statut_liberal = 'ACTIF'")).toBeLessThan(
      register.indexOf("set_config('jolene.liberal_transition', 'true'"),
    );
    expect(register).toContain("type_exercice = 'SALARIE'");
    expect(register).toContain("type_contrat = 'CDD'");
  });

  it('active un profil cohérent et vérifie aussi la date de preuve', () => {
    const activate = functionBody(
      'fn_activer_liberal',
      'CREATE OR REPLACE FUNCTION public.fn_proteger_verification_siret_liberal',
    );

    expect(activate).toContain('v_soignant.siret_liberal_verifie_le IS NULL');
    expect(activate).toContain('v_soignant.siret_liberal_coherence_identite IS NOT TRUE');
    expect(activate).toContain("set_config('jolene.liberal_transition', 'true'");
    expect(activate).toContain("type_exercice = 'LIBERAL'");
    expect(activate).toContain("type_contrat = 'LIBERAL'");
    expect(activate).toContain("statut_liberal = 'ACTIF'");
  });

  it('contrôle les documents jusqu’à la fin même sur un INSERT déjà assigné', () => {
    expect(migration).toMatch(
      /CREATE TRIGGER dec_docs_fin_mission\s+BEFORE INSERT OR UPDATE ON public\.missions/i,
    );
    const documentTrigger = functionBody(
      'dec_verifier_docs_jusqua_fin',
      'REVOKE ALL ON FUNCTION public.dec_verifier_docs_jusqua_fin',
    );
    const finalDocumentTrigger = sourceFunctionBody(
      profileMigration,
      'dec_verifier_docs_jusqua_fin',
      'REVOKE ALL ON FUNCTION public.dec_verifier_docs_jusqua_fin',
    );
    for (const source of [documentTrigger, finalDocumentTrigger]) {
      expect(source).toContain("IF TG_OP = 'INSERT'");
      expect(source).toContain('NEW.type_contrat_applique IS NULL');
      expect(source).toContain('public.fn_documents_ok_pour_mission(');
      expect(source).toContain('ds.valide_jusqua >= NEW.fin_le::date');
    }
    expect(profileMigration).toMatch(
      /CREATE TRIGGER dec_docs_fin_mission\s+BEFORE INSERT OR UPDATE ON public\.missions/i,
    );
  });
});
