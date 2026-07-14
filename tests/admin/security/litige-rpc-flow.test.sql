-- Parcours réel du panneau de contestation et des RPC historiques de litige.
-- Toutes les données et mutations sont annulées par le ROLLBACK final.

\set ON_ERROR_STOP on
BEGIN;

CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;

CREATE TEMP TABLE jolene_litige_rpc_lint_issues ON COMMIT DROP AS
WITH signatures(signature) AS (
  VALUES
    ('public.fn_ouvrir_litige_rate_limited(uuid,type_litige,text)'),
    ('public.fn_ouvrir_litige_rate_limited(uuid,text)'),
    ('public.fn_repondre_litige(uuid,text)'),
    ('public.fn_proposer_accord_partie(uuid)'),
    ('public.fn_confirmer_accord_partie(uuid)'),
    ('public.fn_admin_trancher_litige(uuid,text,text)'),
    ('public.fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)'),
    ('public.fn_ajouter_message_litige(uuid,text)'),
    ('public.fn_executer_modifications_litige(uuid)'),
    ('public.fn_admin_valider_accord_litige(uuid)')
)
SELECT
  s.signature,
  c.level,
  c.sqlstate,
  c.message,
  c.lineno
FROM signatures s
CROSS JOIN LATERAL extensions.plpgsql_check_function_tb(
  s.signature::regprocedure,
  fatal_errors => false
) c
WHERE c.level IN ('error', 'warning');

DO $litige_lint$
BEGIN
  IF EXISTS (SELECT 1 FROM jolene_litige_rpc_lint_issues) THEN
    RAISE EXCEPTION 'Lint RPC litige : %', (
      SELECT jsonb_agg(to_jsonb(i)) FROM jolene_litige_rpc_lint_issues i
    );
  END IF;
END;
$litige_lint$;

DO $litige_flow$
DECLARE
  v_etab_id uuid;
  v_soignant_id uuid;
  v_mission_id uuid := gen_random_uuid();
  v_litige_id uuid;
  v_litige_mediation uuid := gen_random_uuid();
  v_litige_admin uuid := gen_random_uuid();
  v_litige_financier uuid := gen_random_uuid();
  v_lecture uuid := 'abac0002-0000-4000-8000-000000000001'::uuid;
  v_pointage uuid := 'abac0002-0000-4000-8000-000000000002'::uuid;
  v_rh uuid := 'abac0002-0000-4000-8000-000000000003'::uuid;
  v_admin uuid := 'abac0002-0000-4000-8000-000000000004'::uuid;
  v_result jsonb;
  v_message_count integer;
BEGIN
  SELECT e.id
    INTO v_etab_id
    FROM public.etablissements e
   WHERE e.supprime_le IS NULL
   ORDER BY e.id
   LIMIT 1;

  SELECT s.id
    INTO v_soignant_id
    FROM public.soignants s
    JOIN auth.users u ON u.id = s.id
   WHERE s.supprime_le IS NULL
     AND u.deleted_at IS NULL
     AND (u.banned_until IS NULL OR u.banned_until <= now())
     AND u.email_confirmed_at IS NOT NULL
   ORDER BY s.id
   LIMIT 1;

  IF v_etab_id IS NULL OR v_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Fixtures litige impossibles';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_lecture, '00000000-0000-0000-0000-000000000000',
      'litige-flow-lecture@test.local', 'authenticated', 'authenticated',
      '{"role":"ETABLISSEMENT"}', now()
    ),
    (
      v_pointage, '00000000-0000-0000-0000-000000000000',
      'litige-flow-pointage@test.local', 'authenticated', 'authenticated',
      '{"role":"ETABLISSEMENT"}', now()
    ),
    (
      v_rh, '00000000-0000-0000-0000-000000000000',
      'litige-flow-rh@test.local', 'authenticated', 'authenticated',
      '{"role":"ETABLISSEMENT"}', now()
    ),
    (
      v_admin, '00000000-0000-0000-0000-000000000000',
      'litige-flow-admin@test.local', 'authenticated', 'authenticated',
      '{"role":"ADMIN_PLATEFORME"}', now()
    );

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES
    (v_etab_id, v_lecture, 'LECTURE_SEULE', true),
    (v_etab_id, v_pointage, 'POINTAGE_ONLY', true),
    (v_etab_id, v_rh, 'RH', true);

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin,
    'Litige',
    'Admin',
    'litige-flow-admin@test.local',
    true,
    ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[]
  );

  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Test transactionnel parcours RPC litige',
    true
  );
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config(
    'request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id
  ) VALUES (
    v_mission_id, v_etab_id, 'Fixture parcours RPC litige', 'IDE',
    now() + interval '20 years', now() + interval '20 years 1 day',
    24, 20, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par, motif,
    type_litige, statut
  ) VALUES
    (
      v_litige_mediation, v_mission_id, v_soignant_id, v_etab_id,
      'SYSTEME', 'Fixture médiation sécurisée',
      'COMPORTEMENT_SOIGNANT', 'OUVERT'
    ),
    (
      v_litige_admin, v_mission_id, v_soignant_id, v_etab_id,
      'SYSTEME', 'Fixture arbitrage sécurisé',
      'SECURITE_DANGER', 'EN_MEDIATION'
    );

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par, motif,
    type_litige, statut, payload_modifications,
    accord_soignant, accord_etablissement,
    accord_soignant_le, accord_etablissement_le
  ) VALUES (
    v_litige_financier, v_mission_id, v_soignant_id, v_etab_id,
    'SYSTEME', 'Fixture revue financière protégée',
    'DESACCORD_MONTANT_FACTURE', 'REVUE_ADMIN',
    '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":100},"justification":"Fixture financière"}'::jsonb,
    true, true, now(), now()
  );

  INSERT INTO public.parametres_litiges (cle, valeur, description)
  VALUES (
    'rate_limit_litiges_par_heure',
    '100000',
    'Fixture transactionnelle parcours RPC litige'
  )
  ON CONFLICT (cle) DO UPDATE
    SET valeur = EXCLUDED.valeur,
        modifie_le = now();

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  -- LECTURE_SEULE et POINTAGE_ONLY ne peuvent pas ouvrir un litige au nom de
  -- l'établissement malgré leur appartenance au bon tenant.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_lecture, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id, 'Tentative ouverture lecture seule interdite'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Vous n''êtes pas partie prenante de cette mission.' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a ouvert un litige : %', v_result;
  END IF;
  v_result := public.fn_repondre_litige(
    v_litige_mediation, 'Réponse lecture seule interdite'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a répondu : %', v_result;
  END IF;
  v_result := public.fn_ajouter_message_litige(
    v_litige_mediation, 'Message lecture seule interdit'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a écrit un message : %', v_result;
  END IF;
  v_result := public.fn_proposer_accord_partie(v_litige_mediation);
  IF v_result->>'success' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a proposé une médiation : %', v_result;
  END IF;
  v_result := public.fn_confirmer_accord_partie(v_litige_mediation);
  IF v_result->>'success' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a confirmé un accord : %', v_result;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_pointage, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id, 'Tentative ouverture pointage interdite'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Vous n''êtes pas partie prenante de cette mission.' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a ouvert un litige : %', v_result;
  END IF;
  v_result := public.fn_repondre_litige(
    v_litige_mediation, 'Réponse pointage interdite'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a répondu : %', v_result;
  END IF;

  -- Le panneau appelle la signature typée et ouvre en OUVERT pour le soignant
  -- assigné ; une contestation de présence n'est jamais classée AUTRE.
  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant_id, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id,
    'DESACCORD_HEURES_POINTAGE',
    'Les heures validées ne correspondent pas à ma présence'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Ouverture soignant refusée : %', v_result;
  END IF;
  v_litige_id := (v_result->>'litige_id')::uuid;
  IF NOT EXISTS (
    SELECT 1 FROM public.litiges l
    WHERE l.id = v_litige_id
      AND l.statut = 'OUVERT'
      AND l.initie_par = 'SOIGNANT'
      AND l.type_litige = 'DESACCORD_HEURES_POINTAGE'
  ) THEN
    RAISE EXCEPTION
      'Le panneau n''a pas créé le litige canonique : result=%, id=%, row=%, current_user=%, uid=%',
      v_result,
      v_litige_id,
      (
        SELECT to_jsonb(l)
        FROM public.litiges l
        WHERE l.id = v_litige_id
      ),
      current_user,
      auth.uid();
  END IF;

  -- Un compte RH banni est refusé avant toute lecture ou écriture.
  UPDATE auth.users
     SET banned_until = now() + interval '1 day'
   WHERE id = v_rh;
  PERFORM set_config('request.jwt.claim.sub', v_rh::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_rh, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_repondre_litige(
    v_litige_id, 'Réponse par un compte banni interdite'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'Compte banni accepté sur réponse : %', v_result;
  END IF;
  v_result := public.fn_ajouter_message_litige(
    v_litige_id, 'Message par un compte banni interdit'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'Compte banni accepté sur message : %', v_result;
  END IF;
  UPDATE auth.users SET banned_until = NULL WHERE id = v_rh;

  -- RH avec permission contrats répond puis écrit un message.
  v_result := public.fn_repondre_litige(
    v_litige_id, 'Réponse légitime de l’établissement au soignant'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_id
         AND l.statut = 'EN_DISCUSSION'
         AND l.reponse IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Réponse RH légitime refusée : %', v_result;
  END IF;
  v_result := public.fn_ajouter_message_litige(
    v_litige_id, 'Message légitime de suivi du litige'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Message RH légitime refusé : %', v_result;
  END IF;

  SELECT count(*) INTO v_message_count
    FROM public.messages_litige ml
   WHERE ml.litige_id = v_litige_id
     AND ml.auteur_id = v_rh;
  IF v_message_count <> 1 THEN
    RAISE EXCEPTION 'Message RH non persisté exactement une fois';
  END IF;

  -- Le parcours panneau appelle la signature admin à trois arguments et
  -- termine sur un statut admis par la contrainte.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  v_result := public.fn_resoudre_litige(
    v_litige_id,
    'RESOLU_SOIGNANT',
    'Litige résolu en faveur du soignant.'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'statut' IS DISTINCT FROM 'RESOLU_SOIGNANT'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_id
         AND l.statut = 'RESOLU_SOIGNANT'
         AND l.resolution = 'Litige résolu en faveur du soignant.'
     ) THEN
    RAISE EXCEPTION 'Résolution panneau admin invalide : %', v_result;
  END IF;
  v_result := public.fn_ajouter_message_litige(
    v_litige_id, 'Message tardif après résolution interdit'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Ce litige est clôturé.' THEN
    RAISE EXCEPTION 'Message accepté après résolution : %', v_result;
  END IF;

  -- L'admin ne peut ni confirmer à la place des parties ni utiliser
  -- l'arbitrage simple pour exécuter un accord financier en REVUE_ADMIN.
  v_result := public.fn_confirmer_accord_partie(v_litige_mediation);
  IF v_result->>'success' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Admin a confirmé à la place des parties : %', v_result;
  END IF;
  v_result := public.fn_admin_trancher_litige(
    v_litige_financier,
    'PARTAGE',
    'Motif administrateur suffisamment détaillé pour ce test transactionnel financier.'
  );
  IF v_result->>'success' IS DISTINCT FROM 'false'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND l.statut = 'REVUE_ADMIN'
         AND l.modifications_executees IS FALSE
     ) THEN
    RAISE EXCEPTION 'Arbitrage simple a contourné le validateur financier : %', v_result;
  END IF;
  v_result := public.fn_resoudre_litige(
    v_litige_financier,
    'RESOLU_ADMIN',
    'Tentative de contournement du parcours financier.'
  );
  IF v_result->>'error'
       IS DISTINCT FROM 'Accord structuré à traiter via le parcours financier administrateur'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND l.statut = 'REVUE_ADMIN'
         AND l.modifications_executees IS FALSE
     ) THEN
    RAISE EXCEPTION 'Résolution legacy a contourné le validateur financier : %', v_result;
  END IF;

  v_result := public.fn_admin_trancher_litige(
    v_litige_admin,
    'PARTAGE',
    'Motif administrateur suffisamment détaillé pour arbitrer le litige non financier.'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'statut_final' IS DISTINCT FROM 'RESOLU_PARTAGE' THEN
    RAISE EXCEPTION 'Arbitrage non financier légitime refusé : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$litige_flow$;

ROLLBACK;
