-- Complete les recommandations internes du radar d'acquisition.
-- Toutes les actions restent en BROUILLON : aucun canal d'envoi n'est appele.

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



REVOKE ALL ON FUNCTION public.fn_admin_acquisition_generer_actions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_generer_actions() TO authenticated, service_role;
