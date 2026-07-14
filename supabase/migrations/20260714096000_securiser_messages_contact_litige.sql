-- Ferme les dernières écritures directes des canaux de support/litige et
-- conserve un chemin RPC unique, borné et auditable pour chaque interface.

DROP POLICY IF EXISTS messages_contact_insert_self
  ON public.messages_contact;
REVOKE INSERT ON TABLE public.messages_contact
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_envoyer_message_contact(
  p_sujet text,
  p_corps text,
  p_source text DEFAULT 'aide'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_nom text;
  v_email text;
  v_msg_id uuid;
  v_sujet text := pg_catalog.btrim(COALESCE(p_sujet, ''));
  v_corps text := pg_catalog.btrim(COALESCE(p_corps, ''));
  v_source text := COALESCE(
    NULLIF(pg_catalog.btrim(p_source), ''),
    'aide'
  );
  v_url text;
  v_token text;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Non authentifié');
  END IF;
  IF pg_catalog.length(v_sujet) < 1
     OR pg_catalog.length(v_sujet) > 150
     OR pg_catalog.length(v_corps) < 1
     OR pg_catalog.length(v_corps) > 4000 THEN
    RETURN pg_catalog.jsonb_build_object(
      'error', 'Sujet (150 max) et message (4000 max) obligatoires'
    );
  END IF;
  IF pg_catalog.length(v_source) > 120 THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Source invalide');
  END IF;
  IF (
    SELECT pg_catalog.count(*)
    FROM public.messages_contact mc
    WHERE mc.expediteur_id = v_uid
      AND mc.cree_le > pg_catalog.now() - interval '1 hour'
  ) >= 10 THEN
    RETURN pg_catalog.jsonb_build_object(
      'error', 'Trop de demandes. Réessayez dans une heure.'
    );
  END IF;

  IF public.est_admin() THEN
    SELECT
      COALESCE(ea.prenom || ' ' || ea.nom, u.email),
      u.email
    INTO v_nom, v_email
    FROM auth.users u
    LEFT JOIN public.equipe_admin ea
      ON ea.user_id = u.id AND ea.actif IS TRUE
    WHERE u.id = v_uid;
    v_role := 'ADMIN_PLATEFORME';
  ELSE
    SELECT s.prenom || ' ' || s.nom, s.email
    INTO v_nom, v_email
    FROM public.soignants s
    WHERE s.id = v_uid
      AND s.supprime_le IS NULL;
    IF FOUND THEN
      v_role := 'SOIGNANT';
    ELSE
      SELECT e.nom, e.email_contact
      INTO v_nom, v_email
      FROM public.membres_etablissement me
      JOIN public.etablissements e ON e.id = me.etablissement_id
      WHERE me.user_id = v_uid
        AND me.actif IS TRUE
        AND e.supprime_le IS NULL
      ORDER BY
        CASE me.role
          WHEN 'PROPRIETAIRE' THEN 0
          WHEN 'ADMIN_GROUPE' THEN 1
          WHEN 'RH' THEN 2
          ELSE 3
        END,
        me.accepte_le,
        me.id
      LIMIT 1;
      IF NOT FOUND THEN
        -- Compatibilité avec les comptes historiques id établissement = id Auth.
        SELECT e.nom, e.email_contact
        INTO v_nom, v_email
        FROM public.etablissements e
        WHERE e.id = v_uid
          AND e.supprime_le IS NULL;
      END IF;
      IF v_nom IS NOT NULL THEN
        v_role := 'ADMIN_ETABLISSEMENT';
      END IF;
    END IF;
  END IF;

  IF v_email IS NULL THEN
    SELECT u.email INTO v_email FROM auth.users u WHERE u.id = v_uid;
  END IF;
  INSERT INTO public.messages_contact (
    expediteur_id,
    expediteur_role,
    expediteur_nom,
    expediteur_email,
    sujet,
    corps,
    source
  ) VALUES (
    v_uid,
    COALESCE(v_role, 'INCONNU'),
    v_nom,
    v_email,
    v_sujet,
    v_corps,
    v_source
  )
  RETURNING id INTO v_msg_id;

  BEGIN
    INSERT INTO public.notifications (
      destinataire_id,
      type_destinataire,
      type,
      titre,
      corps,
      lien,
      type_ressource,
      id_ressource
    )
    SELECT
      admins.uid,
      'ADMIN',
      'MESSAGE_ADMIN',
      '✉️ Nouveau message — ' || COALESCE(v_nom, 'utilisateur'),
      pg_catalog.left(v_corps, 140),
      '/admin/messages-contact',
      'message_contact',
      v_msg_id
    FROM public.fn_list_admin_user_ids() AS admins(uid);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  BEGIN
    -- L'URL ne doit jamais pointer implicitement vers la production depuis
    -- une branche/staging. Le vault peut la surcharger ; sinon l'issuer du JWT
    -- Supabase vérifié fournit l'URL exacte de l'environnement courant.
    SELECT NULLIF(pg_catalog.btrim(ds.decrypted_secret), '')
    INTO v_url
    FROM vault.decrypted_secrets ds
    WHERE ds.name = 'supabase_url'
    LIMIT 1;
    v_url := COALESCE(
      v_url,
      NULLIF(
        pg_catalog.regexp_replace(
          COALESCE(auth.jwt()->>'iss', ''),
          '/auth/v1/?$',
          ''
        ),
        ''
      )
    );
    v_token := public.fn_lire_secret_cron();
    IF v_token IS NOT NULL AND v_url IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := pg_catalog.jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_token
        ),
        body := pg_catalog.jsonb_build_object(
          'sujet', v_sujet,
          'corps', v_corps,
          'expediteur_nom', v_nom,
          'expediteur_email', v_email,
          'source', 'Contact ' || COALESCE(v_role, ''),
          'lien', '/admin/messages-contact'
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'message_id', v_msg_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_message_contact(text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_message_contact(text, text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_traiter_message_contact(
  p_message_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.messages_contact
  SET statut = 'TRAITE',
      traite_le = COALESCE(traite_le, pg_catalog.now()),
      traite_par = COALESCE(traite_par, v_uid)
  WHERE id = p_message_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Message introuvable');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'ADMIN_ACTION',
    p_type_ressource := 'message_contact',
    p_id_ressource := p_message_id,
    p_details := pg_catalog.jsonb_build_object(
      'sous_action', 'MESSAGE_CONTACT_TRAITE'
    )
  );
  RETURN pg_catalog.jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_traiter_message_contact(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_traiter_message_contact(uuid)
  TO authenticated;

-- Le modèle établissement est multi-compte : les policies historiques basées
-- sur mon_etablissement_id() rendaient un litige illisible pour un membre RH
-- autorisé d'un établissement secondaire. Lecture et mutation utilisent
-- désormais la même permission que les RPC de contrat/litige.
DROP POLICY IF EXISTS pol_litige_insert ON public.litiges;
CREATE POLICY pol_litige_insert
ON public.litiges
FOR INSERT TO authenticated
WITH CHECK (
  public.est_admin()
  OR (
    soignant_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.missions mi
      WHERE mi.id = mission_id
        AND mi.soignant_assigne_id = auth.uid()
        AND mi.etablissement_id = etablissement_id
    )
  )
  OR (
    public.fn_a_permission_etablissement(
      'contrats', etablissement_id
    ) IS TRUE
    AND EXISTS (
      SELECT 1
      FROM public.missions mi
      WHERE mi.id = mission_id
        AND mi.etablissement_id = etablissement_id
    )
  )
);

DROP POLICY IF EXISTS pol_litige_select ON public.litiges;
CREATE POLICY pol_litige_select
ON public.litiges
FOR SELECT TO authenticated
USING (
  public.est_admin()
  OR soignant_id = auth.uid()
  OR public.fn_a_permission_etablissement(
    'contrats', etablissement_id
  ) IS TRUE
);

DROP POLICY IF EXISTS pol_litige_update ON public.litiges;
CREATE POLICY pol_litige_update
ON public.litiges
FOR UPDATE TO authenticated
USING (
  public.est_admin()
  OR (
    initie_par = 'ETABLISSEMENT'
    AND soignant_id = auth.uid()
    AND statut IN ('OUVERT', 'EN_DISCUSSION')
  )
  OR (
    initie_par = 'SOIGNANT'
    AND public.fn_a_permission_etablissement(
      'contrats', etablissement_id
    ) IS TRUE
    AND statut IN ('OUVERT', 'EN_DISCUSSION')
  )
)
WITH CHECK (
  public.est_admin()
  OR (
    initie_par = 'ETABLISSEMENT'
    AND soignant_id = auth.uid()
    AND statut IN ('OUVERT', 'EN_DISCUSSION')
  )
  OR (
    initie_par = 'SOIGNANT'
    AND public.fn_a_permission_etablissement(
      'contrats', etablissement_id
    ) IS TRUE
    AND statut IN ('OUVERT', 'EN_DISCUSSION')
  )
);

DROP POLICY IF EXISTS pol_messages_litige_select
  ON public.messages_litige;
CREATE POLICY pol_messages_litige_select
ON public.messages_litige
FOR SELECT TO authenticated
USING (
  public.est_admin()
  OR auteur_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.litiges l
    WHERE l.id = litige_id
      AND (
        l.soignant_id = auth.uid()
        OR public.fn_a_permission_etablissement(
          'contrats', l.etablissement_id
        ) IS TRUE
      )
  )
);

-- Une notification appartient toujours à un utilisateur Auth (la RLS et la
-- page Notifications filtrent auth.uid()), jamais à l'UUID métier de
-- l'établissement. Ce helper couvre tous les responsables opérationnels et
-- conserve les deux modèles de comptes historiques, sans réactiver un membre
-- révoqué ou banni.
CREATE OR REPLACE FUNCTION private.fn_destinataires_litige_etablissement(
  p_etablissement_id uuid
)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT DISTINCT candidat.user_id
  FROM (
    SELECT me.user_id
    FROM public.membres_etablissement me
    WHERE me.etablissement_id = p_etablissement_id

    UNION ALL

    SELECT e.id
    FROM public.etablissements e
    WHERE e.id = p_etablissement_id

    UNION ALL

    SELECT u.id
    FROM auth.users u
    WHERE u.raw_app_meta_data ->> 'etablissement_id' =
          p_etablissement_id::text
  ) AS candidat
  WHERE private.fn_interlocuteur_operationnel_actif(
    candidat.user_id,
    p_etablissement_id
  )
  ORDER BY candidat.user_id;
$function$;

REVOKE ALL ON FUNCTION private.fn_destinataires_litige_etablissement(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_message_litige_dest
ON public.notifications(destinataire_id, id_ressource)
WHERE type_ressource = 'message_litige';

-- Réinstalle la RPC litige en texte brut : React affiche contenu comme nœud
-- texte, donc l'encodage HTML historique altérait « A & B » et « 1 < 2 ».
CREATE OR REPLACE FUNCTION public.fn_ajouter_message_litige(
  p_litige_id uuid,
  p_contenu text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige public.litiges%ROWTYPE;
  v_type_auteur text;
  v_est_admin boolean := false;
  v_contenu text;
  v_message_id uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_est_admin := public.est_admin();
  SELECT l.* INTO v_litige
  FROM public.litiges l
  WHERE l.id = p_litige_id
    AND (
      l.soignant_id = v_uid
      OR public.fn_a_permission_etablissement(
        'contrats', l.etablissement_id
      ) IS TRUE
      OR v_est_admin
    )
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'error', 'Litige introuvable ou accès refusé'
    );
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS',
    'REVUE_ADMIN'
  ) THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Ce litige est clôturé.');
  END IF;

  v_contenu := pg_catalog.btrim(COALESCE(p_contenu, ''));
  IF pg_catalog.length(v_contenu) < 10
     OR pg_catalog.length(v_contenu) > 5000 THEN
    RETURN pg_catalog.jsonb_build_object(
      'error', 'Le message doit contenir entre 10 et 5000 caractères.'
    );
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_type_auteur := 'SOIGNANT';
  ELSIF public.fn_a_permission_etablissement(
          'contrats', v_litige.etablissement_id
        ) IS TRUE THEN
    v_type_auteur := 'ETABLISSEMENT';
  ELSIF v_est_admin THEN
    v_type_auteur := 'ADMIN';
  ELSE
    RETURN pg_catalog.jsonb_build_object('error', 'Accès refusé');
  END IF;

  INSERT INTO public.messages_litige (
    litige_id, auteur_id, type_auteur, contenu
  ) VALUES (
    p_litige_id, v_uid, v_type_auteur, v_contenu
  )
  RETURNING id INTO v_message_id;

  WITH candidats AS (
    SELECT
      v_litige.soignant_id AS user_id,
      'SOIGNANT'::text AS type_destinataire,
      CASE WHEN v_type_auteur = 'ADMIN'
        THEN 'Nouveau message de l''équipe Jolene'
        ELSE 'Nouveau message sur le litige'
      END AS titre,
      CASE WHEN v_type_auteur = 'ADMIN'
        THEN 'Un message administrateur a été ajouté à votre litige.'
        ELSE 'Un message a été ajouté au litige concernant la mission.'
      END AS corps,
      '/soignant/litiges?litige=' || v_litige.id::text AS lien,
      0 AS priorite
    WHERE v_type_auteur IN ('ETABLISSEMENT', 'ADMIN')
      AND v_litige.soignant_id IS DISTINCT FROM v_uid
      AND private.fn_soignant_messagerie_actif(
        v_litige.soignant_id
      )

    UNION ALL

    SELECT
      d.user_id,
      'ETABLISSEMENT',
      CASE WHEN v_type_auteur = 'ADMIN'
        THEN 'Nouveau message de l''équipe Jolene'
        ELSE 'Nouveau message sur le litige'
      END,
      CASE WHEN v_type_auteur = 'ADMIN'
        THEN 'Un message administrateur a été ajouté à votre litige.'
        ELSE 'Un message a été ajouté au litige concernant la mission.'
      END,
      '/etablissement/litiges?litige=' || v_litige.id::text,
      1
    FROM private.fn_destinataires_litige_etablissement(
      v_litige.etablissement_id
    ) AS d(user_id)
    WHERE v_type_auteur IN ('SOIGNANT', 'ADMIN')
      AND d.user_id IS DISTINCT FROM v_uid
      AND d.user_id IS DISTINCT FROM v_litige.soignant_id
  ), destinataires AS (
    SELECT DISTINCT ON (user_id)
      user_id,
      type_destinataire,
      titre,
      corps,
      lien
    FROM candidats
    ORDER BY user_id, priorite
  )
  INSERT INTO public.notifications (
    destinataire_id,
    type_destinataire,
    type,
    titre,
    corps,
    lien,
    type_ressource,
    id_ressource
  )
  SELECT
    user_id,
    type_destinataire,
    'SYSTEM',
    titre,
    corps,
    lien,
    'message_litige',
    v_message_id
  FROM destinataires
  ON CONFLICT (destinataire_id, id_ressource)
    WHERE type_ressource = 'message_litige'
  DO NOTHING;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'message_id', v_message_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_ajouter_message_litige(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_ajouter_message_litige(uuid, text)
  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
