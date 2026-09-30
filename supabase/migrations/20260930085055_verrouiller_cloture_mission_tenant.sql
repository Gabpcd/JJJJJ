-- Recapture exacte du catalogue LIVE du 30/09/2026, avant toute modification.
-- Ne pas écraser une définition concurrente ni élargir les ACL existantes.
DO $empreinte_cloture$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = 'public.fn_terminer_mission(uuid)'::pg_catalog.regprocedure
      AND pg_catalog.md5(p.prosrc) = '1ea8780f088275804470e8211da98bfb'
      AND p.prosecdef
      AND p.proconfig = ARRAY['search_path=public']::text[]
      AND pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
      AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'fn_terminer_mission: empreinte ou ACL inattendue, réauditer avant migration';
  END IF;
END
$empreinte_cloture$;

CREATE OR REPLACE FUNCTION public.fn_terminer_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_uid uuid := auth.uid();
  v_est_admin boolean := public.est_admin() IS TRUE;
  v_etablissement_id uuid;
  v_nb_presences integer := 0;
  v_nb_departs integer := 0;
  v_nb_segments_ouverts integer := 0;
  v_nb_creneaux_futurs integer := 0;
  v_planning_incomplet boolean := false;
  v_fin_reference timestamptz;
  v_litige_id uuid;
  v_cloture_anticipee boolean := false;
BEGIN
  -- Pas de lecture de mission avant la validation de l'identité et du rôle.
  -- Aucun appel interne/cron ne dépend de cette RPC utilisateur (audit 30/09).
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  IF NOT v_est_admin THEN
    v_etablissement_id := public.mon_etablissement_id();
    IF v_etablissement_id IS NULL
       OR public.fn_a_permission_etablissement('missions', v_etablissement_id) IS NOT TRUE THEN
      RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
    END IF;
  END IF;

  -- Le filtre tenant appartient à la lecture elle-même. Une mission étrangère
  -- et une mission absente produisent le même refus, sans révéler leur statut.
  -- Le verrou sérialise deux clôtures afin de ne pas notifier deux fois.
  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id
    AND (v_est_admin OR etablissement_id = v_etablissement_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  IF v_mission.statut <> 'EN_COURS' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La mission doit être EN_COURS pour être terminée. Statut actuel : '
        || v_mission.statut
    );
  END IF;

  IF v_mission.est_arret_maladie IS TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RECONCILIATION_HEURES_REQUISE',
      'error', 'Mission interrompue : validation admin des heures effectives requise avant clôture.'
    );
  END IF;

  SELECT
    count(*) FILTER (
      WHERE mc.type_creneau = 'EFFECTIF'
        AND NOT mc.est_pause
        AND mc.fin IS NULL
    ),
    count(*) FILTER (
      WHERE mc.type_creneau = 'EFFECTIF'
        AND NOT mc.est_pause
        AND mc.fin IS NOT NULL
    ),
    count(*) FILTER (
      WHERE mc.type_creneau = 'PREVISIONNEL'
        AND NOT mc.est_pause
        AND mc.debut > now()
    ),
    bool_or(
      mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
      AND mc.fin IS NULL
    ),
    max(mc.fin) FILTER (
      WHERE mc.type_creneau = 'PREVISIONNEL'
        AND NOT mc.est_pause
        AND mc.fin IS NOT NULL
    )
  INTO
    v_nb_segments_ouverts,
    v_nb_departs,
    v_nb_creneaux_futurs,
    v_planning_incomplet,
    v_fin_reference
  FROM public.mission_creneaux mc
  WHERE mc.mission_id = p_mission_id;

  IF coalesce(v_planning_incomplet, false) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PLANNING_INCOMPLET',
      'error', 'Impossible de terminer : le planning contient un créneau incomplet.'
    );
  END IF;

  IF v_nb_segments_ouverts > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SEGMENT_OUVERT',
      'error', 'Impossible de terminer : le soignant doit pointer son départ.'
    );
  END IF;

  SELECT count(*) INTO v_nb_presences
  FROM public.presences
  WHERE mission_id = p_mission_id;

  SELECT v_nb_departs + count(*) INTO v_nb_departs
  FROM public.presences
  WHERE mission_id = p_mission_id
    AND pointage_depart_le IS NOT NULL;

  IF v_nb_departs = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'AUCUN_DEPART',
      'error', 'Impossible de terminer : aucun départ n’est enregistré pour cette mission.'
    );
  END IF;

  v_fin_reference := coalesce(v_fin_reference, v_mission.fin_le);
  IF v_fin_reference IS NULL OR now() < v_fin_reference THEN
    IF NOT v_est_admin THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'AVANT_DERNIER_CRENEAU',
        'error', 'La mission ne peut être terminée qu’après le dernier créneau planifié.'
      );
    END IF;

    SELECT l.id INTO v_litige_id
    FROM public.litiges l
    WHERE l.mission_id = p_mission_id
      AND l.statut IN (
        'OUVERT',
        'EN_DISCUSSION',
        'EN_MEDIATION',
        'MEDIATION_EN_COURS',
        'REVUE_ADMIN'
      )
    ORDER BY l.cree_le DESC
    LIMIT 1;

    IF v_litige_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'LITIGE_ACTIF_REQUIS',
        'error', 'Une clôture anticipée admin exige un litige actif et traçable.'
      );
    END IF;

    v_cloture_anticipee := true;
  END IF;

  UPDATE public.missions
  SET statut = 'TERMINEE', terminee_le = now(), modifie_le = now()
  WHERE id = p_mission_id;

  IF v_cloture_anticipee THEN
    INSERT INTO public.journaux_audit (
      acteur_id,
      type_acteur,
      action,
      type_ressource,
      id_ressource,
      details
    ) VALUES (
      auth.uid(),
      'ADMIN_PLATEFORME',
      'ADMIN_ACTION',
      'mission',
      p_mission_id,
      jsonb_build_object(
        'evenement', 'CLOTURE_ANTICIPEE_APRES_ARBITRAGE',
        'litige_id', v_litige_id,
        'fin_planifiee', v_fin_reference,
        'creneaux_futurs', v_nb_creneaux_futurs,
        'segments_effectifs_fermes', v_nb_departs,
        'presences', v_nb_presences
      )
    );
  END IF;

  IF v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_mission.soignant_assigne_id,
      'SYSTEM',
      'Mission terminée ✅',
      'La mission "' || v_mission.intitule || '" est terminée. Consultez vos gains.',
      '/soignant/mes-gains',
      'SOIGNANT'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'cloture_anticipee_admin', v_cloture_anticipee,
    'litige_id', v_litige_id
  );
END;
$function$;

-- Seule cette entrée accompagne le correctif de garde réellement livré.
-- Les douze autres écarts documentés ne sont pas neutralisés par ce lot.
UPDATE private.security_definer_inventory i
SET definition_md5 = pg_catalog.md5(p.prosrc),
    categorie = 'MIXTE_TENANT_ADMIN',
    justification = 'Clôture: identité active, admin valide ou tenant canonique avec permission missions, lecture filtrée et verrouillée; refus NULL/tiers uniforme.'
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.fn_terminer_mission(uuid)'::pg_catalog.regprocedure
  AND pg_catalog.to_regprocedure(i.signature) = p.oid;
