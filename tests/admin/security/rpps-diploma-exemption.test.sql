-- Règle métier documentaire : un RPPS validé par l'API dispense du diplôme
-- uniquement pour les professions à RPPS. Toutes les écritures sont annulées.

\set ON_ERROR_STOP on
BEGIN;

DO $rpps_diploma$
DECLARE
  v_ide uuid := gen_random_uuid();
  v_specialiste uuid;
  v_diplome uuid;
  v_profession text;
  v_adeli uuid := gen_random_uuid();
  v_as uuid := gen_random_uuid();
  v_rpps text := '1' || right(
    lpad(regexp_replace(gen_random_uuid()::text, '[^0-9]', '', 'g'), 10, '0'),
    10
  );
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession, type_exercice,
    rpps_verifie, adeli_verifie, est_compte_test
  ) VALUES (
    v_ide, 'Camille', 'RppsTest',
    'rpps-diploma-' || v_ide::text || '@test.local', DATE '1990-01-01',
    'IDE', 'SALARIE', false, false, true
  );

  -- Installe toutes les preuves critiques salariées sauf celles que le RPPS
  -- peut remplacer. Le diplôme reste volontairement absent.
  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, valide_depuis, valide_jusqua, verifie_le,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom
  )
  SELECT
    v_ide,
    drp.type_document,
    v_ide::text || '/documents/' || lower(drp.type_document::text) || '.pdf',
    lower(drp.type_document::text) || '.pdf',
    'VERIFIE',
    current_date,
    CASE WHEN drp.a_expiration THEN current_date + 365 ELSE NULL END,
    now(),
    CASE
      WHEN drp.type_document = 'CARTE_IDENTITE'
        THEN jsonb_build_object('date_naissance_extraite', '1990-01-01')
      ELSE '{}'::jsonb
    END,
    'RPPSTEST',
    'Camille',
    true
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = 'IDE'
    AND drp.est_critique IS TRUE
    AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
    AND drp.type_document NOT IN ('DIPLOME', 'RPPS_ADELI');

  IF EXISTS (
    SELECT 1
    FROM public.documents_soignants
    WHERE soignant_id = v_ide AND type_document = 'DIPLOME'
  ) THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T0: le fixture contient un diplôme';
  END IF;

  UPDATE public.soignants
  SET numero_rpps = v_rpps,
      rpps_verifie = true,
      rpps_verifie_le = now(),
      rpps_nom_api = 'RPPSTEST',
      rpps_prenom_api = 'Camille',
      rpps_profession_api = 'IDE'
  WHERE id = v_ide;

  IF public.fn_documents_ok_pour_mission(v_ide, 'SALARIE') IS NOT TRUE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T1: le RPPS validé ne dispense pas du diplôme';
  END IF;
  IF (SELECT tous_documents_valides FROM public.soignants WHERE id = v_ide) IS NOT TRUE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T2: le cache n''a pas été recalculé après validation RPPS';
  END IF;

  -- Une révocation serveur du RPPS rétablit immédiatement l'exigence du
  -- diplôme. La GUC reproduit le chemin privilégié utilisé par les services
  -- internes sans dépendre de l'identité SQL du runner de test.
  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET rpps_verifie = false,
      rpps_verifie_le = NULL
  WHERE id = v_ide;
  PERFORM set_config('jolene.system_update', '', true);

  IF (SELECT rpps_verifie FROM public.soignants WHERE id = v_ide) IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T3: la révocation serveur du RPPS n''a pas été persistée';
  END IF;

  IF public.fn_documents_ok_pour_mission(v_ide, 'SALARIE') IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T4: la révocation RPPS n''a pas rétabli le diplôme';
  END IF;
  IF (SELECT tous_documents_valides FROM public.soignants WHERE id = v_ide) IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T5: le cache n''a pas été invalidé à la révocation RPPS';
  END IF;

  -- ADELI seul dispense de la ligne RPPS_ADELI, mais pas du diplôme. Un
  -- profil indépendant évite qu'un ancien verdict RPPS influence ce cas.
  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession, type_exercice,
    rpps_verifie, adeli_verifie, adeli_verifie_le, est_compte_test
  ) VALUES (
    v_adeli, 'Sam', 'AdeliTest',
    'adeli-diploma-' || v_adeli::text || '@test.local', DATE '1992-03-03',
    'IDE', 'SALARIE', false, true, now(), true
  );

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, valide_depuis, valide_jusqua, verifie_le,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom
  )
  SELECT
    v_adeli,
    drp.type_document,
    v_adeli::text || '/documents/' || lower(drp.type_document::text) || '.pdf',
    lower(drp.type_document::text) || '.pdf',
    'VERIFIE',
    current_date,
    CASE WHEN drp.a_expiration THEN current_date + 365 ELSE NULL END,
    now(),
    CASE
      WHEN drp.type_document = 'CARTE_IDENTITE'
        THEN jsonb_build_object('date_naissance_extraite', '1992-03-03')
      ELSE '{}'::jsonb
    END,
    'ADELITEST',
    'Sam',
    true
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = 'IDE'
    AND drp.est_critique IS TRUE
    AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
    AND drp.type_document NOT IN ('DIPLOME', 'RPPS_ADELI');

  IF public.fn_documents_ok_pour_mission(v_adeli, 'SALARIE') IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T6: ADELI seul a dispensé du diplôme';
  END IF;

  -- Défense en profondeur : une profession sans RPPS ne bénéficie jamais de
  -- la dispense, même si une donnée incohérente positionne rpps_verifie=true.
  INSERT INTO public.soignants(
    id, prenom, nom, email, date_naissance, profession, type_exercice,
    rpps_verifie, est_compte_test
  ) VALUES (
    v_as, 'Alex', 'SansRpps',
    'sans-rpps-diploma-' || v_as::text || '@test.local', DATE '1991-02-02',
    'AS', 'SALARIE', false, true
  );

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier,
    statut_verification, valide_depuis, valide_jusqua, verifie_le,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom
  )
  SELECT
    v_as,
    drp.type_document,
    v_as::text || '/documents/' || lower(drp.type_document::text) || '.pdf',
    lower(drp.type_document::text) || '.pdf',
    'VERIFIE',
    current_date,
    CASE WHEN drp.a_expiration THEN current_date + 365 ELSE NULL END,
    now(),
    CASE
      WHEN drp.type_document = 'CARTE_IDENTITE'
        THEN jsonb_build_object('date_naissance_extraite', '1991-02-02')
      ELSE '{}'::jsonb
    END,
    'SANSRPPS',
    'Alex',
    true
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = 'AS'
    AND drp.est_critique IS TRUE
    AND drp.type_exercice_requis IN ('TOUS', 'SALARIE_ONLY')
    AND drp.type_document <> 'DIPLOME';

  UPDATE public.soignants
  SET rpps_verifie = true,
      rpps_verifie_le = now()
  WHERE id = v_as;

  IF public.fn_documents_ok_pour_mission(v_as, 'SALARIE') IS NOT FALSE THEN
    RAISE EXCEPTION 'RPPS-DIPLOME-T7: une profession sans RPPS a été dispensée du diplôme';
  END IF;
  -- IADE/IBODE : ne jamais confondre le contrôle RPPS de profession infirmière
  -- avec la qualification du diplôme spécialisé déjà exigée par la fonction.
  PERFORM set_config('jolene.admin_seed_override_reason', 'TEST DIPLOMES SPECIALISES SYNTHETIQUES SOUS ROLLBACK', true);
  FOREACH v_profession IN ARRAY ARRAY['IADE', 'IBODE'] LOOP
    v_specialiste := gen_random_uuid();
    INSERT INTO public.soignants(id,prenom,nom,email,date_naissance,profession,type_exercice,rpps_verifie,adeli_verifie,est_compte_test)
    VALUES(v_specialiste,'Fixture','Specialite',v_specialiste::text || '@test.local',DATE '1990-01-01',v_profession::public.type_profession,'SALARIE',false,false,true);
    IF NOT EXISTS(SELECT 1 FROM public.documents_requis_par_profession WHERE profession::text=v_profession
      AND type_document='DIPLOME' AND est_critique IS TRUE AND type_exercice_requis IN ('TOUS','SALARIE_ONLY')) THEN
      RAISE EXCEPTION 'RPPS-SPECIALITE: règle diplôme critique absente pour %',v_profession;
    END IF;
    INSERT INTO public.documents_soignants(soignant_id,type_document,s3_cle,nom_fichier,statut_verification,
      valide_depuis,valide_jusqua,verifie_le,resultat_ia,nom_extrait_ia,prenom_extrait_ia,coherence_nom)
    SELECT v_specialiste,drp.type_document,v_specialiste::text||'/documents/fixture.pdf','FIXTURE-SYNTHETIQUE.pdf','VERIFIE',
      current_date,CASE WHEN drp.a_expiration THEN current_date+365 ELSE NULL END,now(),
      CASE WHEN drp.type_document='CARTE_IDENTITE' THEN jsonb_build_object('date_naissance_extraite','1990-01-01') ELSE '{}'::jsonb END,
      'SPECIALITE','Fixture',true
    FROM public.documents_requis_par_profession drp WHERE drp.profession::text=v_profession AND drp.est_critique IS TRUE
      AND drp.type_exercice_requis IN ('TOUS','SALARIE_ONLY') AND drp.type_document NOT IN ('DIPLOME','RPPS_ADELI');
    UPDATE public.soignants SET rpps_verifie=true,rpps_verifie_le=now(),rpps_nom_api='SPECIALITE',
      rpps_prenom_api='Fixture',rpps_profession_api='Infirmier' WHERE id=v_specialiste;
    IF public.fn_documents_ok_pour_mission(v_specialiste,'SALARIE') IS NOT FALSE THEN
      RAISE EXCEPTION 'RPPS-SPECIALITE: RPPS générique a dispensé du diplôme %',v_profession;
    END IF;
    INSERT INTO public.documents_soignants(soignant_id,type_document,s3_cle,nom_fichier,statut_verification,
      valide_depuis,verifie_le,resultat_ia,nom_extrait_ia,prenom_extrait_ia,coherence_nom)
    VALUES(v_specialiste,'DIPLOME',v_specialiste::text||'/documents/diplome.pdf','DIPLOME-FICTIF.pdf','VERIFIE',
      current_date,now(),jsonb_build_object('profession_certifiee','IDE'),'SPECIALITE','Fixture',true)
    RETURNING id INTO v_diplome;
    IF public.fn_documents_ok_pour_mission(v_specialiste,'SALARIE') IS NOT FALSE THEN
      RAISE EXCEPTION 'RPPS-SPECIALITE: diplôme IDE a remplacé le diplôme %',v_profession;
    END IF;
    UPDATE public.documents_soignants SET resultat_ia=jsonb_build_object('profession_certifiee',v_profession),modifie_le=now() WHERE id=v_diplome;
    IF public.fn_documents_ok_pour_mission(v_specialiste,'SALARIE') IS NOT TRUE THEN
      RAISE EXCEPTION 'RPPS-SPECIALITE: diplôme spécialisé % exact refusé',v_profession;
    END IF;
    UPDATE public.documents_soignants SET resultat_ia='{}'::jsonb,modifie_le=now() WHERE id=v_diplome;
    IF public.fn_documents_ok_pour_mission(v_specialiste,'SALARIE') IS NOT FALSE THEN
      RAISE EXCEPTION 'RPPS-SPECIALITE: qualification absente acceptée pour %',v_profession;
    END IF;
    IF (SELECT rpps_verifie FROM public.soignants WHERE id=v_specialiste) IS NOT TRUE THEN
      RAISE EXCEPTION 'RPPS-SPECIALITE: le verdict RPPS a été révoqué';
    END IF;
  END LOOP;
END;
$rpps_diploma$;

-- Cache historique : reproduire l'ancien résultat dérivé sans révoquer le
-- RPPS ni aucune pièce. Même bloc que la migration, avec témoins de non-impact.
CREATE TEMP TABLE rpps_cache_cas(id uuid PRIMARY KEY, attendu boolean NOT NULL, avant jsonb NOT NULL, pieces_md5 text NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE rpps_cache_transports(avant jsonb NOT NULL) ON COMMIT DROP;
DO $cache_fixture$
DECLARE
  cas record;
  sid uuid;
  q bigint := 0;
BEGIN
  FOR cas IN SELECT * FROM (VALUES
    ('IADE',NULL::text,false), ('IBODE','IDE',false),
    ('IADE','IADE',true), ('IBODE','IBODE',true), ('IDE',NULL::text,true)
  ) c(profession,certificat,attendu) LOOP
    sid := gen_random_uuid();
    INSERT INTO public.soignants(id,prenom,nom,email,date_naissance,profession,type_exercice,rpps_verifie,est_compte_test)
    VALUES(sid,'Fixture','CacheSpecialite',sid::text||'@test.local',DATE '1990-01-01',cas.profession::public.type_profession,'SALARIE',false,true);
    INSERT INTO public.documents_soignants(soignant_id,type_document,s3_cle,nom_fichier,statut_verification,
      valide_depuis,valide_jusqua,verifie_le,resultat_ia,nom_extrait_ia,prenom_extrait_ia,coherence_nom)
    SELECT sid,drp.type_document,sid::text||'/documents/fixture.pdf','FIXTURE-CACHE-SYNTHETIQUE.pdf','VERIFIE',
      current_date,CASE WHEN drp.a_expiration THEN current_date+365 ELSE NULL END,now(),
      CASE WHEN drp.type_document='CARTE_IDENTITE' THEN jsonb_build_object('date_naissance_extraite','1990-01-01') ELSE '{}'::jsonb END,
      'CACHESPECIALITE','Fixture',true
    FROM public.documents_requis_par_profession drp WHERE drp.profession::text=cas.profession AND drp.est_critique IS TRUE
      AND drp.type_exercice_requis IN ('TOUS','SALARIE_ONLY') AND drp.type_document NOT IN ('DIPLOME','RPPS_ADELI');
    IF cas.certificat IS NOT NULL THEN
      INSERT INTO public.documents_soignants(soignant_id,type_document,s3_cle,nom_fichier,statut_verification,
        valide_depuis,verifie_le,resultat_ia,nom_extrait_ia,prenom_extrait_ia,coherence_nom)
      VALUES(sid,'DIPLOME',sid::text||'/documents/diplome.pdf','DIPLOME-CACHE-FICTIF.pdf','VERIFIE',
        current_date,now(),jsonb_build_object('profession_certifiee',cas.certificat),'CACHESPECIALITE','Fixture',true);
    END IF;
    UPDATE public.soignants SET rpps_verifie=true,rpps_verifie_le=now(),rpps_nom_api='CACHESPECIALITE',
      rpps_prenom_api='Fixture',rpps_profession_api='Infirmier' WHERE id=sid;
    IF public.fn_documents_ok_pour_mission(sid,'SALARIE') IS DISTINCT FROM cas.attendu THEN
      RAISE EXCEPTION 'RPPS-CACHE: précondition documentaire du témoin incorrecte';
    END IF;
    -- Simulation explicite du seul cache obsolète, pas d'identité officielle.
    UPDATE public.soignants SET tous_documents_valides=true,modifie_le=TIMESTAMPTZ '2001-01-01 00:00:00+00' WHERE id=sid;
    INSERT INTO rpps_cache_cas
    SELECT sid,cas.attendu,to_jsonb(s),(SELECT md5(COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.id)::text,'[]'))
      FROM public.documents_soignants d WHERE d.soignant_id=sid)
    FROM public.soignants s WHERE s.id=sid;
  END LOOP;
  IF to_regclass('net.http_request_queue') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO q;
  END IF;
  INSERT INTO rpps_cache_transports SELECT jsonb_build_object('net',q,
    'email',(SELECT count(*) FROM public.email_queue),'sms',(SELECT count(*) FROM public.sms_envoyes),
    'notifications',(SELECT count(*) FROM public.notifications));
END;
$cache_fixture$;

-- Bloc réel de migration reproduit octet pour octet ; égalité gardée par le
-- test de source document-replacement-rib-toctou-hardening.test.ts.
DO $cache_specialise$
DECLARE
  v_soignant_id uuid;
BEGIN
  FOR v_soignant_id IN
    SELECT s.id
    FROM public.soignants s
    WHERE s.supprime_le IS NULL
      AND s.profession IN ('IADE', 'IBODE')
      AND s.rpps_verifie IS TRUE
      AND s.tous_documents_valides IS TRUE
      AND public.fn_documents_ok_pour_mission(s.id,
        CASE WHEN upper(COALESCE(s.type_exercice, 'SALARIE')) IN ('LIBERAL', 'MIXTE')
          THEN 'LIBERAL' ELSE 'SALARIE' END) IS FALSE
    ORDER BY s.id
  LOOP
    PERFORM public.fn_calculer_tous_documents_valides(v_soignant_id);
  END LOOP;
END;
$cache_specialise$;

DO $cache_assertions$
DECLARE
  q bigint := 0;
  apres jsonb;
BEGIN
  IF (SELECT count(*) FROM rpps_cache_cas) <> 5 THEN RAISE EXCEPTION 'RPPS-CACHE: cinq témoins requis'; END IF;
  IF EXISTS(SELECT 1 FROM rpps_cache_cas c JOIN public.soignants s ON s.id=c.id
    WHERE s.tous_documents_valides IS DISTINCT FROM c.attendu OR s.rpps_verifie IS NOT TRUE
      OR (to_jsonb(s)-'tous_documents_valides'-'modifie_le') IS DISTINCT FROM (c.avant-'tous_documents_valides'-'modifie_le')
      OR (c.attendu AND to_jsonb(s) IS DISTINCT FROM c.avant)
      OR c.pieces_md5 IS DISTINCT FROM (SELECT md5(COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.id)::text,'[]'))
        FROM public.documents_soignants d WHERE d.soignant_id=c.id)) THEN
    RAISE EXCEPTION 'RPPS-CACHE: cache inexact ou preuve/profil hors cache modifié';
  END IF;
  IF to_regclass('net.http_request_queue') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO q;
  END IF;
  apres := jsonb_build_object('net',q,'email',(SELECT count(*) FROM public.email_queue),
    'sms',(SELECT count(*) FROM public.sms_envoyes),'notifications',(SELECT count(*) FROM public.notifications));
  IF apres IS DISTINCT FROM (SELECT avant FROM rpps_cache_transports) THEN
    RAISE EXCEPTION 'RPPS-CACHE: transport/notification produit par le recalcul';
  END IF;
END;
$cache_assertions$;

ROLLBACK;
