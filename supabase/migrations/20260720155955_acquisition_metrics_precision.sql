-- Corrige deux biais de mesure sans modifier le mode silencieux :
--   * un soignant verifie n'est compte qu'une fois, meme avec plusieurs jours
--     de disponibilite ;
--   * les employeurs anonymes ne sont jamais fusionnes en un faux compte ancre.

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_generer_actions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_creees integer := 0; v_ajoutees integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  SELECT
    'QUALIFIER_SIGNAL', 'SIGNAL', s.id::text,
    'Qualifier le besoin — ' || s.nom_etablissement,
    s.intitule || ' · ' || COALESCE(s.ville, s.departement, 'localisation inconnue'),
    s.departement, s.profession, s.score_demande,
    round((s.volume_estime * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'SIGNAL:' || s.id::text
  FROM public.acquisition_signaux s
  WHERE s.statut IN ('NOUVEAU', 'QUALIFIE')
    AND (s.expire_le IS NULL OR s.expire_le >= now())
  ON CONFLICT (idempotence_key) DO UPDATE SET
    titre = EXCLUDED.titre,
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH segments AS (
    SELECT
      t.departement, t.profession, t.objectif_soignants_verifies,
      t.objectif_missions_mensuelles,
      (SELECT count(*) FROM public.soignants s
        WHERE s.supprime_le IS NULL AND NOT s.est_compte_test
          AND s.tous_documents_valides
          AND s.profession::text = t.profession
          AND (CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END) = t.departement) AS soignants,
      (SELECT COALESCE(sum(sig.volume_estime), 0) FROM public.acquisition_signaux sig
        WHERE sig.departement = t.departement AND sig.profession = t.profession
          AND sig.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')) AS demande
    FROM public.acquisition_territoires t
    WHERE t.statut IN ('PREPARATION', 'OUVERT')
  )
  SELECT
    'RENFORCER_VIVIER', 'TERRITOIRE', departement || ':' || profession,
    'Renforcer le vivier ' || profession || ' — ' || departement,
    soignants::text || ' soignant(s) verifie(s) pour un objectif de ' || objectif_soignants_verifies::text,
    departement, profession,
    LEAST(100, 50 + GREATEST(objectif_soignants_verifies - soignants, 0) * 2)::smallint,
    round((LEAST(demande, objectif_missions_mensuelles) * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'VIVIER:' || departement || ':' || profession
  FROM segments
  WHERE soignants < objectif_soignants_verifies AND demande > 0
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Transformer plusieurs signaux publics convergents en compte ancre a
  -- qualifier. Cette recommandation reste strictement interne.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH signaux_identifies AS (
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
  ), ancres AS (
    SELECT
      s.cible_id,
      max(s.nom_etablissement) AS nom_etablissement,
      max(s.departement) AS departement,
      max(s.profession) AS profession,
      count(*)::integer AS signaux,
      sum(s.volume_estime)::integer AS volume,
      max(s.score_demande)::smallint AS score
    FROM signaux_identifies s
    WHERE s.cible_id IS NOT NULL
    GROUP BY s.cible_id
    HAVING count(*) >= 2 OR sum(s.volume_estime) >= 3
  )
  SELECT
    'COMPTE_ANCRE', 'ETABLISSEMENT', cible_id,
    'Qualifier comme compte ancre — ' || nom_etablissement,
    signaux::text || ' signal(aux) public(s), besoin estime a ' || volume::text
      || ' mission(s). Aucune prise de contact automatique.',
    departement, profession, LEAST(100, score + 10)::smallint,
    round((volume * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'ANCRE:' || cible_id
  FROM ancres
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Reverse marketplace : montrer a l'equipe les segments ou l'offre verifiee
  -- peut etre proposee manuellement aux etablissements, sans exposer les
  -- coordonnees des soignants ni lancer une campagne.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH disponibilite AS (
    SELECT
      CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END AS departement,
      s.profession::text AS profession,
      count(DISTINCT s.id)::integer AS soignants_disponibles
    FROM public.soignants s
    JOIN public.disponibilites_soignant ds ON ds.soignant_id = s.id
      AND ds.jour BETWEEN current_date AND current_date + 14
    WHERE s.supprime_le IS NULL
      AND NOT s.est_compte_test
      AND s.tous_documents_valides
      AND s.profession IS NOT NULL
    GROUP BY 1, 2
  )
  SELECT
    'REVERSE_MARKETPLACE', 'TERRITOIRE', d.departement || ':' || d.profession,
    'Valoriser le vivier disponible — ' || d.profession || ' · ' || d.departement,
    d.soignants_disponibles::text || ' soignant(s) verifie(s) disponible(s) sous 14 jours. '
      || 'Preparer une offre anonymisee a valider humainement.',
    d.departement, d.profession,
    LEAST(100, 45 + d.soignants_disponibles * 3)::smallint,
    round((LEAST(d.soignants_disponibles, 20) * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'REVERSE:' || d.departement || ':' || d.profession
  FROM disponibilite d
  LEFT JOIN public.acquisition_territoires t
    ON t.departement = d.departement AND t.profession = d.profession
  WHERE d.departement IS NOT NULL
    AND d.soignants_disponibles >= 3
    AND COALESCE(t.statut, 'OBSERVATION') <> 'PAUSE'
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Les etablissements ayant deja repete des missions sont les candidats les
  -- plus solides a une planification recurrente.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH recurrents AS (
    SELECT
      e.id, e.nom, e.adresse_departement AS departement,
      max(m.profession_requise::text) AS profession,
      count(m.id)::integer AS missions,
      count(DISTINCT m.serie_id) FILTER (WHERE m.serie_id IS NOT NULL)::integer AS series,
      round((COALESCE(sum(COALESCE(m.montant_commission_ht,
        COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
          * COALESCE(m.taux_commission, 15) / 100)), 0) / 180 * 30)::numeric, 2) AS commission_mensuelle_ht
    FROM public.etablissements e
    JOIN public.missions m ON m.etablissement_id = e.id
    WHERE e.supprime_le IS NULL
      AND NOT e.est_compte_test
      AND m.cree_le >= now() - interval '180 days'
    GROUP BY e.id, e.nom, e.adresse_departement
    HAVING count(m.id) >= 2
  )
  SELECT
    'RECURRENCE', 'ETABLISSEMENT', id::text,
    'Proposer un rythme recurrent — ' || nom,
    missions::text || ' mission(s) sur 180 jours, dont ' || series::text
      || ' serie(s). Preparer un calendrier recurrent pour validation humaine.',
    departement, profession, LEAST(100, 55 + missions * 3)::smallint,
    GREATEST(commission_mensuelle_ht, 0),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'RECURRENCE:' || id::text
  FROM recurrents
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Expansion des groupes deja identifies : une validation humaine decide
  -- ensuite si le contrat peut etre etendu a d'autres etablissements.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  SELECT
    'CIBLER_GROUPE', 'GROUPE', g.id::text,
    'Etendre le deploiement — ' || g.nom,
    count(e.id)::text || ' etablissement(s) deja rattache(s). Identifier les implantations suivantes avant toute prise de contact.',
    NULL, NULL, LEAST(100, 60 + count(e.id) * 3)::smallint,
    round((count(e.id) * 10 * 8 * 25 * COALESCE(g.taux_commission_negocie, 15) / 100)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'GROUPE:' || g.id::text
  FROM public.groupes_sante g
  LEFT JOIN public.etablissements e ON e.groupe_sante_id = g.id AND e.supprime_le IS NULL AND NOT e.est_compte_test
  WHERE g.supprime_le IS NULL
  GROUP BY g.id, g.nom, g.taux_commission_negocie
  HAVING count(e.id) >= 1
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Les ecoles issues du repertoire public alimentent un vivier futur. Leur
  -- fiche est uniquement placee dans la file de qualification interne.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  SELECT
    'PARTENARIAT_ECOLE', 'ECOLE', p.finess,
    'Qualifier un partenariat ecole — ' || p.nom,
    COALESCE(NULLIF(p.categorie_lib, ''), 'Etablissement de formation')
      || ' · ' || COALESCE(NULLIF(p.ville, ''), NULLIF(p.departement, ''), 'localisation inconnue')
      || '. Aucun message ne sera envoye sans action humaine.',
    p.departement, NULL, CASE WHEN p.favori THEN 75 ELSE 50 END::smallint,
    0, 'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'ECOLE:' || p.finess
  FROM public.prospects_etablissements p
  WHERE p.type_jolene = 'ECOLE_SANTE'
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  RETURN jsonb_build_object(
    'success', true,
    'actions_preparees', v_creees,
    'statut', 'BROUILLON',
    'contact_automatique', false,
    'genere_le', now()
  );
END;
$fn$;


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
     AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test));

  RETURN (
    WITH offre AS (
      SELECT
        CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END AS departement,
        s.profession::text AS profession,
        count(DISTINCT s.id) FILTER (WHERE s.tous_documents_valides)::integer AS verifies,
        count(DISTINCT ds.soignant_id) FILTER (WHERE ds.jour BETWEEN current_date AND current_date + 14)::integer AS disponibles_14j
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
        count(*) FILTER (WHERE m.soignant_assigne_id IS NOT NULL)::integer AS pourvues,
        count(DISTINCT m.etablissement_id)::integer AS etablissements,
        COALESCE(sum(COALESCE(m.montant_commission_ht,
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100)), 0)::numeric AS commission_ht
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
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
      GROUP BY 1, 2
    ),
    cles AS (
      SELECT departement, profession FROM offre
      UNION SELECT departement, profession FROM demande_interne
      UNION SELECT departement, profession FROM demande_externe
      UNION SELECT departement, profession FROM public.acquisition_territoires
    ),
    segments AS (
      SELECT
        c.departement, c.profession,
        COALESCE(o.verifies, 0) AS soignants_verifies,
        COALESCE(o.disponibles_14j, 0) AS disponibles_14j,
        COALESCE(di.missions, 0) AS missions_90j,
        COALESCE(di.ouvertes, 0) AS missions_ouvertes,
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
          - LEAST(COALESCE(o.disponibles_14j, 0), 20)
        ))::integer AS score_priorite,
        round((COALESCE(de.volume, 0) * 8 * v_taux_horaire * v_taux / 100)::numeric, 2) AS potentiel_commission_mensuel_ht,
        COALESCE(di.commission_ht, 0) AS commission_observee_ht
      FROM cles c
      LEFT JOIN offre o ON o.departement IS NOT DISTINCT FROM c.departement AND o.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN demande_interne di ON di.departement IS NOT DISTINCT FROM c.departement AND di.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN demande_externe de ON de.departement IS NOT DISTINCT FROM c.departement AND de.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN public.acquisition_territoires t ON t.departement IS NOT DISTINCT FROM c.departement AND t.profession IS NOT DISTINCT FROM c.profession
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
        AND (v_departement IS NULL OR s.departement = v_departement)
        AND (v_profession IS NULL OR s.profession = v_profession)
    ),
    ancres AS (
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
    recurrence AS (
      SELECT e.id, e.nom, e.adresse_departement AS departement,
        count(m.id)::integer AS missions,
        count(DISTINCT m.serie_id) FILTER (WHERE m.serie_id IS NOT NULL)::integer AS series,
        count(DISTINCT m.profession_requise)::integer AS professions,
        round((COALESCE(sum(COALESCE(m.montant_commission_ht,
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100)), 0)
          / GREATEST(v_jours, 1) * 30)::numeric, 2) AS commission_mensuelle_estimee_ht
      FROM public.etablissements e
      JOIN public.missions m ON m.etablissement_id = e.id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
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
        'caractere', 'estimation, pas revenu garanti'
      ),
      'stats', jsonb_build_object(
        'signaux_actifs', (SELECT count(*) FROM public.acquisition_signaux s WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM') AND (s.expire_le IS NULL OR s.expire_le >= now())),
        'etablissements_a_potentiel', (SELECT count(*) FROM ancres),
        'soignants_verifies', (SELECT COALESCE(sum(soignants_verifies), 0) FROM segments),
        'disponibles_14j', (SELECT COALESCE(sum(disponibles_14j), 0) FROM segments),
        'potentiel_commission_mensuel_ht', (SELECT COALESCE(sum(potentiel_commission_mensuel_ht), 0) FROM segments),
        'commission_observee_ht', (SELECT COALESCE(sum(commission_observee_ht), 0) FROM segments),
        'actions_brouillon', (SELECT count(*) FROM public.acquisition_actions WHERE statut = 'BROUILLON')
      ),
      'segments', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.score_priorite DESC, s.volume_externe DESC) FROM segments s), '[]'::jsonb),
      'ancres', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.score DESC, a.volume DESC) FROM (SELECT * FROM ancres ORDER BY score DESC, volume DESC LIMIT 50) a), '[]'::jsonb),
      'recurrence', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.missions DESC) FROM (SELECT * FROM recurrence ORDER BY missions DESC LIMIT 30) r), '[]'::jsonb),
      'signaux', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.score_demande DESC, s.maj_le DESC) FROM (SELECT * FROM public.acquisition_signaux s WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM') AND (s.expire_le IS NULL OR s.expire_le >= now()) AND (v_departement IS NULL OR s.departement = v_departement) AND (v_profession IS NULL OR s.profession = v_profession) ORDER BY s.score_demande DESC, s.maj_le DESC LIMIT 100) s), '[]'::jsonb),
      'actions', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.score DESC, a.cree_le DESC) FROM (SELECT * FROM public.acquisition_actions WHERE statut IN ('BROUILLON', 'PRIORISEE', 'EN_COURS') ORDER BY score DESC, cree_le DESC LIMIT 100) a), '[]'::jsonb),
      'sources', COALESCE((SELECT jsonb_agg(to_jsonb(src) ORDER BY src.type_source, src.libelle) FROM public.acquisition_sources src), '[]'::jsonb),
      'depenses', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.periode_fin DESC, d.canal) FROM public.acquisition_depenses d WHERE d.periode_fin >= current_date - make_interval(days => v_jours)), '[]'::jsonb)
    )
  );
END;
$fn$;


REVOKE ALL ON FUNCTION public.fn_admin_acquisition_generer_actions() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_generer_actions() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) TO authenticated, service_role;
