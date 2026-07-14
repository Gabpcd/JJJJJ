-- Suspension admin : synchroniser le soft-delete applicatif avec Supabase Auth.
-- Un JWT déjà émis est immédiatement neutralisé par fn_compte_auth_actif(),
-- tandis que GoTrue refuse les renouvellements grâce à auth.users.banned_until.
-- L'état antérieur est conservé afin qu'une réactivation Jolene ne retire
-- jamais un bannissement posé pour une autre raison.

CREATE TABLE IF NOT EXISTS public.suspensions_auth_admin (
  type_ressource text NOT NULL,
  id_ressource uuid NOT NULL,
  user_id uuid NOT NULL,
  banned_until_avant timestamptz,
  banned_until_pose timestamptz NOT NULL,
  suspendu_le timestamptz NOT NULL DEFAULT now(),
  suspendu_par uuid,
  motif text NOT NULL,
  PRIMARY KEY (type_ressource, id_ressource, user_id),
  CONSTRAINT suspensions_auth_admin_type_check
    CHECK (type_ressource IN ('soignants', 'etablissements')),
  CONSTRAINT suspensions_auth_admin_motif_check
    CHECK (char_length(btrim(motif)) BETWEEN 3 AND 1000)
);

-- Provenance applicative distincte d'une suppression RGPD. Une réactivation
-- n'est autorisée que si cette ligne a été créée par le flux de suspension
-- administrateur (ou par le rattrapage strict ci-dessous).
CREATE TABLE IF NOT EXISTS public.suspensions_profils_admin (
  type_ressource text NOT NULL,
  id_ressource uuid NOT NULL,
  supprime_le_avant timestamptz,
  suspendu_le timestamptz NOT NULL DEFAULT now(),
  suspendu_par uuid,
  motif text NOT NULL,
  PRIMARY KEY (type_ressource, id_ressource),
  CONSTRAINT suspensions_profils_admin_type_check
    CHECK (type_ressource IN ('soignants', 'etablissements')),
  CONSTRAINT suspensions_profils_admin_motif_check
    CHECK (char_length(btrim(motif)) BETWEEN 3 AND 1000)
);

CREATE TABLE IF NOT EXISTS public.suspensions_membres_etablissement_admin (
  etablissement_id uuid NOT NULL,
  membre_id uuid NOT NULL,
  user_id uuid NOT NULL,
  actif_avant boolean NOT NULL,
  desactive_le timestamptz NOT NULL,
  suspendu_par uuid,
  motif text NOT NULL,
  PRIMARY KEY (etablissement_id, membre_id),
  CONSTRAINT suspensions_membres_etablissement_admin_motif_check
    CHECK (char_length(btrim(motif)) BETWEEN 3 AND 1000)
);

CREATE TABLE IF NOT EXISTS public.suspensions_etablissement_admin (
  etablissement_id uuid PRIMARY KEY,
  peut_publier_avant boolean NOT NULL,
  suspendu_le timestamptz NOT NULL,
  suspendu_par uuid,
  motif text NOT NULL,
  CONSTRAINT suspensions_etablissement_admin_motif_check
    CHECK (char_length(btrim(motif)) BETWEEN 3 AND 1000)
);

ALTER TABLE public.suspensions_auth_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_auth_admin FORCE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_profils_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_profils_admin FORCE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_membres_etablissement_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_membres_etablissement_admin FORCE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_etablissement_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspensions_etablissement_admin FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.suspensions_auth_admin FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.suspensions_profils_admin FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.suspensions_membres_etablissement_admin FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.suspensions_etablissement_admin FROM PUBLIC, anon, authenticated;

-- Défense en profondeur : même si une ancienne suspension n'avait pas encore
-- synchronisé Auth, un profil principal soft-deleted ne reste jamais actif.
CREATE OR REPLACE FUNCTION public.fn_compte_auth_actif()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = auth.uid()
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND NOT EXISTS (
        SELECT 1 FROM public.soignants s
        WHERE s.id = u.id AND s.supprime_le IS NOT NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.etablissements e
        WHERE e.id = u.id AND e.supprime_le IS NOT NULL
      )
  ), false);
$function$;

REVOKE ALL ON FUNCTION public.fn_compte_auth_actif() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_compte_auth_actif() TO authenticated, service_role;

-- PostgREST ne consulte pas auth.users.banned_until pour un access token déjà
-- émis et les RPC SECURITY DEFINER peuvent contourner les RLS. Ce garde-fou
-- global est donc exécuté avant chaque requête authentifiée.
CREATE OR REPLACE FUNCTION public.fn_pre_request_compte_actif()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_claims jsonb := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
BEGIN
  IF COALESCE(v_claims->>'role', '') = 'authenticated'
     AND NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'Compte suspendu, supprimé ou désactivé';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_pre_request_compte_actif() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_pre_request_compte_actif()
  TO anon, authenticated, service_role;

ALTER ROLE authenticator
  SET pgrst.db_pre_request = 'public.fn_pre_request_compte_actif';
NOTIFY pgrst, 'reload config';

-- Le hook Data API ne s'applique pas à Storage. Les helpers des deux buckets
-- privés doivent donc refuser explicitement tout JWT suspendu encore valide.
CREATE OR REPLACE FUNCTION public.fn_peut_deposer_justificatif(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND public.fn_compte_auth_actif()
    AND p_name IS NOT NULL
    AND p_name NOT LIKE '%..%'
    AND split_part(p_name, '/', 1) = auth.uid()::text;
$function$;

CREATE OR REPLACE FUNCTION public.fn_peut_lire_justificatif(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND public.fn_compte_auth_actif()
    AND (
      public.est_admin()
      OR public.fn_peut_deposer_justificatif(p_name)
      OR EXISTS (
        SELECT 1 FROM public.missions m
        WHERE m.justificatif_honoraires_cle = p_name
          AND (
            m.soignant_assigne_id = auth.uid()
            OR public.fn_a_permission_etablissement('lecture_paiement', m.etablissement_id)
          )
      )
      OR EXISTS (
        SELECT 1 FROM public.evenements_score_soignant e
        LEFT JOIN public.missions m ON m.id = e.mission_id
        WHERE e.justificatif_storage_path = p_name
          AND (
            e.soignant_id = auth.uid()
            OR public.fn_a_permission_etablissement('candidatures', m.etablissement_id)
          )
      )
      OR EXISTS (
        SELECT 1 FROM public.evenements_score_etab e
        LEFT JOIN public.missions m ON m.id = e.mission_id
        WHERE e.justificatif_storage_path = p_name
          AND (
            public.fn_a_permission_etablissement('profil_etab', e.etablissement_id)
            OR m.soignant_assigne_id = auth.uid()
          )
      )
      OR EXISTS (
        SELECT 1 FROM public.reclamations_score r
        WHERE r.justificatif_storage_path = p_name
          AND r.contesteur_id = auth.uid()
      )
    );
$function$;

REVOKE ALL ON FUNCTION public.fn_peut_deposer_justificatif(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_peut_lire_justificatif(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_peut_deposer_justificatif(text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_peut_lire_justificatif(text)
  TO authenticated, service_role;

DROP POLICY IF EXISTS pol_storage_jolene_insert ON storage.objects;
CREATE POLICY pol_storage_jolene_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'jolene-documents'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_gerer_objet_jolene(name)
);

DROP POLICY IF EXISTS pol_storage_jolene_select ON storage.objects;
CREATE POLICY pol_storage_jolene_select ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'jolene-documents'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_lire_objet_jolene(name)
);

DROP POLICY IF EXISTS justificatifs_insert_auth ON storage.objects;
CREATE POLICY justificatifs_insert_auth ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'justificatifs'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_deposer_justificatif(name)
);

DROP POLICY IF EXISTS justificatifs_select_auth ON storage.objects;
CREATE POLICY justificatifs_select_auth ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'justificatifs'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_lire_justificatif(name)
);

DROP POLICY IF EXISTS pol_contrats_signes_select ON storage.objects;
CREATE POLICY pol_contrats_signes_select
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'contrats-signes'
  AND public.fn_compte_auth_actif()
  AND (
    public.est_admin()
    OR EXISTS (
      SELECT 1
      FROM public.contrats_mission cm
      WHERE cm.storage_path = storage.objects.name
        AND (
          cm.soignant_id = (SELECT auth.uid())
          OR cm.etablissement_id = public.mon_etablissement_id()
        )
    )
  )
);

-- Le bucket historique n'est plus utilisé pour les nouveaux dépôts de
-- l'application, mais ses policies live doivent rester reproductibles et
-- opposables à un access token suspendu.
DROP POLICY IF EXISTS soignant_lit_ses_attestations ON storage.objects;
CREATE POLICY soignant_lit_ses_attestations
ON storage.objects
FOR SELECT
TO authenticated
USING (
  public.fn_compte_auth_actif()
  AND bucket_id = 'attestations-heures-externes'
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.est_admin()
  )
);

DROP POLICY IF EXISTS soignant_supprime_ses_attestations ON storage.objects;
CREATE POLICY soignant_supprime_ses_attestations
ON storage.objects
FOR DELETE
TO authenticated
USING (
  public.fn_compte_auth_actif()
  AND bucket_id = 'attestations-heures-externes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS soignant_upload_ses_attestations ON storage.objects;
CREATE POLICY soignant_upload_ses_attestations
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  public.fn_compte_auth_actif()
  AND bucket_id = 'attestations-heures-externes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Rattrapage strict des anciennes suspensions applicatives : uniquement les
-- comptes Auth non supprimés et sans aucune marque d'anonymisation RGPD.
INSERT INTO public.suspensions_profils_admin (
  type_ressource, id_ressource, supprime_le_avant,
  suspendu_le, suspendu_par, motif
)
SELECT 'soignants', s.id, NULL, COALESCE(s.supprime_le, now()), NULL,
       'Rattrapage suspension applicative existante'
FROM public.soignants s
JOIN auth.users u ON u.id = s.id
WHERE s.supprime_le IS NOT NULL
  AND u.deleted_at IS NULL
  AND COALESCE(u.raw_app_meta_data->>'role', '') <> 'DELETED'
  AND lower(COALESCE(s.email, '')) NOT LIKE '%@supprime.jolene.app'
  AND NOT EXISTS (
    SELECT 1 FROM public.journaux_audit j
    WHERE j.id_ressource = s.id
      AND j.action = 'RGPD_SUPPRESSION_COMPTE'
  )
ON CONFLICT (type_ressource, id_ressource) DO NOTHING;

INSERT INTO public.suspensions_profils_admin (
  type_ressource, id_ressource, supprime_le_avant,
  suspendu_le, suspendu_par, motif
)
SELECT 'etablissements', e.id, NULL, COALESCE(e.supprime_le, now()), NULL,
       'Rattrapage suspension applicative existante'
FROM public.etablissements e
JOIN auth.users u ON u.id = e.id
WHERE e.supprime_le IS NOT NULL
  AND u.deleted_at IS NULL
  AND COALESCE(u.raw_app_meta_data->>'role', '') <> 'DELETED'
  AND lower(COALESCE(e.email_contact, '')) NOT LIKE '%@supprime.jolene.app'
  AND NOT (COALESCE(e.bloque_auto_raisons, '[]'::jsonb) ? 'COMPTE_SUPPRIME_RGPD')
  AND NOT EXISTS (
    SELECT 1 FROM public.journaux_audit j
    WHERE j.id_ressource = e.id
      AND j.action = 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'
  )
ON CONFLICT (type_ressource, id_ressource) DO NOTHING;

INSERT INTO public.suspensions_auth_admin (
  type_ressource, id_ressource, user_id, banned_until_avant, banned_until_pose,
  suspendu_le, suspendu_par, motif
)
SELECT 'soignants', s.id, u.id, u.banned_until,
       GREATEST(
         COALESCE(u.banned_until, transaction_timestamp()),
         transaction_timestamp() + interval '100 years'
       ),
       COALESCE(s.supprime_le, now()), NULL, 'Rattrapage suspension applicative existante'
FROM public.soignants s
JOIN auth.users u ON u.id = s.id
WHERE s.supprime_le IS NOT NULL
  AND u.deleted_at IS NULL
  AND COALESCE(u.raw_app_meta_data->>'role', '') <> 'DELETED'
  AND lower(COALESCE(s.email, '')) NOT LIKE '%@supprime.jolene.app'
  AND EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = 'soignants' AND sp.id_ressource = s.id
  )
ON CONFLICT (type_ressource, id_ressource, user_id) DO NOTHING;

INSERT INTO public.suspensions_auth_admin (
  type_ressource, id_ressource, user_id, banned_until_avant, banned_until_pose,
  suspendu_le, suspendu_par, motif
)
SELECT 'etablissements', e.id, u.id, u.banned_until,
       GREATEST(
         COALESCE(u.banned_until, transaction_timestamp()),
         transaction_timestamp() + interval '100 years'
       ),
       COALESCE(e.supprime_le, now()), NULL, 'Rattrapage suspension applicative existante'
FROM public.etablissements e
JOIN auth.users u ON u.id = e.id
WHERE e.supprime_le IS NOT NULL
  AND u.deleted_at IS NULL
  AND COALESCE(u.raw_app_meta_data->>'role', '') <> 'DELETED'
  AND lower(COALESCE(e.email_contact, '')) NOT LIKE '%@supprime.jolene.app'
  AND NOT (COALESCE(e.bloque_auto_raisons, '[]'::jsonb) ? 'COMPTE_SUPPRIME_RGPD')
  AND EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = 'etablissements' AND sp.id_ressource = e.id
  )
ON CONFLICT (type_ressource, id_ressource, user_id) DO NOTHING;

UPDATE auth.users u
SET banned_until = sa.banned_until_pose,
    updated_at = now()
FROM public.suspensions_auth_admin sa
WHERE sa.user_id = u.id
  AND u.banned_until IS NOT DISTINCT FROM sa.banned_until_avant
  AND (
    (sa.type_ressource = 'soignants' AND EXISTS (
      SELECT 1 FROM public.soignants s
      WHERE s.id = sa.id_ressource AND s.supprime_le IS NOT NULL
    ))
    OR
    (sa.type_ressource = 'etablissements' AND EXISTS (
      SELECT 1 FROM public.etablissements e
      WHERE e.id = sa.id_ressource AND e.supprime_le IS NOT NULL
    ))
  );

INSERT INTO public.suspensions_etablissement_admin (
  etablissement_id, peut_publier_avant, suspendu_le, suspendu_par, motif
)
SELECT e.id, e.peut_publier_missions, COALESCE(e.supprime_le, now()), NULL,
       'Rattrapage suspension applicative existante'
FROM public.etablissements e
WHERE e.supprime_le IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = 'etablissements' AND sp.id_ressource = e.id
  )
ON CONFLICT (etablissement_id) DO NOTHING;

INSERT INTO public.suspensions_membres_etablissement_admin (
  etablissement_id, membre_id, user_id, actif_avant, desactive_le,
  suspendu_par, motif
)
SELECT m.etablissement_id, m.id, m.user_id, m.actif, transaction_timestamp(),
       NULL, 'Rattrapage suspension applicative existante'
FROM public.membres_etablissement m
JOIN public.etablissements e ON e.id = m.etablissement_id
WHERE e.supprime_le IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = 'etablissements' AND sp.id_ressource = e.id
  )
  AND m.actif IS TRUE
ON CONFLICT (etablissement_id, membre_id) DO NOTHING;

UPDATE public.membres_etablissement m
SET actif = false,
    maj_le = sm.desactive_le
FROM public.suspensions_membres_etablissement_admin sm
JOIN public.etablissements e ON e.id = sm.etablissement_id
WHERE m.id = sm.membre_id
  AND m.etablissement_id = sm.etablissement_id
  AND e.supprime_le IS NOT NULL
  AND m.actif IS TRUE;

CREATE OR REPLACE FUNCTION public.fn_admin_suspendre_utilisateur(
  p_table text,
  p_id uuid,
  p_suspendre boolean DEFAULT true,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_nom text;
  v_motif text := NULLIF(btrim(COALESCE(p_motif, '')), '');
  v_maintenant timestamptz := transaction_timestamp();
  v_membres integer := 0;
  v_auth_trouve boolean := false;
  v_auth_state_existe boolean := false;
  v_banned_until_courant timestamptz;
  v_banned_until_pose timestamptz;
  v_pose_precedente timestamptz;
  v_peut_publier_avant boolean := false;
  v_supprime_le timestamptz;
  v_est_suppression_rgpd boolean := false;
  v_provenance_suspension boolean := false;
BEGIN
  IF NOT public.est_admin_valide() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin AAL2 uniquement');
  END IF;
  IF p_table NOT IN ('soignants', 'etablissements') THEN
    RETURN jsonb_build_object('error', 'Table invalide');
  END IF;
  IF p_id IS NULL OR p_suspendre IS NULL THEN
    RETURN jsonb_build_object('error', 'Paramètres de suspension invalides');
  END IF;
  IF p_suspendre AND (v_motif IS NULL OR char_length(v_motif) < 3) THEN
    RETURN jsonb_build_object('error', 'Motif obligatoire (3 caractères minimum)');
  END IF;
  IF v_motif IS NOT NULL AND char_length(v_motif) > 1000 THEN
    RETURN jsonb_build_object('error', 'Motif trop long (1000 caractères maximum)');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_table || ':' || p_id::text, 0));

  IF p_table = 'soignants' THEN
    SELECT
      COALESCE(s.prenom || ' ' || s.nom, 'Inconnu'),
      s.supprime_le,
      (
        lower(COALESCE(s.email, '')) LIKE '%@supprime.jolene.app'
        OR EXISTS (
          SELECT 1 FROM public.journaux_audit j
          WHERE j.id_ressource = s.id
            AND j.action = 'RGPD_SUPPRESSION_COMPTE'
        )
      )
    INTO v_nom, v_supprime_le, v_est_suppression_rgpd
    FROM public.soignants s
    WHERE s.id = p_id
    FOR UPDATE;
  ELSE
    SELECT
      COALESCE(e.nom, 'Inconnu'),
      e.peut_publier_missions,
      e.supprime_le,
      (
        lower(COALESCE(e.email_contact, '')) LIKE '%@supprime.jolene.app'
        OR COALESCE(e.bloque_auto_raisons, '[]'::jsonb) ? 'COMPTE_SUPPRIME_RGPD'
        OR EXISTS (
          SELECT 1 FROM public.journaux_audit j
          WHERE j.id_ressource = e.id
            AND j.action = 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'
        )
      )
    INTO v_nom, v_peut_publier_avant, v_supprime_le, v_est_suppression_rgpd
    FROM public.etablissements e
    WHERE e.id = p_id
    FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Compte introuvable');
  END IF;

  SELECT u.banned_until
  INTO v_banned_until_courant
  FROM auth.users u
  WHERE u.id = p_id AND u.deleted_at IS NULL
  FOR UPDATE;
  v_auth_trouve := FOUND;

  SELECT EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = p_table AND sp.id_ressource = p_id
  ) INTO v_provenance_suspension;

  IF v_est_suppression_rgpd THEN
    RETURN jsonb_build_object(
      'error',
      'Compte supprimé au titre du RGPD : suspension et réactivation interdites'
    );
  END IF;

  IF p_suspendre THEN
    IF v_supprime_le IS NOT NULL AND NOT v_provenance_suspension THEN
      RETURN jsonb_build_object(
        'error',
        'Compte déjà supprimé sans provenance de suspension réversible'
      );
    END IF;

    INSERT INTO public.suspensions_profils_admin (
      type_ressource, id_ressource, supprime_le_avant,
      suspendu_le, suspendu_par, motif
    ) VALUES (
      p_table, p_id, v_supprime_le, v_maintenant, auth.uid(), v_motif
    )
    ON CONFLICT (type_ressource, id_ressource) DO UPDATE
      SET suspendu_par = EXCLUDED.suspendu_par,
          motif = EXCLUDED.motif;

    IF v_auth_trouve THEN
      SELECT sa.banned_until_pose
      INTO v_pose_precedente
      FROM public.suspensions_auth_admin sa
      WHERE sa.type_ressource = p_table
        AND sa.id_ressource = p_id
        AND sa.user_id = p_id
      FOR UPDATE;
      v_auth_state_existe := FOUND;

      IF NOT v_auth_state_existe THEN
        v_banned_until_pose := GREATEST(
          COALESCE(v_banned_until_courant, v_maintenant),
          v_maintenant + interval '100 years'
        );

        INSERT INTO public.suspensions_auth_admin (
          type_ressource, id_ressource, user_id,
          banned_until_avant, banned_until_pose,
          suspendu_le, suspendu_par, motif
        ) VALUES (
          p_table, p_id, p_id,
          v_banned_until_courant, v_banned_until_pose,
          v_maintenant, auth.uid(), v_motif
        );

        UPDATE auth.users
        SET banned_until = v_banned_until_pose,
            updated_at = v_maintenant
        WHERE id = p_id
          AND banned_until IS NOT DISTINCT FROM v_banned_until_courant;
      ELSIF v_banned_until_courant IS NOT DISTINCT FROM v_pose_precedente THEN
        -- Suspension répétée : conserver l'état antérieur, mais faire suivre
        -- la valeur CAS réellement posée. Un ban externe divergent est intact.
        v_banned_until_pose := GREATEST(
          COALESCE(v_banned_until_courant, v_maintenant),
          v_maintenant + interval '100 years'
        );

        UPDATE auth.users
        SET banned_until = v_banned_until_pose,
            updated_at = v_maintenant
        WHERE id = p_id
          AND banned_until IS NOT DISTINCT FROM v_pose_precedente;

        UPDATE public.suspensions_auth_admin
        SET banned_until_pose = v_banned_until_pose,
            suspendu_par = auth.uid(),
            motif = v_motif
        WHERE type_ressource = p_table
          AND id_ressource = p_id
          AND user_id = p_id;
      END IF;
    END IF;

    IF p_table = 'soignants' THEN
      UPDATE public.soignants
      SET supprime_le = COALESCE(supprime_le, v_maintenant),
          modifie_le = v_maintenant
      WHERE id = p_id;
    ELSE
      INSERT INTO public.suspensions_etablissement_admin (
        etablissement_id, peut_publier_avant, suspendu_le, suspendu_par, motif
      ) VALUES (
        p_id, v_peut_publier_avant, v_maintenant, auth.uid(), v_motif
      )
      ON CONFLICT (etablissement_id) DO NOTHING;

      INSERT INTO public.suspensions_membres_etablissement_admin (
        etablissement_id, membre_id, user_id, actif_avant, desactive_le,
        suspendu_par, motif
      )
      SELECT p_id, m.id, m.user_id, m.actif, v_maintenant, auth.uid(), v_motif
      FROM public.membres_etablissement m
      WHERE m.etablissement_id = p_id
        AND m.actif IS TRUE
      ON CONFLICT (etablissement_id, membre_id) DO UPDATE
        SET desactive_le = EXCLUDED.desactive_le,
            suspendu_par = EXCLUDED.suspendu_par,
            motif = EXCLUDED.motif;

      UPDATE public.membres_etablissement m
      SET actif = false,
          maj_le = v_maintenant
      WHERE m.etablissement_id = p_id
        AND m.actif IS TRUE;
      GET DIAGNOSTICS v_membres = ROW_COUNT;

      UPDATE public.etablissements
      SET supprime_le = COALESCE(supprime_le, v_maintenant),
          peut_publier_missions = false,
          modifie_le = v_maintenant
      WHERE id = p_id;
    END IF;
  ELSE
    IF NOT v_provenance_suspension THEN
      RETURN jsonb_build_object(
        'error',
        'Aucune suspension administrateur réversible pour ce compte'
      );
    END IF;

    IF p_table = 'soignants' THEN
      UPDATE public.soignants s
      SET supprime_le = sp.supprime_le_avant,
          modifie_le = v_maintenant
      FROM public.suspensions_profils_admin sp
      WHERE s.id = p_id
        AND sp.type_ressource = 'soignants'
        AND sp.id_ressource = s.id;
    ELSE
      DELETE FROM public.suspensions_etablissement_admin se
      WHERE se.etablissement_id = p_id
      RETURNING se.peut_publier_avant INTO v_peut_publier_avant;

      UPDATE public.etablissements e
      SET supprime_le = sp.supprime_le_avant,
          peut_publier_missions = (
            COALESCE(v_peut_publier_avant, false)
            AND e.statut_verification = 'VERIFIE'
            AND e.siret_verifie IS TRUE
            AND e.finess_verifie IS TRUE
            AND e.representant_identite_verifiee IS TRUE
            AND e.rattachement_verifie IS TRUE
            AND e.contrat_service_signe IS TRUE
            AND e.bloque_auto_le IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM public.factures f
              WHERE f.etablissement_id = e.id
                AND f.statut IN ('EMISE', 'EN_RETARD')
                AND f.date_echeance < current_date
            )
          ),
          modifie_le = v_maintenant
      FROM public.suspensions_profils_admin sp
      WHERE e.id = p_id
        AND sp.type_ressource = 'etablissements'
        AND sp.id_ressource = e.id;

      UPDATE public.membres_etablissement m
      SET actif = sm.actif_avant,
          maj_le = v_maintenant
      FROM public.suspensions_membres_etablissement_admin sm
      WHERE sm.etablissement_id = p_id
        AND sm.membre_id = m.id
        AND m.etablissement_id = sm.etablissement_id
        AND m.user_id = sm.user_id
        AND m.actif IS FALSE
        AND m.maj_le = sm.desactive_le;
      GET DIAGNOSTICS v_membres = ROW_COUNT;

      DELETE FROM public.suspensions_membres_etablissement_admin sm
      WHERE sm.etablissement_id = p_id;
    END IF;

    UPDATE auth.users u
    SET banned_until = sa.banned_until_avant,
        updated_at = v_maintenant
    FROM public.suspensions_auth_admin sa
    WHERE sa.type_ressource = p_table
      AND sa.id_ressource = p_id
      AND sa.user_id = u.id
      AND u.banned_until IS NOT DISTINCT FROM sa.banned_until_pose;

    DELETE FROM public.suspensions_auth_admin sa
    WHERE sa.type_ressource = p_table
      AND sa.id_ressource = p_id;

    DELETE FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = p_table
      AND sp.id_ressource = p_id;
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    auth.uid(), 'ADMIN',
    CASE WHEN p_suspendre THEN 'SUSPENSION_COMPTE' ELSE 'REACTIVATION_COMPTE' END,
    p_table, p_id,
    jsonb_build_object(
      'nom', v_nom,
      'table', p_table,
      'action', CASE WHEN p_suspendre THEN 'suspendre' ELSE 'réactiver' END,
      'motif', v_motif,
      'auth_synchronise', v_auth_trouve,
      'membres_affectes', v_membres
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', CASE WHEN p_suspendre THEN 'Compte suspendu : ' ELSE 'Compte réactivé : ' END || v_nom,
    'auth_synchronise', v_auth_trouve,
    'membres_affectes', v_membres
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_suspendre_utilisateur(text, uuid, boolean, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_suspendre_utilisateur(text, uuid, boolean, text)
  TO authenticated;
