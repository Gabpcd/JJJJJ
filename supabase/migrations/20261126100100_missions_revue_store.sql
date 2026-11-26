-- Missions de revue App Store : trois missions ouvertes et à venir, en permanence,
-- pour l'établissement de revue, visibles de la seule cohorte de test (dont le
-- soignant de revue), jamais d'un soignant réel.
--
-- Constat : sans mission ouverte de sa cohorte, l'onglet Explorer du soignant
-- de revue est vide pendant l'examen de l'app iOS 2.0.0 (risque de refus pour
-- contenu insuffisant). L'établissement de revue est un compte de test
-- (est_compte_test, immuable par private.fn_forcer_compte_test_prelaunch), non
-- vérifié (EN_COURS,
-- peut_publier_missions = false) : toutes les RPC de création réelles
-- (fn_creer_mission*, fn_creer_mission_api_v1/v2) refusent par
-- fn_blocage_publication_etab. Le cloisonnement des envois est posé par la
-- migration précédente (20261126100000) : la cohorte de test ne reçoit que les
-- missions de la cohorte de test, et inversement.
--
-- Ce que fait cette migration :
-- 1. mission_source accepte 'REVUE_STORE' (contrainte CHECK relue en LIVE).
-- 2. public.fn_cleanup_missions_test (cron horaire) épargne ces missions
--    (corps LIVE md5 5a25967b3550051aedbd5cd02dec44e6, une condition ajoutée).
-- 3. private.etablissements_revue_store : désignation de l'établissement de
--    revue (paramètre, jamais un identifiant ni un e-mail dans un corps de
--    fonction). Un déclencheur refuse un établissement qui n'est pas un compte
--    de test ; private.fn_garantir_missions_revue_store le revérifie à chaque
--    passage (un gap connu reste verrouillé).
-- 4. private.fn_garantir_missions_revue_store() : idempotente, SECURITY
--    DEFINER, EXECUTE retiré à PUBLIC, anon, authenticated et service_role.
--    Pour chaque établissement désigné : retire (EXPIREE) les missions de
--    revue qui commencent dans moins de 3 jours (avant la fenêtre des vagues
--    urgentes, 48 h) ou qui dépassent le stock, puis complète à exactement
--    3 missions OUVERTE : infirmier (IDE), ouvertes à tous les profils (TOUS,
--    donc aux libéraux), adresse de l'établissement (les missions n'en ont pas
--    d'autre), début entre J+7 et J+21 heure de Paris (ni dimanche, ni jour
--    férié), un créneau de jour de 7 h, taux au moins égal au plancher
--    parametres_systeme.taux_horaire_minimum_salarie, attribution sur
--    candidature. Chemin : celui de fn_creer_mission_api_v1/v2 (créneaux
--    validés par fn_valider_creneaux_mission_json, contexte
--    jolene.creer_mission_context, créneaux puis totaux, nature TVA déclarée),
--    sous le rôle service_role de l'API établissement, sans identité
--    utilisateur : les déclencheurs de calcul (finance, commission, net estimé,
--    contrat, internat, planning) s'exécutent tous. Seul le contrôle
--    fn_blocage_publication_etab n'est pas appelé : c'est l'objet de la
--    fonction, réservée aux comptes de test désignés. Les réglages de
--    transaction modifiés sont rétablis avant la fin.
-- 5. Cron quotidien jolene_missions_revue_store_quotidien (04:40 UTC), garde
--    pg_extension. Il suit la posture de l'environnement : actif si d'autres
--    crons le sont (production), inactif sinon (staging fermé et branches,
--    dont les suites SQL refusent tout cron actif).
-- 6. Désignation de l'établissement de revue par son e-mail de rôle (no-op si
--    le compte n'existe pas, refus explicite s'il n'est pas un compte de test),
--    puis premier remplissage : aucun SQL direct en production.
--
-- Contrôles : tests/security/revue-store-missions-isolees.test.sql (staging,
-- ROLLBACK ; même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/revue-store-missions.pg17.mjs), garde statique
-- tests/node/revue-store-missions.node.mjs.
-- B9 (SECURITY DEFINER) : go écrit de Gabrielle du 24/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed ────────────────────────────────────────────────
DO $revue_store_avant$
DECLARE
  v_proc record;
BEGIN
  SELECT p.prosrc, p.prosecdef, p.provolatile::text AS volatilite, p.proconfig,
         pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
    INTO v_proc
    FROM pg_catalog.pg_proc p
   WHERE p.oid = pg_catalog.to_regprocedure('public.fn_cleanup_missions_test()');
  IF NOT FOUND
    OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM '5a25967b3550051aedbd5cd02dec44e6'
    OR v_proc.prosecdef IS NOT TRUE
    OR v_proc.volatilite IS DISTINCT FROM 'v'
    OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
  THEN
    RAISE EXCEPTION 'REVUE_STORE_SOURCE_DIVERGENTE : public.fn_cleanup_missions_test() ne correspond plus au corps LIVE relu le 26/11/2026 (md5 5a25967b3550051aedbd5cd02dec44e6). Repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).';
  END IF;
  IF (SELECT pg_catalog.pg_get_constraintdef(c.oid) FROM pg_catalog.pg_constraint c
       WHERE c.conrelid = 'public.missions'::pg_catalog.regclass AND c.conname = 'missions_mission_source_check')
     IS DISTINCT FROM 'CHECK ((mission_source = ANY (ARRAY[''SWIPE''::text, ''CANDIDATURE''::text, ''REBOOK''::text, ''PROPOSITION_DIRECTE''::text, ''REMPLACEMENT''::text, ''REPUBLICATION''::text])))'
  THEN
    RAISE EXCEPTION 'REVUE_STORE_CONTRAINTE_DIVERGENTE : missions_mission_source_check ne correspond plus à la définition LIVE relue le 26/11/2026.';
  END IF;
  -- Prérequis : prédicat de cohorte posé par 20261126100000 dans l'éligibilité.
  IF pg_catalog.strpos((SELECT prosrc FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_soignant_eligible_mission(uuid,uuid,boolean)'::pg_catalog.regprocedure),
       'private.fn_comptes_meme_cohorte_test(p_soignant_id, v_mission.etablissement_id)') = 0
  THEN
    RAISE EXCEPTION 'REVUE_STORE_PREREQUIS : la migration 20261126100000 (cloisonnement des envois) doit précéder celle-ci.';
  END IF;
END
$revue_store_avant$;

-- ── 1. Marquage des missions de revue ──────────────────────────────────────
ALTER TABLE public.missions DROP CONSTRAINT missions_mission_source_check;
ALTER TABLE public.missions ADD CONSTRAINT missions_mission_source_check
  CHECK (mission_source = ANY (ARRAY['SWIPE'::text, 'CANDIDATURE'::text, 'REBOOK'::text,
    'PROPOSITION_DIRECTE'::text, 'REMPLACEMENT'::text, 'REPUBLICATION'::text, 'REVUE_STORE'::text]));

-- ── 2. Le nettoyage horaire des missions de test épargne le stock de revue ─
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
    -- Stock des missions de revue App Store (private.fn_garantir_missions_revue_store,
    -- migration 20261126100100) : jamais purgé par ce nettoyage.
    AND m.mission_source IS DISTINCT FROM 'REVUE_STORE';

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

-- ── 3. Désignation de l'établissement de revue ─────────────────────────────
CREATE TABLE IF NOT EXISTS private.etablissements_revue_store (
  etablissement_id uuid PRIMARY KEY REFERENCES public.etablissements(id) ON DELETE CASCADE,
  designe_le timestamptz NOT NULL DEFAULT pg_catalog.now(),
  motif text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(motif)) >= 10)
);
COMMENT ON TABLE private.etablissements_revue_store IS
  'Établissements de test désignés pour la revue des stores : private.fn_garantir_missions_revue_store leur garantit 3 missions ouvertes à venir. Compte de test exigé (déclencheur et revérification). Migration 20261126100100.';
REVOKE ALL ON TABLE private.etablissements_revue_store FROM PUBLIC, anon, authenticated, service_role;

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
            DETAIL = 'private.etablissements_revue_store, migration 20261126100100_missions_revue_store.sql.';
  END IF;
  IF v_etab.est_compte_test IS NOT TRUE THEN
    RAISE EXCEPTION 'Missions de revue refusées : l''établissement % n''est pas un compte de test. Ses missions seraient visibles des soignants réels et leur seraient diffusées.', p_etablissement_id
      USING ERRCODE = 'P0001', HINT = 'REVUE_STORE_ETABLISSEMENT_REEL',
            DETAIL = 'Seul un compte de test (etablissements.est_compte_test) peut être désigné. Migration 20261126100100_missions_revue_store.sql.';
  END IF;
END;
$fn_verifier_etablissement_revue_store$;
COMMENT ON FUNCTION private.fn_verifier_etablissement_revue_store(uuid) IS
  'Lève une erreur si l''établissement désigné pour la revue des stores est absent, supprimé ou n''est pas un compte de test. Migration 20261126100100.';
REVOKE ALL ON FUNCTION private.fn_verifier_etablissement_revue_store(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_trg_verifier_designation_revue_store()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $fn_trg_verifier_designation_revue_store$
BEGIN
  PERFORM private.fn_verifier_etablissement_revue_store(NEW.etablissement_id);
  RETURN NEW;
END;
$fn_trg_verifier_designation_revue_store$;
REVOKE ALL ON FUNCTION private.fn_trg_verifier_designation_revue_store() FROM PUBLIC, anon, authenticated, service_role;

DO $revue_store_declencheur$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgrelid = 'private.etablissements_revue_store'::pg_catalog.regclass
                    AND tgname = 'trg_verifier_designation_revue_store') THEN
    CREATE TRIGGER trg_verifier_designation_revue_store
      BEFORE INSERT OR UPDATE ON private.etablissements_revue_store
      FOR EACH ROW EXECUTE FUNCTION private.fn_trg_verifier_designation_revue_store();
  END IF;
END
$revue_store_declencheur$;

-- ── 4. Garantie du stock de missions de revue ──────────────────────────────
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
  v_total_creees integer := 0;
  v_total_retirees integer := 0;
  v_nb_etablissements integer := 0;
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

  SELECT p.valeur INTO v_minimum
    FROM public.parametres_systeme p
   WHERE p.cle = 'taux_horaire_minimum_salarie';
  IF v_minimum IS NULL THEN
    RAISE EXCEPTION 'Missions de revue suspendues : le taux horaire minimal d''une mission salariée n''est pas paramétré.'
      USING ERRCODE = 'P0001', HINT = 'TAUX_HORAIRE_MINIMUM_NON_PARAMETRE',
            DETAIL = 'parametres_systeme.taux_horaire_minimum_salarie absent (migration 20261125120000).';
  END IF;

  FOR v_etab IN
    SELECT d.etablissement_id FROM private.etablissements_revue_store d ORDER BY d.etablissement_id
  LOOP
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
      -- Même transition que fn_auto_transitions_missions (OUVERTE → EXPIREE).
      UPDATE public.missions m
         SET statut = 'EXPIREE', modifie_le = pg_catalog.now()
       WHERE m.id = ANY (v_ids);
      UPDATE public.candidatures c
         SET statut = 'REFUSEE',
             motif_refus = 'Mission de démonstration retirée',
             traite_le = pg_catalog.now()
       WHERE c.mission_id = ANY (v_ids)
         AND c.statut IN ('EN_ATTENTE', 'PROPOSEE');
      INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
      SELECT NULL, 'SYSTEME', 'MISSION_MODIFICATION', 'mission', i,
             pg_catalog.jsonb_build_object('source', 'REVUE_STORE', 'statut', 'EXPIREE',
               'motif', 'Retrait du stock de revue (début à moins de 3 jours ou surplus)',
               'fonction', 'private.fn_garantir_missions_revue_store')
        FROM pg_catalog.unnest(v_ids) AS i;
      v_retirees := pg_catalog.cardinality(v_ids);
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

        -- Trois modèles en rotation selon la date.
        SELECT t.* INTO v_modele
          FROM (VALUES
            (0, 'Infirmier(e) en médecine polyvalente — poste de jour', 'Médecine polyvalente',
             'Poste de jour en médecine polyvalente : prise en charge d''un secteur de 12 lits, transmissions avec l''équipe de nuit à l''arrivée. Mission d''exemple du compte de démonstration.',
             time '08:00', time '15:00', 34::numeric),
            (1, 'Infirmier(e) en chirurgie ambulatoire', 'Chirurgie ambulatoire',
             'Accueil des patients, préparation préopératoire et surveillance post-interventionnelle en unité ambulatoire. Mission d''exemple du compte de démonstration.',
             time '07:30', time '14:30', 36::numeric),
            (2, 'Infirmier(e) en soins de suite et de réadaptation', 'Soins de suite et de réadaptation',
             'Soins techniques et éducation thérapeutique en SSR, en lien avec l''équipe de rééducation. Mission d''exemple du compte de démonstration.',
             time '09:00', time '16:00', 33::numeric)
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
    'missions_creees', v_total_creees,
    'missions_retirees', v_total_retirees
  );
END;
$fn_garantir_missions_revue_store$;
COMMENT ON FUNCTION private.fn_garantir_missions_revue_store() IS
  'Garantit exactement 3 missions OUVERTE à venir (mission_source REVUE_STORE) à chaque établissement de test de private.etablissements_revue_store ; refuse tout compte réel. Cron jolene_missions_revue_store_quotidien. Migration 20261126100100.';
REVOKE ALL ON FUNCTION private.fn_garantir_missions_revue_store() FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT 'private.fn_garantir_missions_revue_store()', 'SERVICE_ONLY_REVOQUE', pg_catalog.md5(p.prosrc),
       'Cron et migration seulement (EXECUTE retiré à PUBLIC, anon, authenticated, service_role) : missions de revue des stores pour les seuls établissements de test désignés, compte réel refusé. Source : 20261126100100_missions_revue_store.sql',
       pg_catalog.now()
  FROM pg_catalog.pg_proc p
 WHERE p.oid = 'private.fn_garantir_missions_revue_store()'::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ── 5. Cron quotidien (garde pg_cron pour les branches) ────────────────────
DO $revue_store_cron$
DECLARE
  v_job record;
  v_jobid bigint;
  v_actif boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  -- Posture de l'environnement : actif en production (crons actifs), inactif
  -- sur le staging fermé et les branches (aucun cron actif).
  v_actif := EXISTS (SELECT 1 FROM cron.job j
                      WHERE j.active AND j.jobname IS DISTINCT FROM 'jolene_missions_revue_store_quotidien');
  FOR v_job IN SELECT j.jobid FROM cron.job j WHERE j.jobname = 'jolene_missions_revue_store_quotidien' LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  v_jobid := cron.schedule('jolene_missions_revue_store_quotidien', '40 4 * * *',
    $job$SELECT private.fn_garantir_missions_revue_store()$job$);
  PERFORM cron.alter_job(job_id := v_jobid, active := v_actif);
END
$revue_store_cron$;

-- ── 6. Désignation de l'établissement de revue, puis premier remplissage ───
-- E-mail de rôle de l'entreprise : no-op si le compte n'existe pas (branches,
-- staging) ; un compte réel est refusé par le déclencheur de désignation.
INSERT INTO private.etablissements_revue_store (etablissement_id, motif)
SELECT e.id, 'Établissement de revue des stores (app iOS 2.0.0), compte de test.'
  FROM public.etablissements e
  JOIN auth.users u ON u.id = e.id
 WHERE pg_catalog.lower(u.email) = 'etab@jolene.app'
   AND e.supprime_le IS NULL
ON CONFLICT (etablissement_id) DO NOTHING;

SELECT private.fn_garantir_missions_revue_store();

-- ── 7. Post-condition : stock exact pour chaque établissement désigné ──────
DO $revue_store_apres$
DECLARE
  v_etab record;
BEGIN
  FOR v_etab IN SELECT d.etablissement_id FROM private.etablissements_revue_store d LOOP
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
  IF (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_cleanup_missions_test()'::pg_catalog.regprocedure)
     IS DISTINCT FROM '65b1b5874bd9eb6ce2a6715554cf51ab'
    OR pg_catalog.has_function_privilege('anon', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
    OR pg_catalog.has_function_privilege('service_role', 'private.fn_garantir_missions_revue_store()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'REVUE_STORE_POSTCONDITION : nettoyage ou droits EXECUTE inattendus.';
  END IF;
END
$revue_store_apres$;
