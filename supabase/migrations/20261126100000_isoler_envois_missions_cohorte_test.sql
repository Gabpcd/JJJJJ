-- Envois des missions : la cohorte de test passe par le prédicat de la RLS.
--
-- Contexte (26/11/2026) : la revue App Store de l'app iOS 2.0.0 se fait avec un
-- établissement et un soignant de test. Une mission publiée par un
-- établissement de test ne doit jamais atteindre un soignant réel : ni
-- notification in-app, ni push, ni SMS, ni e-mail, ni affichage. La recherche
-- est déjà cloisonnée par la politique RLS restrictive missions_masquer_etabs_test,
-- dont le prédicat est private.fn_comptes_meme_cohorte_test(soignant,
-- établissement). CLAUDE.md, « filtre de visibilité centralisé » : les envois
-- doivent lire ce même prédicat, pas une règle redécidée sur chaque surface.
--
-- Audit à 4 étages (lecture seule de la production flripxtsyegjshnhzjkz, 26/11/2026) :
-- * pg_proc : 14 fonctions émettent MISSION_A_POURVOIR, MISSION_URGENTE,
--   POOL_URGENCE, FAVORI_NOUVELLE_MISSION, FAVORI_MISSION_EXPIRE,
--   CANDIDATURE_PROPOSEE ou NOUVELLES_MISSIONS_FILTRE. Toutes, sauf deux,
--   choisissent leurs destinataires par public.fn_soignant_eligible_mission
--   (vagues, relances, boost, matching inverse, favoris, pool interne,
--   no-show, escalade, déclencheur urgent) ou par fn_resoudre_contrat_mission
--   (proposition directe, rebook) ; fn_evaluer_alertes_filtres passe par
--   private.fn_resultats_filtre_missions, qui lit déjà le prédicat canonique.
--   fn_soignant_eligible_mission cloisonnait par une comparaison locale
--   (est_compte_test du soignant = est_compte_test de l'établissement), une
--   règle redécidée : elle lit désormais le prédicat canonique. Les deux
--   exceptions : fn_declarer_empechement_imperieux ne fait que compter ces
--   notifications (la diffusion appartient au déclencheur urgent), et
--   fn_notifier_favoris_expirants notifiait tout soignant ayant sauvegardé la
--   mission : elle lit désormais le prédicat.
-- * Étage « établissement » du même audit : public.fn_pool_urgence_etablissement
--   listait tout soignant disponible en urgence, sans cohorte. Ce pool est
--   l'autorisation des envois du navigateur (send-push, send-sms : la cible
--   doit être dans le pool) et de la conversation pool : un établissement de
--   test pouvait voir un soignant réel (messagerie active, disponible en
--   urgence, documents vérifiés) et lui envoyer « Mission urgente ». Corrigé ici.
-- * Hors périmètre, signalé : public.fn_creer_notification est exécutable par
--   authenticated sans contrôle du destinataire ; les écrans qui l'appellent
--   lisent leurs destinataires par une porte cloisonnée (fn_soignants_urgence).
-- * pg_policy : notifications INSERT limité au destinataire lui-même (ou
--   admin) ; missions SELECT déjà cloisonné (RLS restrictive).
-- * src/ et supabase/functions/ : PoolUrgenceEtablissement (send-push via le
--   pool), DetailMission (fn_soignants_urgence, qui passe par l'éligibilité),
--   notif-match (fn_soignant_eligible_mission), digest-hebdo et
--   relance-inactifs (comptes par l'éligibilité, comptes de test écartés).
--
-- Redéfinitions (corps LIVE relus le 26/11/2026, md5(prosrc) identiques à
-- supabase/schema/public.sql ; seules les lignes citées changent) :
-- 1. public.fn_soignant_eligible_mission : la comparaison locale est remplacée
--    par private.fn_comptes_meme_cohorte_test. Aucun changement de résultat :
--    fn_resoudre_contrat_mission, appelée plus bas, appliquait déjà ce
--    prédicat ; la règle a maintenant une seule source.
-- 2. public.fn_pool_urgence_etablissement : filtre ajouté.
-- 3. public.fn_notifier_favoris_expirants : filtre ajouté.
-- En-têtes, SECURITY DEFINER/INVOKER, search_path, propriétaire et ACL sont
-- conservés par CREATE OR REPLACE : aucun GRANT ni REVOKE. Inventaire
-- SECURITY DEFINER : seule fn_pool_urgence_etablissement y est inscrite, son
-- empreinte est mise à jour.
--
-- Contrôles : tests/security/revue-store-missions-isolees.test.sql (staging,
-- ROLLBACK ; même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/revue-store-missions.pg17.mjs), test-garde des émetteurs dans
-- la même suite, garde statique tests/node/revue-store-missions.node.mjs.
-- B9 (SECURITY DEFINER) : go écrit de Gabrielle du 24/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed : corps LIVE attendus ─────────────────────────
DO $isoler_envois_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'f10aeb9ced376cae6ef5a4a863a2cf6b', false, 's', 'search_path=public'),
      ('public.fn_pool_urgence_etablissement(uuid)', '178dbb066ceb8720c38c30ab0fb74f7d', true, 's', 'search_path=""'),
      ('public.fn_notifier_favoris_expirants()', 'd44ae13e1e450ab85942c1863d107b7e', true, 'v', 'search_path=public'),
      ('private.fn_comptes_meme_cohorte_test(uuid,uuid)', '8dbe1d6bdcf7b10bb3a2662f67475196', true, 's', 'search_path=""')
    ) AS t(signature, empreinte, definer, volatilite, config)
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile::text AS volatilite, p.proconfig,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.prosecdef IS DISTINCT FROM v_attendu.definer
      OR v_proc.volatilite IS DISTINCT FROM v_attendu.volatilite
      OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_attendu.config]::text[]
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'ISOLER_ENVOIS_SOURCE_DIVERGENTE : % en base (md5 %) ne correspond plus au corps LIVE relu le 26/11/2026 (md5 %). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature, COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'), v_attendu.empreinte;
    END IF;
  END LOOP;
  -- ACL attendues (conservées par CREATE OR REPLACE, contrôlées après).
  IF pg_catalog.has_function_privilege('anon', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_pool_urgence_etablissement(uuid)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_pool_urgence_etablissement(uuid)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_notifier_favoris_expirants()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_notifier_favoris_expirants()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'ISOLER_ENVOIS_ACL_DIVERGENTE : droits EXECUTE inattendus sur une fonction redéfinie.';
  END IF;
END
$isoler_envois_avant$;

-- ── 1. Éligibilité d'un soignant à une mission : prédicat canonique ────────
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
         m.etablissement_id
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id AND m.statut = 'OUVERTE';
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT profession, specialite_medicale,
         COALESCE(type_exercice, 'SALARIE') AS type_exercice
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id
     AND supprime_le IS NULL
     AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
  IF NOT FOUND THEN RETURN false; END IF;

  -- Cohorte de test : le prédicat de la RLS missions_masquer_etabs_test, source
  -- unique (migration 20261126100000). Vagues, relances, boost, matching
  -- inverse, favoris, pool d'urgence, remplacements et digest en héritent.
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

-- ── 2. Pool d'urgence d'un établissement : même cohorte seulement ─────────
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
    -- Cohorte de test (prédicat de la RLS missions, migration 20261126100000) :
    -- le pool est aussi l'autorisation de send-push, send-sms et de la
    -- conversation pool ; un établissement de test n'y voit jamais un soignant réel.
    AND private.fn_comptes_meme_cohorte_test(s.id, p_etablissement_id)
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

-- ── 3. Missions sauvegardées qui démarrent bientôt : même cohorte ─────────
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
      -- Cohorte de test : prédicat de la RLS missions (migration 20261126100000).
      AND private.fn_comptes_meme_cohorte_test(ms.soignant_id, m.etablissement_id)
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

-- Inventaire SECURITY DEFINER : empreinte du nouveau corps du pool.
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       recense_le = pg_catalog.now()
  FROM pg_catalog.pg_proc p
 WHERE i.signature = 'fn_pool_urgence_etablissement(uuid)'
   AND p.oid = 'public.fn_pool_urgence_etablissement(uuid)'::pg_catalog.regprocedure;

-- ── 4. Post-condition : nouveaux corps, ACL inchangées ─────────────────────
DO $isoler_envois_apres$
BEGIN
  IF (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)'::pg_catalog.regprocedure)
       IS DISTINCT FROM 'f15ef90fcd8a867ecfb375bb37c8d739'
    OR (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_pool_urgence_etablissement(uuid)'::pg_catalog.regprocedure)
       IS DISTINCT FROM '057e327862ee12a7c7cbaacaff8b3ab8'
    OR (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_notifier_favoris_expirants()'::pg_catalog.regprocedure)
       IS DISTINCT FROM 'ad2f2d6c4887de12458807a1b4213bfb'
  THEN
    RAISE EXCEPTION 'ISOLER_ENVOIS_POSTCONDITION : corps installés inattendus.';
  END IF;
  IF pg_catalog.has_function_privilege('anon', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_pool_urgence_etablissement(uuid)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_pool_urgence_etablissement(uuid)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'public.fn_notifier_favoris_expirants()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'ISOLER_ENVOIS_POSTCONDITION : droits EXECUTE modifiés.';
  END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory i
              JOIN pg_catalog.pg_proc p ON p.oid = 'public.fn_pool_urgence_etablissement(uuid)'::pg_catalog.regprocedure
             WHERE i.signature = 'fn_pool_urgence_etablissement(uuid)'
               AND i.definition_md5 IS DISTINCT FROM pg_catalog.md5(p.prosrc))
  THEN
    RAISE EXCEPTION 'ISOLER_ENVOIS_POSTCONDITION : inventaire SECURITY DEFINER désaligné.';
  END IF;
END
$isoler_envois_apres$;
