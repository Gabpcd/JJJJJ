-- Répare les seules missions de démonstration dont l'affectation a contourné
-- le workflow canonique, puis fait reposer le prévisionnel RH sur les créneaux
-- datés plutôt que sur l'enveloppe debut_le/fin_le de la mission.

BEGIN;

DO $reparer_missions_test$
DECLARE
  v_mission record;
  v_creneaux_supprimes integer;
  v_contrat_cree integer;
  v_type_contrat text;
  v_numero_contrat text;
  v_html text;
  v_previous_test_mode text := COALESCE(
    pg_catalog.current_setting('app.test_mode', true),
    ''
  );
BEGIN
  -- Les triggers de notification savent déjà exclure les comptes test. Ce
  -- verrou transactionnel supplémentaire garantit qu'un rattrapage rejoué ne
  -- déclenche jamais de canal externe.
  PERFORM pg_catalog.set_config('app.test_mode', 'true', true);

  FOR v_mission IN
    SELECT
      m.id,
      m.etablissement_id,
      m.soignant_assigne_id,
      m.statut,
      m.type_contrat_applique,
      m.choix_contrat_soignant,
      m.type_contrat_recherche,
      m.profession_requise,
      m.service,
      m.debut_le,
      m.fin_le,
      m.duree_heures,
      m.taux_horaire_base,
      m.retrocession_pct,
      e.nom AS etablissement_nom,
      e.siret AS etablissement_siret,
      e.finess AS etablissement_finess,
      e.adresse_rue AS etablissement_adresse_rue,
      e.adresse_code_postal AS etablissement_code_postal,
      e.adresse_ville AS etablissement_ville,
      s.prenom AS soignant_prenom,
      s.nom AS soignant_nom,
      s.numero_rpps AS soignant_rpps,
      s.siret_liberal AS soignant_siret
    FROM public.missions m
    JOIN public.etablissements e
      ON e.id = m.etablissement_id
     AND e.est_compte_test IS TRUE
     AND e.supprime_le IS NULL
    JOIN public.soignants s
      ON s.id = m.soignant_assigne_id
     AND s.est_compte_test IS TRUE
     AND s.supprime_le IS NULL
    WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND NOT EXISTS (
        SELECT 1
        FROM public.contrats_mission cm
        WHERE cm.mission_id = m.id
          AND cm.etablissement_id = m.etablissement_id
          AND cm.soignant_id = m.soignant_assigne_id
          AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
      )
      -- Refus fail-closed dès qu'une relation métier pointe vers un compte qui
      -- n'est pas explicitement test. Aucune donnée réelle n'est modifiée.
      AND NOT EXISTS (
        SELECT 1
        FROM public.candidatures c
        LEFT JOIN public.soignants sc ON sc.id = c.soignant_id
        WHERE c.mission_id = m.id
          AND sc.est_compte_test IS DISTINCT FROM TRUE
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.presences p
        LEFT JOIN public.soignants sp ON sp.id = p.soignant_id
        WHERE p.mission_id = m.id
          AND sp.est_compte_test IS DISTINCT FROM TRUE
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.scans_pointage scan
        LEFT JOIN public.soignants ss ON ss.id = scan.soignant_id
        WHERE scan.mission_id = m.id
          AND ss.est_compte_test IS DISTINCT FROM TRUE
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.contrats_mission cm_lie
        LEFT JOIN public.soignants s_lie ON s_lie.id = cm_lie.soignant_id
        WHERE cm_lie.mission_id = m.id
          AND s_lie.est_compte_test IS DISTINCT FROM TRUE
      )
    ORDER BY m.id
    FOR UPDATE OF m
  LOOP
    v_creneaux_supprimes := 0;
    v_contrat_cree := 0;

    -- Un EFFECTIF sans scan ni présence n'est pas un pointage. On ne le
    -- neutralise que dans la cohorte ci-dessus, et jamais si une pièce
    -- financière existe déjà pour la mission.
    DELETE FROM public.mission_creneaux mc
    WHERE mc.mission_id = v_mission.id
      AND mc.type_creneau = 'EFFECTIF'
      AND NOT EXISTS (
        SELECT 1
        FROM public.scans_pointage scan
        WHERE scan.mission_id = v_mission.id
           OR scan.creneau_effectif_id = mc.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.presences p
        WHERE p.mission_id = v_mission.id
          AND (
            p.pointage_arrivee_le IS NOT NULL
            OR p.pointage_depart_le IS NOT NULL
          )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.factures f
        WHERE f.mission_id = v_mission.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.factures_honoraires fh
        WHERE fh.mission_id = v_mission.id
      );
    GET DIAGNOSTICS v_creneaux_supprimes = ROW_COUNT;

    v_type_contrat := CASE
      WHEN COALESCE(v_mission.type_contrat_applique::text, '') = 'LIBERAL'
        OR COALESCE(v_mission.choix_contrat_soignant, '') = 'LIBERAL'
        OR COALESCE(v_mission.type_contrat_recherche, '') = 'LIBERAL'
      THEN 'REMPLACEMENT_LIBERAL'
      ELSE 'CDD'
    END;

    v_numero_contrat := public.fn_generer_numero_contrat_safe(
      v_type_contrat
    );
    IF NULLIF(pg_catalog.btrim(v_numero_contrat), '') IS NULL THEN
      RAISE EXCEPTION
        'Rattrapage test refusé: numéro de contrat canonique vide pour %',
        v_mission.id;
    END IF;

    SELECT tc.contenu_html
    INTO v_html
    FROM public.templates_contrat tc
    WHERE tc.type_contrat = v_type_contrat
      AND tc.est_actif IS TRUE
      AND NULLIF(pg_catalog.btrim(tc.contenu_html), '') IS NOT NULL
    ORDER BY tc.id
    LIMIT 1;

    IF NULLIF(pg_catalog.btrim(v_html), '') IS NULL THEN
      RAISE EXCEPTION
        'Rattrapage test refusé: aucun template actif non vide pour %',
        v_type_contrat;
    END IF;

    -- Même rendu que fn_finaliser_attribution_mission : aucun contrat vide,
    -- aucune donnée injectée sans échappement HTML.
    v_html := pg_catalog.replace(
      v_html,
      '{{etablissement_nom}}',
      public.fn_html_escape(COALESCE(v_mission.etablissement_nom, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{etablissement_siret}}',
      public.fn_html_escape(COALESCE(v_mission.etablissement_siret, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{etablissement_finess}}',
      public.fn_html_escape(COALESCE(v_mission.etablissement_finess, 'N/A'))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{etablissement_adresse}}',
      public.fn_html_escape(COALESCE(
        v_mission.etablissement_adresse_rue || ', '
          || v_mission.etablissement_code_postal || ' '
          || v_mission.etablissement_ville,
        ''
      ))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{soignant_prenom}}',
      public.fn_html_escape(COALESCE(v_mission.soignant_prenom, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{soignant_nom}}',
      public.fn_html_escape(COALESCE(v_mission.soignant_nom, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{soignant_rpps}}',
      public.fn_html_escape(COALESCE(v_mission.soignant_rpps, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{soignant_siret}}',
      public.fn_html_escape(COALESCE(v_mission.soignant_siret, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{profession}}',
      public.fn_html_escape(v_mission.profession_requise::text)
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{service}}',
      public.fn_html_escape(COALESCE(v_mission.service, ''))
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{debut_date}}',
      pg_catalog.to_char(
        v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'
      )
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{debut_heure}}',
      pg_catalog.to_char(
        v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'
      )
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{fin_date}}',
      pg_catalog.to_char(
        v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'
      )
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{fin_heure}}',
      pg_catalog.to_char(
        v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'
      )
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{duree_heures}}',
      COALESCE(v_mission.duree_heures::text, '')
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{taux_horaire}}',
      COALESCE(v_mission.taux_horaire_base::text, '')
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{retrocession_pct}}',
      COALESCE(v_mission.retrocession_pct::text, '')
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{numero_contrat}}',
      public.fn_html_escape(v_numero_contrat)
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{date_signature}}',
      pg_catalog.to_char(
        pg_catalog.now() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'
      )
    );
    v_html := pg_catalog.replace(
      v_html,
      '{{lieu}}',
      public.fn_html_escape(COALESCE(v_mission.etablissement_ville, ''))
    );

    INSERT INTO public.contrats_mission (
      mission_id,
      etablissement_id,
      soignant_id,
      type_contrat,
      numero_contrat,
      contenu_html,
      statut
    )
    SELECT
      v_mission.id,
      v_mission.etablissement_id,
      v_mission.soignant_assigne_id,
      v_type_contrat,
      v_numero_contrat,
      v_html,
      'EN_ATTENTE_SIGNATURES'
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.contrats_mission cm
      WHERE cm.mission_id = v_mission.id
        AND cm.etablissement_id = v_mission.etablissement_id
        AND cm.soignant_id = v_mission.soignant_assigne_id
        AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
    )
    ;
    GET DIAGNOSTICS v_contrat_cree = ROW_COUNT;

    IF v_contrat_cree = 1 AND NOT EXISTS (
      SELECT 1
      FROM public.contrats_mission cm
      WHERE cm.mission_id = v_mission.id
        AND cm.etablissement_id = v_mission.etablissement_id
        AND cm.soignant_id = v_mission.soignant_assigne_id
        AND cm.statut = 'EN_ATTENTE_SIGNATURES'
        AND NULLIF(pg_catalog.btrim(cm.numero_contrat), '') IS NOT NULL
        AND NULLIF(pg_catalog.btrim(cm.contenu_html), '') IS NOT NULL
    ) THEN
      RAISE EXCEPTION
        'Contrat de rattrapage test inutilisable pour la mission %',
        v_mission.id;
    END IF;

    IF v_creneaux_supprimes > 0 OR v_contrat_cree > 0 THEN
      INSERT INTO public.journaux_audit (
        acteur_id,
        type_acteur,
        action,
        type_ressource,
        id_ressource,
        details
      ) VALUES (
        NULL,
        'SYSTEME',
        'SYSTEM',
        'mission',
        v_mission.id,
        pg_catalog.jsonb_build_object(
          'reason', 'RATTRAPAGE_MISSION_TEST_SANS_CONTRAT',
          'test_data_only', true,
          'status_preserved', v_mission.statut,
          'unproven_effective_slots_deleted', v_creneaux_supprimes,
          'contract_created', v_contrat_cree = 1
        )
      );
    END IF;
  END LOOP;

  PERFORM pg_catalog.set_config('app.test_mode', v_previous_test_mode, true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_catalog.set_config('app.test_mode', v_previous_test_mode, true);
  RAISE;
END;
$reparer_missions_test$;

CREATE OR REPLACE FUNCTION public.fn_stats_rh_etablissement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
  v_now timestamptz := pg_catalog.now();
  v_debut_mois timestamptz := pg_catalog.date_trunc('month', pg_catalog.now());
  v_debut_mois_prec timestamptz := pg_catalog.date_trunc(
    'month', pg_catalog.now() - interval '1 month'
  );
  v_fin_mois timestamptz := pg_catalog.date_trunc(
    'month', pg_catalog.now()
  ) + interval '1 month';
  v_mois_fr text[] := ARRAY[
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
  ];
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Établissement introuvable');
  END IF;

  WITH heures_terminees_exactes AS (
    -- Pour une mission terminée, les créneaux EFFECTIF clos font foi dès
    -- qu'ils existent. À défaut seulement, on reprend le PREVISIONNEL. Une
    -- mission longue discontinue n'est donc jamais comptée 24 h/24 sur son
    -- enveloppe debut_le/fin_le.
    SELECT
      m.id AS mission_id,
      pg_catalog.sum(
        EXTRACT(epoch FROM (mc.fin - mc.debut)) / 3600.0
      )::numeric AS heures
    FROM public.missions m
    JOIN public.mission_creneaux mc ON mc.mission_id = m.id
    WHERE m.etablissement_id = v_etab_id
      AND m.statut = 'TERMINEE'
      AND mc.est_pause IS FALSE
      AND mc.fin IS NOT NULL
      AND mc.fin > mc.debut
      AND (
        mc.type_creneau = 'EFFECTIF'
        OR (
          mc.type_creneau = 'PREVISIONNEL'
          AND NOT EXISTS (
            SELECT 1
            FROM public.mission_creneaux effectif
            WHERE effectif.mission_id = m.id
              AND effectif.type_creneau = 'EFFECTIF'
              AND effectif.est_pause IS FALSE
              AND effectif.fin IS NOT NULL
              AND effectif.fin > effectif.debut
          )
        )
      )
    GROUP BY m.id
  ),
  planning_total AS (
    SELECT
      mc.mission_id,
      pg_catalog.sum(
        EXTRACT(epoch FROM (mc.fin - mc.debut)) / 3600.0
      )::numeric AS heures_totales
    FROM public.mission_creneaux mc
    WHERE mc.type_creneau = 'PREVISIONNEL'
      AND mc.est_pause IS FALSE
      AND mc.fin IS NOT NULL
    GROUP BY mc.mission_id
  ),
  planning_futur AS (
    SELECT
      m.id AS mission_id,
      m.intitule,
      m.statut,
      m.soignant_assigne_id,
      m.total_brut,
      m.montant_commission_ttc,
      pt.heures_totales,
      pg_catalog.sum(
        EXTRACT(epoch FROM (mc.fin - mc.debut)) / 3600.0
      )::numeric AS heures_futures,
      pg_catalog.min(mc.debut) AS prochain_debut,
      pg_catalog.min(mc.fin) AS prochaine_fin,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
      s.profession::text AS soignant_profession
    FROM public.missions m
    JOIN public.mission_creneaux mc
      ON mc.mission_id = m.id
     AND mc.type_creneau = 'PREVISIONNEL'
     AND mc.est_pause IS FALSE
     AND mc.fin IS NOT NULL
     AND mc.debut >= v_now
    JOIN planning_total pt ON pt.mission_id = m.id
    LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE m.etablissement_id = v_etab_id
      AND m.statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS')
    GROUP BY
      m.id,
      m.intitule,
      m.statut,
      m.soignant_assigne_id,
      m.total_brut,
      m.montant_commission_ttc,
      pt.heures_totales,
      s.prenom,
      s.nom,
      s.profession
  ),
  planning_confirme AS (
    SELECT *
    FROM planning_futur
    WHERE statut IN ('ASSIGNEE', 'EN_COURS')
  )
  SELECT pg_catalog.jsonb_build_object(
    'terminees_total', (
      SELECT pg_catalog.count(*)
      FROM public.missions
      WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'
    ),
    'terminees_mois_prec', (
      SELECT pg_catalog.count(*)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut = 'TERMINEE'
        AND fin_le >= v_debut_mois_prec
        AND fin_le < v_debut_mois
    ),
    'terminees_ce_mois', (
      SELECT pg_catalog.count(*)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut = 'TERMINEE'
        AND fin_le >= v_debut_mois
    ),
    'cout_total_termine', COALESCE((
      SELECT pg_catalog.sum(total_brut)
      FROM public.missions
      WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'
    ), 0),
    'cout_mois_prec', COALESCE((
      SELECT pg_catalog.sum(total_brut)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut = 'TERMINEE'
        AND fin_le >= v_debut_mois_prec
        AND fin_le < v_debut_mois
    ), 0),
    'cout_ce_mois', COALESCE((
      SELECT pg_catalog.sum(total_brut)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut = 'TERMINEE'
        AND fin_le >= v_debut_mois
    ), 0),
    'commission_mois_prec', COALESCE((
      SELECT pg_catalog.sum(montant_commission_ttc)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut = 'TERMINEE'
        AND fin_le >= v_debut_mois_prec
        AND fin_le < v_debut_mois
    ), 0),
    'commission_ce_mois', COALESCE((
      SELECT pg_catalog.sum(montant_commission_ttc)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut = 'TERMINEE'
        AND fin_le >= v_debut_mois
    ), 0),
    'heures_terminees', COALESCE((
      SELECT pg_catalog.sum(hte.heures)
      FROM heures_terminees_exactes hte
    ), 0),
    'cout_moyen_heure', COALESCE((
      SELECT pg_catalog.round((
        pg_catalog.sum(COALESCE(m.total_brut, 0))
        / NULLIF(pg_catalog.sum(hte.heures), 0)
      )::numeric, 2)
      FROM public.missions m
      JOIN heures_terminees_exactes hte ON hte.mission_id = m.id
      WHERE hte.heures > 0
    ), 0),
    -- Les quatre indicateurs prévisionnels ne comptent que la part future des
    -- créneaux exacts confirmés, y compris les missions déjà EN_COURS.
    'assignees_total', (
      SELECT pg_catalog.count(*) FROM planning_confirme
    ),
    'cout_previsionnel_brut', COALESCE((
      SELECT pg_catalog.round(pg_catalog.sum(
        COALESCE(total_brut, 0)
        * heures_futures / NULLIF(heures_totales, 0)
      ), 2)
      FROM planning_confirme
    ), 0),
    'commission_previsionnelle', COALESCE((
      SELECT pg_catalog.round(pg_catalog.sum(
        COALESCE(montant_commission_ttc, 0)
        * heures_futures / NULLIF(heures_totales, 0)
      ), 2)
      FROM planning_confirme
    ), 0),
    'cout_previsionnel_total', COALESCE((
      SELECT pg_catalog.round(pg_catalog.sum(
        (COALESCE(total_brut, 0) + COALESCE(montant_commission_ttc, 0))
        * heures_futures / NULLIF(heures_totales, 0)
      ), 2)
      FROM planning_confirme
    ), 0),
    'heures_prevues', COALESCE((
      SELECT pg_catalog.round(pg_catalog.sum(heures_futures), 2)
      FROM planning_confirme
    ), 0),
    'ouvertes_total', (
      SELECT pg_catalog.count(*)
      FROM public.missions
      WHERE etablissement_id = v_etab_id AND statut = 'OUVERTE'
    ),
    'taux_remplissage', COALESCE((
      SELECT pg_catalog.round((
        pg_catalog.count(*) FILTER (
          WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        )::numeric
        / NULLIF(pg_catalog.count(*) FILTER (
          WHERE statut NOT IN (
            'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT'
          )
        ), 0)
      ) * 100, 0)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
    ), 0),
    'soignants_total', (
      SELECT pg_catalog.count(DISTINCT soignant_assigne_id)
      FROM public.missions
      WHERE etablissement_id = v_etab_id
        AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    ),
    'soignants_ce_mois', (
      SELECT pg_catalog.count(DISTINCT m.soignant_assigne_id)
      FROM public.missions m
      JOIN public.mission_creneaux mc ON mc.mission_id = m.id
      WHERE m.etablissement_id = v_etab_id
        AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        AND mc.type_creneau = 'PREVISIONNEL'
        AND mc.est_pause IS FALSE
        AND mc.fin > v_debut_mois
        AND mc.debut < v_fin_mois
    ),
    'top_soignants', COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.row_to_json(x))
      FROM (
        SELECT
          s.id::text AS soignant_id,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS nom,
          s.profession::text,
          s.score_fiabilite,
          s.note_moyenne,
          pg_catalog.count(*) AS nb_missions,
          pg_catalog.sum(m.total_brut) AS total_facture
        FROM public.missions m
        JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE'
        GROUP BY s.id
        ORDER BY nb_missions DESC
        LIMIT 5
      ) x
    ), '[]'::jsonb),
    'missions_mois_prec', COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.row_to_json(x))
      FROM (
        SELECT
          m.id::text AS mission_id,
          m.intitule,
          m.debut_le,
          m.fin_le,
          m.total_brut,
          m.montant_commission_ttc,
          COALESCE(hte.heures, 0) AS heures,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          s.profession::text AS soignant_profession
        FROM public.missions m
        LEFT JOIN heures_terminees_exactes hte ON hte.mission_id = m.id
        LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.etablissement_id = v_etab_id
          AND m.statut = 'TERMINEE'
          AND m.fin_le >= v_debut_mois_prec
          AND m.fin_le < v_debut_mois
        ORDER BY m.fin_le DESC
      ) x
    ), '[]'::jsonb),
    'missions_ce_mois', COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.row_to_json(x))
      FROM (
        SELECT
          m.id::text AS mission_id,
          m.intitule,
          m.debut_le,
          m.fin_le,
          m.total_brut,
          m.montant_commission_ttc,
          COALESCE(hte.heures, 0) AS heures,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          s.profession::text AS soignant_profession
        FROM public.missions m
        LEFT JOIN heures_terminees_exactes hte ON hte.mission_id = m.id
        LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.etablissement_id = v_etab_id
          AND m.statut = 'TERMINEE'
          AND m.fin_le >= v_debut_mois
        ORDER BY m.fin_le DESC
      ) x
    ), '[]'::jsonb),
    'prochaines_missions', COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.row_to_json(x))
      FROM (
        SELECT
          pf.mission_id::text AS mission_id,
          pf.intitule,
          pf.prochain_debut AS debut_le,
          pf.prochaine_fin AS fin_le,
          pg_catalog.round(
            COALESCE(pf.total_brut, 0)
            * pf.heures_futures / NULLIF(pf.heures_totales, 0),
            2
          ) AS total_brut,
          pg_catalog.round(
            COALESCE(pf.montant_commission_ttc, 0)
            * pf.heures_futures / NULLIF(pf.heures_totales, 0),
            2
          ) AS montant_commission_ttc,
          pf.heures_futures AS heures,
          pf.statut::text,
          pf.soignant_nom,
          pf.soignant_profession
        FROM planning_futur pf
        ORDER BY pf.prochain_debut ASC
        LIMIT 10
      ) x
    ), '[]'::jsonb),
    'mois_en_cours',
      v_mois_fr[EXTRACT(month FROM pg_catalog.now())::integer]
      || ' ' || EXTRACT(year FROM pg_catalog.now())::text,
    'mois_precedent',
      v_mois_fr[
        EXTRACT(month FROM pg_catalog.now() - interval '1 month')::integer
      ] || ' '
      || EXTRACT(year FROM pg_catalog.now() - interval '1 month')::text
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_stats_rh_etablissement()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_stats_rh_etablissement()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_stats_rh_etablissement() IS
  'Statistiques RH du tenant courant; futur sur PREVISIONNEL exact et historique sur EFFECTIF exact, avec repli PREVISIONNEL.';

UPDATE private.security_definer_inventory
SET definition_md5 = 'fb1878c89f881cb577c2511263ee86a6',
    justification = 'RPC établissement authentifié: tenant courant; futur PREVISIONNEL exact et historique EFFECTIF exact avec repli PREVISIONNEL.',
    recense_le = pg_catalog.now()
WHERE signature = 'fn_stats_rh_etablissement()';

DO $assertions$
DECLARE
  v_bad text;
BEGIN
  -- Toute mission éligible au rattrapage possède maintenant son contrat.
  SELECT pg_catalog.string_agg(m.id::text, ', ' ORDER BY m.id::text)
  INTO v_bad
  FROM public.missions m
  JOIN public.etablissements e
    ON e.id = m.etablissement_id
   AND e.est_compte_test IS TRUE
   AND e.supprime_le IS NULL
  JOIN public.soignants s
    ON s.id = m.soignant_assigne_id
   AND s.est_compte_test IS TRUE
   AND s.supprime_le IS NULL
  WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND NOT EXISTS (
      SELECT 1
      FROM public.contrats_mission cm
      WHERE cm.mission_id = m.id
        AND cm.etablissement_id = m.etablissement_id
        AND cm.soignant_id = m.soignant_assigne_id
        AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.candidatures c
      LEFT JOIN public.soignants sc ON sc.id = c.soignant_id
      WHERE c.mission_id = m.id
        AND sc.est_compte_test IS DISTINCT FROM TRUE
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.presences p
      LEFT JOIN public.soignants sp ON sp.id = p.soignant_id
      WHERE p.mission_id = m.id
        AND sp.est_compte_test IS DISTINCT FROM TRUE
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.scans_pointage scan
      LEFT JOIN public.soignants ss ON ss.id = scan.soignant_id
      WHERE scan.mission_id = m.id
        AND ss.est_compte_test IS DISTINCT FROM TRUE
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.contrats_mission cm_lie
      LEFT JOIN public.soignants s_lie ON s_lie.id = cm_lie.soignant_id
      WHERE cm_lie.mission_id = m.id
        AND s_lie.est_compte_test IS DISTINCT FROM TRUE
    );

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Missions test actives toujours sans contrat: %', v_bad;
  END IF;

  -- Fixture explicitement signalée: l'assertion reste no-op sur les bases où
  -- elle n'existe pas, mais fail-closed si elle existe encore incohérente.
  IF EXISTS (
    SELECT 1
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE m.id = '0f180010-0000-4000-8000-000000000001'::uuid
      AND e.est_compte_test IS TRUE
      AND s.est_compte_test IS TRUE
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.contrats_mission cm
          WHERE cm.mission_id = m.id
            AND cm.soignant_id = m.soignant_assigne_id
            AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
            AND NULLIF(pg_catalog.btrim(cm.contenu_html), '') IS NOT NULL
        )
        OR EXISTS (
          SELECT 1
          FROM public.mission_creneaux mc
          WHERE mc.mission_id = m.id
            AND mc.type_creneau = 'EFFECTIF'
            AND NOT EXISTS (
              SELECT 1 FROM public.scans_pointage scan
              WHERE scan.mission_id = m.id
                 OR scan.creneau_effectif_id = mc.id
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.presences p
              WHERE p.mission_id = m.id
                AND (
                  p.pointage_arrivee_le IS NOT NULL
                  OR p.pointage_depart_le IS NOT NULL
                )
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.factures f
              WHERE f.mission_id = m.id
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.factures_honoraires fh
              WHERE fh.mission_id = m.id
            )
        )
      )
  ) THEN
    RAISE EXCEPTION 'Fixture 0f180010 toujours incohérente après rattrapage';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN private.security_definer_inventory i
      ON i.signature = p.oid::pg_catalog.regprocedure::text
    WHERE p.oid = 'public.fn_stats_rh_etablissement()'::pg_catalog.regprocedure
      AND n.nspname = 'public'
      AND p.prosecdef IS TRUE
      AND p.proconfig && ARRAY['search_path=', 'search_path=""']::text[]
      AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND i.definition_md5 = pg_catalog.md5(p.prosrc)
  ) THEN
    RAISE EXCEPTION 'fn_stats_rh_etablissement: sécurité, ACL ou inventaire invalide';
  END IF;
END
$assertions$;

COMMIT;
