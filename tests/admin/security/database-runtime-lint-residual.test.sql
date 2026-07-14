-- Régressions du solde PL/pgSQL pré-lancement.
-- Prérequis : migrations jusqu'à 20260714011105 appliquées.

\set ON_ERROR_STOP on
BEGIN;

CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;

CREATE TEMP TABLE jolene_lint_residuel_issues ON COMMIT DROP AS
WITH signatures(signature) AS (
  VALUES
    ('public.fn_admin_bfa_detail_groupe(uuid,integer)'),
    ('public.fn_admin_lever_suspension(uuid,text)'),
    ('public.fn_admin_reset_test_account(text)'),
    ('public.fn_annuler_mission(uuid,text)'),
    ('public.fn_annuler_mission_etab(uuid,text,text)'),
    ('public.fn_annuler_mission_etablissement(uuid,text)'),
    ('public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'),
    ('public.fn_calculer_remuneration_mission(timestamp with time zone,timestamp with time zone,numeric,uuid,uuid)'),
    ('public.fn_calculer_score_soignant(uuid)'),
    ('public.fn_charger_demo_investisseur()'),
    ('public.fn_commission_info_etablissement()'),
    ('public.fn_creer_serie(text,text,type_profession,text,numeric,boolean,integer,jsonb)'),
    ('public.fn_email_factures_impayees()'),
    ('public.fn_envoyer_rappels_notation_j1()'),
    ('public.fn_modifier_preferences_notifications(boolean,boolean,boolean,boolean,jsonb)'),
    ('public.fn_parrainage_verifier_seuils(uuid)'),
    ('public.fn_souscrire_prevoyance(uuid,text)'),
    ('private.fn_admin_creer_compte_employe_interne_lancement(text,text,text,text,text,numeric,text[])')
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

DO $lint$
BEGIN
  IF EXISTS (SELECT 1 FROM jolene_lint_residuel_issues) THEN
    RAISE EXCEPTION 'Lint PL/pgSQL résiduel : %', (
      SELECT jsonb_agg(to_jsonb(i)) FROM jolene_lint_residuel_issues i
    );
  END IF;
END;
$lint$;

DO $catalogue$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.fn_parrainage_verifier_seuils(uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_list_admin_user_ids[(][)] AS admins[(]admin_user_id[)]'
     OR v_definition !~ '''ADMIN''' THEN
    RAISE EXCEPTION 'Source admin du parrainage non canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_calculer_score_soignant(uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'FROM public[.]notations_missions'
     OR v_definition !~ 'ETAB_VERS_SOIGNANT'
     OR v_definition !~ 'publie_le IS NOT NULL' THEN
    RAISE EXCEPTION 'Source des notations soignant non canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_charger_demo_investisseur()'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ '''PRESERVATION'''
     OR v_definition ~* '\m(INSERT|UPDATE|DELETE)\M' THEN
    RAISE EXCEPTION 'RPC demo destructive ou mode preservation absent';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_envoyer_rappels_notation_j1()'::regprocedure
  ) INTO v_definition;
  IF regexp_count(v_definition, 'IF v_send_email_called THEN') <> 2 THEN
    RAISE EXCEPTION 'Marqueurs de rappel non conditionnes par le succes HTTP';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_email_factures_impayees()'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'email_contact'
     OR v_definition !~ 'date_echeance < CURRENT_DATE'
     OR v_definition !~ '''EN_RETARD''' THEN
    RAISE EXCEPTION 'Selection des factures impayees non canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_commission_info_etablissement()'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_compte_auth_actif[(][)] IS NOT TRUE'
     OR v_definition !~ '''lecture_paiement'''
     OR v_definition !~ 'e[.]id = v_etab_id' THEN
    RAISE EXCEPTION 'Accès aux commissions non borné par lecture_paiement';
  END IF;

  IF (
    SELECT p.provolatile <> 's'
    FROM pg_proc p
    WHERE p.oid = 'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure
  ) THEN
    RAISE EXCEPTION 'Calcul des heures majorees doit etre STABLE';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_annuler_mission(uuid,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'auth[.]uid[(][)] IS NULL'
     OR v_definition !~ 'IS DISTINCT FROM v_etab_id'
     OR v_definition !~ 'IS DISTINCT FROM auth[.]uid[(][)]' THEN
    RAISE EXCEPTION 'Garde fail-closed absente de fn_annuler_mission';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_annuler_mission_etab(uuid,text,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'etablissement_id IS DISTINCT FROM public[.]mon_etablissement_id'
     OR v_definition !~ 'fn_a_permission_etablissement[(][[:space:]]*''missions''[[:space:]]*,[[:space:]]*v_mission[.]etablissement_id[[:space:]]*[)] IS NOT TRUE' THEN
    RAISE EXCEPTION 'Garde fail-closed absente de fn_annuler_mission_etab';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_annuler_mission_etablissement(uuid,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'etablissement_id IS DISTINCT FROM public[.]mon_etablissement_id'
     OR v_definition !~ 'fn_a_permission_etablissement[(][[:space:]]*''missions''[[:space:]]*,[[:space:]]*v_mission[.]etablissement_id[[:space:]]*[)] IS NOT TRUE' THEN
    RAISE EXCEPTION 'Garde fail-closed absente de fn_annuler_mission_etablissement';
  END IF;

  IF has_function_privilege(
       'anon', 'public.fn_annuler_mission(uuid,text)', 'EXECUTE'
     ) OR has_function_privilege(
       'authenticated', 'public.fn_annuler_mission(uuid,text)', 'EXECUTE'
     ) OR has_function_privilege(
       'service_role', 'public.fn_annuler_mission(uuid,text)', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'RPC legacy fn_annuler_mission encore exposee';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(
        COALESCE(p.proacl, acldefault('f', p.proowner))
      ) acl
     WHERE p.oid = 'public.fn_annuler_mission(uuid,text)'::regprocedure
       AND acl.grantee = 0
       AND acl.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC execute encore present sur fn_annuler_mission';
  END IF;

  IF has_function_privilege(
       'anon', 'public.fn_souscrire_prevoyance(uuid,text)', 'EXECUTE'
     ) OR has_function_privilege(
       'authenticated', 'public.fn_souscrire_prevoyance(uuid,text)', 'EXECUTE'
     ) OR has_function_privilege(
       'service_role', 'public.fn_souscrire_prevoyance(uuid,text)', 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Souscription prevoyance legacy encore exposee';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'private.fn_admin_creer_compte_employe_interne_lancement(text,text,text,text,text,numeric,text[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Implémentation privée de création admin exposée';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.fn_admin_creer_compte_employe(text,text,text,text,text,numeric,text[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Wrapper admin de lancement devenu inaccessible';
  END IF;
END;
$catalogue$;

-- Appels uniquement sur des identifiants inexistants ou des branches sans DML.
DO $runtime_lecture_seule$
DECLARE
  v_result jsonb;
  v_heures record;
BEGIN
  -- Rend ce test autonome même lorsqu'il est concaténé après une suite qui a
  -- simulé un JWT dans la même transaction de validation.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  SELECT * INTO v_heures
  FROM public.fn_calculer_heures_majorees(
    '2026-01-06 22:00 Europe/Paris'::timestamptz,
    '2026-01-06 22:15 Europe/Paris'::timestamptz
  );
  IF v_heures.heures_nuit <> 0.25
     OR v_heures.heures_dimanche <> 0
     OR v_heures.heures_ferie <> 0 THEN
    RAISE EXCEPTION 'Calcul quart heure de nuit inattendu : %', row_to_json(v_heures);
  END IF;

  v_result := public.fn_calculer_remuneration_mission(
    now(),
    now(),
    20,
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
    NULL
  );
  IF v_result->>'type_contrat' <> 'CDD' THEN
    RAISE EXCEPTION 'Type contrat initial inattendu : %', v_result;
  END IF;

  v_result := public.fn_calculer_score_soignant(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
  );
  IF v_result->>'error' <> 'Soignant introuvable' THEN
    RAISE EXCEPTION 'Garde score inattendue : %', v_result;
  END IF;

  v_result := public.fn_admin_reset_test_account('ROLE_INCONNU');
  IF v_result->>'error' <> 'Rôle invalide' THEN
    RAISE EXCEPTION 'Garde reset test inattendue : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
    NULL
  );
  IF v_result->>'error' <> 'Mission introuvable' THEN
    RAISE EXCEPTION 'Garde annulation legacy inattendue : %', v_result;
  END IF;

  PERFORM public.fn_parrainage_verifier_seuils(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
  );

  v_result := public.fn_souscrire_prevoyance(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
    NULL
  );
  IF v_result->>'error' <> 'Acces refuse' THEN
    RAISE EXCEPTION 'Garde prévoyance inattendue : %', v_result;
  END IF;
END;
$runtime_lecture_seule$;

-- Preuve adverse BOLA sur donnees existantes, sans ecriture : chaque appel
-- doit sortir par la garde d'autorisation avant la moindre mutation. Le tout
-- reste de surcroit englobe dans la transaction ROLLBACK de ce fichier.
DO $bola_annulation$
DECLARE
  v_mission record;
  v_soignant_id uuid;
  v_cross_etab_user_id uuid;
  v_candidate record;
  v_result jsonb;
  v_statut_apres public.statut_mission;
  v_modifie_apres timestamptz;
BEGIN
  SELECT m.id, m.etablissement_id, m.soignant_assigne_id,
         m.statut, m.modifie_le
    INTO v_mission
    FROM public.missions m
   ORDER BY m.id
   LIMIT 1;

  IF v_mission.id IS NULL THEN
    RAISE EXCEPTION 'Fixture BOLA impossible : aucune mission cible';
  END IF;

  SELECT u.id
    INTO v_soignant_id
    FROM auth.users u
   WHERE u.raw_app_meta_data ->> 'role' = 'SOIGNANT'
     AND u.id IS DISTINCT FROM v_mission.soignant_assigne_id
     AND NOT EXISTS (
       SELECT 1
       FROM public.membres_etablissement me
       WHERE me.user_id = u.id
         AND me.actif IS TRUE
     )
   ORDER BY u.id
   LIMIT 1;

  IF v_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Fixture BOLA impossible : aucun soignant tiers';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_soignant_id, 'role', 'authenticated')::text,
    true
  );

  IF auth.uid() IS DISTINCT FROM v_soignant_id
     OR public.mon_etablissement_id() IS NOT NULL THEN
    RAISE EXCEPTION 'Contexte JWT soignant adverse invalide';
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission.id,
    'AUTRE',
    'Tentative adverse soignant sans etablissement'
  );
  IF v_result->>'error_code' <> 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'BOLA soignant acceptee par fn_annuler_mission_etab : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etablissement(
    v_mission.id,
    'Tentative adverse soignant'
  );
  IF v_result->>'error' <> 'Cette mission ne vous appartient pas' THEN
    RAISE EXCEPTION 'BOLA soignant acceptee par fn_annuler_mission_etablissement : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission(
    v_mission.id,
    'Tentative adverse soignant'
  );
  IF v_result->>'error' <> 'Accès refusé' THEN
    RAISE EXCEPTION 'BOLA soignant acceptee par fn_annuler_mission legacy : %', v_result;
  END IF;

  FOR v_candidate IN
    SELECT u.id
      FROM auth.users u
     WHERE u.raw_app_meta_data ->> 'role' IN (
       'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT'
     )
     ORDER BY u.id
  LOOP
    PERFORM set_config('request.jwt.claim.sub', v_candidate.id::text, true);
    PERFORM set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', v_candidate.id, 'role', 'authenticated')::text,
      true
    );

    IF public.mon_etablissement_id() IS NOT NULL
       AND public.mon_etablissement_id() IS DISTINCT FROM v_mission.etablissement_id THEN
      v_cross_etab_user_id := v_candidate.id;
      EXIT;
    END IF;
  END LOOP;

  IF v_cross_etab_user_id IS NULL THEN
    RAISE EXCEPTION 'Fixture BOLA impossible : aucun etablissement tiers';
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission.id,
    'AUTRE',
    'Tentative adverse depuis un autre etablissement'
  );
  IF v_result->>'error_code' <> 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'BOLA cross-etab acceptee par fn_annuler_mission_etab : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etablissement(
    v_mission.id,
    'Tentative adverse cross-etab'
  );
  IF v_result->>'error' <> 'Cette mission ne vous appartient pas' THEN
    RAISE EXCEPTION 'BOLA cross-etab acceptee par fn_annuler_mission_etablissement : %', v_result;
  END IF;

  SELECT m.statut, m.modifie_le
    INTO v_statut_apres, v_modifie_apres
    FROM public.missions m
   WHERE m.id = v_mission.id;

  IF v_statut_apres IS DISTINCT FROM v_mission.statut
     OR v_modifie_apres IS DISTINCT FROM v_mission.modifie_le THEN
    RAISE EXCEPTION 'Mission modifiee par une tentative BOLA';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$bola_annulation$;

ROLLBACK;
