-- Le chat soignant résolvait uniquement raw_app_meta_data.etablissement_id.
-- Les comptes historiques (auth.users.id = etablissements.id) et les membres
-- du modèle d'équipe actuel obtenaient donc NULL malgré une mission autorisée.

CREATE OR REPLACE FUNCTION public.fn_user_id_pour_etablissement(
  p_etablissement_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_user_id uuid;
  v_caller uuid := auth.uid();
  v_autorise boolean;
BEGIN
  IF v_caller IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  v_autorise :=
       public.est_admin()
    OR (
      public.mon_etablissement_id() IS NOT NULL
      AND p_etablissement_id = public.mon_etablissement_id()
    )
    OR EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.etablissement_id = p_etablissement_id
        AND m.soignant_assigne_id = v_caller
    )
    OR EXISTS (
      SELECT 1
      FROM public.candidatures c
      JOIN public.missions m ON m.id = c.mission_id
      WHERE m.etablissement_id = p_etablissement_id
        AND c.soignant_id = v_caller
    );

  IF NOT COALESCE(v_autorise, false) THEN
    RAISE EXCEPTION 'Non autorisé' USING ERRCODE = '42501';
  END IF;

  -- Source canonique : membre actif. Les responsables opérationnels sont
  -- prioritaires afin qu'une conversation établissement reste déterministe.
  SELECT candidat.user_id
  INTO v_user_id
  FROM (
    SELECT
      m.user_id,
      CASE m.role
        WHEN 'PROPRIETAIRE' THEN 1
        WHEN 'ADMIN_GROUPE' THEN 2
        WHEN 'RH' THEN 3
        WHEN 'POINTAGE_ONLY' THEN 4
        ELSE 5
      END AS priorite
    FROM public.membres_etablissement m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    JOIN auth.users u ON u.id = m.user_id
    WHERE m.etablissement_id = p_etablissement_id
      AND m.actif IS TRUE
      AND e.supprime_le IS NULL
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())

    UNION ALL

    -- Compatibilité historique : compte Auth et établissement partagent l'ID.
    SELECT u.id, 10
    FROM auth.users u
    JOIN public.etablissements e ON e.id = u.id
    WHERE u.id = p_etablissement_id
      AND e.supprime_le IS NULL
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND u.raw_app_meta_data ->> 'role' IN (
        'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
      )

    UNION ALL

    -- Compatibilité des comptes plus récents encore portés uniquement par la
    -- métadonnée serveur. Comparaison textuelle : aucune valeur malformée ne
    -- peut provoquer un cast UUID en erreur.
    SELECT u.id, 20
    FROM auth.users u
    JOIN public.etablissements e ON e.id = p_etablissement_id
    WHERE u.raw_app_meta_data ->> 'etablissement_id' = p_etablissement_id::text
      AND e.supprime_le IS NULL
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND u.raw_app_meta_data ->> 'role' IN (
        'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
      )
  ) AS candidat
  ORDER BY candidat.priorite, candidat.user_id
  LIMIT 1;

  RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_user_id_pour_etablissement(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_user_id_pour_etablissement(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_user_id_pour_etablissement(uuid) IS
  'Résout un interlocuteur Auth actif pour un établissement autorisé : membre actif, fallback UUID historique, puis app_metadata serveur.';
