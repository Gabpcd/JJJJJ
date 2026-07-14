-- RBAC intra-établissement des RPC SECURITY DEFINER sensibles.
-- Prérequis : migrations jusqu'à 20260714011105 appliquées.
-- Toutes les fixtures et mutations légitimes restent dans ce ROLLBACK.

\set ON_ERROR_STOP on
BEGIN;

DO $rbac_rpc$
DECLARE
  v_etab_a uuid;
  v_etab_b uuid;
  v_soignant uuid;
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
  SELECT e.id
    INTO v_etab_a
    FROM public.etablissements e
   WHERE e.supprime_le IS NULL
   ORDER BY e.id
   LIMIT 1;

  SELECT e.id
    INTO v_etab_b
    FROM public.etablissements e
   WHERE e.supprime_le IS NULL
     AND e.id IS DISTINCT FROM v_etab_a
   ORDER BY e.id
   LIMIT 1;

  SELECT s.id
    INTO v_soignant
    FROM public.soignants s
    JOIN auth.users u ON u.id = s.id
   WHERE s.supprime_le IS NULL
     AND u.deleted_at IS NULL
     AND (u.banned_until IS NULL OR u.banned_until <= now())
     AND u.email_confirmed_at IS NOT NULL
   ORDER BY s.id
   LIMIT 1;

  IF v_etab_a IS NULL OR v_etab_b IS NULL OR v_soignant IS NULL THEN
    RAISE EXCEPTION 'Fixtures RBAC impossibles : 2 établissements et 1 soignant requis';
  END IF;

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
     '{"role":"ADMIN_PLATEFORME"}', now());

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
    debut_le, fin_le, duree_heures, taux_horaire_base, statut
  ) VALUES (
    v_mission, v_etab_a, 'Fixture RBAC RPC', 'IDE',
    now() + interval '1 day', now() + interval '2 days', 24, 20, 'TERMINEE'
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
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
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
     OR public.fn_a_permission_etablissement('pointage', v_etab_a)
     OR public.fn_a_permission_etablissement('profil_etab', v_etab_a)
     OR public.fn_a_permission_etablissement('paiement', v_etab_a)
     OR public.fn_a_permission_etablissement('missions', v_etab_a) THEN
    RAISE EXCEPTION 'Matrice LECTURE_SEULE inattendue';
  END IF;

  v_result := public.fn_commission_info_etablissement();
  IF v_result ? 'error' THEN
    RAISE EXCEPTION 'LECTURE_SEULE privé de lecture_paiement : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
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
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a proposé un accord litige : %', v_result;
  END IF;

  v_result := public.fn_valider_presences_lot(ARRAY[v_presence]);
  IF v_result->>'error' <> 'Non autorisé' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a validé des présences : %', v_result;
  END IF;

  v_result := public.fn_modifier_tolerance_pointage_etab(100);
  IF v_result->>'error_code' <> 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a modifié le profil établissement : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Tentative LECTURE_SEULE interdite'
  );
  IF v_result->>'error_code' <> 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a annulé via fn_annuler_mission_etab : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etablissement(
    v_mission, 'Tentative LECTURE_SEULE interdite'
  );
  IF v_result->>'error' <> 'Cette mission ne vous appartient pas' THEN
    RAISE EXCEPTION 'LECTURE_SEULE a annulé via RPC legacy : %', v_result;
  END IF;

  SELECT p.valide_par_etablissement INTO v_validee
  FROM public.presences p WHERE p.id = v_presence;
  IF v_validee IS NOT FALSE THEN
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
     OR public.fn_a_permission_etablissement('pointage', v_etab_b) IS NOT TRUE
     OR public.fn_a_permission_etablissement('missions', v_etab_b) IS NOT TRUE
     OR public.fn_a_permission_etablissement('paiement', v_etab_a) THEN
    RAISE EXCEPTION 'Contexte RH cross-etab invalide';
  END IF;

  v_result := public.fn_commission_info_etablissement();
  IF v_result->>'error' <> 'Accès refusé' THEN
    RAISE EXCEPTION 'RH a lu les données de commission : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Clôture litige cross-etab acceptée : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    v_payload_sans_impact
  );
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Payload litige cross-etab accepté : %', v_result;
  END IF;

  v_result := public.fn_valider_presences_lot(ARRAY[v_presence]);
  IF v_result->>'success' <> 'true' OR (v_result->>'nb_validees')::integer <> 0 THEN
    RAISE EXCEPTION 'Pointage cross-etab non borné : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Tentative RH depuis un autre établissement'
  );
  IF v_result->>'error_code' <> 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'Annulation cross-etab acceptée : %', v_result;
  END IF;

  SELECT p.valide_par_etablissement INTO v_validee
  FROM public.presences p WHERE p.id = v_presence;
  IF v_validee IS NOT FALSE THEN
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
  IF public.fn_a_permission_etablissement('paiement', v_etab_a) THEN
    RAISE EXCEPTION 'POINTAGE_ONLY possède indûment la permission paiement';
  END IF;
  v_result := public.fn_commission_info_etablissement();
  IF v_result->>'error' <> 'Accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a lu les données de commission : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a clôturé un litige : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    v_payload_sans_impact
  );
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'POINTAGE_ONLY a proposé un accord litige : %', v_result;
  END IF;
  v_result := public.fn_valider_presences_lot(ARRAY[v_presence]);
  IF v_result->>'success' <> 'true' OR (v_result->>'nb_validees')::integer <> 1 THEN
    RAISE EXCEPTION 'POINTAGE_ONLY légitime refusé : %', v_result;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_groupe, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  IF public.fn_a_permission_etablissement('paiement', v_etab_a) IS NOT TRUE THEN
    RAISE EXCEPTION 'ADMIN_GROUPE privé de la permission paiement';
  END IF;
  v_result := public.fn_commission_info_etablissement();
  IF v_result ? 'error' THEN
    RAISE EXCEPTION 'ADMIN_GROUPE privé de lecture_paiement : %', v_result;
  END IF;
  v_result := public.fn_modifier_tolerance_pointage_etab(100);
  IF v_result->>'success' <> 'true' THEN
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
  IF v_result->>'error' <> 'Accès refusé' THEN
    RAISE EXCEPTION 'RH a lu les données de commission : %', v_result;
  END IF;

  -- Un objet sans type, un type inconnu ou des champs hors schéma ne créent
  -- jamais une nouvelle version de proposition.
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier, '{}'::jsonb
  );
  IF v_result->>'success' <> 'false' THEN
    RAISE EXCEPTION 'Payload vide accepté : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    '{"type":"TYPE_INCONNU","modifications":{},"justification":"Test"}'::jsonb
  );
  IF v_result->>'success' <> 'false' THEN
    RAISE EXCEPTION 'Type de payload inconnu accepté : %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier,
    '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":-1},"justification":"Test"}'::jsonb
  );
  IF v_result->>'success' <> 'false'
     OR EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND (
           l.payload_modifications IS NOT NULL
           OR l.accord_soignant IS TRUE
           OR l.accord_etablissement IS TRUE
         )
     ) THEN
    RAISE EXCEPTION 'Payload hors limites a muté le litige : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige(v_litige_base, NULL);
  IF v_result->>'success' <> 'true'
     OR v_result->>'accord_etablissement' <> 'true' THEN
    RAISE EXCEPTION 'RH légitime refusé sur clôture litige : %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige_avec_payload(
    v_litige_financier, v_payload_a
  );
  IF v_result->>'statut' <> 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' THEN
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
  IF v_result->>'error' <> 'Un accord avec proposition doit être accepté via son payload exact' THEN
    RAISE EXCEPTION 'Endpoint simple a accepté un payload financier : %', v_result;
  END IF;
  v_result := public.fn_confirmer_accord_partie(v_litige_financier);
  IF v_result->>'success' <> 'false'
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
  IF v_result->>'statut' <> 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' THEN
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
  IF v_result->>'success' <> 'false'
     OR EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_financier
         AND (l.statut = 'RESOLU_ADMIN' OR l.modifications_executees IS TRUE)
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
  IF v_result->>'statut' <> 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' THEN
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
  IF v_result->>'statut' <> 'EN_ATTENTE_VALIDATION_ADMIN'
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
  IF v_result->>'statut' <> 'RESOLU_ACCORD_PARTIES'
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
  IF v_result->>'error_code' <> 'STATUT_INVALIDE' THEN
    RAISE EXCEPTION 'RH légitime refusé avant la garde métier : %', v_result;
  END IF;
  v_result := public.fn_annuler_mission_etablissement(
    v_mission, 'Contrôle rôle RH légitime sans mutation'
  );
  IF COALESCE(v_result->>'error', '') NOT LIKE 'Impossible d''annuler%' THEN
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
  IF public.est_admin()
     OR public.fn_a_permission_etablissement('paiement', v_etab_a) THEN
    RAISE EXCEPTION 'Administrateur plateforme AAL1 accepté sur paiement';
  END IF;
  v_result := public.fn_cloturer_litige(v_litige_admin, NULL);
  IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Administrateur plateforme AAL1 accepté sur litige : %', v_result;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin_plateforme, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  IF public.est_admin() IS NOT TRUE
     OR public.fn_a_permission_etablissement('paiement', v_etab_a) IS NOT TRUE THEN
    RAISE EXCEPTION 'Fixture administrateur plateforme invalide';
  END IF;
  -- MODIFICATION_MONTANT n'est pas exécutable automatiquement au lancement :
  -- l'ancien worker transformait certains ajustements en avoir total. La
  -- validation doit retourner le routage manuel et conserver l'accord en REVUE_ADMIN
  -- pour le bouton « Résoudre (financier + statut) ».
  v_result := public.fn_admin_valider_accord_litige(v_litige_financier);
  IF v_result->>'success' <> 'false'
     OR v_result->>'error_code'
       <> 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE'
     OR v_result->>'manual_resolution_required' <> 'true' THEN
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
  IF v_result->>'statut' <> 'RESOLU_ADMIN' THEN
    RAISE EXCEPTION 'Administrateur complet refusé sur litige : %', v_result;
  END IF;
  v_result := public.fn_annuler_mission_etab(
    v_mission, 'AUTRE', 'Contrôle administrateur complet sans mutation'
  );
  IF v_result->>'error_code' <> 'STATUT_INVALIDE' THEN
    RAISE EXCEPTION 'Administrateur complet refusé avant la garde métier : %', v_result;
  END IF;
  v_result := public.fn_annuler_mission_etablissement(
    v_mission, 'Contrôle administrateur complet sans mutation'
  );
  IF COALESCE(v_result->>'error', '') NOT LIKE 'Impossible d''annuler%' THEN
    RAISE EXCEPTION 'Administrateur complet refusé par la RPC legacy : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$rbac_rpc$;

ROLLBACK;
