-- Un planning Jolene est une liste de créneaux datés. L'enveloppe
-- missions.debut_le/fin_le n'est qu'un index de recherche : elle ne doit plus
-- servir à décider si une personne travaille un jour donné.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_valider_creneaux_mission_json(
  p_creneaux jsonb,
  p_appliquer_plafond_48h boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
SET TimeZone TO 'UTC'
AS $function$
DECLARE
  v_nb integer;
  v_min timestamptz;
  v_max timestamptz;
  v_total numeric;
  v_semaine date;
  v_heures_semaine numeric;
  v_repos numeric;
BEGIN
  IF p_creneaux IS NULL OR pg_catalog.jsonb_typeof(p_creneaux) <> 'array' THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Le planning doit être une liste de créneaux datés.'
    );
  END IF;

  v_nb := pg_catalog.jsonb_array_length(p_creneaux);
  IF v_nb = 0 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Ajoutez au moins un créneau travaillé.'
    );
  END IF;
  IF v_nb > 732 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Maximum 732 créneaux par mission.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.jsonb_array_elements(p_creneaux) AS element
    WHERE NULLIF(pg_catalog.btrim(element->>'debut'), '') IS NULL
       OR NULLIF(pg_catalog.btrim(element->>'fin'), '') IS NULL
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Chaque créneau doit avoir un début et une fin.'
    );
  END IF;

  -- Les instants transmis par l'application sont toujours absolus. Refuser les
  -- timestamps sans Z/offset évite qu'une session SQL dans un autre fuseau
  -- transforme silencieusement le planning (notamment lors des changements
  -- d'heure à Paris).
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.jsonb_array_elements(p_creneaux) AS element
    WHERE (element->>'debut') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
       OR (element->>'fin') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Chaque date et heure doit inclure son fuseau (Z ou décalage UTC).'
    );
  END IF;

  WITH creneaux AS (
    SELECT
      ordinality::integer AS ordre,
      (element->>'debut')::timestamptz AS debut,
      (element->>'fin')::timestamptz AS fin
    FROM pg_catalog.jsonb_array_elements(p_creneaux)
      WITH ORDINALITY AS source(element, ordinality)
  )
  SELECT
    pg_catalog.min(debut),
    pg_catalog.max(fin),
    pg_catalog.round(pg_catalog.sum(
      EXTRACT(epoch FROM (fin - debut)) / 3600.0
    )::numeric, 2)
  INTO v_min, v_max, v_total
  FROM creneaux;

  IF (v_max AT TIME ZONE 'Europe/Paris')::date
       - (v_min AT TIME ZONE 'Europe/Paris')::date > 365 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Une mission ne peut pas couvrir plus de 366 dates.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.jsonb_array_elements(p_creneaux) AS element
    WHERE (element->>'fin')::timestamptz <= (element->>'debut')::timestamptz
       OR (element->>'fin')::timestamptz
          > (element->>'debut')::timestamptz + interval '24 hours'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Chaque créneau doit durer plus de 0 h et au maximum 24 h.'
    );
  END IF;

  IF EXISTS (
    WITH creneaux AS (
      SELECT
        ordinality::integer AS ordre,
        (element->>'debut')::timestamptz AS debut,
        (element->>'fin')::timestamptz AS fin
      FROM pg_catalog.jsonb_array_elements(p_creneaux)
        WITH ORDINALITY AS source(element, ordinality)
    )
    SELECT 1
    FROM creneaux a
    JOIN creneaux b ON b.ordre > a.ordre
    WHERE a.debut < b.fin AND a.fin > b.debut
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Deux créneaux de la mission se chevauchent.'
    );
  END IF;

  -- Le plafond de 48 h relève du salariat. Les missions explicitement
  -- libérales conservent les contrôles structurels, de chevauchement et de
  -- repos, mais ne doivent pas être refusées par ce plafond salarié.
  IF COALESCE(p_appliquer_plafond_48h, true) THEN
    -- Ventile réellement les gardes qui traversent un dimanche soir. Une garde
    -- n'est jamais imputée en totalité à la semaine de son heure de début.
    WITH creneaux AS (
    SELECT
      (element->>'debut')::timestamptz AS debut,
      (element->>'fin')::timestamptz AS fin
    FROM pg_catalog.jsonb_array_elements(p_creneaux) AS source(element)
  ), bornes AS (
    SELECT
      debut,
      fin,
      pg_catalog.date_trunc('week', debut AT TIME ZONE 'Europe/Paris')::date AS premiere,
      pg_catalog.date_trunc(
        'week', (fin - interval '1 microsecond') AT TIME ZONE 'Europe/Paris'
      )::date AS derniere
    FROM creneaux
  ), morceaux AS (
    SELECT
      (b.premiere + (numero * 7))::date AS semaine_du,
      b.debut,
      b.fin
    FROM bornes b
    CROSS JOIN LATERAL pg_catalog.generate_series(
      0,
      ((b.derniere - b.premiere) / 7)::integer
    ) AS numero
  ), heures AS (
    SELECT
      semaine_du,
      pg_catalog.sum(
        EXTRACT(epoch FROM (
          LEAST(
            fin,
            (semaine_du + 7)::timestamp AT TIME ZONE 'Europe/Paris'
          ) -
          GREATEST(
            debut,
            semaine_du::timestamp AT TIME ZONE 'Europe/Paris'
          )
        )) / 3600.0
      ) AS total
    FROM morceaux
    GROUP BY semaine_du
  )
    SELECT semaine_du, total
    INTO v_semaine, v_heures_semaine
    FROM heures
    WHERE total > 48
    ORDER BY semaine_du
    LIMIT 1;

    IF v_semaine IS NOT NULL THEN
      RETURN pg_catalog.jsonb_build_object(
        'success', false,
        'error', 'Le planning dépasse 48 h pour la semaine du ' ||
          pg_catalog.to_char(v_semaine, 'DD/MM/YYYY') || '.',
        'code', 'PLAFOND_48H_HEBDO',
        'semaine_du', v_semaine,
        'heures', pg_catalog.round(v_heures_semaine::numeric, 2)
      );
    END IF;
  END IF;

  -- Plusieurs créneaux peuvent composer une même journée (coupure, pause).
  -- Le repos quotidien est contrôlé entre deux journées de travail datées.
  WITH creneaux AS (
    SELECT
      (element->>'debut')::timestamptz AS debut,
      (element->>'fin')::timestamptz AS fin
    FROM pg_catalog.jsonb_array_elements(p_creneaux) AS source(element)
  ), jours AS (
    SELECT
      (debut AT TIME ZONE 'Europe/Paris')::date AS jour,
      pg_catalog.min(debut) AS premier_debut,
      pg_catalog.max(fin) AS derniere_fin
    FROM creneaux
    GROUP BY (debut AT TIME ZONE 'Europe/Paris')::date
  ), ordonnes AS (
    SELECT
      jour,
      premier_debut,
      pg_catalog.lag(derniere_fin) OVER (ORDER BY jour) AS fin_jour_precedent
    FROM jours
  )
  SELECT EXTRACT(epoch FROM (
    premier_debut - fin_jour_precedent
  )) / 3600.0
  INTO v_repos
  FROM ordonnes
  WHERE fin_jour_precedent IS NOT NULL
    AND premier_debut - fin_jour_precedent < interval '11 hours'
  ORDER BY jour
  LIMIT 1;

  IF v_repos IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Repos quotidien insuffisant : ' ||
        pg_catalog.round(v_repos::numeric, 1) ||
        ' h au lieu de 11 h minimum.',
      'code', 'REPOS_11H'
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'nb_creneaux', v_nb,
    'debut_le', v_min,
    'fin_le', v_max,
    'total_heures', v_total
  );
EXCEPTION
  WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Une date ou une heure du planning est invalide.'
    );
  WHEN OTHERS THEN
    RAISE LOG '[fn_valider_creneaux_mission_json] SQLSTATE=% SQLERRM=%',
      SQLSTATE, SQLERRM;
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Planning invalide.',
      'code', 'PLANNING_INVALIDE'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_valider_creneaux_mission_json(jsonb, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_valider_creneaux_mission_json(jsonb, boolean)
  TO service_role;

-- Deux créneaux distincts peuvent appartenir à une même date travaillée. Le
-- plafond historique de 366 portait implicitement sur les dates et empêchait
-- à tort ce cas ; l'API conserve ci-dessus la limite de 366 dates et de 732
-- créneaux exacts.
ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS ck_max_366_creneaux;
ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS ck_max_732_creneaux;
ALTER TABLE public.missions
  ADD CONSTRAINT ck_max_732_creneaux
  CHECK (nb_creneaux >= 0 AND nb_creneaux <= 732) NOT VALID;
ALTER TABLE public.missions
  VALIDATE CONSTRAINT ck_max_732_creneaux;

-- La durée stockée est désormais la somme des créneaux exacts et non la durée
-- de leur enveloppe. L'ancien plafond de 168 h rendait impossibles les séries
-- valides réparties sur plusieurs semaines. La borne reste cohérente avec le
-- maximum structurel de 732 créneaux de 24 h ; les plafonds hebdomadaires plus
-- stricts restent appliqués par fn_valider_creneaux_mission_json.
ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS chk_duree_positive;
ALTER TABLE public.missions
  ADD CONSTRAINT chk_duree_positive
  CHECK (
    duree_heures IS NULL
    OR (duree_heures >= 0 AND duree_heures <= 17568)
  ) NOT VALID;
ALTER TABLE public.missions
  VALIDATE CONSTRAINT chk_duree_positive;

-- Le rattrapage est idempotent et laisse les triggers actifs. Chaque ancienne
-- mission mono-créneau est donc synchronisée individuellement, sans conserver
-- un verrou ACCESS EXCLUSIVE pendant toute la migration.

-- Les anciennes missions ponctuelles sans ligne PREVISIONNEL restent
-- représentables exactement. Une mission multi-créneaux corrompue n'est pas
-- inventée : elle restera explicitement « planning à confirmer » et ne pourra
-- pas être attribuée.
INSERT INTO public.mission_creneaux (
  mission_id, debut, fin, est_pause, ordre, type_creneau
)
SELECT
  m.id, m.debut_le, m.fin_le, false, 1, 'PREVISIONNEL'
FROM public.missions m
WHERE COALESCE(m.nb_creneaux, 0) <= 1
  AND m.debut_le IS NOT NULL
  AND m.fin_le IS NOT NULL
  AND m.fin_le > m.debut_le
  AND m.fin_le <= m.debut_le + interval '24 hours'
  AND NOT EXISTS (
    SELECT 1
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = m.id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
  );

-- nb_creneaux désigne les périodes réellement travaillées. Les pauses ne
-- doivent ni gonfler ce nombre, ni étendre l'enveloppe contractuelle.
CREATE OR REPLACE FUNCTION public.fn_sync_mission_creneaux()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ids uuid[];
  v_mission_id uuid;
  v_debut timestamptz;
  v_fin timestamptz;
  v_duree numeric;
  v_nb integer;
  v_debut_eff timestamptz;
  v_fin_eff timestamptz;
  v_duree_eff numeric;
  v_duree_reference numeric;
BEGIN
  IF pg_catalog.current_setting('jolene.sync_in_progress', true) = 'true' THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_ids := ARRAY[OLD.mission_id];
  ELSIF TG_OP = 'UPDATE' AND OLD.mission_id IS DISTINCT FROM NEW.mission_id THEN
    v_ids := ARRAY[NEW.mission_id, OLD.mission_id];
  ELSE
    v_ids := ARRAY[NEW.mission_id];
  END IF;

  FOREACH v_mission_id IN ARRAY v_ids
  LOOP
    SELECT
      pg_catalog.min(mc.debut),
      pg_catalog.max(mc.fin),
      COALESCE(pg_catalog.sum(
        EXTRACT(epoch FROM (mc.fin - mc.debut)) / 3600.0
      ), 0),
      pg_catalog.count(*)::integer
    INTO v_debut, v_fin, v_duree, v_nb
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = v_mission_id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause;

    SELECT
      pg_catalog.min(mc.debut),
      pg_catalog.max(mc.fin),
      COALESCE(pg_catalog.sum(
        EXTRACT(epoch FROM (mc.fin - mc.debut)) / 3600.0
      ), 0)
    INTO v_debut_eff, v_fin_eff, v_duree_eff
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = v_mission_id
      AND mc.type_creneau = 'EFFECTIF'
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL;

    IF v_duree_eff = 0 AND v_debut_eff IS NULL THEN
      v_duree_eff := NULL;
    END IF;
    v_duree_reference := GREATEST(
      COALESCE(v_duree_eff, 0),
      COALESCE(v_duree, 0)
    );

    PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'true', true);
    UPDATE public.missions
    SET debut_le = CASE WHEN v_nb > 0 THEN v_debut ELSE debut_le END,
        fin_le = CASE WHEN v_nb > 0 THEN v_fin ELSE fin_le END,
        nb_creneaux = v_nb,
        duree_heures = CASE
          WHEN v_nb > 0 OR v_duree_eff IS NOT NULL
            THEN pg_catalog.round(v_duree_reference::numeric, 2)
          ELSE NULL
        END,
        debut_effectif = v_debut_eff,
        fin_effective = v_fin_eff,
        duree_heures_effective = CASE
          WHEN v_duree_eff IS NOT NULL
            THEN pg_catalog.round(v_duree_eff::numeric, 2)
          ELSE NULL
        END
    WHERE id = v_mission_id;
    PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'false', true);
  END LOOP;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_sync_mission_creneaux()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sync_mission_creneaux()
  TO service_role;

SELECT pg_catalog.set_config('jolene.sync_in_progress', 'true', true);
-- Cette mise en cohérence ne modifie ni clés ni état métier. Désactiver les
-- triggers pour cette seule instruction évite leurs effets secondaires
-- historiques sans ALTER TABLE ... DISABLE TRIGGER, donc sans verrou exclusif
-- conservé jusqu'au commit.
SET LOCAL session_replication_role = replica;

WITH planning AS (
  SELECT
    mc.mission_id,
    pg_catalog.min(mc.debut) FILTER (WHERE NOT mc.est_pause) AS debut,
    pg_catalog.max(mc.fin) FILTER (WHERE NOT mc.est_pause) AS fin,
    pg_catalog.count(*) FILTER (WHERE NOT mc.est_pause)::integer AS nb,
    pg_catalog.round((COALESCE(
      pg_catalog.sum(EXTRACT(epoch FROM (mc.fin - mc.debut)))
        FILTER (WHERE NOT mc.est_pause AND mc.fin IS NOT NULL),
      0
    ) / 3600.0)::numeric, 2) AS heures
  FROM public.mission_creneaux mc
  WHERE mc.type_creneau = 'PREVISIONNEL'
  GROUP BY mc.mission_id
)
UPDATE public.missions m
SET debut_le = CASE WHEN p.nb > 0 THEN p.debut ELSE m.debut_le END,
    fin_le = CASE WHEN p.nb > 0 THEN p.fin ELSE m.fin_le END,
    nb_creneaux = p.nb,
    duree_heures = CASE WHEN p.nb > 0 THEN p.heures ELSE m.duree_heures END
FROM planning p
WHERE p.mission_id = m.id
  AND (
    m.debut_le IS DISTINCT FROM CASE WHEN p.nb > 0 THEN p.debut ELSE m.debut_le END
    OR m.fin_le IS DISTINCT FROM CASE WHEN p.nb > 0 THEN p.fin ELSE m.fin_le END
    OR m.nb_creneaux IS DISTINCT FROM p.nb
    OR m.duree_heures IS DISTINCT FROM CASE
      WHEN p.nb > 0 THEN p.heures ELSE m.duree_heures
    END
  );

SET LOCAL session_replication_role = origin;
SELECT pg_catalog.set_config('jolene.sync_in_progress', 'false', true);

-- Pont d'expansion pour les producteurs encore déployés pendant le rollout.
-- Un remplacement recopie et tronque le planning de la mission source ; les
-- autres insertions legacy ne peuvent représenter qu'un créneau continu de
-- 24 h maximum. Les producteurs exacts posent jolene.planning_exact_managed
-- et insèrent eux-mêmes toutes les lignes après la mission.
CREATE OR REPLACE FUNCTION public.dec_initialiser_planning_exact_legacy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_nb integer := 0;
  v_debut timestamptz;
  v_fin timestamptz;
  v_total numeric;
BEGIN
  IF pg_catalog.current_setting(
       'jolene.planning_exact_managed', true
     ) = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.debut_le IS NULL
     OR NEW.fin_le IS NULL
     OR NEW.fin_le <= NEW.debut_le THEN
    IF NEW.statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS') THEN
      RAISE EXCEPTION
        '[PLANNING_DETAILLE_INDISPONIBLE] Une mission active exige des dates valides.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'true', true);

  IF NEW.remplacement_de_mission_id IS NOT NULL THEN
    INSERT INTO public.mission_creneaux (
      mission_id, debut, fin, est_pause, ordre, type_creneau
    )
    SELECT
      NEW.id,
      GREATEST(mc.debut, NEW.debut_le),
      LEAST(mc.fin, NEW.fin_le),
      false,
      pg_catalog.row_number() OVER (
        ORDER BY GREATEST(mc.debut, NEW.debut_le), mc.ordre, mc.id
      )::integer,
      'PREVISIONNEL'
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = NEW.remplacement_de_mission_id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
      AND LEAST(mc.fin, NEW.fin_le) > GREATEST(mc.debut, NEW.debut_le)
    ORDER BY GREATEST(mc.debut, NEW.debut_le), mc.ordre, mc.id;
    GET DIAGNOSTICS v_nb = ROW_COUNT;

    IF v_nb = 0 THEN
      RAISE EXCEPTION
        '[PLANNING_SOURCE_INDISPONIBLE] Le remplacement exige le planning exact de la mission source.'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    IF NEW.fin_le > NEW.debut_le + interval '24 hours' THEN
      RAISE EXCEPTION
        '[PLANNING_EXACT_REQUIS] Une mission legacy de plus de 24 h doit fournir ses créneaux datés.'
        USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.mission_creneaux (
      mission_id, debut, fin, est_pause, ordre, type_creneau
    ) VALUES (
      NEW.id, NEW.debut_le, NEW.fin_le, false, 1, 'PREVISIONNEL'
    );
    v_nb := 1;
  END IF;

  SELECT
    pg_catalog.min(mc.debut),
    pg_catalog.max(mc.fin),
    pg_catalog.round((pg_catalog.sum(
      EXTRACT(epoch FROM (mc.fin - mc.debut))
    ) / 3600.0)::numeric, 2),
    pg_catalog.count(*)::integer
  INTO v_debut, v_fin, v_total, v_nb
  FROM public.mission_creneaux mc
  WHERE mc.mission_id = NEW.id
    AND mc.type_creneau = 'PREVISIONNEL'
    AND NOT mc.est_pause;

  UPDATE public.missions
  SET debut_le = v_debut,
      fin_le = v_fin,
      duree_heures = v_total,
      nb_creneaux = v_nb
  WHERE id = NEW.id;

  PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'false', true);
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_initialiser_planning_exact_legacy()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_initialiser_planning_exact_legacy()
  TO service_role;

DROP TRIGGER IF EXISTS trg_initialiser_planning_exact_legacy
  ON public.missions;
CREATE TRIGGER trg_initialiser_planning_exact_legacy
AFTER INSERT ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_initialiser_planning_exact_legacy();

CREATE OR REPLACE FUNCTION public.dec_refuser_chevauchement_soignant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_nb integer;
  v_nb_complets integer;
  v_autre_mission uuid;
BEGIN
  IF NEW.soignant_assigne_id IS NULL
     OR NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN NEW;
  END IF;

  -- Phase expand/contract : les nouveaux RPC comparent le planning confirmé,
  -- mais les clients déjà ouverts peuvent encore appeler les anciens RPC.
  -- Le trigger conserve donc l'invariant serveur essentiel (planning complet,
  -- absence de conflit) sans exiger un GUC que ces clients ne connaissent pas.

  SELECT
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) FILTER (WHERE mc.fin IS NOT NULL)::integer
  INTO v_nb, v_nb_complets
  FROM public.mission_creneaux mc
  WHERE mc.mission_id = NEW.id
    AND mc.type_creneau = 'PREVISIONNEL'
    AND NOT mc.est_pause;

  -- À l'INSERT legacy, le trigger AFTER ci-dessus n'a pas encore matérialisé
  -- les créneaux. Son UPDATE de la mission repasse ensuite ici avec le planning
  -- complet et rejoue donc les contrôles de conflit et de repos avant commit.
  IF TG_OP = 'INSERT'
     AND v_nb = 0
     AND pg_catalog.current_setting(
       'jolene.planning_exact_managed', true
     ) IS DISTINCT FROM 'true' THEN
    RETURN NEW;
  END IF;

  IF v_nb = 0
     OR v_nb_complets <> v_nb
     OR (COALESCE(NEW.nb_creneaux, 0) > 0 AND NEW.nb_creneaux <> v_nb) THEN
    RAISE EXCEPTION
      '[PLANNING_DETAILLE_INDISPONIBLE] Cette mission ne peut pas être attribuée sans planning daté complet.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.missions autre
    WHERE autre.soignant_assigne_id = NEW.soignant_assigne_id
      AND autre.id <> NEW.id
      AND autre.statut IN ('ASSIGNEE', 'EN_COURS')
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.mission_creneaux mc
          WHERE mc.mission_id = autre.id
            AND mc.type_creneau = 'PREVISIONNEL'
            AND NOT mc.est_pause
        )
        OR EXISTS (
          SELECT 1
          FROM public.mission_creneaux mc
          WHERE mc.mission_id = autre.id
            AND mc.type_creneau = 'PREVISIONNEL'
            AND NOT mc.est_pause
            AND mc.fin IS NULL
        )
        OR (
          COALESCE(autre.nb_creneaux, 0) > 0
          AND autre.nb_creneaux <> (
            SELECT pg_catalog.count(*)::integer
            FROM public.mission_creneaux mc
            WHERE mc.mission_id = autre.id
              AND mc.type_creneau = 'PREVISIONNEL'
              AND NOT mc.est_pause
          )
        )
      )
  ) THEN
    RAISE EXCEPTION
      '[PLANNING_DETAILLE_INDISPONIBLE] Une mission déjà attribuée à ce soignant possède un planning incomplet.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT autre.id
  INTO v_autre_mission
  FROM public.mission_creneaux cible
  JOIN public.missions autre
    ON autre.soignant_assigne_id = NEW.soignant_assigne_id
   AND autre.id <> NEW.id
   AND autre.statut IN ('ASSIGNEE', 'EN_COURS')
  JOIN public.mission_creneaux existant
    ON existant.mission_id = autre.id
   AND existant.type_creneau = 'PREVISIONNEL'
   AND NOT existant.est_pause
   AND existant.fin IS NOT NULL
  WHERE cible.mission_id = NEW.id
    AND cible.type_creneau = 'PREVISIONNEL'
    AND NOT cible.est_pause
    AND cible.fin IS NOT NULL
    AND cible.debut < existant.fin
    AND cible.fin > existant.debut
  ORDER BY existant.debut
  LIMIT 1;

  IF v_autre_mission IS NOT NULL THEN
    RAISE EXCEPTION
      'Ce soignant a déjà une mission sur l''un des créneaux travaillés.'
      USING ERRCODE = 'exclusion_violation',
            DETAIL = 'mission_conflictuelle=' || v_autre_mission::text;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_refuser_chevauchement_soignant()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_refuser_chevauchement_soignant()
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_verifier_repos_11h()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ecart numeric;
  v_autre_mission uuid;
  v_sens text;
BEGIN
  IF NEW.soignant_assigne_id IS NULL
     OR NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN NEW;
  END IF;

  WITH cible AS (
    SELECT mc.debut, mc.fin
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = NEW.id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
  ), existants AS (
    SELECT m.id AS mission_id, mc.debut, mc.fin
    FROM public.missions m
    JOIN public.mission_creneaux mc ON mc.mission_id = m.id
    WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
      AND m.id <> NEW.id
      AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
      AND mc.type_creneau = CASE
        WHEN m.statut = 'TERMINEE' AND EXISTS (
          SELECT 1
          FROM public.mission_creneaux effectif
          WHERE effectif.mission_id = m.id
            AND effectif.type_creneau = 'EFFECTIF'
            AND NOT effectif.est_pause
            AND effectif.fin IS NOT NULL
        ) THEN 'EFFECTIF'
        ELSE 'PREVISIONNEL'
      END
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
  ), ecarts AS (
    SELECT
      e.mission_id,
      CASE
        WHEN e.fin <= c.debut THEN
          EXTRACT(epoch FROM (c.debut - e.fin)) / 3600.0
        WHEN c.fin <= e.debut THEN
          EXTRACT(epoch FROM (e.debut - c.fin)) / 3600.0
        ELSE NULL
      END AS heures,
      CASE WHEN e.fin <= c.debut THEN 'avant' ELSE 'apres' END AS sens
    FROM cible c
    CROSS JOIN existants e
  )
  SELECT heures, mission_id, sens
  INTO v_ecart, v_autre_mission, v_sens
  FROM ecarts
  WHERE heures >= 0 AND heures < 11
  ORDER BY heures
  LIMIT 1;

  IF v_ecart IS NOT NULL THEN
    RAISE EXCEPTION
      '[CODE DU TRAVAIL] Repos insuffisant % mission : % heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.',
      v_sens, pg_catalog.round(v_ecart, 1)
      USING ERRCODE = 'check_violation',
            DETAIL = 'mission_conflictuelle=' || v_autre_mission::text;
  END IF;

  INSERT INTO public.conformite_travail (
    soignant_id, mission_id, type_controle, resultat
  ) VALUES (
    NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'CONFORME'
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_verifier_repos_11h()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_repos_11h()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise public.type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE',
  p_specialite_medicale_requise text DEFAULT NULL,
  p_accepte_non_specialises boolean DEFAULT true,
  p_creneaux jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_etablissement_id uuid;
  v_blocage jsonb;
  v_validation jsonb;
  v_mission_id uuid;
  v_debut timestamptz;
  v_fin timestamptz;
  v_nb integer;
  v_total numeric;
  v_mode text;
  v_type_contrat_recherche text;
BEGIN
  v_etablissement_id := public.mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Accès refusé.');
  END IF;

  v_blocage := public.fn_blocage_publication_etab(v_etablissement_id);
  IF v_blocage IS NOT NULL THEN RETURN v_blocage; END IF;

  IF p_intitule IS NULL OR pg_catalog.length(pg_catalog.btrim(p_intitule)) < 3 THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'L''intitulé doit contenir au moins 3 caractères.'
    );
  END IF;
  IF p_profession_requise IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'La profession requise est obligatoire.');
  END IF;
  IF p_taux_horaire_base IS NULL OR p_taux_horaire_base <= 0 THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Le taux horaire doit être supérieur à zéro.');
  END IF;

  v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
  IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Mode d''attribution invalide.');
  END IF;

  -- L'adaptateur historique transporte encore le régime dans le tag de
  -- description. Le régime ainsi résolu est écrit sur la mission dans la même
  -- transaction : un appel direct ne peut donc pas contourner le plafond tout
  -- en créant finalement une mission salariée.
  v_type_contrat_recherche := CASE
    WHEN COALESCE(p_description, '') ~ '\[CONTRAT:LIBERAL\]' THEN 'LIBERAL'
    WHEN COALESCE(p_description, '') ~ '\[CONTRAT:SALARIE\]' THEN 'SALARIE'
    ELSE 'TOUS'
  END;

  v_validation := public.fn_valider_creneaux_mission_json(
    p_creneaux,
    v_type_contrat_recherche <> 'LIBERAL'
  );
  IF COALESCE((v_validation->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_validation;
  END IF;

  v_debut := (v_validation->>'debut_le')::timestamptz;
  v_fin := (v_validation->>'fin_le')::timestamptz;
  v_nb := (v_validation->>'nb_creneaux')::integer;
  v_total := (v_validation->>'total_heures')::numeric;

  IF v_debut < pg_catalog.now() AND NOT public.est_admin() THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La mission ne peut pas commencer dans le passé.'
    );
  END IF;

  PERFORM pg_catalog.set_config('jolene.creer_mission_context', 'true', true);
  PERFORM pg_catalog.set_config(
    'jolene.planning_exact_managed', 'true', true
  );
  INSERT INTO public.missions (
    etablissement_id,
    intitule,
    description,
    profession_requise,
    service,
    debut_le,
    fin_le,
    duree_heures,
    nb_creneaux,
    taux_horaire_base,
    est_urgente,
    niveau_urgence,
    mode_attribution,
    type_contrat_recherche,
    specialite_medicale_requise,
    accepte_non_specialises
  ) VALUES (
    v_etablissement_id,
    pg_catalog.btrim(p_intitule),
    p_description,
    p_profession_requise,
    NULLIF(pg_catalog.btrim(p_service), ''),
    v_debut,
    v_fin,
    v_total,
    v_nb,
    p_taux_horaire_base,
    COALESCE(p_est_urgente, false),
    CASE WHEN COALESCE(p_est_urgente, false)
      THEN GREATEST(1, LEAST(COALESCE(p_niveau_urgence, 1), 3))
      ELSE 0
    END,
    v_mode,
    v_type_contrat_recherche,
    CASE WHEN p_profession_requise = 'MEDECIN'
      THEN NULLIF(pg_catalog.btrim(p_specialite_medicale_requise), '')
      ELSE NULL
    END,
    CASE WHEN p_profession_requise IN ('IBODE', 'IADE')
      THEN COALESCE(p_accepte_non_specialises, true)
      ELSE true
    END
  )
  RETURNING id INTO v_mission_id;

  PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'true', true);
  INSERT INTO public.mission_creneaux (
    mission_id, debut, fin, est_pause, ordre, type_creneau
  )
  SELECT
    v_mission_id,
    (element->>'debut')::timestamptz,
    (element->>'fin')::timestamptz,
    false,
    pg_catalog.row_number() OVER (
      ORDER BY (element->>'debut')::timestamptz,
               (element->>'fin')::timestamptz,
               ordinality
    )::integer,
    'PREVISIONNEL'
  FROM pg_catalog.jsonb_array_elements(p_creneaux)
    WITH ORDINALITY AS source(element, ordinality)
  ORDER BY (element->>'debut')::timestamptz,
           (element->>'fin')::timestamptz,
           ordinality;
  PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'false', true);
  PERFORM pg_catalog.set_config(
    'jolene.planning_exact_managed', 'false', true
  );

  UPDATE public.missions
  SET debut_le = v_debut,
      fin_le = v_fin,
      duree_heures = v_total,
      nb_creneaux = v_nb,
      modifie_le = pg_catalog.now()
  WHERE id = v_mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    (SELECT auth.uid()),
    CASE WHEN public.est_admin() THEN 'ADMIN' ELSE 'ADMIN_ETABLISSEMENT' END,
    'MISSION_CREATION',
    'mission',
    v_mission_id,
    NULL,
    pg_catalog.jsonb_build_object(
      'nb_creneaux', v_nb,
      'debut_le', v_debut,
      'fin_le', v_fin,
      'total_heures', v_total,
      'planning_source', 'CRENEAUX_DATES'
    ),
    NULL,
    NULL
  );

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'mission_id', v_mission_id,
    'nb_creneaux', v_nb,
    'total_heures', v_total
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[fn_creer_mission_multi_jours] SQLSTATE=% SQLERRM=%',
      SQLSTATE, SQLERRM;
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La création de la mission est temporairement indisponible.',
      'code', 'CREATION_MISSION_INDISPONIBLE'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_creer_mission_multi_jours(
  text, text, public.type_profession, text, numeric, boolean, integer,
  text, text, boolean, jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission_multi_jours(
  text, text, public.type_profession, text, numeric, boolean, integer,
  text, text, boolean, jsonb
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement_v3(
  p_mission_id uuid,
  p_intitule text,
  p_description text DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_profession_requise public.type_profession DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE',
  p_type_contrat_recherche text DEFAULT 'SALARIE',
  p_specialite_medicale_requise text DEFAULT NULL,
  p_accepte_non_specialises boolean DEFAULT true,
  p_creneaux jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_validation jsonb;
  v_debut timestamptz;
  v_fin timestamptz;
  v_nb integer;
  v_total numeric;
  v_planning_modifie boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Non authentifié.');
  END IF;

  SELECT m.*
  INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND OR public.fn_a_permission_etablissement(
    'missions', v_mission.etablissement_id
  ) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Mission introuvable ou accès refusé.'
    );
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Seules les missions ouvertes peuvent être modifiées.'
    );
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = p_mission_id
      AND mc.type_creneau = 'EFFECTIF'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Le planning ne peut plus être modifié après un pointage.'
    );
  END IF;

  IF p_intitule IS NULL OR pg_catalog.length(pg_catalog.btrim(p_intitule)) < 3 THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'L''intitulé doit contenir au moins 3 caractères.');
  END IF;
  IF p_profession_requise IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'La profession requise est obligatoire.');
  END IF;
  IF p_taux_horaire_base IS NULL OR p_taux_horaire_base <= 0 THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Le taux horaire doit être supérieur à zéro.');
  END IF;
  IF p_mode_attribution IS NULL
     OR p_mode_attribution NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Mode d''attribution invalide.');
  END IF;
  IF p_type_contrat_recherche IS NULL
     OR p_type_contrat_recherche NOT IN ('SALARIE', 'LIBERAL', 'TOUS') THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Type de contrat invalide.');
  END IF;

  v_validation := public.fn_valider_creneaux_mission_json(
    p_creneaux,
    p_type_contrat_recherche <> 'LIBERAL'
  );
  IF COALESCE((v_validation->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_validation;
  END IF;
  v_debut := (v_validation->>'debut_le')::timestamptz;
  v_fin := (v_validation->>'fin_le')::timestamptz;
  v_nb := (v_validation->>'nb_creneaux')::integer;
  v_total := (v_validation->>'total_heures')::numeric;

  IF v_debut < pg_catalog.now() AND NOT public.est_admin() THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Une mission ouverte ne peut pas être déplacée dans le passé.'
    );
  END IF;

  WITH nouveaux AS (
    SELECT
      (element->>'debut')::timestamptz AS debut,
      (element->>'fin')::timestamptz AS fin
    FROM pg_catalog.jsonb_array_elements(p_creneaux) AS source(element)
  ), differences AS (
    (SELECT mc.debut, mc.fin
     FROM public.mission_creneaux mc
     WHERE mc.mission_id = p_mission_id
       AND mc.type_creneau = 'PREVISIONNEL'
       AND NOT mc.est_pause
     EXCEPT
     SELECT n.debut, n.fin FROM nouveaux n)
    UNION ALL
    (SELECT n.debut, n.fin FROM nouveaux n
     EXCEPT
     SELECT mc.debut, mc.fin
     FROM public.mission_creneaux mc
     WHERE mc.mission_id = p_mission_id
       AND mc.type_creneau = 'PREVISIONNEL'
       AND NOT mc.est_pause)
  )
  SELECT EXISTS (SELECT 1 FROM differences)
    OR (
      SELECT pg_catalog.count(*)::integer
      FROM public.mission_creneaux mc
      WHERE mc.mission_id = p_mission_id
        AND mc.type_creneau = 'PREVISIONNEL'
        AND NOT mc.est_pause
    ) <> v_nb
  INTO v_planning_modifie;

  IF v_planning_modifie AND EXISTS (
    SELECT 1
    FROM public.candidatures c
    WHERE c.mission_id = p_mission_id
      AND c.statut::text IN (
        'EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE'
      )
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Le planning ne peut pas être modifié pendant que des candidatures sont en attente. Refusez-les ou publiez une nouvelle mission.'
    );
  END IF;

  IF v_planning_modifie THEN
    PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'true', true);
    DELETE FROM public.mission_creneaux
    WHERE mission_id = p_mission_id
      AND type_creneau = 'PREVISIONNEL';

    INSERT INTO public.mission_creneaux (
      mission_id, debut, fin, est_pause, ordre, type_creneau
    )
    SELECT
      p_mission_id,
      (element->>'debut')::timestamptz,
      (element->>'fin')::timestamptz,
      false,
      pg_catalog.row_number() OVER (
        ORDER BY (element->>'debut')::timestamptz,
                 (element->>'fin')::timestamptz,
                 ordinality
      )::integer,
      'PREVISIONNEL'
    FROM pg_catalog.jsonb_array_elements(p_creneaux)
      WITH ORDINALITY AS source(element, ordinality)
    ORDER BY (element->>'debut')::timestamptz,
             (element->>'fin')::timestamptz,
             ordinality;
    PERFORM pg_catalog.set_config('jolene.sync_in_progress', 'false', true);
  END IF;

  UPDATE public.missions
  SET intitule = pg_catalog.btrim(p_intitule),
      description = p_description,
      service = NULLIF(pg_catalog.btrim(p_service), ''),
      profession_requise = p_profession_requise,
      debut_le = v_debut,
      fin_le = v_fin,
      duree_heures = v_total,
      nb_creneaux = v_nb,
      taux_horaire_base = p_taux_horaire_base,
      est_urgente = COALESCE(p_est_urgente, false),
      niveau_urgence = CASE WHEN COALESCE(p_est_urgente, false)
        THEN GREATEST(1, LEAST(COALESCE(p_niveau_urgence, 1), 3))
        ELSE 0
      END,
      mode_attribution = p_mode_attribution,
      type_contrat_recherche = p_type_contrat_recherche,
      specialite_medicale_requise = CASE WHEN p_profession_requise = 'MEDECIN'
        THEN NULLIF(pg_catalog.btrim(p_specialite_medicale_requise), '')
        ELSE NULL
      END,
      accepte_non_specialises = CASE WHEN p_profession_requise IN ('IBODE', 'IADE')
        THEN COALESCE(p_accepte_non_specialises, true)
        ELSE true
      END,
      modifie_le = pg_catalog.now()
  WHERE id = p_mission_id;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    (SELECT auth.uid()),
    CASE WHEN public.est_admin() THEN 'ADMIN' ELSE 'ADMIN_ETABLISSEMENT' END,
    'MISSION_MODIFICATION',
    'mission',
    p_mission_id,
    NULL,
    pg_catalog.jsonb_build_object(
      'planning_modifie', v_planning_modifie,
      'nb_creneaux', v_nb,
      'debut_le', v_debut,
      'fin_le', v_fin,
      'total_heures', v_total,
      'profession_requise', v_mission.profession_requise,
      'type_contrat_recherche', v_mission.type_contrat_recherche
    ),
    NULL,
    NULL
  );

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'mission_id', p_mission_id,
    'nb_creneaux', v_nb,
    'total_heures', v_total,
    'planning_modifie', v_planning_modifie
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[fn_modifier_mission_etablissement_v3] SQLSTATE=% SQLERRM=%',
      SQLSTATE, SQLERRM;
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La modification de la mission est temporairement indisponible.',
      'code', 'MODIFICATION_MISSION_INDISPONIBLE'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_modifier_mission_etablissement_v3(
  uuid, text, text, text, public.type_profession, numeric, boolean, integer,
  text, text, text, boolean, jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_modifier_mission_etablissement_v3(
  uuid, text, text, text, public.type_profession, numeric, boolean, integer,
  text, text, text, boolean, jsonb
) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_modifier_mission_etablissement_v3(
  uuid, text, text, text, public.type_profession, numeric, boolean, integer,
  text, text, text, boolean, jsonb
) IS 'Édition atomique d''une mission ouverte et de tous ses créneaux PREVISIONNEL datés.';

-- Adaptateur de compatibilité pendant la phase d'expansion. Un ancien client
-- peut encore modifier un créneau unique ; pour une mission multi-créneaux,
-- les dates d'enveloppe doivent rester inchangées et le planning exact vivant
-- est transmis à v3 sans suppression/réinsertion inutile.
CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement_v2(
  p_mission_id uuid,
  p_intitule text,
  p_description text DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_profession_requise public.type_profession DEFAULT NULL,
  p_debut_le timestamptz DEFAULT NULL,
  p_fin_le timestamptz DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE',
  p_type_contrat_recherche text DEFAULT 'SALARIE',
  p_specialite_medicale_requise text DEFAULT NULL,
  p_accepte_non_specialises boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_creneaux jsonb;
  v_nb integer;
BEGIN
  SELECT m.*
  INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Mission introuvable ou accès refusé.'
    );
  END IF;

  SELECT
    pg_catalog.count(*)::integer,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object('debut', mc.debut, 'fin', mc.fin)
      ORDER BY mc.debut, mc.fin, mc.ordre, mc.id
    )
  INTO v_nb, v_creneaux
  FROM public.mission_creneaux mc
  WHERE mc.mission_id = p_mission_id
    AND mc.type_creneau = 'PREVISIONNEL'
    AND NOT mc.est_pause;

  IF v_nb > 1 THEN
    IF p_debut_le IS DISTINCT FROM v_mission.debut_le
       OR p_fin_le IS DISTINCT FROM v_mission.fin_le THEN
      RETURN pg_catalog.jsonb_build_object(
        'success', false,
        'error', 'Les dates d''une mission multi-créneaux se modifient depuis son planning détaillé.'
      );
    END IF;
  ELSE
    v_creneaux := pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('debut', p_debut_le, 'fin', p_fin_le)
    );
  END IF;

  RETURN public.fn_modifier_mission_etablissement_v3(
    p_mission_id,
    p_intitule,
    p_description,
    p_service,
    p_profession_requise,
    p_taux_horaire_base,
    p_est_urgente,
    p_niveau_urgence,
    p_mode_attribution,
    p_type_contrat_recherche,
    p_specialite_medicale_requise,
    p_accepte_non_specialises,
    COALESCE(v_creneaux, '[]'::jsonb)
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[fn_modifier_mission_etablissement_v2] SQLSTATE=% SQLERRM=%',
      SQLSTATE, SQLERRM;
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La modification de la mission est temporairement indisponible.',
      'code', 'MODIFICATION_MISSION_INDISPONIBLE'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_modifier_mission_etablissement_v2(
  uuid, text, text, text, public.type_profession, timestamptz, timestamptz,
  numeric, boolean, integer, text, text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_modifier_mission_etablissement_v2(
  uuid, text, text, text, public.type_profession, timestamptz, timestamptz,
  numeric, boolean, integer, text, text, text, boolean
) TO authenticated, service_role;

-- Une session applicative ne doit jamais pouvoir contourner les validateurs
-- atomiques en écrivant directement les créneaux. Les anciens RPC restent
-- temporairement exécutables : le trigger legacy et l'adaptateur v2 les
-- convertissent vers le modèle exact pendant la phase d'expansion.
REVOKE INSERT, UPDATE, DELETE ON TABLE public.mission_creneaux
  FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.fn_creer_mission(
  text, text, public.type_profession, text, timestamptz, timestamptz,
  numeric, boolean, integer, text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission(
  text, text, public.type_profession, text, timestamptz, timestamptz,
  numeric, boolean, integer, text, text, boolean
) TO authenticated, service_role;

-- Sérialise toute modification directe d'un PREVISIONNEL avec les actions de
-- candidature. Ainsi, un établissement ne peut jamais changer le planning
-- entre le récapitulatif confirmé par le soignant et l'enregistrement métier.
CREATE OR REPLACE FUNCTION public.dec_verrouiller_planning_candidatures()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ids uuid[];
  v_mission_id uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.type_creneau <> 'PREVISIONNEL' THEN RETURN NEW; END IF;
    v_ids := ARRAY[NEW.mission_id];
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.type_creneau <> 'PREVISIONNEL' THEN RETURN OLD; END IF;
    v_ids := ARRAY[OLD.mission_id];
  ELSE
    IF OLD.type_creneau <> 'PREVISIONNEL'
       AND NEW.type_creneau <> 'PREVISIONNEL' THEN
      RETURN NEW;
    END IF;
    v_ids := ARRAY[NEW.mission_id, OLD.mission_id];
  END IF;

  FOREACH v_mission_id IN ARRAY v_ids
  LOOP
    CONTINUE WHEN v_mission_id IS NULL;
    PERFORM 1
    FROM public.missions m
    WHERE m.id = v_mission_id
    FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM public.candidatures c
      WHERE c.mission_id = v_mission_id
        AND c.statut IN (
          'EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE'
        )
    ) THEN
      RAISE EXCEPTION
        'Le planning ne peut pas être modifié pendant qu''une candidature est en attente.'
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_verrouiller_planning_candidatures()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verrouiller_planning_candidatures()
  TO service_role;

DROP TRIGGER IF EXISTS trg_dec_verrouiller_planning_candidatures
  ON public.mission_creneaux;
CREATE TRIGGER trg_dec_verrouiller_planning_candidatures
BEFORE INSERT OR UPDATE OR DELETE ON public.mission_creneaux
FOR EACH ROW
EXECUTE FUNCTION public.dec_verrouiller_planning_candidatures();

-- Pendant la phase d'expansion, les nouveaux clients fournissent une preuve de
-- confirmation via GUC tandis que les clients déjà ouverts utilisent encore
-- les anciens RPC. Dans les deux cas, aucune candidature n'est acceptée si le
-- planning exact est absent ou incohérent avec nb_creneaux.
CREATE OR REPLACE FUNCTION public.dec_exiger_planning_confirme_candidature()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_nb integer;
  v_nb_declares integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL
     OR public.est_admin() IS TRUE
     OR NEW.soignant_id IS DISTINCT FROM (SELECT auth.uid())
     OR NEW.statut::text NOT IN (
       'EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB'
     ) THEN
    RETURN NEW;
  END IF;

  SELECT
    pg_catalog.count(*) FILTER (
      WHERE mc.type_creneau = 'PREVISIONNEL'
        AND NOT mc.est_pause
        AND mc.fin IS NOT NULL
    )::integer,
    pg_catalog.max(m.nb_creneaux)::integer
  INTO v_nb, v_nb_declares
  FROM public.missions m
  LEFT JOIN public.mission_creneaux mc ON mc.mission_id = m.id
  WHERE m.id = NEW.mission_id;

  IF COALESCE(v_nb, 0) = 0
     OR COALESCE(v_nb_declares, 0) <> v_nb THEN
    RAISE EXCEPTION
      '[PLANNING_DETAILLE_INDISPONIBLE] Le planning daté doit être complet avant toute candidature.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_exiger_planning_confirme_candidature()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_exiger_planning_confirme_candidature()
  TO service_role;

DROP TRIGGER IF EXISTS trg_dec_exiger_planning_confirme_candidature
  ON public.candidatures;
CREATE TRIGGER trg_dec_exiger_planning_confirme_candidature
BEFORE INSERT ON public.candidatures
FOR EACH ROW
EXECUTE FUNCTION public.dec_exiger_planning_confirme_candidature();

CREATE OR REPLACE FUNCTION public.fn_confirmer_action_planning_v1(
  p_mission_id uuid,
  p_action text,
  p_creneaux_confirmes jsonb,
  p_message text DEFAULT NULL,
  p_choix_contrat text DEFAULT NULL,
  p_candidature_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_action text;
  v_validation jsonb;
  v_conflit jsonb;
  v_nb_live integer;
  v_planning_differe boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR public.est_soignant() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'ok', false,
      'error', 'Accès réservé aux soignants authentifiés.'
    );
  END IF;

  v_action := pg_catalog.upper(pg_catalog.btrim(COALESCE(p_action, '')));
  IF v_action NOT IN (
    'POSTULER', 'ACCEPTER', 'SWIPE_LIKE', 'URGENCE', 'PROPOSITION'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'ok', false,
      'error', 'Action de candidature invalide.'
    );
  END IF;

  SELECT m.*
  INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND OR v_mission.statut <> 'OUVERTE' THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'ok', false,
      'error', 'Cette mission n''est plus disponible.'
    );
  END IF;

  v_validation := public.fn_valider_creneaux_mission_json(
    p_creneaux_confirmes,
    NOT (
      v_mission.type_contrat_recherche = 'LIBERAL'
      OR (
        v_mission.type_contrat_recherche = 'TOUS'
        AND pg_catalog.upper(pg_catalog.btrim(COALESCE(p_choix_contrat, ''))) = 'LIBERAL'
      )
    )
  );
  IF COALESCE((v_validation->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'ok', false,
      'code', 'PLANNING_A_RECONFIRMER',
      'error', 'Le planning confirmé n''est pas exploitable. Rechargez la mission avant de continuer.'
    );
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO v_nb_live
  FROM public.mission_creneaux mc
  WHERE mc.mission_id = p_mission_id
    AND mc.type_creneau = 'PREVISIONNEL'
    AND NOT mc.est_pause
    AND mc.fin IS NOT NULL;

  WITH confirmes AS (
    SELECT
      (source.element->>'debut')::timestamptz AS debut,
      (source.element->>'fin')::timestamptz AS fin
    FROM pg_catalog.jsonb_array_elements(p_creneaux_confirmes)
      AS source(element)
  ), live AS (
    SELECT mc.debut, mc.fin
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = p_mission_id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
  )
  SELECT EXISTS (
    (SELECT l.debut, l.fin FROM live l
     EXCEPT
     SELECT c.debut, c.fin FROM confirmes c)
    UNION ALL
    (SELECT c.debut, c.fin FROM confirmes c
     EXCEPT
     SELECT l.debut, l.fin FROM live l)
  )
  INTO v_planning_differe;

  IF v_nb_live = 0
     OR v_nb_live <> pg_catalog.jsonb_array_length(p_creneaux_confirmes)
     OR (
       COALESCE(v_mission.nb_creneaux, 0) > 0
       AND v_mission.nb_creneaux <> v_nb_live
     )
     OR v_planning_differe THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'ok', false,
      'code', 'PLANNING_MODIFIE_RECONFIRMER',
      'error', 'Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires.'
    );
  END IF;

  v_conflit := public.fn_conflit_planning_soignant(
    (SELECT auth.uid()),
    p_mission_id
  );
  IF COALESCE((v_conflit->>'conflit')::boolean, false) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'ok', false,
      'code', COALESCE(v_conflit->>'code', 'CONFLIT_PLANNING'),
      'error', COALESCE(
        v_conflit->>'message',
        'Ce planning entre en conflit avec une mission déjà confirmée.'
      )
    );
  END IF;

  PERFORM pg_catalog.set_config(
    'jolene.planning_confirme_mission_id',
    p_mission_id::text,
    true
  );

  CASE v_action
    WHEN 'POSTULER' THEN
      RETURN public.fn_postuler_mission_rate_limited(
        p_mission_id,
        p_message,
        p_choix_contrat
      );
    WHEN 'ACCEPTER' THEN
      RETURN public.fn_accepter_mission(
        p_mission_id,
        p_choix_contrat
      );
    WHEN 'SWIPE_LIKE' THEN
      RETURN public.fn_enregistrer_swipe(
        p_mission_id,
        'LIKE',
        p_choix_contrat
      );
    WHEN 'URGENCE' THEN
      RETURN public.fn_accepter_mission_urgence(p_mission_id);
    WHEN 'PROPOSITION' THEN
      IF p_candidature_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.candidatures c
        WHERE c.id = p_candidature_id
          AND c.mission_id = p_mission_id
          AND c.soignant_id = (SELECT auth.uid())
          AND c.statut::text = 'PROPOSEE'
      ) THEN
        RETURN pg_catalog.jsonb_build_object(
          'success', false,
          'ok', false,
          'error', 'Proposition introuvable.'
        );
      END IF;
      RETURN public.fn_repondre_proposition(p_candidature_id, true);
    ELSE
      RAISE EXCEPTION 'Action planning non traitée';
  END CASE;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_confirmer_action_planning_v1(
  uuid, text, jsonb, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_confirmer_action_planning_v1(
  uuid, text, jsonb, text, text, uuid
) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_confirmer_action_planning_v1(
  uuid, text, jsonb, text, text, uuid
) IS 'Compare sous verrou les créneaux confirmés avec le planning live avant toute candidature ou acceptation.';

-- Même garantie du côté établissement : l'acceptation d'une candidature ne
-- peut pas utiliser un planning devenu différent entre l'affichage et le clic.
CREATE OR REPLACE FUNCTION public.fn_traiter_candidature_planning_v1(
  p_candidature_id uuid,
  p_decision text,
  p_creneaux_confirmes jsonb DEFAULT NULL,
  p_motif text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_mission_id uuid;
  v_decision text;
  v_choix_contrat text;
  v_validation jsonb;
  v_nb_live integer;
  v_planning_differe boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Non authentifié.'
    );
  END IF;

  v_decision := pg_catalog.upper(pg_catalog.btrim(COALESCE(p_decision, '')));
  IF v_decision NOT IN ('ACCEPTEE', 'REFUSEE') THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Décision invalide.'
    );
  END IF;

  SELECT c.mission_id, c.type_contrat_choisi::text
  INTO v_mission_id, v_choix_contrat
  FROM public.candidatures c
  WHERE c.id = p_candidature_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Candidature introuvable.'
    );
  END IF;

  SELECT m.*
  INTO v_mission
  FROM public.missions m
  WHERE m.id = v_mission_id
  FOR UPDATE;
  IF NOT FOUND OR public.fn_a_permission_etablissement(
    'candidatures', v_mission.etablissement_id
  ) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Mission introuvable ou accès refusé.'
    );
  END IF;

  IF v_decision = 'REFUSEE' THEN
    RETURN public.fn_traiter_candidature(
      p_candidature_id,
      v_decision,
      p_motif
    );
  END IF;

  v_validation := public.fn_valider_creneaux_mission_json(
    p_creneaux_confirmes,
    NOT (
      v_mission.type_contrat_recherche = 'LIBERAL'
      OR (
        v_mission.type_contrat_recherche = 'TOUS'
        AND pg_catalog.upper(pg_catalog.btrim(COALESCE(v_choix_contrat, ''))) = 'LIBERAL'
      )
    )
  );
  IF COALESCE((v_validation->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'code', 'PLANNING_A_RECONFIRMER',
      'error', 'Le planning confirmé n''est pas exploitable. Rechargez la mission avant de continuer.'
    );
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO v_nb_live
  FROM public.mission_creneaux mc
  WHERE mc.mission_id = v_mission_id
    AND mc.type_creneau = 'PREVISIONNEL'
    AND NOT mc.est_pause
    AND mc.fin IS NOT NULL;

  WITH confirmes AS (
    SELECT
      (source.element->>'debut')::timestamptz AS debut,
      (source.element->>'fin')::timestamptz AS fin
    FROM pg_catalog.jsonb_array_elements(p_creneaux_confirmes)
      AS source(element)
  ), live AS (
    SELECT mc.debut, mc.fin
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = v_mission_id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
  )
  SELECT EXISTS (
    (SELECT l.debut, l.fin FROM live l
     EXCEPT
     SELECT c.debut, c.fin FROM confirmes c)
    UNION ALL
    (SELECT c.debut, c.fin FROM confirmes c
     EXCEPT
     SELECT l.debut, l.fin FROM live l)
  )
  INTO v_planning_differe;

  IF v_nb_live = 0
     OR v_nb_live <> pg_catalog.jsonb_array_length(p_creneaux_confirmes)
     OR (
       COALESCE(v_mission.nb_creneaux, 0) > 0
       AND v_mission.nb_creneaux <> v_nb_live
     )
     OR v_planning_differe THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'code', 'PLANNING_MODIFIE_RECONFIRMER',
      'error', 'Le planning a changé depuis son affichage. Vérifiez à nouveau toutes les dates et tous les horaires.'
    );
  END IF;

  PERFORM pg_catalog.set_config(
    'jolene.planning_confirme_mission_id',
    v_mission_id::text,
    true
  );
  RETURN public.fn_traiter_candidature(
    p_candidature_id,
    v_decision,
    p_motif
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_traiter_candidature_planning_v1(
  uuid, text, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_traiter_candidature_planning_v1(
  uuid, text, jsonb, text
) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_traiter_candidature_planning_v1(
  uuid, text, jsonb, text
) IS 'Traite une candidature établissement sous verrou et exige la confirmation du planning exact avant acceptation.';

CREATE OR REPLACE FUNCTION public.fn_conflit_planning_soignant(
  p_soignant_id uuid,
  p_mission_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_nb integer;
  v_nb_complets integer;
  v_nb_attendus integer;
  v_conflit record;
  v_repos record;
BEGIN
  SELECT
    pg_catalog.count(mc.mission_id)::integer,
    pg_catalog.count(mc.mission_id) FILTER (WHERE mc.fin IS NOT NULL)::integer,
    pg_catalog.max(COALESCE(m.nb_creneaux, 0))::integer
  INTO v_nb, v_nb_complets, v_nb_attendus
  FROM public.missions m
  LEFT JOIN public.mission_creneaux mc
    ON mc.mission_id = m.id
    AND mc.type_creneau = 'PREVISIONNEL'
    AND NOT mc.est_pause
  WHERE m.id = p_mission_id;

  IF v_nb = 0
     OR v_nb_complets <> v_nb
     OR (COALESCE(v_nb_attendus, 0) > 0 AND v_nb_attendus <> v_nb) THEN
    RETURN pg_catalog.jsonb_build_object(
      'conflit', true,
      'code', 'PLANNING_DETAILLE_INDISPONIBLE',
      'message', 'Le planning détaillé de cette mission doit être confirmé avant toute candidature.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.missions m
    WHERE m.soignant_assigne_id = p_soignant_id
      AND m.id <> p_mission_id
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.mission_creneaux mc
          WHERE mc.mission_id = m.id
            AND mc.type_creneau = 'PREVISIONNEL'
            AND NOT mc.est_pause
        )
        OR EXISTS (
          SELECT 1
          FROM public.mission_creneaux mc
          WHERE mc.mission_id = m.id
            AND mc.type_creneau = 'PREVISIONNEL'
            AND NOT mc.est_pause
            AND mc.fin IS NULL
        )
        OR (
          COALESCE(m.nb_creneaux, 0) > 0
          AND m.nb_creneaux <> (
            SELECT pg_catalog.count(*)::integer
            FROM public.mission_creneaux mc
            WHERE mc.mission_id = m.id
              AND mc.type_creneau = 'PREVISIONNEL'
              AND NOT mc.est_pause
          )
        )
      )
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'conflit', true,
      'code', 'PLANNING_EXISTANT_INDISPONIBLE',
      'message', 'Le planning détaillé d''une mission déjà confirmée doit être vérifié avant cette candidature.'
    );
  END IF;

  SELECT
    m.id AS mission_id,
    m.intitule,
    existant.debut,
    existant.fin
  INTO v_conflit
  FROM public.mission_creneaux cible
  JOIN public.missions m
    ON m.soignant_assigne_id = p_soignant_id
   AND m.id <> p_mission_id
   AND m.statut IN ('ASSIGNEE', 'EN_COURS')
  JOIN public.mission_creneaux existant
    ON existant.mission_id = m.id
   AND existant.type_creneau = 'PREVISIONNEL'
   AND NOT existant.est_pause
   AND existant.fin IS NOT NULL
  WHERE cible.mission_id = p_mission_id
    AND cible.type_creneau = 'PREVISIONNEL'
    AND NOT cible.est_pause
    AND cible.fin IS NOT NULL
    AND cible.debut < existant.fin
    AND cible.fin > existant.debut
  ORDER BY existant.debut
  LIMIT 1;

  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'conflit', true,
      'mission_conflit_id', v_conflit.mission_id,
      'mission_conflit', v_conflit.intitule,
      'message', 'Tu es déjà confirmé(e) sur « ' || v_conflit.intitule ||
        ' » le ' ||
        pg_catalog.to_char(v_conflit.debut AT TIME ZONE 'Europe/Paris', 'DD/MM HH24hMI') ||
        '–' ||
        pg_catalog.to_char(v_conflit.fin AT TIME ZONE 'Europe/Paris', 'DD/MM HH24hMI') ||
        '. Ce créneau chevauche la mission.'
    );
  END IF;

  WITH cible AS (
    SELECT mc.debut, mc.fin
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = p_mission_id
      AND mc.type_creneau = 'PREVISIONNEL'
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
  ), existants AS (
    SELECT m.id AS mission_id, m.intitule, mc.debut, mc.fin
    FROM public.missions m
    JOIN public.mission_creneaux mc ON mc.mission_id = m.id
    WHERE m.soignant_assigne_id = p_soignant_id
      AND m.id <> p_mission_id
      AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
      AND mc.type_creneau = CASE
        WHEN m.statut = 'TERMINEE' AND EXISTS (
          SELECT 1
          FROM public.mission_creneaux effectif
          WHERE effectif.mission_id = m.id
            AND effectif.type_creneau = 'EFFECTIF'
            AND NOT effectif.est_pause
            AND effectif.fin IS NOT NULL
        ) THEN 'EFFECTIF'
        ELSE 'PREVISIONNEL'
      END
      AND NOT mc.est_pause
      AND mc.fin IS NOT NULL
  ), ecarts AS (
    SELECT
      e.mission_id,
      e.intitule,
      CASE
        WHEN e.fin <= c.debut THEN
          EXTRACT(epoch FROM (c.debut - e.fin)) / 3600.0
        WHEN c.fin <= e.debut THEN
          EXTRACT(epoch FROM (e.debut - c.fin)) / 3600.0
        ELSE NULL
      END AS heures
    FROM cible c
    CROSS JOIN existants e
  )
  SELECT mission_id, intitule, heures
  INTO v_repos
  FROM ecarts
  WHERE heures >= 0 AND heures < 11
  ORDER BY heures
  LIMIT 1;

  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'conflit', true,
      'code', 'REPOS_11H',
      'mission_conflit_id', v_repos.mission_id,
      'mission_conflit', v_repos.intitule,
      'heures_repos', pg_catalog.round(v_repos.heures::numeric, 1),
      'message', 'Repos insuffisant avec « ' || v_repos.intitule ||
        ' » : ' || pg_catalog.round(v_repos.heures::numeric, 1) ||
        ' h au lieu de 11 h minimum.'
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object('conflit', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_conflit_planning_soignant(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conflit_planning_soignant(uuid, uuid)
  TO service_role;

-- Toute fonction SECURITY DEFINER exposée est recapturée explicitement :
-- signature, catégorie, empreinte exacte de pg_proc.prosrc et justification.
-- Les empreintes ci-dessous sont calculées sur les corps dollar-quotés, comme
-- dans la migration d'inventaire initiale.
INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
) VALUES
  (
    'fn_confirmer_action_planning_v1(uuid,text,jsonb,text,text,uuid)',
    'RPC_UTILISATEUR_AUTH_INTERNE',
    '3b9e69d418bb2b049ef8ccb9f074d985',
    'RPC soignant authentifié: compare sous verrou le planning affiché au planning live avant de déléguer l''action métier.',
    pg_catalog.now()
  ),
  (
    'fn_traiter_candidature_planning_v1(uuid,text,jsonb,text)',
    'RPC_UTILISATEUR_AUTH_INTERNE',
    '85dbc3790abbf325f9e27aa4b967715a',
    'RPC établissement authentifié: contrôle la permission et compare sous verrou le planning confirmé avant acceptation.',
    pg_catalog.now()
  ),
  (
    'fn_conflit_planning_soignant(uuid,uuid)',
    'SERVICE_ONLY_REVOQUE',
    'b79e76aa8556ab96b4ae00c0b00effe5',
    'Primitive interne fail-closed sur les créneaux exacts; EXECUTE maintenu uniquement pour service_role.',
    pg_catalog.now()
  ),
  (
    'fn_creer_mission_multi_jours(text,text,type_profession,text,numeric,boolean,integer,text,text,boolean,jsonb)',
    'MIXTE_TENANT_ADMIN',
    '47f929c790a6f5961c28370c5eca2692',
    'RPC mixte: établissement courant obligatoire, contrôles administrateur explicites, puis création atomique des créneaux datés.',
    pg_catalog.now()
  ),
  (
    'fn_modifier_mission_etablissement_v3(uuid,text,text,text,type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb)',
    'MIXTE_TENANT_ADMIN',
    '2e7ff2c2da884b2066a8ae3ec605dce2',
    'RPC mixte: permission mission explicite, statut ouvert et remplacement atomique du planning exact avec audit.',
    pg_catalog.now()
  ),
  (
    'fn_modifier_mission_etablissement_v2(uuid,text,text,text,type_profession,timestamp with time zone,timestamp with time zone,numeric,boolean,integer,text,text,text,boolean)',
    'MIXTE_TENANT_ADMIN',
    'be927a11a95a1f2174d4cf0afa112444',
    'Adaptateur temporaire expand/contract: conserve le tenant et délègue à v3 en préservant le planning exact.',
    pg_catalog.now()
  ),
  (
    'dec_initialiser_planning_exact_legacy()',
    'SERVICE_ONLY_REVOQUE',
    '6c685f6468183bd986b135bf01003e7c',
    'Trigger interne de transition: initialise un créneau legacy ou recopie le planning exact d''une mission remplacée.',
    pg_catalog.now()
  )
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_planning_security_definer_manifest$
DECLARE
  v_missing text;
  v_orphan text;
  v_hash_mismatch text;
  v_total integer;
BEGIN
  WITH current_exposed AS (
    SELECT p.oid::regprocedure::text AS signature,
           pg_catalog.md5(p.prosrc) AS body_md5
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef IS TRUE
      AND p.prokind = 'f'
      AND (
        pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
        OR pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
        OR p.oid::regprocedure::text IN (
          'fn_doit_notifier(uuid,type_evenement_notification,canal_notification)',
          'fn_sms_doit_envoyer(uuid,text,integer)',
          'fn_generer_numero_contrat_safe(text)',
          'fn_conflit_planning_soignant(uuid,uuid)',
          'fn_calculer_score_matching(uuid,uuid)'
        )
      )
  )
  SELECT pg_catalog.string_agg(c.signature, ', ' ORDER BY c.signature)
  INTO v_missing
  FROM current_exposed c
  LEFT JOIN private.security_definer_inventory i USING (signature)
  WHERE i.signature IS NULL;

  SELECT pg_catalog.string_agg(i.signature, ', ' ORDER BY i.signature)
  INTO v_orphan
  FROM private.security_definer_inventory i
  LEFT JOIN (
    SELECT p.oid::regprocedure::text AS signature
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef IS TRUE
      AND p.prokind = 'f'
  ) c USING (signature)
  WHERE c.signature IS NULL;

  SELECT pg_catalog.string_agg(i.signature, ', ' ORDER BY i.signature)
  INTO v_hash_mismatch
  FROM private.security_definer_inventory i
  JOIN pg_catalog.pg_proc p ON p.oid::regprocedure::text = i.signature
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND pg_catalog.md5(p.prosrc) <> i.definition_md5;

  SELECT pg_catalog.count(*)::integer
  INTO v_total
  FROM private.security_definer_inventory;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY DEFINER non classées après correction planning : %', v_missing;
  END IF;
  IF v_orphan IS NOT NULL THEN
    RAISE EXCEPTION 'Signatures SECURITY DEFINER obsolètes après correction planning : %', v_orphan;
  END IF;
  IF v_hash_mismatch IS NOT NULL THEN
    RAISE EXCEPTION 'Corps SECURITY DEFINER modifiés sans recapture planning : %', v_hash_mismatch;
  END IF;
  IF v_total <> 426 THEN
    RAISE EXCEPTION 'Manifest SECURITY DEFINER planning incomplet : %/426', v_total;
  END IF;
  IF (
    SELECT pg_catalog.count(*)
    FROM private.security_definer_inventory
    WHERE categorie = 'MIXTE_TENANT_ADMIN'
  ) <> 104 THEN
    RAISE EXCEPTION 'Compte MIXTE_TENANT_ADMIN inattendu après correction planning';
  END IF;
  IF (
    SELECT pg_catalog.count(*)
    FROM private.security_definer_inventory
    WHERE categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
  ) <> 192 THEN
    RAISE EXCEPTION 'Compte RPC_UTILISATEUR_AUTH_INTERNE inattendu après correction planning';
  END IF;
END
$assert_planning_security_definer_manifest$;

COMMIT;
