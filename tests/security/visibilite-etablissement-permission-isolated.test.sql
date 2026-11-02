-- Banc PG17 isolé B5b : visibilité établissement par permission.
-- Vrais corps LIVE (fixture extraite de supabase/schema/public.sql, md5 relus
-- en production le 02/11/2026) des gardes d'identité et des trois RPC, puis la
-- vraie migration. Tables minimales, données synthétiques, aucune RLS :
-- ce banc prouve les réponses des RPC par rôle, pas l'interface ni la
-- lecture directe des tables (étage RLS hors périmètre, voir le corps de PR).
-- Méthode : mêmes appels, mêmes acteurs, avant puis après la migration ; la
-- seule différence admise est la liste fermée « attendus » ci-dessous.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'visibilite_etab_permission'
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
\ir fixtures/visibilite-etablissement-permission-banc.sql

CREATE TEMP TABLE acteurs (nom text PRIMARY KEY, uid uuid);
INSERT INTO acteurs VALUES
  ('admin_plateforme', 'b5b00000-0000-4000-8000-0000000000a1'),
  ('proprietaire', 'b5b00000-0000-4000-8000-0000000000b1'),
  ('admin_groupe', 'b5b00000-0000-4000-8000-0000000000b2'),
  ('rh', 'b5b00000-0000-4000-8000-0000000000b3'),
  ('pointage_only', 'b5b00000-0000-4000-8000-0000000000b4'),
  ('lecture_seule', 'b5b00000-0000-4000-8000-0000000000b5'),
  ('proprietaire_historique', 'b5b00000-0000-4000-8000-0000000000c1'),
  ('membre_autre_etab', 'b5b00000-0000-4000-8000-0000000000d1'),
  ('soignant_affecte', 'b5b00000-0000-4000-8000-0000000000f1'),
  ('soignant_tiers', 'b5b00000-0000-4000-8000-0000000000f2'),
  ('sans_identite', NULL);
CREATE TEMP TABLE observations (
  phase text, acteur text, rpc text, resultat jsonb, PRIMARY KEY (phase, acteur, rpc)
);
CREATE FUNCTION pg_temp.observer(p_phase text) RETURNS void LANGUAGE plpgsql AS $observer$
DECLARE a record;
BEGIN
  FOR a IN SELECT * FROM pg_temp.acteurs ORDER BY nom LOOP
    PERFORM set_config('request.jwt.claim.sub', COALESCE(a.uid::text, ''), true);
    INSERT INTO pg_temp.observations VALUES
      (p_phase, a.nom, 'etat_m1', public.fn_etat_pointage_mission('b5b00000-0000-4000-8000-00000000a001')),
      (p_phase, a.nom, 'etat_ml', public.fn_etat_pointage_mission('b5b00000-0000-4000-8000-00000000a003')),
      (p_phase, a.nom, 'stats', public.fn_stats_dashboard_etablissement()),
      (p_phase, a.nom, 'profil', public.fn_mon_etablissement_complet());
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $observer$;

-- Différences attendues, et seulement elles. « null » : la clé reste présente
-- et vaut null ; « refus » : la réponse entière devient l'erreur existante.
CREATE TEMP TABLE attendus (acteur text, rpc text, cle text, effet text);
INSERT INTO attendus VALUES
  ('lecture_seule', 'etat_m1', 'code_pointage_actif', 'null'),
  ('rh', 'stats', 'commissions_cumulees', 'null'),
  ('rh', 'stats', 'commissions_impayees', 'null'),
  ('pointage_only', 'stats', 'commissions_cumulees', 'null'),
  ('pointage_only', 'stats', 'commissions_impayees', 'null'),
  ('pointage_only', 'stats', 'candidatures_recentes', 'null'),
  -- RH d'un autre établissement : ses propres montants (0) suivent la même règle.
  ('membre_autre_etab', 'stats', 'commissions_cumulees', 'null'),
  ('membre_autre_etab', 'stats', 'commissions_impayees', 'null'),
  ('rh', 'profil', 'stripe_customer_id', 'null'),
  ('rh', 'profil', 'stripe_account_id', 'null'),
  ('rh', 'profil', 'iban_last4', 'null'),
  ('pointage_only', 'profil', 'stripe_customer_id', 'null'),
  ('pointage_only', 'profil', 'stripe_account_id', 'null'),
  ('pointage_only', 'profil', 'iban_last4', 'null'),
  ('soignant_tiers', 'etat_m1', NULL, 'refus'),
  ('soignant_tiers', 'etat_ml', NULL, 'refus'),
  ('sans_identite', 'etat_m1', NULL, 'refus'),
  ('sans_identite', 'etat_ml', NULL, 'refus');

SELECT pg_temp.observer('avant');

-- Rouge historique : chaque fuite corrigée existe avant la migration.
DO $avant$
DECLARE o jsonb;
BEGIN
  IF (SELECT count(*) FROM observations WHERE phase = 'avant') <> 44 THEN
    RAISE EXCEPTION 'VISIBILITE_ETAB_OBSERVATIONS_AVANT_INCOMPLETES';
  END IF;
  SELECT resultat INTO o FROM observations WHERE phase='avant' AND acteur='lecture_seule' AND rpc='etat_m1';
  IF o->>'code_pointage_actif' IS DISTINCT FROM '123456' THEN RAISE EXCEPTION 'VISIBILITE_ETAB_FUITE_CODE_NON_REPRODUITE'; END IF;
  SELECT resultat INTO o FROM observations WHERE phase='avant' AND acteur='rh' AND rpc='stats';
  IF (o->>'commissions_impayees')::numeric IS DISTINCT FROM 12.5 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_FUITE_FINANCES_NON_REPRODUITE'; END IF;
  SELECT resultat INTO o FROM observations WHERE phase='avant' AND acteur='pointage_only' AND rpc='stats';
  IF jsonb_array_length(o->'candidatures_recentes') <> 1
    OR o->'candidatures_recentes'->0->>'soignant_nom' IS DISTINCT FROM 'Bruno Candidat'
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_FUITE_CANDIDATS_NON_REPRODUITE'; END IF;
  SELECT resultat INTO o FROM observations WHERE phase='avant' AND acteur='pointage_only' AND rpc='profil';
  IF o->>'iban_last4' IS DISTINCT FROM '0042' OR o->>'stripe_customer_id' IS DISTINCT FROM 'client-fixture-e'
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_FUITE_PAIEMENT_NON_REPRODUITE'; END IF;
  SELECT resultat INTO o FROM observations WHERE phase='avant' AND acteur='soignant_tiers' AND rpc='etat_m1';
  IF o ? 'error' OR jsonb_array_length(o->'segments') <> 1 OR o->>'intitule' IS DISTINCT FROM 'Nuit IDE'
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_FUITE_LOGIQUE_NULL_NON_REPRODUITE'; END IF;
END $avant$;

CREATE TEMP TABLE attributs_avant AS
  SELECT p.oid, p.oid::regprocedure::text AS signature, p.proowner, p.proacl, p.prosecdef,
         p.provolatile, p.proconfig, md5(p.prosrc) AS ancien_md5
  FROM pg_proc p
  WHERE p.oid IN ('public.fn_etat_pointage_mission(uuid)'::regprocedure,
                  'public.fn_stats_dashboard_etablissement()'::regprocedure,
                  'public.fn_mon_etablissement_complet()'::regprocedure);
CREATE TEMP TABLE inventaire_avant AS SELECT * FROM private.security_definer_inventory;
CREATE TEMP TABLE commentaires_avant AS
  SELECT objoid, description FROM pg_description WHERE objoid IN (SELECT oid FROM attributs_avant);

-- La vraie migration, jamais une recopie.
\ir ../../supabase/migrations/20261102210943_visibilite_etablissement_par_permission.sql

SELECT pg_temp.observer('apres');

DO $apres$
DECLARE
  r record; attendu jsonb; m record; o jsonb; nb integer;
BEGIN
  IF (SELECT count(*) FROM observations WHERE phase = 'apres') <> 44 THEN
    RAISE EXCEPTION 'VISIBILITE_ETAB_OBSERVATIONS_APRES_INCOMPLETES';
  END IF;
  -- 1. Toute réponse est identique, hors différences attendues.
  FOR r IN
    SELECT av.acteur, av.rpc, av.resultat AS avant, ap.resultat AS apres
    FROM observations av JOIN observations ap USING (acteur, rpc)
    WHERE av.phase = 'avant' AND ap.phase = 'apres'
  LOOP
    attendu := r.avant;
    FOR m IN SELECT * FROM attendus a WHERE a.acteur = r.acteur AND a.rpc = r.rpc LOOP
      IF m.effet = 'refus' THEN
        attendu := '{"error":"Accès interdit"}'::jsonb;
      ELSE
        IF NOT (r.avant ? m.cle) OR jsonb_typeof(r.avant -> m.cle) = 'null' THEN
          RAISE EXCEPTION 'VISIBILITE_ETAB_MASQUE_SANS_DONNEE_AVANT: % % %', r.acteur, r.rpc, m.cle;
        END IF;
        attendu := jsonb_set(attendu, ARRAY[m.cle], 'null'::jsonb);
      END IF;
    END LOOP;
    IF r.apres IS DISTINCT FROM attendu THEN
      RAISE EXCEPTION 'VISIBILITE_ETAB_REPONSE_INATTENDUE: % % avant=% apres=%', r.acteur, r.rpc, r.avant, r.apres;
    END IF;
  END LOOP;

  -- 2. Les rôles habilités gardent leurs données (preuve positive, pas seulement un diff).
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'etat_m1' AND resultat->>'code_pointage_actif' = '123456'
    AND acteur IN ('admin_plateforme', 'proprietaire', 'admin_groupe', 'rh', 'pointage_only');
  IF nb <> 5 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_CODE_PERDU_POUR_HABILITE'; END IF;
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'etat_ml' AND resultat->>'code_pointage_actif' = '654321'
    AND acteur IN ('admin_plateforme', 'proprietaire_historique');
  IF nb <> 2 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_CODE_PERDU_POUR_HISTORIQUE'; END IF;
  SELECT resultat INTO o FROM observations WHERE phase='apres' AND acteur='lecture_seule' AND rpc='etat_m1';
  IF o ? 'error' OR o->'est_etab' IS DISTINCT FROM 'true'::jsonb
    OR jsonb_typeof(o->'code_pointage_actif') IS DISTINCT FROM 'null'
    OR jsonb_array_length(o->'segments') <> 1
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_LECTURE_SEULE_ETAT_INCOMPLET'; END IF;
  SELECT resultat INTO o FROM observations WHERE phase='apres' AND acteur='soignant_affecte' AND rpc='etat_m1';
  IF o ? 'error' OR jsonb_typeof(o->'code_pointage_actif') IS DISTINCT FROM 'null'
    OR jsonb_typeof(o->'est_etab') IS DISTINCT FROM 'null' OR jsonb_array_length(o->'segments') <> 1
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_SOIGNANT_AFFECTE_MODIFIE'; END IF;
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'stats'
    AND (resultat->>'commissions_impayees')::numeric = CASE WHEN acteur = 'proprietaire_historique' THEN 30 ELSE 12.5 END
    AND (resultat->>'commissions_cumulees')::numeric = CASE WHEN acteur = 'proprietaire_historique' THEN 25 ELSE 30.42 END
    AND acteur IN ('proprietaire', 'admin_groupe', 'lecture_seule', 'proprietaire_historique');
  IF nb <> 4 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_FINANCES_PERDUES_POUR_HABILITE'; END IF;
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'stats' AND jsonb_array_length(resultat->'candidatures_recentes') = 1
    AND acteur IN ('proprietaire', 'admin_groupe', 'rh', 'lecture_seule');
  IF nb <> 4 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_CANDIDATS_PERDUS_POUR_HABILITE'; END IF;
  -- Compteur sans montant volontairement conservé pour tous les membres (voir PR).
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'stats' AND (resultat->>'nb_factures_impayees')::integer = 1
    AND acteur IN ('proprietaire', 'admin_groupe', 'rh', 'pointage_only', 'lecture_seule');
  IF nb <> 5 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_COMPTEUR_FACTURES_MODIFIE'; END IF;
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'profil'
    AND resultat->>'iban_last4' = CASE WHEN acteur = 'proprietaire_historique' THEN '0077' ELSE '0042' END
    AND resultat->>'stripe_customer_id' IS NOT NULL AND resultat->>'stripe_account_id' IS NOT NULL
    AND acteur IN ('proprietaire', 'admin_groupe', 'lecture_seule', 'proprietaire_historique');
  IF nb <> 4 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_PAIEMENT_PERDU_POUR_HABILITE'; END IF;
  -- rib_s3_key reste servi à tous les membres (le masquer afficherait « Aucun RIB fourni »).
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'profil' AND resultat->>'rib_s3_key' = 'e1/rib-fixture.pdf'
    AND acteur IN ('proprietaire', 'admin_groupe', 'rh', 'pointage_only', 'lecture_seule');
  IF nb <> 5 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_RIB_MODIFIE'; END IF;
  SELECT count(*) INTO nb FROM observations
  WHERE phase = 'apres' AND rpc = 'profil' AND resultat ? 'stripe_customer_id'
    AND resultat ? 'stripe_account_id' AND resultat ? 'iban_last4' AND resultat ? 'rib_s3_key'
    AND acteur IN ('proprietaire', 'admin_groupe', 'rh', 'pointage_only', 'lecture_seule', 'proprietaire_historique');
  IF nb <> 6 THEN RAISE EXCEPTION 'VISIBILITE_ETAB_CLES_PROFIL_RETIREES'; END IF;

  -- 3. Attributs, droits, commentaire et inventaire.
  IF EXISTS (
    SELECT FROM attributs_avant a JOIN pg_proc p ON p.oid = a.oid
    WHERE a.proowner IS DISTINCT FROM p.proowner OR a.proacl IS DISTINCT FROM p.proacl
      OR a.prosecdef IS DISTINCT FROM p.prosecdef OR a.provolatile IS DISTINCT FROM p.provolatile
      OR a.proconfig IS DISTINCT FROM p.proconfig OR md5(p.prosrc) = a.ancien_md5
      OR has_function_privilege('anon', p.oid, 'EXECUTE')
      OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
      OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
  ) OR (SELECT count(*) FROM attributs_avant) <> 3
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_ATTRIBUTS_OU_DROITS_MODIFIES'; END IF;
  IF EXISTS (
    SELECT FROM commentaires_avant c
    WHERE NOT EXISTS (SELECT FROM pg_description d WHERE d.objoid = c.objoid AND d.description = c.description)
  ) OR (SELECT count(*) FROM commentaires_avant) <> 1
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_COMMENTAIRE_PERDU'; END IF;
  IF EXISTS (
    SELECT FROM inventaire_avant i
    JOIN private.security_definer_inventory n USING (signature)
    JOIN attributs_avant a ON a.signature = i.signature
    JOIN pg_proc p ON p.oid = a.oid
    WHERE n.categorie IS DISTINCT FROM i.categorie OR n.justification IS DISTINCT FROM i.justification
      OR n.definition_md5 IS DISTINCT FROM md5(p.prosrc)
  ) OR (SELECT count(*) FROM private.security_definer_inventory) <> 3
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_INVENTAIRE_INCOHERENT'; END IF;
END $apres$;

SELECT jsonb_build_object('postgres', 17, 'liveBodiesLoaded', true, 'realMigrationLoaded', true,
  'acteurs', (SELECT count(*) FROM acteurs), 'reponsesComparees', 44,
  'differencesAttendues', (SELECT count(*) FROM attendus),
  'fuitesReproduitesAvant', 5, 'habilitesInchanges', true,
  'aclProprietaireInventairePreserves', true, 'transactionEnd', 'ROLLBACK') AS visibilite_etablissement_proof;
ROLLBACK;
