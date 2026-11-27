-- Missions de revue App Store : trois missions ouvertes et à venir, en permanence,
-- pour l'établissement de revue désigné ; visibles du seul soignant de revue
-- désigné, diffusées à personne (règles posées par 20261126100000).
--
-- Constat : sans mission ouverte, l'onglet Explorer du soignant de revue est
-- vide pendant l'examen de l'app iOS 2.0.0 (risque de refus pour contenu
-- insuffisant). L'établissement de revue est un compte de test non vérifié
-- (EN_COURS, peut_publier_missions = false) : toutes les RPC de création
-- réelles (fn_creer_mission*, fn_creer_mission_api_v1/v2) refusent par
-- fn_blocage_publication_etab.
--
-- Ce que fait cette migration :
-- 1. public.fn_cleanup_missions_test (cron horaire) épargne les missions
--    REVUE_STORE d'un établissement désigné, et seulement celles-là.
-- 2. private.fn_retirer_missions_revue_store : passe des missions REVUE_STORE
--    ouvertes en EXPIREE (transition de fn_auto_transitions_missions), refuse
--    leurs candidatures en attente (contexte private.candidature_transition_context)
--    et l'écrit au journal d'audit.
--    private.fn_retirer_missions_revue_store_non_conformes : retire toute mission
--    REVUE_STORE ouverte d'un établissement qui n'est pas (ou plus) un
--    établissement de revue désigné de test ; ne lève jamais.
-- 3. private.fn_garantir_missions_revue_store() : SECURITY DEFINER, EXECUTE
--    retiré à PUBLIC, anon, authenticated et service_role, idempotente, verrou
--    consultatif. Pour chaque établissement désigné :
--    - supprimé ou absent : rien, une ligne de journal (RAISE LOG), pas d'échec ;
--    - pas un compte de test : erreur REVUE_STORE_ETABLISSEMENT_REEL (le job de
--      retrait, distinct, a déjà retiré ses missions et validé ce retrait) ;
--    - sinon : retire les missions qui commencent dans moins de 3 jours (avant
--      la fenêtre des vagues urgentes, 48 h) ou au-delà du stock, puis complète
--      à exactement 3 missions OUVERTE : IDE, ouvertes à tous les profils (TOUS,
--      donc aux libéraux), adresse de l'établissement (les missions n'en ont pas
--      d'autre), début J+7 à J+21 heure de Paris (ni dimanche, ni jour férié),
--      créneau de jour de 6 h (aucune pause due), taux au moins égal au plancher
--      parametres_systeme.taux_horaire_minimum_salarie, sur candidature.
--      Chemin de fn_creer_mission_api_v1/v2 (créneaux validés, contexte
--      jolene.creer_mission_context, créneaux puis totaux, nature TVA déclarée),
--      rôle service_role de l'API, sans identité utilisateur : tous les
--      déclencheurs de calcul s'exécutent ; seul fn_blocage_publication_etab
--      n'est pas appelé. Réglages de transaction rétablis.
-- 4. public.fn_supprimer_mon_compte_etablissement (corps LIVE md5
--    a43978aee09ef1ae4a157dbee9911b2f) : les missions REVUE_STORE ouvertes ne
--    bloquent plus la suppression ; elles sont retirées et la désignation levée
--    par private.fn_liberer_revue_store_etablissement, dans la transaction de
--    l'anonymisation. La suppression du soignant de revue (fn_supprimer_mon_compte)
--    ne bloque que sur les missions attribuées : rien à changer, et un soignant
--    désigné supprimé perd sa visibilité (private.fn_est_soignant_revue_store).
-- 5. Crons jolene_missions_revue_store_retrait (04:35 UTC) et
--    jolene_missions_revue_store_quotidien (04:40 UTC), garde pg_extension ;
--    actifs seulement si d'autres crons le sont (production), inactifs sur le
--    staging fermé et les branches (leurs suites SQL refusent tout cron actif).
-- 6. Désignation de l'établissement et du soignant de revue par leurs e-mails
--    (publics dans docs/STORE_METADATA_FR.md) : sans effet si le compte est
--    absent, refus s'il n'est pas un compte de test ; puis premier remplissage
--    et post-condition. Aucun SQL direct en production.
--
-- Contrôles : tests/security/revue-store-missions-isolees.test.sql (staging,
-- ROLLBACK ; même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/revue-store-missions.pg17.mjs), garde statique
-- tests/node/revue-store-missions.node.mjs.
-- B9 (RLS + SECURITY DEFINER) : go écrits de Gabrielle du 24/11/2026 et du 26/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed ────────────────────────────────────────────────
DO $revue_store_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_cleanup_missions_test()', '5a25967b3550051aedbd5cd02dec44e6', true, 'v', 'search_path=public'),
      ('public.fn_supprimer_mon_compte_etablissement()', 'a43978aee09ef1ae4a157dbee9911b2f', true, 'v', 'search_path=public, extensions')
    ) AS t(signature, empreinte, definer, volatilite, config)
  LOOP
    SELECT p.prosrc, p.prosecdef, p.provolatile::text AS volatilite, p.proconfig,
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
      RAISE EXCEPTION 'REVUE_STORE_SOURCE_DIVERGENTE : % en base (md5 %) ne correspond plus au corps attendu (md5 %). Repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature, COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'), v_attendu.empreinte;
    END IF;
  END LOOP;
  IF pg_catalog.to_regclass('private.etablissements_revue_store') IS NULL
     OR pg_catalog.to_regclass('private.soignants_revue_store') IS NULL
     OR pg_catalog.to_regprocedure('private.fn_est_etablissement_revue_store(uuid)') IS NULL
  THEN
    RAISE EXCEPTION 'REVUE_STORE_PREREQUIS : la migration 20261126100000 (cloisonnement) doit précéder celle-ci.';
  END IF;
END
$revue_store_avant$;

-- ── 1. Le nettoyage horaire épargne le seul stock d'un établissement désigné ─
CREATE OR REPLACE FUNCTION public.fn_cleanup_missions_test()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn_cleanup_missions_test$
DECLARE
  v_ids uuid[];
  r record;
BEGIN
  SELECT array_agg(m.id) INTO v_ids
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE e.est_compte_test
    AND m.statut = 'OUVERTE'
    AND m.cree_le < now() - interval '2 hours'
    -- Stock de revue des stores d'un établissement désigné : jamais purgé ici
    -- (migration 20261126100100). Ailleurs, REVUE_STORE est nettoyée comme le reste.
    AND NOT (m.mission_source IS NOT DISTINCT FROM 'REVUE_STORE'
             AND private.fn_est_etablissement_revue_store(m.etablissement_id));

  IF v_ids IS NULL THEN RETURN 0; END IF;

  FOR r IN
    SELECT c.conrelid::regclass::text AS t, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.confrelid = 'public.missions'::regclass AND c.contype = 'f'
  LOOP
    EXECUTE format('DELETE FROM %s WHERE %I = ANY($1)', r.t, r.col) USING v_ids;
  END LOOP;

  DELETE FROM missions WHERE id = ANY(v_ids);
  RETURN array_length(v_ids, 1);
END;
$fn_cleanup_missions_test$;

-- ── 2. Retrait des missions de revue ───────────────────────────────────────
CREATE OR REPLACE FUNCTION private.fn_retirer_missions_revue_store(p_ids uuid[], p_motif text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_retirer_missions_revue_store$
DECLARE
  v_operation uuid := pg_catalog.gen_random_uuid();
  v_ids uuid[];
BEGIN
  SELECT pg_catalog.array_agg(m.id ORDER BY m.id) INTO v_ids
    FROM public.missions m
   WHERE m.id = ANY (p_ids)
     AND m.mission_source = 'REVUE_STORE'
     AND m.statut = 'OUVERTE';
  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;
  -- Même transition que fn_auto_transitions_missions (OUVERTE → EXPIREE).
  UPDATE public.missions m
     SET statut = 'EXPIREE', modifie_le = pg_catalog.now()
   WHERE m.id = ANY (v_ids);
  -- Candidatures en attente refusées, par le contexte de transition canonique.
  INSERT INTO private.candidature_transition_context
    (operation_id, backend_pid, transaction_id, candidature_id, mission_id, allowed_status)
  SELECT v_operation, pg_catalog.pg_backend_pid(), pg_catalog.txid_current(), c.id, c.mission_id, 'REFUSEE'
    FROM public.candidatures c
   WHERE c.mission_id = ANY (v_ids)
     AND c.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');
  UPDATE public.candidatures c
     SET statut = 'REFUSEE',
         motif_refus = 'Mission de démonstration retirée',
         traite_le = pg_catalog.now()
   WHERE c.mission_id = ANY (v_ids)
     AND c.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');
  DELETE FROM private.candidature_transition_context ctx WHERE ctx.operation_id = v_operation;
  INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  SELECT NULL, 'SYSTEME', 'MISSION_MODIFICATION', 'mission', i,
         pg_catalog.jsonb_build_object('source', 'REVUE_STORE', 'statut', 'EXPIREE', 'motif', p_motif,
           'fonction', 'private.fn_retirer_missions_revue_store')
    FROM pg_catalog.unnest(v_ids) AS i;
  RETURN pg_catalog.cardinality(v_ids);
END;
$fn_retirer_missions_revue_store$;
REVOKE ALL ON FUNCTION private.fn_retirer_missions_revue_store(uuid[], text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_retirer_missions_revue_store_non_conformes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_retirer_missions_revue_store_non_conformes$
DECLARE
  v_ids uuid[];
BEGIN
  -- Ne lève jamais : ce retrait doit être validé même quand la garantie échoue.
  SELECT pg_catalog.array_agg(m.id ORDER BY m.id) INTO v_ids
    FROM public.missions m
   WHERE m.mission_source = 'REVUE_STORE'
     AND m.statut = 'OUVERTE'
     AND NOT private.fn_est_etablissement_revue_store(m.etablissement_id);
  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;
  RETURN private.fn_retirer_missions_revue_store(v_ids,
    'Établissement qui n''est pas (ou plus) un établissement de revue désigné de test');
END;
$fn_retirer_missions_revue_store_non_conformes$;
REVOKE ALL ON FUNCTION private.fn_retirer_missions_revue_store_non_conformes() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_liberer_revue_store_etablissement(p_etablissement_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_liberer_revue_store_etablissement$
DECLARE
  v_ids uuid[];
  v_nb integer := 0;
BEGIN
  SELECT pg_catalog.array_agg(m.id ORDER BY m.id) INTO v_ids
    FROM public.missions m
   WHERE m.etablissement_id = p_etablissement_id
     AND m.mission_source = 'REVUE_STORE'
     AND m.statut = 'OUVERTE';
  IF v_ids IS NOT NULL THEN
    v_nb := private.fn_retirer_missions_revue_store(v_ids, 'Suppression du compte établissement de revue');
  END IF;
  DELETE FROM private.etablissements_revue_store d WHERE d.etablissement_id = p_etablissement_id;
  RETURN v_nb;
END;
$fn_liberer_revue_store_etablissement$;
REVOKE ALL ON FUNCTION private.fn_liberer_revue_store_etablissement(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ── 3. Garantie du stock de missions de revue ──────────────────────────────
CREATE OR REPLACE FUNCTION private.fn_garantir_missions_revue_store()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_garantir_missions_revue_store$
DECLARE
  -- Constantes de la revue (sans portée juridique) : stock, marge de retrait,
  -- jours de début possibles (J+7 à J+21, ordre qui étale le stock).
  c_stock constant integer := 3;
  c_marge constant interval := interval '3 days';
  c_jours constant integer[] := ARRAY[7, 14, 21, 10, 17, 12, 19, 8, 15, 9, 16, 11, 18, 13, 20];
  v_aujourdhui date := (pg_catalog.now() AT TIME ZONE 'Europe/Paris')::date;
  v_minimum numeric;
  v_etab record;
  v_modele record;
  v_reglages jsonb;
  v_reglage record;
  v_ids uuid[];
  v_ouvertes integer;
  v_creees integer;
  v_retirees integer;
  v_hors_designation integer;
  v_total_creees integer := 0;
  v_total_retirees integer := 0;
  v_nb_etablissements integer := 0;
  v_nb_ignores integer := 0;
  v_decalage integer;
  v_jour date;
  v_creneaux jsonb;
  v_validation jsonb;
  v_debut timestamptz;
  v_fin timestamptz;
  v_nb integer;
  v_heures numeric;
  v_mission_id uuid;
BEGIN
  -- Une seule exécution à la fois (cron, migration, test).
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('jolene.missions_revue_store', 0));

  -- Missions de revue hors désignation effective : retirées d'abord.
  v_hors_designation := private.fn_retirer_missions_revue_store_non_conformes();

  SELECT p.valeur INTO v_minimum
    FROM public.parametres_systeme p
   WHERE p.cle = 'taux_horaire_minimum_salarie';
  IF v_minimum IS NULL THEN
    RAISE EXCEPTION 'Missions de revue suspendues : le taux horaire minimal d''une mission salariée n''est pas paramétré.'
      USING ERRCODE = 'P0001', HINT = 'TAUX_HORAIRE_MINIMUM_NON_PARAMETRE',
            DETAIL = 'parametres_systeme.taux_horaire_minimum_salarie absent (migration 20261125120000).';
  END IF;

  FOR v_etab IN
    SELECT d.etablissement_id, e.id AS existant, e.supprime_le
      FROM private.etablissements_revue_store d
      LEFT JOIN public.etablissements e ON e.id = d.etablissement_id
     ORDER BY d.etablissement_id
  LOOP
    -- Établissement supprimé ou absent : rien à faire, une ligne de journal.
    IF v_etab.existant IS NULL OR v_etab.supprime_le IS NOT NULL THEN
      RAISE LOG 'REVUE_STORE : établissement désigné % supprimé ou absent, ignoré', v_etab.etablissement_id;
      v_nb_ignores := v_nb_ignores + 1;
      CONTINUE;
    END IF;
    -- Un gap connu reste verrouillé : jamais de mission de revue pour un compte réel.
    PERFORM private.fn_verifier_etablissement_revue_store(v_etab.etablissement_id);
    v_nb_etablissements := v_nb_etablissements + 1;
    v_retirees := 0;
    v_creees := 0;

    -- 1. Retrait : début dans moins de 3 jours, ou au-delà du stock (on garde les plus proches).
    SELECT pg_catalog.array_agg(x.id ORDER BY x.id) INTO v_ids
      FROM (
        SELECT m.id
          FROM public.missions m
         WHERE m.etablissement_id = v_etab.etablissement_id
           AND m.mission_source = 'REVUE_STORE'
           AND m.statut = 'OUVERTE'
           AND m.debut_le < pg_catalog.now() + c_marge
        UNION
        SELECT s.id
          FROM (
            SELECT m.id
              FROM public.missions m
             WHERE m.etablissement_id = v_etab.etablissement_id
               AND m.mission_source = 'REVUE_STORE'
               AND m.statut = 'OUVERTE'
               AND m.debut_le >= pg_catalog.now() + c_marge
             ORDER BY m.debut_le, m.id
            OFFSET c_stock
          ) s
      ) x;
    IF v_ids IS NOT NULL THEN
      v_retirees := private.fn_retirer_missions_revue_store(v_ids,
        'Retrait du stock de revue (début à moins de 3 jours ou surplus)');
    END IF;

    -- 2. Complément jusqu'au stock.
    SELECT pg_catalog.count(*)::integer INTO v_ouvertes
      FROM public.missions m
     WHERE m.etablissement_id = v_etab.etablissement_id
       AND m.mission_source = 'REVUE_STORE'
       AND m.statut = 'OUVERTE';

    IF v_ouvertes < c_stock THEN
      -- Contexte de l'API établissement (fn_creer_mission_api_v1/v2) : rôle
      -- service_role, aucune identité utilisateur. Réglages rétablis plus bas.
      SELECT pg_catalog.jsonb_object_agg(n, COALESCE(pg_catalog.current_setting(n, true), ''))
        INTO v_reglages
        FROM pg_catalog.unnest(ARRAY['request.jwt.claims', 'request.jwt.claim.role', 'request.jwt.claim.sub',
          'jolene.creer_mission_context', 'jolene.planning_exact_managed', 'jolene.sync_in_progress',
          'jolene.tva_mission_managed']) AS n;
      PERFORM pg_catalog.set_config('request.jwt.claims', '{"role":"service_role"}', true);
      PERFORM pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
      PERFORM pg_catalog.set_config('request.jwt.claim.sub', '', true);

      FOREACH v_decalage IN ARRAY c_jours LOOP
        EXIT WHEN v_ouvertes + v_creees >= c_stock;
        v_jour := v_aujourdhui + v_decalage;
        CONTINUE WHEN EXTRACT(ISODOW FROM v_jour) = 7 OR public.fn_est_jour_ferie(v_jour);
        CONTINUE WHEN EXISTS (
          SELECT 1 FROM public.missions m
           WHERE m.etablissement_id = v_etab.etablissement_id
             AND m.mission_source = 'REVUE_STORE'
             AND m.statut = 'OUVERTE'
             AND (m.debut_le AT TIME ZONE 'Europe/Paris')::date = v_jour);

        -- Trois modèles en rotation selon la date ; créneaux de 6 h, sans pause due.
        SELECT t.* INTO v_modele
          FROM (VALUES
            (0, 'Infirmier(e) en médecine polyvalente — poste du matin', 'Médecine polyvalente',
             'Poste du matin en médecine polyvalente : prise en charge d''un secteur de 12 lits, transmissions avec l''équipe de nuit à l''arrivée. Mission d''exemple du compte de démonstration.',
             time '08:00', time '14:00', 34::numeric),
            (1, 'Infirmier(e) en chirurgie ambulatoire', 'Chirurgie ambulatoire',
             'Accueil des patients, préparation préopératoire et surveillance post-interventionnelle en unité ambulatoire. Mission d''exemple du compte de démonstration.',
             time '07:00', time '13:00', 36::numeric),
            (2, 'Infirmier(e) en soins de suite et de réadaptation — après-midi', 'Soins de suite et de réadaptation',
             'Soins techniques et éducation thérapeutique en SSR, en lien avec l''équipe de rééducation. Mission d''exemple du compte de démonstration.',
             time '13:00', time '19:00', 33::numeric)
          ) AS t(rang, intitule, service, description, heure_debut, heure_fin, taux)
         WHERE t.rang = (v_jour - DATE '2026-01-05') % 3;

        v_creneaux := pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'debut', pg_catalog.to_jsonb((v_jour + v_modele.heure_debut) AT TIME ZONE 'Europe/Paris'),
          'fin', pg_catalog.to_jsonb((v_jour + v_modele.heure_fin) AT TIME ZONE 'Europe/Paris')));
        v_validation := public.fn_valider_creneaux_mission_json(v_creneaux, true);
        IF COALESCE((v_validation->>'success')::boolean, false) IS NOT TRUE THEN
          RAISE EXCEPTION 'Missions de revue : créneau refusé (%).', v_validation
            USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_CRENEAU_REFUSE';
        END IF;
        v_debut := (v_validation->>'debut_le')::timestamptz;
        v_fin := (v_validation->>'fin_le')::timestamptz;
        v_nb := (v_validation->>'nb_creneaux')::integer;
        v_heures := (v_validation->>'total_heures')::numeric;

        PERFORM pg_catalog.set_config('jolene.creer_mission_context', 'true', true);
        PERFORM pg_catalog.set_config('jolene.planning_exact_managed', 'true', true);
        INSERT INTO public.missions (
          etablissement_id, intitule, description, profession_requise, service,
          debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base,
          mode_attribution, type_contrat_recherche, mode_remuneration, est_urgente, mission_source
        ) VALUES (
          v_etab.etablissement_id, v_modele.intitule, v_modele.description, 'IDE', v_modele.service,
          v_debut, v_fin, v_heures, v_nb, GREATEST(v_modele.taux, v_minimum),
          'CANDIDATURE', 'TOUS', 'TAUX_HORAIRE', false, 'REVUE_STORE'
        )
        RETURNING id INTO v_mission_id;

        PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'true', true);
        INSERT INTO public.mission_creneaux (mission_id, debut, fin, est_pause, ordre, type_creneau)
        SELECT v_mission_id, (e.element->>'debut')::timestamptz, (e.element->>'fin')::timestamptz,
               false, e.ordre::integer, 'PREVISIONNEL'
          FROM pg_catalog.jsonb_array_elements(v_creneaux) WITH ORDINALITY AS e(element, ordre);
        PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'false', true);
        PERFORM pg_catalog.set_config('jolene.planning_exact_managed', 'false', true);

        UPDATE public.missions
           SET debut_le = v_debut, fin_le = v_fin, duree_heures = v_heures, nb_creneaux = v_nb,
               modifie_le = pg_catalog.now()
         WHERE id = v_mission_id;

        -- Nature TVA déclarée comme fn_creer_mission_api_v2 pour une mission potentiellement libérale.
        PERFORM pg_catalog.set_config('jolene.tva_mission_managed', 'true', true);
        UPDATE public.missions
           SET nature_tva_prestation = CASE WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
                                            ELSE 'SOIN_THERAPEUTIQUE_EXONERE' END,
               nature_tva_declaree_par = NULL,
               nature_tva_declaree_le = CASE WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
                                             ELSE pg_catalog.now() END,
               statut_validation_tva = CASE WHEN type_contrat_recherche::text = 'SALARIE' THEN 'NON_REQUISE'
                                            ELSE 'A_CONFIRMER' END
         WHERE id = v_mission_id;
        PERFORM pg_catalog.set_config('jolene.tva_mission_managed', '', true);
        PERFORM pg_catalog.set_config('jolene.creer_mission_context', '', true);

        INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
        VALUES (NULL, 'SYSTEME', 'MISSION_CREATION', 'mission', v_mission_id,
          pg_catalog.jsonb_build_object('source', 'REVUE_STORE', 'etablissement_id', v_etab.etablissement_id,
            'fonction', 'private.fn_garantir_missions_revue_store', 'debut_le', v_debut));
        v_creees := v_creees + 1;
      END LOOP;

      FOR v_reglage IN SELECT r.key, r.value FROM pg_catalog.jsonb_each_text(v_reglages) AS r LOOP
        PERFORM pg_catalog.set_config(v_reglage.key, v_reglage.value, true);
      END LOOP;

      IF v_ouvertes + v_creees < c_stock THEN
        RAISE EXCEPTION 'Missions de revue : % mission(s) ouverte(s) seulement pour %, calendrier J+7 à J+21 épuisé.',
          v_ouvertes + v_creees, v_etab.etablissement_id
          USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_STOCK_INCOMPLET';
      END IF;
    END IF;

    v_total_creees := v_total_creees + v_creees;
    v_total_retirees := v_total_retirees + v_retirees;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'etablissements', v_nb_etablissements,
    'etablissements_ignores', v_nb_ignores,
    'missions_creees', v_total_creees,
    'missions_retirees', v_total_retirees,
    'missions_retirees_hors_designation', v_hors_designation
  );
END;
$fn_garantir_missions_revue_store$;
COMMENT ON FUNCTION private.fn_garantir_missions_revue_store() IS
  'Garantit exactement 3 missions OUVERTE à venir (mission_source REVUE_STORE) à chaque établissement de test de private.etablissements_revue_store ; ignore un établissement supprimé (journal), refuse tout compte réel. Cron jolene_missions_revue_store_quotidien. Migration 20261126100100.';
REVOKE ALL ON FUNCTION private.fn_garantir_missions_revue_store() FROM PUBLIC, anon, authenticated, service_role;

-- ── 4. Suppression du compte établissement de revue ────────────────────────
CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte_etablissement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn_supprimer_mon_compte_etablissement$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions_actives int;
  v_factures_impayees int;
  v_hash text;
  v_interne text := COALESCE(current_setting('app.internal_operation',true),'');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT id INTO v_etab_id FROM etablissements WHERE id = v_uid FOR UPDATE;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun établissement lié à ce compte');
  END IF;

  IF private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success',true,'deja_anonymise',true);
  END IF;

  -- Garde-fou : missions actives
  SELECT count(*) INTO v_missions_actives FROM missions
   WHERE etablissement_id = v_etab_id
     AND statut IN ('OUVERTE','ASSIGNEE','EN_COURS','LITIGE')
     AND fin_le > NOW()
     -- Missions de revue des stores encore ouvertes : retirées plus bas, dans la
     -- même transaction ; elles ne bloquent pas (migration 20261126100100).
     AND NOT (statut = 'OUVERTE' AND mission_source IS NOT DISTINCT FROM 'REVUE_STORE');
  IF v_missions_actives > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('Vous avez %s mission(s) ouverte(s) ou en cours.', v_missions_actives));
  END IF;

  -- Garde-fou : factures impayées (la suppression n'efface pas une dette)
  SELECT count(*) INTO v_factures_impayees FROM factures
   WHERE etablissement_id = v_etab_id AND statut IN ('EN_ATTENTE','EN_RETARD')
     AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis;
  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('%s facture(s) impayée(s). Réglez-les avant suppression.', v_factures_impayees));
  END IF;

  -- Missions de revue des stores retirées, désignation levée (migration 20261126100100).
  PERFORM private.fn_liberer_revue_store_etablissement(v_etab_id);

  -- Bypass trigger fn_protect_etablissement_commercial pour anonymisation
  PERFORM set_config('app.internal_operation', 'true', true);
  v_hash := encode(extensions.digest(v_etab_id::text || NOW()::text, 'sha256'), 'hex');

  BEGIN
  INSERT INTO private.suppression_etablissement_context(backend_pid,transaction_id,utilisateur_id)
  VALUES(pg_backend_pid(),txid_current(),v_uid);
  -- Anonymisation établissement
  UPDATE etablissements SET
    nom = 'Établissement supprimé',
    siret = '99' || LPAD(LEFT(REGEXP_REPLACE(v_hash, '[^0-9]', '', 'g'), 12), 12, '0'),
    finess = NULL,
    email_contact = v_hash || '@supprime.jolene.app',
    telephone_contact = NULL,
    adresse_rue = '[SUPPRIMÉ]',
    adresse_ville = '[SUPPRIMÉ]',
    adresse_code_postal = '00000',
    adresse_departement = NULL, adresse_lat = NULL, adresse_lng = NULL,
    description = NULL, logo_url = NULL, horaires_ouverture = NULL,
    contrat_url = NULL,
    siret_raison_sociale = NULL, siret_categorie_juridique = NULL,
    siret_code_naf = NULL, siret_est_actif = false,
    chorus_pro_actif = false, chorus_pro_identifiant = NULL,
    sms_actif = false, sms_consent_le = NULL,
    peut_publier_missions = false,
    bloque_auto_le = NOW(),
    bloque_auto_raisons = jsonb_build_array('COMPTE_SUPPRIME_RGPD'),
    supprime_le = NOW(),
    stripe_sepa_payment_method_id = NULL
  WHERE id = v_etab_id;

  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.internal_operation',v_interne,true);
    RAISE;
  END;
  DELETE FROM private.suppression_etablissement_context
  WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current() AND utilisateur_id=v_uid;
  PERFORM set_config('app.internal_operation',v_interne,true);

  -- Tables liées
  DELETE FROM admins_groupe_sante WHERE utilisateur_id = v_uid;
  DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
  DELETE FROM notifications WHERE destinataire_id = v_uid;

  UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

  UPDATE evaluations SET commentaire = NULL
   WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

  DELETE FROM exclusions WHERE exclu_par = v_uid OR exclu_id = v_uid;

  UPDATE partages_rib SET actif = false, expire_le = NOW()
   WHERE etablissement_id = v_etab_id;

  -- Contrats : on conserve (preuves légales) mais anonymise IP/UA
  UPDATE contrats_mission SET
    signature_ip_etablissement = NULL,
    signature_navigateur_etablissement = NULL,
    signature_image_etablissement = NULL
   WHERE etablissement_id = v_etab_id;

  DELETE FROM email_queue WHERE destinataire_id = v_uid;
  UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL
   WHERE destinataire_id = v_uid;

  DELETE FROM calendar_events_sync WHERE connection_id IN
    (SELECT id FROM calendar_connections WHERE utilisateur_id = v_uid);
  DELETE FROM calendar_connections WHERE utilisateur_id = v_uid;
  DELETE FROM api_keys WHERE etablissement_id = v_etab_id;

  -- Audit (type_acteur ADMIN_ETABLISSEMENT, action RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT)
  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (v_uid, 'ADMIN_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT', 'etablissement', v_etab_id,
    jsonb_build_object('anonymise', true));

  INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
  SELECT id,'ETABLISSEMENT',supprime_le,email_contact FROM public.etablissements WHERE id=v_etab_id
  ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
  IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN RAISE EXCEPTION 'Anonymisation établissement non confirmée'; END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Établissement anonymisé. Factures conservées 10 ans (LPF L102 B).',
    'etablissement_id', v_etab_id
  );
END;
$fn_supprimer_mon_compte_etablissement$;

-- ── 5. Inventaire SECURITY DEFINER ─────────────────────────────────────────
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       recense_le = pg_catalog.now()
  FROM pg_catalog.pg_proc p
 WHERE i.signature = 'fn_supprimer_mon_compte_etablissement()'
   AND p.oid = 'public.fn_supprimer_mon_compte_etablissement()'::pg_catalog.regprocedure;

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT v.signature, 'SERVICE_ONLY_REVOQUE', pg_catalog.md5(p.prosrc), v.justification, pg_catalog.now()
  FROM (VALUES
    ('private.fn_garantir_missions_revue_store()',
     'Cron et migration seulement : 3 missions de revue des stores par établissement de test désigné, compte réel refusé. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100100_missions_revue_store.sql'),
    ('private.fn_retirer_missions_revue_store(uuid[],text)',
     'Retrait (EXPIREE) de missions REVUE_STORE ouvertes et refus de leurs candidatures en attente, audit. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100100_missions_revue_store.sql'),
    ('private.fn_retirer_missions_revue_store_non_conformes()',
     'Cron : retrait des missions REVUE_STORE hors désignation effective ; ne lève jamais. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100100_missions_revue_store.sql'),
    ('private.fn_liberer_revue_store_etablissement(uuid)',
     'Appelée par fn_supprimer_mon_compte_etablissement : retrait des missions REVUE_STORE et levée de la désignation. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261126100100_missions_revue_store.sql')
  ) AS v(signature, justification)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.signature)
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ── 6. Crons quotidiens (garde pg_cron pour les branches) ──────────────────
DO $revue_store_cron$
DECLARE
  v_job record;
  v_jobid bigint;
  v_actif boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  -- Posture de l'environnement : actifs en production (crons actifs), inactifs
  -- sur le staging fermé et les branches (aucun cron actif).
  v_actif := EXISTS (SELECT 1 FROM cron.job j
                      WHERE j.active AND j.jobname NOT IN ('jolene_missions_revue_store_retrait',
                                                           'jolene_missions_revue_store_quotidien'));
  FOR v_job IN SELECT j.jobid FROM cron.job j
                WHERE j.jobname IN ('jolene_missions_revue_store_retrait', 'jolene_missions_revue_store_quotidien') LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  -- Retrait d'abord, dans son propre job : validé même si la garantie lève ensuite.
  v_jobid := cron.schedule('jolene_missions_revue_store_retrait', '35 4 * * *',
    $job$SELECT private.fn_retirer_missions_revue_store_non_conformes()$job$);
  PERFORM cron.alter_job(job_id := v_jobid, active := v_actif);
  v_jobid := cron.schedule('jolene_missions_revue_store_quotidien', '40 4 * * *',
    $job$SELECT private.fn_garantir_missions_revue_store()$job$);
  PERFORM cron.alter_job(job_id := v_jobid, active := v_actif);
END
$revue_store_cron$;

-- ── 7. Désignation des comptes de revue, puis premier remplissage ──────────
-- E-mails publics de docs/STORE_METADATA_FR.md : sans effet si le compte est
-- absent (branches, staging) ; un compte réel est refusé par le déclencheur.
INSERT INTO private.etablissements_revue_store (etablissement_id, motif)
SELECT e.id, 'Établissement de revue des stores (app iOS 2.0.0), compte de test.'
  FROM public.etablissements e
  JOIN auth.users u ON u.id = e.id
 WHERE pg_catalog.lower(u.email) = 'etab@jolene.app'
   AND e.supprime_le IS NULL
ON CONFLICT (etablissement_id) DO NOTHING;

INSERT INTO private.soignants_revue_store (soignant_id, motif)
SELECT s.id, 'Soignant de revue des stores (app iOS 2.0.0), compte de test.'
  FROM public.soignants s
  JOIN auth.users u ON u.id = s.id
 WHERE pg_catalog.lower(u.email) = 'marie.lefevre@jolene-demo.dev'
   AND s.supprime_le IS NULL
ON CONFLICT (soignant_id) DO NOTHING;

SELECT private.fn_garantir_missions_revue_store();

-- ── 8. Post-condition ───────────────────────────────────────────────────────
DO $revue_store_apres$
DECLARE
  v_etab record;
  v_attendu record;
BEGIN
  FOR v_etab IN SELECT d.etablissement_id FROM private.etablissements_revue_store d
                 WHERE private.fn_est_etablissement_revue_store(d.etablissement_id) LOOP
    IF (SELECT pg_catalog.count(*) FROM public.missions m
         WHERE m.etablissement_id = v_etab.etablissement_id
           AND m.mission_source = 'REVUE_STORE'
           AND m.statut = 'OUVERTE'
           AND m.profession_requise = 'IDE'
           AND m.type_contrat_recherche IN ('TOUS', 'LIBERAL')
           AND (m.debut_le AT TIME ZONE 'Europe/Paris')::date
               BETWEEN (pg_catalog.now() AT TIME ZONE 'Europe/Paris')::date + 3
                   AND (pg_catalog.now() AT TIME ZONE 'Europe/Paris')::date + 21) <> 3
    THEN
      RAISE EXCEPTION 'REVUE_STORE_POSTCONDITION : stock de missions de revue incorrect pour %.', v_etab.etablissement_id;
    END IF;
  END LOOP;
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_cleanup_missions_test()', 'ee0c90c2fa777643b8261956ef7e3d6f'),
      ('public.fn_supprimer_mon_compte_etablissement()', 'a5dd6e6858e7ad641f4bd353753f3223')
    ) AS t(signature, empreinte)
  LOOP
    IF (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure(v_attendu.signature))
       IS DISTINCT FROM v_attendu.empreinte THEN
      RAISE EXCEPTION 'REVUE_STORE_POSTCONDITION : corps installé inattendu pour %.', v_attendu.signature;
    END IF;
  END LOOP;
  IF pg_catalog.has_function_privilege('anon', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('service_role', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_liberer_revue_store_etablissement(uuid)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_supprimer_mon_compte_etablissement()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_supprimer_mon_compte_etablissement()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'REVUE_STORE_POSTCONDITION : droits EXECUTE inattendus.';
  END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory i
              JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(
                CASE WHEN i.signature LIKE 'private.%' THEN i.signature ELSE 'public.' || i.signature END)
             WHERE (i.signature LIKE 'private.fn_%revue_store%' OR i.signature = 'fn_supprimer_mon_compte_etablissement()')
               AND i.definition_md5 IS DISTINCT FROM pg_catalog.md5(p.prosrc))
  THEN
    RAISE EXCEPTION 'REVUE_STORE_POSTCONDITION : inventaire SECURITY DEFINER désaligné.';
  END IF;
END
$revue_store_apres$;
