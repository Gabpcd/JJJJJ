-- Les UUID des participants d'une conversation sont des UUID Auth. Pour un
-- établissement, cet UUID est donc différent de public.etablissements.id.
-- Depuis le durcissement RLS P0, le client ne peut (à raison) plus lire les
-- profils complets d'un tiers pour retrouver son libellé.
--
-- Cette projection ne renvoie que les informations nécessaires à l'en-tête de
-- messagerie et seulement pour les conversations auxquelles l'appelant a accès.
CREATE OR REPLACE FUNCTION public.fn_interlocuteurs_conversations(
  p_conversation_ids uuid[]
)
RETURNS TABLE (
  conversation_id uuid,
  participant_id uuid,
  prenom text,
  nom text,
  avatar_url text,
  est_jolene boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifie' USING ERRCODE = '28000';
  END IF;

  IF NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Compte inactif' USING ERRCODE = '42501';
  END IF;

  IF COALESCE(cardinality(p_conversation_ids), 0) = 0 THEN
    RETURN;
  END IF;

  IF cardinality(p_conversation_ids) > 100 THEN
    RAISE EXCEPTION 'Trop de conversations demandees' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH conversations_autorisees AS (
    SELECT
      c.id,
      c.mission_id,
      c.participant_1_id,
      c.participant_2_id
    FROM public.conversations c
    WHERE c.id = ANY (p_conversation_ids)
      AND (
        c.participant_1_id = v_uid
        OR c.participant_2_id = v_uid
        OR public.est_admin()
      )
  ), participants AS (
    SELECT
      c.id AS conversation_id,
      c.mission_id,
      p.participant_id
    FROM conversations_autorisees c
    CROSS JOIN LATERAL (
      VALUES (c.participant_1_id), (c.participant_2_id)
    ) AS p(participant_id)
  )
  SELECT
    p.conversation_id,
    p.participant_id,
    CASE
      WHEN s.id IS NOT NULL THEN s.prenom
      WHEN e.id IS NOT NULL THEN e.nom
      ELSE 'Jolene'
    END::text AS prenom,
    CASE WHEN s.id IS NOT NULL THEN s.nom ELSE '' END::text AS nom,
    CASE WHEN s.id IS NOT NULL THEN s.avatar_url ELSE e.logo_url END::text AS avatar_url,
    (s.id IS NULL AND e.id IS NULL) AS est_jolene
  FROM participants p
  LEFT JOIN public.soignants s
    ON s.id = p.participant_id
   AND s.supprime_le IS NULL
  LEFT JOIN LATERAL (
    SELECT e0.id, e0.nom, e0.logo_url
    FROM public.etablissements e0
    WHERE s.id IS NULL
      AND e0.supprime_le IS NULL
      AND (
        -- Compatibilité avec les premiers comptes établissement, pour
        -- lesquels l'UUID Auth et l'UUID métier étaient identiques.
        e0.id = p.participant_id
        OR EXISTS (
          SELECT 1
          FROM public.membres_etablissement me
          WHERE me.user_id = p.participant_id
            AND me.etablissement_id = e0.id
            AND me.actif
        )
        OR EXISTS (
          SELECT 1
          FROM auth.users u
          WHERE u.id = p.participant_id
            AND CASE
              WHEN (u.raw_app_meta_data ->> 'etablissement_id')
                ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
              THEN (u.raw_app_meta_data ->> 'etablissement_id')::uuid
              ELSE NULL
            END = e0.id
        )
      )
    ORDER BY
      CASE WHEN e0.id = (
        SELECT m.etablissement_id
        FROM public.missions m
        WHERE m.id = p.mission_id
      ) THEN 0 ELSE 1 END,
      e0.id
    LIMIT 1
  ) e ON true
  ORDER BY p.conversation_id, p.participant_id;
END;
$$;

COMMENT ON FUNCTION public.fn_interlocuteurs_conversations(uuid[]) IS
  'Projection messagerie nom/avatar des seuls participants de conversations accessibles a l appelant.';

REVOKE ALL ON FUNCTION public.fn_interlocuteurs_conversations(uuid[]) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_interlocuteurs_conversations(uuid[]) TO authenticated;
