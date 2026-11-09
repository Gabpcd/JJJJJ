-- Banc PG17 isolé (B9) : la DPAE couvre les contrats CDDU et VACATION.
-- Vrais corps LIVE (fixture générée depuis supabase/schema/public.sql, md5
-- relus en production le 08/11/2026) des cinq fonctions, puis la vraie
-- migration 20261108223500. Tables minimales, données synthétiques, doublures
-- locales pour net.http_post, vault et auth.uid ; aucune RLS ni trigger de
-- protection : ce banc prouve les réponses et les écritures des cinq
-- fonctions, pas l'interface.
-- Méthode : mêmes appels, mêmes cas, avant puis après la migration ; chaque
-- cas a un résultat attendu fermé pour chaque phase (table « attendus ») :
--   * CDD : déclenché avant et après (inchangé) ;
--   * CDDU, VACATION : non déclenchés avant, déclenchés après ;
--   * REMPLACEMENT_LIBERAL : jamais déclenché ;
--   * témoins hors type (contrat non signé, DPAE déjà faite, rappel hors
--     fenêtre, numéro DPAE saisi) : résultat inchangé.
-- SALARIE n'est pas un type admis par contrats_mission (CHECK LIVE) : il est
-- prouvé par la table de vérité du helper, avec CDD.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'dpae_salarie'
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'DPAE_SALARIE_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
\ir fixtures/dpae-contrats-cddu-vacation-banc.sql

CREATE TEMP TABLE observations (
  phase text, fonction text, cas integer, type_contrat text, contrat_id uuid,
  declenche boolean, detail jsonb, PRIMARY KEY (phase, fonction, cas)
);

CREATE FUNCTION pg_temp.observer(p_phase text, p_num integer) RETURNS void LANGUAGE plpgsql AS $observer$
DECLARE
  c record;
  r jsonb;
  v_contrat uuid;
  v_push boolean;
  v_n bigint;
BEGIN
  PERFORM set_config('banc.phase', p_phase, true);

  -- 1. fn_mes_dpae : liste du soignant, lecture seule.
  PERFORM set_config('request.jwt.claim.sub', 'd9ae0000-0000-4000-8000-0000000000a1', true);
  r := public.fn_mes_dpae();
  IF r->>'success' IS DISTINCT FROM 'true' OR jsonb_typeof(r->'dpae') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'DPAE_BANC_LISTE_EN_ECHEC: % %', p_phase, r;
  END IF;
  INSERT INTO pg_temp.observations
  SELECT p_phase, 'fn_mes_dpae', l.cas, l.type_contrat, pg_temp.banc_id('0002', 0, l.cas),
         EXISTS (SELECT FROM jsonb_array_elements(r->'dpae') e
                  WHERE e->>'contrat_id' = pg_temp.banc_id('0002', 0, l.cas)::text),
         (SELECT e FROM jsonb_array_elements(r->'dpae') e
           WHERE e->>'contrat_id' = pg_temp.banc_id('0002', 0, l.cas)::text)
    FROM pg_temp.banc_cas_liste l;
  -- Rien d'autre n'est listé que les cas observés.
  IF jsonb_array_length(r->'dpae') IS DISTINCT FROM (
       SELECT count(*)::integer FROM pg_temp.observations o
        WHERE o.phase = p_phase AND o.fonction = 'fn_mes_dpae' AND o.declenche) THEN
    RAISE EXCEPTION 'DPAE_BANC_LISTE_ELEMENT_INATTENDU: % %', p_phase, r;
  END IF;

  -- 2. fn_rappel_dpae_quotidien : cron, contexte système.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  r := public.fn_rappel_dpae_quotidien();
  IF r->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'DPAE_BANC_RAPPEL_EN_ECHEC: % %', p_phase, r;
  END IF;
  INSERT INTO pg_temp.observations
  SELECT p_phase, 'fn_rappel_dpae_quotidien', l.cas, l.type_contrat, pg_temp.banc_id('0002', 0, l.cas),
         EXISTS (SELECT FROM net.appels a
                  WHERE a.phase = p_phase
                    AND a.body->>'type_evenement' = 'DPAE_RAPPEL'
                    AND a.body->>'destinataire_id' = 'd9ae0000-0000-4000-8000-0000000000e1'
                    AND a.body->'data'->>'contrat_id' = pg_temp.banc_id('0002', 0, l.cas)::text),
         r
    FROM pg_temp.banc_cas_liste l;
  -- Le compte renvoyé est exactement le nombre de push de rappel de la phase.
  SELECT count(*) INTO v_n FROM net.appels a
   WHERE a.phase = p_phase AND a.body->>'type_evenement' = 'DPAE_RAPPEL';
  IF (r->>'count')::bigint IS DISTINCT FROM v_n
    OR v_n IS DISTINCT FROM (SELECT count(*) FROM pg_temp.observations o
       WHERE o.phase = p_phase AND o.fonction = 'fn_rappel_dpae_quotidien' AND o.declenche)
  THEN
    RAISE EXCEPTION 'DPAE_BANC_RAPPEL_COMPTE_INCOHERENT: % % %', p_phase, r, v_n;
  END IF;

  -- 3. fn_pointer_arrivee : soignant assigné, code de secours (sans GPS).
  PERFORM set_config('request.jwt.claim.sub', 'd9ae0000-0000-4000-8000-0000000000a2', true);
  FOR c IN SELECT * FROM pg_temp.banc_cas_types ORDER BY cas LOOP
    v_contrat := pg_temp.banc_id('0004', p_num, c.cas);
    r := public.fn_pointer_arrivee(pg_temp.banc_id('0003', p_num, c.cas), p_code_arrivee => '2468');
    IF r->>'success' IS DISTINCT FROM 'true' OR r->>'methode' IS DISTINCT FROM 'CODE'
      OR jsonb_typeof(r->'warnings') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'DPAE_BANC_POINTAGE_EN_ECHEC: % % %', p_phase, c.cas, r;
    END IF;
    v_push := EXISTS (SELECT FROM net.appels a
                       WHERE a.phase = p_phase
                         AND a.body->>'type_evenement' = 'DPAE_NON_REGULARISEE_POINTAGE'
                         AND a.body->>'destinataire_id' = 'd9ae0000-0000-4000-8000-0000000000e1'
                         AND a.body->'data'->>'contrat_id' = v_contrat::text);
    INSERT INTO pg_temp.observations VALUES (
      p_phase, 'fn_pointer_arrivee', c.cas, c.type_contrat, v_contrat,
      EXISTS (SELECT FROM jsonb_array_elements(r->'warnings') w
               WHERE w->>'code' = 'DPAE_NON_REGULARISEE'),
      r);
    -- L'avertissement et le push établissement vont toujours ensemble.
    IF v_push IS DISTINCT FROM (SELECT o.declenche FROM pg_temp.observations o
         WHERE o.phase = p_phase AND o.fonction = 'fn_pointer_arrivee' AND o.cas = c.cas) THEN
      RAISE EXCEPTION 'DPAE_BANC_POINTAGE_PUSH_DESACCORDE: % %', p_phase, c.cas;
    END IF;
    -- Le pointage lui-même a lieu dans tous les cas.
    IF (SELECT count(*) FROM public.presences p
         WHERE p.mission_id = pg_temp.banc_id('0003', p_num, c.cas)
           AND p.soignant_id = 'd9ae0000-0000-4000-8000-0000000000a2'
           AND p.methode_pointage_arrivee = 'CODE') <> 1
      OR (SELECT m.statut FROM public.missions m WHERE m.id = pg_temp.banc_id('0003', p_num, c.cas))
         IS DISTINCT FROM 'EN_COURS' THEN
      RAISE EXCEPTION 'DPAE_BANC_POINTAGE_NON_ENREGISTRE: % %', p_phase, c.cas;
    END IF;
  END LOOP;

  -- 4. fn_annuler_candidature_soignant : candidature acceptée, contrat signé.
  PERFORM set_config('request.jwt.claim.sub', 'd9ae0000-0000-4000-8000-0000000000a3', true);
  FOR c IN SELECT * FROM pg_temp.banc_cas_types WHERE cas <= 4 ORDER BY cas LOOP
    v_contrat := pg_temp.banc_id('0007', p_num, c.cas);
    r := public.fn_annuler_candidature_soignant(pg_temp.banc_id('0006', p_num, c.cas),
           'URGENCE_PERSONNELLE', 'Motif de banc suffisamment long', NULL);
    IF r->>'success' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'DPAE_BANC_ANNULATION_EN_ECHEC: % % %', p_phase, c.cas, r;
    END IF;
    -- Notifications établissement inchangées : un email et un push par annulation.
    IF (SELECT count(*) FROM public.externalisation_actions x
         WHERE x.source_id = pg_temp.banc_id('0006', p_num, c.cas)
           AND x.type_action IN ('EMAIL_NOTIF', 'PUSH_NOTIF')) <> 2
      OR (SELECT count(*) FROM public.externalisation_actions x
           WHERE x.source_id = pg_temp.banc_id('0006', p_num, c.cas)
             AND x.type_action = 'DPAE_ANNULATION') > 1 THEN
      RAISE EXCEPTION 'DPAE_BANC_ANNULATION_FILE_INATTENDUE: % %', p_phase, c.cas;
    END IF;
    INSERT INTO pg_temp.observations VALUES (
      p_phase, 'fn_annuler_candidature_soignant', c.cas, c.type_contrat, v_contrat,
      EXISTS (SELECT FROM public.externalisation_actions x
               WHERE x.type_action = 'DPAE_ANNULATION'
                 AND x.source = 'ANNULATION_MISSION'
                 AND x.source_id = pg_temp.banc_id('0006', p_num, c.cas)
                 AND x.payload->>'contrat_id' = v_contrat::text
                 AND x.payload->>'mission_id' = pg_temp.banc_id('0005', p_num, c.cas)::text
                 AND x.payload->>'motif' = 'ANNULATION_SOIGNANT'
                 AND x.payload->>'echeance_legale_h' = '48'),
      r);
  END LOOP;

  -- 5. dec_email_contrat_signe_complet : passage à SIGNE_COMPLET (trigger).
  PERFORM set_config('request.jwt.claim.sub', '', true);
  UPDATE public.contrats_mission SET statut = 'SIGNE_COMPLET'
   WHERE id IN (SELECT pg_temp.banc_id('0009', p_num, t.cas)
                  FROM pg_temp.banc_cas_types t WHERE t.cas <= 4);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 4 THEN RAISE EXCEPTION 'DPAE_BANC_SIGNATURE_LIGNES: % %', p_phase, v_n; END IF;
  FOR c IN SELECT * FROM pg_temp.banc_cas_types WHERE cas <= 4 ORDER BY cas LOOP
    v_contrat := pg_temp.banc_id('0009', p_num, c.cas);
    IF (SELECT count(*) FROM public.journaux_audit j
         WHERE j.id_ressource = v_contrat
           AND j.details->>'evenement' = 'CONTRAT_SIGNE_COMPLET_AUTO') <> 1
      OR (SELECT count(*) FROM net.appels a
           WHERE a.phase = p_phase AND a.body->>'type' = 'CONTRAT_SIGNE'
             AND a.body->'data'->>'numero_contrat' = 'BANC-0009-' || p_num || c.cas) <> 2 THEN
      RAISE EXCEPTION 'DPAE_BANC_SIGNATURE_EFFETS: % %', p_phase, c.cas;
    END IF;
    INSERT INTO pg_temp.observations
    SELECT p_phase, 'dec_email_contrat_signe_complet', c.cas, c.type_contrat, v_contrat,
           (j.details->>'dpae_requise')::boolean, j.details
      FROM public.journaux_audit j
     WHERE j.id_ressource = v_contrat
       AND j.details->>'evenement' = 'CONTRAT_SIGNE_COMPLET_AUTO';
  END LOOP;

  PERFORM set_config('request.jwt.claim.sub', '', true);
END $observer$;

-- Résultat attendu de chaque cas, avant et après. Toute autre valeur échoue.
CREATE TEMP TABLE attendus (
  fonction text, cas integer, type_contrat text, avant boolean, apres boolean,
  PRIMARY KEY (fonction, cas)
);
INSERT INTO attendus VALUES
  ('fn_mes_dpae', 1, 'CDD', true, true),
  ('fn_mes_dpae', 2, 'CDDU', false, true),
  ('fn_mes_dpae', 3, 'VACATION', false, true),
  ('fn_mes_dpae', 4, 'REMPLACEMENT_LIBERAL', false, false),
  ('fn_mes_dpae', 5, 'CDDU', false, false),               -- contrat non signé
  ('fn_mes_dpae', 6, 'VACATION', false, true),            -- DPAE déjà faite : listée
  ('fn_mes_dpae', 7, 'CDD', true, true),
  ('fn_rappel_dpae_quotidien', 1, 'CDD', true, true),
  ('fn_rappel_dpae_quotidien', 2, 'CDDU', false, true),
  ('fn_rappel_dpae_quotidien', 3, 'VACATION', false, true),
  ('fn_rappel_dpae_quotidien', 4, 'REMPLACEMENT_LIBERAL', false, false),
  ('fn_rappel_dpae_quotidien', 5, 'CDDU', false, false),  -- contrat non signé
  ('fn_rappel_dpae_quotidien', 6, 'VACATION', false, false), -- DPAE déjà faite
  ('fn_rappel_dpae_quotidien', 7, 'CDD', false, false),   -- signé il y a 10 jours
  ('fn_pointer_arrivee', 1, 'CDD', true, true),
  ('fn_pointer_arrivee', 2, 'CDDU', false, true),
  ('fn_pointer_arrivee', 3, 'VACATION', false, true),
  ('fn_pointer_arrivee', 4, 'REMPLACEMENT_LIBERAL', false, false),
  ('fn_pointer_arrivee', 5, 'CDDU', false, false),        -- numéro DPAE saisi
  ('fn_annuler_candidature_soignant', 1, 'CDD', true, true),
  ('fn_annuler_candidature_soignant', 2, 'CDDU', false, true),
  ('fn_annuler_candidature_soignant', 3, 'VACATION', false, true),
  ('fn_annuler_candidature_soignant', 4, 'REMPLACEMENT_LIBERAL', false, false),
  ('dec_email_contrat_signe_complet', 1, 'CDD', true, true),
  ('dec_email_contrat_signe_complet', 2, 'CDDU', false, true),
  ('dec_email_contrat_signe_complet', 3, 'VACATION', false, true),
  ('dec_email_contrat_signe_complet', 4, 'REMPLACEMENT_LIBERAL', false, false);

CREATE FUNCTION pg_temp.verifier_phase(p_phase text) RETURNS void LANGUAGE plpgsql AS $verifier$
DECLARE r record;
BEGIN
  IF (SELECT count(*) FROM pg_temp.observations o WHERE o.phase = p_phase) <> 27
    OR (SELECT count(*) FROM pg_temp.attendus) <> 27 THEN
    RAISE EXCEPTION 'DPAE_BANC_OBSERVATIONS_INCOMPLETES: %', p_phase;
  END IF;
  FOR r IN
    SELECT a.*, o.declenche, o.type_contrat AS type_observe
      FROM pg_temp.attendus a
      LEFT JOIN pg_temp.observations o
        ON o.phase = p_phase AND o.fonction = a.fonction AND o.cas = a.cas
  LOOP
    IF r.type_observe IS DISTINCT FROM r.type_contrat
      -- Parenthèses : sans elles, le THEN du CASE clôturerait la condition du IF.
      OR r.declenche IS DISTINCT FROM (CASE WHEN p_phase = 'avant' THEN r.avant ELSE r.apres END)
    THEN
      RAISE EXCEPTION 'DPAE_BANC_RESULTAT_INATTENDU: % % cas % (%) : %',
        p_phase, r.fonction, r.cas, r.type_contrat, r.declenche;
    END IF;
  END LOOP;
END $verifier$;

CREATE TEMP TABLE attributs_avant AS
  SELECT p.oid, p.oid::regprocedure::text AS signature, p.proowner, p.proacl::text AS acl,
         p.prosecdef, p.provolatile, p.proconfig, md5(p.prosrc) AS ancien_md5
    FROM pg_proc p
   WHERE p.oid IN ('public.fn_mes_dpae()'::regprocedure,
                   'public.fn_rappel_dpae_quotidien()'::regprocedure,
                   'public.fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text)'::regprocedure,
                   'public.fn_annuler_candidature_soignant(uuid,text,text,text)'::regprocedure,
                   'public.dec_email_contrat_signe_complet()'::regprocedure);
CREATE TEMP TABLE inventaire_avant AS SELECT * FROM private.security_definer_inventory;

SELECT pg_temp.observer('avant', 1);
-- Rouge historique : CDDU et VACATION exclus des cinq fonctions avant la migration.
SELECT pg_temp.verifier_phase('avant');

-- La vraie migration, jamais une recopie.
\ir ../../supabase/migrations/20261108223500_dpae_contrats_cddu_vacation.sql

SELECT pg_temp.observer('apres', 2);
SELECT pg_temp.verifier_phase('apres');

DO $apres$
DECLARE
  o jsonb;
  nb integer;
  refuse boolean;
  v_liste jsonb;
BEGIN
  -- 1. Comportements conservés hors liste de types.
  -- Liste : les objets des contrats CDD sont identiques avant et après.
  IF EXISTS (
    SELECT FROM pg_temp.observations av JOIN pg_temp.observations ap USING (fonction, cas)
     WHERE av.phase = 'avant' AND ap.phase = 'apres' AND av.fonction = 'fn_mes_dpae'
       AND av.declenche AND av.detail IS DISTINCT FROM ap.detail)
  THEN RAISE EXCEPTION 'DPAE_BANC_LISTE_CDD_MODIFIEE'; END IF;
  -- Rappel : un push avant (CDD), trois après (CDD, CDDU, VACATION).
  IF (SELECT DISTINCT o2.detail->>'count' FROM pg_temp.observations o2
       WHERE o2.phase = 'avant' AND o2.fonction = 'fn_rappel_dpae_quotidien') IS DISTINCT FROM '1'
    OR (SELECT DISTINCT o2.detail->>'count' FROM pg_temp.observations o2
         WHERE o2.phase = 'apres' AND o2.fonction = 'fn_rappel_dpae_quotidien') IS DISTINCT FROM '3'
  THEN RAISE EXCEPTION 'DPAE_BANC_RAPPEL_COMPTES'; END IF;
  -- Pointage : réponses identiques avant/après sauf CDDU et VACATION, qui
  -- reçoivent exactement la réponse du CDD.
  IF EXISTS (
    SELECT FROM pg_temp.observations av JOIN pg_temp.observations ap USING (fonction, cas)
     WHERE av.phase = 'avant' AND ap.phase = 'apres' AND av.fonction = 'fn_pointer_arrivee'
       AND av.cas IN (1, 4, 5) AND av.detail IS DISTINCT FROM ap.detail)
    OR (SELECT count(DISTINCT o2.detail) FROM pg_temp.observations o2
         WHERE o2.phase = 'apres' AND o2.fonction = 'fn_pointer_arrivee' AND o2.cas IN (1, 2, 3)) <> 1
    OR (SELECT jsonb_array_length(o2.detail->'warnings') FROM pg_temp.observations o2
         WHERE o2.phase = 'apres' AND o2.fonction = 'fn_pointer_arrivee' AND o2.cas = 2) <> 1
  THEN RAISE EXCEPTION 'DPAE_BANC_POINTAGE_REPONSE_MODIFIEE'; END IF;
  -- Annulation : même réponse pour tous les types, avant et après.
  IF (SELECT count(DISTINCT o2.detail) FROM pg_temp.observations o2
       WHERE o2.fonction = 'fn_annuler_candidature_soignant') <> 1
  THEN RAISE EXCEPTION 'DPAE_BANC_ANNULATION_REPONSE_MODIFIEE'; END IF;
  -- Audit de signature : seule dpae_requise suit le type ; type_contrat présent.
  IF EXISTS (
    SELECT FROM pg_temp.observations o2
     WHERE o2.fonction = 'dec_email_contrat_signe_complet'
       AND (o2.detail->>'type_contrat' IS DISTINCT FROM o2.type_contrat
            OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(o2.detail) k)
               IS DISTINCT FROM ARRAY['dpae_requise', 'evenement', 'mode_signature', 'numero_contrat', 'type_contrat']))
  THEN RAISE EXCEPTION 'DPAE_BANC_AUDIT_SIGNATURE_MODIFIE'; END IF;

  -- 2. Helper : table de vérité (CDD et SALARIE inchangés).
  IF public.fn_type_contrat_salarie('CDD') IS NOT TRUE
    OR public.fn_type_contrat_salarie('SALARIE') IS NOT TRUE
    OR public.fn_type_contrat_salarie('CDDU') IS NOT TRUE
    OR public.fn_type_contrat_salarie('VACATION') IS NOT TRUE
    OR public.fn_type_contrat_salarie('REMPLACEMENT_LIBERAL') IS NOT FALSE
    OR public.fn_type_contrat_salarie('LIBERAL') IS NOT FALSE
    OR public.fn_type_contrat_salarie(NULL) IS NOT NULL
  THEN RAISE EXCEPTION 'DPAE_BANC_HELPER_TABLE_DE_VERITE'; END IF;

  -- 3. Attributs, droits et inventaire.
  IF EXISTS (
    SELECT FROM pg_temp.attributs_avant a JOIN pg_proc p ON p.oid = a.oid
     WHERE a.proowner IS DISTINCT FROM p.proowner OR a.acl IS DISTINCT FROM p.proacl::text
       OR a.prosecdef IS DISTINCT FROM p.prosecdef OR a.provolatile IS DISTINCT FROM p.provolatile
       OR a.proconfig IS DISTINCT FROM p.proconfig OR md5(p.prosrc) = a.ancien_md5
       OR has_function_privilege('anon', p.oid, 'EXECUTE'))
    OR (SELECT count(*) FROM pg_temp.attributs_avant a JOIN pg_proc p ON p.oid = a.oid) <> 5
  THEN RAISE EXCEPTION 'DPAE_BANC_ATTRIBUTS_OU_DROITS_MODIFIES'; END IF;
  SELECT count(*) INTO nb
    FROM pg_temp.inventaire_avant i
    JOIN private.security_definer_inventory n USING (signature)
    JOIN pg_proc p ON p.oid = to_regprocedure('public.' || i.signature);
  IF nb <> 3 OR EXISTS (
    SELECT FROM pg_temp.inventaire_avant i
    JOIN private.security_definer_inventory n USING (signature)
    JOIN pg_proc p ON p.oid = to_regprocedure('public.' || i.signature)
    WHERE n.categorie IS DISTINCT FROM i.categorie OR n.justification IS DISTINCT FROM i.justification
      OR n.definition_md5 IS DISTINCT FROM md5(p.prosrc)
      OR n.definition_md5 IS NOT DISTINCT FROM i.definition_md5)
    OR (SELECT count(*) FROM private.security_definer_inventory) <> 3
  THEN RAISE EXCEPTION 'DPAE_BANC_INVENTAIRE_INCOHERENT: %', nb; END IF;

  -- 4. Appel réel par le rôle authenticated : la RPC (SECURITY DEFINER)
  -- appelle le helper ; anon n'exécute ni l'une ni l'autre.
  PERFORM set_config('request.jwt.claim.sub', 'd9ae0000-0000-4000-8000-0000000000a1', true);
  v_liste := public.fn_mes_dpae();
  EXECUTE 'SET LOCAL ROLE authenticated';
  o := public.fn_mes_dpae();
  IF public.fn_type_contrat_salarie('CDDU') IS NOT TRUE THEN
    RAISE EXCEPTION 'DPAE_BANC_HELPER_REFUSE_A_AUTHENTICATED';
  END IF;
  EXECUTE 'RESET ROLE';
  IF o IS DISTINCT FROM v_liste OR jsonb_array_length(o->'dpae') <> 5 THEN
    RAISE EXCEPTION 'DPAE_BANC_LISTE_AUTHENTICATED: %', o;
  END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  refuse := false;
  BEGIN
    PERFORM public.fn_type_contrat_salarie('CDD');
  EXCEPTION WHEN insufficient_privilege THEN refuse := true;
  END;
  EXECUTE 'RESET ROLE';
  IF NOT refuse THEN RAISE EXCEPTION 'DPAE_BANC_HELPER_ACCESSIBLE_A_ANON'; END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  refuse := false;
  BEGIN
    PERFORM public.fn_mes_dpae();
  EXCEPTION WHEN insufficient_privilege THEN refuse := true;
  END;
  EXECUTE 'RESET ROLE';
  IF NOT refuse THEN RAISE EXCEPTION 'DPAE_BANC_LISTE_ACCESSIBLE_A_ANON'; END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $apres$;

SELECT jsonb_build_object('postgres', 17, 'liveBodiesLoaded', true, 'realMigrationLoaded', true,
  'cas', (SELECT count(*) FROM attendus),
  'nouveauxCasDeclenches', (SELECT count(*) FROM attendus WHERE apres AND NOT avant),
  'casInchanges', (SELECT count(*) FROM attendus WHERE apres = avant),
  'remplacementLiberalJamaisDeclenche', true, 'aclProprietaireInventairePreserves', true,
  'transactionEnd', 'ROLLBACK') AS dpae_contrats_cddu_vacation_proof;
ROLLBACK;
