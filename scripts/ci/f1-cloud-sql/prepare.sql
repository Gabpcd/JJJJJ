-- CANDIDAT NON EXECUTE, a assembler dans BEGIN/COMMIT par un adapter revu.
-- Exiger avant ce corps le preflight de catalogue, canaux et manifeste.
-- Parametre JSON transactionnel : jolene.recette_f1_manifest.
-- Auth est cree auparavant par API Admin, sans invitation/email ni session admin.
-- Historique synthetique de maintenance : aucune preuve d'attribution/qualification.
SET LOCAL TIME ZONE 'UTC';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $fixture$
DECLARE
  v jsonb := current_setting('jolene.recette_f1_manifest')::jsonb;
  s uuid := (v#>>'{actors,soignant,id}')::uuid;
  e uuid := (v#>>'{actors,etablissement,id}')::uuid;
  a uuid := (v#>>'{sqlActors,admin,id}')::uuid;
  m uuid := (v#>>'{ids,mission}')::uuid;
  team uuid := (v#>>'{ids,equipeAdmin}')::uuid;
  presence uuid := (v#>>'{ids,presence}')::uuid;
  semaine date := date_trunc('week',current_date)::date-7;
  passe date;
  futur date;
  mandat text;
  r jsonb;
  n text;
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
    OR v->>'projectRef' IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
    OR v->>'schemaVersion' IS DISTINCT FROM '1'
    OR v->>'runId' !~ '^f1-[a-z0-9-]{8,80}$'
    OR v->>'sourceSha' !~ '^[a-f0-9]{40}$'
    OR v->>'ownerMarker' IS DISTINCT FROM (v->>'runId')||':'||(v->>'sourceSha')
    OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'F1 contexte/manifeste invalide'; END IF;
  FOREACH n IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.tva_mission_managed','app.internal_operation'] LOOP
    IF NULLIF(current_setting(n,true),'') IS NOT NULL THEN RAISE EXCEPTION 'F1 override present'; END IF;
  END LOOP;
  IF cardinality(ARRAY[s,e,a,m,team,presence])<>6 OR (SELECT count(DISTINCT x) FROM unnest(ARRAY[s,e,a,m,team,presence]) x)<>6
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=s)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=e OR siret=v#>>'{identifiants,siretEtablissement}')
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team OR user_id=a)
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=m)
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=presence OR mission_id=m)
  THEN RAISE EXCEPTION 'F1 collision ou identifiant absent'; END IF;
  IF (SELECT count(*) FROM auth.users u WHERE u.id IN(s,e,a)
    AND u.raw_app_meta_data->>'jolene_f1_owner'=v->>'ownerMarker'
    AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
    AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=now())
    AND u.email = CASE u.id WHEN s THEN v#>>'{actors,soignant,email}' WHEN e THEN v#>>'{actors,etablissement,email}' ELSE v#>>'{sqlActors,admin,email}' END
    AND u.email LIKE '%@example.invalid'
    AND u.raw_app_meta_data->>'role'=CASE u.id WHEN s THEN 'SOIGNANT' WHEN e THEN 'ADMIN_ETABLISSEMENT' ELSE 'ADMIN_PLATEFORME' END)<>3
  THEN RAISE EXCEPTION 'F1 filiation Auth incorrecte'; END IF;
  SELECT d::date INTO passe FROM generate_series(semaine,semaine+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO futur FROM generate_series(semaine+14,semaine+18,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF passe IS NULL OR futur IS NULL OR semaine+6>=current_date THEN RAISE EXCEPTION 'F1 calendrier invalide'; END IF;
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
    source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
    identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides,
    siret_liberal,adresse_rue,adresse_code_postal,adresse_ville)
  VALUES(s,'Łukasz İpek','TEST García & d’Élodie',v#>>'{actors,soignant,email}','IDE','LIBERAL','1990-01-01',true,
    'RECETTE_F1_CLOUD_SYNTHETIQUE',upper(replace(s::text,'-','')),false,false,false,false,false,false,false,
    v#>>'{identifiants,siretSoignant}','Adresse SYNTHETIQUE sans personne réelle','75001','Paris TEST');
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
    est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
    peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
  VALUES(e,'TEST Clinique Łódź & d’Élodie',v#>>'{identifiants,siretEtablissement}','CLINIQUE_PRIVEE',
    'Adresse SYNTHETIQUE sans établissement réel','Paris TEST','75001',v#>>'{actors,etablissement,email}',
    true,'RECETTE_F1_CLOUD_SYNTHETIQUE',upper(replace(e::text,'-','')),false,false,'EN_ATTENTE',false,false,false,15);
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id IN(s,e);
  IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(s,e)
    AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
  THEN RAISE EXCEPTION 'F1 canaux non fermes'; END IF;
  -- Le vrai RPC serveur conserve une attestation explicitement fictive, pas le texte d'un mandat utilisateur.
  mandat := repeat('RECETTE SYNTHETIQUE F1 — AUCUNE PORTEE JURIDIQUE — NON SIGNE PAR UNE PERSONNE REELLE — ',16)
    || (v->>'ownerMarker');
  r:=public.fn_signer_mandat_facturation_serveur(s,'1.4',NULL,'RECETTE_SYNTHETIQUE',
    'recette-f1-synthetique',encode(extensions.digest(convert_to(mandat,'UTF8'),'sha256'),'hex'),mandat,'FRANCHISE_EN_BASE');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'F1 mandat fixture refuse: %',r; END IF;
  -- L'application du régime après INSERT laisse le trigger TVA initier A_REVOIR.
  -- Le régime financier initial reste libéral (recherche/choix/note d'honoraires).
  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
    duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
    choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
  VALUES(m,e,'RECETTE F1 SYNTHETIQUE '||(v->>'runId'),'IDE',futur+time '09:00',futur+time '13:00',
    4,20,'EN_COURS',s,'LIBERAL',NULL,'LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
  UPDATE public.missions SET type_contrat_applique='LIBERAL' WHERE id=m;
  UPDATE public.mission_creneaux SET debut=passe+time '09:00',fin=passe+time '13:00'
    WHERE mission_id=m AND type_creneau='PREVISIONNEL';
  INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
  VALUES(m,futur+time '09:00',futur+time '13:00','PREVISIONNEL',false,2),
    (m,passe+time '09:00',passe+time '13:00','EFFECTIF',false,3);
  INSERT INTO public.equipe_admin(id,user_id,nom,prenom,email,poste,actif,acces_groupes)
  VALUES(team,a,'SYNTHETIQUE','F1',v#>>'{sqlActors,admin,email}','RECETTE F1 SANS SESSION',true,
    ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','aal','aal2')::text,true);
  r:=public.fn_admin_proposer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE','RECETTE SYNTHETIQUE sans prestation ni attestation réelle');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'F1 revue TVA refusee: %',r; END IF;
  PERFORM set_config('request.jwt.claim.sub',s::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'role','authenticated')::text,true);
  r:=public.fn_confirmer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva'<>'CONFIRMEE' THEN RAISE EXCEPTION 'F1 confirmation TVA refusee'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.equipe_admin SET actif=false WHERE id=team AND user_id=a;
  IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=m AND statut='EN_COURS' AND nb_creneaux=2
    AND duree_heures=8 AND duree_heures_effective=4 AND net_a_payer=160 AND montant_commission_ht=24
    AND statut_validation_tva='CONFIRMEE' AND fige_le IS NULL)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e))
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE user_id=a AND actif)
  THEN RAISE EXCEPTION 'F1 seed ou effets inattendus'; END IF;
  r:=public.fn_calculer_montant_periode(m,semaine,semaine+6);
  IF (r->>'montant_ht_periode')::numeric IS DISTINCT FROM 80 THEN RAISE EXCEPTION 'F1 prorata inattendu'; END IF;
  PERFORM set_config('jolene.recette_f1_receipt',jsonb_build_object('runId',v->>'runId','missionId',m,
    'periodeDebut',semaine,'periodeFin',semaine+6,'montantOriginal',80,'montantRemplacement',72,
    'presenceIdReserve',presence,'qualificationVerifiee',false,'signatureSynthetique',true,'mfaProuve',false)::text,true);
END $fixture$;
SELECT current_setting('jolene.recette_f1_receipt')::jsonb AS receipt;
