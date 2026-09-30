-- Source : définition LIVE relue le 30/09/2026, OID 58514,
-- md5(prosrc) de8b4925694aa624a8e45c22e47416b0. Droits, critères, délais et
-- publication réciproque inchangés. Aucun GRANT ni recapture d'inventaire globale.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid =
    'public.fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)'::regprocedure;
  IF NOT FOUND OR md5(p.prosrc) NOT IN ('de8b4925694aa624a8e45c22e47416b0', '430c4e6bb8dce83da949ba41642f3590')
    OR p.prosecdef IS DISTINCT FROM true
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[] THEN
    RAISE EXCEPTION 'Notation : définition ou droits inattendus';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory
    WHERE signature='fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)'
      AND categorie='MIXTE_TENANT_ADMIN'
      AND definition_md5 IN ('de8b4925694aa624a8e45c22e47416b0', '430c4e6bb8dce83da949ba41642f3590')) THEN
    RAISE EXCEPTION 'Notation : inventaire divergent';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_creer_notation_mission(p_mission_id uuid, p_sens text, p_critere_1 integer, p_critere_2 integer, p_critere_3 integer, p_critere_4 integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_admin BOOLEAN;
  v_mission RECORD;
  v_sens public.sens_notation;
  v_notateur_id UUID;
  v_note_id UUID;
  v_id UUID;
  v_tardive BOOLEAN := false;
  v_litige_actif_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Compte suspendu, supprimé ou désactivé');
  END IF;
  v_admin := public.est_admin() IS TRUE;
  v_etab_id := public.mon_etablissement_id();

  BEGIN v_sens := UPPER(TRIM(p_sens))::public.sens_notation;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sens invalide');
  END;

  IF v_sens IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sens invalide');
  END IF;

  -- Un claim ne crée ni établissement canonique ni profil soignant.
  -- Refuser le rôle absent avant toute lecture de mission ou de litige.
  IF NOT v_admin AND (
    (v_sens = 'ETAB_VERS_SOIGNANT' AND v_etab_id IS NULL)
    OR (v_sens = 'SOIGNANT_VERS_ETAB' AND NOT EXISTS (
      SELECT 1 FROM public.soignants s WHERE s.id = v_uid AND s.supprime_le IS NULL
    ))
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès non autorisé à cette mission.');
  END IF;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  -- Filtrer l'appartenance avant d'exposer statut, présence ou litige.
  -- Les identifiants NULL ne peuvent pas neutraliser le refus.
  SELECT m.id, m.etablissement_id, m.soignant_assigne_id, m.statut, m.fin_le INTO v_mission
  FROM public.missions m WHERE m.id = p_mission_id
    AND (v_admin OR NOT (
      (v_sens = 'ETAB_VERS_SOIGNANT' AND m.etablissement_id IS DISTINCT FROM v_etab_id)
      OR (v_sens = 'SOIGNANT_VERS_ETAB' AND m.soignant_assigne_id IS DISTINCT FROM v_uid)
    ));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error',
      CASE WHEN v_admin THEN 'Mission introuvable' ELSE 'Accès non autorisé à cette mission.' END);
  END IF;

  -- 7b-C : TERMINEE, ou EN_COURS avec départ pointé (check-out fait, le cron
  -- de transition n'est simplement pas encore passé).
  IF v_mission.statut <> 'TERMINEE'
     AND NOT (v_mission.statut = 'EN_COURS' AND EXISTS (
       SELECT 1 FROM presences pr
       WHERE pr.mission_id = p_mission_id AND pr.pointage_depart_le IS NOT NULL
     ))
     AND NOT v_admin THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions TERMINEE peuvent être notées');
  END IF;

  -- Itération 1 fix B.8 : bloquer notation pendant litige actif (médiation/arbitrage)
  IF NOT v_admin THEN
    SELECT COUNT(*) INTO v_litige_actif_count FROM litiges
    WHERE mission_id = p_mission_id
      AND statut IN ('MEDIATION_EN_COURS', 'REVUE_ADMIN');
    IF v_litige_actif_count > 0 THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution.');
    END IF;
  END IF;

  IF v_sens = 'ETAB_VERS_SOIGNANT' THEN
    IF v_mission.soignant_assigne_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Mission sans soignant assigné');
    END IF;
    v_notateur_id := v_mission.etablissement_id;
    v_note_id := v_mission.soignant_assigne_id;
  ELSE
    v_notateur_id := v_uid;
    v_note_id := v_mission.etablissement_id;
  END IF;

  IF v_mission.fin_le < NOW() - INTERVAL '30 days' THEN
    v_tardive := true;
  END IF;

  INSERT INTO notations_missions (
    mission_id, notateur_id, note_id, sens,
    critere_1, critere_2, critere_3, critere_4, commentaire
  ) VALUES (
    p_mission_id, v_notateur_id, v_note_id, v_sens,
    p_critere_1, p_critere_2, p_critere_3, p_critere_4, NULLIF(TRIM(p_commentaire), '')
  )
  ON CONFLICT (mission_id, sens) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission déjà notée pour ce sens');
  END IF;

  -- D8 (Lot 15) : double-aveugle — l'INSERT part NON publié (publie_le NULL).
  -- Dès que les deux sens existent, publication SIMULTANÉE des deux notes
  -- (l'UPDATE déclenche le recalcul des scores via le trigger). Sinon le cron
  -- fn_publier_notations_echues publie à J+7.
  IF EXISTS (
    SELECT 1 FROM notations_missions
    WHERE mission_id = p_mission_id AND sens <> v_sens
  ) THEN
    UPDATE notations_missions SET publie_le = NOW()
    WHERE mission_id = p_mission_id AND publie_le IS NULL;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_notateur_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text, 'note_id', v_note_id, 'tardive', v_tardive)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_note_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'NOTATION_RECUE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text)
  );

  RETURN jsonb_build_object('success', true, 'id', v_id, 'tardive', v_tardive);
END;
$function$;

DO $inventory$
BEGIN
  IF md5((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid =
    'public.fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)'::regprocedure)) IS DISTINCT FROM '430c4e6bb8dce83da949ba41642f3590' THEN
    RAISE EXCEPTION 'Garde auteur notation non installée';
  END IF;
  UPDATE private.security_definer_inventory
  SET definition_md5='430c4e6bb8dce83da949ba41642f3590',
      justification='Compte Auth actif, identité de rôle canonique avant lecture métier ; appartenance non NULL filtrée avant statut/litige. Admin validé par est_admin(), auteur établissement canonique de la mission. Double aveugle et droits inchangés. Source 20260930145136_securiser_auteur_notation_mission.sql.',
      recense_le=now()
  WHERE signature='fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)'
    AND categorie='MIXTE_TENANT_ADMIN'
    AND definition_md5 IN ('de8b4925694aa624a8e45c22e47416b0', '430c4e6bb8dce83da949ba41642f3590');
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventaire notation divergent'; END IF;
END;
$inventory$;
