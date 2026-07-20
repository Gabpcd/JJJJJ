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
  v_etab_metadata uuid := 'abac0000-0000-4000-8000-000000000005'::uuid;
  v_soignant uuid := 'abac0000-0000-4000-8000-000000000003'::uuid;
  v_mission uuid := gen_random_uuid();
  v_mission_pool_ide uuid := gen_random_uuid();
  v_mission_inverse uuid := gen_random_uuid();
  v_mission_sans_contact uuid := gen_random_uuid();
  v_candidature_pool uuid := gen_random_uuid();
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
  v_admin_partiel uuid := 'abac0001-0000-4000-8000-000000000009'::uuid;
  v_contact_metadata uuid := 'abac0001-0000-4000-8000-000000000007'::uuid;
  v_soignant_pool uuid := 'abac0001-0000-4000-8000-000000000008'::uuid;
  v_conversation uuid;
  v_conversation_generique uuid;
  v_conversation_malveillante uuid;
  v_conversation_support uuid;
  v_conversation_inverse uuid := gen_random_uuid();
  v_conversation_pool uuid;
  v_conversation_admin_soignant uuid;
  v_conversation_admin_etab uuid;
  v_nb_messages bigint;
  v_doc record;
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
    ),
    (
      v_etab_metadata, 'Fixture RBAC établissement metadata', '99140000000104',
      'CLINIQUE_PRIVEE', '4 rue du Test', 'Nantes', '44000',
      'rbac-etab-metadata@test.local', true
    );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_soignant, '00000000-0000-0000-0000-000000000000',
      'rbac-soignant@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    ),
    (
      v_soignant_pool, '00000000-0000-0000-0000-000000000000',
      'rbac-soignant-pool@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test,
    rpps_verifie, disponible_urgence, tous_documents_valides
  ) VALUES
    (
      v_soignant, 'Fixture', 'RBAC', 'rbac-soignant@test.local', 'IDE', true,
      true, false, true
    ),
    (
      v_soignant_pool, 'Fixture', 'Pool', 'rbac-soignant-pool@test.local',
      'IADE', true, true, true, true
    );

  -- Le Pool Urgence utilise le gate documentaire canonique. Génère toutes les
  -- preuves salariées critiques afin que le test couvre le vrai parcours.
  FOR v_doc IN
    SELECT drp.type_document, drp.a_expiration
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = 'IADE'
      AND drp.est_critique IS TRUE
      AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
      AND drp.type_document <> 'RPPS_ADELI'
  LOOP
    INSERT INTO public.documents_soignants (
      soignant_id, type_document, s3_cle, nom_fichier,
      statut_verification, est_critique, valide_jusqua, resultat_ia
    ) VALUES (
      v_soignant_pool,
      v_doc.type_document,
      'tests/rbac-pool/' || lower(v_doc.type_document::text),
      lower(v_doc.type_document::text) || '.pdf',
      'VERIFIE',
      true,
      CASE WHEN v_doc.a_expiration THEN current_date + 365 ELSE NULL END,
      CASE WHEN v_doc.type_document = 'DIPLOME'
        THEN '{"profession_certifiee":"IADE"}'::jsonb
        ELSE '{}'::jsonb
      END
    );
  END LOOP;

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
    (v_admin_partiel, '00000000-0000-0000-0000-000000000000',
     'rbac-admin-partiel@test.local', 'authenticated', 'authenticated',
     '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_etab_legacy, '00000000-0000-0000-0000-000000000000',
     'rbac-etab-legacy@test.local', 'authenticated', 'authenticated',
     '{"role":"ADMIN_ETABLISSEMENT"}', now()),
    (v_contact_metadata, '00000000-0000-0000-0000-000000000000',
     'rbac-etab-metadata-contact@test.local', 'authenticated', 'authenticated',
     jsonb_build_object(
       'role', 'ADMIN_ETABLISSEMENT',
       'etablissement_id', v_etab_metadata::text
     ), now());

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
  ) VALUES
    (
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
    ),
    (
      v_admin_partiel,
      'RBAC',
      'Admin partiel',
      'rbac-admin-partiel@test.local',
      true,
      ARRAY['Messagerie']::text[]
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
    type_contrat_recherche, mode_attribution, soignant_assigne_id,
    type_contrat_applique
  ) VALUES
    (
      v_mission, v_etab_a, 'Fixture RBAC RPC', 'IDE',
      now() + interval '1 day', now() + interval '2 days', 24, 20, 'TERMINEE',
      'SALARIE', 'CANDIDATURE', v_soignant, 'SALARIE'
    ),
    (
      v_mission_pool_ide, v_etab_a, 'Fixture Pool mission IDE', 'IDE',
      now() + interval '3 days', now() + interval '4 days', 24, 20, 'OUVERTE',
      'SALARIE', 'CANDIDATURE', NULL, NULL
    ),
    (
      v_mission_inverse, v_etab_a, 'Fixture conversation inverse', 'IDE',
      now() + interval '5 days', now() + interval '5 days 8 hours',
      8, 20, 'ASSIGNEE', 'SALARIE', 'CANDIDATURE', v_soignant_pool,
      'SALARIE'
    ),
    (
      v_mission_sans_contact, v_etab_b, 'Fixture attribution sans contact', 'IDE',
      now() + interval '6 days', now() + interval '6 days 8 hours',
      8, 20, 'OUVERTE', 'SALARIE', 'CANDIDATURE', NULL, NULL
    );
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  INSERT INTO public.candidatures (
    id, mission_id, soignant_id, statut, type_contrat_choisi
  ) VALUES (
    v_candidature_pool,
    v_mission_pool_ide,
    v_soignant_pool,
    'EN_ATTENTE',
    'SALARIE'
  );
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
    'request.jwt.claim.sub', v_lecture::text, true
  );
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
  v_result := public.fn_traiter_candidature(
    v_candidature_pool, 'ACCEPTEE', NULL
  );
  IF v_result->>'error' IS DISTINCT FROM 'Non autorisé'
     OR (
       SELECT c.statut::text FROM public.candidatures c
       WHERE c.id = v_candidature_pool
     ) IS DISTINCT FROM 'EN_ATTENTE' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a traité une candidature : %', v_result;
  END IF;

  SELECT p.valide_par_etablissement INTO v_validee
  FROM public.presences p WHERE p.id = v_presence;
  IF v_validee IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Présence modifiée par LECTURE_SEULE';
  END IF;

  -- Un RH d'un autre établissement possède bien pointage/missions chez lui,
  -- mais reste borné à ce périmètre dans les RPC.
  PERFORM set_config(
    'request.jwt.claim.sub', v_cross_rh::text, true
  );
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
  v_result := public.fn_traiter_candidature(
    v_candidature_pool, 'REFUSEE', 'Refus cross établissement'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Non autorisé'
     OR (
       SELECT c.statut::text FROM public.candidatures c
       WHERE c.id = v_candidature_pool
     ) IS DISTINCT FROM 'EN_ATTENTE' THEN
    RAISE EXCEPTION 'Traitement candidature cross-etab accepté : %', v_result;
  END IF;

  SELECT p.valide_par_etablissement INTO v_validee
  FROM public.presences p WHERE p.id = v_presence;
  IF v_validee IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Présence modifiée depuis un autre établissement';
  END IF;

  -- Rôles légitimes : POINTAGE_ONLY valide, ADMIN_GROUPE édite le profil,
  -- RH atteint la garde métier de statut (donc passe bien le RBAC missions).
  PERFORM set_config(
    'request.jwt.claim.sub', v_pointage::text, true
  );
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
    'request.jwt.claim.sub', v_admin_groupe::text, true
  );
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
    'request.jwt.claim.sub', v_rh::text, true
  );
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

  -- Messagerie : fonctions SECURITY DEFINER, search_path vide et aucune voie
  -- de contournement par INSERT/UPDATE direct sur les tables.
  IF has_table_privilege(
       'authenticated', 'public.conversations', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.conversations', 'UPDATE'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.messages_chat', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.messages_chat', 'UPDATE'
     ) IS DISTINCT FROM FALSE
     OR EXISTS (
       SELECT 1
       FROM pg_policies p
       WHERE p.schemaname = 'public'
         AND p.tablename = 'conversations'
         AND p.policyname IN ('pol_conv_insert', 'pol_conv_update')
     )
     OR EXISTS (
       SELECT 1
       FROM pg_policies p
       WHERE p.schemaname = 'public'
         AND p.tablename = 'messages_chat'
         AND p.policyname IN ('pol_msg_chat_insert', 'pol_mchat_update')
     )
     OR has_function_privilege(
       'service_role',
       'public.fn_obtenir_conversation(uuid,uuid)',
       'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'authenticated',
       'public.fn_envoyer_message(uuid,text)',
       'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'service_role',
       'public.fn_envoyer_message(uuid,text)',
       'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'authenticated',
       'public.fn_envoyer_message_valide(uuid,text,uuid,boolean,text)',
       'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'service_role',
       'public.fn_envoyer_message_valide(uuid,text,uuid,boolean,text)',
       'EXECUTE'
     ) IS DISTINCT FROM TRUE
     OR has_function_privilege(
       'authenticated',
       'public.fn_notifier_candidature_acceptee(uuid,uuid,text,text)',
       'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'service_role',
       'public.fn_notifier_candidature_acceptee(uuid,uuid,text,text)',
       'EXECUTE'
     ) IS DISTINCT FROM TRUE
     OR has_table_privilege(
       'authenticated', 'public.typing_status', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.typing_status', 'UPDATE'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.typing_status', 'DELETE'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.typing_status', 'SELECT'
     ) IS DISTINCT FROM TRUE
     OR has_table_privilege(
       'authenticated', 'public.presence_status', 'SELECT'
     ) IS DISTINCT FROM TRUE
     OR has_function_privilege(
       'authenticated', 'public.fn_typing_start(uuid)', 'EXECUTE'
     ) IS DISTINCT FROM TRUE
     OR has_function_privilege(
       'authenticated', 'public.fn_typing_stop(uuid)', 'EXECUTE'
     ) IS DISTINCT FROM TRUE
     OR has_function_privilege(
       'authenticated', 'public.fn_update_presence()', 'EXECUTE'
     ) IS DISTINCT FROM TRUE
     OR has_function_privilege(
       'service_role', 'public.fn_typing_start(uuid)', 'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'service_role', 'public.fn_typing_stop(uuid)', 'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'service_role', 'public.fn_update_presence()', 'EXECUTE'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.messages_mission', 'SELECT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.messages_mission', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'anon', 'public.messages_mission', 'SELECT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'anon', 'public.messages_mission', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.messages_litige', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'public.messages_contact', 'INSERT'
     ) IS DISTINCT FROM FALSE
     OR EXISTS (
       SELECT 1
       FROM pg_policies p
       WHERE p.schemaname = 'public'
         AND p.tablename = 'typing_status'
         AND p.policyname IN (
           'pol_typing_status_upsert', 'pol_typing_status_delete'
         )
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname = 'fn_obtenir_conversation'
         AND p.prosecdef IS TRUE
         AND EXISTS (
           SELECT 1 FROM unnest(p.proconfig) cfg
           WHERE cfg = 'search_path=""'
         )
     ) THEN
    RAISE EXCEPTION 'Frontière SQL de la messagerie invalide';
  END IF;

  -- Fallback metadata positif, puis révocation canonique : une métadonnée
  -- serveur obsolète ne doit jamais ressusciter le contact.
  IF public.fn_user_id_pour_etablissement(v_etab_metadata)
       IS DISTINCT FROM v_contact_metadata THEN
    RAISE EXCEPTION 'Fallback interlocuteur metadata invalide';
  END IF;
  INSERT INTO public.membres_etablissement(
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etab_metadata, v_contact_metadata, 'RH', false
  );
  IF public.fn_user_id_pour_etablissement(v_etab_metadata) IS NOT NULL THEN
    RAISE EXCEPTION 'Une metadata a ressuscité un membre révoqué';
  END IF;
  DELETE FROM public.membres_etablissement
  WHERE etablissement_id = v_etab_metadata
    AND user_id = v_contact_metadata;

  -- Le fallback UUID historique est lui aussi neutralisé par toute ligne de
  -- membership cible inactive.
  INSERT INTO public.membres_etablissement(
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etab_legacy, v_etab_legacy, 'PROPRIETAIRE', false
  );
  IF public.fn_user_id_pour_etablissement(v_etab_legacy) IS NOT NULL THEN
    RAISE EXCEPTION 'Le fallback UUID a ressuscité un membre révoqué';
  END IF;
  DELETE FROM public.membres_etablissement
  WHERE etablissement_id = v_etab_legacy
    AND user_id = v_etab_legacy;

  -- Aucun rôle de lecture/pointage ne devient destinataire de conversations.
  UPDATE public.membres_etablissement
  SET actif = false
  WHERE etablissement_id = v_etab_a
    AND user_id IN (v_admin_groupe, v_rh);
  IF public.fn_user_id_pour_etablissement(v_etab_a) IS NOT NULL THEN
    RAISE EXCEPTION 'Un rôle faible a été choisi comme interlocuteur';
  END IF;
  UPDATE public.membres_etablissement
  SET actif = true
  WHERE etablissement_id = v_etab_a
    AND user_id IN (v_admin_groupe, v_rh);

  -- Une seconde appartenance active est autorisée même si elle n'est pas celle
  -- renvoyée par mon_etablissement_id().
  INSERT INTO public.membres_etablissement(
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etab_b, v_lecture, 'LECTURE_SEULE', true
  );
  PERFORM set_config('request.jwt.claim.sub', v_lecture::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_lecture, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_user_id_pour_etablissement(v_etab_b)
       IS DISTINCT FROM v_cross_rh THEN
    RAISE EXCEPTION 'Seconde appartenance établissement refusée';
  END IF;

  -- Le rôle LECTURE_SEULE ne doit pas pouvoir gérer l'équipe. Le nettoyage de
  -- cette fixture est donc explicitement effectué par le rôle serveur.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config(
    'request.jwt.claims',
    '{"role":"service_role"}',
    true
  );
  DELETE FROM public.membres_etablissement
  WHERE etablissement_id = v_etab_b AND user_id = v_lecture;

  -- Un tiers d'un autre établissement reste refusé avec le SQLSTATE attendu.
  PERFORM set_config('request.jwt.claim.sub', v_cross_rh::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_cross_rh, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM public.fn_user_id_pour_etablissement(v_etab_a);
    RAISE EXCEPTION USING ERRCODE = 'JRB02', MESSAGE = 'resolver cross-etab accepté';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  UPDATE auth.users SET banned_until = now() + interval '1 hour'
  WHERE id = v_cross_rh;
  BEGIN
    PERFORM public.fn_user_id_pour_etablissement(v_etab_b);
    RAISE EXCEPTION USING ERRCODE = 'JRB03', MESSAGE = 'resolver inactif accepté';
  EXCEPTION WHEN SQLSTATE '28000' THEN NULL;
  END;
  UPDATE auth.users SET banned_until = NULL WHERE id = v_cross_rh;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}'::text, true);
  BEGIN
    PERFORM public.fn_user_id_pour_etablissement(v_etab_a);
    RAISE EXCEPTION USING ERRCODE = 'JRB04', MESSAGE = 'resolver anonyme accepté';
  EXCEPTION WHEN SQLSTATE '28000' THEN NULL;
  END;

  -- Une conversation générique préexistante ne peut pas être réutilisée pour
  -- contourner le contrôle d'une mission explicitement demandée.
  INSERT INTO public.conversations(
    participant_1_id, participant_2_id, mission_id
  ) VALUES (
    LEAST(v_soignant, v_admin_groupe),
    GREATEST(v_soignant, v_admin_groupe),
    NULL
  ) RETURNING id INTO v_conversation_generique;

  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_conversation := public.fn_obtenir_conversation(
    v_admin_groupe,
    v_mission
  );
  IF v_conversation IS NULL
     OR v_conversation = v_conversation_generique
     OR NOT EXISTS (
       SELECT 1 FROM public.conversations c
       WHERE c.id = v_conversation AND c.mission_id = v_mission
     ) THEN
    RAISE EXCEPTION 'Conversation mission soignant vers établissement invalide';
  END IF;
  v_result := public.fn_envoyer_message(
    v_conversation,
    'Message mission à marquer comme lu'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Envoi participant légitime refusé : %', v_result;
  END IF;

  -- Le seul chemin d'envoi exposé au backend conserve le texte brut et
  -- revalide immédiatement le statut post-confirmation avant l'INSERT.
  v_result := public.fn_envoyer_message_valide(
    v_conversation,
    'A & B et 1 < 2',
    v_soignant,
    false,
    'TELEPHONE'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR NOT EXISTS (
       SELECT 1
       FROM public.messages_chat mc
       WHERE mc.id = (v_result->>'message_id')::uuid
         AND mc.conversation_id = v_conversation
         AND mc.contenu = 'A & B et 1 < 2'
     ) THEN
    RAISE EXCEPTION 'Envoi atomique TERMINEE altéré ou refusé : %', v_result;
  END IF;

  -- Présence active : un vrai participant peut démarrer/arrêter sa saisie.
  PERFORM public.fn_typing_start(v_conversation);
  IF NOT EXISTS (
    SELECT 1 FROM public.typing_status ts
    WHERE ts.conversation_id = v_conversation
      AND ts.user_id = v_soignant
  ) THEN
    RAISE EXCEPTION 'Typing participant actif non créé';
  END IF;
  PERFORM public.fn_typing_stop(v_conversation);
  IF EXISTS (
    SELECT 1 FROM public.typing_status ts
    WHERE ts.conversation_id = v_conversation
      AND ts.user_id = v_soignant
  ) THEN
    RAISE EXCEPTION 'Typing participant actif non supprimé';
  END IF;

  -- Une archive est strictement en lecture seule pour le typing comme pour
  -- l'envoi, sans effacer le brouillon côté client.
  UPDATE public.conversations
  SET archived_at = pg_catalog.now()
  WHERE id = v_conversation;
  BEGIN
    PERFORM public.fn_typing_start(v_conversation);
    RAISE EXCEPTION USING ERRCODE = 'JRB15', MESSAGE = 'typing archive accepté';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  SELECT count(*) INTO v_nb_messages
  FROM public.messages_chat mc
  WHERE mc.conversation_id = v_conversation;
  v_result := public.fn_envoyer_message_valide(
    v_conversation,
    'Message archive refusé',
    v_soignant,
    false,
    NULL
  );
  IF v_result->>'error' IS DISTINCT FROM 'Cette conversation est archivée.'
     OR (
       SELECT count(*) FROM public.messages_chat mc
       WHERE mc.conversation_id = v_conversation
     ) IS DISTINCT FROM v_nb_messages THEN
    RAISE EXCEPTION 'Conversation archivée encore mutable : %', v_result;
  END IF;
  UPDATE public.conversations SET archived_at = NULL
  WHERE id = v_conversation;

  v_result := public.fn_envoyer_message_valide(
    gen_random_uuid(),
    'Conversation inconnue',
    v_soignant,
    false,
    NULL
  );
  IF v_result->>'error' IS DISTINCT FROM 'Conversation introuvable' THEN
    RAISE EXCEPTION 'Conversation inconnue non refusée : %', v_result;
  END IF;

  BEGIN
    PERFORM public.fn_obtenir_conversation(v_lecture, v_mission);
    RAISE EXCEPTION USING ERRCODE = 'JRB05', MESSAGE = 'rôle lecture destinataire';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_obtenir_conversation(v_soignant, v_mission);
    RAISE EXCEPTION USING ERRCODE = 'JRB06', MESSAGE = 'conversation avec soi-même';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_obtenir_conversation(NULL, v_mission);
    RAISE EXCEPTION USING ERRCODE = 'JRB07', MESSAGE = 'cible NULL acceptée';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- Sens inverse : le responsable du bon établissement retrouve exactement la
  -- même conversation, sans doublon.
  PERFORM set_config('request.jwt.claim.sub', v_admin_groupe::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_groupe, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_obtenir_conversation(v_soignant, v_mission)
       IS DISTINCT FROM v_conversation
     OR (
       SELECT count(*) FROM public.conversations c
       WHERE c.mission_id = v_mission
         AND c.participant_1_id = LEAST(v_soignant, v_admin_groupe)
         AND c.participant_2_id = GREATEST(v_soignant, v_admin_groupe)
     ) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'Conversation mission non idempotente dans les deux sens';
  END IF;

  PERFORM public.fn_marquer_messages_lus(v_conversation);
  IF EXISTS (
    SELECT 1
    FROM public.messages_chat mc
    WHERE mc.conversation_id = v_conversation
      AND mc.auteur_id = v_soignant
      AND mc.lu IS FALSE
  ) THEN
    RAISE EXCEPTION 'Le participant destinataire ne peut pas marquer comme lu';
  END IF;
  v_result := public.fn_envoyer_message(
    v_conversation,
    'Réponse établissement conservée non lue pour le soignant'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réponse établissement légitime refusée : %', v_result;
  END IF;

  -- Pool Urgence : un responsable peut joindre un soignant effectivement
  -- éligible sans historique. Le profil IADE apparaît bien pour la mission IDE :
  -- la règle est celle de la profession demandée, pas celle du diplôme.
  IF NOT EXISTS (
    SELECT 1
    FROM public.fn_pool_urgence_etablissement(v_etab_a) p
    WHERE p.soignant_id = v_soignant_pool
      AND p.profession = 'IADE'
  ) THEN
    RAISE EXCEPTION 'Profil IADE absent du Pool pour une mission IDE compatible';
  END IF;
  v_conversation_pool := public.fn_obtenir_conversation(v_soignant_pool, NULL);
  IF v_conversation_pool IS NULL THEN
    RAISE EXCEPTION 'Conversation Pool Urgence légitime refusée';
  END IF;
  SELECT count(*) INTO v_nb_messages
  FROM public.messages_chat mc
  WHERE mc.conversation_id = v_conversation_pool;
  v_result := public.fn_envoyer_message_valide(
    v_conversation_pool,
    'Contact interdit avant confirmation : test@example.fr',
    v_admin_groupe,
    false,
    'EMAIL'
  );
  IF v_result->>'error' IS DISTINCT FROM 'ANTI_LEAK_REFUSE'
     OR v_result->>'detected_type' IS DISTINCT FROM 'EMAIL'
     OR (
       SELECT count(*) FROM public.messages_chat mc
       WHERE mc.conversation_id = v_conversation_pool
     ) IS DISTINCT FROM v_nb_messages THEN
    RAISE EXCEPTION 'Anti-fuite pré-confirmation contournable : %', v_result;
  END IF;

  -- La même autorisation doit être symétrique : le soignant sélectionné dans
  -- le Pool voit le canal créé par l'établissement et peut répondre.
  PERFORM set_config('request.jwt.claim.sub', v_soignant_pool::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant_pool, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_conversation_accessible(v_conversation_pool)
       IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Conversation Pool masquée au soignant ciblé';
  END IF;
  v_result := public.fn_envoyer_message(
    v_conversation_pool,
    'Réponse du soignant au responsable Pool'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réponse du soignant Pool refusée : %', v_result;
  END IF;

  -- Les rôles lecture/pointage ne peuvent pas extraire les données du Pool.
  PERFORM set_config('request.jwt.claim.sub', v_lecture::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_lecture, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM 1 FROM public.fn_pool_urgence_etablissement(v_etab_a);
    RAISE EXCEPTION USING ERRCODE = 'JRB13', MESSAGE = 'rôle faible a lu le Pool';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  -- L'opt-out emprunte le chemin utilisateur canonique, puis l'établissement
  -- perd immédiatement le droit d'ouvrir ou de réutiliser la conversation.
  PERFORM set_config('request.jwt.claim.sub', v_soignant_pool::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant_pool, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_toggle_pool_urgence(false, 15, NULL);
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Désactivation canonique du Pool refusée : %', v_result;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_admin_groupe::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_groupe, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM public.fn_obtenir_conversation(v_soignant_pool, NULL);
    RAISE EXCEPTION USING ERRCODE = 'JRB08', MESSAGE = 'hors Pool accepté';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub', v_soignant_pool::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant_pool, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_toggle_pool_urgence(true, 15, NULL);
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réactivation canonique du Pool refusée : %', v_result;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_admin_groupe::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_groupe, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );

  UPDATE auth.users SET banned_until = now() + interval '1 hour'
  WHERE id = v_soignant_pool;
  BEGIN
    PERFORM public.fn_obtenir_conversation(v_soignant_pool, NULL);
    RAISE EXCEPTION USING ERRCODE = 'JRB09', MESSAGE = 'cible bannie acceptée';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  UPDATE auth.users SET banned_until = NULL WHERE id = v_soignant_pool;

  -- Une ligne arbitraire préexistante est contrôlée avant lookup et avant tout
  -- envoi : connaître son UUID ne rend pas le canal exploitable.
  INSERT INTO public.conversations(
    participant_1_id, participant_2_id, mission_id
  ) VALUES (
    LEAST(v_cross_rh, v_soignant),
    GREATEST(v_cross_rh, v_soignant),
    v_mission
  ) RETURNING id INTO v_conversation_malveillante;
  PERFORM set_config('request.jwt.claim.sub', v_cross_rh::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_cross_rh, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM public.fn_obtenir_conversation(v_soignant, v_mission);
    RAISE EXCEPTION USING ERRCODE = 'JRB10', MESSAGE = 'BOLA existant retourné';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  SELECT count(*) INTO v_nb_messages
  FROM public.messages_chat mc
  WHERE mc.conversation_id = v_conversation_malveillante;
  v_result := public.fn_envoyer_message(
    v_conversation_malveillante,
    'Message qui doit être refusé'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé'
     OR (
       SELECT count(*) FROM public.messages_chat mc
       WHERE mc.conversation_id = v_conversation_malveillante
     ) IS DISTINCT FROM v_nb_messages THEN
    RAISE EXCEPTION 'Une conversation BOLA historique reste exploitable : %', v_result;
  END IF;
  v_result := public.fn_envoyer_message_valide(
    v_conversation_malveillante,
    'BOLA également refusé par le chemin Edge',
    v_cross_rh,
    false,
    'TELEPHONE'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé'
     OR (
       SELECT count(*) FROM public.messages_chat mc
       WHERE mc.conversation_id = v_conversation_malveillante
     ) IS DISTINCT FROM v_nb_messages THEN
    RAISE EXCEPTION 'Chemin atomique exploitable en BOLA : %', v_result;
  END IF;
  BEGIN
    PERFORM public.fn_marquer_messages_lus(v_conversation);
    RAISE EXCEPTION USING ERRCODE = 'JRB14', MESSAGE = 'tiers a marqué comme lu';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  -- Admin plateforme : AAL1 n'est pas admin ; AAL2 peut contacter un endpoint
  -- réel, mais ne peut pas rattacher un tiers étranger à la mission.
  PERFORM set_config('request.jwt.claim.sub', v_admin_plateforme::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM public.fn_obtenir_conversation(v_soignant, v_mission);
    RAISE EXCEPTION USING ERRCODE = 'JRB11', MESSAGE = 'admin AAL1 accepté';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  -- La modération AAL2 peut envoyer via le chemin atomique, mais un admin qui
  -- n'est pas participant ne doit jamais émettre un typing fantôme.
  BEGIN
    PERFORM public.fn_typing_start(v_conversation);
    RAISE EXCEPTION USING
      ERRCODE = 'JRB16', MESSAGE = 'typing admin non-participant accepté';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  IF EXISTS (
    SELECT 1 FROM public.typing_status ts
    WHERE ts.conversation_id = v_conversation
      AND ts.user_id = v_admin_plateforme
  ) THEN
    RAISE EXCEPTION 'Typing fantôme administrateur créé';
  END IF;
  v_result := public.fn_envoyer_message_valide(
    v_conversation,
    'Intervention de modération AAL2',
    v_admin_plateforme,
    true,
    NULL
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR NOT EXISTS (
       SELECT 1 FROM public.messages_chat mc
       WHERE mc.id = (v_result->>'message_id')::uuid
         AND mc.est_admin IS TRUE
         AND mc.auteur_id = v_admin_plateforme
     ) THEN
    RAISE EXCEPTION 'Envoi atomique admin AAL2 refusé : %', v_result;
  END IF;
  v_conversation_admin_soignant :=
    public.fn_obtenir_conversation(v_soignant, v_mission);
  v_conversation_admin_etab :=
    public.fn_obtenir_conversation(v_admin_groupe, v_mission);
  IF v_conversation_admin_soignant IS NULL
     OR v_conversation_admin_etab IS NULL
     OR public.fn_obtenir_conversation(v_soignant_pool, NULL) IS NULL THEN
    RAISE EXCEPTION 'Admin AAL2 refusé sur un endpoint actif';
  END IF;

  -- Une conversation de modération créée par l'admin reste lisible et
  -- répondable par chacun des deux types d'endpoint métier de la mission.
  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_conversation_accessible(v_conversation_admin_soignant)
       IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Conversation admin masquée au soignant ciblé';
  END IF;
  v_result := public.fn_envoyer_message(
    v_conversation_admin_soignant,
    'Réponse soignant à la modération Jolene'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réponse soignant vers admin refusée : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_groupe::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_groupe, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_conversation_accessible(v_conversation_admin_etab)
       IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Conversation admin masquée à l''établissement ciblé';
  END IF;
  v_result := public.fn_envoyer_message(
    v_conversation_admin_etab,
    'Réponse établissement à la modération Jolene'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réponse établissement vers admin refusée : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_plateforme::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );

  -- Un admin observateur peut consulter pour modération, sans modifier l'état
  -- de lecture des deux vrais participants.
  SELECT count(*) INTO v_nb_messages
  FROM public.messages_chat mc
  WHERE mc.conversation_id = v_conversation
    AND mc.lu IS FALSE;
  PERFORM public.fn_marquer_messages_lus(v_conversation);
  IF (
    SELECT count(*) FROM public.messages_chat mc
    WHERE mc.conversation_id = v_conversation
      AND mc.lu IS FALSE
  ) IS DISTINCT FROM v_nb_messages THEN
    RAISE EXCEPTION 'Admin observateur a modifié les accusés de lecture';
  END IF;

  -- Le canal support choisit exclusivement un admin complet du lancement. Un
  -- compte ayant le seul groupe Messagerie ne peut ni être ciblé, ni lire.
  PERFORM set_config('request.jwt.claim.sub', v_soignant::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_conversation_support := public.fn_contacter_support();
  IF NOT EXISTS (
    SELECT 1
    FROM public.conversations c
    WHERE c.id = v_conversation_support
      AND c.mission_id IS NULL
      AND v_soignant IN (c.participant_1_id, c.participant_2_id)
      AND v_admin_partiel NOT IN (c.participant_1_id, c.participant_2_id)
      AND EXISTS (
        SELECT 1
        FROM public.equipe_admin ea
        JOIN auth.users u ON u.id = ea.user_id
        WHERE ea.user_id = CASE
          WHEN c.participant_1_id = v_soignant THEN c.participant_2_id
          ELSE c.participant_1_id
        END
          AND ea.actif IS TRUE
          AND u.deleted_at IS NULL
          AND u.email_confirmed_at IS NOT NULL
          AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
          AND ARRAY[
            'Dashboard',
            'Utilisateurs',
            'Missions',
            'Litiges & contrats',
            'Finances',
            'Messagerie',
            'Conformité & Technique',
            'Fondateur'
          ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])
      )
  ) THEN
    RAISE EXCEPTION 'Le support n''a pas choisi l''admin complet canonique';
  END IF;
  v_result := public.fn_envoyer_message(
    v_conversation_support,
    'Demande de support transactionnelle'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Message vers support refusé : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_partiel::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_partiel, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  IF public.est_admin() IS DISTINCT FROM FALSE
     OR public.fn_conversation_accessible(v_conversation_support) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Admin partiel accepté dans le canal support';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_plateforme::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  v_result := public.fn_envoyer_message(
    v_conversation_support,
    'Réponse support transactionnelle'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Réponse support AAL2 refusée : %', v_result;
  END IF;
  BEGIN
    PERFORM public.fn_obtenir_conversation(v_cross_rh, v_mission);
    RAISE EXCEPTION USING ERRCODE = 'JRB12', MESSAGE = 'admin vers tiers mission';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  -- Le traitement public complet attribue la mission, accepte la candidature,
  -- crée le chat puis sa notification dans la même transaction. Les deux
  -- triggers convergent vers une conversation et un seul welcome.
  v_result := public.fn_traiter_candidature(
    v_candidature_pool,
    'ACCEPTEE',
    NULL
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Traitement canonique de la candidature refusé : %', v_result;
  END IF;

  SELECT c.id INTO v_conversation
  FROM public.conversations c
  WHERE c.mission_id = v_mission_pool_ide
    AND v_soignant_pool IN (c.participant_1_id, c.participant_2_id)
    AND v_admin_groupe IN (c.participant_1_id, c.participant_2_id)
  ORDER BY c.cree_le, c.id
  LIMIT 1;
  IF v_conversation IS NULL
     OR (
       SELECT count(*)
       FROM public.conversations c
       WHERE c.mission_id = v_mission_pool_ide
         AND v_soignant_pool IN (c.participant_1_id, c.participant_2_id)
         AND v_admin_groupe IN (c.participant_1_id, c.participant_2_id)
     ) IS DISTINCT FROM 1::bigint
     OR EXISTS (
       SELECT 1
       FROM public.conversations c
       WHERE c.mission_id = v_mission_pool_ide
         AND v_etab_a IN (c.participant_1_id, c.participant_2_id)
     ) THEN
    RAISE EXCEPTION
      'Trigger assignation : contact fantôme, doublon ou absence de conversation';
  END IF;
  IF public.fn_user_id_pour_etablissement(v_etab_a)
       IS DISTINCT FROM v_admin_groupe THEN
    RAISE EXCEPTION 'Resolver public et trigger ne partagent pas le même contact';
  END IF;
  IF (
    SELECT count(*)
    FROM public.messages_chat mc
    WHERE mc.conversation_id = v_conversation
      AND mc.auteur_id = '00000000-0000-0000-0000-000000000000'::uuid
      AND mc.est_admin IS TRUE
      AND mc.contenu LIKE '📋 Mission %assignée.%'
  ) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'Welcome système absent ou dupliqué après attribution';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM public.candidatures c
       WHERE c.id = v_candidature_pool
         AND c.statut = 'ACCEPTEE'
     )
     OR (
    SELECT count(*)
    FROM public.conversations c
    WHERE c.mission_id = v_mission_pool_ide
      AND v_soignant_pool IN (c.participant_1_id, c.participant_2_id)
      AND v_admin_groupe IN (c.participant_1_id, c.participant_2_id)
  ) IS DISTINCT FROM 1::bigint
     OR (
       SELECT count(*)
       FROM public.messages_chat mc
       WHERE mc.conversation_id = v_conversation
         AND mc.auteur_id = '00000000-0000-0000-0000-000000000000'::uuid
         AND mc.est_admin IS TRUE
     ) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'Cascade candidature incomplète ou chat/welcome dupliqué';
  END IF;

  IF (
    SELECT count(*)
    FROM public.notifications n
    WHERE n.destinataire_id = v_soignant_pool
      AND n.type = 'CANDIDATURE_ACCEPTEE'
      AND n.type_ressource = 'mission'
      AND n.id_ressource = v_mission_pool_ide
      AND n.lien = '/soignant/messagerie?conv=' || v_conversation::text
  ) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION
      'fn_traiter_candidature n''a pas produit la notification canonique';
  END IF;

  SELECT count(*) INTO v_nb_messages
  FROM public.notifications n
  WHERE n.type = 'CANDIDATURE_ACCEPTEE'
    AND n.id_ressource = v_mission_pool_ide;
  v_result := public.fn_notifier_candidature_acceptee(
    v_mission_pool_ide,
    v_soignant,
    'Notification invalide',
    'Cette notification ne doit jamais être créée'
  );
  IF v_result->>'error' IS DISTINCT FROM
       'Mission non attribuée à ce soignant'
     OR (
       SELECT count(*) FROM public.notifications n
       WHERE n.type = 'CANDIDATURE_ACCEPTEE'
         AND n.id_ressource = v_mission_pool_ide
     ) IS DISTINCT FROM v_nb_messages THEN
    RAISE EXCEPTION 'Helper notification accepte une paire invalide : %',
      v_result;
  END IF;

  v_result := public.fn_notifier_candidature_acceptee(
    v_mission_pool_ide,
    v_soignant_pool,
    'Candidature acceptée',
    'Notification transactionnelle de recette'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'conversation_id' IS DISTINCT FROM v_conversation::text THEN
    RAISE EXCEPTION 'Notification transactionnelle refusée : %', v_result;
  END IF;
  PERFORM public.fn_notifier_candidature_acceptee(
    v_mission_pool_ide,
    v_soignant_pool,
    'Candidature acceptée',
    'Notification transactionnelle de recette'
  );
  IF (
    SELECT count(*)
    FROM public.notifications n
    WHERE n.destinataire_id = v_soignant_pool
      AND n.type = 'CANDIDATURE_ACCEPTEE'
      AND n.type_ressource = 'mission'
      AND n.id_ressource = v_mission_pool_ide
      AND n.lien = '/soignant/messagerie?conv=' || v_conversation::text
  ) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'Notification d''acceptation absente, dupliquée ou mal routée';
  END IF;

  IF public.fn_creer_conversation_si_absente(
       v_mission_pool_ide,
       v_soignant_pool,
       v_etab_a
     ) IS DISTINCT FROM v_conversation THEN
    RAISE EXCEPTION 'Créateur système non idempotent après double trigger';
  END IF;

  -- Une conversation historique stockée dans l'orientation inverse est
  -- réutilisée et n'est jamais dupliquée sous forme canonique.
  INSERT INTO public.conversations (
    id, mission_id, participant_1_id, participant_2_id
  ) VALUES (
    v_conversation_inverse,
    v_mission_inverse,
    v_admin_groupe,
    v_soignant_pool
  );
  IF public.fn_creer_conversation_si_absente(
       v_mission_inverse,
       v_soignant_pool,
       v_etab_a
     ) IS DISTINCT FROM v_conversation_inverse
     OR (
       SELECT count(*)
       FROM public.conversations c
       WHERE c.mission_id = v_mission_inverse
         AND v_soignant_pool IN (c.participant_1_id, c.participant_2_id)
         AND v_admin_groupe IN (c.participant_1_id, c.participant_2_id)
  ) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'Conversation historique inverse non réutilisée';
  END IF;

  v_result := public.fn_envoyer_message_valide(
    v_conversation_inverse,
    'Coordonnées autorisées après assignation',
    v_admin_groupe,
    false,
    'TELEPHONE'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Envoi atomique ASSIGNEE refusé : %', v_result;
  END IF;

  INSERT INTO public.contrats_mission (
    mission_id,
    etablissement_id,
    soignant_id,
    type_contrat,
    numero_contrat,
    signature_etablissement,
    signature_etablissement_le,
    signature_soignant,
    signature_soignant_le,
    statut
  ) VALUES (
    v_mission_inverse,
    v_etab_a,
    v_soignant_pool,
    'CDDU',
    'RBAC-INVERSE-' || v_mission_inverse::text,
    true,
    pg_catalog.now(),
    true,
    pg_catalog.now(),
    'SIGNE_COMPLET'
  );
  UPDATE public.missions
  SET statut = 'EN_COURS'
  WHERE id = v_mission_inverse;
  v_result := public.fn_envoyer_message_valide(
    v_conversation_inverse,
    'Coordonnées autorisées mission en cours',
    v_soignant_pool,
    false,
    'EMAIL'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Envoi atomique EN_COURS refusé : %', v_result;
  END IF;

  -- Aucun interlocuteur opérationnel : l'attribution métier reste réussie,
  -- sans conversation fantôme vers l'UUID de l'établissement.
  UPDATE public.membres_etablissement
  SET actif = false
  WHERE etablissement_id = v_etab_b
    AND user_id = v_cross_rh;
  v_result := public.fn_finaliser_attribution_mission(
    v_mission_sans_contact,
    v_soignant_pool,
    'SALARIE'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR NOT EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id = v_mission_sans_contact
         AND m.statut = 'ASSIGNEE'
         AND m.soignant_assigne_id = v_soignant_pool
     )
     OR EXISTS (
       SELECT 1
       FROM public.conversations c
       WHERE c.mission_id = v_mission_sans_contact
          OR (
            v_etab_b IN (c.participant_1_id, c.participant_2_id)
            AND v_soignant_pool IN (c.participant_1_id, c.participant_2_id)
          )
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.journaux_audit ja
       WHERE ja.details ->> 'evenement' =
             'MESSAGERIE_CREATION_CONVERSATION_ECHEC'
         AND ja.details ->> 'mission_id' = v_mission_sans_contact::text
         AND ja.details ->> 'raison' =
             'interlocuteur_etablissement_introuvable'
     ) THEN
    RAISE EXCEPTION 'Échec chat a bloqué ou pollué une attribution valide : %',
      v_result;
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
       WHERE id IN (
         v_etab_a, v_etab_b, v_etab_legacy, v_etab_metadata
       )
     )
     OR EXISTS (
       SELECT 1 FROM public.soignants
       WHERE id IN (v_soignant, v_soignant_pool)
     )
     OR EXISTS (
       SELECT 1 FROM public.missions
       WHERE id IN (
         v_mission,
         v_mission_pool_ide,
         v_mission_inverse,
         v_mission_sans_contact
       )
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
         v_rh, v_cross_rh, v_admin_plateforme, v_admin_partiel, v_etab_legacy,
         v_contact_metadata, v_soignant_pool
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
