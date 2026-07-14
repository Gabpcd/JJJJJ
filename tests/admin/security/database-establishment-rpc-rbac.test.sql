-- RBAC intra-établissement des RPC SECURITY DEFINER sensibles.
-- Prérequis : migrations jusqu'à 20260714011105 appliquées.
-- Toutes les fixtures et mutations légitimes restent dans ce ROLLBACK.

\set ON_ERROR_STOP on
BEGIN;

DO $rbac_rpc$
DECLARE
  v_etab_a uuid := 'abac0000-0000-4000-8000-000000000001'::uuid;
  v_etab_b uuid := 'abac0000-0000-4000-8000-000000000002'::uuid;
  v_etab_legacy uuid := 'abac0000-0000-4000-8000-000000000004'::uuid;
  v_soignant uuid := 'abac0000-0000-4000-8000-000000000003'::uuid;
  v_mission uuid := gen_random_uuid();
  v_presence uuid := gen_random_uuid();
  v_litige_base uuid := gen_random_uuid();
  v_litige_financier uuid := gen_random_uuid();
  v_litige_sans_impact uuid := gen_random_uuid();
  v_litige_admin uuid := gen_random_uuid();
  v_lecture uuid := 'abac0001-0000-4000-8000-000000000001'::uuid;
  v_pointage uuid := 'abac0001-0000-4000-8000-000000000002'::uuid;
  v_admin_groupe uuid := 'abac0001-0000-4000-8000-000000000003'::uuid;
  v_rh uuid := 'abac0001-0000-4000-8000-000000000004'::uuid;
  v_cross_rh uuid := 'abac0001-0000-4000-8000-000000000005'::uuid;
  v_admin_plateforme uuid := 'abac0001-0000-4000-8000-000000000006'::uuid;
  v_result jsonb;
  v_validee boolean;
  v_payload_a jsonb := '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":100},"justification":"Proposition A"}'::jsonb;
  v_payload_b jsonb := '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":120},"justification":"Proposition B"}'::jsonb;
  v_payload_sans_impact jsonb := '{"type":"ACCORD_SANS_MODIFICATION","modifications":{},"justification":"Accord sans impact"}'::jsonb;
BEGIN
  -- Sous-transaction sentinelle : toute écriture (audit immuable et effets de
  -- bord inclus) est annulée avant qu'une suite SQL concaténée ne démarre.
  -- Seul le SQLSTATE privé de fin de test est absorbé ; toute assertion en
  -- échec conserve son SQLSTATE et fait donc échouer la recette.
  BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test
  ) VALUES
    (
      v_etab_a, 'Fixture RBAC établissement A', '99140000000101',
      'CLINIQUE_PRIVEE', '1 rue du Test', 'Paris', '75001',
      'rbac-etab-a@test.local', true
    ),
    (
      v_etab_b, 'Fixture RBAC établissement B', '99140000000102',
      'CLINIQUE_PRIVEE', '2 rue du Test', 'Lyon', '69001',
      'rbac-etab-b@test.local', true
    ),
    (
      v_etab_legacy, 'Fixture RBAC établissement historique', '99140000000103',
      'CLINIQUE_PRIVEE', '3 rue du Test', 'Lille', '59000',
      'rbac-etab-legacy@test.local', true
    );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES (
    v_soignant, '00000000-0000-0000-0000-000000000000',
    'rbac-soignant@test.local', 'authenticated', 'authenticated',
    '{"role":"SOIGNANT"}', now()
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test
  ) VALUES (
    v_soignant, 'Fixture', 'RBAC', 'rbac-soignant@test.local', 'IDE', true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (v_lecture, '00000000-0000-0000-0000-000000000000',
     'rbac-lecture@test.local', 'authenticated', 'authenticated',
     '{"role":"ETABLISSEMENT"}', now()),
    (v_pointage, '00000000-0000-0000-0000-000000000000',
     'rbac-pointage@test.local', 'authenticated', 'authenticated',
     '{"role":"ETABLISSEMENT"}', now()),
    (v_admin_groupe, '00000000-0000-0000-0000-000000000000',
     'rbac-admin-groupe@test.local', 'authenticated', 'authenticated',
     '{"role":"ETABLISSEMENT"}', now()),
    (v_rh, '00000000-0000-0000-0000-000000000000',
     'rbac-rh@test.local', 'authenticated', 'authenticated',
     '{"role":"ETABLISSEMENT"}', now()),
    (v_cross_rh, '00000000-0000-0000-0000-000000000000',
     'rbac-cross-rh@test.local', 'authenticated', 'authenticated',
     '{"role":"ETABLISSEMENT"}', now()),
    (v_admin_plateforme, '00000000-0000-0000-0000-000000000000',
     'rbac-admin-plateforme@test.local', 'authenticated', 'authenticated',
     '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_etab_legacy, '00000000-0000-0000-0000-000000000000',
     'rbac-etab-legacy@test.local', 'authenticated', 'authenticated',
     '{"role":"ADMIN_ETABLISSEMENT"}', now());

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES
    (v_etab_a, v_lecture, 'LECTURE_SEULE', true),
    (v_etab_a, v_pointage, 'POINTAGE_ONLY', true),
    (v_etab_a, v_admin_groupe, 'ADMIN_GROUPE', true),
    (v_etab_a, v_rh, 'RH', true),
    (v_etab_b, v_cross_rh, 'RH', true);

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin_plateforme,
    'RBAC',
    'Admin',
    'rbac-admin-plateforme@test.local',
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

  -- Fixtures transactionnelles : elles sont créées sans identité JWT, puis
  -- intégralement annulées par le ROLLBACK de cette suite.
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Test transactionnel RBAC des RPC établissement',
    true
  );
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config(
    'request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true
  );
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    type_contrat_recherche, mode_attribution
  ) VALUES (
    v_mission, v_etab_a, 'Fixture RBAC RPC', 'IDE',
    now() + interval '1 day', now() + interval '2 days', 24, 20, 'TERMINEE',
    'SALARIE', 'CANDIDATURE'
  );
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  INSERT INTO public.presences (
    id, mission_id, soignant_id, perimetre_gps_valide,
    alerte_teleportation, valide_par_etablissement
  ) VALUES (
    v_presence, v_mission, v_soignant, true, false, false
  );
  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par, motif,
    type_litige
  ) VALUES
    (v_litige_base, v_mission, v_soignant, v_etab_a,
     'SYSTEME', 'Fixture RBAC clôture simple', 'AUTRE'),
    (v_litige_financier, v_mission, v_soignant, v_etab_a,
     'SYSTEME', 'Fixture RBAC consentement financier',
     'DESACCORD_MONTANT_FACTURE'),
    (v_litige_sans_impact, v_mission, v_soignant, v_etab_a,
     'SYSTEME', 'Fixture RBAC consentement sans impact',
     'COMPORTEMENT_SOIGNANT'),
    (v_litige_admin, v_mission, v_soignant, v_etab_a,
     'SYSTEME', 'Fixture RBAC clôture admin', 'SECURITE_DANGER');
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  -- LECTURE_SEULE appartient bien au bon établissement mais ne peut muter
  -- aucun des trois domaines protégés.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_lecture, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.mon_etablissement_id() IS DISTINCT FROM v_etab_a
     OR public.fn_a_permission_etablissement(
       'pointage', v_etab_a
     ) IS DISTINCT FROM FALSE
     OR public.fn_a_permission_etablissement(
       'profil_etab', v_etab_a
     ) IS DISTINCT FROM FALSE
     OR public.fn_a_permission_etablissement(
       'paiement', v_etab_a
     ) IS DISTINCT FROM FALSE
     OR public.fn_a_permission_etablissement(
       'missions', v_etab_a
     ) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Matrice LECTURE_SEULE inattendue';
  END IF;

  v_result := public.fn_commission_info_etablissement();
  IF v_result IS NULL
     OR jsonb_typeof(v_result) IS DISTINCT FROM 'object'
     OR v_result ? 'error' THEN
    RAISE EXCEPTION 'LECTURE_SEULE privé de lecture_paiement : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a clôturé un litige : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    jsonb_build_object(
      'type', 'MODIFICATION_MONTANT',
      'modifications', jsonb_build_object('montant_total_corrige', 100),
      'justification', 'Proposition interdite lecture seule'
    )
  );
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a proposé un accord litige : %', v_result;
  END IF;

  v_result := public.fn_valider_presences_lot(ARRAY[v_presence]);
  IF v_result->>'error' IS DISTINCT FROM 'Non autorisé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a validé des présences : %', v_result;
  END IF;

  v_result := public.fn_modifier_tolerance_pointage_etab(100);
  IF v_result->>'error_code' IS DISTINCT FROM 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a modifié le profil établissement : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Tentative LECTURE_SEULE interdite'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a annulé via fn_annuler_mission_etab : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etablissement(
    v_mission, 'Tentative LECTURE_SEULE interdite'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Cette mission ne vous appartient pas' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a annulé via RPC legacy : %', v_result;
  END IF;

  SELECT p.valide_par_etablissement INTO v_validee
  FROM public.presences p WHERE p.id = v_presence;
  IF v_validee IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Présence modifiée par LECTURE_SEULE';
  END IF;

  -- Un RH d'un autre établissement possède bien pointage/missions chez lui,
  -- mais reste borné à ce périmètre dans les RPC.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_cross_rh, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.mon_etablissement_id() IS DISTINCT FROM v_etab_b
     OR public.fn_a_permission_etablissement(
       'pointage', v_etab_b
     ) IS DISTINCT FROM TRUE
     OR public.fn_a_permission_etablissement(
       'missions', v_etab_b
     ) IS DISTINCT FROM TRUE
     OR public.fn_a_permission_etablissement(
       'paiement', v_etab_a
     ) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Contexte RH cross-etab invalide';
  END IF;

  v_result := public.fn_commission_info_etablissement();
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'RH a lu les données de commission : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Clôture litige cross-etab acceptée : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    v_payload_sans_impact
  );
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Payload litige cross-etab accepté : %', v_result;
  END IF;

  v_result := public.fn_valider_presences_lot(ARRAY[v_presence]);
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR (v_result->>'nb_validees')::integer IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'Pointage cross-etab non borné : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Tentative RH depuis un autre établissement'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'Annulation cross-etab acceptée : %', v_result;
  END IF;

  SELECT p.valide_par_etablissement INTO v_validee
  FROM public.presences p WHERE p.id = v_presence;
  IF v_validee IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Présence modifiée depuis un autre établissement';
  END IF;

  -- Rôles légitimes : POINTAGE_ONLY valide, ADMIN_GROUPE édite le profil,
  -- RH atteint la garde métier de statut (donc passe bien le RBAC missions).
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_pointage, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_a_permission_etablissement(
    'paiement', v_etab_a
  ) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'POINTAGE_ONLY possède indûment la permission paiement';
  END IF;
  v_result := public.fn_commission_info_etablissement();
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a lu les données de commission : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a clôturé un litige : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    v_payload_sans_impact
  );
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a proposé un accord litige : %', v_result;
  END IF;
  v_result := public.fn_valider_presences_lot(ARRAY[v_presence]);
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR (v_result->>'nb_validees')::integer IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'POINTAGE_ONLY légitime refusé : %', v_result;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_groupe, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_a_permission_etablissement(
    'paiement', v_etab_a
  ) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'ADMIN_GROUPE privé de la permission paiement';
  END IF;
  v_result := public.fn_commission_info_etablissement();
  IF v_result IS NULL
     OR jsonb_typeof(v_result) IS DISTINCT FROM 'object'
     OR v_result ? 'error' THEN
    RAISE EXCEPTION 'ADMIN_GROUPE privé de lecture_paiement : %', v_result;
  END IF;
  v_result := public.fn_modifier_tolerance_pointage_etab(100);
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'ADMIN_GROUPE légitime refusé sur profil_etab : %', v_result;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_rh, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_commission_info_etablissement();
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'RH a lu les données de commission : %', v_result;
  END IF;

  -- Un objet sans type, un type inconnu ou des champs hors schéma ne créent
  -- jamais une nouvelle version de proposition.
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier, '{}'::jsonb
  );
  IF v_result->>'success' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Payload vide accepté : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    '{"type":"TYPE_INCONNU","modifications":{},"justification":"Test"}'::jsonb
  );
  IF v_result->>'success' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Type de payload inconnu accepté : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":-1},"justification":"Test"}'::jsonb
  );
  IF v_result->>'success' IS DISTINCT FROM 'false'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND l.payload_modifications IS NULL
         AND l.accord_soignant IS FALSE
         AND l.accord_etablissement IS FALSE
     ) THEN
    RAISE EXCEPTION 'Payload hors limites a muté le litige : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'accord_etablissement' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'RH légitime refusé sur clôture litige : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier, v_payload_a
  );
  IF v_result->>'statut' IS DISTINCT FROM 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' THEN
    RAISE EXCEPTION 'Première proposition établissement inattendue : %', v_result;
  END IF;

  -- L'endpoint simple ne peut pas consentir à une proposition financière.
  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_cloturer_litige(v_litige_financier, NULL);
  IF v_result->>'error' IS DISTINCT FROM
       'Un accord avec proposition doit être accepté via son payload exact' THEN
    RAISE EXCEPTION 'Endpoint simple a accepté un payload financier : %', v_result;
  END IF;
  v_result := public.fn_confirmer_accord_partie(v_litige_financier);
  IF v_result->>'success' IS DISTINCT FROM 'false'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND l.payload_modifications = v_payload_a
         AND l.accord_etablissement IS TRUE
         AND l.accord_soignant IS FALSE
     ) THEN
    RAISE EXCEPTION 'RPC legacy a accepté un payload sans JSON exact : %', v_result;
  END IF;

  -- Une proposition B après accord établissement sur A doit invalider cet
  -- accord opposé, sans résolution ni exécution anticipée.
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier, v_payload_b
  );
  IF v_result->>'statut' IS DISTINCT FROM 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' THEN
    RAISE EXCEPTION 'Changement de proposition A vers B a progressé : %', v_result;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.litiges l
    WHERE l.id = v_litige_financier
      AND l.payload_modifications = v_payload_b
      AND l.accord_soignant IS TRUE
      AND l.accord_soignant_le IS NOT NULL
      AND l.accord_etablissement IS FALSE
      AND l.accord_etablissement_le IS NULL
      AND l.statut IN (
        'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
      )
      AND l.modifications_executees IS FALSE
  ) THEN
    RAISE EXCEPTION 'Consentement A conservé après proposition distincte B';
  END IF;

  -- Une validation admin avant le second accord reste sans effet.
  PERFORM set_config(
    'request.jwt.claim.sub', v_admin_plateforme::text, true
  );
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  v_result := public.fn_admin_valider_accord_litige(v_litige_financier);
  IF v_result->>'success' IS DISTINCT FROM 'false'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND l.statut IN (
           'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'
         )
         AND l.modifications_executees IS FALSE
     ) THEN
    RAISE EXCEPTION 'Validation admin unilatérale acceptée : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );

  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_sans_impact, v_payload_sans_impact
  );
  IF v_result->>'statut' IS DISTINCT FROM 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' THEN
    RAISE EXCEPTION 'Proposition sans impact initiale inattendue : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_rh::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_rh, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier, v_payload_b
  );
  IF v_result->>'statut' IS DISTINCT FROM 'EN_ATTENTE_VALIDATION_ADMIN'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND l.payload_modifications = v_payload_b
         AND l.accord_soignant IS TRUE
         AND l.accord_etablissement IS TRUE
         AND l.statut = 'REVUE_ADMIN'
         AND l.modifications_executees IS FALSE
     ) THEN
    RAISE EXCEPTION 'Double accord financier exact non routé en revue : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_sans_impact, v_payload_sans_impact
  );
  IF v_result->>'statut' IS DISTINCT FROM 'RESOLU_ACCORD_PARTIES'
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_sans_impact
         AND l.statut = 'RESOLU_ACCORD_PARTIES'
         AND l.accord_soignant IS TRUE
         AND l.accord_etablissement IS TRUE
         AND l.modifications_executees IS TRUE
     ) THEN
    RAISE EXCEPTION 'Double accord sans impact non résolu canoniquement : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Contrôle rôle RH légitime sans mutation'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'STATUT_INVALIDE' THEN
    RAISE EXCEPTION 'RH légitime refusé avant la garde métier : %', v_result;
  END IF;
  v_result := public.fn_annuler_mission_etablissement(
    v_mission, 'Contrôle rôle RH légitime sans mutation'
  );
  IF v_result->>'error' IS NULL
     OR v_result->>'error' NOT LIKE 'Impossible d''annuler%' THEN
    RAISE EXCEPTION 'RH légitime refusé par la RPC legacy : %', v_result;
  END IF;

  -- Le même compte plateforme reste sans privilège à AAL1. À AAL2, un admin
  -- complet conserve ensuite paiement et le bypass transversal explicite,
  -- sans que la mission terminale puisse être mutée.
  PERFORM set_config(
    'request.jwt.claim.sub', v_admin_plateforme::text, true
  );
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.est_admin() IS DISTINCT FROM FALSE
     OR public.fn_a_permission_etablissement(
       'paiement', v_etab_a
     ) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Administrateur plateforme AAL1 accepté sur paiement';
  END IF;
  v_result := public.fn_cloturer_litige(v_litige_admin, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Administrateur plateforme AAL1 accepté sur litige : %', v_result;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  IF public.est_admin() IS DISTINCT FROM TRUE
     OR public.fn_a_permission_etablissement(
       'paiement', v_etab_a
     ) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Fixture administrateur plateforme invalide';
  END IF;
  IF public.fn_user_id_pour_etablissement(v_etab_a)
       IS DISTINCT FROM v_admin_groupe THEN
    RAISE EXCEPTION
      'Résolution interlocuteur membre actif invalide : attendu %, obtenu %',
      v_admin_groupe,
      public.fn_user_id_pour_etablissement(v_etab_a);
  END IF;
  IF public.fn_user_id_pour_etablissement(v_etab_legacy)
       IS DISTINCT FROM v_etab_legacy THEN
    RAISE EXCEPTION
      'Résolution interlocuteur établissement historique invalide';
  END IF;
  -- MODIFICATION_MONTANT n'est pas exécutable automatiquement au lancement :
  -- l'ancien worker transformait certains ajustements en avoir total. La
  -- validation doit retourner le routage manuel et conserver l'accord en REVUE_ADMIN
  -- pour le bouton « Résoudre (financier + statut) ».
  v_result := public.fn_admin_valider_accord_litige(v_litige_financier);
  IF v_result->>'success' IS DISTINCT FROM 'false'
     OR v_result->>'error_code' IS DISTINCT FROM
       'RESOLUTION_FINANCIERE_MANUELLE_REQUISE'
     OR v_result->>'manual_resolution_required' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Routage financier manuel invalide : %', v_result;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.litiges l
    WHERE l.id = v_litige_financier
      AND l.statut = 'REVUE_ADMIN'
      AND l.accord_soignant IS TRUE
      AND l.accord_etablissement IS TRUE
      AND l.modifications_executees IS FALSE
      AND l.modifications_executees_a IS NULL
  ) THEN
    RAISE EXCEPTION
      'Échec financier manuel non atomique ou dossier sorti de REVUE_ADMIN';
  END IF;
  v_result := public.fn_cloturer_litige(
    v_litige_admin, 'Clôture transactionnelle administrateur complet'
  );
  IF v_result->>'statut' IS DISTINCT FROM 'RESOLU_ADMIN' THEN
    RAISE EXCEPTION 'Administrateur complet refusé sur litige : %', v_result;
  END IF;
  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Contrôle administrateur complet sans mutation'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'STATUT_INVALIDE' THEN
    RAISE EXCEPTION 'Administrateur complet refusé avant la garde métier : %', v_result;
  END IF;
  v_result := public.fn_annuler_mission_etablissement(
    v_mission, 'Contrôle administrateur complet sans mutation'
  );
  IF v_result->>'error' IS NULL
     OR v_result->>'error' NOT LIKE 'Impossible d''annuler%' THEN
    RAISE EXCEPTION 'Administrateur complet refusé par la RPC legacy : %', v_result;
  END IF;

  RAISE EXCEPTION USING
    ERRCODE = 'JRB01',
    MESSAGE = 'RBAC_FIXTURES_ROLLBACK';
  EXCEPTION
    WHEN SQLSTATE 'JRB01' THEN NULL;
  END;

  IF EXISTS (
       SELECT 1 FROM public.etablissements
       WHERE id IN (v_etab_a, v_etab_b, v_etab_legacy)
     )
     OR EXISTS (
       SELECT 1 FROM public.soignants WHERE id = v_soignant
     )
     OR EXISTS (
       SELECT 1 FROM public.missions WHERE id = v_mission
     )
     OR EXISTS (
       SELECT 1 FROM public.litiges
       WHERE id IN (
         v_litige_base, v_litige_financier,
         v_litige_sans_impact, v_litige_admin
       )
     )
     OR EXISTS (
       SELECT 1 FROM auth.users
       WHERE id IN (
         v_soignant, v_lecture, v_pointage, v_admin_groupe,
         v_rh, v_cross_rh, v_admin_plateforme, v_etab_legacy
       )
     ) THEN
    RAISE EXCEPTION 'Sous-transaction RBAC non nettoyee';
  END IF;

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$rbac_rpc$;

ROLLBACK;
