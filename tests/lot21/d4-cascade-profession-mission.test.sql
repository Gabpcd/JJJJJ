-- Lot 21 / D4 — test comportemental complet.
-- Usage : psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f tests/lot21/d4-cascade-profession-mission.test.sql
-- Prérequis : toutes les migrations, dont 20260712163000, appliquées.

\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_etab uuid := gen_random_uuid();
  v_officine uuid := gen_random_uuid();
  v_iade uuid := gen_random_uuid();
  v_concurrent uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_m_candidature uuid := gen_random_uuid();
  v_m_directe uuid := gen_random_uuid();
  v_m_admin uuid := gen_random_uuid();
  v_m_feed uuid := gen_random_uuid();
  v_m_iade uuid := gen_random_uuid();
  v_m_proposition uuid := gen_random_uuid();
  v_m_proposition_expiree uuid := gen_random_uuid();
  v_candidature uuid;
  v_candidature_concurrente uuid;
  v_result jsonb;
  v_doc record;
  v_mission record;
  v_direct_transition_bloquee boolean := false;
  v_transition_erreur text;
  v_officine_bloquee boolean := false;
  v_officine_erreur text;
BEGIN
  -- Empêche les canaux externes (push/email/SMS) pendant ce test
  -- transactionnel ; les notifications en base restent vérifiées.
  PERFORM set_config('app.test_mode', 'true', true);

  -- 0. Le référentiel de PROFIL contient exactement les 17 règles attendues,
  -- avant toute fixture susceptible de masquer une profession mal seedée.
  IF EXISTS (
    WITH attendu(profession, types_exercice_autorises) AS (
      VALUES
        ('IDE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('AS'::public.type_profession, ARRAY['SALARIE']::text[]),
        ('AES'::public.type_profession, ARRAY['SALARIE']::text[]),
        ('IBODE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('IADE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('SAGE_FEMME'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('KINE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('MEDECIN'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('PHARMACIEN'::public.type_profession, ARRAY['SALARIE']::text[]),
        ('MANIPULATEUR_RADIO'::public.type_profession, ARRAY['SALARIE']::text[]),
        ('PREPARATEUR_PHARMA'::public.type_profession, ARRAY['SALARIE']::text[]),
        ('DIETETICIEN'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('ERGOTHERAPEUTE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('PSYCHOMOTRICIEN'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('ORTHOPHONISTE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('DENTISTE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
        ('AUXILIAIRE_PUERICULTURE'::public.type_profession, ARRAY['SALARIE']::text[])
    )
    SELECT 1
    FROM attendu a
    LEFT JOIN public.regles_exercice_profession r
      ON r.profession = a.profession
    WHERE r.profession IS NULL
       OR r.types_exercice_autorises IS DISTINCT FROM a.types_exercice_autorises
  ) THEN
    RAISE EXCEPTION 'D4-T0: référentiel de profil incomplet ou divergent';
  END IF;

  -- 1. Matrice : cellule inconnue et établissements publics = salarié par défaut.
  IF public.fn_mode_exercice('PROFESSION_INCONNUE', 'CLINIQUE_PRIVEE', NULL)->>'niveau'
       IS DISTINCT FROM 'NON_PROPOSE' THEN
    RAISE EXCEPTION 'D4-T1: une combinaison inconnue doit tomber en NON_PROPOSE';
  END IF;
  IF public.fn_mode_exercice('MEDECIN', 'HOPITAL_PUBLIC', 'PUBLIC')->>'niveau'
       IS DISTINCT FROM 'NON_PROPOSE' THEN
    RAISE EXCEPTION 'D4-T2: le secteur public doit tomber en NON_PROPOSE';
  END IF;
  IF public.fn_mode_exercice('MEDECIN', 'CLINIQUE_PRIVEE', NULL)->>'niveau'
       IS DISTINCT FROM 'AUTORISE'
     OR public.fn_mode_exercice('MEDECIN', 'CENTRE_SANTE', NULL)->>'niveau'
       IS DISTINCT FROM 'BLOQUE' THEN
    RAISE EXCEPTION 'D4-T2B: branches MEDECIN privé/centre incohérentes';
  END IF;
  IF public.fn_mode_exercice('IADE', 'CLINIQUE_PRIVEE', NULL)->>'niveau'
       IS DISTINCT FROM 'BLOQUE'
     OR public.fn_mode_exercice('IBODE', 'CLINIQUE_PRIVEE', NULL)->>'niveau'
       IS DISTINCT FROM 'BLOQUE' THEN
    RAISE EXCEPTION 'D4-T2C: missions IADE/IBODE privées doivent rester salariées';
  END IF;
  IF public.fn_mode_exercice('PHARMACIEN', 'CLINIQUE_PRIVEE', NULL)->>'niveau'
       IS DISTINCT FROM 'NON_PROPOSE' THEN
    RAISE EXCEPTION 'D4-T3: PHARMACIEN en établissement doit être NON_PROPOSE';
  END IF;
  IF public.fn_mode_exercice('PHARMACIEN', 'CLINIQUE_PRIVEE', NULL)->>'source_url' IS NOT NULL THEN
    RAISE EXCEPTION 'D4-T3B: le défaut PHARMACIEN ne doit pas afficher une source juridique trompeuse';
  END IF;
  IF public.fn_mode_exercice('MEDECIN', 'HOPITAL_PUBLIC', 'PUBLIC')->>'source_url' IS NOT NULL THEN
    RAISE EXCEPTION 'D4-T3C: le défaut public Jolene ne doit pas afficher une interdiction juridique';
  END IF;
  IF public.fn_mode_exercice('IADE', 'CLINIQUE_PRIVEE', NULL)->>'source_url'
       IS DISTINCT FROM 'https://www.fehap.fr/jcms/navigation-internet/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf' THEN
    RAISE EXCEPTION 'D4-T3D: IADE doit pointer vers le texte original de la lettre D21-031940';
  END IF;
  IF public.fn_mode_exercice('IADE', 'CLINIQUE_PRIVEE', NULL)->>'source_url_complementaire'
       IS DISTINCT FROM 'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546' THEN
    RAISE EXCEPTION 'D4-T3D2: IADE doit compléter la lettre par CE n°491128, cas aide-soignant';
  END IF;
  IF public.fn_mode_exercice('MANIPULATEUR_RADIO', 'CLINIQUE_PRIVEE', NULL)->>'source_url'
       IS DISTINCT FROM 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093' THEN
    RAISE EXCEPTION 'D4-T3E: MANIPULATEUR_RADIO doit pointer vers L.4351-1 CSP';
  END IF;
  IF public.fn_mode_exercice('DENTISTE', 'CENTRE_SANTE', NULL)->>'source_url'
       IS DISTINCT FROM 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000047567923' THEN
    RAISE EXCEPTION 'D4-T3F: le centre de santé doit pointer vers L.6323-1-5 CSP';
  END IF;

  -- 2. Compatibilité de diplôme : IADE peut remplir une mission IDE.
  IF public.fn_soignant_compatible_mission('IADE', NULL, 'IDE', NULL, true)
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'D4-T4: IADE × mission IDE doit être compatible';
  END IF;
  IF public.fn_soignant_compatible_mission('IDE', NULL, 'IADE', NULL, true)
       IS DISTINCT FROM false
     OR public.fn_soignant_compatible_mission('IDE', NULL, 'IBODE', NULL, true)
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'D4-T4B: IDE ne doit pas remplir une mission IADE/IBODE';
  END IF;

  INSERT INTO public.etablissements(
    id, nom, siret, finess, type, adresse_rue, adresse_ville, adresse_code_postal,
    email_contact, statut_verification, peut_publier_missions, est_compte_test,
    siret_verifie, finess_verifie, contrat_service_signe, representant_identite_verifiee,
    rattachement_verifie, coherence_identite,
    mode_paiement_commission, stripe_sepa_payment_method_id
  ) VALUES (
    v_etab, 'D4 Etablissement', substr(md5(v_etab::text), 1, 14), '750000001', 'CLINIQUE_PRIVEE',
    '1 rue du Test', 'Paris', '75001', 'd4-etab-' || v_etab::text || '@test.local',
    'VERIFIE', true, true, true, true, true, true, true, 'OK',
    'SEPA_DEBIT', 'pm_d4_etablissement_test'
  );
  INSERT INTO public.etablissements(
    id, nom, siret, finess, type, adresse_rue, adresse_ville, adresse_code_postal,
    email_contact, statut_verification, peut_publier_missions, est_compte_test,
    siret_verifie, finess_verifie, contrat_service_signe, representant_identite_verifiee,
    rattachement_verifie, coherence_identite,
    mode_paiement_commission, stripe_sepa_payment_method_id
  ) VALUES (
    v_officine, 'D4 Officine', substr(md5(v_officine::text), 1, 14), '750000002', 'PHARMACIE_OFFICINE',
    '2 rue du Test', 'Paris', '75002', 'd4-officine-' || v_officine::text || '@test.local',
    'VERIFIE', true, true, true, true, true, true, true, 'OK',
    'SEPA_DEBIT', 'pm_d4_officine_test'
  );

  INSERT INTO auth.users(
    id, email, raw_app_meta_data, role, aud, instance_id, email_confirmed_at
  )
  VALUES
    (
      v_admin, 'd4-admin-' || v_admin::text || '@test.local', jsonb_build_object('role', 'ADMIN_PLATEFORME'),
      'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid, now()
    ),
    (
      v_iade, 'd4-iade-' || v_iade::text || '@test.local', jsonb_build_object('role', 'SOIGNANT'),
      'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid, now()
    ),
    (
      v_concurrent, 'd4-concurrent-' || v_concurrent::text || '@test.local', jsonb_build_object('role', 'SOIGNANT'),
      'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid, now()
    )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.equipe_admin(
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin, 'D4', 'Admin',
    'd4-admin-' || v_admin::text || '@test.local', true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  -- Simule un profil IADE libéral déjà valide : sa spécialité IADE n'est pas
  -- exercée en libéral, mais il peut remplir une mission IDE. Cette règle de
  -- profil ne crée aucune cellule IADE libérale dans la matrice des missions.
  INSERT INTO public.regles_exercice_profession(profession, types_exercice_autorises, description)
  VALUES ('IADE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE'], 'Fixture profil existant Lot 21 D4')
  ON CONFLICT (profession) DO UPDATE SET
    types_exercice_autorises = EXCLUDED.types_exercice_autorises,
    description = EXCLUDED.description;

  INSERT INTO public.soignants(
    id, nom, prenom, email, profession, type_exercice, type_contrat,
    types_contrat_acceptes, preference_contrat_mixte, heures_cumulees,
    rpps_verifie, tous_documents_valides, disponible_urgence,
    statut_compte, est_compte_test, mandat_facturation_signe,
    statut_liberal, siret_liberal, siret_liberal_verifie,
    siret_liberal_verifie_le, siret_liberal_raison_sociale,
    siret_liberal_coherence_identite
  ) VALUES (
    v_iade, 'D4', 'Iade', 'd4-iade-' || v_iade::text || '@test.local', 'IADE', 'LIBERAL', 'LIBERAL',
    'LIBERAL', NULL, 4000, true, true, true, 'ACTIF', true, true,
    'ACTIF', substring(regexp_replace(v_iade::text, '[^0-9]', '', 'g') || '00000000000000' from 1 for 14),
    true, now(), 'Cabinet D4 Iade', true
  );

  INSERT INTO public.soignants
  SELECT (
    jsonb_populate_record(
      NULL::public.soignants,
      to_jsonb(s) || jsonb_build_object(
        'id', v_concurrent,
        'email', 'd4-concurrent-' || v_concurrent::text || '@test.local',
        'code_parrainage', 'JO-' || upper(substr(replace(v_concurrent::text, '-', ''), 1, 6)),
        'siret_liberal', substring(
          regexp_replace(v_concurrent::text, '[^0-9]', '', 'g') || '00000000000000'
          from 1 for 14
        ),
        'siret_liberal_raison_sociale', 'Cabinet D4 Concurrent'
      )
    )
  ).*
  FROM public.soignants s
  WHERE s.id = v_iade;

  -- Fixture documentaire explicite : RIB requis en salarié, RCP uniquement en
  -- libéral. La RCP expirée ne doit jamais bloquer la mission IDE salariée.
  INSERT INTO public.documents_requis_par_profession(
    profession, type_document, est_critique, a_expiration, type_exercice_requis, description
  ) VALUES
    ('IADE', 'RIB', true, false, 'SALARIE_ONLY', 'Fixture D4 salarié'),
    ('IADE', 'RCP_ASSURANCE', true, true, 'LIBERAL_ONLY', 'Fixture D4 libéral')
  ON CONFLICT (profession, type_document) DO UPDATE SET
    est_critique = EXCLUDED.est_critique,
    a_expiration = EXCLUDED.a_expiration,
    type_exercice_requis = EXCLUDED.type_exercice_requis,
    description = EXCLUDED.description;

  -- Génère les documents critiques du régime SALARIE uniquement. Le profil
  -- reste LIBERAL pendant tout le test.
  FOR v_doc IN
    SELECT DISTINCT drp.type_document, drp.a_expiration
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = 'IADE'
      AND drp.est_critique
      AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
      AND drp.type_document NOT IN ('DIPLOME', 'RPPS_ADELI')
  LOOP
    INSERT INTO public.documents_soignants(
      soignant_id, type_document, s3_cle, nom_fichier,
      statut_verification, est_critique, valide_jusqua
    ) VALUES (
      v_iade, v_doc.type_document,
      'tests/lot21/' || v_doc.type_document::text,
      'd4-' || lower(v_doc.type_document::text) || '.pdf',
      'VERIFIE', true,
      CASE WHEN v_doc.a_expiration THEN current_date + 365 ELSE NULL END
    );
  END LOOP;

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, est_critique, resultat_ia
  ) VALUES (
    v_iade, 'DIPLOME', 'tests/lot21/diplome-iade', 'd4-diplome-iade.pdf',
    'VERIFIE', true, '{"profession_certifiee":"IADE"}'::jsonb
  );

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, est_critique, valide_jusqua
  ) VALUES (
    v_iade, 'RCP_ASSURANCE', 'tests/lot21/rcp-expiree', 'd4-rcp-expiree.pdf',
    'VERIFIE', true, current_date - 1
  );

  IF public.fn_documents_ok_pour_mission(v_iade, 'SALARIE')
       IS DISTINCT FROM true
     OR public.fn_documents_ok_pour_mission(v_iade, 'LIBERAL')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'D4-T5: séparation des documents salarié/libéral invalide';
  END IF;

  INSERT INTO public.missions(
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, mode_attribution, type_contrat_recherche, est_urgente
  ) VALUES
    (v_m_candidature, v_etab, 'D4 candidature IDE', 'IDE', now()+interval '10 days', now()+interval '10 days 8 hours', 8, 30, 'OUVERTE', 'CANDIDATURE', 'SALARIE', false),
    (v_m_directe, v_etab, 'D4 directe IDE', 'IDE', now()+interval '12 days', now()+interval '12 days 8 hours', 8, 30, 'OUVERTE', 'PREMIER_ARRIVE', 'SALARIE', false),
    (v_m_admin, v_etab, 'D4 admin IDE', 'IDE', now()+interval '14 days', now()+interval '14 days 8 hours', 8, 30, 'OUVERTE', 'CANDIDATURE', 'SALARIE', false),
    (v_m_feed, v_etab, 'D4 feed urgence IDE', 'IDE', now()+interval '2 days', now()+interval '2 days 8 hours', 8, 30, 'OUVERTE', 'CANDIDATURE', 'SALARIE', true),
    (v_m_iade, v_etab, 'D4 mission IADE', 'IADE', now()+interval '16 days', now()+interval '16 days 8 hours', 8, 40, 'OUVERTE', 'CANDIDATURE', 'TOUS', false),
    (v_m_proposition, v_etab, 'D4 proposition IDE', 'IDE', now()+interval '18 days', now()+interval '18 days 8 hours', 8, 30, 'OUVERTE', 'CANDIDATURE', 'SALARIE', true),
    (v_m_proposition_expiree, v_etab, 'D4 proposition IDE expirée', 'IDE', now()+interval '20 days', now()+interval '20 days 8 hours', 8, 30, 'OUVERTE', 'CANDIDATURE', 'SALARIE', false);

  SELECT type_contrat_recherche INTO v_mission FROM public.missions WHERE id = v_m_iade;
  IF v_mission.type_contrat_recherche::text IS DISTINCT FROM 'SALARIE' THEN
    RAISE EXCEPTION 'D4-T6: une mission IADE doit être forcée en SALARIE, obtenu %', v_mission.type_contrat_recherche;
  END IF;
  IF (SELECT accepte_non_specialises FROM public.missions WHERE id = v_m_iade) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'D4-T6A: une mission IADE doit exiger la profession exacte';
  END IF;
  -- Le verrou pré-lancement neutralise le fan-out automatique des missions de
  -- test. La compatibilité IADE × IDE reste vérifiée plus bas via les
  -- diffusions manuelles boost et pool, bornées à cette fixture.
  IF EXISTS (
    SELECT 1 FROM public.notifications
     WHERE destinataire_id = v_iade
       AND type = 'MISSION_URGENTE'
       AND id_ressource = v_m_feed
  ) THEN
    RAISE EXCEPTION 'D4-T6B: une mission de test a déclenché un fan-out urgent automatique';
  END IF;

  -- 3. Candidature + traitement : IADE libérale sur mission IDE salariée.
  PERFORM set_config('request.jwt.claim.sub', v_iade::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_iade::text, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  v_result := public.fn_postuler_mission(v_m_candidature, 'Test IADE vers IDE', NULL);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR v_result->>'choix_contrat' IS DISTINCT FROM 'SALARIE'
     OR v_result->>'profession_requise' IS DISTINCT FROM 'IDE' THEN
    RAISE EXCEPTION 'D4-T7: candidature IADE × IDE salariée invalide: %', v_result;
  END IF;
  v_candidature := (v_result->>'candidature_id')::uuid;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin::text, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  v_result := public.fn_traiter_candidature(v_candidature, 'ACCEPTEE', NULL);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR v_result->>'choix_applique' IS DISTINCT FROM 'SALARIE' THEN
    RAISE EXCEPTION 'D4-T8: traitement candidature invalide: %', v_result;
  END IF;
  SELECT type_contrat_applique, type_paiement_soignant, soignant_assigne_id
    INTO v_mission FROM public.missions WHERE id = v_m_candidature;
  IF v_mission.type_contrat_applique::text IS DISTINCT FROM 'SALARIE'
     OR v_mission.type_paiement_soignant IS DISTINCT FROM 'BULLETIN_PAIE'
     OR v_mission.soignant_assigne_id IS DISTINCT FROM v_iade THEN
    RAISE EXCEPTION 'D4-T9: attribution candidature incohérente: %', row_to_json(v_mission);
  END IF;

  -- 4. Premier arrivé : même résultat, sans muter le profil.
  PERFORM set_config('request.jwt.claim.sub', v_iade::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_iade::text, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  v_result := public.fn_accepter_mission(v_m_directe, NULL);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR v_result->>'choix_applique' IS DISTINCT FROM 'SALARIE' THEN
    RAISE EXCEPTION 'D4-T10: acceptation directe invalide: %', v_result;
  END IF;
  IF (SELECT soignant_assigne_id FROM public.missions WHERE id = v_m_directe)
       IS DISTINCT FROM v_iade THEN
    RAISE EXCEPTION 'D4-T11: le garde-fou a neutralisé soignant_assigne_id pendant le RPC';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.conformite_travail
     WHERE mission_id = v_m_directe
       AND soignant_id = v_iade
       AND type_controle = 'PLAFOND_48H_HEBDO'
       AND resultat = 'CONFORME'
  ) THEN
    RAISE EXCEPTION 'D4-T11B: le plafond salarié a été ignoré à cause du profil libéral';
  END IF;

  -- 5. Clôture financière : le PROFIL reste libéral, mais la mission IDE
  -- salariée produit IFM/ICP, cotisations et bulletin, jamais une facture
  -- d'honoraires (même avec un mandat de facturation signé).
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin::text, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  UPDATE public.missions SET statut = 'TERMINEE' WHERE id = v_m_directe;
  IF NOT EXISTS (
    SELECT 1 FROM public.cotisations_sociales
    WHERE mission_id = v_m_directe AND type_contrat::text = 'CDD'
  ) THEN
    RAISE EXCEPTION 'D4-T12: cotisations salariées absentes pour profil libéral × mission salariée';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.bulletins_paie WHERE mission_id = v_m_directe
  ) THEN
    RAISE EXCEPTION 'D4-T13: bulletin de paie absent pour profil libéral × mission salariée';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.factures_honoraires WHERE mission_id = v_m_directe
  ) THEN
    RAISE EXCEPTION 'D4-T14: facture d’honoraires créée à tort pour une mission salariée';
  END IF;
  IF COALESCE((SELECT montant_ifm FROM public.missions WHERE id = v_m_directe), 0) <= 0
     OR COALESCE((SELECT montant_icp FROM public.missions WHERE id = v_m_directe), 0) <= 0 THEN
    RAISE EXCEPTION 'D4-T15: IFM/ICP salariées perdues à cause du profil libéral';
  END IF;
  v_result := public.fn_mode_paiement_mission(v_m_directe);
  IF v_result->>'mode_recommande' IS DISTINCT FROM 'VIREMENT_PAIE'
     OR v_result->>'type_contrat_applique' IS DISTINCT FROM 'SALARIE' THEN
    RAISE EXCEPTION 'D4-T16: mode de paiement encore déduit du profil: %', v_result;
  END IF;

  -- 6. Affectation admin : compatibilité hiérarchique, pas d'égalité stricte.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin::text, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  v_result := public.fn_assigner_mission_admin(v_m_admin, v_iade, NULL);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR v_result->>'choix_applique' IS DISTINCT FROM 'SALARIE' THEN
    RAISE EXCEPTION 'D4-T17: affectation admin invalide: %', v_result;
  END IF;

  v_result := public.fn_modifier_mission_etablissement_v2(
    v_m_iade, 'D4 mission IADE modifiée', NULL, 'Bloc opératoire', 'IADE',
    now() + interval '16 days', now() + interval '16 days 8 hours', 42,
    false, 0, 'CANDIDATURE', 'LIBERAL', NULL, true
  );
  IF (v_result->>'success')::boolean IS DISTINCT FROM false
     OR NULLIF(v_result->>'error', '') IS NULL
     OR (SELECT type_contrat_recherche::text FROM public.missions WHERE id = v_m_iade)
       IS DISTINCT FROM 'SALARIE' THEN
    RAISE EXCEPTION 'D4-T17B: édition IADE libérale non refusée ou mission mutée: %', v_result;
  END IF;

  -- 7. Proposition directe établissement/admin puis acceptation soignant : la
  -- profession et le contrat viennent toujours de la mission IDE.
  v_result := public.fn_proposer_mission_soignant(v_m_proposition, v_iade, NULL);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR v_result->>'choix_persiste' IS DISTINCT FROM 'SALARIE'
     OR v_result->>'profession_requise' IS DISTINCT FROM 'IDE' THEN
    RAISE EXCEPTION 'D4-T18: proposition IADE × IDE invalide: %', v_result;
  END IF;
  v_candidature := (v_result->>'candidature_id')::uuid;
  INSERT INTO public.candidatures(
    mission_id, soignant_id, statut, type_contrat_choisi
  ) VALUES (
    v_m_proposition, v_concurrent, 'PROPOSEE', 'SALARIE'
  ) RETURNING id INTO v_candidature_concurrente;
  PERFORM set_config('request.jwt.claim.sub', v_iade::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_iade::text, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  v_result := public.fn_dashboard_soignant_complet();
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_result->'propositions') p
     WHERE p->>'id' = v_candidature::text
       AND p->>'type_contrat_choisi' = 'SALARIE'
       AND p->'missions'->>'id' = v_m_proposition::text
       AND p->'missions'->>'type_contrat_recherche' = 'SALARIE'
  ) THEN
    RAISE EXCEPTION 'D4-T18B: proposition dashboard absente ou forme mission invalide: %', v_result->'propositions';
  END IF;

  -- Le correctif RPC ne doit surtout pas élargir les droits d'UPDATE direct
  -- du soignant : seule fn_repondre_proposition finalise la mission et le
  -- contrat avant de faire évoluer la candidature.
  IF has_table_privilege(
       'authenticated',
       'private.candidature_transition_context',
       'INSERT'
     ) THEN
    RAISE EXCEPTION 'D4-T18C: contexte de transition insérable par authenticated';
  END IF;
  BEGIN
    UPDATE public.candidatures
       SET statut = 'ACCEPTEE', traite_le = now()
     WHERE id = v_candidature;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_transition_erreur = MESSAGE_TEXT;
    IF v_transition_erreur NOT LIKE
         'Vous ne pouvez pas modifier le statut de votre candidature%' THEN
      RAISE;
    END IF;
    v_direct_transition_bloquee := true;
  END;
  IF v_direct_transition_bloquee IS DISTINCT FROM true
     OR (SELECT statut FROM public.candidatures WHERE id = v_candidature)
       IS DISTINCT FROM 'PROPOSEE' THEN
    RAISE EXCEPTION 'D4-T18C: transition directe PROPOSEE → ACCEPTEE non bloquée';
  END IF;

  v_result := public.fn_repondre_proposition(v_candidature, true);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR v_result->>'choix_applique' IS DISTINCT FROM 'SALARIE'
     OR (SELECT soignant_assigne_id FROM public.missions WHERE id = v_m_proposition)
       IS DISTINCT FROM v_iade
     OR (SELECT statut FROM public.candidatures WHERE id = v_candidature_concurrente)
       IS DISTINCT FROM 'REFUSEE'
     OR (SELECT motif_refus FROM public.candidatures WHERE id = v_candidature_concurrente)
       IS DISTINCT FROM 'Mission attribuée' THEN
    RAISE EXCEPTION 'D4-T19: acceptation proposition IADE × IDE invalide: %', v_result;
  END IF;
  IF EXISTS (
    SELECT 1
      FROM private.candidature_transition_context ctx
     WHERE ctx.backend_pid = pg_backend_pid()
       AND ctx.transaction_id = txid_current()
  ) THEN
    RAISE EXCEPTION 'D4-T19A: contexte candidature non nettoyé après acceptation';
  END IF;

  -- La fenêtre de 2 h affichée par la carte est également imposée en base.
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin::text, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  v_result := public.fn_proposer_mission_soignant(v_m_proposition_expiree, v_iade, NULL);
  v_candidature := (v_result->>'candidature_id')::uuid;
  IF v_candidature IS NULL THEN
    RAISE EXCEPTION 'D4-T19B: proposition destinée au test d’expiration non créée: %', v_result;
  END IF;
  UPDATE public.candidatures
     SET cree_le = now() - interval '3 hours'
   WHERE id = v_candidature;
  PERFORM set_config('request.jwt.claim.sub', v_iade::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_iade::text, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  v_result := public.fn_repondre_proposition(v_candidature, true);
  IF v_result->>'error' IS DISTINCT FROM 'Cette proposition a expiré'
     OR (SELECT statut FROM public.candidatures WHERE id = v_candidature)
       IS DISTINCT FROM 'EXPIREE' THEN
    RAISE EXCEPTION 'D4-T19C: proposition expirée encore acceptable: %', v_result;
  END IF;
  IF EXISTS (
    SELECT 1
      FROM private.candidature_transition_context ctx
     WHERE ctx.backend_pid = pg_backend_pid()
       AND ctx.transaction_id = txid_current()
  ) THEN
    RAISE EXCEPTION 'D4-T19D: contexte candidature non nettoyé après expiration';
  END IF;

  -- 8. Feed, pool et notification partagent l'éligibilité IADE × IDE.
  IF public.fn_soignant_eligible_mission(v_iade, v_m_feed, true)
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'D4-T20: mission IDE absente de l’éligibilité pool/feed IADE';
  END IF;

  -- Isole les deux feeds des données ambiantes sans les modifier : la
  -- fixture est seule dans le rayon, au plafond tarifaire autorisé et avec
  -- le meilleur score de matching. Un limit=1 prouve alors chaque chemin.
  -- Ces mutations sont celles du serveur de recette, pas celles du soignant.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE public.etablissements
     SET adresse_lat = 89.123456, adresse_lng = 42.654321
   WHERE id = v_etab;
  UPDATE public.soignants
     SET adresse_lat = 89.123456, adresse_lng = 42.654321,
         rayon_deplacement_km = 1, urgence_rayon_km = 1,
         taux_horaire_minimum = 1000
   WHERE id = v_iade;
  UPDATE public.missions
     SET taux_horaire_base = 1000, cree_le = 'infinity'::timestamptz
   WHERE id = v_m_feed;
  INSERT INTO public.matching_scores(soignant_id, mission_id, score_global)
  VALUES (v_iade, v_m_feed, 100)
  ON CONFLICT (soignant_id, mission_id) DO UPDATE
    SET score_global = EXCLUDED.score_global;

  PERFORM set_config('request.jwt.claim.sub', v_iade::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_iade::text, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  v_result := public.fn_toggle_pool_urgence(false, 30, NULL);
  v_result := public.fn_toggle_pool_urgence(true, 30, NULL);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR (v_result->>'documents_salarie_ok')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'D4-T20B: la RCP expirée bloque encore le pool salarié: %', v_result;
  END IF;
  v_result := public.fn_suggestions_missions_pour_soignant(1);
  IF jsonb_typeof(v_result) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'D4-T20C: le feed suggestions n’a pas retourné un tableau: %', v_result;
  END IF;
  IF jsonb_array_length(v_result) IS DISTINCT FROM 1
     OR v_result->0->>'id' IS DISTINCT FROM v_m_feed::text THEN
    RAISE EXCEPTION 'D4-T20C: suggestion IDE absente pour le profil IADE: %', v_result;
  END IF;
  v_result := public.fn_obtenir_missions_swipe(1);
  IF jsonb_typeof(v_result->'missions') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'D4-T21: le feed swipe n’a pas retourné un tableau: %', v_result;
  END IF;
  IF jsonb_array_length(v_result->'missions') IS DISTINCT FROM 1
     OR v_result->'missions'->0->>'mission_id' IS DISTINCT FROM v_m_feed::text THEN
    RAISE EXCEPTION 'D4-T21: mission IDE absente du feed swipe IADE: %', v_result;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin::text, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);

  -- Borne les fan-outs inverses à la seule fixture IADE. Les exclusions
  -- référencent uniquement l'établissement transactionnel du test et sont
  -- annulées par le ROLLBACK final ; aucun profil ambiant n'est modifié.
  INSERT INTO public.exclusions(
    exclu_par, exclu_id, type_exclu_par, motif
  )
  SELECT v_etab, s.id, 'ETABLISSEMENT', 'Fixture Lot 21 D4'
    FROM public.soignants s
   WHERE s.id <> v_iade
     AND public.fn_soignant_eligible_mission(s.id, v_m_feed, true)
  ON CONFLICT (exclu_par, exclu_id) DO NOTHING;

  -- Une preuve neuve et typée pour chaque diffusion : la notification
  -- MISSION_URGENTE créée lors du seed ne peut satisfaire ces assertions.
  DELETE FROM public.notifications
   WHERE destinataire_id = v_iade
     AND type = 'MISSION_A_POURVOIR'
     AND lien = '/soignant/missions/' || v_m_feed;
  v_result := public.fn_booster_mission(v_m_feed);
  IF (v_result->>'success')::boolean IS DISTINCT FROM true
     OR (v_result->>'soignants_notifies')::integer IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'D4-T21B: le boost n’a pas ciblé IADE × mission IDE: %', v_result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
     WHERE destinataire_id = v_iade
       AND type = 'MISSION_A_POURVOIR'
       AND lien = '/soignant/missions/' || v_m_feed
  ) THEN
    RAISE EXCEPTION 'D4-T21C: notification boost IADE × mission IDE introuvable';
  END IF;

  DELETE FROM public.notifications
   WHERE destinataire_id = v_iade
     AND type = 'POOL_URGENCE'
     AND type_ressource = 'mission'
     AND id_ressource = v_m_feed;
  IF public.fn_diffuser_pool_urgence(v_m_feed) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'D4-T22: diffusion pool non bornée à IADE × mission IDE';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
     WHERE destinataire_id = v_iade
       AND type = 'POOL_URGENCE'
       AND type_ressource = 'mission'
       AND id_ressource = v_m_feed
  ) THEN
    RAISE EXCEPTION 'D4-T22B: notification pool IADE × mission IDE introuvable';
  END IF;

  v_result := public.fn_rebooker_soignant(
    v_iade, v_m_feed, now() + interval '22 days', now() + interval '22 days 8 hours'
  );
  IF (v_result->>'success')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'D4-T23B: rebooking IADE × mission modèle IDE refusé: %', v_result;
  END IF;

  -- 9. Le profil n'est jamais réécrit par une mission salariée.
  IF (SELECT type_exercice FROM public.soignants WHERE id = v_iade)
       IS DISTINCT FROM 'LIBERAL' THEN
    RAISE EXCEPTION 'D4-T24: le profil libéral a été muté';
  END IF;
  IF (
    SELECT (item->>'liberal')::boolean
    FROM jsonb_array_elements(public.fn_professions_liberales()) AS item
    WHERE item->>'code' = 'IADE'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'D4-T25: IADE reste annoncé libéral dans l’API historique';
  END IF;
  IF (
    SELECT (item->>'liberal')::boolean
    FROM jsonb_array_elements(public.fn_professions_liberales()) AS item
    WHERE item->>'code' = 'PHARMACIEN'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'D4-T26: PHARMACIEN reste annoncé libéral dans l’API historique';
  END IF;

  -- 10. Une officine ne peut plus publier de remplacement via Jolene.
  BEGIN
    INSERT INTO public.missions(
      etablissement_id, intitule, profession_requise, debut_le, fin_le,
      duree_heures, taux_horaire_base, statut, type_contrat_recherche
    ) VALUES (
      v_officine, 'D4 remplacement titulaire', 'PHARMACIEN',
      now()+interval '20 days', now()+interval '20 days 8 hours', 8, 35,
      'OUVERTE', 'SALARIE'
    );
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      GET STACKED DIAGNOSTICS v_officine_erreur = MESSAGE_TEXT;
      v_officine_bloquee := v_officine_erreur IS NOT DISTINCT FROM
        'Jolene ne propose pas le remplacement du titulaire d''une officine. Les missions pharmacien proposées par la plateforme sont des missions salariées d''établissement, notamment en PUI.';
  END;
  IF v_officine_bloquee IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'D4-T27: garde officine absente ou message inattendu: %',
      COALESCE(v_officine_erreur, 'aucune exception P0001');
  END IF;

  RAISE NOTICE 'PASS Lot21 D4 — matrice, IADE×IDE, documents, attribution, paie, proposition, admin, feed, pool, notifications et officine';
END;
$test$;

ROLLBACK;
