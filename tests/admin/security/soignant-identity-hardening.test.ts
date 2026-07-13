import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const edge = readFileSync(
  join(process.cwd(), "supabase/functions/verify-document/index.ts"),
  "utf8",
);
const migration = readFileSync(
  join(
    process.cwd(),
    "supabase/migrations/20260713223000_durcir_identite_soignant_documents.sql",
  ),
  "utf8",
);
const atomicMigration = readFileSync(
  join(
    process.cwd(),
    "supabase/migrations/20260713226000_durcir_atomicite_verifications_soignants.sql",
  ),
  "utf8",
);

describe("preuve d’identité soignant liée au profil", () => {
  it("invalide toutes les preuves vérifiées après correction d’un profil", () => {
    const invalidation =
      migration.match(
        /CREATE OR REPLACE FUNCTION public\.fn_invalider_preuves_identite_sur_changement\(\)[\s\S]*?\$\$;/i,
      )?.[0] || "";

    expect(invalidation).toContain("statut_verification = 'VERIFIE'");
    expect(invalidation).toContain("SET statut_verification = 'EN_ATTENTE'");
    expect(invalidation).toContain("identite_verifiee = false");
    expect(invalidation).toContain("diplome_verifie = false");
    expect(invalidation).toContain("siret_liberal_verifie = false");
    expect(invalidation).toContain("siret_liberal_verifie_le = NULL");
    expect(invalidation).toContain("siret_liberal_raison_sociale = NULL");
    expect(invalidation).toContain("siret_liberal_coherence_identite = NULL");
    expect(invalidation).toContain(
      "rpps_verifie = CASE WHEN v_nom_prenom_modifie THEN false",
    );
    expect(invalidation).toContain(
      "adeli_verifie = CASE WHEN v_nom_prenom_modifie THEN false",
    );
    expect(invalidation).toContain(
      "specialite_medicale = CASE WHEN v_nom_prenom_modifie THEN NULL",
    );
    expect(invalidation).toContain(
      "specialite_code = CASE WHEN v_nom_prenom_modifie THEN NULL",
    );
    expect(invalidation).toContain(
      "specialite_source = CASE WHEN v_nom_prenom_modifie THEN NULL",
    );
    expect(invalidation).not.toContain("specialite_medicale_declaree =");
    expect(invalidation).toContain("coherence_identite = 'EN_ATTENTE_REVUE'");
    expect(invalidation).not.toContain(
      "AND type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')",
    );
    expect(invalidation).not.toContain("NEW.profession");
    expect(invalidation).not.toContain("OLD.profession");
    expect(invalidation).not.toContain("OLD.identite_verifiee");
    expect(invalidation).toContain(
      "set_config('jolene.siret_liberal_reset', 'true', true)",
    );
  });

  it("traite CNI, passeport et titre de séjour comme preuves officielles", () => {
    expect(edge).toContain("const IDENTITY_DOCUMENT_TYPES = new Set([");
    expect(edge).toContain('"CARTE_IDENTITE"');
    expect(edge).toContain('"PASSEPORT"');
    expect(edge).toContain('"TITRE_SEJOUR"');
    expect(migration).toMatch(
      /NEW\.type_document IN \('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR'\)/,
    );

    const coherence =
      migration.match(
        /CREATE OR REPLACE FUNCTION public\.fn_verifier_coherence_identite\(p_soignant_id uuid\)[\s\S]*?\$\$;/i,
      )?.[0] || "";
    expect(coherence).toContain(
      "type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')",
    );
    expect(coherence).toContain("identite_verifiee = v_all_ok");
    expect(coherence).not.toContain("rpps_verifie");
    expect(migration).toMatch(
      /CREATE OR REPLACE FUNCTION public\.fn_type_document_preuve_compatible[\s\S]*p_type_requis IN \('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR'\)[\s\S]*p_type_fourni IN \('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR'\)/i,
    );
    expect(migration).toMatch(
      /CREATE OR REPLACE FUNCTION public\.fn_documents_ok_pour_mission[\s\S]*fn_type_document_preuve_compatible/i,
    );
    expect(migration).toMatch(
      /CREATE OR REPLACE FUNCTION public\.dec_verifier_docs_jusqua_fin[\s\S]*fn_type_document_preuve_compatible/i,
    );
  });

  it("recalcule le cache identité pour toute mutation de la preuve et ses deux propriétaires", () => {
    const coherenceTrigger =
      migration.match(
        /CREATE OR REPLACE FUNCTION public\.dec_check_coherence_apres_doc_identite\(\)[\s\S]*?\$\$;/i,
      )?.[0] || "";

    expect(coherenceTrigger).toContain("IF TG_OP = 'DELETE' THEN");
    expect(coherenceTrigger).toContain(
      "OLD.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')",
    );
    expect(coherenceTrigger).toContain(
      "PERFORM public.fn_verifier_coherence_identite(OLD.soignant_id)",
    );
    expect(coherenceTrigger).toContain("RETURN OLD");
    expect(coherenceTrigger).toContain(
      "OLD.soignant_id IS DISTINCT FROM NEW.soignant_id",
    );
    expect(coherenceTrigger).toContain(
      "PERFORM public.fn_verifier_coherence_identite(NEW.soignant_id)",
    );

    const trigger =
      migration.match(
        /CREATE TRIGGER trg_check_coherence_doc_identite[\s\S]*?EXECUTE FUNCTION public\.dec_check_coherence_apres_doc_identite\(\);/i,
      )?.[0] || "";
    expect(trigger).toMatch(/AFTER INSERT OR DELETE OR UPDATE OF/i);
    for (const sourceColumn of [
      "soignant_id",
      "type_document",
      "statut_verification",
      "supprime_le",
      "verifie_le",
      "televerse_le",
      "resultat_ia",
      "nom_extrait_ia",
      "prenom_extrait_ia",
      "coherence_nom",
    ]) {
      expect(trigger).toContain(sourceColumn);
    }
  });

  it("refuse une date de naissance absente, invalide ou contradictoire", () => {
    expect(edge).toContain(
      "function normalizeIsoDate(value: unknown): string | null",
    );
    expect(edge).toContain("dateNaissanceExtraite === dateNaissanceProfil");
    expect(edge).toContain("dateNaissanceExtraite === null");
    expect(edge).toContain("coherenceDateNaissance !== true");
    expect(edge).toContain(
      "p_identite_date_naissance: estIdentite ? dateNaissanceExtraite : null",
    );
    expect(edge).toContain(
      "p_expected_date_naissance: normalizeIsoDate(soignant.date_naissance)",
    );
    expect(atomicMigration).toContain(
      "v_soignant.date_naissance IS DISTINCT FROM p_expected_date_naissance",
    );
    expect(atomicMigration).toContain(
      "v_soignant.date_naissance IS DISTINCT FROM p_identite_date_naissance",
    );
    expect(migration).toContain("v_date_brute ~ '^\\d{4}-\\d{2}-\\d{2}$'");
  });

  it("persiste les traits, les effets profil et le verdict dans une transaction atomique", () => {
    expect(edge).toContain('"fn_finaliser_document_verification" as any');
    expect(edge).toContain("p_resultat_ia: analysisPersisted");
    expect(edge).toContain("p_statut_verification: verdictFinal");
    expect(atomicMigration).toContain("FOR UPDATE");
    expect(atomicMigration).toMatch(
      /UPDATE public\.documents_soignants[\s\S]*resultat_ia = p_resultat_ia[\s\S]*statut_verification = v_statut[\s\S]*verification_attempt_id = NULL/i,
    );
  });

  it("refuse un verdict si le profil ou la tentative a changé pendant l’appel externe", () => {
    expect(edge).toContain("const verificationAttemptId = crypto.randomUUID()");
    expect(edge).toContain('.eq("verification_attempt_id", attemptId)');
    expect(atomicMigration).toContain("verification_attempt_id = p_attempt_id");
    expect(atomicMigration).toContain("Profil modifié pendant la vérification");
    expect(atomicMigration).toContain("USING ERRCODE = '40001'");
    expect(atomicMigration).toContain("fn_noms_personne_correspondent(");
  });

  it("autorise la correction mais ne laisse jamais la preuve inchangée", () => {
    const profileRpc =
      migration.match(
        /CREATE OR REPLACE FUNCTION public\.fn_modifier_mon_profil\([\s\S]*?\$\$;/i,
      )?.[0] || "";
    expect(profileRpc).toContain(
      "prenom = COALESCE(NULLIF(btrim(p_prenom), ''), prenom)",
    );
    expect(profileRpc).toContain(
      "nom = COALESCE(NULLIF(btrim(p_nom), ''), nom)",
    );
    expect(profileRpc).not.toContain(
      "WHEN identite_verifiee = TRUE THEN prenom",
    );
    expect(migration).toMatch(
      /AFTER UPDATE OF prenom, nom, date_naissance ON public\.soignants/i,
    );
  });

  it("restaure la garde système après un recalcul imbriqué, y compris sur erreur", () => {
    const recalcul =
      migration.match(
        /CREATE OR REPLACE FUNCTION public\.fn_recalculer_preuves_etudiant\(p_soignant_id uuid\)[\s\S]*?\$\$;/i,
      )?.[0] || "";

    expect(recalcul).toContain("v_previous_system_update text := COALESCE(");
    expect(recalcul).toContain("current_setting('jolene.system_update', true)");
    expect(recalcul).toContain(
      "set_config('jolene.system_update', 'true', true)",
    );
    expect(recalcul).toMatch(
      /EXCEPTION WHEN OTHERS THEN[\s\S]*set_config\([\s\S]*v_previous_system_update[\s\S]*RAISE;/i,
    );
    expect(
      recalcul.match(/v_previous_system_update/g)?.length,
    ).toBeGreaterThanOrEqual(3);
    expect(recalcul).not.toContain(
      "set_config('jolene.system_update', '', true)",
    );
    expect(
      readFileSync(
        join(
          process.cwd(),
          "tests/admin/security/soignant-identity-hardening.test.sql",
        ),
        "utf8",
      ),
    ).toContain(
      "current_setting('jolene.system_update', true) IS DISTINCT FROM 'true'",
    );
  });

  it("bloque les lectures et recalculs BOLA sur un autre soignant", () => {
    const gate =
      migration.match(
        /CREATE OR REPLACE FUNCTION public\.fn_documents_ok_pour_mission\([\s\S]*?\$\$;/i,
      )?.[0] || "";

    expect(gate).toContain("SECURITY INVOKER");
    expect(gate).toContain(
      "current_user NOT IN ('postgres', 'supabase_admin', 'service_role')",
    );
    expect(gate).toContain("ERRCODE = 'insufficient_privilege'");
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_documents_ok_pour_mission\(uuid, text\)[\s\S]*FROM PUBLIC, anon, authenticated;/i,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_documents_ok_pour_mission\(uuid, text\)[\s\S]*TO service_role;/i,
    );
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_calculer_tous_documents_valides\(uuid\)[\s\S]*FROM PUBLIC, anon, authenticated;/i,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_calculer_tous_documents_valides\(uuid\)[\s\S]*TO service_role;/i,
    );
  });
});
