-- Le contrôle du diplôme spécialisé/profession_certifiee existe déjà dans
-- fn_documents_ok_pour_mission. Un RPPS infirmier générique ne doit pas le
-- court-circuiter. Aucun numéro/verdict RPPS, profil ni preuve n'est révoqué.
CREATE OR REPLACE FUNCTION "public"."fn_documents_ok_pour_mission"("p_soignant_id" "uuid", "p_type_contrat" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'pg_catalog', 'public'
    AS $_$
DECLARE
  v_profession public.type_profession;
  v_rpps_verifie boolean;
  v_identifiant_officiel boolean;
  v_regime_liberal boolean;
  v_liberal_actif boolean;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN false; END IF;

  IF current_user NOT IN ('postgres', 'supabase_admin', 'service_role')
     AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Calcul documentaire réservé au service interne.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT profession,
         COALESCE(rpps_verifie, false)
           AND profession::text NOT IN ('AS', 'AES', 'AUXILIAIRE_PUERICULTURE', 'IADE', 'IBODE'),
         COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false),
         COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF'
           AND COALESCE(type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')
           AND statut_liberal = 'ACTIF'
           AND siret_liberal ~ '^[0-9]{14}$'
           AND siret_liberal_verifie IS TRUE
           AND siret_liberal_verifie_le IS NOT NULL
           AND siret_liberal_coherence_identite IS TRUE
    INTO v_profession, v_rpps_verifie, v_identifiant_officiel, v_liberal_actif
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND OR v_profession IS NULL THEN RETURN false; END IF;

  v_regime_liberal := upper(COALESCE(p_type_contrat, 'SALARIE')) = 'LIBERAL';
  IF v_regime_liberal AND NOT COALESCE(v_liberal_actif, false) THEN
    RETURN false;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = v_profession
      AND drp.est_critique IS TRUE
      AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal)
      )
      AND NOT (
        (drp.type_document = 'RPPS_ADELI' AND v_identifiant_officiel)
        OR (drp.type_document = 'DIPLOME' AND v_rpps_verifie)
        OR EXISTS (
          SELECT 1
          FROM public.documents_soignants ds
          WHERE ds.soignant_id = p_soignant_id
            AND public.fn_type_document_preuve_compatible(
              drp.type_document,
              ds.type_document
            )
            AND ds.statut_verification = 'VERIFIE'
            AND ds.supprime_le IS NULL
            AND ds.revoque_le IS NULL
            AND (
              drp.a_expiration IS FALSE
              OR (ds.valide_jusqua IS NOT NULL AND ds.valide_jusqua > current_date)
            )
            AND (
              drp.type_document <> 'DIPLOME'
              OR v_profession NOT IN ('IADE', 'IBODE')
              OR upper(COALESCE(ds.resultat_ia->>'profession_certifiee', ''))
                   = v_profession::text
            )
        )
      )
  );
END;
$_$;

COMMENT ON FUNCTION "public"."fn_documents_ok_pour_mission"("p_soignant_id" "uuid", "p_type_contrat" "text") IS 'Vérifie les preuves critiques. RPPS API vérifié : dispense RPPS_ADELI et DIPLOME hors IADE/IBODE ; les diplômes spécialisés exigent profession_certifiee correspondante. ADELI seul : dispense RPPS_ADELI uniquement.';

-- Départ LIVE STAGE/PROD MD5 prosrc524f4ef09befb069b6590388e34c3f8e.
-- Aucun changement de propriétaire, ACL, configuration ou catégorie d'inventaire.
DO $cache_recalcul_preflight$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_calculer_tous_documents_valides(uuid)'::regprocedure)
       IS DISTINCT FROM '524f4ef09befb069b6590388e34c3f8e'
    OR has_function_privilege('authenticated','public.fn_calculer_tous_documents_valides(uuid)','EXECUTE')
    OR has_function_privilege('anon','public.fn_calculer_tous_documents_valides(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'CACHE_RECALCUL_SOURCE_OR_ACL_CHANGED'; END IF;
  -- Si l'inventaire connaît cette primitive, ne modifier que son empreinte.
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory
      WHERE signature IN ('fn_calculer_tous_documents_valides(uuid)','public.fn_calculer_tous_documents_valides(uuid)')
        AND definition_md5 IS DISTINCT FROM '524f4ef09befb069b6590388e34c3f8e') THEN
    RAISE EXCEPTION 'CACHE_RECALCUL_INVENTORY_CHANGED'; END IF;
END;
$cache_recalcul_preflight$;
CREATE OR REPLACE FUNCTION public.fn_calculer_tous_documents_valides(p_soignant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_type_exercice text;
  v_regime text;
  v_system_update_precedent text;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN; END IF;
  SELECT type_exercice INTO v_type_exercice
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN; END IF;

  -- Un profil MIXTE doit être prêt pour son régime le plus exigeant. La règle
  -- mission continuera de relire le régime réel au moment de l'affectation.
  v_regime := CASE WHEN upper(COALESCE(v_type_exercice, 'SALARIE')) IN ('LIBERAL', 'MIXTE')
    THEN 'LIBERAL' ELSE 'SALARIE' END;
  -- Contexte limité à cette seule écriture calculée, jamais laissé au JWT.
  v_system_update_precedent := COALESCE(current_setting('jolene.system_update', true), '');
  PERFORM set_config('jolene.system_update', 'true', true);
  BEGIN
    UPDATE public.soignants
      SET tous_documents_valides = public.fn_documents_ok_pour_mission(p_soignant_id, v_regime),
          modifie_le = now()
      WHERE id = p_soignant_id;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('jolene.system_update', v_system_update_precedent, true);
    RAISE;
  END;
  PERFORM set_config('jolene.system_update', v_system_update_precedent, true);
END;
$function$;
UPDATE private.security_definer_inventory
SET definition_md5 = (SELECT md5(prosrc) FROM pg_proc
    WHERE oid='public.fn_calculer_tous_documents_valides(uuid)'::regprocedure), recense_le=now()
WHERE signature IN ('fn_calculer_tous_documents_valides(uuid)','public.fn_calculer_tous_documents_valides(uuid)')
  AND definition_md5='524f4ef09befb069b6590388e34c3f8e';

-- Corriger uniquement le cache dérivé devenu inexact par l'ancienne dispense.
-- Le calcul canonique ne modifie que tous_documents_valides et modifie_le ;
-- aucun verdict RPPS, document, statut de compte ou attribution n'est révoqué.
DO $cache_specialise$
DECLARE
  v_soignant_id uuid;
BEGIN
  FOR v_soignant_id IN
    SELECT s.id
    FROM public.soignants s
    WHERE s.supprime_le IS NULL
      AND s.profession IN ('IADE', 'IBODE')
      AND s.rpps_verifie IS TRUE
      AND s.tous_documents_valides IS TRUE
      AND public.fn_documents_ok_pour_mission(s.id,
        CASE WHEN upper(COALESCE(s.type_exercice, 'SALARIE')) IN ('LIBERAL', 'MIXTE')
          THEN 'LIBERAL' ELSE 'SALARIE' END) IS FALSE
    ORDER BY s.id
  LOOP
    PERFORM public.fn_calculer_tous_documents_valides(v_soignant_id);
  END LOOP;
END;
$cache_specialise$;
