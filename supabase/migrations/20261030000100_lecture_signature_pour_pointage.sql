-- Read-only eligibility for the pointage role. No contract content, scan, signature
-- or payment is modified. Existing contract SELECT policies remain unchanged.
DO $preflight$
DECLARE
  v_expected record;
  v_oid oid;
BEGIN
  IF pg_catalog.to_regprocedure('public.fn_contrat_signe_pour_pointage(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'PRESENCE_CONTRACT_READER_ALREADY_EXISTS';
  END IF;
  FOR v_expected IN SELECT * FROM (VALUES
    ('public.fn_compte_auth_actif()', 'cba1336dbd147cadc94bc6baf06ceb43'),
    ('public.mon_etablissement_id()', 'c460c68169ff164cb109501d6dde885d'),
    ('public.fn_a_permission_etablissement(text,uuid)', '324d479198251e9c91524f28496780ba')
  ) AS expected(signature, definition_md5)
  LOOP
    v_oid := pg_catalog.to_regprocedure(v_expected.signature);
    IF v_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid = v_oid
        AND pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) = v_expected.definition_md5
        AND pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
    ) THEN
      RAISE EXCEPTION 'PRESENCE_CONTRACT_DEPENDENCY_DRIFT: %', v_expected.signature;
    END IF;
  END LOOP;
END;
$preflight$;

CREATE FUNCTION public.fn_contrat_signe_pour_pointage(p_mission_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_mission record;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Lecture du pointage non autorisée.' USING ERRCODE = '42501';
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id INTO v_mission
  FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lecture du pointage non autorisée.' USING ERRCODE = '42501';
  END IF;

  IF v_mission.soignant_assigne_id IS DISTINCT FROM v_uid THEN
    IF v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
      OR public.fn_a_permission_etablissement('lecture_pointage', v_mission.etablissement_id) IS NOT TRUE
      OR public.fn_a_permission_etablissement('pointage', v_mission.etablissement_id) IS NOT TRUE THEN
      RAISE EXCEPTION 'Lecture du pointage non autorisée.' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Match both parties as well as the mission: a prior assignee's signed
  -- contract cannot make an unsigned replacement eligible.
  RETURN EXISTS (
    SELECT 1 FROM public.contrats_mission c
    WHERE c.mission_id = v_mission.id
      AND c.etablissement_id = v_mission.etablissement_id
      AND c.soignant_id = v_mission.soignant_assigne_id
      AND c.statut = 'SIGNE_COMPLET'
  );
END;
$body$;
ALTER FUNCTION public.fn_contrat_signe_pour_pointage(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_contrat_signe_pour_pointage(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_contrat_signe_pour_pointage(uuid) TO authenticated;
COMMENT ON FUNCTION public.fn_contrat_signe_pour_pointage(uuid) IS
  'Lecture seule : signature complète de la mission affectée, sans accès au contrat pour POINTAGE_ONLY.';

INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT p.oid::regprocedure::text, 'RPC_UTILISATEUR_AUTH_INTERNE', md5(p.prosrc),
  'Compte actif ; soignant affecté ou établissement courant avec permissions pointage. Booléen seul, sans contrat.', now()
FROM pg_proc p WHERE p.oid='public.fn_contrat_signe_pour_pointage(uuid)'::regprocedure;
