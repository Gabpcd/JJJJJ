-- ================================================================
-- FIX 1: CRITICAL - Prevent soignants from self-verifying documents
-- ================================================================

-- 1a. Replace INSERT policy to block verification fields
DROP POLICY IF EXISTS pol_doc_insert ON public.documents_soignants;
CREATE POLICY pol_doc_insert ON public.documents_soignants
  FOR INSERT TO authenticated
  WITH CHECK (
    est_admin()
    OR (
      soignant_id = auth.uid()
      AND statut_verification = 'EN_ATTENTE'
      AND verifie_par IS NULL
      AND verifie_le IS NULL
      AND valide_depuis IS NULL
      AND valide_jusqua IS NULL
      AND motif_rejet IS NULL
      AND est_critique = false
    )
  );

-- 1b. Create a trigger to block soignants from updating verification fields
CREATE OR REPLACE FUNCTION fn_proteger_document_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Allow admin to do anything
  IF est_admin() THEN
    RETURN NEW;
  END IF;

  -- Block soignants from modifying verification fields
  IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification
     OR NEW.verifie_par IS DISTINCT FROM OLD.verifie_par
     OR NEW.verifie_le IS DISTINCT FROM OLD.verifie_le
     OR NEW.valide_depuis IS DISTINCT FROM OLD.valide_depuis
     OR NEW.valide_jusqua IS DISTINCT FROM OLD.valide_jusqua
     OR NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet
     OR NEW.est_critique IS DISTINCT FROM OLD.est_critique
  THEN
    RAISE EXCEPTION 'Modification des champs de vérification interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_document_verification ON public.documents_soignants;
CREATE TRIGGER trg_proteger_document_verification
  BEFORE UPDATE ON public.documents_soignants
  FOR EACH ROW
  EXECUTE FUNCTION fn_proteger_document_verification();


-- ================================================================
-- FIX 2: CRITICAL - Prevent soignants from inserting pre-validated presences
-- ================================================================

DROP POLICY IF EXISTS pol_pres_insert ON public.presences;
CREATE POLICY pol_pres_insert ON public.presences
  FOR INSERT TO authenticated
  WITH CHECK (
    est_admin()
    OR (
      soignant_id = auth.uid()
      AND valide_par_etablissement = false
      AND valide_le IS NULL
      AND perimetre_gps_valide IS NULL
      AND alerte_teleportation = false
      AND alertes_fraude IS NULL
      AND mission_id IN (
        SELECT missions.id FROM missions
        WHERE missions.soignant_assigne_id = auth.uid()
          AND missions.statut = ANY (ARRAY['ASSIGNEE'::statut_mission, 'EN_COURS'::statut_mission])
      )
      AND mission_id IN (
        SELECT contrats_mission.mission_id FROM contrats_mission
        WHERE contrats_mission.statut = 'SIGNE_COMPLET'
      )
    )
  );


-- ================================================================
-- FIX 3: WARN - Lock rpps_test table with RLS
-- ================================================================

ALTER TABLE IF EXISTS public.rpps_test ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'rpps_test' AND schemaname = 'public') THEN
    EXECUTE 'DROP POLICY IF EXISTS pol_rpps_test_admin ON public.rpps_test';
    EXECUTE 'CREATE POLICY pol_rpps_test_admin ON public.rpps_test FOR ALL TO authenticated USING (est_admin())';
  END IF;
END;
$$;