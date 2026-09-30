-- Définition LIVE relue le 30/09/2026 ; seul delta : garde initiale uniforme.
-- Les résolveurs salarié/libéral, leurs gardes et leurs calculs sont inchangés.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid =
    'public.fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)'::regprocedure;
  IF NOT FOUND OR md5(p.prosrc) NOT IN (
    '1d1a6d0593e1899ff2c58c48a38f3a4d', '5a13493bf67426d968d0d75aad16b86c'
  ) OR p.prosecdef IS DISTINCT FROM true
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
    OR has_function_privilege('anon',p.oid,'EXECUTE') IS DISTINCT FROM false
    OR has_function_privilege('authenticated',p.oid,'EXECUTE') IS DISTINCT FROM true
    OR has_function_privilege('service_role',p.oid,'EXECUTE') IS DISTINCT FROM true
    OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
              WHERE a.grantee=0 AND a.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'Résolveur litige : définition ou droits inattendus';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_intelligent(p_litige_id uuid, p_resolution text, p_en_faveur_de text DEFAULT NULL::text, p_ajuster_heures numeric DEFAULT NULL::numeric, p_ajuster_taux numeric DEFAULT NULL::numeric, p_action_financiere text DEFAULT 'AUTO'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_action text := upper(btrim(COALESCE(p_action_financiere, 'AUTO')));
  v_result jsonb;
  v_action_resultat text;
  v_facture_cible_id uuid;
  v_rectification_id uuid;
  v_litige public.litiges%ROWTYPE;
  v_facture public.factures_honoraires%ROWTYPE;
  v_total_courant_ttc numeric;
  v_heures_apres numeric;
  v_taux_apres numeric;
  v_ajustement_demande boolean;
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Administrateur requis.');
  END IF;

  IF v_action NOT IN ('AUTO', 'AUCUNE', 'RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR', 'COMPLEMENT') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action financière invalide.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.litiges l
    JOIN public.missions m ON m.id = l.mission_id
    WHERE l.id = p_litige_id
      AND COALESCE(m.type_contrat_applique::text, '') = 'SALARIE'
  ) THEN
    RETURN public.fn_admin_resoudre_litige_salarie(
      p_litige_id, p_resolution, p_en_faveur_de,
      p_ajuster_heures, p_ajuster_taux, v_action
    );
  END IF;

  IF v_action IN ('AUTO', 'COMPLEMENT') THEN
    v_result := public.fn_admin_resoudre_litige_complement_honoraires(
      p_litige_id, p_resolution, p_en_faveur_de,
      p_ajuster_heures, p_ajuster_taux
    );
    IF COALESCE((v_result->>'success')::boolean, false) IS TRUE
       OR v_action = 'COMPLEMENT'
       OR COALESCE(v_result->>'error_code', '') <> 'COMPLEMENT_NON_APPLICABLE' THEN
      RETURN v_result;
    END IF;
  END IF;

  SELECT * INTO v_litige
  FROM public.litiges
  WHERE id = p_litige_id;
  v_ajustement_demande := p_ajuster_heures IS NOT NULL
    OR p_ajuster_taux IS NOT NULL
    OR v_litige.payload_modifications IS NOT NULL;

  v_result := public.fn_admin_resoudre_litige(
    p_litige_id,
    p_resolution,
    p_en_faveur_de,
    p_ajuster_heures,
    p_ajuster_taux,
    v_action
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_result;
  END IF;

  v_action_resultat := v_result->>'action_financiere';
  v_heures_apres := NULLIF(v_result->>'heures_final', '')::numeric;
  v_taux_apres := NULLIF(v_result->>'taux_final', '')::numeric;

  -- La file PDF est déclenchée dans le résolveur historique mais ne devient
  -- visible qu'après le commit. On complète donc les snapshots avant que le
  -- worker ne lise la facture rectificative.
  IF v_action_resultat IN ('RECALCUL', 'ANNULER_REEMETTRE') THEN
    v_facture_cible_id := CASE
      WHEN v_action_resultat = 'RECALCUL'
        THEN NULLIF(v_result->>'facture_id', '')::uuid
      ELSE NULLIF(v_result->>'nouvelle_facture_id', '')::uuid
    END;
    UPDATE public.factures_honoraires
    SET quantite_heures_snapshot = COALESCE(v_heures_apres, quantite_heures_snapshot),
        taux_horaire_snapshot = COALESCE(v_taux_apres, taux_horaire_snapshot),
        description_prestation_snapshot =
          'Rectification après litige — '
          || COALESCE(v_heures_apres::text, quantite_heures_snapshot::text, '—') || ' h × '
          || COALESCE(v_taux_apres::text, taux_horaire_snapshot::text, '—') || ' EUR/h',
        modifie_le = now()
    WHERE id = v_facture_cible_id;
  END IF;

  IF v_action_resultat = 'AUCUNE' AND v_ajustement_demande THEN
    SELECT * INTO v_facture
    FROM public.factures_honoraires
    WHERE id = NULLIF(v_result->>'facture_id', '')::uuid
      AND statut IN ('PAYEE', 'FACTORISEE')
    FOR UPDATE;
    IF FOUND THEN
      SELECT solde.montant_ttc
        INTO v_total_courant_ttc
        FROM public.fn_solde_correction_facture_honoraires(v_facture.id) solde;
    END IF;
    IF NOT FOUND
       OR NULLIF(v_result->>'montant_final_ttc', '')::numeric
          IS DISTINCT FROM v_total_courant_ttc THEN
      RAISE EXCEPTION 'Rectification descriptive incohérente';
    END IF;
    IF v_facture.quantite_heures_snapshot IS DISTINCT FROM v_heures_apres
       OR v_facture.taux_horaire_snapshot IS DISTINCT FROM v_taux_apres THEN
      INSERT INTO public.factures_honoraires_rectifications (
        facture_honoraire_id, litige_id, heures_avant, taux_avant,
        heures_apres, taux_apres, montant_ttc_inchange, resolution, cree_par
      ) VALUES (
        v_facture.id, p_litige_id,
        v_facture.quantite_heures_snapshot, v_facture.taux_horaire_snapshot,
        v_heures_apres, v_taux_apres, v_total_courant_ttc,
        btrim(p_resolution), auth.uid()
      ) RETURNING id INTO v_rectification_id;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := auth.uid(),
        p_type_acteur := 'ADMIN_PLATEFORME',
        p_action := 'LITIGE_RESOLUTION',
        p_type_ressource := 'facture_honoraires_rectification',
        p_id_ressource := v_rectification_id,
        p_details := jsonb_build_object(
          'evenement', 'RECTIFICATION_DESCRIPTIVE_SANS_IMPACT_FINANCIER',
          'facture_id', v_facture.id,
          'litige_id', p_litige_id,
          'heures_avant', v_facture.quantite_heures_snapshot,
          'heures_apres', v_heures_apres,
          'taux_avant', v_facture.taux_horaire_snapshot,
          'taux_apres', v_taux_apres,
          'montant_ttc_inchange', v_total_courant_ttc
        )
      );
      PERFORM public.fn_litige_push_notification(
        v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — détail de facture rectifié',
        'Les heures ou le taux ont été rectifiés sans changer le total déjà payé.',
        p_litige_id, jsonb_build_object('rectification_id', v_rectification_id)
      );
      PERFORM public.fn_litige_push_notification(
        v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — détail de facture rectifié',
        'Les heures ou le taux ont été rectifiés sans changer le total déjà payé.',
        p_litige_id, jsonb_build_object('rectification_id', v_rectification_id)
      );
      v_result := v_result || jsonb_build_object(
        'action_financiere', 'RECTIFICATION_DESCRIPTIVE',
        'rectification_id', v_rectification_id
      );
    ELSE
      -- Un changement de pointage peut être légitime sans modifier ni les
      -- heures facturées ni le taux. Il est audité par le résolveur de litige,
      -- sans fabriquer un faux document comptable ni faire échouer le parcours.
      v_result := v_result || jsonb_build_object(
        'action_financiere', 'CORRECTION_PRESENCE_SANS_IMPACT_FACTURE'
      );
    END IF;
  END IF;

  RETURN v_result;
END;
$function$;

DO $inventory$
BEGIN
  IF md5((SELECT prosrc FROM pg_proc WHERE oid =
      'public.fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)'::regprocedure))
     IS DISTINCT FROM '5a13493bf67426d968d0d75aad16b86c' THEN
    RAISE EXCEPTION 'Garde initiale litige non installée';
  END IF;
  UPDATE private.security_definer_inventory
  SET definition_md5='5a13493bf67426d968d0d75aad16b86c',
      justification='Identité non NULL et est_admin() IS TRUE avant toute lecture métier ou routage ; refus uniforme. Résolveurs financiers et gardes propres inchangés. Source 20260930091209_garder_resolveur_litige_avant_lecture.sql.',
      recense_le=now()
  WHERE signature='fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)'
    AND categorie='ADMIN_EST_ADMIN_VALIDE'
    AND definition_md5 IN ('b71fe9716df5eabb54c910aa90ecb637','5a13493bf67426d968d0d75aad16b86c');
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventaire résolveur litige divergent'; END IF;
END;
$inventory$;
