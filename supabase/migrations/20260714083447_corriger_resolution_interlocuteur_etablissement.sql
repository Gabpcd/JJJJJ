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
  IF v_caller IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  v_autorise :=
       public.est_admin()
    -- L'appartenance est bornée à la cible, y compris pour un compte membre de
    -- plusieurs établissements. mon_etablissement_id() ne renvoie qu'une
    -- appartenance prioritaire et refusait donc à tort les suivantes.
    OR EXISTS (
      SELECT 1
      FROM public.membres_etablissement me
      JOIN public.etablissements e ON e.id = me.etablissement_id
      WHERE me.user_id = v_caller
        AND me.etablissement_id = p_etablissement_id
        AND me.actif IS TRUE
        AND e.supprime_le IS NULL
    )
    -- Compatibilité du compte historique (UUID Auth = UUID établissement),
    -- seulement s'il n'existe aucune appartenance canonique cible. Une ligne
    -- inactive représente une révocation explicite et interdit ce fallback.
    OR (
      v_caller = p_etablissement_id
      AND EXISTS (
        SELECT 1
        FROM auth.users u
        JOIN public.etablissements e ON e.id = u.id
        WHERE u.id = v_caller
          AND e.supprime_le IS NULL
          AND u.raw_app_meta_data ->> 'role' IN (
            'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
          )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.membres_etablissement me
        WHERE me.user_id = v_caller
          AND me.etablissement_id = p_etablissement_id
      )
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
        AND c.statut = 'ACCEPTEE'
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
      AND m.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
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
      AND NOT EXISTS (
        SELECT 1
        FROM public.membres_etablissement me
        WHERE me.user_id = u.id
          AND me.etablissement_id = p_etablissement_id
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
      -- Ce fallback est réservé aux comptes réellement portés uniquement par
      -- la métadonnée. Toute appartenance canonique, active ou révoquée,
      -- neutralise une métadonnée potentiellement obsolète.
      AND NOT EXISTS (
        SELECT 1
        FROM public.membres_etablissement me
        WHERE me.user_id = u.id
      )
  ) AS candidat
  ORDER BY candidat.priorite, candidat.user_id
  LIMIT 1;

  RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_user_id_pour_etablissement(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_user_id_pour_etablissement(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_user_id_pour_etablissement(uuid) IS
  'Résout un interlocuteur Auth actif pour un établissement autorisé : membre actif, fallback UUID historique, puis app_metadata serveur.';
