-- ═══════════════════════════════════════════════════════════════════════════
-- Régression B3 (lot 3 app iOS native, B9) : fn_contester_paiement_soignant
-- exécutable et idempotente.
--
-- ⚠️  JAMAIS EN PROD. Staging CI exclusivement : job « sql-transaction » de
--     validate-pr.yml, après la migration candidate, sous SAVEPOINT puis
--     ROLLBACK global. Le préflight refuse toute base où un cron est actif.
--     Vraies routines et vrais triggers ; profils fictifs TEST ; aucun appel
--     GoTrue, Stripe ou fournisseur ; zéro persistance.
--
-- Ce qu'il prouve (critère LOT3_PLAN.md §3 B3, option D19 du §7) :
--   - une contestation passe : paiement CONTESTE, un litige, une seule
--     notification établissement, LITIGE_OUVERT, posée par le trigger
--     trg_notifier_creation_litige, et aucune notification
--     CONTESTATION_PAIEMENT (CHECK des notifications laissé intact, non figé ici) ;
--   - un second appel répond {error} sans second litige ni notification ;
--   - refus structurés sans aucune écriture : anon (droit EXECUTE), sans
--     identité, compte suspendu, motif vide/NULL/> 500, paiement inconnu,
--     paiement d'un tiers, statut RESOLU, paiement déjà confirmé, litige
--     ouvert préexistant sur la mission (uq_litige_mission_type_ouvert_legacy) ;
--   - EN_ATTENTE et un motif de 500 caractères sont acceptés.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout='45s';
SET LOCAL lock_timeout='5s';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $b3_contestation$
DECLARE
  v_soignant constant uuid := 'b3c0a001-0000-4000-8000-000000000001';
  v_tiers constant uuid := 'b3c0a001-0000-4000-8000-000000000002';
  v_suspendu constant uuid := 'b3c0a001-0000-4000-8000-000000000003';
  v_etab constant uuid := 'b3c0a001-0000-4000-8000-000000000004';
  v_mission constant uuid := 'b3c0a002-0000-4000-8000-000000000001';
  v_fh constant uuid := 'b3c0a003-0000-4000-8000-000000000001';
  v_inconnu constant uuid := 'b3c0a004-0000-4000-8000-000000000001';
  v_fn constant regprocedure := 'public.fn_contester_paiement_soignant(uuid,text)'::regprocedure;
  -- Empreinte du corps candidat (contrôlée aussi par tests/node/contestation-paiement-soignant.node.mjs).
  v_corps_md5 constant text := '368f41ca6e0157cd48ebbf6a638cecae';
  v_motif constant text := 'Montant reçu inférieur au montant déclaré';
  v_debut date := date_trunc('week',current_date)::date - 7;
  v_passe date;
  v_futur_jour date;
  v_ps uuid;
  v_litige uuid;
  v_avant jsonb;
  v_apres jsonb;
  v_resultat jsonb;
  v_refus boolean;
  v_nom text;
  v_sujet uuid;
  v_appel text;
BEGIN
  -- ── 1. Contexte isolé et catalogue candidat ────────────────────────────────
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
    OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'B3 contestation : maintenance staging isolée requise'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'B3 contestation : trigger INSERT Auth non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.soignants'::regclass,
    'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,
    'public.factures_honoraires'::regclass,'public.paiements_soignant'::regclass,
    'public.litiges'::regclass,'public.notifications'::regclass)
    AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'B3 contestation : trigger métier désactivé'; END IF;
  FOREACH v_nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation'] LOOP
    IF NULLIF(current_setting(v_nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'B3 contestation : contexte de contournement interdit'; END IF;
  END LOOP;
  FOREACH v_nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF COALESCE(current_setting(v_nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'B3 contestation : contexte forcé interdit'; END IF;
  END LOOP;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=v_fn) IS DISTINCT FROM v_corps_md5
    OR (SELECT proconfig FROM pg_proc WHERE oid=v_fn) IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR (SELECT prosecdef FROM pg_proc WHERE oid=v_fn) IS DISTINCT FROM true
    OR (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid=v_fn) IS DISTINCT FROM 'postgres'
    OR has_function_privilege('anon',v_fn,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_fn,'EXECUTE')
    OR NOT has_function_privilege('service_role',v_fn,'EXECUTE')
  THEN RAISE EXCEPTION 'B3 contestation : corps, configuration ou droits candidats inattendus'; END IF;
  IF EXISTS(SELECT 1 FROM private.security_definer_inventory
    WHERE signature IN ('fn_contester_paiement_soignant(uuid,text)','public.fn_contester_paiement_soignant(uuid,text)')
      AND (definition_md5 IS DISTINCT FROM v_corps_md5 OR categorie IS DISTINCT FROM 'MIXTE_TENANT_ADMIN'))
  THEN RAISE EXCEPTION 'B3 contestation : inventaire SECURITY DEFINER désaligné'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id::text LIKE 'b3c0a00%')
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id::text LIKE 'b3c0a00%')
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id::text LIKE 'b3c0a00%' OR siret='99150000003306')
    OR EXISTS(SELECT 1 FROM public.missions WHERE id::text LIKE 'b3c0a00%')
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id::text LIKE 'b3c0a00%')
  THEN RAISE EXCEPTION 'B3 contestation : identifiants de fixture déjà présents'; END IF;
  SELECT d::date INTO v_passe FROM generate_series(v_debut,v_debut+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_futur_jour FROM generate_series(v_debut+14,v_debut+18,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF v_passe IS NULL OR v_futur_jour IS NULL OR v_debut+6>=current_date
  THEN RAISE EXCEPTION 'B3 contestation : calendrier indisponible'; END IF;

  -- ── 2. Fixture : un paiement DECLARE réel (voie maintenance, comme F161) ───
  -- SQL Auth direct uniquement : ni session, ni email, ni hook GoTrue.
  INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at,banned_until)
  SELECT id,'00000000-0000-0000-0000-000000000000'::uuid,id::text||'@example.invalid',
    'authenticated','authenticated',
    jsonb_build_object('role',CASE WHEN id=v_etab THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
      'est_compte_test',true,'is_test_playwright',true),now(),
    CASE WHEN id=v_suspendu THEN now()+interval '1 day' END
  FROM unnest(ARRAY[v_soignant,v_tiers,v_suspendu,v_etab]) id;
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
    source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
    identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
  VALUES(v_soignant,'Recette','Contestation',v_soignant::text||'@example.invalid','IDE','LIBERAL','1990-01-01',true,
    'RECETTE_B3_SQL','B3SQLCONTESTATION',false,false,false,false,false,false,false);
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
    est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
    peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
  VALUES(v_etab,'Recette B3','99150000003306','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',
    'b3-etab@example.invalid',true,'RECETTE_B3_SQL','B3SQLETABLISSEMENT',false,false,'EN_ATTENTE',false,false,false,15);
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id IN(v_soignant,v_etab);
  IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab)
    AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
  THEN RAISE EXCEPTION 'B3 contestation : canaux de fixture non fermés'; END IF;

  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
    duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
    choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
  VALUES(v_mission,v_etab,'Recette B3 contestation annulee','IDE',v_futur_jour+time '09:00',v_futur_jour+time '13:00',
    4,20,'TERMINEE'::public.statut_mission,v_soignant,'LIBERAL','LIBERAL','LIBERAL','NOTE_HONORAIRES','DIRECT','FINALE_UNIQUE',false);
  UPDATE public.mission_creneaux SET debut=v_passe+time '09:00',fin=v_passe+time '13:00'
    WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL';
  INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
  VALUES(v_mission,v_passe+time '09:00',v_passe+time '13:00','EFFECTIF',false,2);
  IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut='TERMINEE'
    AND fin_le<now() AND duree_heures=4 AND duree_heures_effective=4 AND net_a_payer=80)
  THEN RAISE EXCEPTION 'B3 contestation : mission 4h/80 incorrecte'; END IF;
  INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
    montant_ht,montant_ttc,montant_tva,taux_tva,periode_debut,periode_fin,statut,type_document,
    nature_correction,mode_remboursement,est_facture_finale_mission,quantite_heures_snapshot,taux_horaire_snapshot)
  VALUES(v_fh,public.next_invoice_number(v_soignant),v_soignant,v_etab,v_mission,80,80,0,0,v_debut,v_debut+6,
    'BROUILLON','FACTURE','ORIGINALE','N_A',true,4,20);
  PERFORM public.fn_emettre_document_facturation_honoraires(v_fh,'recette-b3.pdf','recette-b3.xml');
  INSERT INTO public.paiements_soignant(mission_id,soignant_id,etablissement_id,facture_honoraire_id,
    montant_net,methode,reference_virement,date_paiement,statut,confirme_par_etablissement,confirme_par_soignant)
  VALUES(v_mission,v_soignant,v_etab,v_fh,80,'VIREMENT','B3-CONTESTATION',current_date,'DECLARE',true,false)
  RETURNING id INTO v_ps;
  IF EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=v_etab
      AND type IN ('LITIGE_OUVERT','CONTESTATION_PAIEMENT'))
  THEN RAISE EXCEPTION 'B3 contestation : fixture déjà en litige'; END IF;
  SELECT to_jsonb(p) INTO v_avant FROM public.paiements_soignant p WHERE id=v_ps;

  -- ── 3. anon : aucun droit EXECUTE ──────────────────────────────────────────
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','anon',true);
  PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
  EXECUTE 'SET LOCAL ROLE anon';
  v_refus:=false;
  BEGIN PERFORM public.fn_contester_paiement_soignant(v_ps,v_motif);
  EXCEPTION WHEN insufficient_privilege THEN v_refus:=true; END;
  EXECUTE 'RESET ROLE';
  IF NOT v_refus THEN RAISE EXCEPTION 'B3 contestation : appel anonyme accepté'; END IF;

  -- ── 4. Refus structurés : aucune écriture ─────────────────────────────────
  -- (sujet, motif, error_code) ; sujet NULL = pas d'identité JWT.
  FOR v_sujet, v_appel, v_nom IN
    SELECT s.sujet, s.motif, s.code FROM (VALUES
      (NULL::uuid, v_motif, 'NON_AUTHENTIFIE'),
      (v_suspendu, v_motif, 'NON_AUTHENTIFIE'),
      (v_soignant, '   ', 'MOTIF_INVALIDE'),
      (v_soignant, NULL::text, 'MOTIF_INVALIDE'),
      (v_soignant, repeat('x',501), 'MOTIF_INVALIDE'),
      (v_tiers, v_motif, 'ACCES_REFUSE')
    ) AS s(sujet, motif, code)
  LOOP
    PERFORM set_config('request.jwt.claim.sub',COALESCE(v_sujet::text,''),true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',
      CASE WHEN v_sujet IS NULL THEN '{"role":"authenticated"}'
        ELSE jsonb_build_object('sub',v_sujet,'role','authenticated')::text END,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_resultat:=public.fn_contester_paiement_soignant(v_ps,v_appel);
    EXECUTE 'RESET ROLE';
    IF v_resultat->>'error_code' IS DISTINCT FROM v_nom OR v_resultat ? 'success'
      OR v_resultat->>'error' IS DISTINCT FROM CASE
        WHEN v_nom='NON_AUTHENTIFIE' THEN 'Non authentifié ou compte inactif'
        WHEN v_nom='ACCES_REFUSE' THEN 'Accès refusé'
        WHEN v_appel IS NULL OR btrim(v_appel)='' THEN 'Motif requis'
        ELSE 'Motif trop long (500 caractères maximum)' END
    THEN RAISE EXCEPTION 'B3 contestation : refus % inattendu : %',v_nom,v_resultat; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
  v_resultat:=public.fn_contester_paiement_soignant(v_inconnu,v_motif);
  IF v_resultat IS DISTINCT FROM '{"error":"Paiement introuvable","error_code":"PAIEMENT_INTROUVABLE"}'::jsonb
  THEN RAISE EXCEPTION 'B3 contestation : paiement inconnu non refusé : %',v_resultat; END IF;
  IF (SELECT to_jsonb(p) FROM public.paiements_soignant p WHERE id=v_ps) IS DISTINCT FROM v_avant
    OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=v_mission OR paiement_soignant_id=v_ps)
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=v_etab
      AND type IN ('LITIGE_OUVERT','CONTESTATION_PAIEMENT'))
  THEN RAISE EXCEPTION 'B3 contestation : un refus a écrit'; END IF;

  -- ── 5. Statuts et collisions, chacun dans un sous-bloc annulé ─────────────
  -- RESOLU : statut hors (DECLARE, EN_ATTENTE).
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    UPDATE public.paiements_soignant SET statut='RESOLU' WHERE id=v_ps;
    PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
    v_resultat:=public.fn_contester_paiement_soignant(v_ps,v_motif);
    IF v_resultat IS DISTINCT FROM jsonb_build_object('error','Ce paiement ne peut plus être contesté (statut: RESOLU)','error_code','STATUT_INVALIDE')
      OR (SELECT statut FROM public.paiements_soignant WHERE id=v_ps)<>'RESOLU'
      OR EXISTS(SELECT 1 FROM public.litiges WHERE paiement_soignant_id=v_ps)
    THEN RAISE EXCEPTION 'B3 contestation : statut RESOLU non refusé : %',v_resultat; END IF;
    RAISE EXCEPTION 'B3_SOUS_CAS_ANNULE' USING ERRCODE='JB301';
  EXCEPTION WHEN SQLSTATE 'JB301' THEN IF SQLERRM<>'B3_SOUS_CAS_ANNULE' THEN RAISE; END IF; END;

  -- Déjà confirmé par le soignant : jamais contestable.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    UPDATE public.paiements_soignant SET confirme_par_soignant=true WHERE id=v_ps;
    PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
    v_resultat:=public.fn_contester_paiement_soignant(v_ps,v_motif);
    IF v_resultat IS DISTINCT FROM '{"error":"Paiement déjà confirmé","error_code":"DEJA_CONFIRME"}'::jsonb
      OR EXISTS(SELECT 1 FROM public.litiges WHERE paiement_soignant_id=v_ps)
    THEN RAISE EXCEPTION 'B3 contestation : paiement confirmé contesté : %',v_resultat; END IF;
    RAISE EXCEPTION 'B3_SOUS_CAS_ANNULE' USING ERRCODE='JB301';
  EXCEPTION WHEN SQLSTATE 'JB301' THEN IF SQLERRM<>'B3_SOUS_CAS_ANNULE' THEN RAISE; END IF; END;

  -- Litige AUTRE sans facture déjà ouvert sur la mission : refus structuré,
  -- paiement intact (l'UPDATE et l'INSERT sont annulés ensemble).
  BEGIN
    PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
    INSERT INTO public.litiges(mission_id,soignant_id,etablissement_id,initie_par,motif,statut)
    VALUES(v_mission,v_soignant,v_etab,'ETABLISSEMENT','Recette B3 litige préexistant','OUVERT')
    RETURNING id INTO v_litige;
    PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
    v_resultat:=public.fn_contester_paiement_soignant(v_ps,v_motif);
    IF v_resultat IS DISTINCT FROM jsonb_build_object('error','Un litige de ce type est déjà ouvert pour cette mission.','error_code','LITIGE_DEJA_OUVERT')
      OR (SELECT to_jsonb(p) FROM public.paiements_soignant p WHERE id=v_ps) IS DISTINCT FROM v_avant
      OR (SELECT count(*) FROM public.litiges WHERE mission_id=v_mission)<>1
      OR EXISTS(SELECT 1 FROM public.litiges WHERE paiement_soignant_id=v_ps)
      OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=v_etab
        AND type IN ('LITIGE_OUVERT','CONTESTATION_PAIEMENT'))
    THEN RAISE EXCEPTION 'B3 contestation : collision de litige mal restituée : %',v_resultat; END IF;
    RAISE EXCEPTION 'B3_SOUS_CAS_ANNULE' USING ERRCODE='JB301';
  EXCEPTION WHEN SQLSTATE 'JB301' THEN IF SQLERRM<>'B3_SOUS_CAS_ANNULE' THEN RAISE; END IF; END;

  -- EN_ATTENTE et motif de 500 caractères : contestation acceptée.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    UPDATE public.paiements_soignant SET statut='EN_ATTENTE' WHERE id=v_ps;
    PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
    v_resultat:=public.fn_contester_paiement_soignant(v_ps,repeat('y',500));
    IF v_resultat->>'success' IS DISTINCT FROM 'true'
      OR (SELECT statut FROM public.paiements_soignant WHERE id=v_ps)<>'CONTESTE'
      OR NOT EXISTS(SELECT 1 FROM public.litiges WHERE id=(v_resultat->>'litige_id')::uuid
        AND paiement_soignant_id=v_ps AND motif='Paiement contesté — '||repeat('y',500))
    THEN RAISE EXCEPTION 'B3 contestation : EN_ATTENTE / 500 caractères refusé : %',v_resultat; END IF;
    RAISE EXCEPTION 'B3_SOUS_CAS_ANNULE' USING ERRCODE='JB301';
  EXCEPTION WHEN SQLSTATE 'JB301' THEN IF SQLERRM<>'B3_SOUS_CAS_ANNULE' THEN RAISE; END IF; END;
  IF (SELECT to_jsonb(p) FROM public.paiements_soignant p WHERE id=v_ps) IS DISTINCT FROM v_avant
    OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=v_mission)
  THEN RAISE EXCEPTION 'B3 contestation : sous-cas non annulé'; END IF;

  -- ── 6. Contestation réelle par le soignant (rôle authenticated) ───────────
  PERFORM set_config('request.jwt.claim.sub',v_soignant::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_soignant,'role','authenticated')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_resultat:=public.fn_contester_paiement_soignant(v_ps,'  '||v_motif||'  ');
  EXECUTE 'RESET ROLE';
  v_litige:=(v_resultat->>'litige_id')::uuid;
  IF v_resultat IS DISTINCT FROM jsonb_build_object('success',true,'litige_id',v_litige) OR v_litige IS NULL
  THEN RAISE EXCEPTION 'B3 contestation : contestation refusée : %',v_resultat; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.paiements_soignant WHERE id=v_ps AND statut='CONTESTE'
      AND conteste IS TRUE AND motif_contestation=v_motif AND confirme_par_soignant IS FALSE
      AND montant_net=80 AND facture_honoraire_id=v_fh)
  THEN RAISE EXCEPTION 'B3 contestation : paiement non marqué CONTESTE'; END IF;
  IF (SELECT count(*) FROM public.litiges WHERE mission_id=v_mission)<>1
    OR NOT EXISTS(SELECT 1 FROM public.litiges WHERE id=v_litige AND paiement_soignant_id=v_ps
      AND mission_id=v_mission AND soignant_id=v_soignant AND etablissement_id=v_etab
      AND initie_par='SOIGNANT' AND statut='OUVERT' AND type_litige='AUTRE' AND facture_id IS NULL
      AND motif='Paiement contesté — '||v_motif)
  THEN RAISE EXCEPTION 'B3 contestation : litige absent ou incorrect'; END IF;
  -- Option D19 : aucune notification CONTESTATION_PAIEMENT ; l'établissement
  -- reçoit exactement une notification, LITIGE_OUVERT, du trigger historique.
  IF EXISTS(SELECT 1 FROM public.notifications WHERE type='CONTESTATION_PAIEMENT'
      AND (destinataire_id=v_etab OR id_ressource=v_litige))
  THEN RAISE EXCEPTION 'B3 contestation : notification CONTESTATION_PAIEMENT inattendue'; END IF;
  IF (SELECT count(*) FROM public.notifications WHERE type='LITIGE_OUVERT' AND destinataire_id=v_etab)<>1
    OR (SELECT count(*) FROM public.notifications WHERE destinataire_id=v_etab AND id_ressource=v_litige)<>1
    OR NOT EXISTS(SELECT 1 FROM public.notifications WHERE type='LITIGE_OUVERT'
      AND destinataire_id=v_etab AND type_destinataire='ETABLISSEMENT'
      AND type_ressource='litige' AND id_ressource=v_litige)
  THEN RAISE EXCEPTION 'B3 contestation : notification établissement LITIGE_OUVERT absente, doublée ou incorrecte'; END IF;
  -- Soignant TEST : la notification admin est écartée par la garde TEST existante.
  IF EXISTS(SELECT 1 FROM public.notifications WHERE type_destinataire='ADMIN' AND id_ressource=v_litige)
  THEN RAISE EXCEPTION 'B3 contestation : notification admin pour un compte TEST'; END IF;
  SELECT to_jsonb(p) INTO v_apres FROM public.paiements_soignant p WHERE id=v_ps;

  -- ── 7. Idempotence : second appel refusé, sans second litige ──────────────
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_resultat:=public.fn_contester_paiement_soignant(v_ps,'Autre motif');
  EXECUTE 'RESET ROLE';
  IF v_resultat IS DISTINCT FROM '{"error":"Paiement déjà contesté","error_code":"DEJA_CONTESTE"}'::jsonb
  THEN RAISE EXCEPTION 'B3 contestation : second appel non refusé : %',v_resultat; END IF;
  IF (SELECT to_jsonb(p) FROM public.paiements_soignant p WHERE id=v_ps) IS DISTINCT FROM v_apres
    OR (SELECT count(*) FROM public.litiges WHERE mission_id=v_mission OR paiement_soignant_id=v_ps)<>1
    OR (SELECT count(*) FROM public.notifications WHERE type='LITIGE_OUVERT' AND destinataire_id=v_etab)<>1
    OR EXISTS(SELECT 1 FROM public.notifications WHERE type='CONTESTATION_PAIEMENT' AND destinataire_id=v_etab)
  THEN RAISE EXCEPTION 'B3 contestation : le second appel a écrit'; END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  RAISE NOTICE 'B3 contestation : succès unique, idempotence et douze refus sans écriture vérifiés (rollback à suivre)';
END;
$b3_contestation$;

ROLLBACK;
