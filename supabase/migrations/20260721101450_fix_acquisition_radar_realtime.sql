-- Le radar précédent calculait le potentiel uniquement depuis les signaux
-- France Travail. Sans secrets France Travail, il affichait donc 0 € alors que
-- des missions Jolene réelles existaient. Le potentiel combine désormais le
-- pipeline attribué/en cours, le stock de missions ouvertes et les signaux
-- externes éventuellement configurés. La commission observée reste strictement
-- limitée aux missions terminées.

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_radar(
  p_scope text DEFAULT 'REEL',
  p_jours integer DEFAULT 90,
  p_departement text DEFAULT NULL,
  p_profession text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_scope text := upper(COALESCE(p_scope, 'REEL'));
  v_jours integer := LEAST(GREATEST(COALESCE(p_jours, 90), 7), 365);
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_profession text := NULLIF(upper(btrim(COALESCE(p_profession, ''))), '');
  v_taux numeric := 15;
  v_taux_horaire numeric := 25;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501'; END IF;
  IF v_scope NOT IN ('REEL', 'TEST', 'TOUS') THEN RAISE EXCEPTION 'Scope invalide'; END IF;

  SELECT COALESCE(avg(NULLIF(m.taux_commission, 0)), 15),
         COALESCE(avg(NULLIF(m.taux_horaire_base, 0)), 25)
    INTO v_taux, v_taux_horaire
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.cree_le >= now() - make_interval(days => v_jours)
     AND m.statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
     AND (m.statut <> 'OUVERTE' OR m.fin_le >= now())
     AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test));

  RETURN (
    WITH offre AS (
      SELECT
        CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END AS departement,
        s.profession::text AS profession,
        count(DISTINCT s.id) FILTER (WHERE s.tous_documents_valides)::integer AS verifies,
        count(DISTINCT ds.soignant_id) FILTER (
          WHERE ds.jour BETWEEN current_date AND current_date + 14
            AND s.tous_documents_valides
        )::integer AS disponibles_14j
      FROM public.soignants s
      LEFT JOIN public.disponibilites_soignant ds ON ds.soignant_id = s.id
      WHERE s.supprime_le IS NULL
        AND s.profession IS NOT NULL
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND s.est_compte_test) OR (v_scope = 'REEL' AND NOT s.est_compte_test))
      GROUP BY 1, 2
    ),
    demande_interne AS (
      SELECT e.adresse_departement AS departement, m.profession_requise::text AS profession,
        count(*)::integer AS missions,
        count(*) FILTER (WHERE m.statut = 'OUVERTE')::integer AS ouvertes,
        count(*) FILTER (WHERE m.statut IN ('ASSIGNEE', 'EN_COURS'))::integer AS pipeline,
        count(*) FILTER (WHERE m.soignant_assigne_id IS NOT NULL)::integer AS pourvues,
        count(DISTINCT m.etablissement_id)::integer AS etablissements,
        COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100))
          FILTER (WHERE m.statut = 'TERMINEE'), 0)::numeric AS commission_observee_ht,
        COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100))
          FILTER (WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')), 0)::numeric AS commission_pipeline_ht,
        COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100)) FILTER (WHERE m.statut = 'OUVERTE'), 0)::numeric AS commission_ouverte_ht
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
        AND m.statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
        AND (m.statut <> 'OUVERTE' OR m.fin_le >= now())
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test))
      GROUP BY 1, 2
    ),
    demande_externe AS (
      SELECT s.departement, s.profession,
        count(*)::integer AS signaux,
        COALESCE(sum(s.volume_estime), 0)::integer AS volume,
        COALESCE(round(avg(s.score_demande)), 0)::integer AS score_moyen
      FROM public.acquisition_signaux s
      WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')
        AND (s.expire_le IS NULL OR s.expire_le >= now())
        -- Un signal déjà rapproché d'un établissement Jolene ne doit pas être
        -- recompté comme demande externe. Les données externes sont réelles et
        -- n'ont pas de scope test : elles sont donc absentes de TEST.
        AND s.etablissement_id IS NULL
        AND v_scope <> 'TEST'
      GROUP BY 1, 2
    ),
    cles AS (
      SELECT departement, profession FROM offre
      UNION SELECT departement, profession FROM demande_interne
      UNION SELECT departement, profession FROM demande_externe
      UNION SELECT departement, profession FROM public.acquisition_territoires WHERE v_scope <> 'TEST'
    ),
    segments AS (
      SELECT
        c.departement, c.profession,
        COALESCE(o.verifies, 0) AS soignants_verifies,
        COALESCE(o.disponibles_14j, 0) AS disponibles_14j,
        COALESCE(di.missions, 0) AS missions_90j,
        COALESCE(di.ouvertes, 0) AS missions_ouvertes,
        COALESCE(di.pipeline, 0) AS missions_pipeline,
        COALESCE(di.pourvues, 0) AS missions_pourvues,
        COALESCE(di.etablissements, 0) AS etablissements_actifs,
        COALESCE(de.signaux, 0) AS signaux_externes,
        COALESCE(de.volume, 0) AS volume_externe,
        COALESCE(de.score_moyen, 0) AS score_signal,
        COALESCE(t.statut, 'OBSERVATION') AS statut_territoire,
        COALESCE(t.objectif_etablissements_ancres, 2) AS objectif_ancres,
        COALESCE(t.objectif_soignants_verifies, 20) AS objectif_soignants,
        COALESCE(t.objectif_missions_mensuelles, 20) AS objectif_missions,
        t.bmo_annee, t.bmo_projets_recrutement, t.bmo_difficulte_pct,
        LEAST(100, GREATEST(0,
          20 + COALESCE(de.score_moyen, 0) * 0.35
          + LEAST(COALESCE(de.volume, 0), 20) * 2
          + LEAST(COALESCE(di.ouvertes, 0), 10) * 2
          + LEAST(COALESCE(di.missions, 0), 20)
          - LEAST(COALESCE(o.disponibles_14j, 0), 20)
        ))::integer AS score_priorite,
        round((
          COALESCE(de.volume, 0) * 8 * v_taux_horaire * v_taux / 100
          + GREATEST(
              COALESCE(di.commission_pipeline_ht, 0) / GREATEST(v_jours, 1) * 30,
              COALESCE(di.commission_ouverte_ht, 0)
            )
        )::numeric, 2) AS potentiel_commission_mensuel_ht,
        round((COALESCE(di.commission_observee_ht, 0) / GREATEST(v_jours, 1) * 30)::numeric, 2) AS commission_observee_mensuelle_ht,
        COALESCE(di.commission_observee_ht, 0) AS commission_observee_ht,
        round((COALESCE(di.commission_pipeline_ht, 0) / GREATEST(v_jours, 1) * 30)::numeric, 2) AS commission_pipeline_mensuelle_ht,
        COALESCE(di.commission_pipeline_ht, 0) AS commission_pipeline_ht,
        COALESCE(di.commission_ouverte_ht, 0) AS commission_ouverte_ht
      FROM cles c
      LEFT JOIN offre o ON o.departement IS NOT DISTINCT FROM c.departement AND o.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN demande_interne di ON di.departement IS NOT DISTINCT FROM c.departement AND di.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN demande_externe de ON de.departement IS NOT DISTINCT FROM c.departement AND de.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN public.acquisition_territoires t ON v_scope <> 'TEST'
        AND t.departement IS NOT DISTINCT FROM c.departement
        AND t.profession IS NOT DISTINCT FROM c.profession
      WHERE c.departement IS NOT NULL AND c.profession IS NOT NULL
        AND (v_departement IS NULL OR c.departement = v_departement)
        AND (v_profession IS NULL OR c.profession = v_profession)
    ),
    signaux_identifies AS (
      SELECT s.*,
        COALESCE(
          NULLIF(s.finess, ''),
          NULLIF(s.siret, ''),
          CASE
            WHEN lower(btrim(s.nom_etablissement)) NOT IN (
              'employeur non communique', 'employeur non communiqué',
              'entreprise non communiquee', 'entreprise non communiquée'
            ) THEN md5(lower(btrim(s.nom_etablissement)))
          END
        ) AS cible_id
      FROM public.acquisition_signaux s
      WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')
        AND (s.expire_le IS NULL OR s.expire_le >= now())
        AND s.etablissement_id IS NULL
        AND v_scope <> 'TEST'
        AND (v_departement IS NULL OR s.departement = v_departement)
        AND (v_profession IS NULL OR s.profession = v_profession)
    ),
    cibles_potentielles AS (
      SELECT 'JOLENE:' || e.id::text AS cible_id
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
        AND m.statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
        AND (m.statut <> 'OUVERTE' OR m.fin_le >= now())
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test))
        AND (v_departement IS NULL OR e.adresse_departement = v_departement)
        AND (v_profession IS NULL OR m.profession_requise::text = v_profession)
      UNION
      SELECT 'EXTERNE:' || cible_id FROM signaux_identifies WHERE cible_id IS NOT NULL
    ),
    ancres_externes AS (
      SELECT
        max(s.nom_etablissement) AS nom,
        max(s.departement) AS departement,
        max(s.ville) AS ville,
        max(s.finess) AS finess,
        max(s.siret) AS siret,
        count(*)::integer AS nb_signaux,
        sum(s.volume_estime)::integer AS volume,
        max(s.score_demande)::integer AS score,
        jsonb_agg(DISTINCT s.profession) FILTER (WHERE s.profession IS NOT NULL) AS professions,
        bool_or(s.etablissement_id IS NOT NULL) AS deja_inscrit,
        round((sum(s.volume_estime) * 8 * v_taux_horaire * v_taux / 100)::numeric, 2) AS potentiel_commission_mensuel_ht
      FROM signaux_identifies s
      WHERE s.cible_id IS NOT NULL
      GROUP BY s.cible_id
    ),
    ancres_internes AS (
      SELECT
        e.nom,
        e.adresse_departement AS departement,
        e.adresse_ville AS ville,
        e.finess,
        e.siret,
        count(m.id)::integer AS nb_signaux,
        count(m.id)::integer AS volume,
        LEAST(100, 50 + count(m.id) * 5)::integer AS score,
        jsonb_agg(DISTINCT m.profession_requise::text) AS professions,
        true AS deja_inscrit,
        round(GREATEST(
          COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
            COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
              * COALESCE(m.taux_commission, v_taux) / 100))
            FILTER (WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')), 0) / GREATEST(v_jours, 1) * 30,
          COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
            COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
              * COALESCE(m.taux_commission, v_taux) / 100)) FILTER (WHERE m.statut = 'OUVERTE'), 0)
        )::numeric, 2) AS potentiel_commission_mensuel_ht
      FROM public.etablissements e
      JOIN public.missions m ON m.etablissement_id = e.id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
        AND m.statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
        AND (m.statut <> 'OUVERTE' OR m.fin_le >= now())
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test))
        AND (v_departement IS NULL OR e.adresse_departement = v_departement)
        AND (v_profession IS NULL OR m.profession_requise::text = v_profession)
      GROUP BY e.id, e.nom, e.adresse_departement, e.adresse_ville, e.finess, e.siret
      HAVING count(m.id) >= 2
    ),
    ancres AS (
      SELECT * FROM ancres_internes
      UNION ALL
      SELECT * FROM ancres_externes
    ),
    recurrence AS (
      SELECT e.id, e.nom, e.adresse_departement AS departement,
        count(m.id)::integer AS missions,
        count(DISTINCT m.serie_id) FILTER (WHERE m.serie_id IS NOT NULL)::integer AS series,
        count(DISTINCT m.profession_requise)::integer AS professions,
        round(GREATEST(
          COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
            COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
              * COALESCE(m.taux_commission, v_taux) / 100))
            FILTER (WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')), 0)
            / GREATEST(v_jours, 1) * 30,
          COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
            COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
              * COALESCE(m.taux_commission, v_taux) / 100))
            FILTER (WHERE m.statut = 'OUVERTE'), 0)
        )::numeric, 2) AS commission_mensuelle_estimee_ht,
        round((COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100))
          FILTER (WHERE m.statut = 'TERMINEE'), 0)
          / GREATEST(v_jours, 1) * 30)::numeric, 2) AS commission_observee_mensuelle_ht,
        COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100))
          FILTER (WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')), 0)::numeric AS commission_pipeline_ht,
        COALESCE(sum(COALESCE(NULLIF(m.montant_commission_ht, 0),
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100))
          FILTER (WHERE m.statut = 'OUVERTE'), 0)::numeric AS commission_ouverte_ht
      FROM public.etablissements e
      JOIN public.missions m ON m.etablissement_id = e.id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
        AND m.statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
        AND (m.statut <> 'OUVERTE' OR m.fin_le >= now())
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test))
        AND (v_departement IS NULL OR e.adresse_departement = v_departement)
        AND (v_profession IS NULL OR m.profession_requise::text = v_profession)
      GROUP BY e.id, e.nom, e.adresse_departement
      HAVING count(m.id) >= 2
    )
    SELECT jsonb_build_object(
      'scope', v_scope,
      'jours', v_jours,
      'genere_le', now(),
      'contact_automatique', false,
      'marketing_actif', COALESCE((SELECT valeur::boolean FROM public.growth_config WHERE cle = 'automatisations_marketing_actives'), false),
      'hypotheses', jsonb_build_object(
        'taux_commission_pct', round(v_taux, 2),
        'taux_horaire_moyen', round(v_taux_horaire, 2),
        'duree_signal_heures', 8,
        'caractere', 'estimation, pas revenu garanti',
        'commission_observee', 'missions terminees uniquement',
        'pipeline_interne', 'missions assignees ou en cours, distinctes du realise',
        'potentiel_interne', 'maximum entre pipeline attribue/en cours mensualise et stock des missions ouvertes non expirees',
        'scope_test', 'missions, etablissements et soignants de test uniquement; signaux externes et territoires non scopes exclus'
      ),
      'stats', jsonb_build_object(
        'signaux_actifs', (SELECT COALESCE(sum(missions_90j + signaux_externes), 0) FROM segments),
        'etablissements_a_potentiel', (SELECT count(*) FROM cibles_potentielles),
        'soignants_verifies', (SELECT COALESCE(sum(soignants_verifies), 0) FROM segments),
        'disponibles_14j', (SELECT COALESCE(sum(disponibles_14j), 0) FROM segments),
        'potentiel_commission_mensuel_ht', (SELECT COALESCE(sum(potentiel_commission_mensuel_ht), 0) FROM segments),
        'commission_observee_ht', (SELECT COALESCE(sum(commission_observee_ht), 0) FROM segments),
        'commission_observee_mensuelle_ht', (SELECT COALESCE(sum(commission_observee_mensuelle_ht), 0) FROM segments),
        'commission_pipeline_ht', (SELECT COALESCE(sum(commission_pipeline_ht), 0) FROM segments),
        'commission_pipeline_mensuelle_ht', (SELECT COALESCE(sum(commission_pipeline_mensuelle_ht), 0) FROM segments),
        'commission_ouverte_ht', (SELECT COALESCE(sum(commission_ouverte_ht), 0) FROM segments),
        'actions_brouillon', (SELECT count(*) FROM public.acquisition_actions WHERE statut = 'BROUILLON')
      ),
      'segments', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.score_priorite DESC, s.volume_externe DESC, s.missions_ouvertes DESC) FROM segments s), '[]'::jsonb),
      'ancres', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.score DESC, a.volume DESC) FROM (SELECT * FROM ancres ORDER BY score DESC, volume DESC LIMIT 50) a), '[]'::jsonb),
      'recurrence', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.missions DESC) FROM (SELECT * FROM recurrence ORDER BY missions DESC LIMIT 30) r), '[]'::jsonb),
      'signaux', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.score_demande DESC, s.maj_le DESC) FROM (SELECT * FROM public.acquisition_signaux s WHERE v_scope <> 'TEST' AND s.etablissement_id IS NULL AND s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM') AND (s.expire_le IS NULL OR s.expire_le >= now()) AND (v_departement IS NULL OR s.departement = v_departement) AND (v_profession IS NULL OR s.profession = v_profession) ORDER BY s.score_demande DESC, s.maj_le DESC LIMIT 100) s), '[]'::jsonb),
      'actions', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.score DESC, a.cree_le DESC) FROM (SELECT * FROM public.acquisition_actions WHERE statut IN ('BROUILLON', 'PRIORISEE', 'EN_COURS') ORDER BY score DESC, cree_le DESC LIMIT 100) a), '[]'::jsonb),
      'sources', COALESCE((SELECT jsonb_agg(to_jsonb(src) ORDER BY src.type_source, src.libelle) FROM public.acquisition_sources src), '[]'::jsonb),
      'depenses', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.periode_fin DESC, d.canal) FROM public.acquisition_depenses d WHERE d.periode_fin >= current_date - make_interval(days => v_jours)), '[]'::jsonb)
    )
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) IS
  'Radar fondateur temps reel : besoins internes + signaux externes, liquidite et potentiel de commission mensualise. Aucun contact automatique.';
