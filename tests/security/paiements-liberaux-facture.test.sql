-- Staging : vraies fonctions/triggers, écritures intégralement annulées.
-- Les traces Stripe sont synthétiques : aucune invocation ni preuve fournisseur.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $f1$
DECLARE
  v_soignant constant uuid := 'f1520001-1000-4000-8000-000000000001';
  v_etab constant uuid := 'f1520002-2000-4000-8000-000000000002';
  v_mission constant uuid := 'f1520003-3000-4000-8000-000000000003';
  v_honoraire constant uuid := 'f1520004-4000-4000-8000-000000000004';
  v_doublon constant uuid := 'f1520005-5000-4000-8000-000000000005';
  v_commission uuid;
  v_semaine date := date_trunc('week',current_date)::date - 7;
  v_jour_passe date;
  v_jour_futur date;
  v_resultat jsonb;
  v_rejeu jsonb;
  v_snapshot jsonb;
  v_numero text;
  v_nom text;
  v_annule boolean := false;
  v_paiement uuid;
  v_transfer uuid;
  v_avant jsonb;
  v_montant numeric;
  v_colonne text;
  v_refus boolean;
  v_salarie constant uuid := 'f1520006-6000-4000-8000-000000000006';
  v_cas integer:=0;
  v_statut text;
  v_code text;
BEGIN
  -- Ce fichier est raccordé uniquement au job staging à verrou global. Aucun
  -- cron ne doit consommer d'outbox ; toutes les écritures restent invisibles.
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
     OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'Paiement F152 : contexte SQL de maintenance isolé requis'; END IF;
  FOREACH v_nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation'] LOOP
    IF NULLIF(current_setting(v_nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'Paiement F152 : contexte de contournement interdit'; END IF;
  END LOOP;
  FOREACH v_nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF COALESCE(current_setting(v_nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'Paiement F152 : synchronisation forcée interdite'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'Paiement F152 : trigger Auth INSERT non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.soignants'::regclass,
    'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,
    'public.factures_honoraires'::regclass,'public.factures'::regclass,'public.notifications'::regclass,
    'public.invoice_audit_log'::regclass,'public.paiements_soignant'::regclass,
    'public.stripe_transfers'::regclass,'public.stripe_payment_flow_claims'::regclass) AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'Paiement F152 : triggers métier désactivés'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab OR siret='99150000001847')
    OR EXISTS(SELECT 1 FROM public.missions WHERE id IN(v_mission,v_salarie))
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id IN(v_honoraire,v_doublon))
  THEN RAISE EXCEPTION 'Paiement F152 : identifiants de fixture déjà présents'; END IF;

  -- Deux jours ouvrés sans jour férié : montants indépendants, sans modifier le
  -- calendrier. La semaine précédente est fermée ; la mission reste EN_COURS.
  SELECT d::date INTO v_jour_passe FROM generate_series(v_semaine,v_semaine+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_jour_futur FROM generate_series(v_semaine+14,v_semaine+18,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF v_jour_passe IS NULL OR v_jour_futur IS NULL OR v_semaine+6>=current_date
  THEN RAISE EXCEPTION 'Paiement F152 : calendrier de fixture indisponible'; END IF;

  BEGIN
    -- INSERT SQL Auth seulement : pas de session/token/SMTP/hook Auth HTTP.
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES (v_soignant,'00000000-0000-0000-0000-000000000000','f152-soignant@example.invalid','authenticated','authenticated',
      '{"role":"SOIGNANT","est_compte_test":true,"is_test_playwright":true}',now()),
      (v_etab,'00000000-0000-0000-0000-000000000000','f152-etablissement@example.invalid','authenticated','authenticated',
      '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true,"is_test_playwright":true}',now());
    INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
      source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
      identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
    VALUES(v_soignant,'Fixture','F1','f152-soignant@example.invalid','IDE','LIBERAL','1990-01-01',true,
      'RECETTE_F1_SQL','F152SQLSOIGNANT',false,false,false,false,false,false,false);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
      est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
      peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
    VALUES(v_etab,'Fixture F1','99150000001847','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',
      'f152-etablissement@example.invalid',true,'RECETTE_F1_SQL','F152SQLETABLISSEMENT',false,false,'EN_ATTENTE',false,false,false,15);
    UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
      WHERE utilisateur_id IN(v_soignant,v_etab);
    IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab)
      AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
    THEN RAISE EXCEPTION 'Paiement F152 : canaux de fixture non fermés'; END IF;

    -- Voie maintenance déjà autorisée par trg_verrouiller_etat_initial_mission.
    -- Pas d'override anti-seed, de trigger désactivé ni de qualification créée.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
    VALUES(v_mission,v_etab,'RECETTE F1 SQL annulee','IDE',v_jour_futur+time '09:00',v_jour_futur+time '13:00',
      4,20,'EN_COURS',v_soignant,'LIBERAL','LIBERAL','LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
    IF (SELECT count(*) FROM public.mission_creneaux WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL')<>1
      OR (SELECT fige_le FROM public.missions WHERE id=v_mission) IS NOT NULL
    THEN RAISE EXCEPTION 'Paiement F152 : planning legacy/état initial inattendu'; END IF;
    UPDATE public.mission_creneaux SET debut=v_jour_passe+time '09:00',fin=v_jour_passe+time '13:00'
      WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL';
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
    VALUES(v_mission,v_jour_futur+time '09:00',v_jour_futur+time '13:00','PREVISIONNEL',false,2),
      (v_mission,v_jour_passe+time '09:00',v_jour_passe+time '13:00','EFFECTIF',false,3);
    IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut='EN_COURS'
      AND nb_creneaux=2 AND duree_heures=8 AND duree_heures_effective=4 AND total_brut=160 AND net_a_payer=160
      AND montant_ifm=0 AND montant_icp=0 AND montant_commission_ht=24 AND montant_commission_tva=4.8
      AND montant_commission_ttc=28.8 AND fige_le IS NULL)
    THEN RAISE EXCEPTION 'Paiement F152 : snapshot indépendant 8h x 20 incohérent'; END IF;
    v_resultat:=public.fn_verifier_pre_facturation(v_mission,v_semaine,v_semaine+6);
    IF v_resultat->'ok' IS DISTINCT FROM 'true'::jsonb OR v_resultat->>'source_facturation'<>'EFFECTIF'
      OR (v_resultat->>'duree_facturee')::numeric IS DISTINCT FROM 4
    THEN RAISE EXCEPTION 'Paiement F152 : préfacturation semaine fermée incorrecte'; END IF;
    v_resultat:=public.fn_calculer_montant_periode(v_mission,v_semaine,v_semaine+6);
    IF (v_resultat->>'duree_totale_mission_heures')::numeric IS DISTINCT FROM 8
      OR (v_resultat->>'duree_periode_heures')::numeric IS DISTINCT FROM 4
      OR (v_resultat->>'ratio_periode')::numeric IS DISTINCT FROM 0.5
      OR (v_resultat->>'montant_ht_periode')::numeric IS DISTINCT FROM 80
    THEN RAISE EXCEPTION 'Paiement F152 : prorata hebdomadaire indépendant incorrect'; END IF;

    INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
      montant_ht,montant_ttc,montant_tva,taux_tva,periode_debut,periode_fin,statut,
      type_document,nature_correction,mode_remboursement,est_facture_finale_mission,
      quantite_heures_snapshot,taux_horaire_snapshot)
    VALUES(v_honoraire,public.next_invoice_number(v_soignant),v_soignant,v_etab,v_mission,
      80,80,0,0,v_semaine,v_semaine+6,'BROUILLON','FACTURE','ORIGINALE','N_A',false,4,20);
    PERFORM public.fn_emettre_document_facturation_honoraires(v_honoraire,'fixture-paiement.pdf','fixture-paiement.xml');
    v_commission:=(public.fn_preparer_facture_commission_periode(v_honoraire)->>'facture_id')::uuid;
    IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission AND montant_ttc=14.4)
    THEN RAISE EXCEPTION 'Paiement F152 : commission fixture incorrecte'; END IF;

    PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF public.mon_etablissement_id() IS DISTINCT FROM v_etab OR public.est_admin()
      OR public.fn_a_permission_etablissement('paiement',v_etab) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Paiement F152 : acteur établissement incorrect';
    END IF;
    v_resultat:=public.fn_declarer_paiement_soignant(v_mission,160,'VIREMENT','TEST152',current_date,true);
    v_rejeu:=public.fn_declarer_paiement_soignant_v2(v_mission,160,160,'VIREMENT','TEST152',current_date,true);
    IF v_resultat->>'error' IS DISTINCT FROM 'LIBERAL_FACTURE_REQUISE'
      OR v_rejeu->>'error' IS DISTINCT FROM 'LIBERAL_FACTURE_REQUISE'
      OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_mission) THEN
      RAISE EXCEPTION 'Paiement F152 : voie globale encore ouverte';
    END IF;
    v_cas:=v_cas+1;
    BEGIN
      INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,montant_net,methode,statut,confirme_par_etablissement)
      VALUES(v_mission,v_soignant,v_etab,160,'VIREMENT','DECLARE',true);
      RAISE EXCEPTION 'Paiement F152 : INSERT mission-only accepté';
    EXCEPTION WHEN check_violation THEN IF SQLERRM<>'LIBERAL_FACTURE_REQUISE' THEN RAISE; END IF; END;
    FOREACH v_montant IN ARRAY ARRAY[79.99,80.01,80.001,'NaN'::numeric,'Infinity'::numeric] LOOP
      v_resultat:=public.fn_declarer_paiement_facture_soignant(v_honoraire,v_montant,'VIREMENT','TEST152',current_date,true);
      IF NOT (v_resultat ? 'error') THEN RAISE EXCEPTION 'Paiement F152 : montant RPC invalide accepté %',v_montant; END IF;
      BEGIN
        INSERT INTO public.paiements_soignant(mission_id,facture_honoraire_id,soignant_id,etablissement_id,montant_net,methode,statut,confirme_par_etablissement)
        VALUES(v_mission,v_honoraire,v_soignant,v_etab,v_montant,'VIREMENT','DECLARE',true);
        RAISE EXCEPTION 'Paiement F152 : montant INSERT invalide accepté %',v_montant;
      EXCEPTION WHEN check_violation THEN IF SQLERRM<>'MONTANT_FACTURE_INCOHERENT' THEN RAISE; END IF; END;
    END LOOP;
    v_cas:=v_cas+1;
    BEGIN
      INSERT INTO public.paiements_soignant(mission_id,facture_honoraire_id,soignant_id,etablissement_id,montant_net,methode,statut,confirme_par_etablissement,
        stripe_transfer_id,confirme_par_soignant)
      VALUES(v_mission,v_honoraire,v_soignant,v_etab,80,'STRIPE_CONNECT','CONFIRME',true,'tr_F152faux',true);
      RAISE EXCEPTION 'Paiement F152 : provenance client Stripe acceptée';
    EXCEPTION WHEN check_violation THEN IF SQLERRM<>'PREUVE_STRIPE_REQUISE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    -- Ce sous-scénario réussit puis s'annule : le scénario Stripe conserve la
    -- même facture EMISE, pas une dette fabriquée après un paiement acquis.
    BEGIN
      v_resultat:=public.fn_declarer_paiement_facture_soignant(v_honoraire,80,'VIREMENT','TEST152',current_date,true);
      v_paiement:=(v_resultat->>'paiement_id')::uuid;
      IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
        OR NOT EXISTS(SELECT 1 FROM public.paiements_soignant WHERE id=v_paiement AND montant_net=80
          AND facture_honoraire_id=v_honoraire AND source_montant_du='FACTURE_HONORAIRES'
          AND montant_du_reference=80 AND solde_restant=0 AND NOT est_partiel AND statut='DECLARE') THEN
        RAISE EXCEPTION 'Paiement F152 : déclaration documentaire refusée ou altérée %',v_resultat;
      END IF;
      v_rejeu:=public.fn_declarer_paiement_facture_soignant(v_honoraire,80,'VIREMENT','TEST152',current_date,true);
      IF NOT (v_rejeu ? 'error') OR (SELECT count(*) FROM public.paiements_soignant WHERE facture_honoraire_id=v_honoraire)<>1 THEN
        RAISE EXCEPTION 'Paiement F152 : double déclaration acceptée';
      END IF;
      FOREACH v_colonne IN ARRAY ARRAY['montant_net','facture_honoraire_id','soignant_id','montant_du_reference','source_montant_du','stripe_transfer_id'] LOOP
        BEGIN
          EXECUTE format('UPDATE public.paiements_soignant SET %I=%s WHERE id=$1',v_colonne,
            CASE v_colonne WHEN 'montant_net' THEN '79' WHEN 'montant_du_reference' THEN '81'
              WHEN 'facture_honoraire_id' THEN 'NULL' WHEN 'soignant_id' THEN quote_literal(v_etab)
              WHEN 'source_montant_du' THEN quote_literal('CLIENT') ELSE quote_literal('tr_F152faux') END) USING v_paiement;
          RAISE EXCEPTION 'Paiement F152 : mutation financière acceptée %',v_colonne;
        EXCEPTION WHEN check_violation THEN IF SQLERRM<>'PAIEMENT_FINANCIER_IMMUABLE' THEN RAISE; END IF; END;
      END LOOP;
      v_resultat:=public.fn_modifier_reference_paiement(v_paiement,'TEST152B');
      IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb THEN
        RAISE EXCEPTION 'Paiement F152 : modification canonique de référence cassée'; END IF;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      v_resultat:=public.fn_confirmer_paiement_soignant(v_paiement);
      IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
        OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_honoraire AND statut='PAYEE')
        OR NOT EXISTS(SELECT 1 FROM public.paiements_soignant WHERE id=v_paiement AND montant_net=80 AND facture_honoraire_id=v_honoraire
          AND statut='CONFIRME' AND reference_virement='TEST152B') THEN
        RAISE EXCEPTION 'Paiement F152 : confirmation documentaire incorrecte'; END IF;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
      BEGIN
        PERFORM public.fn_stripe_payment_flow_claim('CONNECT_INVOICE','connect-invoice:'||v_honoraire::text,v_commission,NULL);
        RAISE EXCEPTION 'Paiement F152 : claim après déclaration accepté';
      EXCEPTION WHEN check_violation THEN IF SQLERRM<>'PAIEMENT_FACTURE_DEJA_DECLARE' THEN RAISE; END IF; END;
      RAISE EXCEPTION 'F152_MANUEL_ANNULE' USING ERRCODE='JP151';
    EXCEPTION WHEN SQLSTATE 'JP151' THEN IF SQLERRM<>'F152_MANUEL_ANNULE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    BEGIN
      v_resultat:=public.fn_stripe_payment_flow_claim('CONNECT_INVOICE','connect-invoice:'||v_honoraire::text,v_commission,NULL);
      IF v_resultat->'acquired' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'Paiement F152 : réservation refusée'; END IF;
      BEGIN
        PERFORM public.fn_stripe_payment_flow_claim('CONNECT_MISSION','connect:'||v_mission::text,NULL,v_mission);
        RAISE EXCEPTION 'Paiement F152 : claims croisés acceptés';
      EXCEPTION WHEN check_violation THEN IF SQLERRM<>'PAIEMENT_STRIPE_EN_COURS' THEN RAISE; END IF; END;
      PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      v_resultat:=public.fn_declarer_paiement_facture_soignant(v_honoraire,80,'VIREMENT','TEST152',current_date,true);
      IF v_resultat->>'error' IS DISTINCT FROM 'PAIEMENT_STRIPE_EN_COURS' THEN
        RAISE EXCEPTION 'Paiement F152 : réservation ignorée %',v_resultat; END IF;
      RAISE EXCEPTION 'F152_CLAIM_ANNULE' USING ERRCODE='JP152';
    EXCEPTION WHEN SQLSTATE 'JP152' THEN IF SQLERRM<>'F152_CLAIM_ANNULE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      v_resultat:=public.fn_declarer_paiement_facture_soignant(v_honoraire,80,'VIREMENT','TEST152',current_date,true);
      IF v_resultat->>'error' IS DISTINCT FROM 'Accès refusé' OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_mission) THEN
        RAISE EXCEPTION 'Paiement F152 : rôle soignant autorisé à déclarer pour établissement'; END IF;
      RAISE EXCEPTION 'F152_ROLE_ANNULE' USING ERRCODE='JP158';
    EXCEPTION WHEN SQLSTATE 'JP158' THEN IF SQLERRM<>'F152_ROLE_ANNULE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    -- Refus de pièces closes : état comptable synthétique, jamais présenté
    -- comme un paiement fournisseur ou une résolution de litige réalisée.
    FOREACH v_statut IN ARRAY ARRAY['PAYEE','REMPLACEE','ANNULEE','FACTORISEE'] LOOP
      BEGIN
        UPDATE public.factures_honoraires SET statut=v_statut WHERE id=v_honoraire;
        PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
        PERFORM set_config('request.jwt.claim.role','authenticated',true);
        PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
        EXECUTE 'SET LOCAL ROLE authenticated';
        v_resultat:=public.fn_declarer_paiement_facture_soignant(v_honoraire,80,'VIREMENT','TEST152',current_date,true);
        IF NOT (v_resultat ? 'error') THEN RAISE EXCEPTION 'Paiement F152 : statut non payable accepté %',v_statut; END IF;
        BEGIN
          INSERT INTO public.paiements_soignant(mission_id,facture_honoraire_id,soignant_id,etablissement_id,montant_net,methode,statut,confirme_par_etablissement)
          VALUES(v_mission,v_honoraire,v_soignant,v_etab,80,'VIREMENT','DECLARE',true);
          RAISE EXCEPTION 'Paiement F152 : INSERT sur pièce close accepté';
        EXCEPTION WHEN check_violation THEN IF SQLERRM<>'DECLARATION_FACTURE_INVALIDE' THEN RAISE; END IF; END;
        RAISE EXCEPTION 'F152_PIECE_CLOSE_ANNULEE' USING ERRCODE='JP154';
      EXCEPTION WHEN SQLSTATE 'JP154' THEN IF SQLERRM<>'F152_PIECE_CLOSE_ANNULEE' THEN RAISE; END IF; END;
    END LOOP;
    v_cas:=v_cas+1;
    BEGIN
      -- Avoir synthétique en cours de préparation : aucun envoi, remboursement
      -- ou imputation. L'avoir total reste distinct : le paiement n'est pas ramené implicitement à zéro.
      INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
        montant_ht,montant_ttc,montant_tva,taux_tva,periode_debut,periode_fin,statut,
        type_document,nature_correction,mode_remboursement,est_facture_finale_mission,facture_precedente_id)
      VALUES(v_doublon,public.next_avoir_number(v_soignant),v_soignant,v_etab,v_mission,
        80,80,0,0,v_semaine,v_semaine+6,'BROUILLON','AVOIR','AVOIR','VIREMENT_MANUEL',false,v_honoraire);
      BEGIN
        PERFORM public.fn_stripe_payment_flow_claim('CONNECT_INVOICE','connect-invoice:'||v_honoraire::text,v_commission,NULL);
        RAISE EXCEPTION 'Paiement F152 : nouveau claim malgré avoir accepté';
      EXCEPTION WHEN check_violation THEN IF SQLERRM<>'AVOIR_A_RAPPROCHER' THEN RAISE; END IF; END;
      PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      v_resultat:=public.fn_declarer_paiement_facture_soignant(v_honoraire,80,'VIREMENT','TEST152',current_date,true);
      IF v_resultat->>'error' IS DISTINCT FROM 'AVOIR_A_RAPPROCHER' THEN
        RAISE EXCEPTION 'Paiement F152 : avoir ignoré %',v_resultat; END IF;
      v_resultat:=public.fn_declarer_paiement_facture_soignant(v_doublon,80,'VIREMENT','TEST152',current_date,true);
      IF NOT (v_resultat ? 'error') THEN RAISE EXCEPTION 'Paiement F152 : avoir pris pour facture'; END IF;
      RAISE EXCEPTION 'F152_AVOIR_ANNULE' USING ERRCODE='JP155';
    EXCEPTION WHEN SQLSTATE 'JP155' THEN IF SQLERRM<>'F152_AVOIR_ANNULE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    BEGIN
      INSERT INTO public.paiements_escrow(mission_id,etablissement_id,soignant_id,
        montant_total_cents,commission_cents,honoraires_cents,statut)
      VALUES(v_mission,v_etab,v_soignant,9440,1440,8000,'INITIE');
      PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      BEGIN
        INSERT INTO public.paiements_soignant(mission_id,facture_honoraire_id,soignant_id,etablissement_id,montant_net,methode,statut,confirme_par_etablissement)
        VALUES(v_mission,v_honoraire,v_soignant,v_etab,80,'VIREMENT','DECLARE',true);
        RAISE EXCEPTION 'Paiement F152 : INSERT manuel en doublon escrow accepté';
      EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM<>'Le paiement de cette mission passe par le circuit sécurisé (paiement rapide) : la déclaration manuelle est indisponible.' THEN RAISE; END IF;
      END;
      IF EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_mission) THEN
        RAISE EXCEPTION 'Paiement F152 : doublon escrow résiduel'; END IF;
      RAISE EXCEPTION 'F152_ESCROW_ANNULE' USING ERRCODE='JP156';
    EXCEPTION WHEN SQLSTATE 'JP156' THEN IF SQLERRM<>'F152_ESCROW_ANNULE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    BEGIN
      -- Historique salarié synthétique : salaire déclaré 60, aucun bulletin
      -- émis ni paiement bancaire. Le même RPC doit conserver sa branche paie.
      INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
        duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
        choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
      VALUES(v_salarie,v_etab,'RECETTE F152 salarié synthétique','IDE',v_jour_futur+time '15:00',v_jour_futur+time '19:00',
        4,20,'TERMINEE',v_soignant,'SALARIE','SALARIE','SALARIE','BULLETIN_PAIE','DIRECT','FINALE_UNIQUE',false);
      IF (SELECT count(*) FROM public.mission_creneaux WHERE mission_id=v_salarie AND type_creneau='PREVISIONNEL')<>1 THEN
        RAISE EXCEPTION 'Paiement F152 : planning salarié initial inattendu'; END IF;
      UPDATE public.mission_creneaux SET debut=v_jour_passe+time '15:00',fin=v_jour_passe+time '19:00'
        WHERE mission_id=v_salarie AND type_creneau='PREVISIONNEL';
      IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_salarie AND statut='TERMINEE'
        AND debut_le=v_jour_passe+time '15:00' AND fin_le=v_jour_passe+time '19:00'
        AND fin_le<now() AND duree_heures=4 AND total_brut=80) THEN
        RAISE EXCEPTION 'Paiement F152 : historique salarié 4 h x 20 incohérent'; END IF;
      PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      v_resultat:=public.fn_declarer_paiement_soignant_v2(v_salarie,60,60,'VIREMENT','TEST152SAL',current_date,true);
      IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
        OR v_resultat->>'source_montant_du' IS DISTINCT FROM 'BULLETIN_OFFICIEL_ETABLISSEMENT'
        OR NOT EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_salarie
          AND montant_net=60 AND montant_du_reference=60 AND solde_restant=0 AND NOT est_partiel
          AND facture_honoraire_id IS NULL AND statut='DECLARE') THEN
        RAISE EXCEPTION 'Paiement F152 : branche salarié régressée %',v_resultat; END IF;
      RAISE EXCEPTION 'F152_SALARIE_ANNULE' USING ERRCODE='JP157';
    EXCEPTION WHEN SQLSTATE 'JP157' THEN IF SQLERRM<>'F152_SALARIE_ANNULE' THEN RAISE; END IF; END;
    v_cas:=v_cas+1;
    -- Droits des nouveaux triggers fermés ; les RPC publiques conservent leur ACL.
    IF has_function_privilege('anon','private.fn_garder_paiement_liberal_facture()','EXECUTE')
      OR has_function_privilege('authenticated','private.fn_garder_paiement_liberal_facture()','EXECUTE')
      OR has_function_privilege('service_role','private.fn_garder_reservation_connect()','EXECUTE')
      OR has_function_privilege('authenticated','public.fn_stripe_payment_flow_claim(text,text,uuid,uuid)','EXECUTE') THEN
      RAISE EXCEPTION 'Paiement F152 : ACL ouverte'; END IF;
    v_cas:=v_cas+1;
    -- Trace explicitement synthétique, montant/identité acquis au sens du SQL.
    -- Aucun appel Stripe : la vérification fournisseur est une preuve distincte.
    INSERT INTO public.stripe_transfers(mission_id,facture_id,facture_honoraire_id,soignant_id,etablissement_id,
      montant_soignant,montant_commission,montant_total,statut,stripe_checkout_session_id,
      stripe_payment_intent_id,stripe_charge_id,stripe_transfer_id)
    VALUES(v_mission,v_commission,v_honoraire,v_soignant,v_etab,80,14.4,94.4,'TRANSFERE',
      'cs_F152synthetique','pi_F152synthetique','ch_F152synthetique','tr_F152synthetique') RETURNING id INTO v_transfer;
    v_resultat:=public.fn_stripe_connect_rapprocher_facture(v_mission,v_soignant,v_etab,v_honoraire,v_commission,
      'cs_F152synthetique','pi_F152synthetique','ch_F152synthetique','tr_F152synthetique',8000,1440,9440,now());
    IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
      OR (SELECT count(*) FROM public.paiements_soignant WHERE facture_honoraire_id=v_honoraire
        AND statut='CONFIRME' AND montant_net=80 AND stripe_transfer_id='tr_F152synthetique')<>1 THEN
      RAISE EXCEPTION 'Paiement F152 : rapprochement Stripe synthétique refusé %',v_resultat; END IF;
    SELECT to_jsonb(p) INTO v_avant FROM public.paiements_soignant p WHERE facture_honoraire_id=v_honoraire;
    v_rejeu:=public.fn_stripe_connect_rapprocher_facture(v_mission,v_soignant,v_etab,v_honoraire,v_commission,
      'cs_F152synthetique','pi_F152synthetique','ch_F152synthetique','tr_F152synthetique',8000,1440,9440,now());
    IF v_rejeu->'success' IS DISTINCT FROM 'true'::jsonb
      OR v_avant IS DISTINCT FROM (SELECT to_jsonb(p) FROM public.paiements_soignant p WHERE facture_honoraire_id=v_honoraire) THEN
      RAISE EXCEPTION 'Paiement F152 : rejeu Stripe réécrit le paiement'; END IF;
    -- Même trace acquise, mais JWT authenticated : aucun champ client ni
    -- ON CONFLICT n'accorde l'exception réservée au rapprochement service.
    PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      INSERT INTO public.paiements_soignant(mission_id,facture_honoraire_id,soignant_id,etablissement_id,montant_net,methode,statut,
        confirme_par_etablissement,confirme_par_soignant,stripe_transfer_id)
      VALUES(v_mission,v_honoraire,v_soignant,v_etab,80,'NOTE_HONORAIRES','CONFIRME',true,true,'tr_F152synthetique')
      ON CONFLICT(stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL DO NOTHING;
      RAISE EXCEPTION 'Paiement F152 : rejeu Stripe client accepté';
    EXCEPTION WHEN check_violation THEN IF SQLERRM<>'PREUVE_STRIPE_REQUISE' THEN RAISE; END IF; END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    v_cas:=v_cas+1;
    IF v_cas<>12 OR EXISTS(SELECT 1 FROM net.http_request_queue)
      OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE facture_origine_id=v_honoraire)
      OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=v_mission) THEN
      RAISE EXCEPTION 'Paiement F152 : compte des cas ou effet sortant inattendu'; END IF;
    RAISE EXCEPTION 'F152_ANNULATION_ATTENDUE' USING ERRCODE='JP153';
  EXCEPTION WHEN SQLSTATE 'JP153' THEN
    IF SQLERRM<>'F152_ANNULATION_ATTENDUE' THEN RAISE; END IF;
    v_annule:=true;
  END;
  IF NOT v_annule OR EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.missions WHERE id IN(v_mission,v_salarie))
    OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key IN('MISSION:'||v_mission::text,'FACTURE:'||v_commission::text))
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(v_soignant,v_etab))
  THEN RAISE EXCEPTION 'Paiement F152 : résidu après annulation'; END IF;
END $f1$;
SELECT 'PAIEMENTS_LIBERAUX_ROLLBACK' AS preuve,true AS annule;
ROLLBACK;
