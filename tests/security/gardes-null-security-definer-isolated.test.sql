-- Banc PG17 isolé B9 « gardes NULL » : vraies définitions LIVE (fixture
-- pg_get_functiondef relue le 09/11/2026), vrais helpers d'identité LIVE du
-- banc B5b, puis les deux vraies migrations du lot
-- (20261109010957 gardes NULL, 20261109020404 verrou double facturation).
-- Tables minimales, données synthétiques, aucune RLS : ce banc prouve
--   1. la fuite de fn_presences_detail_mission par rôle, sur la mission
--      assignée (M1) ET sur la mission sans soignant assigné (M2), avant
--      correctif, sur deux variantes à demi corrigées et après migration :
--      chaque variante à demi corrigée laisse encore fuir la mission non
--      assignée (S, T, R, autre établissement ou contexte système), donc le
--      cas 24 de tests/security/gardes-null-security-definer.test.sql y serait
--      rouge ; seule la migration complète les refuse ;
--   2. que la migration ne change que la garde des 20 corps, met l'inventaire
--      à jour et conserve les ACL ;
--   3. que fn_generer_facture n'est plus exécutable par authenticated ni anon
--      (42501), service_role conservé.
-- Le refus du rejeu et d'un corps dérivé est prouvé par
-- tests/security/gardes-null-security-definer-rejeu.test.sql.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'gardes_null_isole'
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'GARDES_NULL_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
\ir fixtures/visibilite-etablissement-permission-banc.sql
\ir fixtures/gardes-null-security-definer-banc.sql

-- Acteurs (banc B5b) : E = b5b…e1, E2 = b5b…e2 ; M1 = mission EN_COURS de E
-- assignée au soignant f1 ; M2 = mission OUVERTE de E sans soignant assigné.
CREATE TEMP TABLE gn_acteurs (nom text PRIMARY KEY, uid uuid);
INSERT INTO gn_acteurs VALUES
  ('proprietaire', 'b5b00000-0000-4000-8000-0000000000b1'),
  ('membre_autre_etab', 'b5b00000-0000-4000-8000-0000000000d1'),
  ('admin_plateforme', 'b5b00000-0000-4000-8000-0000000000a1'),
  ('soignant_affecte', 'b5b00000-0000-4000-8000-0000000000f1'),
  ('soignant_tiers', 'b5b00000-0000-4000-8000-0000000000f2'),
  ('membre_revoque', 'b5b00000-0000-4000-8000-0000000000b9'),
  ('systeme', NULL);
CREATE TEMP TABLE gn_obs (
  phase text, acteur text, mission text, resultat jsonb, PRIMARY KEY (phase, acteur, mission)
);
CREATE FUNCTION pg_temp.gn_observer(p_phase text) RETURNS void LANGUAGE plpgsql AS $observer$
DECLARE a record;
BEGIN
  FOR a IN SELECT * FROM pg_temp.gn_acteurs ORDER BY nom LOOP
    PERFORM set_config('request.jwt.claim.sub', COALESCE(a.uid::text, ''), true);
    PERFORM set_config('request.jwt.claim.role', CASE WHEN a.uid IS NULL THEN 'service_role' ELSE '' END, true);
    INSERT INTO pg_temp.gn_obs VALUES
      (p_phase, a.nom, 'm1', public.fn_presences_detail_mission('b5b00000-0000-4000-8000-00000000a001')),
      (p_phase, a.nom, 'm2', public.fn_presences_detail_mission('b5b00000-0000-4000-8000-00000000a002'));
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
END $observer$;

-- Corps LIVE capturés (restaurés après les variantes) et ancres des gardes.
CREATE TEMP TABLE gn_live AS
  SELECT p.oid AS fonction_oid, p.oid::regprocedure::text AS signature,
         pg_catalog.pg_get_functiondef(p.oid) AS definition, p.prosrc, p.proacl::text AS acl
    FROM pg_catalog.pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.oid IN (SELECT pg_catalog.to_regprocedure('public.' || i.signature)
                     FROM private.security_definer_inventory i
                    WHERE i.justification = 'fixture gardes NULL');
DO $live$ BEGIN
  IF (SELECT count(*) FROM gn_live) <> 20 THEN RAISE EXCEPTION 'GARDES_NULL_BANC_LIVE_INCOMPLET'; END IF;
END $live$;

SELECT pg_temp.gn_observer('live');

-- Variante 1 à demi corrigée : seule la comparaison avec mon_etablissement_id().
DO $demi1$
DECLARE v_def text := (SELECT definition FROM gn_live WHERE signature = 'fn_presences_detail_mission(uuid)');
BEGIN
  IF strpos(v_def, 'IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() ') = 0 THEN
    RAISE EXCEPTION 'GARDES_NULL_DEMI1_ANCRE_ABSENTE';
  END IF;
  EXECUTE replace(v_def, 'IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() ',
    'IF NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() ');
END $demi1$;
SELECT pg_temp.gn_observer('demi1');

-- Variante 2 à demi corrigée : seule la comparaison avec auth.uid().
DO $demi2$
DECLARE v_def text := (SELECT definition FROM gn_live WHERE signature = 'fn_presences_detail_mission(uuid)');
BEGIN
  IF strpos(v_def, 'AND v_mission.soignant_assigne_id != auth.uid() THEN') = 0 THEN
    RAISE EXCEPTION 'GARDES_NULL_DEMI2_ANCRE_ABSENTE';
  END IF;
  EXECUTE replace(v_def, 'AND v_mission.soignant_assigne_id != auth.uid() THEN',
    'AND NOT COALESCE(v_mission.soignant_assigne_id = auth.uid(), false) THEN');
END $demi2$;
SELECT pg_temp.gn_observer('demi2');

-- Restauration du corps LIVE exact avant la vraie migration.
DO $restaurer$ BEGIN
  EXECUTE (SELECT definition FROM gn_live WHERE signature = 'fn_presences_detail_mission(uuid)');
  IF EXISTS (SELECT FROM gn_live l JOIN pg_catalog.pg_proc p ON p.oid = l.fonction_oid
              WHERE p.prosrc IS DISTINCT FROM l.prosrc) THEN
    RAISE EXCEPTION 'GARDES_NULL_RESTAURATION_LIVE_INCOMPLETE';
  END IF;
END $restaurer$;

\ir ../../supabase/migrations/20261109010957_gardes_null_security_definer.sql
\ir ../../supabase/migrations/20261109020404_verrou_double_facturation_generer_facture.sql

SELECT pg_temp.gn_observer('apres');

-- 1. Matrice attendue (refus = {"error":"Accès refusé"} ; passe = réponse de
-- présence). Aucune autre combinaison n'est admise.
CREATE TEMP TABLE gn_attendus (phase text, acteur text, mission text, effet text);
INSERT INTO gn_attendus
  SELECT ph, ac, mi,
    CASE
      WHEN ac IN ('proprietaire', 'admin_plateforme') THEN 'passe'
      WHEN mi = 'm1' AND ac = 'soignant_affecte' THEN 'passe'
      WHEN mi = 'm1' AND ac = 'membre_autre_etab' THEN 'refus'
      WHEN ph = 'live' THEN 'passe'
      -- Variante 1 : M1 refusée sauf contexte système ; M2 fuit pour tous.
      WHEN ph = 'demi1' AND mi = 'm1' AND ac <> 'systeme' THEN 'refus'
      WHEN ph = 'demi1' THEN 'passe'
      -- Variante 2 : l'autre établissement est refusé partout ; M2 fuit pour
      -- les comptes sans établissement et le contexte système.
      WHEN ph = 'demi2' AND ac = 'membre_autre_etab' THEN 'refus'
      WHEN ph = 'demi2' THEN 'passe'
      ELSE 'refus'
    END
  FROM unnest(ARRAY['live', 'demi1', 'demi2', 'apres']) ph,
       unnest(ARRAY['proprietaire', 'membre_autre_etab', 'admin_plateforme', 'soignant_affecte',
                     'soignant_tiers', 'membre_revoque', 'systeme']) ac,
       unnest(ARRAY['m1', 'm2']) mi;
DO $matrice$
DECLARE r record;
BEGIN
  IF (SELECT count(*) FROM gn_obs) <> 56 OR (SELECT count(*) FROM gn_attendus) <> 56 THEN
    RAISE EXCEPTION 'GARDES_NULL_MATRICE_INCOMPLETE';
  END IF;
  FOR r IN
    SELECT a.*, o.resultat FROM gn_attendus a
      JOIN gn_obs o USING (phase, acteur, mission)
     ORDER BY phase, mission, acteur
  LOOP
    IF (r.effet = 'refus' AND r.resultat IS DISTINCT FROM '{"error":"Accès refusé"}'::jsonb)
       OR (r.effet = 'passe' AND NOT COALESCE(r.resultat ? 'pointage_effectue', false)) THEN
      RAISE EXCEPTION 'GARDES_NULL_MATRICE % % % : attendu %, obtenu %',
        r.phase, r.mission, r.acteur, r.effet, r.resultat;
    END IF;
  END LOOP;
  -- Sur M2, chaque variante à demi corrigée laisse fuir au moins un compte sans
  -- établissement : le cas 24 de la recette staging y est rouge.
  IF NOT EXISTS (SELECT FROM gn_obs WHERE phase = 'demi1' AND mission = 'm2'
                   AND acteur IN ('soignant_affecte', 'soignant_tiers', 'membre_revoque', 'systeme', 'membre_autre_etab')
                   AND resultat ? 'pointage_effectue')
     OR NOT EXISTS (SELECT FROM gn_obs WHERE phase = 'demi2' AND mission = 'm2'
                   AND acteur IN ('soignant_affecte', 'soignant_tiers', 'membre_revoque', 'systeme')
                   AND resultat ? 'pointage_effectue')
     OR EXISTS (SELECT FROM gn_obs WHERE phase = 'apres' AND mission = 'm2'
                   AND acteur NOT IN ('proprietaire', 'admin_plateforme')
                   AND resultat IS DISTINCT FROM '{"error":"Accès refusé"}'::jsonb) THEN
    RAISE EXCEPTION 'GARDES_NULL_VARIANTES_DEMI_CORRIGEES_NON_DISCRIMINANTES';
  END IF;
  IF (SELECT resultat FROM gn_obs WHERE phase = 'apres' AND mission = 'm2' AND acteur = 'proprietaire')
       IS DISTINCT FROM '{"pointage_effectue": false, "heures_planifiees": 8}'::jsonb THEN
    RAISE EXCEPTION 'GARDES_NULL_PROPRIETAIRE_REPONSE_INATTENDUE';
  END IF;
END $matrice$;

-- 2. Corps, inventaire et ACL après migration : seule la garde a changé.
DO $corps$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN
    SELECT l.*, p.prosrc AS nouveau, p.proacl::text AS nouvelle_acl, i.categorie, i.definition_md5
      FROM gn_live l
      JOIN pg_catalog.pg_proc p ON p.oid = l.fonction_oid
      JOIN private.security_definer_inventory i ON i.signature = l.signature
  LOOP
    IF r.nouveau = r.prosrc OR r.definition_md5 IS DISTINCT FROM md5(r.nouveau)
       OR strpos(r.nouveau, 'COALESCE(') = 0 THEN
      RAISE EXCEPTION 'GARDES_NULL_CORPS_APRES: %', r.signature;
    END IF;
    IF r.signature = 'fn_generer_facture(uuid)' THEN
      IF r.categorie IS DISTINCT FROM 'SERVICE_ONLY_REVOQUE'
         OR has_function_privilege('authenticated', r.fonction_oid, 'EXECUTE')
         OR has_function_privilege('anon', r.fonction_oid, 'EXECUTE')
         OR NOT has_function_privilege('service_role', r.fonction_oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'GARDES_NULL_VERROU_FACTURE_ACL: %', r.nouvelle_acl;
      END IF;
    ELSIF r.nouvelle_acl IS DISTINCT FROM r.acl
       OR r.categorie = 'SERVICE_ONLY_REVOQUE'
       OR NOT has_function_privilege('authenticated', r.fonction_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'GARDES_NULL_ACL_APRES: %', r.signature;
    END IF;
    n := n + 1;
  END LOOP;
  IF n <> 20 THEN RAISE EXCEPTION 'GARDES_NULL_CORPS_APRES_INCOMPLET: %', n; END IF;
END $corps$;

-- 3. Verrou double facturation : appel authenticated et anon → 42501.
DO $verrou$
DECLARE v_role text; v_refus boolean; n integer := 0;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['authenticated', 'anon'] LOOP
    PERFORM set_config('request.jwt.claim.sub',
      CASE WHEN v_role = 'authenticated' THEN 'b5b00000-0000-4000-8000-0000000000b1' ELSE '' END, true);
    v_refus := false;
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    BEGIN
      PERFORM public.fn_generer_facture('b5b00000-0000-4000-8000-00000000a002');
    EXCEPTION WHEN insufficient_privilege THEN v_refus := true;
    END;
    EXECUTE 'RESET ROLE';
    IF NOT v_refus THEN RAISE EXCEPTION 'GARDES_NULL_VERROU_FACTURE_APPEL_ACCEPTE: %', v_role; END IF;
    n := n + 1;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF n <> 2 THEN RAISE EXCEPTION 'GARDES_NULL_VERROU_FACTURE_INCOMPLET'; END IF;
END $verrou$;

SELECT 'GARDES_NULL_ISOLE_OK' AS marqueur;
ROLLBACK;
