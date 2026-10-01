-- CANDIDAT NON EXECUTE : matrice complémentaire au témoin rouge figé.
-- SQL staging sous rollback seulement. Historique PAYEE explicitement synthétique
-- pour deux chemins documentaires : aucune preuve de paiement ni fournisseur.
-- Références PDF/XML fictives ; vrais triggers/claims/helpers, jamais de COMMIT.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

-- Ces fonctions temporaires rejouent les deux blocs réels de la migration.
-- Le test Node vérifie l'identité octet pour octet ; aucun corps métier n'est recopié.
CREATE FUNCTION pg_temp.f1_inventory_preflight() RETURNS void LANGUAGE plpgsql AS $replay_preflight$
DECLARE r record; p record;
BEGIN
  IF md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure))
    IS DISTINCT FROM 'c793ac81eaef0fe18fb5920c9264c675' THEN
    RAISE EXCEPTION 'Prérequis commission rectificative absent';
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('fn_preparer_facture_commission_periode(uuid)','e155d0232345adb95321d1e56f3c4cdd','8030a296741d5bfe6dad70edd4d8f20d','f26f4d29b77cb2be569c0db62c1fb4dc','fe01d207db4766c4246f641ba171a3e7','search_path=public, pg_temp'),
    ('dec_calculer_commission()','065286258fe7a131557692126c896b1a','2767aab47df4d531744cd751a4faed95','cdfa3faf225b0ac26b43db8a9ad8b41f','4c0238a79c1e54e0b17ad55f89e35104','search_path=public')
  ) AS attendu(signature, ancien_corps, nouveau_corps, ancienne_definition, nouvelle_definition, configuration) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF NOT FOUND OR md5(p.prosrc) NOT IN (r.ancien_corps,r.nouveau_corps)
      OR md5(pg_get_functiondef(p.oid)) NOT IN (r.ancienne_definition,r.nouvelle_definition)
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory
        WHERE signature=r.signature AND (categorie IS DISTINCT FROM 'SERVICE_ONLY_REVOQUE'
          OR definition_md5 IS DISTINCT FROM md5(p.prosrc)))
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory
        WHERE signature='public.'||r.signature) THEN
      RAISE EXCEPTION 'Commission : corps, droits ou inventaire inattendus (%)',r.signature;
    END IF;
  END LOOP;
END;
$replay_preflight$;
CREATE FUNCTION pg_temp.f1_inventory_install() RETURNS void LANGUAGE plpgsql AS $replay_inventory$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fn_preparer_facture_commission_periode(uuid)','e155d0232345adb95321d1e56f3c4cdd','8030a296741d5bfe6dad70edd4d8f20d','f26f4d29b77cb2be569c0db62c1fb4dc','fe01d207db4766c4246f641ba171a3e7','search_path=public, pg_temp'),
    ('dec_calculer_commission()','065286258fe7a131557692126c896b1a','2767aab47df4d531744cd751a4faed95','cdfa3faf225b0ac26b43db8a9ad8b41f','4c0238a79c1e54e0b17ad55f89e35104','search_path=public')
  ) AS attendu(signature, ancien_corps, nouveau_corps, ancienne_definition, nouvelle_definition, configuration) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM r.nouveau_corps
      OR md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM r.nouvelle_definition
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
      RAISE EXCEPTION 'Commission : installation ou droits inattendus (%)',r.signature;
    END IF;
    -- Ces deux fonctions n'avaient pas d'entrée d'inventaire sur le staging
    -- ni en production. Le préflight vérifie leur définition et leurs droits
    -- exacts avant toute installation ; aucune entrée divergente n'est reprise.
    IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=r.signature) THEN
      INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
      VALUES(r.signature,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),
        CASE r.signature
          WHEN 'fn_preparer_facture_commission_periode(uuid)' THEN
            'Primitive service_role : commission rattachée à la pièce exacte, taux de mission stocké et historique documentaire contrôlés.'
          WHEN 'dec_calculer_commission()' THEN
            'Fonction trigger : estimation financière de mission ; EXECUTE révoqué pour PUBLIC, anon et authenticated.'
        END,now());
    ELSE
      UPDATE private.security_definer_inventory SET definition_md5=md5(p.prosrc),recense_le=now()
        WHERE signature=r.signature AND categorie='SERVICE_ONLY_REVOQUE'
          AND definition_md5 IN(r.ancien_corps,r.nouveau_corps);
      IF NOT FOUND THEN RAISE EXCEPTION 'Commission : inventaire non actualisé (%)',r.signature; END IF;
    END IF;
    IF (SELECT count(*) FROM private.security_definer_inventory WHERE signature=r.signature
      AND categorie='SERVICE_ONLY_REVOQUE' AND definition_md5=md5(p.prosrc))<>1 THEN
      RAISE EXCEPTION 'Commission : inventaire installé inattendu (%)',r.signature;
    END IF;
  END LOOP;
END;
$replay_inventory$;
DO $inventory_test$
DECLARE
  v_signatures constant text[]:=ARRAY['fn_preparer_facture_commission_periode(uuid)','dec_calculer_commission()'];
  v_before jsonb;
  v_after jsonb;
  v_functions_before jsonb;
  v_functions_after jsonb;
  v_signature text;
  v_kind text;
  v_phase text;
  v_refused boolean;
  v_rolled_back boolean:=false;
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
     OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'F1 inventaire : contexte de maintenance isolé requis'; END IF;
  SELECT jsonb_agg(to_jsonb(i) ORDER BY signature) INTO v_before
    FROM private.security_definer_inventory i WHERE signature=ANY(v_signatures);
  SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
    'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,
    'config',p.proconfig,'security_definer',p.prosecdef) ORDER BY p.oid)
    INTO v_functions_before FROM pg_proc p
    WHERE p.oid IN ('public.fn_preparer_facture_commission_periode(uuid)'::regprocedure,
      'public.dec_calculer_commission()'::regprocedure);
  BEGIN
    -- Absence réellement exercée sur la table canonique, puis recensement exact.
    DELETE FROM private.security_definer_inventory WHERE signature=ANY(v_signatures);
    PERFORM pg_temp.f1_inventory_preflight();
    PERFORM pg_temp.f1_inventory_install();
    IF (SELECT count(*) FROM private.security_definer_inventory i
      JOIN pg_proc p ON p.oid=to_regprocedure('public.'||i.signature)
      WHERE i.signature=ANY(v_signatures) AND i.categorie='SERVICE_ONLY_REVOQUE'
        AND i.definition_md5=md5(p.prosrc))<>2
    THEN RAISE EXCEPTION 'F1 inventaire : absence non réparée exactement'; END IF;
    -- Rejeu avec entrées exactes présentes : mêmes signatures, corps et droits.
    PERFORM pg_temp.f1_inventory_preflight();
    PERFORM pg_temp.f1_inventory_install();
    FOREACH v_signature IN ARRAY v_signatures LOOP
      FOREACH v_kind IN ARRAY ARRAY['empreinte','categorie'] LOOP
        FOREACH v_phase IN ARRAY ARRAY['preflight','installation'] LOOP
          v_refused:=false;
          BEGIN
            UPDATE private.security_definer_inventory SET
              definition_md5=CASE WHEN v_kind='empreinte' THEN repeat('0',32) ELSE definition_md5 END,
              categorie=CASE WHEN v_kind='categorie' THEN 'PUBLIC_VOLONTAIRE' ELSE categorie END
            WHERE signature=v_signature;
            IF v_phase='preflight' THEN PERFORM pg_temp.f1_inventory_preflight();
            ELSE PERFORM pg_temp.f1_inventory_install(); END IF;
          EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM IS DISTINCT FROM (CASE v_phase
              WHEN 'preflight' THEN format('Commission : corps, droits ou inventaire inattendus (%s)',v_signature)
              ELSE format('Commission : inventaire non actualisé (%s)',v_signature) END)
            THEN RAISE; END IF;
            v_refused:=true;
          END;
          IF NOT v_refused THEN
            RAISE EXCEPTION 'F1 inventaire : contradiction acceptée (%/%/%)',v_signature,v_kind,v_phase;
          END IF;
          -- Le sous-bloc de refus doit aussi annuler sa mutation contradictoire.
          PERFORM pg_temp.f1_inventory_preflight();
        END LOOP;
      END LOOP;
    END LOOP;
    SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
      'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,
      'config',p.proconfig,'security_definer',p.prosecdef) ORDER BY p.oid)
      INTO v_functions_after FROM pg_proc p
      WHERE p.oid IN ('public.fn_preparer_facture_commission_periode(uuid)'::regprocedure,
        'public.dec_calculer_commission()'::regprocedure);
    IF v_functions_after IS DISTINCT FROM v_functions_before THEN
      RAISE EXCEPTION 'F1 inventaire : corps ou droits modifiés';
    END IF;
    RAISE EXCEPTION 'F1_INVENTAIRE_ANNULATION_ATTENDUE' USING ERRCODE='JF152';
  EXCEPTION WHEN SQLSTATE 'JF152' THEN
    IF SQLERRM<>'F1_INVENTAIRE_ANNULATION_ATTENDUE' THEN RAISE; END IF;
    v_rolled_back:=true;
  END;
  SELECT jsonb_agg(to_jsonb(i) ORDER BY signature) INTO v_after
    FROM private.security_definer_inventory i WHERE signature=ANY(v_signatures);
  IF NOT v_rolled_back OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'F1 inventaire : annulation non prouvée';
  END IF;
END;
$inventory_test$;

DO $f1$
DECLARE
  v_soignant constant uuid := 'f1410001-1000-4000-8000-000000000001';
  v_etab constant uuid := 'f1410002-2000-4000-8000-000000000002';
  v_mission constant uuid := 'f1410003-3000-4000-8000-000000000003';
  v_honoraire constant uuid := 'f1410004-4000-4000-8000-000000000004';
  v_doublon constant uuid := 'f1410005-5000-4000-8000-000000000005';
  v_commission uuid;
  v_admin constant uuid := 'f1410006-6000-4000-8000-000000000006';
  v_equipe constant uuid := 'f1410007-7000-4000-8000-000000000007';
  v_litige constant uuid := 'f1410008-8000-4000-8000-000000000008';
  v_presence constant uuid := 'f1410009-9000-4000-8000-000000000009';
  v_remplacement uuid;
  v_commission_remplacement uuid;
  v_semaine date := date_trunc('week',current_date)::date - 14;
  v_jour_passe date;
  v_jour_futur date;
  v_jour_suivant date;
  v_facture_suivante constant uuid := 'f141000a-a000-4000-8000-00000000000a';
  v_commission_suivante uuid;
  v_pieces_avant jsonb;
  v_financier_cloture jsonb;
  v_resultat jsonb;
  v_rejeu jsonb;
  v_nom text;
  v_annule boolean := false;
  v_cas record;
  v_mission_apres jsonb;
  v_initial_net numeric;
  v_statut public.statut_mission;
  v_ht_origine numeric;
  v_tva_origine numeric;
  v_ttc_origine numeric;
  v_commission_origine_ht numeric;
  v_commission_origine_tva numeric;
  v_total_pieces numeric;
  v_total_commissions numeric;
  v_attendu_erreur text;
  v_refus boolean;
  v_compte_commissions integer;
  v_duplicates uuid;
  v_dernier_snapshot jsonb;
  v_nb_cas integer:=0;
BEGIN
  -- Ce candidat est destiné au job staging à verrou global seulement. Aucun
  -- cron ne doit consommer d'outbox ; toutes les écritures restent invisibles.
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
     OR public.est_admin() OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'F1 : contexte SQL de maintenance isolé requis'; END IF;
  FOREACH v_nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation',
    'jolene.heures_litige_override','jolene.heures_litige_mission_id','jolene.assignment_rpc_soignant_id',
    'jolene.empechement_mission_context','jolene.empechement_mission_validated'] LOOP
    IF NULLIF(current_setting(v_nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'F1 : contexte de contournement interdit'; END IF;
  END LOOP;
  FOREACH v_nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed','app.test_bypass_protections'] LOOP
    IF COALESCE(current_setting(v_nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'F1 : synchronisation forcée interdite'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'F1 : trigger Auth INSERT non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.soignants'::regclass,
    'public.etablissements'::regclass,'public.missions'::regclass,'public.mission_creneaux'::regclass,
    'public.factures_honoraires'::regclass,'public.factures'::regclass,'public.notifications'::regclass,
    'public.invoice_audit_log'::regclass,'public.presences'::regclass,
    'public.email_queue'::regclass,'public.scoring_breakdown'::regclass) AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'F1 : triggers métier désactivés'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(v_soignant,v_etab,v_admin))
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=v_equipe OR user_id=v_admin)
    OR EXISTS(SELECT 1 FROM public.litiges WHERE id=v_litige)
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=v_presence OR mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_etab OR siret='99150000000843')
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission)
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id IN(v_honoraire,v_doublon,v_facture_suivante))
  THEN RAISE EXCEPTION 'F1 : identifiants de fixture déjà présents'; END IF;

  -- Deux jours ouvrés sans jour férié : montants indépendants, sans modifier le
  -- calendrier. Les deux semaines sont fermées ; la mission reste EN_COURS.
  SELECT d::date INTO v_jour_passe FROM generate_series(v_semaine,v_semaine+4,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_jour_futur FROM generate_series(v_semaine+21,v_semaine+25,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  SELECT d::date INTO v_jour_suivant FROM generate_series(v_semaine+7,v_semaine+11,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF v_jour_passe IS NULL OR v_jour_futur IS NULL OR v_jour_suivant IS NULL OR v_semaine+13>=current_date
  THEN RAISE EXCEPTION 'F1 : calendrier de fixture indisponible'; END IF;


  IF md5(pg_get_functiondef('public.fn_preparer_commission_complement_honoraires(uuid)'::regprocedure)) IS DISTINCT FROM 'b4e7b07193aa270a24a66a10709a87d8'
    OR md5(pg_get_functiondef('public.fn_admin_resoudre_litige_complement_honoraires(uuid,text,text,numeric,numeric)'::regprocedure)) IS DISTINCT FROM '0f8d3a480b3dd60e8081e53a97b30cc9'
    OR md5(pg_get_functiondef('public.fn_solde_correction_facture_honoraires(uuid)'::regprocedure)) IS DISTINCT FROM '668023f4f4e42102dbc9f6faa95a8cd9'
    OR md5(pg_get_functiondef('public.fn_preparer_avoir_commission_honoraires(uuid)'::regprocedure)) IS DISTINCT FROM 'a65bb72885271a63de5b2dbcdbb7a6be'
  THEN RAISE EXCEPTION 'F1 matrice : dépendances LIVE des corrections modifiées'; END IF;

  -- Matrice complémentaire, distincte du témoin rouge byte-identique.
  -- Chaque cas est annulé avant le suivant, avec les mêmes identifiants bornés.
  FOR v_cas IN SELECT * FROM (VALUES
    ('tva_honoraires',20::numeric,15::numeric,20::numeric,NULL::text,NULL::numeric,12::numeric,160::numeric,24::numeric),
    ('taux_fige_12',20,12,0,NULL,NULL,9.60,160,19.20),
    ('lissage_finale',20.01,15,0,NULL,NULL,12,160.08,24.01),
    ('avoir_finale',20,15,0,'AVOIR',3,12,140,21),
    ('complement_finale',20,15,0,'COMPLEMENT',5,12,180,27),
    ('remplacement_historique_null',20,15,0,'ANNULER_REEMETTRE',3,12,140,21),
    ('commission_absente',20,15,0,NULL,NULL,12,160,24),
    ('historique_taux_incoherent',20,15,0,NULL,NULL,NULL,NULL,NULL),
    ('commission_ambigue',20,15,0,'AVOIR',3,NULL,NULL,NULL)
  ) AS c(nom,taux_horaire,taux_commission,tva_honoraires,action,heures_corrigees,
    suivante_ht,cumul_honoraires_ht,cumul_commissions_ht)
  LOOP
    v_initial_net:=round(8*v_cas.taux_horaire,2); v_statut:='EN_COURS';
    v_ht_origine:=round(4*v_cas.taux_horaire,2);
    v_tva_origine:=round(v_ht_origine*v_cas.tva_honoraires/100,2);
    v_ttc_origine:=v_ht_origine+v_tva_origine;
    v_commission_origine_ht:=round(v_ht_origine*v_cas.taux_commission/100,2);
    v_commission_origine_tva:=round(v_commission_origine_ht*0.2,2);
    v_annule:=false; v_remplacement:=NULL; v_commission:=NULL;
    v_commission_remplacement:=NULL; v_commission_suivante:=NULL; v_duplicates:=NULL;
    v_attendu_erreur:=NULL;
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
    -- Les taux figés du cas sont des snapshots financiers synthétiques ;
    -- fige_le reste NULL, sans prétendre avoir signé/attribué une mission.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente,
      taux_horaire_base_fige,taux_commission_fige)
    VALUES(v_mission,v_etab,'RECETTE F1 SQL annulee','IDE',v_jour_futur+time '09:00',v_jour_futur+time '13:00',
      4,v_cas.taux_horaire,v_statut,v_soignant,'LIBERAL','LIBERAL','LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false,v_cas.taux_horaire,v_cas.taux_commission);
    IF (SELECT count(*) FROM public.mission_creneaux WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL')<>1
      OR (SELECT fige_le FROM public.missions WHERE id=v_mission) IS NOT NULL
    THEN RAISE EXCEPTION 'F1 : planning legacy/état initial inattendu'; END IF;
    UPDATE public.mission_creneaux SET debut=v_jour_passe+time '09:00',fin=v_jour_passe+time '13:00'
      WHERE mission_id=v_mission AND type_creneau='PREVISIONNEL';
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
      VALUES(v_mission,v_jour_suivant+time '09:00',v_jour_suivant+time '13:00','PREVISIONNEL',false,2);
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
    VALUES(v_mission,v_jour_passe+time '09:00',v_jour_passe+time '13:00','EFFECTIF',false,3),
      (v_mission,v_jour_suivant+time '09:00',v_jour_suivant+time '13:00','EFFECTIF',false,4);

      IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission
        AND statut='EN_COURS' AND nb_creneaux=2 AND duree_heures=8 AND duree_heures_effective=8
        AND total_brut=v_initial_net AND net_a_payer=v_initial_net AND fige_le IS NULL
        AND taux_commission_fige=v_cas.taux_commission)
      THEN RAISE EXCEPTION 'F1 matrice : planning initial incohérent, cas %',v_cas.nom; END IF;
      INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
        montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,periode_debut,periode_fin,
        statut,type_document,nature_correction,mode_remboursement,est_facture_finale_mission,
        quantite_heures_snapshot,taux_horaire_snapshot)
      VALUES(v_honoraire,public.next_invoice_number(v_soignant),v_soignant,v_etab,v_mission,
        v_ht_origine,v_tva_origine,v_ttc_origine,v_cas.tva_honoraires,v_cas.tva_honoraires=0,
        v_semaine,v_semaine+6,'BROUILLON','FACTURE','ORIGINALE','N_A',false,
        CASE WHEN v_cas.nom='remplacement_historique_null' THEN NULL ELSE 4 END,
        CASE WHEN v_cas.nom='remplacement_historique_null' THEN NULL ELSE v_cas.taux_horaire END);
      PERFORM public.fn_emettre_document_facturation_honoraires(v_honoraire,'fixture-matrice-original.pdf','fixture-matrice-original.xml');
      IF v_cas.nom<>'commission_absente' THEN
        v_resultat:=public.fn_preparer_facture_commission_periode(v_honoraire);
        v_commission:=(v_resultat->>'facture_id')::uuid;
        IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
          OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission
            AND montant_ht=v_commission_origine_ht AND montant_tva=v_commission_origine_tva
            AND montant_ttc=v_commission_origine_ht+v_commission_origine_tva AND statut='EMISE')
        THEN RAISE EXCEPTION 'F1 matrice : commission initiale incorrecte, cas %',v_cas.nom; END IF;
      END IF;

      IF v_cas.action IS NOT NULL THEN
        IF v_cas.action IN ('AVOIR','COMPLEMENT') THEN
          -- Historique PAYEE synthétique dans le sous-bloc annulé : aucun
          -- PaymentIntent, encaissement, virement ou preuve Stripe n'est créé.
          UPDATE public.factures_honoraires SET statut='PAYEE',date_paiement=current_date
            WHERE id=v_honoraire;
        END IF;
        INSERT INTO public.presences(id,mission_id,soignant_id,heures_reelles)
        VALUES(v_presence,v_mission,v_soignant,4);
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
    VALUES(v_litige,v_mission,v_soignant,v_etab,'SOIGNANT','RECETTE SYNTHETIQUE ANNULEE : heures erronées sur première période',
      'OUVERT','DESACCORD_MONTANT_FACTURE',v_honoraire,'FACTURE_UNIQUE',v_semaine,v_semaine+6);

        v_resultat:=public.fn_admin_resoudre_litige_intelligent(v_litige,
          'RECETTE SYNTHETIQUE ANNULEE : matrice de commissions documentaires',
          'NEUTRE',v_cas.heures_corrigees,v_cas.taux_horaire,v_cas.action);
        v_remplacement:=COALESCE(NULLIF(v_resultat->>'nouvelle_facture_id',''),NULLIF(v_resultat->>'avoir_id',''))::uuid;
        IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
          OR v_resultat->>'action_financiere' IS DISTINCT FROM v_cas.action OR v_remplacement IS NULL
          OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_remplacement
            AND facture_precedente_id=v_honoraire AND mission_id=v_mission
            AND montant_ht=CASE WHEN v_cas.action='ANNULER_REEMETTRE' THEN 60 ELSE 20 END
            AND montant_ttc=montant_ht AND taux_tva=0)
        THEN RAISE EXCEPTION 'F1 matrice : correction canonique refusée, cas %, résultat %',v_cas.nom,v_resultat; END IF;
        IF v_cas.action='AVOIR' AND NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=v_remplacement
          AND type_document='AVOIR' AND mode_remboursement='VIREMENT_MANUEL' AND stripe_payment_intent_id IS NULL)
        THEN RAISE EXCEPTION 'F1 matrice : avoir non isolé'; END IF;
        PERFORM set_config('request.jwt.claim.sub','',true);
        PERFORM set_config('request.jwt.claim.role','service_role',true);
        PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
        PERFORM public.fn_emettre_document_facturation_honoraires(v_remplacement,'fixture-matrice-correction.pdf','fixture-matrice-correction.xml');
        v_resultat:=CASE v_cas.action
          WHEN 'AVOIR' THEN public.fn_preparer_avoir_commission_honoraires(v_remplacement)
          WHEN 'COMPLEMENT' THEN public.fn_preparer_commission_complement_honoraires(v_remplacement)
          ELSE public.fn_preparer_commission_remplacement_honoraires(v_remplacement) END;
        v_commission_remplacement:=(v_resultat->>'facture_id')::uuid;
        IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
          OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission_remplacement
            AND facture_honoraire_id=v_remplacement AND facture_precedente_id=v_commission
            AND montant_ht=CASE WHEN v_cas.action='ANNULER_REEMETTRE' THEN 9 ELSE 3 END
            AND montant_tva=CASE WHEN v_cas.action='ANNULER_REEMETTRE' THEN 1.8 ELSE 0.6 END
            AND montant_ttc=CASE WHEN v_cas.action='ANNULER_REEMETTRE' THEN 10.8 ELSE 3.6 END)
        THEN RAISE EXCEPTION 'F1 matrice : commission de correction incorrecte, cas %',v_cas.nom; END IF;
        SELECT to_jsonb(m) INTO v_mission_apres FROM public.missions m WHERE id=v_mission;
        v_rejeu:=CASE v_cas.action
          WHEN 'AVOIR' THEN public.fn_preparer_avoir_commission_honoraires(v_remplacement)
          WHEN 'COMPLEMENT' THEN public.fn_preparer_commission_complement_honoraires(v_remplacement)
          ELSE public.fn_preparer_commission_remplacement_honoraires(v_remplacement) END;
        IF v_rejeu->'existing' IS DISTINCT FROM 'true'::jsonb
          OR v_rejeu->>'facture_id' IS DISTINCT FROM v_commission_remplacement::text
          OR (SELECT count(*) FROM public.factures WHERE facture_honoraire_id=v_remplacement)<>1
          OR v_mission_apres IS DISTINCT FROM (SELECT to_jsonb(m) FROM public.missions m WHERE id=v_mission)
        THEN RAISE EXCEPTION 'F1 matrice : correction non idempotente'; END IF;
      END IF;
      -- Même base estimative après tous les helpers ; ne pas la remplacer par
      -- les soldes documentaires 140 ou 180 qui fausseraient le prorata suivant.
      IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut='EN_COURS'
        AND total_brut=v_initial_net AND net_a_payer=v_initial_net
        AND montant_commission_ht=round(v_initial_net*v_cas.taux_commission/100,2)
        AND montant_commission_tva=round(round(v_initial_net*v_cas.taux_commission/100,2)*.2,2)
        AND montant_commission_ttc=montant_commission_ht+montant_commission_tva)
      THEN RAISE EXCEPTION 'F1 matrice : estimation incohérente après helper, cas %',v_cas.nom; END IF;

      PERFORM set_config('request.jwt.claim.sub',v_etab::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_etab,'role','authenticated')::text,true);
      IF public.est_admin() IS TRUE OR public.mon_etablissement_id() IS DISTINCT FROM v_etab
        OR public.fn_a_permission_etablissement('missions',v_etab) IS NOT TRUE
        OR public.fn_compte_auth_actif() IS NOT TRUE
      THEN RAISE EXCEPTION 'F1 heures : acteur établissement de clôture non reconnu'; END IF;
      v_resultat:=public.fn_terminer_mission(v_mission);
      IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
        OR v_resultat->'cloture_anticipee_admin' IS DISTINCT FROM 'false'::jsonb
        OR NOT EXISTS(SELECT 1 FROM public.missions WHERE id=v_mission AND statut='TERMINEE' AND fin_le<now())
      THEN RAISE EXCEPTION 'F1 heures : clôture canonique refusée : %',v_resultat; END IF;
      SELECT jsonb_build_object('net',net_a_payer,'brut',total_brut,
        'commission_ht',montant_commission_ht,'commission_tva',montant_commission_tva,
        'commission_ttc',montant_commission_ttc)
        INTO v_financier_cloture FROM public.missions WHERE id=v_mission;
      IF v_financier_cloture IS DISTINCT FROM jsonb_build_object(
        'net',v_initial_net,'brut',v_initial_net,
        'commission_ht',round(v_initial_net*v_cas.taux_commission/100,2),
        'commission_tva',round(round(v_initial_net*v_cas.taux_commission/100,2)*.2,2),
        'commission_ttc',round(v_initial_net*v_cas.taux_commission/100,2)
          +round(round(v_initial_net*v_cas.taux_commission/100,2)*.2,2))
      THEN RAISE EXCEPTION 'F1 matrice : estimation altérée à la clôture, cas %, observé %',v_cas.nom,v_financier_cloture; END IF;
      -- Le trigger métier enfile deux emails. Ils restent non commités ;
      -- les préférences n'empêchent pas cet INSERT historique.
      IF (SELECT count(*) FROM public.email_queue WHERE destinataire_id IN(v_soignant,v_etab)
        AND type='MISSION_TERMINEE' AND data->>'mission_id'=v_mission::text)<>2
      THEN RAISE EXCEPTION 'F1 heures : emails transactionnels de clôture inattendus'; END IF;
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claim.role','service_role',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);

      IF v_cas.nom='historique_taux_incoherent' THEN
        -- Ancienne pièce inchangée ; un taux synthétique différent ne peut pas
        -- être absorbé silencieusement dans une facture finale de rattrapage.
        UPDATE public.missions SET taux_commission_fige=12 WHERE id=v_mission;
        v_attendu_erreur:='Historique de commission incohérent : écart hors arrondis';
      ELSIF v_cas.nom='commission_absente' THEN
        v_attendu_erreur:='Commission antérieure absente, ambiguë ou incohérente : facture finale suspendue';
      ELSIF v_cas.nom='commission_ambigue' THEN
        -- Corruption historique synthétique bornée : deux avoirs Jolene liés
        -- au même avoir d'honoraires. Aucun document réel n'est modifié.
        INSERT INTO public.factures(etablissement_id,mission_id,facture_honoraire_id,numero_facture,
          type_document,facture_precedente_id,montant_ht,taux_tva,montant_tva,montant_ttc,
          nombre_missions,statut,date_emission,date_echeance,periode_debut,periode_fin,
          est_secteur_public,mode_paiement)
        SELECT etablissement_id,mission_id,facture_honoraire_id,public.next_avoir_commission_number(v_etab),
          type_document,facture_precedente_id,montant_ht,taux_tva,montant_tva,montant_ttc,
          nombre_missions,statut,date_emission,date_echeance,periode_debut,periode_fin,
          est_secteur_public,mode_paiement FROM public.factures WHERE id=v_commission_remplacement
        RETURNING id INTO v_duplicates;
        v_attendu_erreur:='Commission antérieure absente, ambiguë ou incohérente : facture finale suspendue';
      END IF;
      v_resultat:=public.fn_calculer_montant_periode(v_mission,v_semaine+7,v_semaine+13);
      IF (v_resultat->>'montant_ht_periode')::numeric IS DISTINCT FROM v_ht_origine
      THEN RAISE EXCEPTION 'F1 matrice : période suivante altérée, cas %',v_cas.nom; END IF;
      INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
        montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,periode_debut,periode_fin,
        statut,type_document,nature_correction,mode_remboursement,est_facture_finale_mission,
        quantite_heures_snapshot,taux_horaire_snapshot)
      VALUES(v_facture_suivante,public.next_invoice_number(v_soignant),v_soignant,v_etab,v_mission,
        v_ht_origine,v_tva_origine,v_ttc_origine,v_cas.tva_honoraires,v_cas.tva_honoraires=0,
        v_semaine+7,v_semaine+13,'BROUILLON','FACTURE','ORIGINALE','N_A',true,4,v_cas.taux_horaire);
      PERFORM public.fn_emettre_document_facturation_honoraires(v_facture_suivante,'fixture-matrice-suite.pdf','fixture-matrice-suite.xml');
      -- La facture suivante et son refus éventuel ne réécrivent pas l'estimation.
      -- Le cas de taux contradictoire possède son propre historique volontaire.
      SELECT jsonb_build_object('net',net_a_payer,'brut',total_brut,
        'commission_ht',montant_commission_ht,'commission_tva',montant_commission_tva,
        'commission_ttc',montant_commission_ttc)
        INTO v_financier_cloture FROM public.missions WHERE id=v_mission;
      SELECT jsonb_build_object('honoraires',(SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM public.factures_honoraires h
        WHERE mission_id=v_mission AND id<>v_facture_suivante),
        'commissions',(SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM public.factures f WHERE mission_id=v_mission))
        INTO v_pieces_avant;
      IF v_attendu_erreur IS NOT NULL THEN
        SELECT to_jsonb(m) INTO v_mission_apres FROM public.missions m WHERE id=v_mission;
        SELECT count(*) INTO v_compte_commissions FROM public.factures WHERE mission_id=v_mission;
        v_refus:=false;
        BEGIN
          PERFORM public.fn_preparer_facture_commission_periode(v_facture_suivante);
        EXCEPTION WHEN check_violation THEN
          IF SQLERRM IS DISTINCT FROM v_attendu_erreur THEN RAISE; END IF;
          v_refus:=true;
        END;
        IF NOT v_refus OR (SELECT count(*) FROM public.factures WHERE mission_id=v_mission)<>v_compte_commissions
          OR v_mission_apres IS DISTINCT FROM (SELECT to_jsonb(m) FROM public.missions m WHERE id=v_mission)
        THEN RAISE EXCEPTION 'F1 matrice : refus non atomique, cas %',v_cas.nom; END IF;
      ELSE
        v_resultat:=public.fn_preparer_facture_commission_periode(v_facture_suivante);
        v_commission_suivante:=(v_resultat->>'facture_id')::uuid;
        IF v_resultat->'success' IS DISTINCT FROM 'true'::jsonb
          OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=v_commission_suivante AND facture_honoraire_id=v_facture_suivante
            AND montant_ht=v_cas.suivante_ht AND montant_tva=round(v_cas.suivante_ht*.2,2)
            AND montant_ttc=v_cas.suivante_ht+round(v_cas.suivante_ht*.2,2) AND statut='EMISE')
        THEN RAISE EXCEPTION 'F1 matrice : commission finale incorrecte, cas %',v_cas.nom; END IF;
        SELECT sum(CASE WHEN type_document='AVOIR' THEN -montant_ht ELSE montant_ht END)
          INTO v_total_pieces FROM public.factures_honoraires
          WHERE mission_id=v_mission AND statut IN('EMISE','PAYEE','EN_RETARD','FACTORISEE','REMBOURSE');
        SELECT sum(CASE WHEN type_document='AVOIR' THEN -montant_ht ELSE montant_ht END)
          INTO v_total_commissions FROM public.factures
          WHERE mission_id=v_mission AND statut NOT IN('ANNULEE','REMPLACEE','ERREUR_GENERATION');
        IF v_total_pieces IS DISTINCT FROM v_cas.cumul_honoraires_ht
          OR v_total_commissions IS DISTINCT FROM v_cas.cumul_commissions_ht
        THEN RAISE EXCEPTION 'F1 matrice : cumuls documentaires incorrects, cas %, honoraires %, commissions %',v_cas.nom,v_total_pieces,v_total_commissions; END IF;
        SELECT to_jsonb(m) INTO v_mission_apres FROM public.missions m WHERE id=v_mission;
        v_rejeu:=public.fn_preparer_facture_commission_periode(v_facture_suivante);
        IF v_rejeu->'existing' IS DISTINCT FROM 'true'::jsonb OR v_rejeu->>'facture_id' IS DISTINCT FROM v_commission_suivante::text
          OR v_mission_apres IS DISTINCT FROM (SELECT to_jsonb(m) FROM public.missions m WHERE id=v_mission)
        THEN RAISE EXCEPTION 'F1 matrice : finale non idempotente'; END IF;
      END IF;
      SELECT jsonb_build_object('honoraires',(SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM public.factures_honoraires h
        WHERE mission_id=v_mission AND id<>v_facture_suivante),
        'commissions',(SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM public.factures f
          WHERE mission_id=v_mission AND id IS DISTINCT FROM v_commission_suivante)) INTO v_dernier_snapshot;
      IF v_financier_cloture IS DISTINCT FROM (SELECT jsonb_build_object(
        'net',net_a_payer,'brut',total_brut,'commission_ht',montant_commission_ht,
        'commission_tva',montant_commission_tva,'commission_ttc',montant_commission_ttc)
        FROM public.missions WHERE id=v_mission)
      THEN RAISE EXCEPTION 'F1 matrice : estimation altérée par la commission finale, cas %',v_cas.nom; END IF;
      IF v_pieces_avant IS DISTINCT FROM v_dernier_snapshot
        OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE avoir_id IN(v_honoraire,v_remplacement,v_facture_suivante))
        OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=v_mission)
        OR EXISTS(SELECT 1 FROM public.paiements_mission WHERE mission_id=v_mission)
        OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_mission)
        OR EXISTS(SELECT 1 FROM public.cessions_creance WHERE facture_honoraire_id IN(v_honoraire,v_remplacement,v_facture_suivante))
      THEN RAISE EXCEPTION 'F1 matrice : archive ou effet fournisseur inattendu'; END IF;
      RAISE EXCEPTION USING ERRCODE='JF151',MESSAGE='F1_ANNULATION_ATTENDUE';
    EXCEPTION WHEN SQLSTATE 'JF151' THEN
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
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=v_mission OR id IN(v_honoraire,v_doublon,v_remplacement,v_facture_suivante))
    OR EXISTS(SELECT 1 FROM public.factures WHERE mission_id=v_mission OR id IN(v_commission,v_commission_remplacement,v_commission_suivante))
    OR EXISTS(SELECT 1 FROM public.invoice_audit_log WHERE invoice_id IN(v_honoraire,v_remplacement,v_facture_suivante))
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource IN(v_litige,v_remplacement,v_commission_remplacement) OR acteur_id=v_admin)
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.scoring_breakdown WHERE soignant_id=v_soignant)
    OR EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.paiements_mission WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE avoir_id IN(v_honoraire,v_remplacement,v_facture_suivante))
    OR EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id IN(v_soignant,v_etab))
    OR EXISTS(SELECT 1 FROM public.conformite_travail WHERE mission_id=v_mission)
    OR EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=v_soignant)
  THEN RAISE EXCEPTION 'F1 : annulation transactionnelle non prouvée'; END IF;

    v_nb_cas:=v_nb_cas+1;
  END LOOP;
  IF v_nb_cas<>9 THEN RAISE EXCEPTION 'F1 matrice : cas manquant'; END IF;
END $f1$;
SELECT 'F1_COMMISSIONS_MATRICE_SQL_ROLLBACK' AS preuve,true AS annule,9 AS scenarios;
ROLLBACK;
