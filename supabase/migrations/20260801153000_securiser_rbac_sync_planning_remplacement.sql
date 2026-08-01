-- Le pont legacy matérialise les créneaux d'un remplacement dans un AFTER
-- INSERT, puis recale uniquement son enveloppe et ses compteurs. Le garde
-- d'empêchement doit revalider cette seconde phase avant que le RBAC ne
-- l'autorise : un custom GUC fourni par un client ne suffit jamais.
BEGIN;

CREATE OR REPLACE FUNCTION private.fn_guard_contexte_empechement_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, auth
AS $function$
DECLARE
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
  v_expected text;
  v_original public.missions%ROWTYPE;
  v_planning_nb integer;
  v_planning_debut timestamptz;
  v_planning_fin timestamptz;
  v_planning_total numeric;
BEGIN
  PERFORM set_config('jolene.empechement_mission_validated', '', true);
  IF v_context = '' OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    v_expected := 'FLAG:' || OLD.id::text || ':' || auth.uid()::text;
    IF v_context = v_expected
       AND OLD.id = NEW.id
       AND OLD.soignant_assigne_id = auth.uid()
       AND OLD.statut IN ('ASSIGNEE', 'EN_COURS')
       AND COALESCE(OLD.est_arret_maladie, false) IS FALSE
       AND NEW.est_arret_maladie IS TRUE
       AND NEW.arret_maladie_declare_le IS NOT NULL
       AND (
         to_jsonb(NEW) - ARRAY[
           'est_arret_maladie', 'arret_maladie_declare_le', 'modifie_le'
         ]::text[]
       ) = (
         to_jsonb(OLD) - ARRAY[
           'est_arret_maladie', 'arret_maladie_declare_le', 'modifie_le'
         ]::text[]
       ) THEN
      PERFORM set_config(
        'jolene.empechement_mission_validated', v_context, true
      );
      RETURN NEW;
    END IF;

    v_expected := 'CLOSE:' || OLD.id::text || ':' || auth.uid()::text;
    IF v_context = v_expected
       AND OLD.id = NEW.id
       AND OLD.soignant_assigne_id = auth.uid()
       AND OLD.statut = 'ASSIGNEE'
       AND OLD.debut_le > now()
       AND OLD.est_arret_maladie IS TRUE
       AND NEW.statut = 'ANNULEE_PAR_SOIGNANT'
       AND (
         to_jsonb(NEW) - ARRAY[
           'statut', 'modifie_le'
         ]::text[]
       ) = (
         to_jsonb(OLD) - ARRAY[
           'statut', 'modifie_le'
         ]::text[]
       ) THEN
      PERFORM set_config(
        'jolene.empechement_mission_validated', v_context, true
      );
      RETURN NEW;
    END IF;

    -- Seul l'UPDATE imbriqué du pont planning peut réutiliser le contexte
    -- REPLACEMENT. Les quatre valeurs doivent être exactement les agrégats des
    -- créneaux PREVISIONNEL déjà insérés ; toute autre mutation reste refusée.
    IF NEW.remplacement_de_mission_id IS NOT NULL THEN
      v_expected := 'REPLACEMENT:'
        || NEW.remplacement_de_mission_id::text
        || ':' || auth.uid()::text;

      IF v_context = v_expected
         AND current_setting('jolene.sync_in_progress', true) = 'true'
         AND OLD.id = NEW.id
         AND OLD.remplacement_de_mission_id = NEW.remplacement_de_mission_id
         AND (
           to_jsonb(NEW) - ARRAY[
             'debut_le', 'fin_le', 'duree_heures', 'nb_creneaux'
           ]::text[]
         ) = (
           to_jsonb(OLD) - ARRAY[
             'debut_le', 'fin_le', 'duree_heures', 'nb_creneaux'
           ]::text[]
         )
         AND EXISTS (
           SELECT 1
           FROM public.missions originale
           WHERE originale.id = NEW.remplacement_de_mission_id
             AND originale.soignant_assigne_id = auth.uid()
             AND originale.garantie_remplacement IS TRUE
             AND originale.est_arret_maladie IS TRUE
         ) THEN
        SELECT
          count(*)::integer,
          min(mc.debut),
          max(mc.fin),
          round((sum(
            extract(epoch FROM (mc.fin - mc.debut))
          ) / 3600.0)::numeric, 2)
        INTO
          v_planning_nb,
          v_planning_debut,
          v_planning_fin,
          v_planning_total
        FROM public.mission_creneaux mc
        WHERE mc.mission_id = NEW.id
          AND mc.type_creneau = 'PREVISIONNEL'
          AND NOT mc.est_pause
          AND mc.fin IS NOT NULL;

        IF v_planning_nb > 0
           AND NEW.nb_creneaux = v_planning_nb
           AND NEW.debut_le = v_planning_debut
           AND NEW.fin_le = v_planning_fin
           AND NEW.duree_heures = v_planning_total THEN
          PERFORM set_config(
            'jolene.empechement_mission_validated', v_context, true
          );
          RETURN NEW;
        END IF;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.remplacement_de_mission_id IS NOT NULL THEN
    SELECT *
      INTO v_original
      FROM public.missions
     WHERE id = NEW.remplacement_de_mission_id;

    IF FOUND THEN
      v_expected := 'REPLACEMENT:' || v_original.id::text || ':' || auth.uid()::text;
      IF v_context = v_expected
         AND v_original.soignant_assigne_id = auth.uid()
         AND (
           v_original.statut = 'EN_COURS'
           OR (
             v_original.statut = 'ASSIGNEE'
             AND v_original.debut_le <= now()
           )
           OR (
             v_original.statut = 'ANNULEE_PAR_SOIGNANT'
             AND v_original.debut_le > now()
           )
         )
         AND v_original.fin_le > now() + interval '1 hour'
         AND v_original.garantie_remplacement IS TRUE
         AND v_original.est_arret_maladie IS TRUE
         AND NEW.etablissement_id = v_original.etablissement_id
         AND NEW.intitule = 'REMPLACEMENT URGENT — ' || v_original.intitule
         AND NEW.description = COALESCE(v_original.description, '')
           || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]'
         AND NEW.service IS NOT DISTINCT FROM v_original.service
         AND NEW.profession_requise = v_original.profession_requise
         AND NEW.specialite_medicale_requise
               IS NOT DISTINCT FROM v_original.specialite_medicale_requise
         AND NEW.accepte_non_specialises
               IS NOT DISTINCT FROM v_original.accepte_non_specialises
         AND NEW.debut_le = GREATEST(
           v_original.debut_le, now() + interval '15 minutes'
         )
         AND NEW.fin_le = v_original.fin_le
         AND NEW.duree_heures = round(extract(epoch FROM (
           v_original.fin_le - GREATEST(
             v_original.debut_le, now() + interval '15 minutes'
           )
         )) / 3600.0, 2)
         AND NEW.taux_horaire_base = v_original.taux_horaire_base
         AND NEW.type_contrat_recherche = v_original.type_contrat_recherche
         AND NEW.mode_remuneration = v_original.mode_remuneration
         AND NEW.retrocession_pct IS NOT DISTINCT FROM v_original.retrocession_pct
         AND NEW.mission_source = 'REMPLACEMENT'
         AND NEW.statut = 'OUVERTE'
         AND NEW.soignant_assigne_id IS NULL
         AND NEW.mode_attribution = 'PREMIER_ARRIVE'
         AND NEW.est_urgente IS TRUE
         AND NEW.niveau_urgence = 3
         AND NEW.garantie_remplacement IS TRUE
         AND NEW.remplacement_de_mission_id = v_original.id THEN
        PERFORM set_config(
          'jolene.empechement_mission_validated', v_context, true
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_guard_contexte_empechement_mission()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_enforce_etablissement_rbac_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_row jsonb;
  v_old_row jsonb;
  v_new_row jsonb;
  v_etab_id uuid;
  v_mission_id uuid;
  v_permission text := TG_ARGV[0];
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_TABLE_NAME = 'missions'
     AND v_context <> ''
     AND v_context = COALESCE(
       current_setting('jolene.empechement_mission_validated', true), ''
     )
     AND (
       (
         TG_OP = 'UPDATE'
         AND (
           v_context IN (
             'FLAG:' || (to_jsonb(OLD)->>'id') || ':' || auth.uid()::text,
             'CLOSE:' || (to_jsonb(OLD)->>'id') || ':' || auth.uid()::text
           )
           OR (
             to_jsonb(NEW)->>'remplacement_de_mission_id' IS NOT NULL
             AND v_context = 'REPLACEMENT:'
               || (to_jsonb(NEW)->>'remplacement_de_mission_id')
               || ':' || auth.uid()::text
           )
         )
       )
       OR (
         TG_OP = 'INSERT'
         AND to_jsonb(NEW)->>'remplacement_de_mission_id' IS NOT NULL
         AND v_context = 'REPLACEMENT:'
           || (to_jsonb(NEW)->>'remplacement_de_mission_id')
           || ':' || auth.uid()::text
       )
     ) THEN
    RETURN NEW;
  END IF;

  -- Conserver les transitions Lot 21 protégées par
  -- fn_protect_candidature_statut. Un soignant peut répondre à sa propre
  -- proposition, y compris pour un profil aussi membre d'un établissement.
  IF TG_TABLE_NAME = 'candidatures' THEN
    v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    IF v_row ->> 'soignant_id' = auth.uid()::text
       OR current_setting('jolene.candidature_rpc_mission_id', true)
            = v_row ->> 'mission_id' THEN
      IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
  END IF;

  IF public.fn_role_etablissement_courant(NULL) IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  IF TG_OP = 'UPDATE' THEN
    v_old_row := to_jsonb(OLD);
    v_new_row := to_jsonb(NEW);
  END IF;
  IF COALESCE(v_row ->> 'etablissement_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_etab_id := (v_row ->> 'etablissement_id')::uuid;
  END IF;
  IF v_etab_id IS NULL
     AND COALESCE(v_row ->> 'mission_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_mission_id := (v_row ->> 'mission_id')::uuid;
    SELECT m.etablissement_id INTO v_etab_id
    FROM public.missions m WHERE m.id = v_mission_id;
  END IF;

  IF v_etab_id IS NOT NULL
     AND v_permission = 'missions'
     AND TG_TABLE_NAME = 'missions'
     AND TG_OP = 'UPDATE'
     AND public.fn_a_permission_etablissement('pointage', v_etab_id)
     AND (
       v_new_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) = (
       v_old_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) THEN
    RETURN NEW;
  END IF;

  IF v_etab_id IS NULL
     OR NOT public.fn_a_permission_etablissement(v_permission, v_etab_id) THEN
    RAISE EXCEPTION 'Permission etablissement % requise', v_permission
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_enforce_etablissement_rbac_trigger()
  FROM PUBLIC, anon, authenticated;

-- La protection reste fail-closed : le contexte REPLACEMENT n'est accepté sur
-- UPDATE qu'après comparaison intégrale avec le planning exact matérialisé.
DO $assert_rbac_planning_remplacement$
BEGIN
  IF pg_catalog.position(
       'NEW.nb_creneaux = v_planning_nb'
       IN (
         SELECT p.prosrc
         FROM pg_catalog.pg_proc p
         JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'private'
           AND p.proname = 'fn_guard_contexte_empechement_mission'
       )
     ) = 0 THEN
    RAISE EXCEPTION 'Le sceau RBAC du planning de remplacement est absent';
  END IF;

  IF pg_catalog.has_function_privilege(
       'authenticated',
       'private.fn_guard_contexte_empechement_mission()'::regprocedure,
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Le garde privé est exécutable par authenticated';
  END IF;
END
$assert_rbac_planning_remplacement$;

COMMIT;
