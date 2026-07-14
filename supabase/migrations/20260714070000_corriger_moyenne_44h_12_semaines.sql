-- Art. L3121-22 : la moyenne de 44 h s'apprécie sur toute période de
-- 12 semaines consécutives. Le contrôle historique imputait toute mission à
-- sa semaine de début, comptait aussi les missions libérales et ne regardait
-- que la fenêtre se terminant au début de la mission.

ALTER TABLE public.attestations_heures_externes
  DROP CONSTRAINT IF EXISTS attestations_heures_externes_heures_salarie_check;
ALTER TABLE public.attestations_heures_externes
  ADD COLUMN IF NOT EXISTS modifie_le timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.attestations_heures_externes
  ADD CONSTRAINT attestations_heures_externes_heures_salarie_check
  CHECK (heures_salarie IS NULL OR heures_salarie BETWEEN 0 AND 168);

ALTER TABLE public.attestations_heures_externes
  DROP CONSTRAINT IF EXISTS attestations_heures_externes_semaine_lundi_check;
ALTER TABLE public.attestations_heures_externes
  ADD CONSTRAINT attestations_heures_externes_semaine_lundi_check
  CHECK (semaine_du = date_trunc('week', semaine_du)::date);
ALTER TABLE public.attestations_heures_externes
  DROP CONSTRAINT IF EXISTS attestations_heures_externes_honneur_check;
ALTER TABLE public.attestations_heures_externes
  ADD CONSTRAINT attestations_heures_externes_honneur_check
  CHECK (COALESCE(heures_salarie, 0) = 0 OR attestation_honneur IS TRUE);
ALTER TABLE public.attestations_heures_externes
  DROP CONSTRAINT IF EXISTS attestations_heures_externes_employeur_check;
ALTER TABLE public.attestations_heures_externes
  ADD CONSTRAINT attestations_heures_externes_employeur_check
  CHECK (
    COALESCE(heures_salarie, 0) = 0
    OR char_length(btrim(COALESCE(employeur_principal, ''))) BETWEEN 2 AND 200
  );

-- Les missions simples historiques n'ont pas toujours de mission_creneaux.
-- Une mission TERMINEE doit alors utiliser ses heures/bornes effectives et
-- les ventiler proportionnellement si elles traversent une semaine civile.
CREATE OR REPLACE FUNCTION public.fn_heures_mission_semaine(
  p_mission_id uuid,
  p_semaine_debut date
) RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $function$
  WITH bornes AS (
    SELECT
      p_semaine_debut::timestamp AT TIME ZONE 'Europe/Paris' AS debut_ts,
      (p_semaine_debut + 7)::timestamp AT TIME ZONE 'Europe/Paris' AS fin_ts
  ), mission AS (
    SELECT m.* FROM public.missions m WHERE m.id = p_mission_id
  ), type_reference AS (
    SELECT CASE
      WHEN m.statut = 'TERMINEE' AND EXISTS (
        SELECT 1 FROM public.mission_creneaux mc
        WHERE mc.mission_id = m.id
          AND mc.type_creneau = 'EFFECTIF'
          AND mc.fin IS NOT NULL
          AND NOT mc.est_pause
      ) THEN 'EFFECTIF'
      WHEN EXISTS (
        SELECT 1 FROM public.mission_creneaux mc
        WHERE mc.mission_id = m.id
          AND mc.type_creneau = 'PREVISIONNEL'
          AND mc.fin IS NOT NULL
          AND NOT mc.est_pause
      ) THEN 'PREVISIONNEL'
      WHEN EXISTS (
        SELECT 1 FROM public.mission_creneaux mc
        WHERE mc.mission_id = m.id
          AND mc.type_creneau = 'EFFECTIF'
          AND mc.fin IS NOT NULL
          AND NOT mc.est_pause
      ) THEN 'EFFECTIF'
      ELSE NULL
    END AS type_creneau
    FROM mission m
  ), heures_creneaux AS (
    SELECT sum(
      extract(epoch FROM (
        least(mc.fin, b.fin_ts) - greatest(mc.debut, b.debut_ts)
      )) / 3600.0
    ) AS heures
    FROM public.mission_creneaux mc
    CROSS JOIN bornes b
    CROSS JOIN type_reference tr
    WHERE tr.type_creneau IS NOT NULL
      AND mc.mission_id = p_mission_id
      AND mc.type_creneau = tr.type_creneau
      AND mc.fin IS NOT NULL
      AND NOT mc.est_pause
      AND mc.debut < b.fin_ts
      AND mc.fin > b.debut_ts
  ), reference_repli AS (
    SELECT
      CASE WHEN m.statut = 'TERMINEE'
        THEN COALESCE(m.debut_effectif, m.debut_le)
        ELSE m.debut_le
      END AS debut_ref,
      CASE WHEN m.statut = 'TERMINEE'
        THEN COALESCE(m.fin_effective, m.fin_le)
        ELSE m.fin_le
      END AS fin_ref,
      CASE WHEN m.statut = 'TERMINEE'
        THEN COALESCE(
          m.duree_heures_effective,
          m.duree_heures,
          extract(epoch FROM (
            COALESCE(m.fin_effective, m.fin_le)
            - COALESCE(m.debut_effectif, m.debut_le)
          )) / 3600.0,
          0
        )
        ELSE COALESCE(
          m.duree_heures,
          extract(epoch FROM (m.fin_le - m.debut_le)) / 3600.0,
          0
        )
      END::numeric AS duree_ref,
      COALESCE(m.nb_creneaux, 0) AS nb_creneaux
    FROM mission m
  ), heures_repli AS (
    SELECT CASE
      WHEN tr.type_creneau IS NULL
       AND rr.nb_creneaux <= 1
       AND rr.debut_ref < b.fin_ts
       AND rr.fin_ref > b.debut_ts
       AND rr.fin_ref > rr.debut_ref
      THEN rr.duree_ref * (
        extract(epoch FROM (
          least(rr.fin_ref, b.fin_ts) - greatest(rr.debut_ref, b.debut_ts)
        )) / NULLIF(extract(epoch FROM (rr.fin_ref - rr.debut_ref)), 0)
      )
      ELSE 0
    END AS heures
    FROM reference_repli rr
    CROSS JOIN bornes b
    CROSS JOIN type_reference tr
  )
  SELECT round(COALESCE(hc.heures, hr.heures, 0)::numeric, 2)
  FROM heures_creneaux hc CROSS JOIN heures_repli hr;
$function$;

CREATE OR REPLACE FUNCTION public.fn_semaines_mission(p_mission_id uuid)
RETURNS TABLE(semaine_debut date, heures numeric)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $function$
  WITH bornes AS (
    SELECT
      date_trunc(
        'week',
        (CASE WHEN m.statut = 'TERMINEE'
          THEN COALESCE(m.debut_effectif, m.debut_le)
          ELSE m.debut_le
        END) AT TIME ZONE 'Europe/Paris'
      )::date AS premiere,
      date_trunc(
        'week',
        ((CASE WHEN m.statut = 'TERMINEE'
          THEN COALESCE(m.fin_effective, m.fin_le)
          ELSE m.fin_le
        END) - interval '1 microsecond') AT TIME ZONE 'Europe/Paris'
      )::date AS derniere
    FROM public.missions m
    WHERE m.id = p_mission_id
  ), semaines AS (
    SELECT (b.premiere + (n * 7))::date AS semaine_debut
    FROM bornes b
    CROSS JOIN LATERAL generate_series(
      0, ((b.derniere - b.premiere) / 7)::integer
    ) AS n
  )
  SELECT s.semaine_debut, h.heures
  FROM semaines s
  CROSS JOIN LATERAL (
    SELECT public.fn_heures_mission_semaine(
      p_mission_id, s.semaine_debut
    ) AS heures
  ) h
  WHERE h.heures > 0
  ORDER BY s.semaine_debut;
$function$;

CREATE OR REPLACE FUNCTION public.fn_heures_soignant_semaine(
  p_soignant_id uuid,
  p_semaine_debut date,
  p_exclure_mission_id uuid DEFAULT NULL
) RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $function$
  SELECT round(COALESCE(sum(
    public.fn_heures_mission_semaine(m.id, p_semaine_debut)
  ), 0)::numeric, 2)
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.id IS DISTINCT FROM p_exclure_mission_id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND (CASE WHEN m.statut = 'TERMINEE'
      THEN COALESCE(m.debut_effectif, m.debut_le)
      ELSE m.debut_le
    END) < ((p_semaine_debut + 7)::timestamp AT TIME ZONE 'Europe/Paris')
    AND (CASE WHEN m.statut = 'TERMINEE'
      THEN COALESCE(m.fin_effective, m.fin_le)
      ELSE m.fin_le
    END) > (p_semaine_debut::timestamp AT TIME ZONE 'Europe/Paris')
    AND COALESCE(
      m.type_contrat_applique::text,
      NULLIF(upper(m.choix_contrat_soignant), ''),
      CASE WHEN m.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
    ) = 'SALARIE';
$function$;

-- Le verrou est pris avant toute mutation pertinente, y compris lors d'une
-- modification de créneaux qui resynchronise ensuite la mission.
CREATE OR REPLACE FUNCTION public.trg_verrouiller_controles_temps_travail()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE') THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('jolene:attribution:' || NEW.soignant_assigne_id::text, 0)
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_00_verrouiller_controles_temps_travail
  ON public.missions;
CREATE TRIGGER trg_00_verrouiller_controles_temps_travail
BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.trg_verrouiller_controles_temps_travail();

-- Une déclaration externe est un fait : elle reste enregistrable même si elle
-- révèle un dépassement. Elle prend toutefois le même verrou que l'attribution
-- et crée une alerte durable si une mission Jolene déjà affectée est concernée.
CREATE OR REPLACE FUNCTION public.trg_verrouiller_attestation_temps_travail()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  -- Une correction administrative de l'attribution doit serialiser les
  -- controles des deux soignants. L'ordre UUID stable evite un interblocage
  -- lorsque deux attestations sont permutees concurremment.
  IF TG_OP = 'UPDATE'
     AND OLD.soignant_id IS DISTINCT FROM NEW.soignant_id THEN
    IF OLD.soignant_id IS NULL THEN
      PERFORM pg_advisory_xact_lock(
        hashtextextended('jolene:attribution:' || NEW.soignant_id::text, 0)
      );
    ELSIF NEW.soignant_id IS NULL THEN
      PERFORM pg_advisory_xact_lock(
        hashtextextended('jolene:attribution:' || OLD.soignant_id::text, 0)
      );
    ELSIF OLD.soignant_id::text < NEW.soignant_id::text THEN
      PERFORM pg_advisory_xact_lock(
        hashtextextended('jolene:attribution:' || OLD.soignant_id::text, 0)
      );
      PERFORM pg_advisory_xact_lock(
        hashtextextended('jolene:attribution:' || NEW.soignant_id::text, 0)
      );
    ELSE
      PERFORM pg_advisory_xact_lock(
        hashtextextended('jolene:attribution:' || NEW.soignant_id::text, 0)
      );
      PERFORM pg_advisory_xact_lock(
        hashtextextended('jolene:attribution:' || OLD.soignant_id::text, 0)
      );
    END IF;
  ELSIF NEW.soignant_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('jolene:attribution:' || NEW.soignant_id::text, 0)
    );
  END IF;
  NEW.modifie_le := clock_timestamp();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_00_verrouiller_attestation_temps_travail
  ON public.attestations_heures_externes;
CREATE TRIGGER trg_00_verrouiller_attestation_temps_travail
BEFORE INSERT OR UPDATE OF soignant_id, semaine_du, heures_salarie,
  employeur_principal, attestation_honneur
ON public.attestations_heures_externes
FOR EACH ROW
EXECUTE FUNCTION public.trg_verrouiller_attestation_temps_travail();

CREATE OR REPLACE FUNCTION public.trg_alerter_attestation_temps_travail()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_heures_jolene numeric;
  v_total_48 numeric;
  v_fin_fenetre date;
  v_debut_fenetre date;
  v_heures_fenetre_jolene numeric;
  v_heures_fenetre_externes numeric;
  v_moyenne numeric;
  v_moyenne_max numeric := 0;
  v_fenetre_max_debut date;
  v_fenetre_max_fin date;
  v_mission_48 uuid;
  v_mission_44 uuid;
  v_alerte boolean := false;
  v_resume text;
BEGIN
  v_heures_jolene := public.fn_heures_soignant_semaine(
    NEW.soignant_id, NEW.semaine_du, NULL
  );
  v_total_48 := v_heures_jolene + COALESCE(NEW.heures_salarie, 0);

  IF v_total_48 > 48 THEN
    SELECT m.id
    INTO v_mission_48
    FROM public.missions m
    WHERE m.soignant_assigne_id = NEW.soignant_id
      AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
      AND COALESCE(
        m.type_contrat_applique::text,
        NULLIF(upper(m.choix_contrat_soignant), ''),
        CASE WHEN m.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
      ) = 'SALARIE'
      AND public.fn_heures_mission_semaine(m.id, NEW.semaine_du) > 0
    ORDER BY m.debut_le
    LIMIT 1;

    IF v_mission_48 IS NOT NULL THEN
      INSERT INTO public.conformite_travail (
        soignant_id, mission_id, type_controle, resultat, details_violation
      ) VALUES (
        NEW.soignant_id, v_mission_48, 'PLAFOND_48H_HEBDO', 'VIOLATION_ALERTEE',
        jsonb_build_object(
          'origine', 'ATTESTATION_HEURES_EXTERNES',
          'attestation_id', NEW.id,
          'attestation_modifiee_le', NEW.modifie_le,
          'semaine_du', NEW.semaine_du,
          'heures_jolene', round(v_heures_jolene, 2),
          'heures_externes', round(COALESCE(NEW.heures_salarie, 0), 2),
          'total', round(v_total_48, 2),
          'plafond', 48,
          'article', 'L3121-20',
          'action', 'REVUE_HUMAINE_MISSION_DEJA_AFFECTEE'
        )
      );
      v_alerte := true;
      v_resume := format(
        '%s h sur la semaine du %s (plafond 48 h)',
        round(v_total_48, 1), to_char(NEW.semaine_du, 'DD/MM/YYYY')
      );
    END IF;
  END IF;

  FOR v_fin_fenetre IN
    SELECT (NEW.semaine_du + (n * 7))::date
    FROM generate_series(0, 11) AS offsets(n)
  LOOP
    v_debut_fenetre := v_fin_fenetre - 77;

    SELECT COALESCE(sum(
      public.fn_heures_soignant_semaine(
        NEW.soignant_id,
        (v_debut_fenetre + (semaines.n * 7))::date,
        NULL
      )
    ), 0)
    INTO v_heures_fenetre_jolene
    FROM generate_series(0, 11) AS semaines(n);

    SELECT COALESCE(sum(COALESCE(a.heures_salarie, 0)), 0)
    INTO v_heures_fenetre_externes
    FROM public.attestations_heures_externes a
    WHERE a.soignant_id = NEW.soignant_id
      AND a.semaine_du BETWEEN v_debut_fenetre AND v_fin_fenetre;

    v_moyenne := (v_heures_fenetre_jolene + v_heures_fenetre_externes) / 12.0;
    IF v_moyenne > v_moyenne_max THEN
      v_moyenne_max := v_moyenne;
      v_fenetre_max_debut := v_debut_fenetre;
      v_fenetre_max_fin := v_fin_fenetre;
    END IF;
  END LOOP;

  IF v_moyenne_max > 44 THEN
    SELECT m.id
    INTO v_mission_44
    FROM public.missions m
    WHERE m.soignant_assigne_id = NEW.soignant_id
      AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
      AND COALESCE(
        m.type_contrat_applique::text,
        NULLIF(upper(m.choix_contrat_soignant), ''),
        CASE WHEN m.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
      ) = 'SALARIE'
      AND (CASE WHEN m.statut = 'TERMINEE'
        THEN COALESCE(m.debut_effectif, m.debut_le)
        ELSE m.debut_le
      END) < ((v_fenetre_max_fin + 7)::timestamp AT TIME ZONE 'Europe/Paris')
      AND (CASE WHEN m.statut = 'TERMINEE'
        THEN COALESCE(m.fin_effective, m.fin_le)
        ELSE m.fin_le
      END) > (v_fenetre_max_debut::timestamp AT TIME ZONE 'Europe/Paris')
    ORDER BY CASE WHEN m.statut = 'TERMINEE'
      THEN COALESCE(m.debut_effectif, m.debut_le)
      ELSE m.debut_le
    END
    LIMIT 1;

    IF v_mission_44 IS NOT NULL THEN
      INSERT INTO public.conformite_travail (
        soignant_id, mission_id, type_controle, resultat, details_violation
      ) VALUES (
        NEW.soignant_id, v_mission_44, 'MOYENNE_44H_12_SEMAINES', 'VIOLATION_ALERTEE',
        jsonb_build_object(
          'origine', 'ATTESTATION_HEURES_EXTERNES',
          'attestation_id', NEW.id,
          'attestation_modifiee_le', NEW.modifie_le,
          'fenetre_debut', v_fenetre_max_debut,
          'fenetre_fin', v_fenetre_max_fin + 6,
          'moyenne_hebdo', round(v_moyenne_max, 2),
          'plafond_moyenne', 44,
          'article', 'L3121-22',
          'action', 'REVUE_HUMAINE_MISSION_DEJA_AFFECTEE'
        )
      );
      v_alerte := true;
      v_resume := concat_ws(
        ' ; ',
        v_resume,
        format(
          '%s h/semaine du %s au %s (moyenne max 44 h)',
          round(v_moyenne_max, 1),
          to_char(v_fenetre_max_debut, 'DD/MM/YYYY'),
          to_char(v_fenetre_max_fin + 6, 'DD/MM/YYYY')
        )
      );
    END IF;
  END IF;

  IF v_alerte THEN
    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      NEW.soignant_id,
      'SOIGNANT',
      'SYSTEM',
      'Temps de travail à vérifier',
      'Ta déclaration a bien été enregistrée. Elle révèle un conflit avec une mission déjà affectée ('
        || v_resume || '). N’accepte aucune nouvelle mission salariée sur cette période ; l’équipe Jolene va vérifier la situation.',
      '/soignant/missions',
      'attestations_heures_externes',
      NEW.id
    );

    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    )
    SELECT
      ea.user_id,
      'ADMIN',
      'SYSTEM',
      'Alerte temps de travail',
      'Une déclaration externe postérieure à une affectation révèle un dépassement : '
        || v_resume || '. Revue humaine requise avant toute action sur la mission.',
      '/admin/conformite',
      'attestations_heures_externes',
      NEW.id
    FROM public.equipe_admin ea
    WHERE ea.actif IS TRUE;
  END IF;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_90_alerter_attestation_temps_travail
  ON public.attestations_heures_externes;
CREATE TRIGGER trg_90_alerter_attestation_temps_travail
AFTER INSERT OR UPDATE OF soignant_id, semaine_du, heures_salarie
ON public.attestations_heures_externes
FOR EACH ROW
EXECUTE FUNCTION public.trg_alerter_attestation_temps_travail();

-- À la terminaison, les heures effectives peuvent dépasser le prévisionnel.
-- On ne peut pas refuser un fait accompli : le snapshot est conservé, signalé
-- au soignant et placé en revue humaine pour les missions concernées.
CREATE OR REPLACE FUNCTION public.trg_alerter_temps_travail_effectif()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_regime text;
  v_semaine record;
  v_heures_existantes numeric;
  v_heures_externes numeric;
  v_total_48 numeric;
  v_fin_fenetre date;
  v_debut_fenetre date;
  v_heures_fenetre_jolene numeric;
  v_heures_fenetre_externes numeric;
  v_heures_fenetre_mission numeric;
  v_moyenne numeric;
  v_moyenne_max numeric := 0;
  v_fenetre_max_debut date;
  v_fenetre_max_fin date;
  v_alertes integer := 0;
BEGIN
  IF NEW.soignant_assigne_id IS NULL OR NEW.statut <> 'TERMINEE' THEN
    RETURN NULL;
  END IF;

  v_regime := COALESCE(
    NEW.type_contrat_applique::text,
    NULLIF(upper(NEW.choix_contrat_soignant), ''),
    CASE WHEN NEW.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  IF v_regime = 'LIBERAL' THEN
    RETURN NULL;
  END IF;

  FOR v_semaine IN
    SELECT * FROM public.fn_semaines_mission(NEW.id)
  LOOP
    v_heures_existantes := public.fn_heures_soignant_semaine(
      NEW.soignant_assigne_id, v_semaine.semaine_debut, NEW.id
    );
    SELECT COALESCE(sum(COALESCE(a.heures_salarie, 0)), 0)
    INTO v_heures_externes
    FROM public.attestations_heures_externes a
    WHERE a.soignant_id = NEW.soignant_assigne_id
      AND a.semaine_du = v_semaine.semaine_debut;

    v_total_48 := v_heures_existantes + v_heures_externes + v_semaine.heures;
    IF v_total_48 > 48
       AND NOT EXISTS (
         SELECT 1 FROM public.conformite_travail ct
         WHERE ct.mission_id = NEW.id
           AND ct.type_controle = 'PLAFOND_48H_HEBDO'
           AND ct.resultat = 'VIOLATION_ALERTEE'
           AND ct.details_violation->>'origine' = 'HEURES_EFFECTIVES_TERMINEES'
           AND ct.details_violation->>'semaine_du' = v_semaine.semaine_debut::text
           AND (ct.details_violation->>'total')::numeric = round(v_total_48, 2)
       ) THEN
      INSERT INTO public.conformite_travail (
        soignant_id, mission_id, type_controle, resultat, details_violation
      ) VALUES (
        NEW.soignant_assigne_id,
        NEW.id,
        'PLAFOND_48H_HEBDO',
        'VIOLATION_ALERTEE',
        jsonb_build_object(
          'origine', 'HEURES_EFFECTIVES_TERMINEES',
          'semaine_du', v_semaine.semaine_debut,
          'heures_jolene_hors_mission', round(v_heures_existantes, 2),
          'heures_mission_effectives', round(v_semaine.heures, 2),
          'heures_externes', round(v_heures_externes, 2),
          'total', round(v_total_48, 2),
          'plafond', 48,
          'article', 'L3121-20',
          'action', 'REVUE_HUMAINE_FAIT_ACCOMPLI'
        )
      );
      v_alertes := v_alertes + 1;
    END IF;
  END LOOP;

  FOR v_fin_fenetre IN
    SELECT DISTINCT (sm.semaine_debut + (offsets.n * 7))::date
    FROM public.fn_semaines_mission(NEW.id) sm
    CROSS JOIN generate_series(0, 11) AS offsets(n)
    ORDER BY 1
  LOOP
    v_debut_fenetre := v_fin_fenetre - 77;
    SELECT COALESCE(sum(
      public.fn_heures_soignant_semaine(
        NEW.soignant_assigne_id,
        (v_debut_fenetre + (semaines.n * 7))::date,
        NEW.id
      )
    ), 0)
    INTO v_heures_fenetre_jolene
    FROM generate_series(0, 11) AS semaines(n);

    SELECT COALESCE(sum(COALESCE(a.heures_salarie, 0)), 0)
    INTO v_heures_fenetre_externes
    FROM public.attestations_heures_externes a
    WHERE a.soignant_id = NEW.soignant_assigne_id
      AND a.semaine_du BETWEEN v_debut_fenetre AND v_fin_fenetre;

    SELECT COALESCE(sum(sm.heures), 0)
    INTO v_heures_fenetre_mission
    FROM public.fn_semaines_mission(NEW.id) sm
    WHERE sm.semaine_debut BETWEEN v_debut_fenetre AND v_fin_fenetre;

    v_moyenne := (
      v_heures_fenetre_jolene
      + v_heures_fenetre_externes
      + v_heures_fenetre_mission
    ) / 12.0;
    IF v_moyenne > v_moyenne_max THEN
      v_moyenne_max := v_moyenne;
      v_fenetre_max_debut := v_debut_fenetre;
      v_fenetre_max_fin := v_fin_fenetre;
    END IF;
  END LOOP;

  IF v_moyenne_max > 44
     AND NOT EXISTS (
       SELECT 1 FROM public.conformite_travail ct
       WHERE ct.mission_id = NEW.id
         AND ct.type_controle = 'MOYENNE_44H_12_SEMAINES'
         AND ct.resultat = 'VIOLATION_ALERTEE'
         AND ct.details_violation->>'origine' = 'HEURES_EFFECTIVES_TERMINEES'
         AND ct.details_violation->>'fenetre_debut' = v_fenetre_max_debut::text
         AND (ct.details_violation->>'moyenne_hebdo')::numeric = round(v_moyenne_max, 2)
     ) THEN
    INSERT INTO public.conformite_travail (
      soignant_id, mission_id, type_controle, resultat, details_violation
    ) VALUES (
      NEW.soignant_assigne_id,
      NEW.id,
      'MOYENNE_44H_12_SEMAINES',
      'VIOLATION_ALERTEE',
      jsonb_build_object(
        'origine', 'HEURES_EFFECTIVES_TERMINEES',
        'fenetre_debut', v_fenetre_max_debut,
        'fenetre_fin', v_fenetre_max_fin + 6,
        'moyenne_hebdo', round(v_moyenne_max, 2),
        'plafond_moyenne', 44,
        'article', 'L3121-22',
        'action', 'REVUE_HUMAINE_FAIT_ACCOMPLI'
      )
    );
    v_alertes := v_alertes + 1;
  END IF;

  IF v_alertes > 0 THEN
    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      NEW.soignant_assigne_id,
      'SOIGNANT',
      'SYSTEM',
      'Heures effectives à vérifier',
      'Les heures effectives de cette mission révèlent un dépassement du temps de travail. Elles sont conservées ; n’accepte aucune nouvelle mission salariée sur la période pendant la revue Jolene.',
      '/soignant/missions/' || NEW.id::text,
      'missions',
      NEW.id
    );

    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    )
    SELECT
      ea.user_id,
      'ADMIN',
      'SYSTEM',
      'Alerte heures effectives',
      'Les heures effectives d’une mission terminée révèlent un dépassement. Revue humaine requise ; les heures ne doivent pas être altérées.',
      '/admin/conformite',
      'missions',
      NEW.id
    FROM public.equipe_admin ea
    WHERE ea.actif IS TRUE;
  END IF;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_95_alerter_temps_travail_effectif
  ON public.missions;
CREATE TRIGGER trg_95_alerter_temps_travail_effectif
AFTER UPDATE OF
  soignant_assigne_id,
  statut,
  debut_le,
  fin_le,
  duree_heures,
  duree_heures_effective,
  debut_effectif,
  fin_effective,
  type_contrat_applique,
  choix_contrat_soignant,
  type_contrat_recherche
ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.trg_alerter_temps_travail_effectif();

CREATE OR REPLACE FUNCTION public.dec_verifier_moyenne_44h_12_semaines()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_regime text;
  v_nb_creneaux_valides integer;
  v_fin_fenetre date;
  v_debut_fenetre date;
  v_heures_jolene numeric;
  v_heures_externes numeric;
  v_heures_mission numeric;
  v_heures_total numeric;
  v_moyenne numeric;
  v_moyenne_max numeric := 0;
  v_fenetre_max_debut date;
  v_fenetre_max_fin date;
BEGIN
  IF NEW.soignant_assigne_id IS NULL
     OR NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN NEW;
  END IF;

  -- Le régime se résout sur la mission, jamais sur les diplômes ou le statut
  -- global du profil. Une IADE sur une mission IDE salariée est donc contrôlée;
  -- une mission effectivement libérale ne l'est pas.
  v_regime := COALESCE(
    NEW.type_contrat_applique::text,
    NULLIF(upper(NEW.choix_contrat_soignant), ''),
    CASE
      WHEN NEW.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL'
      ELSE 'SALARIE'
    END
  );
  IF v_regime = 'LIBERAL' THEN
    RETURN NEW;
  END IF;

  -- Même verrou que l'attribution atomique et le plafond de 48 h : deux
  -- missions ne peuvent pas valider en parallèle le même planning.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('jolene:attribution:' || NEW.soignant_assigne_id::text, 0)
  );

  IF COALESCE(NEW.nb_creneaux, 0) > 1 THEN
    SELECT count(*)::integer
    INTO v_nb_creneaux_valides
    FROM public.mission_creneaux mc
    WHERE mc.mission_id = NEW.id
      AND mc.fin IS NOT NULL
      AND NOT mc.est_pause
      AND mc.type_creneau = CASE
        WHEN EXISTS (
          SELECT 1
          FROM public.mission_creneaux p
          WHERE p.mission_id = NEW.id
            AND p.type_creneau = 'PREVISIONNEL'
            AND p.fin IS NOT NULL
            AND NOT p.est_pause
        ) THEN 'PREVISIONNEL'
        ELSE 'EFFECTIF'
      END;

    IF v_nb_creneaux_valides < NEW.nb_creneaux THEN
      RAISE EXCEPTION
        '[PLANNING_HEBDOMADAIRE_INDISPONIBLE] Mission % : % créneau(x) valide(s) sur % attendu(s)',
        NEW.id, v_nb_creneaux_valides, NEW.nb_creneaux;
    END IF;
  END IF;

  -- Une heure ajoutée en semaine S affecte les douze fenêtres glissantes se
  -- terminant de S à S+11. On vérifie l'union de ces fenêtres pour chacune des
  -- semaines réellement touchées par la mission.
  FOR v_fin_fenetre IN
    SELECT DISTINCT (sm.semaine_debut + (offsets.n * 7))::date
    FROM public.fn_semaines_mission(NEW.id) sm
    CROSS JOIN generate_series(0, 11) AS offsets(n)
    ORDER BY 1
  LOOP
    v_debut_fenetre := v_fin_fenetre - 77;

    SELECT COALESCE(sum(
      public.fn_heures_soignant_semaine(
        NEW.soignant_assigne_id,
        (v_debut_fenetre + (semaines.n * 7))::date,
        NEW.id
      )
    ), 0)
    INTO v_heures_jolene
    FROM generate_series(0, 11) AS semaines(n);

    SELECT COALESCE(sum(COALESCE(a.heures_salarie, 0)), 0)
    INTO v_heures_externes
    FROM public.attestations_heures_externes a
    WHERE a.soignant_id = NEW.soignant_assigne_id
      AND a.semaine_du BETWEEN v_debut_fenetre AND v_fin_fenetre;

    SELECT COALESCE(sum(sm.heures), 0)
    INTO v_heures_mission
    FROM public.fn_semaines_mission(NEW.id) sm
    WHERE sm.semaine_debut BETWEEN v_debut_fenetre AND v_fin_fenetre;

    v_heures_total := v_heures_jolene + v_heures_externes + v_heures_mission;
    v_moyenne := v_heures_total / 12.0;

    IF v_moyenne > v_moyenne_max THEN
      v_moyenne_max := v_moyenne;
      v_fenetre_max_debut := v_debut_fenetre;
      v_fenetre_max_fin := v_fin_fenetre + 6;
    END IF;

    IF v_moyenne > 44.0 THEN
      INSERT INTO public.conformite_travail (
        soignant_id, mission_id, type_controle, resultat, details_violation
      ) VALUES (
        NEW.soignant_assigne_id,
        NEW.id,
        'MOYENNE_44H_12_SEMAINES',
        'VIOLATION_BLOQUEE',
        jsonb_build_object(
          'fenetre_debut', v_debut_fenetre,
          'fenetre_fin', v_fin_fenetre + 6,
          'heures_jolene_existantes', round(v_heures_jolene, 2),
          'heures_mission', round(v_heures_mission, 2),
          'heures_externes', round(v_heures_externes, 2),
          'total_heures', round(v_heures_total, 2),
          'moyenne_hebdo', round(v_moyenne, 2),
          'nb_semaines', 12,
          'plafond_moyenne', 44,
          'article', 'L3121-22'
        )
      );

      RAISE EXCEPTION
        '[CODE DU TRAVAIL] Moyenne dépassée du % au % : %h/semaine sur 12 semaines (max 44h, Art. L3121-22). Assignation bloquée.',
        to_char(v_debut_fenetre, 'DD/MM/YYYY'),
        to_char(v_fin_fenetre + 6, 'DD/MM/YYYY'),
        round(v_moyenne, 1);
    END IF;
  END LOOP;

  IF v_moyenne_max > 40.0 THEN
    INSERT INTO public.conformite_travail (
      soignant_id, mission_id, type_controle, resultat, details_violation
    ) VALUES (
      NEW.soignant_assigne_id,
      NEW.id,
      'MOYENNE_44H_12_SEMAINES',
      'CONFORME',
      jsonb_build_object(
        'moyenne_hebdo_max', round(v_moyenne_max, 2),
        'fenetre_debut', v_fenetre_max_debut,
        'fenetre_fin', v_fenetre_max_fin,
        'nb_semaines', 12,
        'plafond_moyenne', 44,
        'article', 'L3121-22'
      )
    );
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_verifier_moyenne_44h_after_insert
  ON public.missions;
CREATE TRIGGER trg_dec_verifier_moyenne_44h_after_insert
AFTER INSERT ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_verifier_moyenne_44h_12_semaines();

-- AFTER UPDATE garantit que les helpers lisent bien les nouvelles dates et
-- la nouvelle ventilation synchronisée depuis mission_creneaux.
DROP TRIGGER IF EXISTS trg_dec_verifier_moyenne_44h_before_update
  ON public.missions;
DROP TRIGGER IF EXISTS trg_dec_verifier_moyenne_44h_after_update
  ON public.missions;
CREATE TRIGGER trg_dec_verifier_moyenne_44h_after_update
AFTER UPDATE OF
  soignant_assigne_id,
  statut,
  debut_le,
  fin_le,
  duree_heures,
  type_contrat_applique,
  choix_contrat_soignant,
  type_contrat_recherche
ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_verifier_moyenne_44h_12_semaines();

-- Le contrôle 48 h utilisait les mêmes helpers dans un BEFORE UPDATE et
-- relisait donc l'ancien planning. Après mutation, une exception annule tout
-- autant la transaction mais la fonction voit enfin les nouvelles semaines.
DROP TRIGGER IF EXISTS dec_mission_plafond_48h_before_update
  ON public.missions;
DROP TRIGGER IF EXISTS dec_mission_plafond_48h_after_update
  ON public.missions;
CREATE TRIGGER dec_mission_plafond_48h_after_update
AFTER UPDATE OF
  soignant_assigne_id,
  statut,
  debut_le,
  fin_le,
  duree_heures,
  type_contrat_applique,
  choix_contrat_soignant,
  type_contrat_recherche
ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_verifier_plafond_48h();

REVOKE ALL ON FUNCTION public.dec_verifier_moyenne_44h_12_semaines()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_moyenne_44h_12_semaines()
  TO service_role;
REVOKE ALL ON FUNCTION public.fn_heures_mission_semaine(uuid, date)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_semaines_mission(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_heures_soignant_semaine(uuid, date, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_heures_mission_semaine(uuid, date)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_semaines_mission(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_heures_soignant_semaine(uuid, date, uuid)
  TO service_role;
REVOKE ALL ON FUNCTION public.trg_verrouiller_controles_temps_travail()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_verrouiller_controles_temps_travail()
  TO service_role;
REVOKE ALL ON FUNCTION public.trg_verrouiller_attestation_temps_travail()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_alerter_attestation_temps_travail()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_verrouiller_attestation_temps_travail()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_alerter_attestation_temps_travail()
  TO service_role;
REVOKE ALL ON FUNCTION public.trg_alerter_temps_travail_effectif()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_alerter_temps_travail_effectif()
  TO service_role;

COMMENT ON FUNCTION public.dec_verifier_moyenne_44h_12_semaines() IS
  'Contrôle salarié de toute fenêtre glissante de 12 semaines affectée par la mission, ventilée par semaine réelle (Art. L3121-22).';
