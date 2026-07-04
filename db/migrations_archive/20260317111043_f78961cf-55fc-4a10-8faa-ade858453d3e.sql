-- Nettoyage et correction des fonctions / triggers cassés ou dupliqués

-- 1) Recherche publique des missions : supprimer les surcharges ambiguës puis recréer une seule version canonique
DROP FUNCTION IF EXISTS public.fn_missions_publiques_recherche(text, text);
DROP FUNCTION IF EXISTS public.fn_missions_publiques_recherche(public.type_profession, text);

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(
  p_profession text DEFAULT NULL,
  p_ville text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  intitule text,
  profession_requise text,
  ville text,
  code_postal text,
  debut_le timestamptz,
  fin_le timestamptz,
  taux_horaire_base numeric,
  est_urgente boolean,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH filtered AS (
    SELECT
      m.id,
      m.intitule,
      m.profession_requise::text AS profession_requise,
      e.adresse_ville::text AS ville,
      e.adresse_code_postal::text AS code_postal,
      m.debut_le,
      m.fin_le,
      m.taux_horaire_base,
      COALESCE(m.est_urgente, false) AS est_urgente
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND e.supprime_le IS NULL
      AND (
        p_profession IS NULL
        OR btrim(p_profession) = ''
        OR m.profession_requise::text = btrim(p_profession)
      )
      AND (
        p_ville IS NULL
        OR btrim(p_ville) = ''
        OR e.adresse_ville ILIKE '%' || btrim(p_ville) || '%'
        OR e.adresse_code_postal LIKE btrim(p_ville) || '%'
      )
  ), counted AS (
    SELECT count(*)::bigint AS cnt FROM filtered
  )
  SELECT
    f.id,
    f.intitule,
    f.profession_requise,
    f.ville,
    f.code_postal,
    f.debut_le,
    f.fin_le,
    f.taux_horaire_base,
    f.est_urgente,
    c.cnt AS total_count
  FROM filtered f
  CROSS JOIN counted c
  ORDER BY f.est_urgente DESC, f.debut_le ASC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_recherche(text, text) TO anon, authenticated;

-- 2) Pool urgence : supprimer la version cassée qui référence des colonnes inexistantes puis recréer une version cohérente avec le schéma réel
DROP FUNCTION IF EXISTS public.fn_pool_urgence_etablissement();
DROP FUNCTION IF EXISTS public.fn_pool_urgence_etablissement(uuid);

CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(
  p_etablissement_id uuid
)
RETURNS TABLE(
  soignant_id uuid,
  prenom text,
  nom text,
  profession text,
  score_fiabilite integer,
  pool_urgence_rayon_km integer,
  distance_km numeric,
  missions_urgence_terminees bigint,
  en_mission_maintenant boolean,
  derniere_mission_chez_nous timestamptz,
  bio text,
  avatar_url text,
  est_favori boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_etab RECORD;
BEGIN
  SELECT e.id, e.adresse_lat, e.adresse_lng
  INTO v_etab
  FROM public.etablissements e
  WHERE e.id = p_etablissement_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.id AS soignant_id,
    s.prenom::text,
    s.nom::text,
    s.profession::text,
    COALESCE(s.score_fiabilite, 0)::integer AS score_fiabilite,
    COALESCE(s.urgence_rayon_km, 15)::integer AS pool_urgence_rayon_km,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        round((6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
            cos(radians(s.adresse_lng) - radians(v_etab.adresse_lng)) +
            sin(radians(v_etab.adresse_lat)) * sin(radians(s.adresse_lat))
          ))
        ))::numeric, 1)
      ELSE NULL
    END AS distance_km,
    (
      SELECT count(*)::bigint
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND COALESCE(m.est_urgente, false) = true
        AND m.statut = 'TERMINEE'
    ) AS missions_urgence_terminees,
    EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND m.statut = 'EN_COURS'
        AND now() BETWEEN m.debut_le AND m.fin_le
    ) AS en_mission_maintenant,
    (
      SELECT max(m2.fin_le)
      FROM public.missions m2
      WHERE m2.soignant_assigne_id = s.id
        AND m2.etablissement_id = p_etablissement_id
        AND m2.statut = 'TERMINEE'
    ) AS derniere_mission_chez_nous,
    s.bio::text,
    s.avatar_url::text,
    EXISTS (
      SELECT 1
      FROM public.favoris f
      WHERE f.soignant_id = s.id
        AND f.etablissement_id = p_etablissement_id
    ) AS est_favori
  FROM public.soignants s
  WHERE COALESCE(s.disponible_urgence, false) = true
    AND s.supprime_le IS NULL
    AND NOT public.fn_est_exclu(s.id, p_etablissement_id)
    AND (
      s.profession IN (
        SELECT DISTINCT m.profession_requise
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE')
      )
      OR NOT EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE')
      )
    )
  ORDER BY score_fiabilite DESC, distance_km NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_pool_urgence_etablissement(uuid) TO authenticated;

-- 3) Recherche de remplaçants urgence : réaligner avec les vraies colonnes soignant
DROP FUNCTION IF EXISTS public.fn_soignants_urgence(uuid);

CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(
  p_mission_id uuid
)
RETURNS TABLE(
  soignant_id uuid,
  prenom text,
  nom text,
  score_fiabilite integer,
  distance_km numeric,
  pool_urgence_rayon_km integer,
  telephone text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mission RECORD;
BEGIN
  SELECT m.id, m.profession_requise, e.id AS etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
  INTO v_mission
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.id = p_mission_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.id AS soignant_id,
    s.prenom::text,
    s.nom::text,
    COALESCE(s.score_fiabilite, 0)::integer AS score_fiabilite,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_mission.etab_lat IS NOT NULL
       AND v_mission.etab_lng IS NOT NULL THEN
        round((6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(v_mission.etab_lat)) * cos(radians(s.adresse_lat)) *
            cos(radians(s.adresse_lng) - radians(v_mission.etab_lng)) +
            sin(radians(v_mission.etab_lat)) * sin(radians(s.adresse_lat))
          ))
        ))::numeric, 1)
      ELSE NULL
    END AS distance_km,
    COALESCE(s.urgence_rayon_km, 15)::integer AS pool_urgence_rayon_km,
    s.telephone::text
  FROM public.soignants s
  WHERE COALESCE(s.disponible_urgence, false) = true
    AND s.supprime_le IS NULL
    AND s.profession = v_mission.profession_requise
    AND NOT public.fn_est_exclu(s.id, v_mission.etablissement_id)
    AND NOT EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND m.statut = 'EN_COURS'
        AND now() BETWEEN m.debut_le AND m.fin_le
    )
  ORDER BY score_fiabilite DESC, distance_km NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_soignants_urgence(uuid) TO authenticated;

-- 4) Chat mission : autoriser les messages aussi sur ABSENCE / LITIGE, et retirer le trigger dupliqué
DROP POLICY IF EXISTS pol_msg_insert ON public.messages_mission;
CREATE POLICY pol_msg_insert
ON public.messages_mission
FOR INSERT
TO authenticated
WITH CHECK (
  auteur_id = auth.uid()
  AND (
    est_admin()
    OR mission_id IN (
      SELECT m.id
      FROM public.missions m
      WHERE (
        (m.soignant_assigne_id = auth.uid())
        OR (m.etablissement_id = mon_etablissement_id())
      )
      AND m.statut = ANY (ARRAY['ASSIGNEE'::public.statut_mission, 'EN_COURS'::public.statut_mission, 'TERMINEE'::public.statut_mission, 'ABSENCE'::public.statut_mission, 'LITIGE'::public.statut_mission])
    )
  )
);

DROP TRIGGER IF EXISTS dec_notif_message ON public.messages_mission;
DROP TRIGGER IF EXISTS trg_notifier_nouveau_message ON public.messages_mission;
CREATE TRIGGER trg_notifier_nouveau_message
AFTER INSERT ON public.messages_mission
FOR EACH ROW
EXECUTE FUNCTION public.dec_notifier_nouveau_message();