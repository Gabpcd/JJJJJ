-- Le POST /api-v1/missions utilise une cle serveur sans auth.uid(). Cette RPC
-- SECURITY INVOKER, executable uniquement par service_role, conserve le scope
-- etablissement porte par la cle API tout en creant mission + planning exact
-- dans la meme transaction PostgreSQL.

BEGIN;

-- Wrapper transactionnelle du formulaire. Elle conserve le moteur exact
-- canonique puis applique le regime contractuel dans la meme transaction :
-- aucun succes partiel "mission creee mais type/retrocession ignore".
CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours_v2(
  p_intitule text,
  p_description text,
  p_profession_requise public.type_profession,
  p_service text,
  p_taux_horaire_base numeric,
  p_est_urgente boolean,
  p_niveau_urgence integer,
  p_mode_attribution text,
  p_specialite_medicale_requise text,
  p_accepte_non_specialises boolean,
  p_creneaux jsonb,
  p_type_contrat_recherche text,
  p_mode_remuneration text,
  p_retrocession_pct numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_creation jsonb;
  v_regime jsonb;
  v_mission_id uuid;
BEGIN
  IF p_type_contrat_recherche IS NULL
     OR p_type_contrat_recherche NOT IN ('TOUS', 'SALARIE', 'LIBERAL') THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Type de contrat recherche invalide.'
    );
  END IF;
  IF p_mode_remuneration IS NULL
     OR p_mode_remuneration NOT IN ('TAUX_HORAIRE', 'RETROCESSION') THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Mode de remuneration invalide.'
    );
  END IF;
  IF p_mode_remuneration = 'RETROCESSION' AND (
    p_type_contrat_recherche <> 'LIBERAL'
    OR p_retrocession_pct IS NULL
    OR p_retrocession_pct <= 0
    OR p_retrocession_pct > 100
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La retrocession exige un contrat liberal et un pourcentage entre 1 et 100.'
    );
  END IF;

  v_creation := public.fn_creer_mission_multi_jours(
    p_intitule => p_intitule,
    p_description => pg_catalog.btrim(
      pg_catalog.regexp_replace(
        COALESCE(p_description, ''),
        '\[CONTRAT:[^]]+\]',
        '',
        'g'
      )
    ) || ' [CONTRAT:' || p_type_contrat_recherche || ']',
    p_profession_requise => p_profession_requise,
    p_service => p_service,
    p_taux_horaire_base => p_taux_horaire_base,
    p_est_urgente => p_est_urgente,
    p_niveau_urgence => p_niveau_urgence,
    p_mode_attribution => p_mode_attribution,
    p_specialite_medicale_requise => p_specialite_medicale_requise,
    p_accepte_non_specialises => p_accepte_non_specialises,
    p_creneaux => p_creneaux
  );
  IF COALESCE((v_creation->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_creation;
  END IF;

  v_mission_id := (v_creation->>'mission_id')::uuid;
  IF p_mode_remuneration = 'RETROCESSION' THEN
    v_regime := public.fn_definir_retrocession_mission(
      v_mission_id,
      p_retrocession_pct
    );
    IF COALESCE((v_regime->>'success')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Retrocession non appliquee: %',
        COALESCE(v_regime->>'error', 'erreur inconnue')
        USING ERRCODE = 'P0001';
    END IF;
  ELSIF p_type_contrat_recherche <> 'TOUS' THEN
    v_regime := public.fn_modifier_type_contrat_mission(
      v_mission_id,
      p_type_contrat_recherche
    );
    IF COALESCE((v_regime->>'ok')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Type de contrat non applique: %',
        COALESCE(v_regime->>'error', 'erreur inconnue')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN v_creation || pg_catalog.jsonb_build_object(
    'type_contrat_recherche', p_type_contrat_recherche,
    'mode_remuneration', p_mode_remuneration,
    'retrocession_pct', CASE
      WHEN p_mode_remuneration = 'RETROCESSION' THEN p_retrocession_pct
      ELSE NULL
    END
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[fn_creer_mission_multi_jours_v2] SQLSTATE=% SQLERRM=%',
      SQLSTATE, SQLERRM;
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La creation de la mission est temporairement indisponible.',
      'code', 'CREATION_MISSION_INDISPONIBLE'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_creer_mission_multi_jours_v2(
  text, text, public.type_profession, text, numeric, boolean, integer,
  text, text, boolean, jsonb, text, text, numeric
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission_multi_jours_v2(
  text, text, public.type_profession, text, numeric, boolean, integer,
  text, text, boolean, jsonb, text, text, numeric
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_creer_mission_api_v1(
  p_etablissement_id uuid,
  p_intitule text,
  p_profession_requise public.type_profession,
  p_service text,
  p_taux_horaire_base numeric,
  p_creneaux jsonb,
  p_type_contrat_recherche text,
  p_mode_remuneration text,
  p_retrocession_pct numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_blocage jsonb;
  v_validation jsonb;
  v_mission_id uuid;
  v_debut timestamptz;
  v_fin timestamptz;
  v_nb integer;
  v_total numeric;
BEGIN
  IF p_etablissement_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.etablissements e
    WHERE e.id = p_etablissement_id
      AND e.supprime_le IS NULL
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Etablissement introuvable ou inactif.'
    );
  END IF;

  v_blocage := public.fn_blocage_publication_etab(p_etablissement_id);
  IF v_blocage IS NOT NULL THEN RETURN v_blocage; END IF;

  IF p_intitule IS NULL OR pg_catalog.length(pg_catalog.btrim(p_intitule)) < 3 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'L''intitule doit contenir au moins 3 caracteres.'
    );
  END IF;
  IF p_profession_requise IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La profession requise est obligatoire.'
    );
  END IF;
  IF p_taux_horaire_base IS NULL OR p_taux_horaire_base <= 0 OR p_taux_horaire_base > 1000 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Le taux horaire doit etre strictement positif et au plus egal a 1000 euros.'
    );
  END IF;
  IF p_type_contrat_recherche IS NULL
     OR p_type_contrat_recherche NOT IN ('TOUS', 'SALARIE', 'LIBERAL') THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Type de contrat recherche invalide.'
    );
  END IF;
  IF p_mode_remuneration IS NULL
     OR p_mode_remuneration NOT IN ('TAUX_HORAIRE', 'RETROCESSION') THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Mode de remuneration invalide.'
    );
  END IF;
  IF p_mode_remuneration = 'RETROCESSION' AND (
    p_type_contrat_recherche <> 'LIBERAL'
    OR p_retrocession_pct IS NULL
    OR p_retrocession_pct <= 0
    OR p_retrocession_pct > 100
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La retrocession exige un contrat liberal et un pourcentage entre 1 et 100.'
    );
  END IF;

  v_validation := public.fn_valider_creneaux_mission_json(
    p_creneaux,
    p_type_contrat_recherche <> 'LIBERAL'
  );
  IF COALESCE((v_validation->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_validation;
  END IF;

  v_debut := (v_validation->>'debut_le')::timestamptz;
  v_fin := (v_validation->>'fin_le')::timestamptz;
  v_nb := (v_validation->>'nb_creneaux')::integer;
  v_total := (v_validation->>'total_heures')::numeric;

  IF v_debut < pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La mission ne peut pas commencer dans le passe.'
    );
  END IF;

  PERFORM pg_catalog.set_config('jolene.creer_mission_context', 'true', true);
  PERFORM pg_catalog.set_config(
    'jolene.planning_exact_managed', 'true', true
  );
  INSERT INTO public.missions (
    etablissement_id,
    intitule,
    profession_requise,
    service,
    debut_le,
    fin_le,
    duree_heures,
    nb_creneaux,
    taux_horaire_base,
    mode_attribution,
    type_contrat_recherche,
    mode_remuneration,
    retrocession_pct
  ) VALUES (
    p_etablissement_id,
    pg_catalog.btrim(p_intitule),
    p_profession_requise,
    NULLIF(pg_catalog.btrim(p_service), ''),
    v_debut,
    v_fin,
    v_total,
    v_nb,
    p_taux_horaire_base,
    'PREMIER_ARRIVE',
    p_type_contrat_recherche,
    p_mode_remuneration,
    CASE WHEN p_mode_remuneration = 'RETROCESSION'
      THEN p_retrocession_pct
      ELSE NULL
    END
  )
  RETURNING id INTO v_mission_id;

  PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'true', true);
  INSERT INTO public.mission_creneaux (
    mission_id, debut, fin, est_pause, ordre, type_creneau
  )
  SELECT
    v_mission_id,
    (element->>'debut')::timestamptz,
    (element->>'fin')::timestamptz,
    false,
    pg_catalog.row_number() OVER (
      ORDER BY (element->>'debut')::timestamptz,
               (element->>'fin')::timestamptz,
               ordinality
    )::integer,
    'PREVISIONNEL'
  FROM pg_catalog.jsonb_array_elements(p_creneaux)
    WITH ORDINALITY AS source(element, ordinality)
  ORDER BY (element->>'debut')::timestamptz,
           (element->>'fin')::timestamptz,
           ordinality;
  PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'false', true);
  PERFORM pg_catalog.set_config(
    'jolene.planning_exact_managed', 'false', true
  );

  UPDATE public.missions
  SET debut_le = v_debut,
      fin_le = v_fin,
      duree_heures = v_total,
      nb_creneaux = v_nb,
      modifie_le = pg_catalog.now()
  WHERE id = v_mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    NULL,
    'API_ETABLISSEMENT',
    'MISSION_CREATION_API',
    'mission',
    v_mission_id,
    NULL,
    pg_catalog.jsonb_build_object(
      'etablissement_id', p_etablissement_id,
      'nb_creneaux', v_nb,
      'planning_source', 'API_CRENEAUX_DATES'
    ),
    NULL,
    NULL
  );

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'mission_id', v_mission_id,
    'nb_creneaux', v_nb,
    'total_heures', v_total
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[fn_creer_mission_api_v1] SQLSTATE=% SQLERRM=%',
      SQLSTATE, SQLERRM;
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Creation temporairement indisponible.',
      'code', 'CREATION_MISSION_INDISPONIBLE'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_creer_mission_api_v1(
  uuid, text, public.type_profession, text, numeric, jsonb, text, text, numeric
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission_api_v1(
  uuid, text, public.type_profession, text, numeric, jsonb, text, text, numeric
) TO service_role;

COMMENT ON FUNCTION public.fn_creer_mission_api_v1(
  uuid, text, public.type_profession, text, numeric, jsonb, text, text, numeric
) IS 'Creation atomique mission + creneaux exacts depuis une cle API etablissement; service_role uniquement.';

COMMIT;
