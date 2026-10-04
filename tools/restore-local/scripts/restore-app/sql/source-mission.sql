-- Préparation synthétique uniquement ; aucune facture ni statut financier forcé.
-- Dérivé du seed F1 : aucun lancement du pilote F1 ni modification de ses verrous.
-- Le troisième acteur est un admin synthétique désactivé dans cette transaction.
-- Exiger avant ce corps le preflight de catalogue, canaux et manifeste.
-- Parametre JSON transactionnel : jolene.connect_test_fixture_manifest.
-- Auth est cree auparavant par API Admin, sans invitation/email ni session admin.
-- Historique synthetique de maintenance : aucune preuve d'attribution/qualification.
SET LOCAL TIME ZONE 'UTC';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $fixture$
DECLARE
  v jsonb := current_setting('jolene.connect_test_fixture_manifest')::jsonb;
  s uuid := (v#>>'{actors,soignant,id}')::uuid;
  e uuid := (v#>>'{actors,etablissement,id}')::uuid;
  a uuid := (v#>>'{sqlActors,admin,id}')::uuid;
  m uuid := (v#>>'{ids,mission}')::uuid;
  team uuid := (v#>>'{ids,equipeAdmin}')::uuid;
  presence uuid := (v#>>'{ids,presence}')::uuid;
  semaine date;
  passe date;
  futur date;
  mandat text;
  r jsonb;
  n text;
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
    OR v->>'projectRef' IS DISTINCT FROM 'LOCAL_PG17_RESTORE_APP'
    OR current_database()<>'jolene_candidatures_pg17_test' OR inet_server_addr() IS NOT NULL
    OR current_setting('cron.launch_active_jobs')<>'off' OR current_setting('max_worker_processes')<>'0'
    OR v->>'schemaVersion' IS DISTINCT FROM '1'
    OR v->>'runId' !~ '^connect-test-[a-z0-9-]{8,64}$'
    OR v->>'sourceSha' !~ '^[a-f0-9]{40}$'
    OR v->>'ownerMarker' IS DISTINCT FROM (v->>'runId')||':'||(v->>'sourceSha')
    OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'CONNECT TEST contexte/manifeste invalide'; END IF;
  FOREACH n IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.tva_mission_managed','app.internal_operation'] LOOP
    IF NULLIF(current_setting(n,true),'') IS NOT NULL THEN RAISE EXCEPTION 'CONNECT TEST override present'; END IF;
  END LOOP;
  IF cardinality(ARRAY[s,e,a,m,team,presence])<>6 OR (SELECT count(DISTINCT x) FROM unnest(ARRAY[s,e,a,m,team,presence]) x)<>6
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=s)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=e OR siret=v#>>'{identifiants,siretEtablissement}')
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team OR user_id=a)
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=m)
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=presence OR mission_id=m)
  THEN RAISE EXCEPTION 'CONNECT TEST collision ou identifiant absent'; END IF;
  IF (SELECT count(*) FROM auth.users u WHERE u.id IN(s,e,a)
    AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=v->>'ownerMarker'
    AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
    AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=now())
    AND u.email = CASE u.id WHEN s THEN v#>>'{actors,soignant,email}' WHEN e THEN v#>>'{actors,etablissement,email}' ELSE v#>>'{sqlActors,admin,email}' END
    AND u.email LIKE '%@example.invalid'
    AND u.raw_app_meta_data->>'role'=CASE u.id WHEN s THEN 'SOIGNANT' WHEN e THEN 'ADMIN_ETABLISSEMENT' ELSE 'ADMIN_PLATEFORME' END)<>3
  THEN RAISE EXCEPTION 'CONNECT TEST filiation Auth incorrecte'; END IF;
  -- Une semaine dont le lundi est ouvré garde periodeDebut dans la mission.
  -- Un lundi férié ne doit pas décaler le premier créneau après cette borne.
  SELECT d::date INTO semaine FROM generate_series(date_trunc('week',current_date)::date-7,
    date_trunc('week',current_date)::date-35,interval '-7 days') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d DESC LIMIT 1;
  passe := semaine;
  -- Reste futur même si la semaine facturable a reculé à cause d'un jour férié.
  SELECT d::date INTO futur FROM generate_series(date_trunc('week',current_date)::date+7,
    date_trunc('week',current_date)::date+11,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF passe IS NULL OR futur IS NULL OR semaine+6>=current_date THEN RAISE EXCEPTION 'CONNECT TEST calendrier invalide'; END IF;
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
    source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
    identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides,
    siret_liberal,adresse_rue,adresse_code_postal,adresse_ville)
  VALUES(s,'Connect','TEST Synthétique',v#>>'{actors,soignant,email}','IDE','LIBERAL','1990-01-01',true,
    'RECETTE_CONNECT_TEST_SYNTHETIQUE',upper(replace(s::text,'-','')),false,false,false,false,false,false,false,
    v#>>'{identifiants,siretSoignant}','Adresse SYNTHETIQUE sans personne réelle','75001','Paris TEST');
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
    est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
    peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
  VALUES(e,'TEST Clinique Connect Synthétique',v#>>'{identifiants,siretEtablissement}','CLINIQUE_PRIVEE',
    'Adresse SYNTHETIQUE sans établissement réel','Paris TEST','75001',v#>>'{actors,etablissement,email}',
    true,'RECETTE_CONNECT_TEST_SYNTHETIQUE',upper(replace(e::text,'-','')),false,false,'EN_ATTENTE',false,false,false,15);
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id IN(s,e);
  IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(s,e)
    AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
  THEN RAISE EXCEPTION 'CONNECT TEST canaux non fermes'; END IF;
  -- Le vrai RPC serveur conserve une attestation explicitement fictive, pas le texte d'un mandat utilisateur.
  mandat := repeat('RECETTE SYNTHETIQUE CONNECT TEST — AUCUNE PORTEE JURIDIQUE — NON SIGNE PAR UNE PERSONNE REELLE — ',16)
    || (v->>'ownerMarker');
  r:=public.fn_signer_mandat_facturation_serveur(s,'1.4',NULL,'RECETTE_SYNTHETIQUE',
    'recette-connect-test-synthetique',encode(extensions.digest(convert_to(mandat,'UTF8'),'sha256'),'hex'),mandat,'FRANCHISE_EN_BASE');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CONNECT TEST mandat fixture refuse: %',r; END IF;
  -- L'application du régime après INSERT laisse le trigger TVA initier A_REVOIR.
  -- Le régime financier initial reste libéral (recherche/choix/note d'honoraires).
  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
    duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
    choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
  VALUES(m,e,'RECETTE CONNECT TEST SYNTHETIQUE '||(v->>'runId'),'IDE',futur+time '09:00',futur+time '13:00',
    4,20,'EN_COURS',s,'LIBERAL',NULL,'LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
  UPDATE public.missions SET type_contrat_applique='LIBERAL' WHERE id=m;
  UPDATE public.mission_creneaux SET debut=passe+time '09:00',fin=passe+time '13:00'
    WHERE mission_id=m AND type_creneau='PREVISIONNEL';
  INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
  VALUES(m,futur+time '09:00',futur+time '13:00','PREVISIONNEL',false,2),
    (m,passe+time '09:00',passe+time '13:00','EFFECTIF',false,3);
  INSERT INTO public.equipe_admin(id,user_id,nom,prenom,email,poste,actif,acces_groupes)
  VALUES(team,a,'SYNTHETIQUE','CONNECT TEST',v#>>'{sqlActors,admin,email}','RECETTE CONNECT TEST SANS SESSION',true,
    ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','aal','aal2')::text,true);
  r:=public.fn_admin_proposer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE','RECETTE SYNTHETIQUE sans prestation ni attestation réelle');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CONNECT TEST revue TVA refusee: %',r; END IF;
  PERFORM set_config('request.jwt.claim.sub',s::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'role','authenticated')::text,true);
  r:=public.fn_confirmer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva'<>'CONFIRMEE' THEN RAISE EXCEPTION 'CONNECT TEST confirmation TVA refusee'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.equipe_admin SET actif=false WHERE id=team AND user_id=a;
  IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=m AND statut='EN_COURS' AND nb_creneaux=2
    AND duree_heures=8 AND duree_heures_effective=4 AND net_a_payer=160 AND montant_commission_ht=24
    AND statut_validation_tva='CONFIRMEE' AND fige_le IS NULL
    AND debut_le::date=semaine AND fin_le::date=futur AND semaine+6<fin_le::date)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e))
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE user_id=a AND actif)
  THEN RAISE EXCEPTION 'CONNECT TEST seed ou effets inattendus'; END IF;
  r:=public.fn_calculer_montant_periode(m,semaine,semaine+6);
  IF (r->>'montant_ht_periode')::numeric IS DISTINCT FROM 80 THEN RAISE EXCEPTION 'CONNECT TEST prorata inattendu'; END IF;
  PERFORM set_config('jolene.connect_test_fixture_receipt',jsonb_build_object('runId',v->>'runId','missionId',m,
    'periodeDebut',semaine,'periodeFin',semaine+6,'montantOriginal',80,'commissionTtc',14.4,
    'presenceIdReserve',presence,'qualificationVerifiee',false,'signatureSynthetique',true,'mfaProuve',false)::text,true);
END $fixture$;
SELECT current_setting('jolene.connect_test_fixture_receipt')::jsonb AS receipt;
