-- Cloisonnement des missions : cohorte de test et missions de revue des stores.
--
-- Contexte (26/11/2026) : la revue App Store de l'app iOS 2.0.0 se fait avec un
-- établissement et un soignant de démonstration, comptes de test. La cohorte de
-- test ne se limite pas à des comptes internes : toute inscription faite avant
-- l'ouverture des inscriptions publiques y a été classée
-- (private.fn_forcer_compte_test_prelaunch, migration 20260729121419), et le
-- drapeau est figé. Décision (coordination, délégation de Gabrielle, 26/11) :
-- les missions de revue (mission_source REVUE_STORE) ne sont diffusées à
-- PERSONNE et ne sont visibles QUE du soignant de revue désigné.
--
-- 1. Cohorte de test, source unique (CLAUDE.md, « filtre de visibilité
--    centralisé ») : public.fn_soignant_eligible_mission comparait localement
--    les drapeaux est_compte_test ; elle lit désormais
--    private.fn_comptes_meme_cohorte_test, le prédicat de la RLS
--    missions_masquer_etabs_test (aucun changement de résultat :
--    fn_resoudre_contrat_mission l'appliquait déjà).
--    fn_pool_urgence_etablissement (autorisation de send-push, send-sms et de
--    la conversation pool), son jumeau private.fn_soignant_visible_pool_etablissement
--    et fn_notifier_favoris_expirants n'avaient aucun filtre de cohorte.
-- 2. Missions de revue :
--    - désignation des comptes de revue : private.etablissements_revue_store et
--      private.soignants_revue_store (comptes de test seulement, refus par
--      déclencheur) ;
--    - visibilité : politique RLS RESTRICTIVE missions_revue_store_soignant_designe
--      (un soignant ne lit une mission REVUE_STORE que s'il est soignant de revue
--      désigné ; rien ne change pour les admins, l'établissement et les autres
--      missions) ; les lecteurs SECURITY DEFINER qui contournent la RLS passent
--      par l'éligibilité, par un filtre de test, ou par
--      private.fn_soignant_voit_mission (favoris) ;
--    - diffusion : aucune. fn_soignant_eligible_mission ne rend jamais une
--      mission REVUE_STORE éligible (vagues, relances, boost, matching inverse,
--      favoris, pool interne, remplacements, digest, notif-match) ; les alertes
--      de recherche (private.fn_resultats_filtre_missions), la relance sans
--      candidat (y compris l'avis à l'établissement) et les missions
--      sauvegardées les écartent ; le pool d'un établissement de revue est
--      vide (private.fn_soignant_contactable_par_etablissement) ;
--    - réponse : fn_resoudre_contrat_mission refuse une mission REVUE_STORE à
--      tout soignant non désigné (candidature, proposition, rebook, swipe) ;
--    - mission_source REVUE_STORE ne se pose ni ne se retire depuis une session
--      utilisateur (déclencheur), seulement en contexte système.
-- 3. Textes publics : public.fn_admin_generer_posts (posts partagés sur les
--    réseaux) ne compte plus que les missions réelles
--    (private.fn_mission_lie_compte_test, filtre de fn_missions_publiques_*).
--
-- Redéfinitions : corps LIVE relus en lecture seule le 26/11/2026
-- (flripxtsyegjshnhzjkz), md5(prosrc) identiques à supabase/schema/public.sql
-- et à 20261029080849 ; seules les lignes citées changent. Préflight
-- fail-closed et post-condition sur md5(prosrc). En-têtes, SECURITY
-- DEFINER/INVOKER, search_path, propriétaire et ACL conservés par CREATE OR
-- REPLACE. Inventaire SECURITY DEFINER mis à jour pour les fonctions inscrites.
--
-- Contrôles : tests/security/revue-store-missions-isolees.test.sql (staging,
-- ROLLBACK ; même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/revue-store-missions.pg17.mjs), garde statique
-- tests/node/revue-store-missions.node.mjs.
-- B9 (RLS + SECURITY DEFINER) : go écrits de Gabrielle du 24/11/2026 et du 26/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed : corps LIVE attendus ─────────────────────────
DO $cloisonner_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'f10aeb9ced376cae6ef5a4a863a2cf6b', false, 's', 'search_path=public'),
      ('public.fn_resoudre_contrat_mission(uuid,uuid,text)', 'e39388880b3e026e8b81b0d94d0de777', false, 's', 'search_path=pg_catalog, public'),
      ('public.fn_pool_urgence_etablissement(uuid)', '178dbb066ceb8720c38c30ab0fb74f7d', true, 's', 'search_path=""'),
      ('private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)', '4eb5e4ba20268e667e33c0c57a209f77', true, 'v', 'search_path=""'),
      ('public.fn_notifier_favoris_expirants()', 'd44ae13e1e450ab85942c1863d107b7e', true, 'v', 'search_path=public'),
      ('public.fn_relancer_missions_sans_candidat()', '49ae7d9e38110b4009e70af2d3a77c9f', true, 'v', 'search_path=public'),
      ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', '0e83167df94ef8d1d64019af1f4fe6ae', false, 's', 'search_path=""'),
      ('public.fn_mes_favoris_etablissements()', '26c080a4e6e197018a5b27195981473a', true, 's', 'search_path=public, extensions'),
      ('public.fn_admin_generer_posts()', 'fd4a9e677fa1cdae1c0a75a061b789c4', true, 's', 'search_path=public'),
      ('private.fn_comptes_meme_cohorte_test(uuid,uuid)', '8dbe1d6bdcf7b10bb3a2662f67475196', true, 's', 'search_path=""'),
      ('private.fn_mission_lie_compte_test(uuid)', NULL, true, 's', 'search_path=""')
    ) AS t(signature, empreinte, definer, volatilite, config)
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile::text AS volatilite, p.proconfig,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature);
    IF NOT FOUND
      OR (v_attendu.empreinte IS NOT NULL AND pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte)
      OR v_proc.prosecdef IS DISTINCT FROM v_attendu.definer
      OR v_proc.volatilite IS DISTINCT FROM v_attendu.volatilite
      OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_attendu.config]::text[]
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'CLOISONNER_SOURCE_DIVERGENTE : % en base (md5 %) ne correspond plus au corps LIVE relu le 26/11/2026 (md5 %). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature, COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'), v_attendu.empreinte;
    END IF;
  END LOOP;
  IF (SELECT pg_catalog.pg_get_constraintdef(c.oid) FROM pg_catalog.pg_constraint c
       WHERE c.conrelid = 'public.missions'::pg_catalog.regclass AND c.conname = 'missions_mission_source_check')
     IS DISTINCT FROM 'CHECK ((mission_source = ANY (ARRAY[''SWIPE''::text, ''CANDIDATURE''::text, ''REBOOK''::text, ''PROPOSITION_DIRECTE''::text, ''REMPLACEMENT''::text, ''REPUBLICATION''::text])))'
  THEN
    RAISE EXCEPTION 'CLOISONNER_CONTRAINTE_DIVERGENTE : missions_mission_source_check ne correspond plus à la définition LIVE relue le 26/11/2026.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid = 'public.missions'::pg_catalog.regclass
              AND polname = 'missions_revue_store_soignant_designe') THEN
    RAISE EXCEPTION 'CLOISONNER_POLITIQUE_PRESENTE : la politique missions_revue_store_soignant_designe existe déjà.';
  END IF;
END
$cloisonner_avant$;

-- ── 1. Marquage des missions de revue ──────────────────────────────────────
ALTER TABLE public.missions DROP CONSTRAINT missions_mission_source_check;
ALTER TABLE public.missions ADD CONSTRAINT missions_mission_source_check
  CHECK (mission_source = ANY (ARRAY['SWIPE'::text, 'CANDIDATURE'::text, 'REBOOK'::text,
    'PROPOSITION_DIRECTE'::text, 'REMPLACEMENT'::text, 'REPUBLICATION'::text, 'REVUE_STORE'::text]));

-- ── 2. Désignation des comptes de revue (comptes de test seulement) ────────
CREATE TABLE IF NOT EXISTS private.etablissements_revue_store (
  etablissement_id uuid PRIMARY KEY REFERENCES public.etablissements(id) ON DELETE CASCADE,
  designe_le timestamptz NOT NULL DEFAULT pg_catalog.now(),
  motif text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(motif)) >= 10)
);
COMMENT ON TABLE private.etablissements_revue_store IS
  'Établissements de test désignés pour la revue des stores : 3 missions REVUE_STORE garanties (private.fn_garantir_missions_revue_store), pool d''urgence vide. Compte de test exigé. Migrations 20261126100000 et 20261126100100.';
REVOKE ALL ON TABLE private.etablissements_revue_store FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS private.soignants_revue_store (
  soignant_id uuid PRIMARY KEY REFERENCES public.soignants(id) ON DELETE CASCADE,
  designe_le timestamptz NOT NULL DEFAULT pg_catalog.now(),
  motif text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(motif)) >= 10)
);
COMMENT ON TABLE private.soignants_revue_store IS
  'Soignants de test désignés pour la revue des stores : seuls lecteurs des missions REVUE_STORE (RLS missions_revue_store_soignant_designe). Compte de test exigé. Migration 20261126100000.';
REVOKE ALL ON TABLE private.soignants_revue_store FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_verifier_etablissement_revue_store(p_etablissement_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $fn_verifier_etablissement_revue_store$
DECLARE
  v_etab record;
BEGIN
  SELECT e.id, e.est_compte_test, e.supprime_le
    INTO v_etab
    FROM public.etablissements e
   WHERE e.id = p_etablissement_id;
  IF NOT FOUND OR v_etab.supprime_le IS NOT NULL THEN
    RAISE EXCEPTION 'Établissement de revue introuvable ou supprimé (%).', p_etablissement_id
      USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_ETABLISSEMENT_INTROUVABLE',
            DETAIL = 'private.etablissements_revue_store, migration 20261126100000.';
  END IF;
  IF v_etab.est_compte_test IS NOT TRUE THEN
    RAISE EXCEPTION 'Missions de revue refusées : l''établissement % n''est pas un compte de test. Ses missions seraient visibles des soignants réels et leur seraient diffusées.', p_etablissement_id
      USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_ETABLISSEMENT_REEL',
            DETAIL = 'Seul un compte de test (etablissements.est_compte_test) peut être désigné. Migration 20261126100000.';
  END IF;
END;
$fn_verifier_etablissement_revue_store$;
REVOKE ALL ON FUNCTION private.fn_verifier_etablissement_revue_store(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_verifier_soignant_revue_store(p_soignant_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $fn_verifier_soignant_revue_store$
DECLARE
  v_soignant record;
BEGIN
  SELECT s.id, s.est_compte_test, s.supprime_le
    INTO v_soignant
    FROM public.soignants s
   WHERE s.id = p_soignant_id;
  IF NOT FOUND OR v_soignant.supprime_le IS NOT NULL THEN
    RAISE EXCEPTION 'Soignant de revue introuvable ou supprimé (%).', p_soignant_id
      USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_SOIGNANT_INTROUVABLE',
            DETAIL = 'private.soignants_revue_store, migration 20261126100000.';
  END IF;
  IF v_soignant.est_compte_test IS NOT TRUE THEN
    RAISE EXCEPTION 'Désignation refusée : le soignant % n''est pas un compte de test.', p_soignant_id
      USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_SOIGNANT_REEL',
            DETAIL = 'Seul un compte de test (soignants.est_compte_test) peut être soignant de revue. Migration 20261126100000.';
  END IF;
END;
$fn_verifier_soignant_revue_store$;
REVOKE ALL ON FUNCTION private.fn_verifier_soignant_revue_store(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_trg_verifier_designation_revue_store()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $fn_trg_verifier_designation_revue_store$
BEGIN
  IF TG_TABLE_NAME = 'etablissements_revue_store' THEN
    PERFORM private.fn_verifier_etablissement_revue_store(NEW.etablissement_id);
  ELSE
    PERFORM private.fn_verifier_soignant_revue_store(NEW.soignant_id);
  END IF;
  RETURN NEW;
END;
$fn_trg_verifier_designation_revue_store$;
REVOKE ALL ON FUNCTION private.fn_trg_verifier_designation_revue_store() FROM PUBLIC, anon, authenticated, service_role;

DO $cloisonner_declencheurs$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgrelid = 'private.etablissements_revue_store'::pg_catalog.regclass
                    AND tgname = 'trg_verifier_designation_revue_store') THEN
    CREATE TRIGGER trg_verifier_designation_revue_store
      BEFORE INSERT OR UPDATE ON private.etablissements_revue_store
      FOR EACH ROW EXECUTE FUNCTION private.fn_trg_verifier_designation_revue_store();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgrelid = 'private.soignants_revue_store'::pg_catalog.regclass
                    AND tgname = 'trg_verifier_designation_revue_store') THEN
    CREATE TRIGGER trg_verifier_designation_revue_store
      BEFORE INSERT OR UPDATE ON private.soignants_revue_store
      FOR EACH ROW EXECUTE FUNCTION private.fn_trg_verifier_designation_revue_store();
  END IF;
END
$cloisonner_declencheurs$;

-- ── 3. Prédicats canoniques ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.fn_est_etablissement_revue_store(p_etablissement_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn_est_etablissement_revue_store$
  SELECT EXISTS (
    SELECT 1
      FROM private.etablissements_revue_store d
      JOIN public.etablissements e ON e.id = d.etablissement_id
     WHERE d.etablissement_id = p_etablissement_id
       AND e.est_compte_test IS TRUE
       AND e.supprime_le IS NULL
  );
$fn_est_etablissement_revue_store$;
COMMENT ON FUNCTION private.fn_est_etablissement_revue_store(uuid) IS
  'Vrai pour un établissement de revue des stores désigné, compte de test non supprimé. Migration 20261126100000.';
REVOKE ALL ON FUNCTION private.fn_est_etablissement_revue_store(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_est_soignant_revue_store(p_soignant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn_est_soignant_revue_store$
  SELECT EXISTS (
    SELECT 1
      FROM private.soignants_revue_store d
      JOIN public.soignants s ON s.id = d.soignant_id
     WHERE d.soignant_id = p_soignant_id
       AND s.est_compte_test IS TRUE
       AND s.supprime_le IS NULL
  );
$fn_est_soignant_revue_store$;
COMMENT ON FUNCTION private.fn_est_soignant_revue_store(uuid) IS
  'Vrai pour un soignant de revue des stores désigné, compte de test non supprimé : seul lecteur des missions REVUE_STORE (RLS) et seul à pouvoir y répondre. Migration 20261126100000.';
REVOKE ALL ON FUNCTION private.fn_est_soignant_revue_store(uuid) FROM PUBLIC, anon;
-- Lu par la RLS (rôle authenticated) et par fn_resoudre_contrat_mission (INVOKER, service_role).
GRANT EXECUTE ON FUNCTION private.fn_est_soignant_revue_store(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_soignant_voit_mission(p_soignant_id uuid, p_etablissement_id uuid, p_mission_source text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn_soignant_voit_mission$
  SELECT private.fn_comptes_meme_cohorte_test(p_soignant_id, p_etablissement_id)
     AND (p_mission_source IS DISTINCT FROM 'REVUE_STORE'
          OR private.fn_est_soignant_revue_store(p_soignant_id));
$fn_soignant_voit_mission$;
COMMENT ON FUNCTION private.fn_soignant_voit_mission(uuid, uuid, text) IS
  'Même règle que les RLS missions_masquer_etabs_test et missions_revue_store_soignant_designe, pour les lecteurs SECURITY DEFINER qui les contournent. Migration 20261126100000.';
REVOKE ALL ON FUNCTION private.fn_soignant_voit_mission(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_soignant_contactable_par_etablissement(p_soignant_id uuid, p_etablissement_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn_soignant_contactable_par_etablissement$
  SELECT private.fn_comptes_meme_cohorte_test(p_soignant_id, p_etablissement_id)
     AND NOT private.fn_est_etablissement_revue_store(p_etablissement_id);
$fn_soignant_contactable_par_etablissement$;
COMMENT ON FUNCTION private.fn_soignant_contactable_par_etablissement(uuid, uuid) IS
  'Pool d''urgence d''un établissement (send-push, send-sms, conversation pool) : même cohorte de test, et aucun soignant pour un établissement de revue des stores. Migration 20261126100000.';
REVOKE ALL ON FUNCTION private.fn_soignant_contactable_par_etablissement(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ── 4. mission_source REVUE_STORE : contexte système seulement ─────────────
CREATE OR REPLACE FUNCTION private.fn_trg_proteger_mission_source_revue_store()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $fn_trg_proteger_mission_source_revue_store$
BEGIN
  -- Contexte système (cron, migration, service sans identité) : autorisé.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF (TG_OP = 'INSERT' AND NEW.mission_source IS NOT DISTINCT FROM 'REVUE_STORE')
     OR (TG_OP = 'UPDATE'
         AND NEW.mission_source IS DISTINCT FROM OLD.mission_source
         AND 'REVUE_STORE' IN (COALESCE(NEW.mission_source, ''), COALESCE(OLD.mission_source, ''))) THEN
    RAISE EXCEPTION 'La source REVUE_STORE d''une mission ne se pose ni ne se retire depuis un compte.'
      USING ERRCODE = '42501', HINT = 'REVUE_STORE_SOURCE_PROTEGEE',
            DETAIL = 'Missions de revue des stores : private.fn_garantir_missions_revue_store seulement (migration 20261126100000).';
  END IF;
  RETURN NEW;
END;
$fn_trg_proteger_mission_source_revue_store$;
REVOKE ALL ON FUNCTION private.fn_trg_proteger_mission_source_revue_store() FROM PUBLIC, anon, authenticated, service_role;

DO $cloisonner_source$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgrelid = 'public.missions'::pg_catalog.regclass
                    AND tgname = 'trg_00_proteger_mission_source_revue_store') THEN
    CREATE TRIGGER trg_00_proteger_mission_source_revue_store
      BEFORE INSERT OR UPDATE OF mission_source ON public.missions
      FOR EACH ROW EXECUTE FUNCTION private.fn_trg_proteger_mission_source_revue_store();
  END IF;
END
$cloisonner_source$;

-- ── 5. Visibilité : un soignant ne lit une mission de revue que s'il est désigné ─
CREATE POLICY missions_revue_store_soignant_designe ON public.missions
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    mission_source IS DISTINCT FROM 'REVUE_STORE'
    OR NOT (SELECT public.est_soignant() AS est_soignant)
    OR (SELECT private.fn_est_soignant_revue_store((SELECT auth.uid() AS uid)))
  );

-- ── 6. Redéfinitions (corps LIVE + lignes citées) ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_soignant_eligible_mission(p_soignant_id uuid, p_mission_id uuid, p_exiger_documents boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn_soignant_eligible_mission$
DECLARE
  v_mission record;
  v_soignant record;
  v_type text;
  v_resolution jsonb;
BEGIN
  SELECT m.profession_requise, m.specialite_medicale_requise, m.accepte_internes, m.fin_le,
         COALESCE(m.accepte_non_specialises, true) AS accepte_non_specialises,
         COALESCE(m.type_contrat_recherche::text, 'SALARIE') AS type_contrat_recherche,
         m.remplacement_de_mission_id,
         m.etablissement_id,
         m.mission_source
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id AND m.statut = 'OUVERTE';
  IF NOT FOUND THEN RETURN false; END IF;

  -- Mission de revue des stores (REVUE_STORE) : jamais diffusée, à personne,
  -- pas même au soignant de revue. Cette fonction choisit les destinataires
  -- des vagues, relances, boost, matching inverse, favoris, pool,
  -- remplacements, digest et notif-match (migration 20261126100000).
  IF v_mission.mission_source IS NOT DISTINCT FROM 'REVUE_STORE' THEN
    RETURN false;
  END IF;

  SELECT profession, specialite_medicale,
         COALESCE(type_exercice, 'SALARIE') AS type_exercice
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id
     AND supprime_le IS NULL
     AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
  IF NOT FOUND THEN RETURN false; END IF;

  -- Cohorte de test : le prédicat de la RLS missions_masquer_etabs_test, source
  -- unique (migration 20261126100000).
  IF NOT private.fn_comptes_meme_cohorte_test(p_soignant_id, v_mission.etablissement_id) THEN
    RETURN false;
  END IF;

  -- Aucun assigné remplacé, ni auteur d'une attestation EPI, ne peut revenir
  -- par un descendant de la chaîne. L'ascendance récursive couvre aussi
  -- EPI(A) -> remplacement B -> no-show(B) -> remplacement C.
  IF v_mission.remplacement_de_mission_id IS NOT NULL
     AND EXISTS (
       WITH RECURSIVE ascendance AS (
         SELECT m.id, m.soignant_assigne_id, m.remplacement_de_mission_id
         FROM public.missions m
         WHERE m.id = v_mission.remplacement_de_mission_id
         UNION
         SELECT parent.id, parent.soignant_assigne_id,
                parent.remplacement_de_mission_id
         FROM public.missions parent
         JOIN ascendance enfant
           ON parent.id = enfant.remplacement_de_mission_id
       )
       SELECT 1
       FROM ascendance a
       WHERE a.soignant_assigne_id = p_soignant_id
          OR EXISTS (
            SELECT 1
            FROM public.journaux_audit ja
            WHERE ja.acteur_id = p_soignant_id
              AND ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
              AND ja.type_ressource = 'mission'
              AND ja.id_ressource = a.id
          )
     ) THEN
    RETURN false;
  END IF;

  IF NOT private.fn_compatibilite_profil_mission(
    p_soignant_id, v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true), v_mission.accepte_internes, v_mission.fin_le
  ) THEN
    RETURN false;
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id, p_soignant_id, NULL
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE
     AND COALESCE((v_resolution->>'choix_requis')::boolean, false) IS NOT TRUE THEN
    RETURN false;
  END IF;
  IF NOT p_exiger_documents THEN RETURN true; END IF;

  IF COALESCE((v_resolution->>'choix_requis')::boolean, false) THEN
    RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'SALARIE')
      OR (v_soignant.type_exercice IN ('LIBERAL', 'MIXTE')
          AND public.fn_documents_ok_pour_mission(p_soignant_id, 'LIBERAL'));
  END IF;
  v_type := v_resolution->>'contrat';
  IF v_type = 'LIBERAL' THEN
    RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'LIBERAL');
  END IF;
  RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'SALARIE');
END;
$fn_soignant_eligible_mission$;
CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $fn_resoudre_contrat_mission$
DECLARE
  v_mission record;
  v_soignant record;
  v_etablissement record;
  v_recherche text;
  v_choix text;
  v_mode jsonb;
  v_liberal_verifie boolean := false;
BEGIN
  SELECT id, profession_requise, type_contrat_recherche, etablissement_id, mission_source
    INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission introuvable');
  END IF;

  SELECT
    id,
    COALESCE(type_exercice, 'SALARIE') AS type_exercice,
    preference_contrat_mixte
  INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Profil soignant introuvable'
    );
  END IF;

  SELECT
    type::text AS type_etablissement,
    COALESCE(est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements
  WHERE id = v_mission.etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Établissement introuvable'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    p_soignant_id,
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Mission indisponible pour ce compte'
    );
  END IF;

  -- Mission de revue des stores : seul un soignant de revue désigné peut y
  -- répondre, comme le veut la RLS missions_revue_store_soignant_designe
  -- (migration 20261126100000). Candidature, proposition, rebook, swipe, urgence.
  IF v_mission.mission_source IS NOT DISTINCT FROM 'REVUE_STORE'
     AND NOT private.fn_est_soignant_revue_store(p_soignant_id) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Mission indisponible pour ce compte'
    );
  END IF;

  v_liberal_verifie :=
    public.fn_soignant_liberal_actif_verifie(p_soignant_id);

  IF p_choix_contrat IS NOT NULL
     AND upper(p_choix_contrat) NOT IN ('SALARIE', 'LIBERAL') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Choix de contrat invalide'
    );
  END IF;

  v_recherche := CASE
    WHEN upper(COALESCE(
      v_mission.type_contrat_recherche::text,
      'SALARIE'
    )) IN ('SALARIE', 'LIBERAL', 'TOUS')
      THEN upper(COALESCE(
        v_mission.type_contrat_recherche::text,
        'SALARIE'
      ))
    ELSE 'SALARIE'
  END;

  IF v_recherche = 'SALARIE' THEN
    v_choix := 'SALARIE';
  ELSIF v_recherche = 'LIBERAL' THEN
    IF v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
       OR NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Cette mission est proposée en libéral ; activez un profil libéral avec SIRET et identité vérifiés.'
      );
    END IF;
    v_choix := 'LIBERAL';
  ELSE
    v_choix := upper(p_choix_contrat);

    IF v_choix = 'LIBERAL' AND NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil libéral doit être actif, avec SIRET et identité vérifiés.'
      );
    END IF;

    IF v_choix IS NULL THEN
      IF v_soignant.type_exercice = 'MIXTE' AND v_liberal_verifie THEN
        v_choix := CASE
          WHEN upper(COALESCE(
            v_soignant.preference_contrat_mixte,
            ''
          )) IN ('SALARIE', 'LIBERAL')
            THEN upper(v_soignant.preference_contrat_mixte)
          ELSE NULL
        END;
        IF v_choix IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Choisissez votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object(
                'value', 'SALARIE',
                'label', 'Salarié (CDD / bulletin de paie)'
              ),
              jsonb_build_object(
                'value', 'LIBERAL',
                'label', 'Libéral (note d''honoraires)'
              )
            )
          );
        END IF;
      ELSIF v_soignant.type_exercice = 'LIBERAL'
            AND v_liberal_verifie THEN
        v_choix := 'LIBERAL';
      ELSE
        v_choix := 'SALARIE';
      END IF;
    END IF;

    IF v_choix = 'LIBERAL'
       AND (
         v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
         OR NOT v_liberal_verifie
       ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil n''est pas activé pour un contrat libéral vérifié.'
      );
    END IF;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_mode := public.fn_mode_exercice(
      v_mission.profession_requise::text,
      v_etablissement.type_etablissement,
      CASE
        WHEN v_etablissement.est_public THEN 'PUBLIC'
        ELSE NULL
      END
    );
    IF COALESCE(v_mode->>'niveau', 'BLOQUE') = 'BLOQUE'
       OR (
         v_mission.profession_requise::text IN ('IADE', 'IBODE')
         AND COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE'
       ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', COALESCE(
          v_mode->>'source_libelle',
          'Le mode libéral est indisponible pour cette mission.'
        ),
        'niveau', COALESCE(v_mode->>'niveau', 'BLOQUE')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_contrat_recherche', v_recherche
  );
END;
$fn_resoudre_contrat_mission$;
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn_pool_urgence_etablissement$
DECLARE
  v_etab public.etablissements%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;
  IF public.fn_a_permission_etablissement(
       'candidatures', p_etablissement_id
     ) IS NOT TRUE THEN
    RAISE EXCEPTION
      'Accès refusé : pool urgence réservé aux responsables de l’établissement'
      USING ERRCODE = '42501';
  END IF;

  SELECT e.* INTO v_etab
  FROM public.etablissements e
  WHERE e.id = p_etablissement_id
    AND e.supprime_le IS NULL;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.prenom::text,
    s.nom::text,
    s.profession::text,
    CASE
      WHEN COALESCE(s.total_missions_terminees, 0) >= 3
      THEN s.score_fiabilite::integer
      ELSE NULL
    END,
    COALESCE(s.urgence_rayon_km, 15)::integer,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        pg_catalog.round((
          6371 * pg_catalog.acos(least(
            1.0::double precision,
            greatest(
              (-1.0)::double precision,
              pg_catalog.cos(pg_catalog.radians(v_etab.adresse_lat))
                * pg_catalog.cos(pg_catalog.radians(s.adresse_lat))
                * pg_catalog.cos(
                    pg_catalog.radians(s.adresse_lng)
                    - pg_catalog.radians(v_etab.adresse_lng)
                  )
                + pg_catalog.sin(pg_catalog.radians(v_etab.adresse_lat))
                  * pg_catalog.sin(pg_catalog.radians(s.adresse_lat))
            )
          ))
        )::numeric, 1)
      ELSE NULL
    END,
    (
      SELECT pg_catalog.count(*)::bigint
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND COALESCE(m.est_urgente, false) IS TRUE
        AND m.statut = 'TERMINEE'
    ),
    EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND m.statut = 'EN_COURS'
        AND pg_catalog.now() BETWEEN m.debut_le AND m.fin_le
    ),
    (
      SELECT pg_catalog.max(m2.fin_le)
      FROM public.missions m2
      WHERE m2.soignant_assigne_id = s.id
        AND m2.etablissement_id = p_etablissement_id
        AND m2.statut = 'TERMINEE'
    ),
    s.bio::text,
    s.avatar_url::text,
    EXISTS (
      SELECT 1
      FROM public.favoris_etab_soignant f
      WHERE f.soignant_id = s.id
        AND f.etablissement_id = p_etablissement_id
    )
  FROM public.soignants s
  WHERE private.fn_soignant_messagerie_actif(s.id)
    -- Pool = autorisation de send-push, send-sms et de la conversation pool :
    -- même cohorte de test, et jamais aucun soignant pour un établissement de
    -- revue des stores (migration 20261126100000).
    AND private.fn_soignant_contactable_par_etablissement(s.id, p_etablissement_id)
    AND COALESCE(s.disponible_urgence, false) IS TRUE
    AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND NOT public.fn_est_exclu(s.id, p_etablissement_id)
    AND (
      EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN (
            'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
          )
          AND private.fn_compatibilite_profil_mission(
    s.id, m.profession_requise, m.specialite_medicale_requise,
    COALESCE(m.accepte_non_specialises, true), m.accepte_internes, m.fin_le
  )
      )
      OR (private.fn_statut_internat_medical(s.id)->>'statut' = 'NON_CONCERNE' AND NOT EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN (
            'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
          )
      ))
    )
  ORDER BY
    CASE
      WHEN COALESCE(s.total_missions_terminees, 0) >= 3
      THEN s.score_fiabilite
      ELSE NULL
    END DESC NULLS LAST,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        6371 * pg_catalog.acos(least(
          1.0::double precision,
          greatest(
            (-1.0)::double precision,
            pg_catalog.cos(pg_catalog.radians(v_etab.adresse_lat))
              * pg_catalog.cos(pg_catalog.radians(s.adresse_lat))
              * pg_catalog.cos(
                  pg_catalog.radians(s.adresse_lng)
                  - pg_catalog.radians(v_etab.adresse_lng)
                )
              + pg_catalog.sin(pg_catalog.radians(v_etab.adresse_lat))
                * pg_catalog.sin(pg_catalog.radians(s.adresse_lat))
          )
        ))
      ELSE NULL
    END NULLS LAST;
END;
$fn_pool_urgence_etablissement$;
CREATE OR REPLACE FUNCTION private.fn_soignant_visible_pool_etablissement(p_etablissement_user_id uuid, p_soignant_id uuid, p_etablissement_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $fn_soignant_visible_pool_etablissement$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM public.etablissements e
    JOIN public.soignants s ON s.id = p_soignant_id
    WHERE e.id = p_etablissement_id
      AND e.supprime_le IS NULL
      -- Même règle que public.fn_pool_urgence_etablissement (migration 20261126100000).
      AND private.fn_soignant_contactable_par_etablissement(s.id, e.id)
      AND private.fn_interlocuteur_operationnel_actif(
        p_etablissement_user_id,
        e.id
      )
      AND private.fn_soignant_messagerie_actif(s.id)
      AND COALESCE(s.disponible_urgence, false) IS TRUE
      AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND NOT public.fn_est_exclu(s.id, e.id)
      AND (
        EXISTS (
          SELECT 1
          FROM public.missions mi
          WHERE mi.etablissement_id = e.id
            AND mi.statut IN (
              'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
            )
            AND private.fn_compatibilite_profil_mission(
    s.id, mi.profession_requise, mi.specialite_medicale_requise,
    COALESCE(mi.accepte_non_specialises, true), mi.accepte_internes, mi.fin_le
  )
        )
        OR (private.fn_statut_internat_medical(s.id)->>'statut' = 'NON_CONCERNE' AND NOT EXISTS (
          SELECT 1
          FROM public.missions mi
          WHERE mi.etablissement_id = e.id
            AND mi.statut IN (
              'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
            )
        ))
      )
  ), false);
$fn_soignant_visible_pool_etablissement$;
CREATE OR REPLACE FUNCTION public.fn_notifier_favoris_expirants()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn_notifier_favoris_expirants$
DECLARE
  v_nb integer := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT ms.id AS sauvegarde_id, ms.soignant_id, m.id AS mission_id, m.intitule,
           to_char(m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24hMI') AS debut_txt
    FROM missions_sauvegardees ms
    JOIN missions m ON m.id = ms.mission_id
    WHERE ms.notifie_expiration = false
      AND m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND m.debut_le <= now() + interval '48 hours'
      -- Cohorte de test, et jamais une mission de revue des stores (migration 20261126100000).
      AND private.fn_comptes_meme_cohorte_test(ms.soignant_id, m.etablissement_id)
      AND m.mission_source IS DISTINCT FROM 'REVUE_STORE'
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = m.id AND c.soignant_id = ms.soignant_id
      )
  LOOP
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (
      r.soignant_id, 'SOIGNANT', 'FAVORI_MISSION_EXPIRE',
      '⭐ Ta mission sauvegardée démarre bientôt',
      '« ' || r.intitule || ' » démarre le ' || r.debut_txt || ' — postule avant qu''elle ne parte.',
      '/soignant/missions/' || r.mission_id
    );
    UPDATE missions_sauvegardees SET notifie_expiration = true WHERE id = r.sauvegarde_id;
    v_nb := v_nb + 1;
  END LOOP;
  RETURN v_nb;
END;
$fn_notifier_favoris_expirants$;
CREATE OR REPLACE FUNCTION public.fn_relancer_missions_sans_candidat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn_relancer_missions_sans_candidat$
DECLARE
  v_m record;
  v_missions_relancees integer := 0;
  v_soignants_notifies integer := 0;
  v_nb integer;
BEGIN
  FOR v_m IN
    SELECT m.id, m.intitule, m.profession_requise, m.type_contrat_recherche,
           m.taux_horaire_base, m.debut_le, m.etablissement_id,
           e.nom AS etab_nom, e.adresse_ville AS etab_ville,
           e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
     WHERE m.statut = 'OUVERTE'
       AND m.mode_attribution = 'CANDIDATURE'
       -- Mission de revue des stores : aucune relance, ni à l'établissement ni
       -- aux soignants (migration 20261126100000).
       AND m.mission_source IS DISTINCT FROM 'REVUE_STORE'
       AND m.debut_le > now()
       AND m.cree_le < now() - interval '24 hours'
       AND COALESCE(m.relances_sans_candidat, 0) < 2
       AND (m.derniere_relance_sans_candidat_le IS NULL
            OR m.derniere_relance_sans_candidat_le < now() - interval '48 hours')
       AND NOT EXISTS (
         SELECT 1 FROM public.candidatures c
          WHERE c.mission_id = m.id AND c.statut = 'EN_ATTENTE'
       )
     LIMIT 200
  LOOP
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (
      v_m.etablissement_id, 'MISSION_NON_POURVUE',
      'Aucun candidat pour « ' || public.fn_html_escape(v_m.intitule) || ' »',
      'Votre mission du ' || to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') ||
      ' n’a pas encore de candidat. Les soignants compatibles viennent d’être notifiés. Vérifiez le taux horaire ou alertez le pool d’urgence.',
      '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT'
    );

    WITH cibles AS (
      SELECT s.id
        FROM public.soignants s
       WHERE public.fn_soignant_eligible_mission(s.id, v_m.id, true)
         AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
         AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
         AND NOT EXISTS (
           SELECT 1 FROM public.candidatures c
            WHERE c.mission_id = v_m.id AND c.soignant_id = s.id
         )
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
            WHERE n.destinataire_id = s.id AND n.type = 'MISSION_A_POURVOIR'
              AND n.lien = '/soignant/missions/' || v_m.id
         )
         AND (
           s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
           OR public.fn_haversine_distance_m(
             s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng
           ) <= COALESCE(s.rayon_deplacement_km, 50) * 1000
         )
       LIMIT 25
    )
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    SELECT id, 'MISSION_A_POURVOIR',
      'Mission ' || v_m.profession_requise::text || ' à pourvoir près de chez vous',
      public.fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
      to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
      COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L’établissement cherche encore — postulez vite.',
      '/soignant/missions/' || v_m.id, 'SOIGNANT'
    FROM cibles;
    GET DIAGNOSTICS v_nb = ROW_COUNT;
    v_soignants_notifies := v_soignants_notifies + v_nb;

    UPDATE public.missions
       SET relances_sans_candidat = COALESCE(relances_sans_candidat, 0) + 1,
           derniere_relance_sans_candidat_le = now()
     WHERE id = v_m.id;
    v_missions_relancees := v_missions_relancees + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'missions_relancees', v_missions_relancees,
    'soignants_notifies', v_soignants_notifies
  );
END;
$fn_relancer_missions_sans_candidat$;
CREATE OR REPLACE FUNCTION private.fn_resultats_filtre_missions(p_filtre_id uuid, p_since timestamp with time zone)
RETURNS TABLE(mission_id uuid)
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $fn_resultats_filtre_missions$
DECLARE f public.filtres_sauvegardes; s public.soignants; profession text; accepted text[]; raw text; rayon numeric; ville text;
BEGIN
 SELECT * INTO f FROM public.filtres_sauvegardes WHERE id=p_filtre_id AND audience='SOIGNANT_RECHERCHE_MISSIONS';
 IF NOT FOUND OR NOT private.fn_filtres_recherche_missions_valides(f.filtres) OR NOT private.fn_destinataire_alerte_actif(f.utilisateur_id) THEN RETURN; END IF;
 SELECT * INTO s FROM public.soignants WHERE id=f.utilisateur_id AND supprime_le IS NULL;
 IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.parcours_inscription WHERE user_id=f.utilisateur_id AND type_compte='SOIGNANT') THEN RETURN; END IF;
 profession:=coalesce(s.profession::text,(SELECT donnees->>'profession' FROM public.parcours_inscription WHERE user_id=f.utilisateur_id AND type_compte='SOIGNANT'));
 raw:=trim(coalesce(s.types_contrat_acceptes,''));
 IF raw<>'' THEN
  BEGIN
   IF jsonb_typeof(raw::jsonb)='array' THEN
    IF jsonb_array_length(raw::jsonb)>0 THEN SELECT array_agg(value) INTO accepted FROM jsonb_array_elements_text(raw::jsonb); END IF;
   END IF;
  EXCEPTION WHEN invalid_text_representation THEN NULL; END;
  IF accepted IS NULL THEN SELECT array_agg(trim(x)) INTO accepted FROM unnest(string_to_array(raw,',')) x WHERE trim(x)<>''; END IF;
 END IF;
 IF accepted IS NULL THEN accepted:=CASE s.type_exercice WHEN 'MIXTE' THEN ARRAY['CDD','LIBERAL'] WHEN 'LIBERAL' THEN ARRAY['LIBERAL'] ELSE CASE WHEN s.type_contrat IS NOT NULL THEN ARRAY[s.type_contrat::text] ELSE ARRAY['CDD','VACATION','LIBERAL','SALARIE'] END END; END IF;
 rayon:=coalesce((f.filtres->>'rayonKm')::numeric,s.rayon_deplacement_km,50);
 ville:=lower(trim(coalesce(f.filtres->>'villeRecherche','')));
 RETURN QUERY SELECT m.id FROM public.missions m
 JOIN public.etablissements e ON e.id=m.etablissement_id AND e.supprime_le IS NULL
 CROSS JOIN LATERAL(SELECT coalesce(nullif(m.type_contrat_recherche,''),substring(m.description FROM '\[CONTRAT:(TOUS|SALARIE|LIBERAL)\]'),'TOUS') AS type) contrat
 WHERE m.statut='OUVERTE' AND m.debut_le>=now() AND m.cree_le>p_since AND m.cree_le<=now()
 -- Alertes et aperçus de recherche : jamais une mission de revue des stores (migration 20261126100000).
 AND m.mission_source IS DISTINCT FROM 'REVUE_STORE'
 AND private.fn_destinataire_alerte_actif(e.id)
 AND CASE WHEN s.id IS NULL THEN
   m.soignant_assigne_id IS NULL AND public.fn_mission_publique(m.id) IS NOT NULL
   AND NOT private.fn_mission_lie_compte_test(m.id)
  ELSE private.fn_comptes_meme_cohorte_test(f.utilisateur_id,e.id) END
 AND NOT public.fn_est_exclu(f.utilisateur_id,e.id)
 -- Admission internat commune aussi pour les aperçus et emails de recherches.
 -- Préinscription sans profil : conserve le catalogue public existant.
 AND (s.id IS NULL OR private.fn_internat_compatible(
   private.fn_statut_internat_medical(s.id), m.profession_requise,
   m.specialite_medicale_requise, m.accepte_internes, m.fin_le, m.accepte_non_specialises))
 AND CASE WHEN coalesce(f.filtres->>'profession','')<>'' THEN m.profession_requise::text=f.filtres->>'profession'
  ELSE profession IS NULL OR profession='' OR m.profession_requise::text=profession OR (profession IN ('IADE','IBODE') AND m.profession_requise::text='IDE') END
 AND coalesce(m.taux_horaire_base,0)>=coalesce((f.filtres->>'tauxMin')::numeric,0)
 AND (coalesce((f.filtres->>'urgentesOnly')::boolean,false)=false OR m.est_urgente IS TRUE)
 AND (ville='' OR position(ville IN lower(coalesce(e.adresse_ville,'')))>0 OR starts_with(lower(coalesce(e.adresse_code_postal,'')),ville))
 AND (s.adresse_lat IS NULL OR s.adresse_lng IS NULL OR e.adresse_lat IS NULL OR e.adresse_lng IS NULL OR
  round((6371*2*asin(least(1,sqrt(power(sin(radians(e.adresse_lat-s.adresse_lat)/2),2)+cos(radians(s.adresse_lat))*cos(radians(e.adresse_lat))*power(sin(radians(e.adresse_lng-s.adresse_lng)/2),2)))))::numeric,1)<=rayon)
 AND (contrat.type<>'LIBERAL' OR 'LIBERAL'=ANY(accepted))
 AND (coalesce(f.filtres->>'typeContrat','TOUS')<>'CDD' OR contrat.type<>'LIBERAL')
 AND (coalesce(f.filtres->>'typeContrat','TOUS')<>'LIBERAL' OR contrat.type<>'SALARIE')
 AND private.fn_mission_correspond_horaire(m.id,coalesce(f.filtres->>'horaire','TOUS'));
END $fn_resultats_filtre_missions$;
CREATE OR REPLACE FUNCTION public.fn_mes_favoris_etablissements()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn_mes_favoris_etablissements$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'etablissement_id', e.id,
    'nom', e.nom,
    'ville', e.adresse_ville,
    'logo_url', e.logo_url,
    'type_etablissement', e.type,
    'nb_missions_ouvertes', (
      SELECT count(*) FROM missions m
      WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE' AND m.debut_le > NOW()
        -- Seules les missions que ce soignant peut voir (migration 20261126100000).
        AND private.fn_soignant_voit_mission(v_uid, m.etablissement_id, m.mission_source)
    ),
    'cree_le', f.cree_le
  ) ORDER BY f.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM favoris_soignant_etab f
  JOIN etablissements e ON e.id = f.etablissement_id
  WHERE f.soignant_id = v_uid;

  RETURN v_result;
END;
$fn_mes_favoris_etablissements$;
CREATE OR REPLACE FUNCTION public.fn_admin_generer_posts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn_admin_generer_posts$
DECLARE v jsonb;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.nb DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT m.profession_requise::text AS profession,
           count(*) AS nb,
           max(m.taux_horaire_base) AS taux_max,
           (SELECT string_agg(DISTINCT e2.adresse_ville, ', ')
            FROM (SELECT e3.adresse_ville FROM missions m3
                  JOIN etablissements e3 ON e3.id = m3.etablissement_id
                  WHERE m3.statut='OUVERTE' AND m3.profession_requise = m.profession_requise
                    AND NOT private.fn_mission_lie_compte_test(m3.id)
                  LIMIT 3) e2(adresse_ville)) AS villes
    FROM missions m
    WHERE m.statut = 'OUVERTE'
      -- Textes publics : missions réelles seulement, comme fn_missions_publiques_etablissement
      -- et private.fn_growth_missions_reelles (migration 20261126100000).
      AND NOT private.fn_mission_lie_compte_test(m.id)
    GROUP BY m.profession_requise
  ) t;
  RETURN v;
END;
$fn_admin_generer_posts$;

-- ACL LIVE des deux fonctions private redéfinies (postgres seul), réaffirmées
-- pour les bancs qui ne rejouent pas leurs REVOKE d'origine ; sans effet en production.
REVOKE ALL ON FUNCTION private.fn_soignant_visible_pool_etablissement(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_resultats_filtre_missions(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;

-- ── 7. Inventaire SECURITY DEFINER ─────────────────────────────────────────
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       recense_le = pg_catalog.now()
  FROM pg_catalog.pg_proc p
 WHERE p.oid = pg_catalog.to_regprocedure('public.' || i.signature)
   AND i.signature IN ('fn_pool_urgence_etablissement(uuid)', 'fn_mes_favoris_etablissements()', 'fn_admin_generer_posts()');

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT v.signature, v.categorie, pg_catalog.md5(p.prosrc), v.justification, pg_catalog.now()
  FROM (VALUES
    ('private.fn_est_etablissement_revue_store(uuid)', 'SERVICE_ONLY_REVOQUE',
     'Booléen : établissement de revue des stores désigné, compte de test non supprimé. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100000_cloisonner_missions_cohorte_et_revue.sql'),
    ('private.fn_est_soignant_revue_store(uuid)', 'RPC_UTILISATEUR_AUTH_INTERNE',
     'Booléen lu par la RLS missions_revue_store_soignant_designe et par fn_resoudre_contrat_mission ; schéma private non exposé ; aucune donnée rendue. EXECUTE authenticated et service_role. Source : 20261126100000_cloisonner_missions_cohorte_et_revue.sql'),
    ('private.fn_soignant_voit_mission(uuid,uuid,text)', 'SERVICE_ONLY_REVOQUE',
     'Booléen : cohorte de test et règle REVUE_STORE des RLS missions, pour les lecteurs SECURITY DEFINER. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100000_cloisonner_missions_cohorte_et_revue.sql'),
    ('private.fn_soignant_contactable_par_etablissement(uuid,uuid)', 'SERVICE_ONLY_REVOQUE',
     'Booléen : pool d''urgence (même cohorte, vide pour un établissement de revue). EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100000_cloisonner_missions_cohorte_et_revue.sql')
  ) AS v(signature, categorie, justification)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.signature)
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ── 8. Post-condition : nouveaux corps, ACL inchangées, politique posée ────
DO $cloisonner_apres$
DECLARE
  v_attendu record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', '6db2aebbc7342bb721108b66688b62bc'),
      ('public.fn_resoudre_contrat_mission(uuid,uuid,text)', '91bf0908b53aaca7b5b4ea2cefaf4110'),
      ('public.fn_pool_urgence_etablissement(uuid)', 'a4308cb167e6c0d895efda615c5da297'),
      ('private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)', 'e2d9b4f46afb52b8278c0f71018b2539'),
      ('public.fn_notifier_favoris_expirants()', '8d3fa4597fb5835e8658bc4f31a3730c'),
      ('public.fn_relancer_missions_sans_candidat()', '6d9af12f3446ccdabe4f840d93debfc7'),
      ('private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', 'bf44aa1996cebc52ea272622000876c5'),
      ('public.fn_mes_favoris_etablissements()', '100f3988e20a0446673267ce804bb3b0'),
      ('public.fn_admin_generer_posts()', 'f822983bb47bd93f1d984cdcb41a4b15')
    ) AS t(signature, empreinte)
  LOOP
    IF (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure(v_attendu.signature))
       IS DISTINCT FROM v_attendu.empreinte THEN
      RAISE EXCEPTION 'CLOISONNER_POSTCONDITION : corps installé inattendu pour %.', v_attendu.signature;
    END IF;
  END LOOP;
  IF pg_catalog.has_function_privilege('authenticated', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_resoudre_contrat_mission(uuid,uuid,text)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_pool_urgence_etablissement(uuid)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_pool_urgence_etablissement(uuid)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_notifier_favoris_expirants()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_relancer_missions_sans_candidat()', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_mes_favoris_etablissements()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_admin_generer_posts()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_soignant_visible_pool_etablissement(uuid,uuid,uuid)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_resultats_filtre_missions(uuid,timestamp with time zone)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', 'private.fn_est_soignant_revue_store(uuid)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_est_etablissement_revue_store(uuid)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_soignant_voit_mission(uuid,uuid,text)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_soignant_contactable_par_etablissement(uuid,uuid)', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'CLOISONNER_POSTCONDITION : droits EXECUTE inattendus.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid = 'public.missions'::pg_catalog.regclass
                  AND polname = 'missions_revue_store_soignant_designe' AND NOT polpermissive AND polcmd = 'r')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid = 'public.missions'::pg_catalog.regclass
                  AND polname = 'missions_masquer_etabs_test' AND NOT polpermissive)
  THEN
    RAISE EXCEPTION 'CLOISONNER_POSTCONDITION : politiques RESTRICTIVE de missions absentes.';
  END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory i
              JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(
                CASE WHEN i.signature LIKE 'private.%' THEN i.signature ELSE 'public.' || i.signature END)
             WHERE i.signature IN ('fn_pool_urgence_etablissement(uuid)', 'fn_mes_favoris_etablissements()', 'fn_admin_generer_posts()',
                                   'private.fn_est_etablissement_revue_store(uuid)', 'private.fn_est_soignant_revue_store(uuid)',
                                   'private.fn_soignant_voit_mission(uuid,uuid,text)', 'private.fn_soignant_contactable_par_etablissement(uuid,uuid)')
               AND i.definition_md5 IS DISTINCT FROM pg_catalog.md5(p.prosrc))
  THEN
    RAISE EXCEPTION 'CLOISONNER_POSTCONDITION : inventaire SECURITY DEFINER désaligné.';
  END IF;
END
$cloisonner_apres$;
