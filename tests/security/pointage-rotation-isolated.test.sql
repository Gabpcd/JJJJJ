-- Banc PG17 isolé de rotation du code de pointage.
-- Vraies fonctions complètes, tirages reproductibles avec setseed ; random()
-- n'est ni remplacé ni simulé. Tables minimales : ne prouve pas tous les triggers
-- métier de production, l'interface, la caméra ou un téléphone physique.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'pointage_rotation'
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'POINTAGE_ROTATION_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
-- Même corps que le helper canonique du schéma, sans modification de l'arrondi.
CREATE FUNCTION public.fn_arrondir_quart_heure(p_ts timestamptz) RETURNS timestamptz
LANGUAGE sql IMMUTABLE SET search_path TO 'public', 'extensions' AS $$
  SELECT date_trunc('hour', p_ts) +
    INTERVAL '15 minutes' * ROUND(EXTRACT(MINUTE FROM p_ts) / 15.0);
$$;
CREATE TABLE public.missions (
  id uuid PRIMARY KEY, soignant_assigne_id uuid, code_pointage_actif text,
  prochain_type_scan text, nb_scans smallint, statut text,
  code_pointage_hmac text, modifie_le timestamptz
);
CREATE TABLE public.contrats_mission (id uuid DEFAULT gen_random_uuid(), mission_id uuid, statut text);
CREATE TABLE public.mission_creneaux (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid,
  debut timestamptz, fin timestamptz, est_pause boolean DEFAULT false,
  ordre integer, type_creneau text
);
CREATE TABLE public.scans_pointage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid,
  code_saisi text, numero_scan smallint, type_scan text, scanne_le timestamptz,
  horodatage_arrondi timestamptz, creneau_effectif_id uuid,
  est_en_avance boolean, validation_etab_requise boolean,
  latitude numeric, longitude numeric, precision_gps_m numeric,
  id_terminal text, ip_address inet
);
CREATE TABLE public.presences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid,
  pointage_arrivee_le timestamptz, pointage_depart_le timestamptz,
  arrivee_lat numeric, arrivee_lng numeric, arrivee_precision_gps_m numeric,
  arrivee_id_terminal text, methode_pointage_arrivee text,
  depart_lat numeric, depart_lng numeric, depart_precision_gps_m numeric,
  methode_pointage_depart text, heures_reelles numeric, modifie_le timestamptz
);
CREATE TABLE private.security_definer_inventory (
  signature text PRIMARY KEY, categorie text, definition_md5 text,
  justification text, recense_le timestamptz
);

-- Ancien vrai scanner et son inventaire ; la seconde RPC créée par cette
-- migration n'est jamais appelée dans ce banc.
\ir ../../supabase/migrations/20260903194000_preserver_heures_reelles_pointage.sql

CREATE TEMP TABLE tirages (codes text[] NOT NULL);
DO $draws$
DECLARE codes text[];
BEGIN
  PERFORM setseed(0.31415926);
  SELECT array_agg(lpad(floor(random() * 1000000)::text, 6, '0') ORDER BY n)
    INTO codes FROM generate_series(1, 5) n;
  IF cardinality(codes) <> 5 OR (SELECT count(DISTINCT c) FROM unnest(codes) c) <> 5
  THEN RAISE EXCEPTION 'POINTAGE_ROTATION_FIXTURE_DRAWS_NOT_DISTINCT'; END IF;
  INSERT INTO tirages VALUES (codes);
END $draws$;
SELECT set_config('request.jwt.claim.sub', 'f1700000-0000-4000-8000-000000000002', true);

-- Tirage 1 = courant ; 2 = ancien code de CETTE mission ; 3 = code actif
-- d'une AUTRE mission ; 4 = neuf ; 5 = témoin du nombre de tirages consommés.
INSERT INTO public.missions(id, soignant_assigne_id, code_pointage_actif, prochain_type_scan, nb_scans, statut)
SELECT 'f1700000-0000-4000-8000-000000000001', 'f1700000-0000-4000-8000-000000000002', codes[1], 'OUVERTURE', 1, 'EN_COURS'
FROM tirages;
INSERT INTO public.missions(id, soignant_assigne_id, code_pointage_actif, prochain_type_scan, nb_scans, statut)
SELECT 'f1700000-0000-4000-8000-000000000003', 'f1700000-0000-4000-8000-000000000004', codes[3], 'OUVERTURE', 0, 'ASSIGNEE'
FROM tirages;
INSERT INTO public.contrats_mission(mission_id, statut)
VALUES ('f1700000-0000-4000-8000-000000000001', 'SIGNE_COMPLET');
INSERT INTO public.mission_creneaux(mission_id, debut, fin, ordre, type_creneau)
VALUES ('f1700000-0000-4000-8000-000000000001', now() - interval '30 minutes', now() + interval '1 hour', 1, 'PREVISIONNEL');
INSERT INTO public.scans_pointage(mission_id, soignant_id, code_saisi, numero_scan, type_scan, scanne_le, horodatage_arrondi)
SELECT 'f1700000-0000-4000-8000-000000000001', 'f1700000-0000-4000-8000-000000000002',
  codes[2], 1, 'FERMETURE', now() - interval '10 minutes', now() - interval '10 minutes' FROM tirages;

-- Témoin avant correction : le vrai scanner accepte le premier tirage, égal
-- au code courant. On annule ce scan avant de tester la vraie migration.
SAVEPOINT before_old_scanner;
DO $before$
DECLARE codes text[]; r jsonb;
BEGIN
  SELECT t.codes INTO codes FROM tirages t;
  PERFORM setseed(0.31415926);
  r := public.fn_scanner_code_pointage(codes[1], NULL);
  IF r->>'nouveau_code' IS DISTINCT FROM codes[1]
    OR (SELECT count(*) FROM scans_pointage) <> 2
  THEN RAISE EXCEPTION 'POINTAGE_ROTATION_OLD_DEFECT_NOT_REPRODUCED'; END IF;
END $before$;
ROLLBACK TO SAVEPOINT before_old_scanner;
RELEASE SAVEPOINT before_old_scanner;

CREATE TEMP TABLE original_inventory AS SELECT categorie, justification
  FROM private.security_definer_inventory WHERE signature = 'fn_scanner_code_pointage(text,jsonb)';
CREATE TEMP TABLE original_acl AS SELECT proowner, proacl, prosecdef, proconfig
  FROM pg_proc WHERE oid = 'public.fn_scanner_code_pointage(text,jsonb)'::regprocedure;

-- La migration entière, jamais une recopie simplifiée de son WHILE.
\ir ../../supabase/migrations/20261017165819_garantir_rotation_code_pointage.sql

DO $opening$
DECLARE codes text[]; r jsonb; next_draw text; snapshot jsonb; after_snapshot jsonb; c text;
BEGIN
  SELECT t.codes INTO codes FROM tirages t;
  PERFORM setseed(0.31415926);
  r := public.fn_scanner_code_pointage(codes[1], NULL);
  next_draw := lpad(floor(random() * 1000000)::text, 6, '0');
  IF r->>'nouveau_code' IS DISTINCT FROM codes[4] OR next_draw IS DISTINCT FROM codes[5]
    OR r->>'type_scan_effectue' IS DISTINCT FROM 'OUVERTURE'
    OR r->>'prochain_type_scan' IS DISTINCT FROM 'FERMETURE'
    OR (r->>'numero_scan')::integer IS DISTINCT FROM 2
    OR (r->>'horodatage_effectif')::timestamptz IS DISTINCT FROM now()
    OR (SELECT code_pointage_actif FROM missions WHERE id='f1700000-0000-4000-8000-000000000001') IS DISTINCT FROM codes[4]
    OR (SELECT count(*) FROM scans_pointage) <> 2
    OR (SELECT count(*) FROM mission_creneaux WHERE type_creneau='EFFECTIF' AND debut=now() AND fin IS NULL) <> 1
    OR (SELECT count(*) FROM presences WHERE pointage_arrivee_le=now()) <> 1
    OR EXISTS (SELECT FROM scans_pointage sp JOIN missions m ON m.id=sp.mission_id WHERE sp.code_saisi=m.code_pointage_actif)
  THEN RAISE EXCEPTION 'POINTAGE_ROTATION_OPENING_COLLISION_OR_STATE_FAILURE'; END IF;
  SELECT jsonb_build_object('missions',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM missions m),
    'scans',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM scans_pointage s),
    'segments',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM mission_creneaux s),
    'presences',(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM presences p)) INTO snapshot;
  FOREACH c IN ARRAY ARRAY[codes[1], codes[2]] LOOP
    BEGIN
      PERFORM public.fn_scanner_code_pointage(c, NULL);
      RAISE EXCEPTION 'POINTAGE_ROTATION_OLD_CODE_ACCEPTED';
    EXCEPTION WHEN no_data_found THEN
      IF SQLERRM IS DISTINCT FROM 'Code de pointage invalide ou expiré.' THEN RAISE; END IF;
    END;
  END LOOP;
  SELECT jsonb_build_object('missions',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM missions m),
    'scans',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM scans_pointage s),
    'segments',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM mission_creneaux s),
    'presences',(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM presences p)) INTO after_snapshot;
  IF snapshot IS DISTINCT FROM after_snapshot THEN RAISE EXCEPTION 'POINTAGE_ROTATION_REPLAY_MUTATED_STATE'; END IF;
END $opening$;

-- Nouveau scénario minimal de fermeture, même vraie fonction : les trois
-- collisions doivent aussi être refusées après la clôture du segment.
TRUNCATE public.scans_pointage, public.presences;
DELETE FROM public.mission_creneaux WHERE type_creneau='EFFECTIF';
UPDATE public.missions SET code_pointage_actif=(SELECT codes[1] FROM tirages),
  prochain_type_scan='FERMETURE', nb_scans=1
WHERE id='f1700000-0000-4000-8000-000000000001';
INSERT INTO public.scans_pointage(mission_id,soignant_id,code_saisi,numero_scan,type_scan,scanne_le,horodatage_arrondi)
SELECT 'f1700000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000002',
  codes[2],1,'OUVERTURE',now()-interval '15 minutes',now()-interval '15 minutes' FROM tirages;
INSERT INTO public.mission_creneaux(mission_id,debut,fin,ordre,type_creneau)
VALUES ('f1700000-0000-4000-8000-000000000001',now()-interval '15 minutes',NULL,2,'EFFECTIF');
INSERT INTO public.presences(mission_id,soignant_id,pointage_arrivee_le)
VALUES ('f1700000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000002',now()-interval '15 minutes');
DO $closing$
DECLARE codes text[]; r jsonb; next_draw text;
BEGIN
  SELECT t.codes INTO codes FROM tirages t;
  PERFORM setseed(0.31415926);
  r := public.fn_scanner_code_pointage(codes[1], NULL);
  next_draw := lpad(floor(random() * 1000000)::text, 6, '0');
  IF r->>'nouveau_code' IS DISTINCT FROM codes[4] OR next_draw IS DISTINCT FROM codes[5]
    OR r->>'type_scan_effectue' IS DISTINCT FROM 'FERMETURE'
    OR r->>'prochain_type_scan' IS DISTINCT FROM 'OUVERTURE'
    OR (r->>'horodatage_effectif')::timestamptz IS DISTINCT FROM now()
    OR (SELECT count(*) FROM scans_pointage) <> 2
    OR (SELECT count(*) FROM mission_creneaux WHERE type_creneau='EFFECTIF' AND fin=now()) <> 1
    OR (SELECT count(*) FROM presences WHERE pointage_depart_le=now() AND heures_reelles=0.25) <> 1
    OR EXISTS (SELECT FROM scans_pointage sp JOIN missions m ON m.id=sp.mission_id WHERE sp.code_saisi=m.code_pointage_actif)
  THEN RAISE EXCEPTION 'POINTAGE_ROTATION_CLOSING_COLLISION_OR_STATE_FAILURE'; END IF;
  IF EXISTS (SELECT FROM original_acl a CROSS JOIN pg_proc p
    WHERE p.oid='public.fn_scanner_code_pointage(text,jsonb)'::regprocedure
      AND (a.proowner IS DISTINCT FROM p.proowner OR a.proacl IS DISTINCT FROM p.proacl
        OR a.prosecdef IS DISTINCT FROM p.prosecdef OR a.proconfig IS DISTINCT FROM p.proconfig))
    OR NOT EXISTS (SELECT FROM private.security_definer_inventory i CROSS JOIN original_inventory old
      WHERE i.signature='fn_scanner_code_pointage(text,jsonb)' AND i.categorie=old.categorie
        AND i.justification=old.justification
        AND i.definition_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_scanner_code_pointage(text,jsonb)'::regprocedure))
  THEN RAISE EXCEPTION 'POINTAGE_ROTATION_SECURITY_OR_INVENTORY_CHANGED'; END IF;
END $closing$;

SELECT jsonb_build_object('postgres',17,'oldDefectReproduced',true,
  'realMigrationLoaded',true,'randomMocked',false,'deterministicCollisionPaths',2,
  'currentHistoricalAndOtherActiveCodesRejected',true,'oldCodeReplaysRejected',2,
  'actualOpenCloseTimesPreserved',true,'aclAndClassificationPreserved',true,
  'transactionEnd','ROLLBACK') AS pointage_rotation_proof;
ROLLBACK;
