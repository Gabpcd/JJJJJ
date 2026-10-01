-- Régression : commission globale après remplacement canonique d’une facture hebdomadaire.
-- Source de seed : banc F1 rollback existant ; taux, heures seules et finale.
-- Le cas heures seules décrit la parité historique, pas une cohérence globale corrigée.
-- Pas Edge/Storage. Les références PDF/XML ci-dessous sont fictives.
-- Le pg_net notify-support éventuel reste dans une transaction jamais commitée.
-- Les claims administrateur sont synthétiques : aucune preuve de login/MFA.
-- F1 : logique SQL d'une échéance intermédiaire, triggers actifs, aucune Edge,
-- aucun objet Storage, aucun fournisseur. Le seed est un historique synthétique
-- de maintenance ; il ne prouve ni attribution, ni mandat, ni qualification/TVA.
-- Le sous-bloc est annulé même lorsque validate-pr retire le ROLLBACK externe.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $f1$
DECLARE
  v_soignant constant uuid := 'f1310001-1000-4000-8000-000000000001';
  v_etab constant uuid := 'f1310002-2000-4000-8000-000000000002';
  v_mission constant uuid := 'f1310003-3000-4000-8000-000000000003';
  v_honoraire constant uuid := 'f1310004-4000-4000-8000-000000000004';
  v_doublon constant uuid := 'f1310005-5000-4000-8000-000000000005';
  v_commission uuid;
  v_admin constant uuid := 'f1310006-6000-4000-8000-000000000006';
  v_equipe constant uuid := 'f1310007-7000-4000-8000-000000000007';
  v_litige constant uuid := 'f1310008-8000-4000-8000-000000000008';
  v_presence constant uuid := 'f1310009-9000-4000-8000-000000000009';
  v_remplacement uuid;
  v_commission_remplacement uuid;
  v_commission_globale numeric;
  v_net_global numeric;
  v_semaine date := date_trunc('week',current_date)::date - 7;
  v_jour_passe date;
  v_jour_futur date;
  v_resultat jsonb;
  v_rejeu jsonb;
  v_snapshot jsonb;
  v_numero text;
  v_nom text;
  v_annule boolean := false;
  v_cas record;
  v_financier_avant jsonb;
  v_mission_apres jsonb;
  v_initial_net numeric;
  v_duree_mission numeric;
  v_statut public.statut_mission;
BEGIN
  -- Ce fichier est raccordé uniquement au job staging à verrou global. Aucun
  -- cron ne doit consommer d'outbox ; toutes les écritures restent invisibles.
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
     OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'F1 : contexte SQL de maintenance isolé requis'; END IF;
  FOREACH v_nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation'] LOOP
    IF NULLIF(current_setting(v_nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'F1 : contexte de contournement interdit'; END IF;
  END LOOP;
  FOREACH v_nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF COALESCE(current_setting(v_nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'F1 : synchronisation forcée interdite'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'F1 : trigger Auth INSERT non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.soignants'::regclass,
    'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,
    'public.factures_honoraires'::regclass,'public.factures'::regclass,'public.notifications'::regclass,
    'public.invoice_audit_log'::regclass,'public.presences'::regclass) AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'F1 : triggers métier désactivés'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab,v_admin))
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=v_equipe OR user_id=v_admin)
    OR EXISTS(SELECT 1 FROM public.litiges WHERE id=v_litige)
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=v_presence OR mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab OR siret='99150000000843')
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id IN(v_honoraire,v_doublon))
  THEN RAISE EXCEPTION 'F1 : identifiants de fixture déjà présents'; END IF;

  -- Deux jours ouvrés sans jour férié : montants indépendants, sans modifier le
  -- calendrier. La semaine précédente est fermée ; la mission reste EN_COURS.
  SELECT d::date INTO v_jour_passe FROM generate_series(v_semaine,v_semaine+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_jour_futur FROM generate_series(v_semaine+14,v_semaine+18,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF v_jour_passe IS NULL OR v_jour_futur IS NULL OR v_semaine+6>=current_date
  THEN RAISE EXCEPTION 'F1 : calendrier de fixture indisponible'; END IF;

  -- Les deux premiers cas caractérisent les chemins partagés AVANT la
  -- régression de taux hebdomadaire. Atteindre celle-ci prouve leur passage.
  -- Pour les heures seules, 160/21 est la parité historique à documenter,
  -- PAS une nouvelle règle : 21 ne représente pas 15 % du net resté à 160.
  FOR v_cas IN SELECT * FROM (VALUES
    ('heures_seules_historique',false,3::numeric,NULL::numeric,20::numeric,
      60::numeric,160::numeric,9::numeric,1.80::numeric,10.80::numeric,
      24::numeric,4.80::numeric,28.80::numeric,21::numeric,4.20::numeric,25.20::numeric),
    ('finale_taux_baisse',true,NULL,18,18,72,72,10.80,2.16,12.96,10.80,2.16,12.96,10.80,2.16,12.96),
    ('hebdo_taux_baisse',false,NULL,18,18,72,144,10.80,2.16,12.96,21.60,4.32,25.92,21.60,4.32,25.92),
    ('hebdo_taux_hausse',false,NULL,22,22,88,176,13.20,2.64,15.84,26.40,5.28,31.68,26.40,5.28,31.68),
    ('hebdo_taux_baisse_payload_ui',false,4,18,18,72,144,10.80,2.16,12.96,21.60,4.32,25.92,21.60,4.32,25.92)
  ) AS cas(nom,finale,heures_ajustees,taux_ajuste,taux,honoraires,net_global,
    commission_ht,commission_tva,commission_ttc,avant_ht,avant_tva,avant_ttc,globale_ht,globale_tva,globale_ttc) LOOP
  v_duree_mission:=CASE WHEN v_cas.finale THEN 4 ELSE 8 END;
  v_initial_net:=CASE WHEN v_cas.finale THEN 80 ELSE 160 END;
  v_statut:=CASE WHEN v_cas.finale THEN 'TERMINEE'::public.statut_mission ELSE 'EN_COURS'::public.statut_mission END;
  v_annule:=false;
  v_remplacement:=NULL;
  v_commission:=NULL;
  v_commission_remplacement:=NULL;
  BEGIN
    -- INSERT SQL Auth seulement : pas de session/token/SMTP/hook Auth HTTP.
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES (v_soignant,'00000000-0000-0000-0000-000000000000','f1-soignant@example.invalid','authenticated','authenticated',
      '{"role":"SOIGNANT","est_compte_test":true,"is_test_playwright":true}',now()),
      (v_etab,'00000000-0000-0000-0000-000000000000','f1-etablissement@example.invalid','authenticated','authenticated',
      '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true,"is_test_playwright":true}',now());
    INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
      source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
      identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
    VALUES(v_soignant,'Fixture','F1','f1-soignant@example.invalid','IDE','LIBERAL','1990-01-01',true,
      'RECETTE_F1_SQL','F1SQLSOIGNANT',false,false,false,false,false,false,false);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
      est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
      peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
    VALUES(v_etab,'Fixture F1','99150000000843','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',
      'f1-etablissement@example.invalid',true,'RECETTE_F1_SQL','F1SQLETABLISSEMENT',false,false,'EN_ATTENTE',false,false,false,15);
    UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
      WHERE utilisateur_id IN(v_soignant,v_etab);
    IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab)
      AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
    THEN RAISE EXCEPTION 'F1 : canaux de fixture non fermés'; END IF;

    -- Voie maintenance déjà autorisée par trg_verrouiller_etat_initial_mission.
    -- Pas d'override anti-seed, de trigger désactivé ni de qualification créée.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
    VALUES(v_mission,v_etab,'RECETTE F1 SQL annulee','IDE',v_jour_futur+time '09:00',v_jour_futur+time '13:00',
      4,20,v_statut,v_soignant,'LIBERAL','LIBERAL','LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
    IF (SELECT count(*) FROM public.mission_creneaux WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL')<>1
      OR (SELECT fige_le FROM public.missions WHERE id=v_mission) IS NOT NULL
    THEN RAISE EXCEPTION 'F1 : planning legacy/état initial inattendu'; END IF;
    UPDATE public.mission_creneaux SET debut=v_jour_passe+time '09:00',fin=v_jour_passe+time '13:00'
      WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL';
    IF NOT v_cas.finale THEN
      INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
      VALUES(v_mission,v_jour_futur+time '09:00',v_jour_futur+time '13:00','PREVISIONNEL',false,2);
    END IF;
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
    VALUES(v_mission,v_jour_passe+time '09:00',v_jour_passe+time '13:00','EFFECTIF',false,3);
    -- L'état historique final est posé par maintenance dans cette transaction,
    -- jamais par un faux paiement ni une clôture utilisateur contournée.
    IF v_cas.finale AND NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission
      AND statut='TERMINEE' AND fin_le<now() AND duree_heures=4)
    THEN RAISE EXCEPTION 'F1 : historique final non passé'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut=v_statut
      AND nb_creneaux=CASE WHEN v_cas.finale THEN 1 ELSE 2 END AND duree_heures=v_duree_mission
      AND duree_heures_effective=4 AND total_brut=v_initial_net AND net_a_payer=v_initial_net
      AND montant_ifm=0 AND montant_icp=0 AND montant_commission_ht=v_initial_net*0.15
      AND montant_commission_tva=v_initial_net*0.03 AND montant_commission_ttc=v_initial_net*0.18 AND fige_le IS NULL)
    THEN RAISE EXCEPTION 'F1 : snapshot initial incohérent, cas %',v_cas.nom; END IF;
    v_resultat:=public.fn_verifier_pre_facturation(v_mission,v_semaine,v_semaine+6);
    IF v_resultat->'ok' IS DISTINCT FROM 'true'::jsonb OR v_resultat->>'source_facturation'<>'EFFECTIF'
      OR (v_resultat->>'duree_facturee')::numeric IS DISTINCT FROM 4
    THEN RAISE EXCEPTION 'F1 : préfacturation semaine fermée incorrecte'; END IF;
    v_resultat:=public.fn_calculer_montant_periode(v_mission,v_semaine,v_semaine+6);
    IF (v_resultat->>'duree_totale_mission_heures')::numeric IS DISTINCT FROM v_duree_mission
      OR (v_resultat->>'duree_periode_heures')::numeric IS DISTINCT FROM 4
      OR (v_resultat->>'ratio_periode')::numeric IS DISTINCT FROM (CASE WHEN v_cas.finale THEN 1::numeric ELSE 0.5::numeric END)
      OR (v_resultat->>'montant_ht_periode')::numeric IS DISTINCT FROM 80
    THEN RAISE EXCEPTION 'F1 : prorata hebdomadaire indépendant incorrect'; END IF;

    BEGIN
      UPDATE public.mission_creneaux SET fin=NULL WHERE mission_id=v_mission AND type_creneau='EFFECTIF';
      PERFORM public.fn_verifier_pre_facturation(v_mission,v_semaine,v_semaine+6);
      RAISE EXCEPTION 'F1 : pointage ouvert accepté';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM NOT LIKE 'Facturation bloquée : % créneau(x) effectif(s) ouvert(s)%' THEN RAISE; END IF;
    END;
    BEGIN
      INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
        montant_ht,montant_ttc,periode_debut,periode_fin,est_facture_finale_mission)
      VALUES(v_doublon,'F1-ANTI-SEED',v_soignant,v_etab,v_mission,81,81,v_semaine,v_semaine+6,false);
      RAISE EXCEPTION 'F1 : montant inventé accepté';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM NOT LIKE 'anti-seed facture: montant_ht %' THEN RAISE; END IF;
    END;

    v_numero:=public.next_invoice_number(v_soignant);
    INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
      montant_ht,montant_ttc,montant_tva,taux_tva,periode_debut,periode_fin,statut,
      type_document,nature_correction,mode_remboursement,est_facture_finale_mission)
    VALUES(v_honoraire,v_numero,v_soignant,v_etab,v_mission,80,80,0,0,v_semaine,v_semaine+6,'BROUILLON',
      'FACTURE','ORIGINALE','N_A',v_cas.finale);
    BEGIN
      INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
        montant_ht,montant_ttc,periode_debut,periode_fin,est_facture_finale_mission)
      VALUES(v_doublon,public.next_invoice_number(v_soignant),v_soignant,v_etab,v_mission,80,80,v_semaine,v_semaine+6,false);
      RAISE EXCEPTION 'F1 : chevauchement de période accepté';
    EXCEPTION WHEN exclusion_violation THEN
      IF SQLERRM<>'Une facture active couvre déjà tout ou partie de cette période pour cette mission.' THEN RAISE; END IF;
    END;
    -- Vrai contrôle interne service_role, sans accorder de droit à un utilisateur.
    PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
    BEGIN
      PERFORM public.fn_emettre_document_facturation_honoraires(v_honoraire,'fixture-f1.pdf','fixture-f1.xml');
      RAISE EXCEPTION 'F1 : émission non-service acceptée';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
      PERFORM public.fn_preparer_facture_commission_periode(v_honoraire);
      RAISE EXCEPTION 'F1 : commission non-service acceptée';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    BEGIN
      PERFORM public.fn_emettre_document_facturation_honoraires(v_honoraire,'fixture-f1.pdf','');
      RAISE EXCEPTION 'F1 : émission sans référence XML acceptée';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'Les deux versions PDF et XML CII sont requises avant émission.' THEN RAISE; END IF;
    END;
    SELECT to_jsonb(m) INTO v_snapshot FROM public.missions m WHERE id=v_mission;
    -- Références fictives seulement : aucun octet PDF/XML n'existe dans ce test.
    v_resultat:=public.fn_emettre_document_facturation_honoraires(v_honoraire,'fixture-f1.pdf','fixture-f1.xml');
    IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
      OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_honoraire AND statut='EMISE'
        AND pdf_s3_key='fixture-f1.pdf' AND facturx_xml_url='fixture-f1.xml'
        AND emise_le=notifiee_soignant_le AND verification_echeance_le>emise_le AND NOT is_public_sector)
    THEN RAISE EXCEPTION 'F1 : émission non confirmée'; END IF;
    -- Pour la finale, ce helper lie la commission à la mission. Son UPDATE
    -- normalise aussi taux_rist_plafonne de NULL vers20, sans plafond appliqué
    -- (dec_appliquer_plafond_rist) : cette mutation est vérifiée séparément.
    v_resultat:=public.fn_preparer_facture_commission_periode(v_honoraire);
    v_commission:=(v_resultat->>'facture_id')::uuid;
    v_rejeu:=public.fn_preparer_facture_commission_periode(v_honoraire);
    IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb OR v_resultat->'existing' IS DISTINCT FROM 'false'::jsonb
      OR v_rejeu->'existing' IS DISTINCT FROM 'true'::jsonb OR v_rejeu->>'facture_id' IS DISTINCT FROM v_commission::text
      OR (SELECT count(*) FROM public.factures WHERE facture_honoraire_id=v_honoraire)<>1
      OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission AND montant_ht=12 AND montant_tva=2.4
        AND montant_ttc=14.4 AND statut='EMISE' AND NOT est_secteur_public AND chorus_pro_statut='NON_APPLICABLE')
      OR (NOT v_cas.finale AND v_snapshot IS DISTINCT FROM (SELECT to_jsonb(m) FROM public.missions m WHERE id=v_mission))
      OR (v_cas.finale AND (v_snapshot-'commission_facturee'-'facture_id'-'modifie_le'-'taux_rist_plafonne' IS DISTINCT FROM
        (SELECT to_jsonb(m)-'commission_facturee'-'facture_id'-'modifie_le'-'taux_rist_plafonne' FROM public.missions m WHERE id=v_mission)
        OR v_snapshot->'taux_rist_plafonne' IS DISTINCT FROM 'null'::jsonb
        OR NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND commission_facturee
          AND facture_id=v_commission AND taux_rist_plafonne=20 AND rist_plafond_applique=false)))
    THEN RAISE EXCEPTION 'F1 : commission initiale/idempotence incorrecte ; cas=% ; resultat=% ; rejeu=% ; montants=% ; champs_mission=%',
      v_cas.nom,v_resultat,v_rejeu,
      (SELECT jsonb_build_object('ht',montant_ht,'tva',montant_tva,'ttc',montant_ttc,'statut',statut)
        FROM public.factures WHERE id=v_commission),
      (SELECT jsonb_agg(a.key ORDER BY a.key) FROM jsonb_each(v_snapshot) a
        WHERE a.value IS DISTINCT FROM (SELECT to_jsonb(m)->a.key FROM public.missions m WHERE id=v_mission));
    END IF;
    BEGIN
      PERFORM public.fn_emettre_document_facturation_honoraires(v_honoraire,'fixture-f1.pdf','fixture-f1.xml');
      RAISE EXCEPTION 'F1 : double émission acceptée';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM NOT LIKE 'Le document % est déjà émis ou n’est plus émissible.' THEN RAISE; END IF;
    END;
    v_resultat:=public.fn_cumul_factures_mission(v_mission,v_semaine+6);
    IF (v_resultat->>'nb_factures')::integer IS DISTINCT FROM 1
      OR (v_resultat->>'cumul_ht')::numeric IS DISTINCT FROM 80 OR (v_resultat->>'cumul_ttc')::numeric IS DISTINCT FROM 80
      OR (SELECT count(*) FROM public.notifications WHERE id_ressource=v_honoraire)<>2
      OR (SELECT count(*) FROM public.notifications WHERE id_ressource=v_honoraire AND type='FACTURE_EMISE'
        AND destinataire_id IN(v_soignant,v_etab) AND NOT coalesce(email_envoye,false) AND NOT coalesce(push_envoyee,false))<>2
      OR (SELECT array_agg(action ORDER BY action) FROM public.invoice_audit_log WHERE invoice_id=v_honoraire)
        IS DISTINCT FROM ARRAY['CREATED','EMISSION_ET_REMISE_COPIE','STATUS_CHANGE:BROUILLON->EMISE']::text[]
    THEN RAISE EXCEPTION 'F1 : cumul/notifications/audits non exacts'; END IF;
    IF EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(v_soignant,v_etab))
      OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE avoir_id IN(v_honoraire,v_doublon))
      OR EXISTS(SELECT 1 FROM public.cessions_creance WHERE facture_honoraire_id=v_honoraire)
      OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=v_mission)
      OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id IN(v_soignant,v_etab) AND id_ressource IS DISTINCT FROM v_honoraire)
      OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource IN(v_mission,v_honoraire) AND action='OVERRIDE_ANTI_SEED')
    THEN RAISE EXCEPTION 'F1 : effet externe/override inattendu'; END IF;
    IF v_cas.heures_ajustees IS NOT NULL THEN
      -- Historique SQL synthétique sans arrivée/départ/GPS, sans validation
      -- établissement : ne déclenche ni conformité de pointage ni escrow.
      INSERT INTO public.presences(id,mission_id,soignant_id,heures_reelles)
      VALUES(v_presence,v_mission,v_soignant,4);
    END IF;
    -- Troisième identité de recette SQL uniquement : aucun mot de passe/token.
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES(v_admin,'00000000-0000-0000-0000-000000000000','f1-rectif-admin@example.invalid',
      'authenticated','authenticated','{"role":"ADMIN_PLATEFORME","est_compte_test":true,"is_test_playwright":true}',now());
    INSERT INTO public.equipe_admin(id,user_id,nom,prenom,email,poste,actif,acces_groupes)
    VALUES(v_equipe,v_admin,'SYNTHETIQUE','F1','f1-rectif-admin@example.invalid','RECETTE SQL ANNULEE',true,
      ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
    PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated','aal','aal2')::text,true);
    IF public.est_admin() IS NOT TRUE THEN RAISE EXCEPTION 'F1 rectification : administrateur synthétique non reconnu'; END IF;
    INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,
      statut,type_litige,facture_id,gel_facture_scope,periode_debut,periode_fin)
    VALUES(v_litige,v_mission,v_soignant,v_etab,'SOIGNANT','RECETTE SYNTHETIQUE ANNULEE : taux erroné sur première période',
      'OUVERT','DESACCORD_MONTANT_FACTURE',v_honoraire,'FACTURE_UNIQUE',v_semaine,v_semaine+6);
    v_resultat:=public.fn_admin_resoudre_litige_intelligent(v_litige,
      'RECETTE SYNTHETIQUE ANNULEE : correction canonique du taux',
      'ETABLISSEMENT',v_cas.heures_ajustees,v_cas.taux_ajuste,'ANNULER_REEMETTRE');
    v_remplacement:=NULLIF(v_resultat->>'nouvelle_facture_id','')::uuid;
    IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb OR v_remplacement IS NULL
      OR v_resultat->>'action_financiere' IS DISTINCT FROM 'ANNULER_REEMETTRE'
      OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_honoraire AND statut='REMPLACEE' AND montant_ht=80)
      OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_remplacement AND statut='BROUILLON'
        AND nature_correction='REMPLACEMENT' AND type_document='FACTURE' AND facture_precedente_id=v_honoraire
        AND montant_ht=v_cas.honoraires AND montant_tva=0 AND montant_ttc=v_cas.honoraires
        AND quantite_heures_snapshot=COALESCE(v_cas.heures_ajustees,4) AND taux_horaire_snapshot=v_cas.taux
        AND periode_debut=v_semaine AND periode_fin=v_semaine+6)
    THEN RAISE EXCEPTION 'F1 rectification canonique incorrecte : %',v_resultat; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut=v_statut
      AND duree_heures=v_duree_mission AND taux_horaire_base=v_cas.taux AND total_brut=v_cas.net_global AND net_a_payer=v_cas.net_global
      AND montant_commission_ht=v_cas.avant_ht AND montant_commission_tva=v_cas.avant_tva
      AND montant_commission_ttc=v_cas.avant_ttc)
    THEN RAISE EXCEPTION 'F1 rectification : mission incohérente AVANT commission remplacement'; END IF;
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    PERFORM public.fn_emettre_document_facturation_honoraires(v_remplacement,'fixture-f1-remplacement.pdf','fixture-f1-remplacement.xml');
    -- Les agrégats canoniques existent déjà avant le helper documentaire.
    SELECT jsonb_build_array(total_brut,net_a_payer,montant_commission_ht,montant_commission_tva,montant_commission_ttc)
      INTO v_financier_avant FROM public.missions WHERE id=v_mission;
    PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
    BEGIN
      PERFORM public.fn_preparer_commission_remplacement_honoraires(v_remplacement);
      RAISE EXCEPTION 'F1 rectification : remplacement non-service accepté';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    v_resultat:=public.fn_preparer_commission_remplacement_honoraires(v_remplacement);
    v_commission_remplacement:=(v_resultat->>'facture_id')::uuid;
    IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission AND statut='REMPLACEE')
      OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission_remplacement AND statut='EMISE'
        AND facture_precedente_id=v_commission AND facture_honoraire_id=v_remplacement
        AND montant_ht=v_cas.commission_ht AND montant_tva=v_cas.commission_tva AND montant_ttc=v_cas.commission_ttc)
    THEN RAISE EXCEPTION 'F1 rectification : paire de commissions incorrecte'; END IF;
    SELECT net_a_payer,montant_commission_ht INTO v_net_global,v_commission_globale
      FROM public.missions WHERE id=v_mission;
    -- Le cas rouge initial reste 8 h × 18 = 144, commission de 15 % = 21,60.
    -- Le cas symétrique est 8 h × 22 = 176, commission de 15 % = 26,40.
    IF v_net_global IS DISTINCT FROM v_cas.net_global OR v_commission_globale IS DISTINCT FROM v_cas.globale_ht THEN
      RAISE EXCEPTION 'F1_RECTIF_GLOBAL_COMMISSION_INCOHERENTE net attendu=% obtenu=% ; commission HT attendue=% obtenue=%',
        v_cas.net_global,v_net_global,v_cas.globale_ht,v_commission_globale;
    END IF;
    IF ((v_cas.heures_ajustees IS NULL OR v_cas.heures_ajustees=4) AND v_financier_avant IS DISTINCT FROM (SELECT jsonb_build_array(total_brut,net_a_payer,
      montant_commission_ht,montant_commission_tva,montant_commission_ttc) FROM public.missions WHERE id=v_mission))
      OR (SELECT jsonb_build_array(total_brut,net_a_payer,montant_commission_ht,montant_commission_tva,montant_commission_ttc)
        FROM public.missions WHERE id=v_mission) IS DISTINCT FROM jsonb_build_array(v_cas.net_global,v_cas.net_global,
          v_cas.globale_ht,v_cas.globale_tva,v_cas.globale_ttc)
      OR (SELECT commission_a_recalculer FROM public.missions WHERE id=v_mission) IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'F1 rectification : agrégats inattendus, cas %',v_cas.nom; END IF;
    SELECT to_jsonb(m) INTO v_mission_apres FROM public.missions m WHERE id=v_mission;
    -- Idempotence SQL seulement ; aucun replay de l'Edge qui crée une version.
    v_rejeu:=public.fn_preparer_commission_remplacement_honoraires(v_remplacement);
    IF v_rejeu->'existing' IS DISTINCT FROM 'true'::jsonb OR v_rejeu->>'facture_id' IS DISTINCT FROM v_commission_remplacement::text
      OR (SELECT count(*) FROM public.factures WHERE facture_honoraire_id=v_remplacement)<>1
      OR v_mission_apres IS DISTINCT FROM (SELECT to_jsonb(m) FROM public.missions m WHERE id=v_mission)
    THEN RAISE EXCEPTION 'F1 rectification : réparation non idempotente'; END IF;
    RAISE EXCEPTION USING ERRCODE='JF101',MESSAGE='F1_ANNULATION_ATTENDUE';
  EXCEPTION WHEN SQLSTATE 'JF101' THEN
    IF SQLERRM<>'F1_ANNULATION_ATTENDUE' THEN RAISE; END IF;
    v_annule:=true;
  END;
  IF NOT v_annule OR EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab,v_admin))
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=v_equipe)
    OR EXISTS(SELECT 1 FROM public.litiges WHERE id=v_litige)
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=v_presence OR mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab)
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission)
    OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id IN(v_honoraire,v_doublon,v_remplacement))
    OR EXISTS(SELECT 1 FROM public.factures WHERE id IN(v_commission,v_commission_remplacement) OR facture_honoraire_id IN(v_honoraire,v_remplacement))
    OR EXISTS(SELECT 1 FROM public.invoice_audit_log WHERE invoice_id IN(v_honoraire,v_remplacement))
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource IN(v_litige,v_remplacement,v_commission_remplacement) OR acteur_id=v_admin)
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.conformite_travail WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=v_soignant)
  THEN RAISE EXCEPTION 'F1 : annulation transactionnelle non prouvée'; END IF;
  END LOOP;
END $f1$;
SELECT 'F1_RECTIFICATION_SQL_ROLLBACK' AS preuve,true AS annule,5 AS scenarios;
ROLLBACK;
