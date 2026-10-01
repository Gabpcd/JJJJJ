-- F172 : vraie réservation, reprise et émission, triggers actifs, aucune Edge,
-- aucun objet Storage, aucun fournisseur. Le seed est un historique synthétique
-- de maintenance ; il ne prouve ni attribution, ni mandat, ni qualification/TVA.
-- Le sous-bloc est annulé même lorsque validate-pr retire le ROLLBACK externe.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $f172$
DECLARE
  v_soignant constant uuid := 'f1720001-1000-4000-8000-000000000001';
  v_etab constant uuid := 'f1720002-2000-4000-8000-000000000002';
  v_mission constant uuid := 'f1720003-3000-4000-8000-000000000003';
  v_honoraire uuid;
  v_semaine date := date_trunc('week',current_date)::date - 7;
  v_jour_passe date;
  v_jour_futur date;
  v_resultat jsonb;
  v_rejeu jsonb;
  v_snapshot jsonb;
  v_numero text;
  v_nom text;
  v_annule boolean := false;
  v_document jsonb; v_reserve jsonb; v_bail jsonb; v_documents jsonb; v_token uuid; v_token_ancien uuid;
BEGIN
  -- Ce fichier est raccordé uniquement au job staging à verrou global. Aucun
  -- cron ne doit consommer d'outbox ; toutes les écritures restent invisibles.
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
     OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
     OR EXISTS(SELECT 1 FROM net.http_request_queue)
  THEN RAISE EXCEPTION 'F172 : contexte SQL de maintenance isolé requis'; END IF;
  FOREACH v_nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation'] LOOP
    IF NULLIF(current_setting(v_nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'F172 : contexte de contournement interdit'; END IF;
  END LOOP;
  FOREACH v_nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF COALESCE(current_setting(v_nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'F172 : synchronisation forcée interdite'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'F172 : trigger Auth INSERT non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.soignants'::regclass,
    'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,
    'public.factures_honoraires'::regclass,'public.factures'::regclass,'public.notifications'::regclass,
    'public.invoice_audit_log'::regclass) AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'F172 : triggers métier désactivés'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab OR siret='99150000000843')
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=v_mission OR soignant_id=v_soignant)
  THEN RAISE EXCEPTION 'F172 : identifiants de fixture déjà présents'; END IF;

  -- Deux jours ouvrés sans jour férié : montants indépendants, sans modifier le
  -- calendrier. La semaine précédente est fermée ; la mission reste EN_COURS.
  SELECT d::date INTO v_jour_passe FROM generate_series(v_semaine,v_semaine+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_jour_futur FROM generate_series(v_semaine+14,v_semaine+18,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF v_jour_passe IS NULL OR v_jour_futur IS NULL OR v_semaine+6>=current_date
  THEN RAISE EXCEPTION 'F172 : calendrier de fixture indisponible'; END IF;

  BEGIN
    -- INSERT SQL Auth seulement : pas de session/token/SMTP/hook Auth HTTP.
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES (v_soignant,'00000000-0000-0000-0000-000000000000','f172-soignant@example.invalid','authenticated','authenticated',
      '{"role":"SOIGNANT","est_compte_test":true,"is_test_playwright":true}',now()),
      (v_etab,'00000000-0000-0000-0000-000000000000','f172-etablissement@example.invalid','authenticated','authenticated',
      '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true,"is_test_playwright":true}',now());
    INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
      source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
      identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
    VALUES(v_soignant,'Fixture','F172','f172-soignant@example.invalid','IDE','LIBERAL','1990-01-01',true,
      'RECETTE_F172_SQL','F172SQLSOIGNANT',false,false,false,false,false,false,false);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
      est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
      peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
    VALUES(v_etab,'Fixture F172','99150000000843','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',
      'f172-etablissement@example.invalid',true,'RECETTE_F172_SQL','F172SQLETABLISSEMENT',false,false,'EN_ATTENTE',false,false,false,15);
    UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
      WHERE utilisateur_id IN(v_soignant,v_etab);
    IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab)
      AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
    THEN RAISE EXCEPTION 'F172 : canaux de fixture non fermés'; END IF;

    -- Voie maintenance déjà autorisée par trg_verrouiller_etat_initial_mission.
    -- Pas d'override anti-seed, de trigger désactivé ni de qualification créée.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
    VALUES(v_mission,v_etab,'RECETTE F172 SQL annulee','IDE',v_jour_futur+time '09:00',v_jour_futur+time '13:00',
      4,20,'EN_COURS',v_soignant,'LIBERAL','LIBERAL','LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
    IF (SELECT count(*) FROM public.mission_creneaux WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL')<>1
      OR (SELECT fige_le FROM public.missions WHERE id=v_mission) IS NOT NULL
    THEN RAISE EXCEPTION 'F172 : planning legacy/état initial inattendu'; END IF;
    UPDATE public.mission_creneaux SET debut=v_jour_passe+time '09:00',fin=v_jour_passe+time '13:00'
      WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL';
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
    VALUES(v_mission,v_jour_futur+time '09:00',v_jour_futur+time '13:00','PREVISIONNEL',false,2),
      (v_mission,v_jour_passe+time '09:00',v_jour_passe+time '13:00','EFFECTIF',false,3);
    IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut='EN_COURS'
      AND nb_creneaux=2 AND duree_heures=8 AND duree_heures_effective=4 AND total_brut=160 AND net_a_payer=160
      AND montant_ifm=0 AND montant_icp=0 AND montant_commission_ht=24 AND montant_commission_tva=4.8
      AND montant_commission_ttc=28.8 AND fige_le IS NULL)
    THEN RAISE EXCEPTION 'F172 : snapshot indépendant 8h x 20 incohérent'; END IF;
    v_resultat:=public.fn_verifier_pre_facturation(v_mission,v_semaine,v_semaine+6);
    IF v_resultat->'ok' IS DISTINCT FROM 'true'::jsonb OR v_resultat->>'source_facturation'<>'EFFECTIF'
      OR (v_resultat->>'duree_facturee')::numeric IS DISTINCT FROM 4
    THEN RAISE EXCEPTION 'F172 : préfacturation semaine fermée incorrecte'; END IF;
    v_resultat:=public.fn_calculer_montant_periode(v_mission,v_semaine,v_semaine+6);
    IF (v_resultat->>'duree_totale_mission_heures')::numeric IS DISTINCT FROM 8
      OR (v_resultat->>'duree_periode_heures')::numeric IS DISTINCT FROM 4
      OR (v_resultat->>'ratio_periode')::numeric IS DISTINCT FROM 0.5
      OR (v_resultat->>'montant_ht_periode')::numeric IS DISTINCT FROM 80
    THEN RAISE EXCEPTION 'F172 : prorata hebdomadaire indépendant incorrect'; END IF;

    v_document:=jsonb_build_object(
      'soignant_id',v_soignant,'etablissement_id',v_etab,'mission_id',v_mission,
      'montant_ht',80,'montant_tva',0,'montant_ttc',80,'taux_tva',0,'exoneration_tva',true,
      'date_emission',current_date,'date_echeance',current_date+30,
      'mandat_version','FIXTURE_SYNTHESE_NON_SIGNEE','template_version','v2_facturx','is_public_sector',false,
      'periode_debut',v_semaine,'periode_fin',v_semaine+6,
      'numero_semaine_iso',extract(week FROM v_semaine),'annee_iso',extract(isoyear FROM v_semaine),
      'est_facture_finale_mission',false,'quantite_heures_snapshot',4,'taux_horaire_snapshot',20,
      'regime_tva_snapshot','EXONERE_ART_261_4_1','description_prestation_snapshot','4 heures synthétiques',
      'emetteur_identite_snapshot','Łukasz İpek de recette','destinataire_nom_snapshot','Établissement de recette');
    -- Aucun numéro fourni par le client ; une réservation compte aussi sa pièce.
    BEGIN
      PERFORM public.fn_reserver_facture_honoraires(v_document||jsonb_build_object('numero_facture','FORGE'));
      RAISE EXCEPTION 'F172 : numéro client accepté';
    EXCEPTION WHEN invalid_parameter_value THEN
      IF SQLERRM<>'FACTURE_RESERVATION_CHAMPS_INVALIDES' THEN RAISE; END IF;
    END;
    v_reserve:=public.fn_reserver_facture_honoraires(v_document);
    v_honoraire:=(v_reserve->>'facture_id')::uuid; v_token:=(v_reserve->>'token')::uuid;
    IF v_reserve->'cree' IS DISTINCT FROM 'true'::jsonb OR v_token IS NULL
      OR v_reserve->>'numero_facture' NOT LIKE 'JOL-'||replace(v_soignant::text,'-','')||'-%-00001'
      OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_honoraire AND statut='EN_GENERATION'
        AND quantite_heures_snapshot=4 AND taux_horaire_snapshot=20 AND montant_ht=80 AND montant_ttc=80)
    THEN RAISE EXCEPTION 'F172 : réservation canonique invalide'; END IF;
    SELECT to_jsonb(f) INTO v_snapshot FROM public.factures_honoraires f WHERE id=v_honoraire;
    v_rejeu:=public.fn_reserver_facture_honoraires(v_document||jsonb_build_object('emetteur_identite_snapshot','Nom actuel différent'));
    IF v_rejeu->'cree' IS DISTINCT FROM 'false'::jsonb OR (v_rejeu->>'facture_id')::uuid IS DISTINCT FROM v_honoraire
      OR (SELECT to_jsonb(f) FROM public.factures_honoraires f WHERE id=v_honoraire) IS DISTINCT FROM v_snapshot
      OR (public.fn_acquerir_generation_honoraires(v_honoraire))->'acquise' IS DISTINCT FROM 'false'::jsonb
    THEN RAISE EXCEPTION 'F172 : réservation rejouée ou bail occupé altéré'; END IF;
    BEGIN
      PERFORM public.fn_reserver_facture_honoraires(v_document||jsonb_build_object('periode_fin',v_semaine+5));
      RAISE EXCEPTION 'F172 : autre période acceptée';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM<>'FACTURE_RESERVATION_PERIODE_DIFFERENTE' THEN RAISE; END IF;
    END;
    PERFORM public.fn_terminer_generation_honoraires(v_honoraire,v_token,NULL);
    IF (SELECT statut FROM public.factures_honoraires WHERE id=v_honoraire)<>'ERREUR_GENERATION'
      OR EXISTS(SELECT 1 FROM public.factures_honoraires_documents WHERE facture_honoraire_id=v_honoraire)
    THEN RAISE EXCEPTION 'F172 : panne non conservée'; END IF;
    v_token_ancien:=v_token;
    v_bail:=public.fn_acquerir_generation_honoraires(v_honoraire); v_token:=(v_bail->>'token')::uuid;
    IF v_bail->'acquise' IS DISTINCT FROM 'true'::jsonb OR v_token=v_token_ancien
      OR (SELECT numero_facture FROM public.factures_honoraires WHERE id=v_honoraire) IS DISTINCT FROM v_snapshot->>'numero_facture'
    THEN RAISE EXCEPTION 'F172 : reprise changeant la pièce ou le numéro'; END IF;
    BEGIN
      PERFORM public.fn_terminer_generation_honoraires(v_honoraire,v_token_ancien,NULL);
      RAISE EXCEPTION 'F172 : échec ancien accepté';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM<>'FACTURE_GENERATION_TOKEN_PERIME' THEN RAISE; END IF;
    END;
    -- Horloge de bail de cette seule fixture ; aucune horloge métier modifiée.
    UPDATE private.generations_factures_honoraires SET expire_le=clock_timestamp()-interval '1 second'
      WHERE facture_id=v_honoraire;
    BEGIN
      PERFORM public.fn_terminer_generation_honoraires(v_honoraire,v_token,NULL);
      RAISE EXCEPTION 'F172 : bail expiré accepté';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM<>'FACTURE_GENERATION_BAIL_EXPIRE' THEN RAISE; END IF;
    END;
    v_token_ancien:=v_token;
    v_bail:=public.fn_acquerir_generation_honoraires(v_honoraire); v_token:=(v_bail->>'token')::uuid;
    IF v_bail->'acquise' IS DISTINCT FROM 'true'::jsonb OR v_token=v_token_ancien
    THEN RAISE EXCEPTION 'F172 : bail expiré non repris'; END IF;
    -- Références synthétiques : preuve SQL seulement, aucun octet Storage créé.
    v_numero:=(SELECT numero_facture FROM public.factures_honoraires WHERE id=v_honoraire);
    v_documents:=jsonb_build_object(
      'pdf_s3_key','invoices/'||v_soignant||'/'||v_numero||'/f1720004-4000-4000-8000-000000000004.pdf',
      'facturx_xml_url','invoices/'||v_soignant||'/'||v_numero||'/f1720005-5000-4000-8000-000000000005.xml',
      'pdf_sha256',repeat('a',64),'xml_sha256',repeat('b',64));
    BEGIN
      PERFORM public.fn_terminer_generation_honoraires(v_honoraire,v_token_ancien,v_documents);
      RAISE EXCEPTION 'F172 : émission ancienne acceptée';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM<>'FACTURE_GENERATION_TOKEN_PERIME' THEN RAISE; END IF;
    END;
    v_resultat:=public.fn_terminer_generation_honoraires(v_honoraire,v_token,v_documents);
    SELECT to_jsonb(f) INTO v_snapshot FROM public.factures_honoraires f WHERE id=v_honoraire;
    UPDATE private.generations_factures_honoraires SET expire_le=clock_timestamp()-interval '1 second'
      WHERE facture_id=v_honoraire;
    IF public.fn_terminer_generation_honoraires(v_honoraire,v_token,v_documents) IS DISTINCT FROM v_resultat
      OR public.fn_terminer_generation_honoraires(v_honoraire,v_token,NULL) IS DISTINCT FROM v_resultat
      OR (SELECT to_jsonb(f) FROM public.factures_honoraires f WHERE id=v_honoraire) IS DISTINCT FROM v_snapshot
      OR v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
      OR v_snapshot->>'statut'<>'EMISE'
      OR (SELECT count(*) FROM public.factures_honoraires WHERE mission_id=v_mission)<>1
      OR (SELECT count(*) FROM public.factures_honoraires_documents WHERE facture_honoraire_id=v_honoraire)<>1
      OR (SELECT count(*) FROM public.notifications WHERE id_ressource=v_honoraire AND type='FACTURE_EMISE')<>2
      OR (SELECT count(*) FROM public.invoice_audit_log WHERE invoice_id=v_honoraire AND action='EMISSION_ET_REMISE_COPIE')<>1
      OR (SELECT count(*) FROM public.factures_honoraires_documents WHERE facture_honoraire_id=v_honoraire
        AND pdf_s3_key=v_documents->>'pdf_s3_key' AND facturx_xml_url=v_documents->>'facturx_xml_url'
        AND pdf_sha256=v_documents->>'pdf_sha256' AND xml_sha256=v_documents->>'xml_sha256')<>1
    THEN RAISE EXCEPTION 'F172 : émission/registre/rejeu non exacts'; END IF;
    IF EXISTS(SELECT 1 FROM net.http_request_queue)
      OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(v_soignant,v_etab))
      OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE avoir_id=v_honoraire)
      OR EXISTS(SELECT 1 FROM public.cessions_creance WHERE facture_honoraire_id=v_honoraire)
      OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=v_mission)
      OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource IN(v_mission,v_honoraire) AND action='OVERRIDE_ANTI_SEED')
    THEN RAISE EXCEPTION 'F172 : effet sortant ou override'; END IF;
    RAISE EXCEPTION USING ERRCODE='JF172',MESSAGE='F172_ANNULATION_ATTENDUE';
  EXCEPTION WHEN SQLSTATE 'JF172' THEN
    IF SQLERRM<>'F172_ANNULATION_ATTENDUE' THEN RAISE; END IF;
    v_annule:=true;
  END;
  IF NOT v_annule OR EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab)
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission)
    OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_honoraire OR mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM private.generations_factures_honoraires WHERE facture_id=v_honoraire)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires_documents WHERE facture_honoraire_id=v_honoraire)
    OR EXISTS(SELECT 1 FROM public.factures WHERE facture_honoraire_id=v_honoraire)
    OR EXISTS(SELECT 1 FROM public.invoice_audit_log WHERE invoice_id=v_honoraire)
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.conformite_travail WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=v_soignant)
  THEN RAISE EXCEPTION 'F172 : annulation non prouvée'; END IF;
END $f172$;
SELECT 'F172_SQL_ROLLBACK' AS preuve,true AS annule;
ROLLBACK;
