-- Ferme le BOLA historique de la messagerie : fn_obtenir_conversation ne
-- validait plus aucune relation dès qu'un mission_id était fourni, tandis que
-- les ACL permettaient encore INSERT/UPDATE direct sur les conversations.

CREATE OR REPLACE FUNCTION private.fn_interlocuteur_operationnel_actif(
  p_user_id uuid,
  p_etablissement_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    JOIN public.etablissements e ON e.id = p_etablissement_id
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
      AND e.supprime_le IS NULL
      AND (
        EXISTS (
          SELECT 1
          FROM public.membres_etablissement me
          WHERE me.user_id = u.id
            AND me.etablissement_id = e.id
            AND me.actif IS TRUE
            AND me.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
        )
        OR (
          u.id = e.id
          AND u.raw_app_meta_data ->> 'role' IN (
            'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.membres_etablissement me
            WHERE me.user_id = u.id
              AND me.etablissement_id = e.id
          )
        )
        OR (
          u.raw_app_meta_data ->> 'etablissement_id' = e.id::text
          AND u.raw_app_meta_data ->> 'role' IN (
            'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.membres_etablissement me
            WHERE me.user_id = u.id
          )
        )
      )
  ), false);
$function$;

-- La RPC publique conserve son contrôle d'autorisation, puis délègue la
-- sélection à la source interne unique utilisée aussi par les triggers.
CREATE OR REPLACE FUNCTION public.fn_user_id_pour_etablissement(
  p_etablissement_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_autorise boolean;
BEGIN
  IF v_caller IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  v_autorise :=
       public.est_admin()
    OR EXISTS (
      SELECT 1
      FROM public.membres_etablissement me
      JOIN public.etablissements e ON e.id = me.etablissement_id
      WHERE me.user_id = v_caller
        AND me.etablissement_id = p_etablissement_id
        AND me.actif IS TRUE
        AND e.supprime_le IS NULL
    )
    OR (
      v_caller = p_etablissement_id
      AND EXISTS (
        SELECT 1
        FROM auth.users u
        JOIN public.etablissements e ON e.id = u.id
        WHERE u.id = v_caller
          AND e.supprime_le IS NULL
          AND u.deleted_at IS NULL
          AND u.email_confirmed_at IS NOT NULL
          AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
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

  IF COALESCE(v_autorise, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Non autorisé' USING ERRCODE = '42501';
  END IF;

  RETURN private.fn_interlocuteur_operationnel_id(p_etablissement_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_user_id_pour_etablissement(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_user_id_pour_etablissement(uuid)
  TO authenticated, service_role;

-- Résolution interne déterministe pour les triggers système. Contrairement à
-- la RPC publique, elle ne dépend pas de auth.uid(), mais applique exactement
-- les mêmes critères d'activité et neutralise les fallbacks historiques dès
-- qu'une appartenance canonique (même révoquée) existe.
CREATE OR REPLACE FUNCTION private.fn_interlocuteur_operationnel_id(
  p_etablissement_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT candidat.user_id
  FROM (
    SELECT
      me.user_id,
      CASE me.role
        WHEN 'PROPRIETAIRE' THEN 1
        WHEN 'ADMIN_GROUPE' THEN 2
        WHEN 'RH' THEN 3
        ELSE 9
      END AS priorite
    FROM public.membres_etablissement me
    JOIN public.etablissements e ON e.id = me.etablissement_id
    JOIN auth.users u ON u.id = me.user_id
    WHERE me.etablissement_id = p_etablissement_id
      AND me.actif IS TRUE
      AND me.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
      AND e.supprime_le IS NULL
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())

    UNION ALL

    SELECT u.id, 10
    FROM auth.users u
    JOIN public.etablissements e ON e.id = u.id
    WHERE u.id = p_etablissement_id
      AND e.supprime_le IS NULL
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
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

    SELECT u.id, 20
    FROM auth.users u
    JOIN public.etablissements e ON e.id = p_etablissement_id
    WHERE u.raw_app_meta_data ->> 'etablissement_id' =
          p_etablissement_id::text
      AND e.supprime_le IS NULL
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
      AND u.raw_app_meta_data ->> 'role' IN (
        'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.membres_etablissement me
        WHERE me.user_id = u.id
      )
  ) AS candidat
  ORDER BY candidat.priorite, candidat.user_id
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION private.fn_soignant_messagerie_actif(
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    JOIN public.soignants s ON s.id = u.id
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
      AND s.supprime_le IS NULL
      AND s.statut_compte = 'ACTIF'
  ), false);
$function$;

CREATE OR REPLACE FUNCTION private.fn_soignant_lie_mission(
  p_soignant_id uuid,
  p_mission_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM public.missions mi
    WHERE mi.id = p_mission_id
      AND (
        mi.soignant_assigne_id = p_soignant_id
        OR EXISTS (
          SELECT 1
          FROM public.candidatures c
          WHERE c.mission_id = mi.id
            AND c.soignant_id = p_soignant_id
            AND c.statut = 'ACCEPTEE'
        )
      )
  ), false);
$function$;

CREATE OR REPLACE FUNCTION private.fn_support_messagerie_actif(
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    JOIN public.equipe_admin ea ON ea.user_id = u.id
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND ea.actif IS TRUE
      AND ARRAY[
        'Dashboard',
        'Utilisateurs',
        'Missions',
        'Litiges & contrats',
        'Finances',
        'Messagerie',
        'Conformité & Technique',
        'Fondateur'
      ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])
  ), false);
$function$;

CREATE OR REPLACE FUNCTION private.fn_soignant_visible_pool(
  p_etablissement_user_id uuid,
  p_soignant_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM public.etablissements e
    JOIN public.soignants s ON s.id = p_soignant_id
    WHERE e.supprime_le IS NULL
      AND private.fn_interlocuteur_operationnel_actif(
        p_etablissement_user_id,
        e.id
      )
      AND private.fn_soignant_messagerie_actif(s.id)
      AND COALESCE(s.disponible_urgence, false) IS TRUE
      AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND NOT public.fn_est_exclu(s.id, e.id)
      AND (
        EXISTS (
          SELECT 1
          FROM public.missions mi
          WHERE mi.etablissement_id = e.id
            AND mi.statut IN (
              'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
            )
            AND public.fn_soignant_compatible_mission(
              s.profession,
              s.specialite_medicale,
              mi.profession_requise,
              mi.specialite_medicale_requise,
              COALESCE(mi.accepte_non_specialises, true)
            )
        )
        OR NOT EXISTS (
          SELECT 1
          FROM public.missions mi
          WHERE mi.etablissement_id = e.id
            AND mi.statut IN (
              'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
            )
        )
      )
  ), false);
$function$;

-- La vue du Pool et l'autorisation d'ouvrir une conversation reposent sur la
-- même compatibilité. La profession demandée par la mission prime donc sur le
-- diplôme du profil (IADE/IBODE vers mission IDE, jamais l'inverse).
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(
  p_etablissement_id uuid
)
RETURNS TABLE (
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
SET search_path TO ''
AS $function$
DECLARE
  v_etab public.etablissements%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;
  IF public.fn_a_permission_etablissement(
       'candidatures', p_etablissement_id
     ) IS NOT TRUE THEN
    RAISE EXCEPTION
      'Accès refusé : pool urgence réservé aux responsables de l’établissement'
      USING ERRCODE = '42501';
  END IF;

  SELECT e.* INTO v_etab
  FROM public.etablissements e
  WHERE e.id = p_etablissement_id
    AND e.supprime_le IS NULL;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.prenom::text,
    s.nom::text,
    s.profession::text,
    CASE
      WHEN COALESCE(s.total_missions_terminees, 0) >= 3
      THEN s.score_fiabilite::integer
      ELSE NULL
    END,
    COALESCE(s.urgence_rayon_km, 15)::integer,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        pg_catalog.round((
          6371 * pg_catalog.acos(pg_catalog.least(
            1.0::double precision,
            pg_catalog.greatest(
              (-1.0)::double precision,
              pg_catalog.cos(pg_catalog.radians(v_etab.adresse_lat))
                * pg_catalog.cos(pg_catalog.radians(s.adresse_lat))
                * pg_catalog.cos(
                    pg_catalog.radians(s.adresse_lng)
                    - pg_catalog.radians(v_etab.adresse_lng)
                  )
                + pg_catalog.sin(pg_catalog.radians(v_etab.adresse_lat))
                  * pg_catalog.sin(pg_catalog.radians(s.adresse_lat))
            )
          ))
        )::numeric, 1)
      ELSE NULL
    END,
    (
      SELECT pg_catalog.count(*)::bigint
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND COALESCE(m.est_urgente, false) IS TRUE
        AND m.statut = 'TERMINEE'
    ),
    EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.soignant_assigne_id = s.id
        AND m.statut = 'EN_COURS'
        AND pg_catalog.now() BETWEEN m.debut_le AND m.fin_le
    ),
    (
      SELECT pg_catalog.max(m2.fin_le)
      FROM public.missions m2
      WHERE m2.soignant_assigne_id = s.id
        AND m2.etablissement_id = p_etablissement_id
        AND m2.statut = 'TERMINEE'
    ),
    s.bio::text,
    s.avatar_url::text,
    EXISTS (
      SELECT 1
      FROM public.favoris_etab_soignant f
      WHERE f.soignant_id = s.id
        AND f.etablissement_id = p_etablissement_id
    )
  FROM public.soignants s
  WHERE private.fn_soignant_messagerie_actif(s.id)
    AND COALESCE(s.disponible_urgence, false) IS TRUE
    AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND NOT public.fn_est_exclu(s.id, p_etablissement_id)
    AND (
      EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN (
            'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
          )
          AND public.fn_soignant_compatible_mission(
            s.profession,
            s.specialite_medicale,
            m.profession_requise,
            m.specialite_medicale_requise,
            COALESCE(m.accepte_non_specialises, true)
          )
      )
      OR NOT EXISTS (
        SELECT 1
        FROM public.missions m
        WHERE m.etablissement_id = p_etablissement_id
          AND m.statut IN (
            'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'ABSENCE', 'LITIGE'
          )
      )
    )
  ORDER BY
    CASE
      WHEN COALESCE(s.total_missions_terminees, 0) >= 3
      THEN s.score_fiabilite
      ELSE NULL
    END DESC NULLS LAST,
    CASE
      WHEN s.adresse_lat IS NOT NULL
       AND s.adresse_lng IS NOT NULL
       AND v_etab.adresse_lat IS NOT NULL
       AND v_etab.adresse_lng IS NOT NULL THEN
        6371 * pg_catalog.acos(pg_catalog.least(
          1.0::double precision,
          pg_catalog.greatest(
            (-1.0)::double precision,
            pg_catalog.cos(pg_catalog.radians(v_etab.adresse_lat))
              * pg_catalog.cos(pg_catalog.radians(s.adresse_lat))
              * pg_catalog.cos(
                  pg_catalog.radians(s.adresse_lng)
                  - pg_catalog.radians(v_etab.adresse_lng)
                )
              + pg_catalog.sin(pg_catalog.radians(v_etab.adresse_lat))
                * pg_catalog.sin(pg_catalog.radians(s.adresse_lat))
          )
        ))
      ELSE NULL
    END NULLS LAST;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_pool_urgence_etablissement(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_pool_urgence_etablissement(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.fn_pool_urgence_etablissement(uuid) IS
  'Pool réservé aux rôles établissement opérationnels ; filtrage par profession requise de chaque mission, dont IADE/IBODE compatibles avec IDE.';

CREATE OR REPLACE FUNCTION private.fn_relation_messagerie_autorisee(
  p_acteur_id uuid,
  p_autre_id uuid,
  p_mission_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_acteur_id IS NULL
      OR p_autre_id IS NULL
      OR p_acteur_id = p_autre_id THEN false
    WHEN p_mission_id IS NOT NULL THEN EXISTS (
      SELECT 1
      FROM public.missions mi
      WHERE mi.id = p_mission_id
        AND (
          (
            private.fn_soignant_lie_mission(p_acteur_id, mi.id)
            AND private.fn_soignant_messagerie_actif(p_acteur_id)
            AND private.fn_interlocuteur_operationnel_actif(
              p_autre_id,
              mi.etablissement_id
            )
          )
          OR (
            private.fn_soignant_lie_mission(p_autre_id, mi.id)
            AND private.fn_soignant_messagerie_actif(p_autre_id)
            AND private.fn_interlocuteur_operationnel_actif(
              p_acteur_id,
              mi.etablissement_id
            )
          )
          -- Une conversation de modération explicitement créée par un admin
          -- AAL2 reste utilisable par l'endpoint métier ciblé. Le support doit
          -- être l'autre participant actif ; aucun tiers à la mission n'entre.
          OR (
            private.fn_support_messagerie_actif(p_autre_id)
            AND (
              (
                private.fn_soignant_lie_mission(p_acteur_id, mi.id)
                AND private.fn_soignant_messagerie_actif(p_acteur_id)
              )
              OR private.fn_interlocuteur_operationnel_actif(
                p_acteur_id,
                mi.etablissement_id
              )
            )
          )
        )
    )
    ELSE
      EXISTS (
        SELECT 1
        FROM public.missions mi
        WHERE (
          private.fn_soignant_lie_mission(p_acteur_id, mi.id)
          AND private.fn_soignant_messagerie_actif(p_acteur_id)
          AND private.fn_interlocuteur_operationnel_actif(
            p_autre_id,
            mi.etablissement_id
          )
        ) OR (
          private.fn_soignant_lie_mission(p_autre_id, mi.id)
          AND private.fn_soignant_messagerie_actif(p_autre_id)
          AND private.fn_interlocuteur_operationnel_actif(
            p_acteur_id,
            mi.etablissement_id
          )
        )
      )
      OR private.fn_soignant_visible_pool(p_acteur_id, p_autre_id)
      OR private.fn_soignant_visible_pool(p_autre_id, p_acteur_id)
      OR private.fn_support_messagerie_actif(p_autre_id)
  END;
$function$;

REVOKE ALL ON FUNCTION private.fn_interlocuteur_operationnel_actif(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_interlocuteur_operationnel_id(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_soignant_messagerie_actif(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_soignant_lie_mission(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_support_messagerie_actif(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_soignant_visible_pool(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_relation_messagerie_autorisee(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_obtenir_conversation(
  p_autre_id uuid,
  p_mission_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_conv_id uuid;
  v_mon_id uuid := auth.uid();
  v_autorise boolean := false;
  v_participant_1 uuid;
  v_participant_2 uuid;
BEGIN
  IF v_mon_id IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  IF p_autre_id IS NULL OR p_autre_id = v_mon_id THEN
    RAISE EXCEPTION 'Interlocuteur invalide' USING ERRCODE = '22023';
  END IF;

  IF public.est_admin() THEN
    IF p_mission_id IS NULL THEN
      v_autorise :=
        private.fn_soignant_messagerie_actif(p_autre_id)
        OR EXISTS (
          SELECT 1
          FROM public.etablissements e
          WHERE private.fn_interlocuteur_operationnel_actif(p_autre_id, e.id)
        );
    ELSE
      SELECT EXISTS (
        SELECT 1
        FROM public.missions mi
        WHERE mi.id = p_mission_id
          AND (
            (
              private.fn_soignant_lie_mission(p_autre_id, mi.id)
              AND private.fn_soignant_messagerie_actif(p_autre_id)
            )
            OR private.fn_interlocuteur_operationnel_actif(
              p_autre_id,
              mi.etablissement_id
            )
          )
      ) INTO v_autorise;
    END IF;
  ELSE
    v_autorise := private.fn_relation_messagerie_autorisee(
      v_mon_id,
      p_autre_id,
      p_mission_id
    );
  END IF;

  IF v_autorise IS NOT TRUE THEN
    RAISE EXCEPTION 'Conversation non autorisée' USING ERRCODE = '42501';
  END IF;

  v_participant_1 := LEAST(v_mon_id, p_autre_id);
  v_participant_2 := GREATEST(v_mon_id, p_autre_id);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_participant_1::text || ':' || v_participant_2::text || ':' ||
      COALESCE(p_mission_id::text, 'sans-mission'),
      0
    )
  );

  SELECT c.id
  INTO v_conv_id
  FROM public.conversations c
  WHERE (
      (c.participant_1_id = v_mon_id AND c.participant_2_id = p_autre_id)
      OR (c.participant_1_id = p_autre_id AND c.participant_2_id = v_mon_id)
    )
    AND (
      (p_mission_id IS NOT NULL AND c.mission_id = p_mission_id)
      OR (p_mission_id IS NULL AND c.mission_id IS NULL)
    )
  ORDER BY
    CASE WHEN c.mission_id IS NULL THEN 0 ELSE 1 END,
    c.dernier_message_le DESC NULLS LAST,
    c.cree_le DESC NULLS LAST,
    c.id
  LIMIT 1;

  IF v_conv_id IS NULL THEN
    INSERT INTO public.conversations (
      participant_1_id,
      participant_2_id,
      mission_id
    ) VALUES (
      v_participant_1,
      v_participant_2,
      p_mission_id
    )
    RETURNING id INTO v_conv_id;
  END IF;

  RETURN v_conv_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_obtenir_conversation(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_obtenir_conversation(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.fn_obtenir_conversation(uuid, uuid) IS
  'Crée ou retrouve une conversation après validation de la relation mission, match accepté ou Pool Urgence ; admin AAL2 borné aux endpoints de mission.';

-- Les deux triggers historiques d'attribution convergeaient vers des modèles
-- différents : l'un utilisait à tort l'UUID de l'établissement comme UUID
-- Auth, l'autre ne cherchait qu'un propriétaire. Ce chemin système unique
-- résout un contact opérationnel actif et reste idempotent sous concurrence.
CREATE OR REPLACE FUNCTION public.fn_creer_conversation_si_absente(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_etablissement_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_etab_id uuid;
  v_conv_id uuid;
  v_participant_1 uuid;
  v_participant_2 uuid;
  v_raison text;
  v_intitule text;
BEGIN
  IF p_mission_id IS NULL
     OR p_soignant_id IS NULL
     OR p_etablissement_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT mi.intitule
  INTO v_intitule
  FROM public.missions mi
  WHERE mi.id = p_mission_id
    AND mi.etablissement_id = p_etablissement_id
    AND mi.soignant_assigne_id = p_soignant_id;
  IF NOT FOUND THEN
    v_raison := 'relation_mission_invalide';
  ELSIF private.fn_soignant_messagerie_actif(p_soignant_id) IS NOT TRUE THEN
    v_raison := 'soignant_inactif';
  ELSE
    v_user_etab_id :=
      private.fn_interlocuteur_operationnel_id(p_etablissement_id);
    IF v_user_etab_id IS NULL THEN
      v_raison := 'interlocuteur_etablissement_introuvable';
    END IF;
  END IF;

  IF v_raison IS NOT NULL THEN
    BEGIN
      INSERT INTO public.journaux_audit (
        acteur_id,
        type_acteur,
        action,
        type_ressource,
        id_ressource,
        details
      ) VALUES (
        '00000000-0000-0000-0000-000000000000'::uuid,
        'SYSTEME',
        'SYSTEM',
        'conversations',
        NULL,
        pg_catalog.jsonb_build_object(
          'evenement', 'MESSAGERIE_CREATION_CONVERSATION_ECHEC',
          'raison', v_raison,
          'mission_id', p_mission_id,
          'soignant_id', p_soignant_id,
          'etablissement_id', p_etablissement_id
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN NULL;
  END IF;

  v_participant_1 := LEAST(p_soignant_id, v_user_etab_id);
  v_participant_2 := GREATEST(p_soignant_id, v_user_etab_id);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_participant_1::text || ':' || v_participant_2::text || ':' ||
      p_mission_id::text,
      0
    )
  );

  SELECT c.id
  INTO v_conv_id
  FROM public.conversations c
  WHERE c.mission_id = p_mission_id
    AND (
      (
        c.participant_1_id = p_soignant_id
        AND c.participant_2_id = v_user_etab_id
      )
      OR (
        c.participant_1_id = v_user_etab_id
        AND c.participant_2_id = p_soignant_id
      )
    )
  ORDER BY c.cree_le, c.id
  LIMIT 1;

  IF v_conv_id IS NULL THEN
    INSERT INTO public.conversations (
      mission_id,
      participant_1_id,
      participant_2_id,
      cree_le,
      dernier_message_le
    ) VALUES (
      p_mission_id,
      v_participant_1,
      v_participant_2,
      pg_catalog.now(),
      pg_catalog.now()
    )
    RETURNING id INTO v_conv_id;

    INSERT INTO public.messages_chat (
      conversation_id,
      auteur_id,
      contenu,
      est_admin
    ) VALUES (
      v_conv_id,
      '00000000-0000-0000-0000-000000000000'::uuid,
      '📋 Mission "' || COALESCE(v_intitule, 'Mission') ||
        '" assignée. Vous pouvez échanger ici pour coordonner les détails.',
      true
    );

    BEGIN
      INSERT INTO public.journaux_audit (
        acteur_id,
        type_acteur,
        action,
        type_ressource,
        id_ressource,
        details
      ) VALUES (
        p_soignant_id,
        'SYSTEME',
        'SYSTEM',
        'conversations',
        v_conv_id,
        pg_catalog.jsonb_build_object(
          'evenement', 'MESSAGERIE_CONVERSATION_OUVERTE',
          'origine', 'ATTRIBUTION_MISSION',
          'mission_id', p_mission_id,
          'soignant_id', p_soignant_id,
          'etablissement_id', p_etablissement_id,
          'user_etab_id', v_user_etab_id
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN v_conv_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_creer_conversation_si_absente(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_creer_conversation_si_absente(uuid, uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_creer_conversation_assignation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.statut <> 'ASSIGNEE'
     OR NEW.soignant_assigne_id IS NULL
     OR (
       OLD.statut = 'ASSIGNEE'
       AND OLD.soignant_assigne_id = NEW.soignant_assigne_id
     ) THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM public.fn_creer_conversation_si_absente(
      NEW.id,
      NEW.soignant_assigne_id,
      NEW.etablissement_id
    );
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.journaux_audit (
        acteur_id,
        type_acteur,
        action,
        type_ressource,
        id_ressource,
        details
      ) VALUES (
        '00000000-0000-0000-0000-000000000000'::uuid,
        'SYSTEME',
        'SYSTEM',
        'missions',
        NEW.id,
        pg_catalog.jsonb_build_object(
          'evenement', 'MESSAGERIE_TRIGGER_ASSIGNATION_ECHEC',
          'sql_state', SQLSTATE,
          'sql_errm', SQLERRM,
          'mission_id', NEW.id,
          'soignant_id', NEW.soignant_assigne_id,
          'etablissement_id', NEW.etablissement_id
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_creer_conversation_assignation()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.dec_creer_conversation_assignation()
  TO service_role;

-- Le second trigger est conservé comme retry idempotent après l'acceptation de
-- candidature. Son journal d'erreur ne doit jamais annuler l'acceptation.
CREATE OR REPLACE FUNCTION public.tg_candidature_acceptee_creer_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_etab_id uuid;
BEGIN
  SELECT m.etablissement_id INTO v_etab_id
  FROM public.missions m
  WHERE m.id = NEW.mission_id;
  IF v_etab_id IS NULL THEN RETURN NEW; END IF;

  BEGIN
    PERFORM public.fn_creer_conversation_si_absente(
      NEW.mission_id,
      NEW.soignant_id,
      v_etab_id
    );
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.journaux_audit (
        acteur_id,
        type_acteur,
        action,
        type_ressource,
        id_ressource,
        details
      ) VALUES (
        '00000000-0000-0000-0000-000000000000'::uuid,
        'SYSTEME',
        'SYSTEM',
        'candidatures',
        NEW.id,
        pg_catalog.jsonb_build_object(
          'evenement', 'MESSAGERIE_TRIGGER_ECHEC',
          'sql_state', SQLSTATE,
          'sql_errm', SQLERRM,
          'mission_id', NEW.mission_id,
          'soignant_id', NEW.soignant_id
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.tg_candidature_acceptee_creer_conversation()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tg_candidature_acceptee_creer_conversation()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_conversation_accessible(
  p_conversation_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_conv public.conversations%ROWTYPE;
  v_autre uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN false;
  END IF;
  IF public.est_admin() THEN
    RETURN EXISTS (
      SELECT 1 FROM public.conversations c WHERE c.id = p_conversation_id
    );
  END IF;

  SELECT c.* INTO v_conv
  FROM public.conversations c
  WHERE c.id = p_conversation_id;
  IF NOT FOUND THEN RETURN false; END IF;

  IF v_uid = v_conv.participant_1_id THEN
    v_autre := v_conv.participant_2_id;
  ELSIF v_uid = v_conv.participant_2_id THEN
    v_autre := v_conv.participant_1_id;
  ELSE
    RETURN false;
  END IF;

  RETURN private.fn_relation_messagerie_autorisee(
    v_uid,
    v_autre,
    v_conv.mission_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_conversation_accessible(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_conversation_accessible(uuid)
  TO authenticated;

-- Le canal support reste une exception explicite, créée uniquement vers un
-- administrateur actif disposant du groupe Messagerie.
CREATE OR REPLACE FUNCTION public.fn_contacter_support()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_support uuid;
BEGIN
  IF v_me IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  SELECT u.id INTO v_support
  FROM auth.users u
  JOIN public.equipe_admin ea ON ea.user_id = u.id
  WHERE u.id <> v_me
    AND u.deleted_at IS NULL
    AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
    AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
    AND ea.actif IS TRUE
    AND ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])
  ORDER BY (u.email = 'admin@jolene.app') DESC, u.created_at, u.id
  LIMIT 1;
  IF v_support IS NULL THEN
    RAISE EXCEPTION 'Support indisponible pour le moment.'
      USING ERRCODE = '55000';
  END IF;

  -- Délégation au chemin canonique : même verrou que les autres conversations
  -- sans mission et recherche des deux orientations historiques.
  RETURN public.fn_obtenir_conversation(v_support, NULL);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_contacter_support()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_contacter_support()
  TO authenticated;

-- Mutation atomique commune : le contenu exact validé par l'Edge Function est
-- inséré dans la même requête serveur. Elle revalide la relation afin qu'une
-- ancienne ligne BOLA ou un participant révoqué ne puisse jamais envoyer.
CREATE OR REPLACE FUNCTION private.fn_envoyer_message_interne(
  p_conversation_id uuid,
  p_contenu text,
  p_acteur_id uuid,
  p_admin_aal2 boolean DEFAULT false,
  p_detected_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_conv public.conversations%ROWTYPE;
  v_autre uuid;
  v_admin boolean := false;
  v_message_id uuid;
  v_mission_id uuid;
  v_mission_statut text;
BEGIN
  IF p_acteur_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = p_acteur_id
      AND u.deleted_at IS NULL
      AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until <= pg_catalog.now())
  ) THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Non authentifié');
  END IF;
  IF p_contenu IS NULL OR pg_catalog.length(pg_catalog.btrim(p_contenu)) < 1 THEN
    RETURN pg_catalog.jsonb_build_object(
      'error',
      'Le message ne peut pas être vide.'
    );
  END IF;
  IF pg_catalog.length(p_contenu) > 4000 THEN
    RETURN pg_catalog.jsonb_build_object(
      'error',
      'Le message est trop long (4000 caractères max).'
    );
  END IF;

  IF p_detected_type IS NOT NULL
     AND p_detected_type NOT IN (
       'TELEPHONE', 'EMAIL', 'URL', 'HANDLE', 'KEYWORD'
     ) THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Type de détection invalide');
  END IF;

  -- L'ordre de verrouillage suit les transitions métier (mission puis
  -- conversation) afin d'éviter un deadlock avec leurs triggers. Le premier
  -- SELECT ne donne aucune information au client : toute erreur reste réduite
  -- au même résultat métier après le verrou de conversation.
  IF p_detected_type IS NOT NULL THEN
    SELECT c.mission_id INTO v_mission_id
    FROM public.conversations c
    WHERE c.id = p_conversation_id;

    IF v_mission_id IS NOT NULL THEN
      SELECT mi.statut::text INTO v_mission_statut
      FROM public.missions mi
      WHERE mi.id = v_mission_id
      FOR SHARE;
    END IF;
  END IF;

  SELECT c.* INTO v_conv
  FROM public.conversations c
  WHERE c.id = p_conversation_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Conversation introuvable');
  END IF;
  IF v_conv.archived_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'error',
      'Cette conversation est archivée.'
    );
  END IF;

  v_admin := COALESCE(p_admin_aal2, false)
    AND private.fn_support_messagerie_actif(p_acteur_id);
  IF p_acteur_id = v_conv.participant_1_id THEN
    v_autre := v_conv.participant_2_id;
  ELSIF p_acteur_id = v_conv.participant_2_id THEN
    v_autre := v_conv.participant_1_id;
  ELSIF NOT v_admin THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF NOT v_admin
     AND private.fn_relation_messagerie_autorisee(
       p_acteur_id,
       v_autre,
       v_conv.mission_id
     ) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_autre IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.utilisateurs_bloques b
    WHERE (b.bloqueur_id = p_acteur_id AND b.bloque_id = v_autre)
       OR (b.bloqueur_id = v_autre AND b.bloque_id = p_acteur_id)
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'error',
      'Vous ne pouvez plus échanger avec cet utilisateur (blocage actif).'
    );
  END IF;

  -- L'Edge peut autoriser des coordonnées après confirmation, mais le statut
  -- est revalidé ici, après la relation et le blocage puis juste avant
  -- l'INSERT, afin de fermer le TOCTOU sans créer d'oracle BOLA.
  IF p_detected_type IS NOT NULL
     AND (
       v_conv.mission_id IS DISTINCT FROM v_mission_id
       OR COALESCE(
         v_mission_statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE'),
         false
       ) IS NOT TRUE
     ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'error',
      'ANTI_LEAK_REFUSE',
      'detected_type',
      p_detected_type
    );
  END IF;

  INSERT INTO public.messages_chat (
    conversation_id,
    auteur_id,
    contenu,
    est_admin
  ) VALUES (
    p_conversation_id,
    p_acteur_id,
    p_contenu,
    v_admin
  )
  RETURNING id INTO v_message_id;

  UPDATE public.conversations
  SET dernier_message_le = pg_catalog.now()
  WHERE id = p_conversation_id;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'message_id', v_message_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_envoyer_message_interne(
  uuid, text, uuid, boolean, text
) FROM PUBLIC, anon, authenticated, service_role;

-- Signature historique conservée uniquement pour les tests SQL propriétaires
-- et les appels internes. Aucun JWT client ni service_role ne peut l'exécuter :
-- l'anti-fuite Edge n'est donc plus contournable par un RPC direct.
CREATE OR REPLACE FUNCTION public.fn_envoyer_message(
  p_conversation_id uuid,
  p_contenu text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Non authentifié');
  END IF;
  RETURN private.fn_envoyer_message_interne(
    p_conversation_id,
    p_contenu,
    v_uid,
    public.est_admin(),
    NULL
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_message(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_envoyer_message_valide(
  p_conversation_id uuid,
  p_contenu text,
  p_acteur_id uuid,
  p_admin_aal2 boolean DEFAULT false,
  p_detected_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT private.fn_envoyer_message_interne(
    p_conversation_id,
    p_contenu,
    p_acteur_id,
    p_admin_aal2,
    p_detected_type
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_message_valide(
  uuid, text, uuid, boolean, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_message_valide(
  uuid, text, uuid, boolean, text
) TO service_role;

COMMENT ON FUNCTION public.fn_envoyer_message_valide(
  uuid, text, uuid, boolean, text
) IS
  'Insertion atomique réservée à messagerie-validate après contrôle anti-fuite du contenu exact.';

-- Les clients n'écrivent plus directement dans les deux tables sensibles.
-- Les RPC et triggers SECURITY DEFINER restent les seules voies de mutation.
DROP POLICY IF EXISTS pol_conv_insert ON public.conversations;
DROP POLICY IF EXISTS pol_conv_update ON public.conversations;
REVOKE INSERT, UPDATE ON TABLE public.conversations
  FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS pol_msg_chat_insert ON public.messages_chat;
DROP POLICY IF EXISTS pol_mchat_update ON public.messages_chat;
REVOKE INSERT, UPDATE ON TABLE public.messages_chat
  FROM PUBLIC, anon, authenticated;

-- La lecture est elle aussi revalidée : un ancien participant révoqué ou une
-- conversation BOLA historique ne reste pas visible par simple possession de
-- son UUID. Le support et les admins AAL2 sont gérés par la fonction.
DROP POLICY IF EXISTS pol_conv_select ON public.conversations;
CREATE POLICY pol_conv_select
  ON public.conversations
  FOR SELECT
  TO authenticated
  USING (public.fn_conversation_accessible(id));

DROP POLICY IF EXISTS pol_msg_select ON public.messages_chat;
CREATE POLICY pol_msg_select
  ON public.messages_chat
  FOR SELECT
  TO authenticated
  USING (public.fn_conversation_accessible(conversation_id));

CREATE INDEX IF NOT EXISTS idx_conversations_participant_1_message
  ON public.conversations(participant_1_id, dernier_message_le DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_participant_2_message
  ON public.conversations(participant_2_id, dernier_message_le DESC);
CREATE INDEX IF NOT EXISTS idx_messages_chat_non_lus
  ON public.messages_chat(conversation_id, auteur_id)
  WHERE lu IS FALSE;

-- Le statut de frappe passe exclusivement par deux RPC revalidées. Un ancien
-- participant révoqué ne peut plus écrire directement ni signaler sa présence.
DROP POLICY IF EXISTS pol_typing_status_upsert ON public.typing_status;
DROP POLICY IF EXISTS pol_typing_status_delete ON public.typing_status;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.typing_status
  FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS pol_typing_status_select ON public.typing_status;
CREATE POLICY pol_typing_status_select
  ON public.typing_status
  FOR SELECT
  TO authenticated
  USING (public.fn_conversation_accessible(conversation_id));

CREATE OR REPLACE FUNCTION public.fn_typing_start(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'NON_AUTHENTIFIE' USING ERRCODE = '28000';
  END IF;
  IF public.fn_conversation_accessible(p_conversation_id) IS NOT TRUE
     OR NOT EXISTS (
       SELECT 1
       FROM public.conversations c
       WHERE c.id = p_conversation_id
         AND c.archived_at IS NULL
         AND v_uid IN (c.participant_1_id, c.participant_2_id)
     ) THEN
    RAISE EXCEPTION 'NON_AUTORISE' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.typing_status(conversation_id, user_id, started_at)
  VALUES (p_conversation_id, v_uid, pg_catalog.now())
  ON CONFLICT (conversation_id, user_id) DO UPDATE
    SET started_at = EXCLUDED.started_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_typing_stop(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'NON_AUTHENTIFIE' USING ERRCODE = '28000';
  END IF;
  IF public.fn_conversation_accessible(p_conversation_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'NON_AUTORISE' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.typing_status
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_typing_start(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_typing_start(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_typing_stop(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_typing_stop(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_marquer_messages_lus(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_conv public.conversations%ROWTYPE;
  v_autre uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  SELECT c.* INTO v_conv
  FROM public.conversations c
  WHERE c.id = p_conversation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  IF v_uid = v_conv.participant_1_id THEN
    v_autre := v_conv.participant_2_id;
  ELSIF v_uid = v_conv.participant_2_id THEN
    v_autre := v_conv.participant_1_id;
  ELSIF public.est_admin() THEN
    -- Un administrateur qui observe une conversation ne doit jamais modifier
    -- l'état de lecture des participants.
    RETURN;
  ELSE
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  IF public.est_admin() IS NOT TRUE
     AND private.fn_relation_messagerie_autorisee(
       v_uid, v_autre, v_conv.mission_id
     ) IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  UPDATE public.messages_chat
  SET lu = true
  WHERE conversation_id = p_conversation_id
    AND auteur_id <> v_uid
    AND lu IS FALSE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_messages_non_lus()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT count(*)::integer
  FROM public.conversations c
  JOIN public.messages_chat mc ON mc.conversation_id = c.id
  WHERE c.archived_at IS NULL
    AND auth.uid() IN (c.participant_1_id, c.participant_2_id)
    AND mc.lu IS FALSE
    AND mc.auteur_id <> auth.uid()
    AND public.fn_conversation_accessible(c.id);
$function$;

REVOKE ALL ON FUNCTION public.fn_marquer_messages_lus(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_marquer_messages_lus(uuid)
  TO authenticated;
REVOKE ALL ON FUNCTION public.fn_messages_non_lus()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_messages_non_lus()
  TO authenticated;

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
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;
  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Compte inactif' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(cardinality(p_conversation_ids), 0) = 0 THEN
    RETURN;
  END IF;
  IF cardinality(p_conversation_ids) > 100 THEN
    RAISE EXCEPTION 'Trop de conversations demandées' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH conversations_autorisees AS (
    SELECT
      c.id,
      c.mission_id,
      c.participant_1_id,
      c.participant_2_id
    FROM public.conversations c
    WHERE c.id = ANY(p_conversation_ids)
      AND public.fn_conversation_accessible(c.id)
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
    CASE WHEN s.id IS NOT NULL THEN s.avatar_url ELSE e.logo_url END::text,
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
        e0.id = p.participant_id
        OR EXISTS (
          SELECT 1
          FROM public.membres_etablissement me
          WHERE me.user_id = p.participant_id
            AND me.etablissement_id = e0.id
            AND me.actif IS TRUE
        )
        OR EXISTS (
          SELECT 1
          FROM auth.users u
          WHERE u.id = p.participant_id
            AND u.raw_app_meta_data ->> 'etablissement_id' = e0.id::text
            AND NOT EXISTS (
              SELECT 1
              FROM public.membres_etablissement me
              WHERE me.user_id = u.id
            )
        )
      )
    ORDER BY
      CASE WHEN e0.id = (
        SELECT mi.etablissement_id
        FROM public.missions mi
        WHERE mi.id = p.mission_id
      ) THEN 0 ELSE 1 END,
      e0.id
    LIMIT 1
  ) e ON true
  ORDER BY p.conversation_id, p.participant_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_interlocuteurs_conversations(uuid[])
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_interlocuteurs_conversations(uuid[])
  TO authenticated;
