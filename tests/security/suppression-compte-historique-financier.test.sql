-- Recette staging isolée seulement : vraies routines, données fictives, ROLLBACK.
-- Aucun endpoint Auth, Stripe, Storage ou autre fournisseur n’est appelé.
-- Une trace Stripe acquise ci-dessous est une fixture SQL, pas une preuve fournisseur.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout='45s';
SET LOCAL lock_timeout='5s';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $suppression$
DECLARE
  v_etab constant uuid := 'f1610000-0000-4000-8000-000000000001';
  v_manuel constant uuid := 'f1610000-0000-4000-8000-000000000002';
  v_stripe constant uuid := 'f1610000-0000-4000-8000-000000000003';
  v_futur constant uuid := 'f1610000-0000-4000-8000-000000000004';
  v_sans_profil constant uuid := 'f1610000-0000-4000-8000-000000000005';
  v_mission uuid;
  v_fh uuid;
  v_ps uuid;
  v_uid uuid;
  v_i integer;
  v_nom text;
  v_resultat jsonb;
  v_profil_avant jsonb;
  v_auth_avant jsonb;
  v_ps_avant jsonb;
  v_st_avant jsonb;
  v_piece_avant jsonb;
  v_debut date := date_trunc('week',current_date)::date - 7;
  v_passe date;
  v_futur_jour date;
  v_net_avant bigint;
  v_refus boolean;
  v_contextes_avant jsonb;
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
    OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'Suppression F161 : maintenance staging isolée requise'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'Suppression F161 : trigger INSERT Auth non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.soignants'::regclass,
    'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,
    'public.factures_honoraires'::regclass,'public.paiements_soignant'::regclass,
    'public.stripe_transfers'::regclass,'public.notifications'::regclass)
    AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'Suppression F161 : trigger métier désactivé'; END IF;
  FOREACH v_nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation'] LOOP
    IF NULLIF(current_setting(v_nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'Suppression F161 : contexte de contournement interdit'; END IF;
  END LOOP;
  FOREACH v_nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF COALESCE(current_setting(v_nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'Suppression F161 : contexte forcé interdit'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_etab,v_manuel,v_stripe,v_futur,v_sans_profil))
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE siret='99150000001920')
    OR EXISTS(SELECT 1 FROM public.missions WHERE id::text LIKE 'f1610001-%')
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id::text LIKE 'f1610002-%')
  THEN RAISE EXCEPTION 'Suppression F161 : identifiants de recette déjà présents'; END IF;
  SELECT count(*) INTO v_net_avant FROM net.http_request_queue;
  IF v_net_avant<>0 THEN RAISE EXCEPTION 'Suppression F161 : file réseau non vide avant recette'; END IF;
  IF has_function_privilege('anon','public.fn_supprimer_compte_rate_limited()','EXECUTE')
    OR has_function_privilege('anon','public.fn_supprimer_mon_compte()','EXECUTE')
    OR has_table_privilege('authenticated','private.suppressions_compte_confirmees','INSERT')
    OR has_table_privilege('service_role','private.suppressions_compte_confirmees','UPDATE')
  THEN RAISE EXCEPTION 'Suppression F161 : droits de suppression ou reçu privé élargis'; END IF;
  SELECT d::date INTO v_passe FROM generate_series(v_debut,v_debut+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_futur_jour FROM generate_series(v_debut+14,v_debut+18,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF v_passe IS NULL OR v_futur_jour IS NULL OR v_debut+6>=current_date
  THEN RAISE EXCEPTION 'Suppression F161 : calendrier indisponible'; END IF;

  -- Aucun appel GoTrue : SQL Auth direct uniquement, sans sessions ni emails.
  INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
  SELECT id,'00000000-0000-0000-0000-000000000000'::uuid,id::text||'@example.invalid',
    'authenticated','authenticated',jsonb_build_object('role',CASE WHEN id=v_etab THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
      'est_compte_test',true,'is_test_playwright',true),now()
  FROM unnest(ARRAY[v_etab,v_manuel,v_stripe,v_futur,v_sans_profil]) id;
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
    source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
    identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
  SELECT id,'Recette','Historique',id::text||'@example.invalid','IDE','LIBERAL','1990-01-01',true,
    'RECETTE_F161',replace(id::text,'-',''),false,false,false,false,false,false,false
  FROM unnest(ARRAY[v_manuel,v_stripe,v_futur]) id;
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
    est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
    peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
  VALUES(v_etab,'Recette F161','99150000001920','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',
    'f161-etab@example.invalid',true,'RECETTE_F161','F161ETABLISSEMENT',false,false,'EN_ATTENTE',false,false,false,15);
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id IN(v_etab,v_manuel,v_stripe,v_futur);
  IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(v_etab,v_manuel,v_stripe,v_futur)
    AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>4
  THEN RAISE EXCEPTION 'Suppression F161 : canaux de recette non fermés'; END IF;
  SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO v_auth_avant FROM auth.users u
    WHERE id IN(v_etab,v_manuel,v_stripe,v_futur,v_sans_profil);

  -- Sans identité, le wrapper reste non appelable par anon.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','anon',true);
  PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
  EXECUTE 'SET LOCAL ROLE anon';
  v_refus:=false;
  BEGIN PERFORM public.fn_supprimer_compte_rate_limited();
  EXCEPTION WHEN insufficient_privilege THEN v_refus:=true; END;
  IF NOT v_refus THEN RAISE EXCEPTION 'Suppression F161 : appel anonyme accepté'; END IF;
  EXECUTE 'RESET ROLE';
  -- Un utilisateur sans profil ne peut choisir le profil d’un autre compte.
  PERFORM set_config('request.jwt.claim.sub',v_sans_profil::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_sans_profil,'role','authenticated')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_resultat:=public.fn_supprimer_compte_rate_limited();
  IF v_resultat->>'error' IS DISTINCT FROM 'Aucun profil soignant lié à ce compte'
  THEN RAISE EXCEPTION 'Suppression F161 : identité sans profil non refusée'; END IF;
  EXECUTE 'RESET ROLE';

  FOR v_i IN 1..3 LOOP
    v_uid:=CASE v_i WHEN 1 THEN v_manuel WHEN 2 THEN v_stripe ELSE v_futur END;
    v_mission:=('f1610001-0000-4000-8000-'||lpad(v_i::text,12,'0'))::uuid;
    v_fh:=('f1610002-0000-4000-8000-'||lpad(v_i::text,12,'0'))::uuid;
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    -- Historique préparé par la voie maintenance existante, sans override.
    -- Ce seed ne prétend pas exécuter le cycle utilisateur de clôture.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
    VALUES(v_mission,v_etab,'Recette suppression historique','IDE',v_futur_jour+time '09:00',v_futur_jour+time '13:00',
      4,20,CASE WHEN v_i=3 THEN 'EN_COURS'::public.statut_mission ELSE 'TERMINEE'::public.statut_mission END,
      v_uid,'LIBERAL','LIBERAL','LIBERAL','NOTE_HONORAIRES','DIRECT','FINALE_UNIQUE',false);
    IF v_i<3 THEN
      UPDATE public.mission_creneaux SET debut=v_passe+time '09:00',fin=v_passe+time '13:00'
        WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL';
      INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
      VALUES(v_mission,v_passe+time '09:00',v_passe+time '13:00','EFFECTIF',false,2);
      IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut='TERMINEE'
        AND fin_le<now() AND duree_heures=4 AND duree_heures_effective=4 AND net_a_payer=80)
      THEN RAISE EXCEPTION 'Suppression F161 : historique 4h/80 incorrect'; END IF;
      INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
        montant_ht,montant_ttc,montant_tva,taux_tva,periode_debut,periode_fin,statut,type_document,
        nature_correction,mode_remboursement,est_facture_finale_mission,quantite_heures_snapshot,taux_horaire_snapshot)
      VALUES(v_fh,public.next_invoice_number(v_uid),v_uid,v_etab,v_mission,80,80,0,0,v_debut,v_debut+6,
        'BROUILLON','FACTURE','ORIGINALE','N_A',true,4,20);
      PERFORM public.fn_emettre_document_facturation_honoraires(v_fh,'recette-f161.pdf','recette-f161.xml');
      IF v_i=1 THEN
        INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,facture_honoraire_id,
          montant_net,methode,reference_virement,date_paiement,statut,confirme_par_etablissement,confirme_par_soignant)
        VALUES(v_mission,v_uid,v_etab,v_fh,80,'VIREMENT','F161-MANUEL',current_date,'DECLARE',true,false)
        RETURNING id INTO v_ps;
        PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
        PERFORM set_config('request.jwt.claim.role','authenticated',true);
        PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        v_resultat:=public.fn_confirmer_paiement_soignant(v_ps);
        IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Suppression F161 : confirmation fixture refusée'; END IF;
        EXECUTE 'RESET ROLE';
      ELSE
        INSERT INTO public.stripe_transfers(mission_id,soignant_id,etablissement_id,facture_honoraire_id,
          montant_total,montant_commission,montant_soignant,statut,stripe_transfer_id,
          stripe_checkout_session_id,stripe_payment_intent_id,stripe_charge_id)
        VALUES(v_mission,v_uid,v_etab,v_fh,94.4,14.4,80,'TRANSFERE','tr_F161synthetique',
          'cs_F161synthetique','pi_F161synthetique','ch_F161synthetique');
        INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,facture_honoraire_id,
          montant_net,methode,date_paiement,statut,stripe_transfer_id,confirme_par_etablissement,confirme_par_soignant)
        VALUES(v_mission,v_uid,v_etab,v_fh,80,'STRIPE_CONNECT',current_date,'CONFIRME','tr_F161synthetique',true,true);
      END IF;
    END IF;
    SELECT to_jsonb(s) INTO v_profil_avant FROM public.soignants s WHERE id=v_uid;
    SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'::jsonb) INTO v_ps_avant FROM public.paiements_soignant p WHERE soignant_id=v_uid;
    SELECT coalesce(jsonb_agg(to_jsonb(st) ORDER BY id),'[]'::jsonb) INTO v_st_avant FROM public.stripe_transfers st WHERE soignant_id=v_uid;
    -- La routine historique conserve son UPDATE sans changement de soignant_id
    -- sur FH : son updated_at/audit peuvent changer, jamais la pièce financière.
    SELECT coalesce(jsonb_agg(to_jsonb(h)-'updated_at' ORDER BY id),'[]'::jsonb) INTO v_piece_avant FROM public.factures_honoraires h WHERE soignant_id=v_uid;
    PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
    SELECT jsonb_object_agg(cle,COALESCE(current_setting(cle,true),'')) INTO v_contextes_avant
      FROM unnest(ARRAY['jolene.system_update','jolene.bank_server_update','jolene.liberal_transition','jolene.siret_liberal_reset']) cle;
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_resultat:=public.fn_supprimer_compte_rate_limited();
    IF v_i<3 THEN
      IF v_resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Suppression F161 : historique % refusé : %',v_i,v_resultat; END IF;
      v_resultat:=public.fn_supprimer_compte_rate_limited();
      IF v_resultat->>'deja_anonymise' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Suppression F161 : reprise sans reçu'; END IF;
    ELSE
      IF v_resultat->>'error' IS DISTINCT FROM 'Vous avez 1 mission(s) en cours.'
      THEN RAISE EXCEPTION 'Suppression F161 : mission future non refusée'; END IF;
    END IF;
    EXECUTE 'RESET ROLE';
    IF v_i<3 THEN
      IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT')
        OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=v_uid AND supprime_le IS NOT NULL
          AND prenom='Soignant' AND nom='Supprimé' AND email LIKE '%@supprime.jolene.app')
      THEN RAISE EXCEPTION 'Suppression F161 : profil ou reçu privé incorrect'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.journaux_audit WHERE acteur_id=v_uid AND action='RGPD_SUPPRESSION_COMPTE'
        AND details->'tables_financieres_conservees'='["stripe_transfers","paiements_soignant"]'::jsonb
        AND NOT (details->'tables_nettoyees' ?| ARRAY['stripe_transfers','paiements_soignant']))
      THEN RAISE EXCEPTION 'Suppression F161 : audit de conservation incorrect'; END IF;
    ELSIF (SELECT to_jsonb(s) FROM public.soignants s WHERE id=v_uid) IS DISTINCT FROM v_profil_avant
      OR private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT') THEN
      RAISE EXCEPTION 'Suppression F161 : refus avec anonymisation partielle';
    END IF;
    IF (SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'::jsonb) FROM public.paiements_soignant p WHERE soignant_id=v_uid) IS DISTINCT FROM v_ps_avant
      OR (SELECT coalesce(jsonb_agg(to_jsonb(st) ORDER BY id),'[]'::jsonb) FROM public.stripe_transfers st WHERE soignant_id=v_uid) IS DISTINCT FROM v_st_avant
      OR (SELECT coalesce(jsonb_agg(to_jsonb(h)-'updated_at' ORDER BY id),'[]'::jsonb) FROM public.factures_honoraires h WHERE soignant_id=v_uid) IS DISTINCT FROM v_piece_avant
    THEN RAISE EXCEPTION 'Suppression F161 : historique financier altéré (%)',v_i; END IF;
    FOREACH v_nom IN ARRAY ARRAY['jolene.system_update','jolene.bank_server_update','jolene.liberal_transition','jolene.siret_liberal_reset'] LOOP
      IF COALESCE(current_setting(v_nom,true),'') IS DISTINCT FROM v_contextes_avant->>v_nom THEN RAISE EXCEPTION 'Suppression F161 : contexte de suppression non restauré'; END IF;
    END LOOP;
  END LOOP;
  IF (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM auth.users u
    WHERE id IN(v_etab,v_manuel,v_stripe,v_futur,v_sans_profil)) IS DISTINCT FROM v_auth_avant
  THEN RAISE EXCEPTION 'Suppression F161 : Auth modifié par la RPC SQL'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab AND supprime_le IS NULL)
    OR EXISTS(SELECT 1 FROM private.suppressions_compte_confirmees WHERE utilisateur_id IN(v_etab,v_futur,v_sans_profil))
  THEN RAISE EXCEPTION 'Suppression F161 : compte tiers ou reçu injustifié'; END IF;
  IF (SELECT count(*) FROM net.http_request_queue)<>v_net_avant
  THEN RAISE EXCEPTION 'Suppression F161 : tentative réseau inattendue'; END IF;
  RAISE NOTICE 'Suppression F161 : manuel, Stripe synthétique, droits, mission future et identités conservées';
END;
$suppression$;
ROLLBACK;
