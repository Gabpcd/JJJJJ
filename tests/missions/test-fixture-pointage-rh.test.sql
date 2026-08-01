-- Régressions runtime du rattrapage test et du prévisionnel RH exact.
-- Prérequis : migration 20260801205804 appliquée.

\set ON_ERROR_STOP on
BEGIN;

DO $catalogue_et_stock$
DECLARE
  v_definition text;
  v_bad text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'public.fn_stats_rh_etablissement()'::pg_catalog.regprocedure
  ) INTO v_definition;

  IF v_definition NOT LIKE '%planning_futur%'
     OR v_definition NOT LIKE '%heures_terminees_exactes%'
     OR v_definition NOT LIKE '%mc.type_creneau = ''PREVISIONNEL''%'
     OR v_definition NOT LIKE '%mc.type_creneau = ''EFFECTIF''%'
     OR v_definition NOT LIKE '%effectif.type_creneau = ''EFFECTIF''%'
     OR v_definition NOT LIKE '%mc.debut >= v_now%'
     OR v_definition NOT LIKE '%statut IN (''ASSIGNEE'', ''EN_COURS'')%'
     OR v_definition NOT LIKE '%heures_futures / NULLIF(heures_totales, 0)%'
     OR v_definition LIKE '%fin_le - debut_le%' THEN
    RAISE EXCEPTION 'La RPC RH ne repose pas sur le planning futur exact';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN private.security_definer_inventory i
      ON i.signature = p.oid::pg_catalog.regprocedure::text
    WHERE p.oid =
      'public.fn_stats_rh_etablissement()'::pg_catalog.regprocedure
      AND p.prosecdef IS TRUE
      AND p.proconfig && ARRAY['search_path=', 'search_path=""']::text[]
      AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege(
        'authenticated', p.oid, 'EXECUTE'
      )
      AND i.definition_md5 = pg_catalog.md5(p.prosrc)
  ) THEN
    RAISE EXCEPTION 'RPC RH: SECURITY DEFINER, ACL ou inventaire invalide';
  END IF;

  SELECT pg_catalog.string_agg(m.id::text, ', ' ORDER BY m.id::text)
  INTO v_bad
  FROM public.missions m
  JOIN public.etablissements e
    ON e.id = m.etablissement_id
   AND e.est_compte_test IS TRUE
   AND e.supprime_le IS NULL
  JOIN public.soignants s
    ON s.id = m.soignant_assigne_id
   AND s.est_compte_test IS TRUE
   AND s.supprime_le IS NULL
  WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND NOT EXISTS (
      SELECT 1
      FROM public.contrats_mission cm
      WHERE cm.mission_id = m.id
        AND cm.etablissement_id = m.etablissement_id
        AND cm.soignant_id = m.soignant_assigne_id
        AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.candidatures c
      LEFT JOIN public.soignants sc ON sc.id = c.soignant_id
      WHERE c.mission_id = m.id
        AND sc.est_compte_test IS DISTINCT FROM TRUE
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.presences p
      LEFT JOIN public.soignants sp ON sp.id = p.soignant_id
      WHERE p.mission_id = m.id
        AND sp.est_compte_test IS DISTINCT FROM TRUE
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.scans_pointage scan
      LEFT JOIN public.soignants ss ON ss.id = scan.soignant_id
      WHERE scan.mission_id = m.id
        AND ss.est_compte_test IS DISTINCT FROM TRUE
    );

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Missions test réparables toujours sans contrat: %', v_bad;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE m.id = '0f180010-0000-4000-8000-000000000001'::uuid
      AND e.est_compte_test IS TRUE
      AND s.est_compte_test IS TRUE
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND NOT EXISTS (
        SELECT 1
        FROM public.contrats_mission cm
        WHERE cm.mission_id = m.id
          AND cm.soignant_id = m.soignant_assigne_id
          AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
          AND NULLIF(pg_catalog.btrim(cm.contenu_html), '') IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'Fixture 0f180010 toujours sans contrat';
  END IF;
END
$catalogue_et_stock$;

DO $stats_rh_exactes$
DECLARE
  v_etablissement_id constant uuid :=
    'a18e0000-0000-4000-8000-000000000001';
  v_soignant_id constant uuid :=
    'a18e0000-0000-4000-8000-000000000002';
  v_acteur_id constant uuid :=
    'a18e0000-0000-4000-8000-000000000003';
  v_mission_id constant uuid :=
    'a18e0000-0000-4000-8000-000000000004';
  v_mission_terminee_id constant uuid :=
    'a18e0000-0000-4000-8000-000000000005';
  v_passe_debut timestamptz := pg_catalog.now() - interval '2 days';
  v_passe_fin timestamptz := pg_catalog.now() - interval '2 days' + interval '2 hours';
  v_futur_debut timestamptz := pg_catalog.now() + interval '2 days';
  v_futur_fin timestamptz := pg_catalog.now() + interval '2 days 4 hours';
  v_terminee_debut timestamptz :=
    pg_catalog.date_trunc('month', pg_catalog.now() - interval '1 month')
      + interval '1 day 08 hours';
  v_terminee_second_debut timestamptz :=
    pg_catalog.date_trunc('month', pg_catalog.now() - interval '1 month')
      + interval '3 days 08 hours';
  v_terminee_fin timestamptz :=
    pg_catalog.date_trunc('month', pg_catalog.now() - interval '1 month')
      + interval '3 days 16 hours';
  v_stats jsonb;
  v_prochaine jsonb;
  v_terminee_detail jsonb;
  v_total_brut numeric;
  v_terminee_total_brut numeric;
  v_attendu_futur numeric;
  v_attendu_cout_horaire numeric;
BEGIN
  PERFORM pg_catalog.set_config('app.test_mode', 'true', true);
  PERFORM pg_catalog.set_config('request.jwt.claim.sub', '', true);
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.role', 'service_role', true
  );
  PERFORM pg_catalog.set_config(
    'request.jwt.claims', '{"role":"service_role"}', true
  );
  PERFORM pg_catalog.set_config(
    'jolene.admin_seed_override_reason',
    'Fixture transactionnelle stats RH planning exact',
    true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_soignant_id,
      '00000000-0000-0000-0000-000000000000',
      'stats-rh-soignant@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      pg_catalog.now()
    ),
    (
      v_acteur_id,
      '00000000-0000-0000-0000-000000000000',
      'stats-rh-acteur@test.local',
      'authenticated',
      'authenticated',
      '{"role":"ADMIN_ETABLISSEMENT"}',
      pg_catalog.now()
    );

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test
  ) VALUES (
    v_etablissement_id,
    'Fixture stats RH exactes',
    '99180000000401',
    'CLINIQUE_PRIVEE',
    '18 rue du Test',
    'Paris',
    '75018',
    'stats-rh-etablissement@test.local',
    true
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test
  ) VALUES (
    v_soignant_id,
    'Fixture',
    'StatsRH',
    'stats-rh-soignant@test.local',
    'IDE',
    true
  );

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etablissement_id, v_acteur_id, 'PROPRIETAIRE', true
  );

  -- EN_COURS est volontaire: l'ancienne RPC ne comptait que ASSIGNEE et
  -- perdait donc le créneau futur de cette mission multi-jours.
  INSERT INTO public.missions (
    id,
    etablissement_id,
    intitule,
    profession_requise,
    debut_le,
    fin_le,
    taux_horaire_base,
    statut,
    soignant_assigne_id,
    type_contrat_recherche,
    type_contrat_applique
  ) VALUES (
    v_mission_id,
    v_etablissement_id,
    'Fixture EN_COURS avec prochain jour exact',
    'IDE',
    v_passe_debut,
    v_futur_fin,
    25,
    'EN_COURS',
    v_soignant_id,
    'SALARIE',
    'SALARIE'
  );

  INSERT INTO public.mission_creneaux (
    mission_id, debut, fin, ordre, type_creneau
  ) VALUES
    (
      v_mission_id, v_passe_debut, v_passe_fin, 1, 'PREVISIONNEL'
    ),
    (
      v_mission_id, v_futur_debut, v_futur_fin, 2, 'PREVISIONNEL'
    );

  -- Cette mission couvre plusieurs jours calendaires mais seulement deux
  -- vacations prévisionnelles. Un EFFECTIF clos existe: ses 3 h doivent donc
  -- remplacer les 16 h prévisionnelles dans l'historique RH, jamais devenir
  -- toute l'enveloppe calendaire.
  INSERT INTO public.missions (
    id,
    etablissement_id,
    intitule,
    profession_requise,
    debut_le,
    fin_le,
    taux_horaire_base,
    statut,
    soignant_assigne_id,
    type_contrat_recherche,
    type_contrat_applique
  ) VALUES (
    v_mission_terminee_id,
    v_etablissement_id,
    'Fixture TERMINEE discontinue avec EFFECTIF exact',
    'IDE',
    v_terminee_debut,
    v_terminee_fin,
    25,
    'TERMINEE',
    v_soignant_id,
    'SALARIE',
    'SALARIE'
  );

  INSERT INTO public.mission_creneaux (
    mission_id, debut, fin, ordre, type_creneau
  ) VALUES
    (
      v_mission_terminee_id,
      v_terminee_debut,
      v_terminee_debut + interval '8 hours',
      1,
      'PREVISIONNEL'
    ),
    (
      v_mission_terminee_id,
      v_terminee_second_debut,
      v_terminee_fin,
      2,
      'PREVISIONNEL'
    ),
    (
      v_mission_terminee_id,
      v_terminee_debut,
      v_terminee_debut + interval '3 hours',
      1,
      'EFFECTIF'
    );

  SELECT m.total_brut
  INTO v_total_brut
  FROM public.missions m
  WHERE m.id = v_mission_id;
  v_attendu_futur := pg_catalog.round(v_total_brut * 4 / 6, 2);

  SELECT m.total_brut
  INTO v_terminee_total_brut
  FROM public.missions m
  WHERE m.id = v_mission_terminee_id;
  v_attendu_cout_horaire := pg_catalog.round(
    v_terminee_total_brut / 3,
    2
  );

  PERFORM pg_catalog.set_config(
    'jolene.admin_seed_override_reason', '', true
  );
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.sub', v_acteur_id::text, true
  );
  PERFORM pg_catalog.set_config(
    'request.jwt.claim.role', 'authenticated', true
  );
  PERFORM pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object(
      'sub', v_acteur_id,
      'role', 'authenticated',
      'aal', 'aal1'
    )::text,
    true
  );

  v_stats := public.fn_stats_rh_etablissement();

  IF (v_stats ->> 'assignees_total')::integer IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EN_COURS future non comptée: %', v_stats;
  END IF;
  IF (v_stats ->> 'heures_prevues')::numeric IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'Heures futures exactes attendues 4h: %', v_stats;
  END IF;
  IF (v_stats ->> 'cout_previsionnel_brut')::numeric
       IS DISTINCT FROM v_attendu_futur THEN
    RAISE EXCEPTION
      'Budget futur mal proratisé: attendu %, obtenu %',
      v_attendu_futur,
      v_stats ->> 'cout_previsionnel_brut';
  END IF;
  IF (v_stats ->> 'heures_terminees')::numeric IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION
      'Historique terminé attendu à 3h EFFECTIF, obtenu: %',
      v_stats ->> 'heures_terminees';
  END IF;
  IF (v_stats ->> 'cout_moyen_heure')::numeric
       IS DISTINCT FROM v_attendu_cout_horaire THEN
    RAISE EXCEPTION
      'Coût horaire terminé attendu %, obtenu %',
      v_attendu_cout_horaire,
      v_stats ->> 'cout_moyen_heure';
  END IF;

  SELECT item
  INTO v_prochaine
  FROM pg_catalog.jsonb_array_elements(
    v_stats -> 'prochaines_missions'
  ) AS items(item)
  WHERE item ->> 'mission_id' = v_mission_id::text;

  IF v_prochaine IS NULL
     OR (v_prochaine ->> 'debut_le')::timestamptz
          IS DISTINCT FROM v_futur_debut
     OR (v_prochaine ->> 'heures')::numeric IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'Prochain créneau exact absent ou faux: %', v_prochaine;
  END IF;

  SELECT item
  INTO v_terminee_detail
  FROM pg_catalog.jsonb_array_elements(
    v_stats -> 'missions_mois_prec'
  ) AS items(item)
  WHERE item ->> 'mission_id' = v_mission_terminee_id::text;

  IF v_terminee_detail IS NULL
     OR (v_terminee_detail ->> 'heures')::numeric IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION
      'Détail terminé attendu à 3h EFFECTIF: %',
      v_terminee_detail;
  END IF;
END
$stats_rh_exactes$;

ROLLBACK;
