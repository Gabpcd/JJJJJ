-- P0 securite pre-lancement (apres Lots 19-21 pour conserver les gardes finaux)
-- - sessions/comptes supprimes neutralises immediatement cote Data API
-- - admin et membres etablissement verifies dans les sources serveur
-- - retrait des lectures full-row inter-profils
-- - RBAC etablissement applique aux mutations principales
-- - vues partagees a projection minimale pour router le frontend

-- ---------------------------------------------------------------------------
-- 0. Un compte Auth ne peut appartenir qu'a une seule famille de comptes
-- ---------------------------------------------------------------------------

-- Les deux inscriptions sont terminees par des Edge Functions service-role.
-- Sans reservation atomique, deux appels concurrents pourraient creer a la
-- fois un profil soignant et un profil etablissement pour le meme auth.users.id.
-- Cette table ne contient aucune donnee de profil et conserve les comptes de
-- demonstration tels quels : elle enregistre uniquement leur famille d'acces.
CREATE TABLE IF NOT EXISTS public.types_comptes_auth (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  type_compte text NOT NULL CHECK (type_compte IN ('SOIGNANT', 'ETABLISSEMENT', 'ADMIN')),
  reserve_le timestamptz NOT NULL DEFAULT now(),
  finalise_le timestamptz,
  claim_token uuid,
  claim_expire_le timestamptz,
  CONSTRAINT types_comptes_auth_finalisation_check
    CHECK (finalise_le IS NULL OR finalise_le >= reserve_le)
);

ALTER TABLE public.types_comptes_auth ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.types_comptes_auth FORCE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.types_comptes_auth FROM PUBLIC, anon, authenticated;
GRANT ALL PRIVILEGES ON TABLE public.types_comptes_auth TO service_role;

-- Backfill non destructif. La metadonnee serveur est prioritaire, puis les
-- profils existants. Les eventuels conflits historiques restent intacts et
-- seront refuses explicitement par fn_reserver_type_compte pour revue admin.
INSERT INTO public.types_comptes_auth (user_id, type_compte, finalise_le)
SELECT
  u.id,
  CASE
    WHEN u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME' THEN 'ADMIN'
    WHEN u.raw_app_meta_data ->> 'role' = 'SOIGNANT' THEN 'SOIGNANT'
    WHEN u.raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE') THEN 'ETABLISSEMENT'
  END,
  now()
FROM auth.users u
WHERE u.raw_app_meta_data ->> 'role' IN (
  'ADMIN_PLATEFORME', 'SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE'
)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.types_comptes_auth (user_id, type_compte, finalise_le)
SELECT s.id, 'SOIGNANT', now()
FROM public.soignants s
JOIN auth.users u ON u.id = s.id
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.types_comptes_auth (user_id, type_compte, finalise_le)
SELECT e.id, 'ETABLISSEMENT', now()
FROM public.etablissements e
JOIN auth.users u ON u.id = e.id
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.types_comptes_auth (user_id, type_compte, finalise_le)
SELECT DISTINCT m.user_id, 'ETABLISSEMENT', now()
FROM public.membres_etablissement m
JOIN auth.users u ON u.id = m.user_id
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_reserver_type_compte(
  p_user_id uuid,
  p_type_compte text,
  p_claim_token uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_type_demande text := upper(trim(COALESCE(p_type_compte, '')));
  v_type_reserve text;
  v_role_auth text;
  v_soignant boolean;
  v_etablissement boolean;
  v_membre_etablissement boolean;
  v_finalise_le timestamptz;
  v_claim_token uuid;
  v_claim_expire_le timestamptz;
  v_frais boolean;
BEGIN
  IF p_user_id IS NULL OR p_claim_token IS NULL
     OR v_type_demande NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'ACCOUNT_TYPE_INVALID');
  END IF;

  -- Un seul gagnant, y compris entre register-soignant et
  -- register-etablissement lances exactement au meme instant.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  SELECT u.raw_app_meta_data ->> 'role'
  INTO v_role_auth
  FROM auth.users u
  WHERE u.id = p_user_id
    AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until <= now());

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'ACCOUNT_AUTH_INACTIVE');
  END IF;

  SELECT EXISTS (SELECT 1 FROM public.soignants s WHERE s.id = p_user_id),
         EXISTS (SELECT 1 FROM public.etablissements e WHERE e.id = p_user_id),
         EXISTS (SELECT 1 FROM public.membres_etablissement m WHERE m.user_id = p_user_id)
  INTO v_soignant, v_etablissement, v_membre_etablissement;

  -- Un profil historiquement croise n'est jamais « repare » automatiquement :
  -- aucun profil ni aucune donnee de test n'est supprime par la migration.
  IF v_soignant AND (v_etablissement OR v_membre_etablissement) THEN
    RETURN jsonb_build_object('allowed', false, 'code', 'ACCOUNT_PROFILE_CONFLICT');
  END IF;

  SELECT t.type_compte, t.finalise_le, t.claim_token, t.claim_expire_le
  INTO v_type_reserve, v_finalise_le, v_claim_token, v_claim_expire_le
  FROM public.types_comptes_auth t
  WHERE t.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    v_type_reserve := CASE
      WHEN v_role_auth = 'ADMIN_PLATEFORME' THEN 'ADMIN'
      WHEN v_role_auth = 'SOIGNANT' OR v_soignant THEN 'SOIGNANT'
      WHEN v_role_auth IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE')
        OR v_etablissement OR v_membre_etablissement THEN 'ETABLISSEMENT'
      ELSE v_type_demande
    END;

    v_finalise_le := CASE
      WHEN v_soignant OR v_etablissement OR v_membre_etablissement OR v_role_auth IS NOT NULL
        THEN now()
      ELSE NULL
    END;
    INSERT INTO public.types_comptes_auth (
      user_id, type_compte, finalise_le, claim_token, claim_expire_le
    )
    VALUES (
      p_user_id,
      v_type_reserve,
      v_finalise_le,
      CASE WHEN v_finalise_le IS NULL THEN p_claim_token ELSE NULL END,
      CASE WHEN v_finalise_le IS NULL THEN now() + interval '15 minutes' ELSE NULL END
    );
  END IF;

  IF v_type_reserve <> v_type_demande THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'code', 'ACCOUNT_TYPE_MISMATCH',
      'existing_type', v_type_reserve
    );
  END IF;

  -- Un profil deja finalise doit se connecter; l'Edge Function ne doit surtout
  -- pas le supprimer au titre d'une compensation d'inscription.
  IF (v_type_demande = 'SOIGNANT' AND v_soignant)
     OR (v_type_demande = 'ETABLISSEMENT' AND (v_etablissement OR v_membre_etablissement)) THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'code', 'ACCOUNT_ALREADY_REGISTERED',
      'existing_type', v_type_reserve
    );
  END IF;

  IF v_finalise_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'code', 'ACCOUNT_REGISTRATION_INCOMPLETE',
      'existing_type', v_type_reserve
    );
  END IF;

  IF v_claim_token IS NOT NULL
     AND v_claim_token <> p_claim_token
     AND COALESCE(v_claim_expire_le, '-infinity'::timestamptz) > now() THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'code', 'ACCOUNT_REGISTRATION_IN_PROGRESS',
      'existing_type', v_type_reserve
    );
  END IF;

  -- Une reservation abandonnee est recuperable apres un delai court. Un appel
  -- concurrent du meme type ne partage jamais le droit de compensation Auth.
  UPDATE public.types_comptes_auth
  SET claim_token = p_claim_token,
      claim_expire_le = now() + interval '15 minutes'
  WHERE user_id = p_user_id;

  v_frais := v_finalise_le IS NULL
    AND v_role_auth IS NULL
    AND NOT v_soignant
    AND NOT v_etablissement
    AND NOT v_membre_etablissement;

  RETURN jsonb_build_object(
    'allowed', true,
    'fresh', v_frais,
    'type_compte', v_type_reserve
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_finaliser_type_compte(
  p_user_id uuid,
  p_type_compte text,
  p_claim_token uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_type text := upper(trim(COALESCE(p_type_compte, '')));
BEGIN
  IF v_type = 'SOIGNANT' AND NOT EXISTS (
    SELECT 1 FROM public.soignants s WHERE s.id = p_user_id
  ) THEN
    RETURN false;
  ELSIF v_type = 'ETABLISSEMENT' AND NOT EXISTS (
    SELECT 1 FROM public.etablissements e WHERE e.id = p_user_id
  ) THEN
    RETURN false;
  ELSIF v_type NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RETURN false;
  END IF;

  UPDATE public.types_comptes_auth
  SET finalise_le = COALESCE(finalise_le, now()),
      claim_token = NULL,
      claim_expire_le = NULL
  WHERE user_id = p_user_id
    AND type_compte = v_type
    AND claim_token = p_claim_token
    AND claim_expire_le > now();
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_reserver_type_compte(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_finaliser_type_compte(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_type_compte(uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_finaliser_type_compte(uuid, text, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_protect_famille_compte_membre_etablissement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_type text;
BEGIN
  IF NEW.actif IS NOT TRUE THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id::text, 0));

  SELECT t.type_compte INTO v_type
  FROM public.types_comptes_auth t
  WHERE t.user_id = NEW.user_id
  FOR UPDATE;

  IF v_type IS NULL THEN
    SELECT CASE
      WHEN EXISTS (SELECT 1 FROM public.soignants s WHERE s.id = NEW.user_id)
        OR u.raw_app_meta_data ->> 'role' = 'SOIGNANT' THEN 'SOIGNANT'
      WHEN u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME' THEN 'ADMIN'
      WHEN EXISTS (SELECT 1 FROM public.etablissements e WHERE e.id = NEW.user_id)
        OR u.raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT', 'ADMIN_GROUPE')
        THEN 'ETABLISSEMENT'
      ELSE NULL
    END
    INTO v_type
    FROM auth.users u
    WHERE u.id = NEW.user_id;
  END IF;
  IF v_type IS NULL THEN
    INSERT INTO public.types_comptes_auth(user_id, type_compte, finalise_le)
    VALUES (NEW.user_id, 'ETABLISSEMENT', now())
    ON CONFLICT (user_id) DO NOTHING;
    SELECT t.type_compte INTO v_type
    FROM public.types_comptes_auth t WHERE t.user_id = NEW.user_id;
  END IF;

  IF v_type IS DISTINCT FROM 'ETABLISSEMENT' THEN
    RAISE EXCEPTION 'Ce compte appartient deja a un espace incompatible'
      USING ERRCODE = '23514', HINT = 'Utiliser une adresse dediee a l espace etablissement';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_famille_compte_membre_etablissement
  ON public.membres_etablissement;
CREATE TRIGGER trg_protect_famille_compte_membre_etablissement
  BEFORE INSERT OR UPDATE OF user_id, actif ON public.membres_etablissement
  FOR EACH ROW EXECUTE FUNCTION public.fn_protect_famille_compte_membre_etablissement();
REVOKE ALL ON FUNCTION public.fn_protect_famille_compte_membre_etablissement()
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Source de verite d'activite Auth
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_compte_auth_actif()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = auth.uid()
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
  ), false);
$$;

REVOKE ALL ON FUNCTION public.fn_compte_auth_actif() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_compte_auth_actif() TO authenticated, service_role;

-- Une policy RESTRICTIVE s'ajoute avec AND a toutes les policies permissives
-- existantes. Un JWT deja emis ne peut donc plus lire/ecrire apres soft-delete
-- ou bannissement du compte Auth, meme avant son expiration cryptographique.
DO $policies_compte_actif$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS relation
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relrowsecurity = true
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS pol_compte_auth_actif_restrictive ON %s', r.relation);
    EXECUTE format(
      'CREATE POLICY pol_compte_auth_actif_restrictive ON %s AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT public.fn_compte_auth_actif())) WITH CHECK ((SELECT public.fn_compte_auth_actif()))',
      r.relation
    );
  END LOOP;
END;
$policies_compte_actif$;

-- ---------------------------------------------------------------------------
-- 2. Admin fail-closed, y compris equipe_admin.actif=false
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.est_admin_valide()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = auth.uid()
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND u.email_confirmed_at IS NOT NULL
      AND COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'
      -- L'absence de ligne conserve la compatibilite fondatrice. En revanche,
      -- la presence d'au moins une ligne explicite inactive est bloquante,
      -- meme en cas de doublon historique dans equipe_admin.
      AND NOT EXISTS (
        SELECT 1 FROM public.equipe_admin ea
        WHERE ea.user_id = u.id AND ea.actif IS NOT TRUE
      )
  ), false);
$$;

CREATE OR REPLACE FUNCTION public.est_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.est_admin_valide();
$$;

REVOKE ALL ON FUNCTION public.est_admin_valide() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.est_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.est_admin_valide() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.est_admin() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_list_admin_user_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT u.id
  FROM auth.users u
  WHERE u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
    AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until <= now())
    AND u.email_confirmed_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.equipe_admin ea
      WHERE ea.user_id = u.id AND ea.actif IS NOT TRUE
    );
$$;

REVOKE ALL ON FUNCTION public.fn_list_admin_user_ids() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_list_admin_user_ids() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_mes_acces()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_equipe public.equipe_admin%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_equipe
  FROM public.equipe_admin
  WHERE user_id = v_uid;

  IF FOUND AND v_equipe.actif IS NOT TRUE THEN
    RAISE EXCEPTION 'Compte administrateur desactive' USING ERRCODE = '42501';
  END IF;

  IF NOT FOUND OR v_equipe.poste ILIKE '%fondat%' THEN
    RETURN jsonb_build_object('acces_total', true, 'groupes', '[]'::jsonb, 'actif', true);
  END IF;

  RETURN jsonb_build_object(
    'acces_total', false,
    'groupes', to_jsonb(COALESCE(v_equipe.acces_groupes, ARRAY[]::text[])),
    'actif', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_mes_acces() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_mes_acces() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Appartenance et permissions etablissement actives
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_role_etablissement_courant(
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN NULL;
  END IF;

  SELECT m.role INTO v_role
  FROM public.membres_etablissement m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.user_id = v_uid
    AND m.actif = true
    AND e.supprime_le IS NULL
    AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id)
  ORDER BY CASE m.role WHEN 'PROPRIETAIRE' THEN 1 WHEN 'ADMIN_GROUPE' THEN 2 ELSE 3 END
  LIMIT 1;

  IF v_role IS NOT NULL THEN
    RETURN v_role;
  END IF;

  -- Compatibilite des comptes historiques : le compte Auth et la ligne
  -- etablissement partagent le meme UUID. Un simple etablissement_id stale
  -- dans app_metadata ne suffit jamais a recreer une appartenance revoquee.
  SELECT 'PROPRIETAIRE' INTO v_role
  FROM auth.users u
  JOIN public.etablissements e ON e.id = u.id
  WHERE u.id = v_uid
    AND u.raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT')
    AND e.supprime_le IS NULL
    AND (p_etablissement_id IS NULL OR e.id = p_etablissement_id)
  LIMIT 1;

  RETURN v_role;
END;
$$;

CREATE OR REPLACE FUNCTION public.mon_etablissement_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT COALESCE(
    (
      SELECT m.etablissement_id
      FROM public.membres_etablissement m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.user_id = auth.uid()
        AND m.actif = true
        AND e.supprime_le IS NULL
      ORDER BY CASE m.role WHEN 'PROPRIETAIRE' THEN 1 WHEN 'ADMIN_GROUPE' THEN 2 ELSE 3 END
      LIMIT 1
    ),
    (
      SELECT e.id
      FROM auth.users u
      JOIN public.etablissements e ON e.id = u.id
      WHERE u.id = auth.uid()
        AND u.deleted_at IS NULL
        AND (u.banned_until IS NULL OR u.banned_until <= now())
        AND u.raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT')
        AND e.supprime_le IS NULL
      LIMIT 1
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_a_permission_etablissement(
  p_permission text,
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_role text;
BEGIN
  IF public.est_admin() THEN RETURN true; END IF;
  v_role := public.fn_role_etablissement_courant(p_etablissement_id);
  IF v_role IS NULL THEN RETURN false; END IF;

  RETURN CASE lower(COALESCE(p_permission, ''))
    WHEN 'gerer_equipe' THEN v_role = 'PROPRIETAIRE'
    WHEN 'supprimer_compte' THEN v_role = 'PROPRIETAIRE'
    WHEN 'profil_etab' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    WHEN 'paiement' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    WHEN 'missions' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'candidatures' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'contrats' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'pointage' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY')
    WHEN 'rh' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'api' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    WHEN 'lecture_missions' THEN true
    WHEN 'lecture_candidatures' THEN v_role <> 'POINTAGE_ONLY'
    WHEN 'lecture_contrats' THEN v_role <> 'POINTAGE_ONLY'
    WHEN 'lecture_paiement' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'LECTURE_SEULE')
    WHEN 'lecture_pointage' THEN true
    WHEN 'lecture' THEN true
    ELSE false
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.est_admin_etablissement()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.fn_role_etablissement_courant(NULL) IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH');
$$;

CREATE OR REPLACE FUNCTION public.fn_mes_permissions_etab(
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_etab_id uuid := COALESCE(p_etablissement_id, public.mon_etablissement_id());
  v_role text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'role', NULL, 'permissions', '{}'::jsonb);
  END IF;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'etablissement_id', NULL, 'permissions', '{}'::jsonb);
  END IF;

  v_role := public.fn_role_etablissement_courant(v_etab_id);
  IF v_role IS NULL AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'etablissement_id', NULL, 'permissions', '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'role', COALESCE(v_role, 'ADMIN_PLATEFORME'),
    'etablissement_id', v_etab_id,
    'permissions', jsonb_build_object(
      'gerer_equipe', public.fn_a_permission_etablissement('gerer_equipe', v_etab_id),
      'supprimer_compte', public.fn_a_permission_etablissement('supprimer_compte', v_etab_id),
      'profil_etab', public.fn_a_permission_etablissement('profil_etab', v_etab_id),
      'paiement', public.fn_a_permission_etablissement('paiement', v_etab_id),
      'missions', public.fn_a_permission_etablissement('missions', v_etab_id),
      'candidatures', public.fn_a_permission_etablissement('candidatures', v_etab_id),
      'contrats', public.fn_a_permission_etablissement('contrats', v_etab_id),
      'pointage', public.fn_a_permission_etablissement('pointage', v_etab_id),
      'rh', public.fn_a_permission_etablissement('rh', v_etab_id),
      'lecture', public.fn_a_permission_etablissement('lecture', v_etab_id)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_role_etablissement_courant(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mon_etablissement_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_a_permission_etablissement(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.est_admin_etablissement() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_mes_permissions_etab(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_role_etablissement_courant(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mon_etablissement_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_a_permission_etablissement(text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.est_admin_etablissement() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mes_permissions_etab(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_get_my_role()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'INCONNU', 'etablissement_id', NULL);
  END IF;
  IF public.est_admin() THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'ADMIN_PLATEFORME', 'etablissement_id', NULL);
  END IF;
  IF EXISTS (SELECT 1 FROM public.soignants s WHERE s.id = v_uid AND s.supprime_le IS NULL) THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'SOIGNANT', 'etablissement_id', NULL);
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.admins_groupe_sante ag
    JOIN auth.users u ON u.id = ag.utilisateur_id
    WHERE ag.utilisateur_id = v_uid
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_GROUPE'
  ) THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'ADMIN_GROUPE', 'etablissement_id', NULL);
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'ADMIN_ETABLISSEMENT', 'etablissement_id', v_etab_id);
  END IF;
  RETURN jsonb_build_object('user_id', v_uid, 'role', 'INCONNU', 'etablissement_id', NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_my_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_my_role() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Tables profil : plus aucun full-row par simple relation contractuelle
-- ---------------------------------------------------------------------------

REVOKE ALL PRIVILEGES ON TABLE public.soignants FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.etablissements FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.etablissements FROM anon;

-- Les proprietaires et admins gardent les parcours existants. La projection
-- inter-profils passe exclusivement par les vues minimales ci-dessous. Les
-- UPDATE directs sont limites aux champs effectivement saisis par le client :
-- aucun score, verification, statut commercial, identifiant bancaire/Stripe
-- ou drapeau de compte test ne peut etre forge via PostgREST.
GRANT SELECT ON TABLE public.soignants TO authenticated;
GRANT UPDATE (
  telephone, types_contrat_acceptes, rayon_deplacement_km, ville_recherche,
  sms_alertes_actives, specialite_medicale, specialite_code, specialite_source,
  est_etudiant, etudiant_details, regime_fiscal, regime_fiscal_confirme,
  preference_contrat_mixte, defacto_opt_in, sms_actif, sms_consent_le,
  disponible_urgence
) ON TABLE public.soignants TO authenticated;

GRANT SELECT ON TABLE public.etablissements TO authenticated;
GRANT UPDATE (
  representant_nom, representant_prenom,
  representant_piece_s3_key, representant_piece_type_mime,
  representant_piece_type_document,
  justificatif_fonction_s3_key, justificatif_fonction_type_mime,
  justificatif_fonction_type, rib_s3_key,
  sms_actif, sms_consent_le, jour_paie_habituel
) ON TABLE public.etablissements TO authenticated;

-- Defense en profondeur pour fn_modifier_mon_profil : l'ancienne fonction
-- sait creer le profil manquant. Un compte etablissement ne doit jamais pouvoir
-- s'en servir pour se fabriquer en plus un profil soignant.
CREATE OR REPLACE FUNCTION public.fn_protect_soignant_insert_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF public.est_admin() THEN RETURN NEW; END IF;

  SELECT u.raw_app_meta_data ->> 'role' INTO v_role
  FROM auth.users u WHERE u.id = auth.uid();
  IF NEW.id IS DISTINCT FROM auth.uid() OR v_role <> 'SOIGNANT' THEN
    RAISE EXCEPTION 'Creation profil soignant interdite' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_soignant_insert_role ON public.soignants;
CREATE TRIGGER trg_protect_soignant_insert_role
  BEFORE INSERT ON public.soignants
  FOR EACH ROW EXECUTE FUNCTION public.fn_protect_soignant_insert_role();
REVOKE ALL ON FUNCTION public.fn_protect_soignant_insert_role() FROM PUBLIC, anon, authenticated;

-- Les fonctions de verification telechargent avec service_role le chemin
-- stocke sur l'etablissement. Le prefixe UUID empeche un utilisateur de leur
-- faire lire le document prive d'un autre compte en devinant sa cle Storage.
CREATE OR REPLACE FUNCTION public.fn_protect_etablissement_storage_paths()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;
  IF NOT public.fn_a_permission_etablissement('profil_etab', NEW.id) THEN
    RAISE EXCEPTION 'Permission profil etablissement requise' USING ERRCODE = '42501';
  END IF;

  IF NEW.rib_s3_key IS DISTINCT FROM OLD.rib_s3_key
     AND NEW.rib_s3_key IS NOT NULL
     AND NEW.rib_s3_key NOT LIKE NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Chemin RIB non autorise' USING ERRCODE = '42501';
  END IF;
  IF NEW.representant_piece_s3_key IS DISTINCT FROM OLD.representant_piece_s3_key
     AND NEW.representant_piece_s3_key IS NOT NULL
     AND NEW.representant_piece_s3_key NOT LIKE NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Chemin piece identite non autorise' USING ERRCODE = '42501';
  END IF;
  IF NEW.justificatif_fonction_s3_key IS DISTINCT FROM OLD.justificatif_fonction_s3_key
     AND NEW.justificatif_fonction_s3_key IS NOT NULL
     AND NEW.justificatif_fonction_s3_key NOT LIKE NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Chemin justificatif non autorise' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_etablissement_storage_paths ON public.etablissements;
CREATE TRIGGER trg_protect_etablissement_storage_paths
  BEFORE UPDATE ON public.etablissements
  FOR EACH ROW EXECUTE FUNCTION public.fn_protect_etablissement_storage_paths();
REVOKE ALL ON FUNCTION public.fn_protect_etablissement_storage_paths() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_reinitialiser_ma_profession()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants s
    WHERE s.id = v_uid AND s.supprime_le IS NULL
      AND COALESCE(s.rpps_verifie, false) = false
      AND COALESCE(s.diplome_verifie, false) = false
      AND COALESCE(s.tous_documents_valides, false) = false
  ) OR EXISTS (
    SELECT 1 FROM public.documents_soignants d
    WHERE d.soignant_id = v_uid AND d.supprime_le IS NULL
      AND d.statut_verification = 'VERIFIE'
  ) OR EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.soignant_assigne_id = v_uid
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PROFESSION_VERROUILLEE',
      'error', 'La profession est verrouillee apres verification ou attribution.'
    );
  END IF;

  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET profession = NULL,
      specialite_medicale = NULL,
      specialite_code = NULL,
      specialite_source = NULL,
      modifie_le = now()
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'MODIFICATION_PROFIL',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('champs_modifies', jsonb_build_array('profession_reinitialisee'))
  );
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_reinitialiser_ma_profession() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reinitialiser_ma_profession() TO authenticated;

DROP POLICY IF EXISTS pol_soig_select ON public.soignants;
CREATE POLICY pol_soig_select ON public.soignants
  FOR SELECT TO authenticated
  USING (
    (id = (SELECT auth.uid()) AND supprime_le IS NULL)
    OR (SELECT public.est_admin())
  );

DROP POLICY IF EXISTS pol_etab_select ON public.etablissements;
CREATE POLICY pol_etab_select ON public.etablissements
  FOR SELECT TO authenticated
  USING (
    (id = (SELECT public.mon_etablissement_id()) AND supprime_le IS NULL)
    OR (SELECT public.est_admin())
  );

DROP POLICY IF EXISTS pol_etab_update ON public.etablissements;
CREATE POLICY pol_etab_update ON public.etablissements
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.est_admin())
    OR (
      id = (SELECT public.mon_etablissement_id())
      AND supprime_le IS NULL
      AND (SELECT public.fn_a_permission_etablissement('profil_etab', id))
    )
  )
  WITH CHECK (
    (SELECT public.est_admin())
    OR (
      id = (SELECT public.mon_etablissement_id())
      AND supprime_le IS NULL
      AND (SELECT public.fn_a_permission_etablissement('profil_etab', id))
    )
  );

CREATE OR REPLACE VIEW public.vue_soignants_etablissement
WITH (security_barrier = true)
AS
SELECT
  s.id, s.prenom, s.nom,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.email END AS email,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.telephone END AS telephone,
  s.profession,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.numero_rpps END AS numero_rpps,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.type_contrat END AS type_contrat,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.type_exercice END AS type_exercice,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.score_fiabilite END AS score_fiabilite,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.total_missions_terminees END AS total_missions_terminees,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.total_missions_annulees END AS total_missions_annulees,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.total_retards_pointage END AS total_retards_pointage,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.total_absences END AS total_absences,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.tous_documents_valides END AS tous_documents_valides,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.identite_verifiee END AS identite_verifiee,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.diplome_verifie END AS diplome_verifie,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.rpps_verifie END AS rpps_verifie,
  s.avatar_url,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.bio END AS bio,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.annees_experience END AS annees_experience,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.specialites END AS specialites,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.disponible_urgence END AS disponible_urgence,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.urgence_rayon_km END AS urgence_rayon_km,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.note_moyenne END AS note_moyenne,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.nb_evaluations END AS nb_evaluations,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.est_etudiant END AS est_etudiant,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.scolarite_verifiee END AS scolarite_verifiee,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.scolarite_annee_validee END AS scolarite_annee_validee,
  CASE WHEN public.fn_a_permission_etablissement('lecture_candidatures', public.mon_etablissement_id()) THEN s.scolarite_profession_autorisee END AS scolarite_profession_autorisee,
  s.est_compte_test
FROM public.soignants s
WHERE s.supprime_le IS NULL
  AND public.fn_a_permission_etablissement('lecture', public.mon_etablissement_id())
  AND (
    EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.etablissement_id = public.mon_etablissement_id()
        AND m.soignant_assigne_id = s.id
    )
    OR EXISTS (
      SELECT 1
      FROM public.candidatures c
      JOIN public.missions m ON m.id = c.mission_id
      WHERE m.etablissement_id = public.mon_etablissement_id()
        AND c.soignant_id = s.id
    )
  );

CREATE OR REPLACE VIEW public.vue_etablissements_soignant
WITH (security_barrier = true)
AS
SELECT
  e.id, e.nom, e.siret, e.finess, e.type,
  e.adresse_rue, e.adresse_ville, e.adresse_code_postal,
  e.adresse_departement, e.adresse_lat, e.adresse_lng,
  e.email_contact, e.telephone_contact, e.convention_collective,
  e.couleur_theme, e.logo_url, e.description, e.horaires_ouverture,
  e.note_moyenne, e.nb_evaluations, e.est_secteur_public,
  e.rist_plafond_actif, e.rist_taux_base_horaire,
  e.taux_majoration_nuit_pourcent, e.taux_majoration_dimanche_pourcent,
  e.taux_majoration_ferie_pourcent, e.est_compte_test
FROM public.etablissements e
WHERE e.supprime_le IS NULL;

REVOKE ALL ON TABLE public.vue_soignants_etablissement FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.vue_etablissements_soignant FROM PUBLIC;
GRANT SELECT ON TABLE public.vue_soignants_etablissement TO authenticated;
GRANT SELECT ON TABLE public.vue_etablissements_soignant TO authenticated, anon;

COMMENT ON VIEW public.vue_soignants_etablissement IS
  'Projection minimale des soignants ayant candidate ou travaille pour l etablissement actif. Aucune donnee de sante, bancaire, GPS ou Stripe.';
COMMENT ON VIEW public.vue_etablissements_soignant IS
  'Projection publique minimale des etablissements actifs. Aucun identifiant paiement, cle Storage, resultat IA ni token.';

-- ---------------------------------------------------------------------------
-- 5. RBAC sur les mutations metier etablissement principales
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS pol_mission_insert ON public.missions;
CREATE POLICY pol_mission_insert ON public.missions
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('missions', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_mission_update ON public.missions;
CREATE POLICY pol_mission_update ON public.missions
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('missions', etablissement_id))
    )
  )
  WITH CHECK (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('missions', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_mission_select ON public.missions;
CREATE POLICY pol_mission_select ON public.missions
  FOR SELECT TO authenticated
  USING (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_missions', etablissement_id))
    )
    OR soignant_assigne_id = (SELECT auth.uid())
    OR (
      (SELECT public.est_soignant())
      AND statut = 'OUVERTE'::public.statut_mission
      AND NOT public.fn_est_exclu((SELECT auth.uid()), etablissement_id)
    )
  );

DROP POLICY IF EXISTS pol_cand_select ON public.candidatures;
CREATE POLICY pol_cand_select ON public.candidatures
  FOR SELECT TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('lecture_candidatures', m.etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_cand_insert ON public.candidatures;
CREATE POLICY pol_cand_insert ON public.candidatures
  FOR INSERT TO authenticated
  WITH CHECK (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('candidatures', m.etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_cand_update ON public.candidatures;
CREATE POLICY pol_cand_update ON public.candidatures
  FOR UPDATE TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('candidatures', m.etablissement_id))
    )
  )
  WITH CHECK (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('candidatures', m.etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_pres_select ON public.presences;
CREATE POLICY pol_pres_select ON public.presences
  FOR SELECT TO authenticated
  USING (
    (SELECT public.est_admin())
    OR soignant_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('lecture_pointage', m.etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_pres_insert ON public.presences;
CREATE POLICY pol_pres_insert ON public.presences
  FOR INSERT TO authenticated
  WITH CHECK (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('pointage', m.etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_pres_update ON public.presences;
CREATE POLICY pol_pres_update ON public.presences
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('pointage', m.etablissement_id))
    )
  )
  WITH CHECK (
    (SELECT public.est_admin())
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_id
        AND m.etablissement_id = (SELECT public.mon_etablissement_id())
        AND (SELECT public.fn_a_permission_etablissement('pointage', m.etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_contrat_select ON public.contrats_mission;
CREATE POLICY pol_contrat_select ON public.contrats_mission
  FOR SELECT TO authenticated
  USING (
    (SELECT public.est_admin())
    OR soignant_id = (SELECT auth.uid())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_contrats', etablissement_id))
    )
  );

DROP POLICY IF EXISTS ctm_insert ON public.contrats_travail_missions;
CREATE POLICY ctm_insert ON public.contrats_travail_missions
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('contrats', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_paie_soig_insert ON public.paiements_soignant;
CREATE POLICY pol_paie_soig_insert ON public.paiements_soignant
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('paiement', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_paie_soig_select ON public.paiements_soignant;
CREATE POLICY pol_paie_soig_select ON public.paiements_soignant
  FOR SELECT TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('lecture_paiement', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_paie_soig_update ON public.paiements_soignant;
CREATE POLICY pol_paie_soig_update ON public.paiements_soignant
  FOR UPDATE TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('paiement', etablissement_id))
    )
  )
  WITH CHECK (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
    OR (
      etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('paiement', etablissement_id))
    )
  );

DROP POLICY IF EXISTS pol_fav_es_insert ON public.favoris_etab_soignant;
CREATE POLICY pol_fav_es_insert ON public.favoris_etab_soignant
  FOR INSERT TO authenticated
  WITH CHECK (
    etablissement_id = (SELECT public.mon_etablissement_id())
    AND (SELECT public.fn_a_permission_etablissement('candidatures', etablissement_id))
  );

DROP POLICY IF EXISTS pol_fav_es_delete ON public.favoris_etab_soignant;
CREATE POLICY pol_fav_es_delete ON public.favoris_etab_soignant
  FOR DELETE TO authenticated
  USING (
    etablissement_id = (SELECT public.mon_etablissement_id())
      AND (SELECT public.fn_a_permission_etablissement('candidatures', etablissement_id))
  );

-- Les fonctions SECURITY DEFINER historiques contournent volontairement RLS.
-- Ce garde commun applique donc aussi le RBAC au niveau trigger : un membre
-- LECTURE_SEULE/POINTAGE_ONLY ne peut pas appeler directement une ancienne RPC
-- mutante reservee aux RH/proprietaires.
CREATE OR REPLACE FUNCTION public.fn_enforce_etablissement_rbac_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row jsonb;
  v_old_row jsonb;
  v_new_row jsonb;
  v_etab_id uuid;
  v_mission_id uuid;
  v_permission text := TG_ARGV[0];
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  -- Conserver les transitions Lot 21 protegees par
  -- fn_protect_candidature_statut. Un soignant peut repondre a sa propre
  -- proposition et la RPC peut refuser atomiquement les candidatures
  -- concurrentes, meme pour un rare compte historique aussi membre d'un etab.
  IF TG_TABLE_NAME = 'candidatures' THEN
    v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    IF v_row ->> 'soignant_id' = auth.uid()::text
       OR current_setting('jolene.candidature_rpc_mission_id', true) = v_row ->> 'mission_id' THEN
      IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
  END IF;

  -- Un soignant sans appartenance etablissement conserve ses propres RPCs.
  IF public.fn_role_etablissement_courant(NULL) IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  IF TG_OP = 'UPDATE' THEN
    v_old_row := to_jsonb(OLD);
    v_new_row := to_jsonb(NEW);
  END IF;
  IF COALESCE(v_row ->> 'etablissement_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_etab_id := (v_row ->> 'etablissement_id')::uuid;
  END IF;
  IF v_etab_id IS NULL
     AND COALESCE(v_row ->> 'mission_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_mission_id := (v_row ->> 'mission_id')::uuid;
    SELECT m.etablissement_id INTO v_etab_id
    FROM public.missions m WHERE m.id = v_mission_id;
  END IF;

  IF v_etab_id IS NOT NULL
     AND v_permission = 'missions'
     AND TG_TABLE_NAME = 'missions'
     AND TG_OP = 'UPDATE'
     AND public.fn_a_permission_etablissement('pointage', v_etab_id)
     AND (
       v_new_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) = (
       v_old_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) THEN
    RETURN NEW;
  END IF;

  IF v_etab_id IS NULL
     OR NOT public.fn_a_permission_etablissement(v_permission, v_etab_id) THEN
    RAISE EXCEPTION 'Permission etablissement % requise', v_permission
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_enforce_etablissement_rbac_trigger()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_p0_rbac_missions ON public.missions;
CREATE TRIGGER trg_p0_rbac_missions
  BEFORE INSERT OR UPDATE OR DELETE ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('missions');

DROP TRIGGER IF EXISTS trg_p0_rbac_mission_series ON public.mission_series;
CREATE TRIGGER trg_p0_rbac_mission_series
  BEFORE INSERT OR UPDATE OR DELETE ON public.mission_series
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('missions');

DROP TRIGGER IF EXISTS trg_p0_rbac_candidatures ON public.candidatures;
CREATE TRIGGER trg_p0_rbac_candidatures
  BEFORE INSERT OR UPDATE OR DELETE ON public.candidatures
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('candidatures');

DROP TRIGGER IF EXISTS trg_p0_rbac_presences ON public.presences;
CREATE TRIGGER trg_p0_rbac_presences
  BEFORE INSERT OR UPDATE OR DELETE ON public.presences
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('pointage');

DROP TRIGGER IF EXISTS trg_p0_rbac_contrats_mission ON public.contrats_mission;
CREATE TRIGGER trg_p0_rbac_contrats_mission
  BEFORE INSERT OR UPDATE OR DELETE ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('contrats');

DROP TRIGGER IF EXISTS trg_p0_rbac_contrats_travail ON public.contrats_travail_missions;
CREATE TRIGGER trg_p0_rbac_contrats_travail
  BEFORE INSERT OR UPDATE OR DELETE ON public.contrats_travail_missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('contrats');

DROP TRIGGER IF EXISTS trg_p0_rbac_paiements_soignant ON public.paiements_soignant;
CREATE TRIGGER trg_p0_rbac_paiements_soignant
  BEFORE INSERT OR UPDATE OR DELETE ON public.paiements_soignant
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('paiement');

DROP TRIGGER IF EXISTS trg_p0_rbac_factures ON public.factures;
CREATE TRIGGER trg_p0_rbac_factures
  BEFORE INSERT OR UPDATE OR DELETE ON public.factures
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('paiement');

DROP TRIGGER IF EXISTS trg_p0_rbac_partages_rib ON public.partages_rib;
CREATE TRIGGER trg_p0_rbac_partages_rib
  BEFORE UPDATE OR DELETE ON public.partages_rib
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('paiement');

DROP TRIGGER IF EXISTS trg_p0_rbac_favoris_etab ON public.favoris_etab_soignant;
CREATE TRIGGER trg_p0_rbac_favoris_etab
  BEFORE INSERT OR UPDATE OR DELETE ON public.favoris_etab_soignant
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('candidatures');

DROP TRIGGER IF EXISTS trg_p0_rbac_membres_etablissement ON public.membres_etablissement;
CREATE TRIGGER trg_p0_rbac_membres_etablissement
  BEFORE INSERT OR UPDATE OR DELETE ON public.membres_etablissement
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('gerer_equipe');

DROP TRIGGER IF EXISTS trg_p0_rbac_api_keys ON public.api_keys;
CREATE TRIGGER trg_p0_rbac_api_keys
  BEFORE INSERT OR UPDATE OR DELETE ON public.api_keys
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('api');

DROP TRIGGER IF EXISTS trg_p0_rbac_codes_secours ON public.codes_secours_mission;
CREATE TRIGGER trg_p0_rbac_codes_secours
  BEFORE INSERT OR UPDATE OR DELETE ON public.codes_secours_mission
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('pointage');

DROP TRIGGER IF EXISTS trg_p0_rbac_qr_codes ON public.qr_codes_mission;
CREATE TRIGGER trg_p0_rbac_qr_codes
  BEFORE INSERT OR UPDATE OR DELETE ON public.qr_codes_mission
  FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('pointage');

-- ---------------------------------------------------------------------------
-- 6. Revue documentaire self-service, idempotente et strictement proprietaire
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_demander_revue_document(
  p_document_id uuid,
  p_motif text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_doc public.documents_soignants%ROWTYPE;
  v_revue_id uuid;
  v_motif text := trim(COALESCE(p_motif, ''));
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_document_id IS NULL OR length(v_motif) < 10 OR length(v_motif) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
      'error', 'Le motif doit contenir entre 10 et 1000 caracteres.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_document_id::text, 0));
  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id
    AND soignant_id = v_uid
    AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DOCUMENT_INTROUVABLE');
  END IF;

  SELECT id INTO v_revue_id
  FROM public.file_revue_manuelle
  WHERE type_entite = 'TELEVERSEMENT_DOCUMENT'
    AND id_entite = p_document_id
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
  ORDER BY cree_le DESC
  LIMIT 1;

  IF v_revue_id IS NOT NULL THEN
    UPDATE public.documents_soignants
    SET statut_verification = 'REVUE_MANUELLE_REQUISE', modifie_le = now()
    WHERE id = p_document_id;
    RETURN jsonb_build_object('success', true, 'idempotent', true, 'revue_id', v_revue_id);
  END IF;

  INSERT INTO public.file_revue_manuelle (
    type_entite, id_entite, service_en_echec, motif_echec,
    donnees_originales, statut, priorite
  ) VALUES (
    'TELEVERSEMENT_DOCUMENT', p_document_id, 'REVUE_DEMANDEE_PAR_SOIGNANT', v_motif,
    jsonb_build_object(
      'soignant_id', v_uid,
      'type_document', v_doc.type_document::text,
      'ancien_statut', v_doc.statut_verification::text,
      'demande_le', now()
    ),
    'EN_ATTENTE', 3
  ) RETURNING id INTO v_revue_id;

  UPDATE public.documents_soignants
  SET statut_verification = 'REVUE_MANUELLE_REQUISE',
      verifie_par = NULL, verifie_le = NULL, motif_rejet = NULL,
      modifie_le = now()
  WHERE id = p_document_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'DOCUMENT_REVUE_MANUELLE_DEMANDEE',
    p_type_ressource := 'document_soignant',
    p_id_ressource := p_document_id,
    p_details := jsonb_build_object('revue_id', v_revue_id, 'motif', v_motif)
  );

  RETURN jsonb_build_object('success', true, 'idempotent', false, 'revue_id', v_revue_id);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_demander_revue_document(uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_demander_revue_document(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. Retention GPS unique : anonymisation complete a 90 jours
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_purger_gps_ancien()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.presences
  SET arrivee_lat = NULL,
      arrivee_lng = NULL,
      depart_lat = NULL,
      depart_lng = NULL,
      arrivee_precision_gps_m = NULL,
      depart_precision_gps_m = NULL,
      arrivee_ip = NULL,
      depart_ip = NULL,
      arrivee_id_terminal = NULL,
      depart_id_terminal = NULL,
      arrivee_modele_terminal = NULL,
      depart_modele_terminal = NULL
  WHERE COALESCE(pointage_depart_le, pointage_arrivee_le, cree_le) < now() - interval '90 days'
    AND (
      arrivee_lat IS NOT NULL OR arrivee_lng IS NOT NULL
      OR depart_lat IS NOT NULL OR depart_lng IS NOT NULL
      OR arrivee_precision_gps_m IS NOT NULL OR depart_precision_gps_m IS NOT NULL
      OR arrivee_ip IS NOT NULL OR depart_ip IS NOT NULL
      OR arrivee_id_terminal IS NOT NULL OR depart_id_terminal IS NOT NULL
      OR arrivee_modele_terminal IS NOT NULL OR depart_modele_terminal IS NOT NULL
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_purger_gps_ancien() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_purger_gps_ancien() TO service_role;

-- ---------------------------------------------------------------------------
-- 8. Endpoints destructifs internes et calendrier idempotent
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.fn_purger_demo() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_purger_demo() TO service_role;

REVOKE ALL ON FUNCTION public.fn_admin_invocations_purge() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_invocations_purge() TO service_role;

-- Serialise chaque compteur par (action, cle). L'ancienne implementation
-- pouvait creer deux compteurs concurrents et laisser passer une rafale entre
-- plusieurs instances Edge.
CREATE OR REPLACE FUNCTION public.fn_verifier_rate_limit(
  p_cle text,
  p_action text,
  p_max_tentatives integer DEFAULT 10,
  p_fenetre_secondes integer DEFAULT 60
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_fenetre_debut timestamptz;
  v_id uuid;
  v_total integer;
  v_premiere timestamptz;
BEGIN
  IF p_cle IS NULL OR length(p_cle) < 1 OR length(p_cle) > 256
     OR p_action IS NULL OR p_action !~ '^[a-zA-Z0-9_:-]{1,100}$'
     OR p_max_tentatives < 1 OR p_max_tentatives > 100000
     OR p_fenetre_secondes < 1 OR p_fenetre_secondes > 31536000 THEN
    RETURN false;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_action || ':' || p_cle, 0));
  v_fenetre_debut := now() - make_interval(secs => p_fenetre_secondes);

  DELETE FROM public.rate_limits
  WHERE cle = p_cle AND action = p_action
    AND premiere_tentative < v_fenetre_debut;

  SELECT
    (array_agg(id ORDER BY premiere_tentative, id))[1],
    COALESCE(sum(tentatives), 0)::integer,
    min(premiere_tentative)
  INTO v_id, v_total, v_premiere
  FROM public.rate_limits
  WHERE cle = p_cle AND action = p_action
    AND premiere_tentative >= v_fenetre_debut;

  IF v_id IS NULL THEN
    INSERT INTO public.rate_limits(cle, action, tentatives, premiere_tentative, derniere_tentative)
    VALUES (p_cle, p_action, 1, now(), now());
    RETURN true;
  END IF;

  -- Consolide aussi d'eventuels doublons crees avant ce correctif.
  DELETE FROM public.rate_limits
  WHERE cle = p_cle AND action = p_action AND id <> v_id;

  IF v_total >= p_max_tentatives THEN
    UPDATE public.rate_limits
    SET tentatives = v_total, premiere_tentative = v_premiere,
        derniere_tentative = now()
    WHERE id = v_id;
    RETURN false;
  END IF;

  UPDATE public.rate_limits
  SET tentatives = v_total + 1, premiere_tentative = v_premiere,
      derniere_tentative = now()
  WHERE id = v_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_verifier_rate_limit(text, text, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verifier_rate_limit(text, text, integer, integer)
  TO service_role;

-- Le code calendar-sync utilise ON CONFLICT(connection_id, mission_id).
-- Conserver une seule ligne technique par paire avant de poser l'unicite.
DELETE FROM public.calendar_events_sync a
USING public.calendar_events_sync b
WHERE a.connection_id = b.connection_id
  AND a.mission_id = b.mission_id
  AND a.id > b.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_calendar_events_sync_connection_mission
  ON public.calendar_events_sync(connection_id, mission_id);

-- Un token push identifie une installation/appareil, pas un couple
-- (utilisateur, appareil). Conserver plusieurs proprietaires en parallele peut
-- envoyer la notification du nouveau compte a l'ancien compte de l'appareil.
WITH classes AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY token
      ORDER BY actif DESC NULLS LAST, derniere_utilisation DESC NULLS LAST,
               cree_le DESC NULLS LAST, id DESC
    ) AS rang
  FROM public.tokens_push
)
DELETE FROM public.tokens_push t
USING classes c
WHERE t.id = c.id AND c.rang > 1;

ALTER TABLE public.tokens_push
  DROP CONSTRAINT IF EXISTS tokens_push_utilisateur_id_token_key;
ALTER TABLE public.tokens_push
  DROP CONSTRAINT IF EXISTS tokens_push_token_key;
ALTER TABLE public.tokens_push
  ADD CONSTRAINT tokens_push_token_key UNIQUE (token);

CREATE OR REPLACE FUNCTION public.fn_upsert_token_push(
  p_token text,
  p_plateforme text DEFAULT 'WEB'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_token text := trim(COALESCE(p_token, ''));
  v_plateforme text := upper(trim(COALESCE(p_plateforme, '')));
  v_json jsonb;
  v_endpoint text;
  v_p256dh text;
  v_auth_key text;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Non authentifie' USING ERRCODE = '42501';
  END IF;
  IF length(v_token) < 16 OR length(v_token) > 4096 THEN
    RAISE EXCEPTION 'Token push invalide' USING ERRCODE = '22023';
  END IF;
  IF v_plateforme NOT IN ('WEB', 'IOS', 'ANDROID') THEN
    RAISE EXCEPTION 'Plateforme push invalide' USING ERRCODE = '22023';
  END IF;

  -- Une subscription PushManager reste du Web Push meme si le user-agent est
  -- Safari iOS/Chrome Android et que l'ancien client l'etiquette IOS/ANDROID.
  IF left(v_token, 1) = '{' THEN
    v_plateforme := 'WEB';
    BEGIN
      v_json := v_token::jsonb;
      v_endpoint := NULLIF(trim(v_json ->> 'endpoint'), '');
      v_p256dh := NULLIF(trim(v_json -> 'keys' ->> 'p256dh'), '');
      v_auth_key := NULLIF(trim(v_json -> 'keys' ->> 'auth'), '');
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Abonnement Web Push JSON invalide' USING ERRCODE = '22023';
    END;
    -- Allowlist fournisseur stricte : cet endpoint sera appele depuis l'Edge
    -- Function. Autoriser une URL HTTPS arbitraire creerait un SSRF aveugle.
    -- L'ancrage impose aussi l'absence de userinfo et de port explicite.
    IF v_endpoint IS NULL
       OR length(v_endpoint) > 2048
       OR v_endpoint !~* '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|([a-z0-9-]+[.])+push[.]apple[.]com|([a-z0-9-]+[.])*notify[.]windows[.]com)(/|$)'
       OR v_p256dh IS NULL OR length(v_p256dh) > 512
       OR v_auth_key IS NULL OR length(v_auth_key) > 512 THEN
      RAISE EXCEPTION 'Abonnement Web Push incomplet' USING ERRCODE = '22023';
    END IF;
  ELSIF v_plateforme = 'WEB' THEN
    RAISE EXCEPTION 'Abonnement Web Push JSON requis' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.tokens_push(
    utilisateur_id, token, plateforme, endpoint, p256dh, auth_key,
    actif, derniere_utilisation
  ) VALUES (
    v_uid, v_token, v_plateforme, v_endpoint, v_p256dh, v_auth_key,
    true, now()
  )
  ON CONFLICT (token) DO UPDATE SET
    utilisateur_id = EXCLUDED.utilisateur_id,
    plateforme = EXCLUDED.plateforme,
    endpoint = EXCLUDED.endpoint,
    p256dh = EXCLUDED.p256dh,
    auth_key = EXCLUDED.auth_key,
    actif = true,
    derniere_utilisation = now();
END;
$$;

REVOKE ALL ON FUNCTION public.fn_upsert_token_push(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_upsert_token_push(text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_desactiver_mon_token_push(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_token text := trim(COALESCE(p_token, ''));
  v_endpoint text;
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifie');
  END IF;
  IF length(v_token) < 16 OR length(v_token) > 4096 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token push invalide');
  END IF;

  -- JSON.stringify(PushSubscription) est normalement stable. L'endpoint sert
  -- de repli pour les navigateurs qui reordonnent les cles JSON entre deux
  -- lectures, toujours dans le perimetre strict auth.uid().
  IF left(v_token, 1) = '{' THEN
    BEGIN
      v_endpoint := NULLIF(trim((v_token::jsonb) ->> 'endpoint'), '');
    EXCEPTION WHEN OTHERS THEN
      v_endpoint := NULL;
    END;
  END IF;

  UPDATE public.tokens_push
  SET actif = false,
      derniere_utilisation = now()
  WHERE utilisateur_id = v_uid
    AND (
      token = v_token
      OR (v_endpoint IS NOT NULL AND endpoint = v_endpoint)
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'tokens_desactives', v_count,
    'scope', 'CURRENT_DEVICE'
  );
END;
$$;

-- Les anciennes versions appelaient cette RPC sans identifiant d'appareil et
-- supprimaient tous les tokens du compte. Elles peuvent encore se deconnecter,
-- mais ne peuvent plus couper les notifications des autres installations.
REVOKE ALL ON FUNCTION public.fn_supprimer_mes_tokens_push() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_supprimer_mes_tokens_push() TO service_role;
REVOKE ALL ON FUNCTION public.fn_desactiver_mon_token_push(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_desactiver_mon_token_push(text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8b. File anti-fraude pointage : source et effets alignes avec l'admin
-- ---------------------------------------------------------------------------

-- fn_detecter_teleportations journalise l'evenement. Ce miroir cree la ligne
-- alertes_systeme effectivement lue par fn_admin_lister/resume. Le verrou par
-- presence rend la creation idempotente sans supprimer l'historique existant.
CREATE OR REPLACE FUNCTION public.fn_mirror_teleportation_alerte_systeme()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_presence_id uuid;
BEGIN
  IF NEW.action <> 'SYSTEM'
     OR COALESCE(NEW.details ->> 'evenement', '') <> 'TELEPORTATION_DETECTED' THEN
    RETURN NEW;
  END IF;

  v_presence_id := COALESCE(
    CASE WHEN COALESCE(NEW.details ->> 'presence_id_destination', '')
                   ~ '^[0-9a-fA-F-]{36}$'
         THEN (NEW.details ->> 'presence_id_destination')::uuid END,
    CASE WHEN NEW.type_ressource = 'presence' THEN NEW.id_ressource END
  );
  IF v_presence_id IS NULL THEN RETURN NEW; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('teleportation:' || v_presence_id::text, 0));
  IF NOT EXISTS (
    SELECT 1 FROM public.alertes_systeme a
    WHERE a.type_alerte = 'TELEPORTATION_DETECTED'
      AND COALESCE(
        a.details ->> 'presence_id_destination',
        a.details ->> 'presence_id'
      ) = v_presence_id::text
  ) THEN
    INSERT INTO public.alertes_systeme(
      type_alerte, severite, source, message, details
    ) VALUES (
      'TELEPORTATION_DETECTED',
      'CRITICAL',
      'fn_detecter_teleportations',
      format('Teleportation GPS detectee pour la presence %s.', v_presence_id),
      COALESCE(NEW.details, '{}'::jsonb) || jsonb_build_object(
        'presence_id_destination', v_presence_id,
        'journal_audit_id', NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mirror_teleportation_alerte_systeme ON public.journaux_audit;
CREATE TRIGGER trg_mirror_teleportation_alerte_systeme
  AFTER INSERT ON public.journaux_audit
  FOR EACH ROW EXECUTE FUNCTION public.fn_mirror_teleportation_alerte_systeme();
REVOKE ALL ON FUNCTION public.fn_mirror_teleportation_alerte_systeme()
  FROM PUBLIC, anon, authenticated;

-- Backfill non destructif : rend visibles dans la file les detections deja
-- journalisees avant l'installation du trigger, sans doubler une alerte.
INSERT INTO public.alertes_systeme(type_alerte, severite, source, message, details)
SELECT
  'TELEPORTATION_DETECTED', 'CRITICAL', 'fn_detecter_teleportations',
  format('Teleportation GPS detectee pour la presence %s.', ja.id_ressource),
  COALESCE(ja.details, '{}'::jsonb) || jsonb_build_object(
    'presence_id_destination', ja.id_ressource,
    'journal_audit_id', ja.id
  )
FROM public.journaux_audit ja
WHERE ja.action = 'SYSTEM'
  AND ja.details ->> 'evenement' = 'TELEPORTATION_DETECTED'
  AND ja.type_ressource = 'presence'
  AND ja.id_ressource IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.alertes_systeme a
    WHERE a.type_alerte = 'TELEPORTATION_DETECTED'
      AND COALESCE(
        a.details ->> 'presence_id_destination',
        a.details ->> 'presence_id'
      ) = ja.id_ressource::text
  );

CREATE OR REPLACE FUNCTION public.fn_admin_traiter_alerte_pointage(
  p_alerte_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_alerte public.alertes_systeme%ROWTYPE;
  v_motif text := trim(COALESCE(p_motif, ''));
  v_revue_id uuid;
  v_soignant_id uuid;
  v_notifications integer := 0;
  v_effet text := 'ALERTE_FERMEE';
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;
  IF p_decision NOT IN (
    'LEGITIME', 'FRAUDE_AVERTISSEMENT',
    'FRAUDE_SUSPENSION_PROPOSEE', 'IGNORER'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DECISION_INVALIDE');
  END IF;
  IF length(v_motif) < 10 OR length(v_motif) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'MOTIF_INVALIDE',
      'error', 'Le motif doit contenir entre 10 et 1000 caracteres.'
    );
  END IF;

  SELECT * INTO v_alerte
  FROM public.alertes_systeme
  WHERE id = p_alerte_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ALERTE_INTROUVABLE');
  END IF;
  IF v_alerte.type_alerte NOT IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_ALERTE_INVALIDE');
  END IF;
  IF v_alerte.resolu_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ALERTE_DEJA_TRAITEE');
  END IF;

  IF COALESCE(v_alerte.details ->> 'soignant_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_soignant_id := (v_alerte.details ->> 'soignant_id')::uuid;
  END IF;

  IF p_decision = 'FRAUDE_SUSPENSION_PROPOSEE' THEN
    SELECT f.id INTO v_revue_id
    FROM public.file_revue_manuelle f
    WHERE f.type_entite = 'ALERTE_FRAUDE'
      AND f.id_entite = p_alerte_id
      AND f.service_en_echec = 'ADMIN_SUSPENSION_REVIEW'
      AND f.statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
    ORDER BY f.cree_le DESC
    LIMIT 1;

    IF v_revue_id IS NULL THEN
      INSERT INTO public.file_revue_manuelle(
        type_entite, id_entite, service_en_echec, motif_echec,
        donnees_originales, statut, priorite, expire_le
      ) VALUES (
        'ALERTE_FRAUDE', p_alerte_id, 'ADMIN_SUSPENSION_REVIEW', v_motif,
        jsonb_build_object(
          'alerte_id', p_alerte_id,
          'type_alerte', v_alerte.type_alerte,
          'soignant_id', v_soignant_id,
          'propose_par', v_uid,
          'propose_le', now(),
          'details_alerte', v_alerte.details
        ),
        'EN_ATTENTE', 5, now() + interval '7 days'
      ) RETURNING id INTO v_revue_id;
    END IF;

    INSERT INTO public.notifications(
      destinataire_id, type_destinataire, type, titre, corps,
      lien, type_ressource, id_ressource
    )
    SELECT
      a.id, 'ADMIN', 'SYSTEM', 'Suspension a revoir',
      'Une proposition de suspension anti-fraude requiert une seconde validation.',
      '/admin/alertes-pointage', 'file_revue_manuelle', v_revue_id
    FROM public.fn_list_admin_user_ids() AS a(id)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.destinataire_id = a.id
        AND n.type = 'SYSTEM'
        AND n.type_ressource = 'file_revue_manuelle'
        AND n.id_ressource = v_revue_id
    );
    GET DIAGNOSTICS v_notifications = ROW_COUNT;
    v_effet := 'SUSPENSION_REVIEW_CREATED';
  ELSIF p_decision = 'FRAUDE_AVERTISSEMENT' THEN
    v_effet := 'AVERTISSEMENT_A_PREPARER_ENREGISTRE';
  END IF;

  UPDATE public.alertes_systeme
  SET resolu_le = now(),
      details = COALESCE(details, '{}'::jsonb) || jsonb_build_object(
        'decision_admin', p_decision,
        'motif_admin', v_motif,
        'traite_par', v_uid,
        'traite_le', now(),
        'revue_suspension_id', v_revue_id
      )
  WHERE id = p_alerte_id;

  INSERT INTO public.journaux_audit(
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'alerte_systeme', p_alerte_id,
    jsonb_build_object(
      'evenement', 'ALERTE_POINTAGE_TRAITEE',
      'decision', p_decision,
      'motif', v_motif,
      'type_alerte', v_alerte.type_alerte,
      'effet', v_effet,
      'revue_suspension_id', v_revue_id,
      'notifications_admin', v_notifications
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'decision', p_decision,
    'effect', v_effet,
    'review_task_id', v_revue_id,
    'admin_notifications_created', v_notifications,
    'automatic_suspension', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_traiter_alerte_pointage(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_traiter_alerte_pointage(uuid, text, text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9. API REST : secret obligatoire, aucun secret lisible apres creation
-- ---------------------------------------------------------------------------

-- Neutralise les secrets historiques en clair sans detruire les cles. Le hash
-- existant (SHA-256 ou bcrypt historique) est conserve; sinon il est cree.
ALTER TABLE public.api_keys DISABLE TRIGGER trg_protect_api_key_secrets;
UPDATE public.api_keys
SET cle_secret_hash = COALESCE(cle_secret_hash, public._sha256_hex(cle_secret)),
    cle_secret = NULL
WHERE cle_secret IS NOT NULL;
ALTER TABLE public.api_keys ENABLE TRIGGER trg_protect_api_key_secrets;

CREATE OR REPLACE FUNCTION public.fn_creer_api_key(
  p_nom text,
  p_permissions text[],
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := public.est_admin();
  v_etab_id uuid;
  v_cle_api text;
  v_cle_secret text;
  v_id uuid;
  v_allowed text[] := ARRAY['missions:read','missions:write','presences:read','factures:read'];
BEGIN
  IF v_actor IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('error', 'Non authentifie');
  END IF;

  IF v_is_admin THEN
    -- Une cle globale etablissement_id=NULL etait inutilisable mais surtout
    -- dangereuse en cas d'oubli d'un filtre multi-tenant.
    v_etab_id := p_etablissement_id;
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Un etablissement est obligatoire pour chaque cle API');
    END IF;
  ELSE
    v_etab_id := public.mon_etablissement_id();
    IF v_etab_id IS NULL
       OR NOT public.fn_a_permission_etablissement('api', v_etab_id)
       OR (p_etablissement_id IS NOT NULL AND p_etablissement_id <> v_etab_id) THEN
      RETURN jsonb_build_object('error', 'Acces refuse');
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.etablissements e WHERE e.id = v_etab_id AND e.supprime_le IS NULL) THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;
  IF p_nom IS NULL OR length(trim(p_nom)) < 2 OR length(trim(p_nom)) > 100 THEN
    RETURN jsonb_build_object('error', 'Nom invalide (2 a 100 caracteres)');
  END IF;
  IF p_permissions IS NULL OR cardinality(p_permissions) = 0
     OR NOT (p_permissions <@ v_allowed) THEN
    RETURN jsonb_build_object('error', 'Permissions invalides');
  END IF;

  v_cle_api := 'sd_live_' || encode(extensions.gen_random_bytes(24), 'hex');
  v_cle_secret := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.api_keys (
    nom, cle_api, cle_secret, cle_secret_hash, permissions,
    etablissement_id, groupe_sante_id, actif
  ) VALUES (
    trim(p_nom), v_cle_api, NULL, public._sha256_hex(v_cle_secret),
    ARRAY(SELECT DISTINCT unnest(p_permissions)), v_etab_id, NULL, true
  ) RETURNING id INTO v_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_actor,
    p_type_acteur := CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'API_KEY_CREEE',
    p_type_ressource := 'api_key',
    p_id_ressource := v_id,
    p_details := jsonb_build_object('nom', trim(p_nom), 'permissions', p_permissions, 'etablissement_id', v_etab_id)
  );

  -- Le secret en clair n'est ni stocke ni relisible. C'est son unique affichage.
  RETURN jsonb_build_object('id', v_id, 'cle_api', v_cle_api, 'cle_secret', v_cle_secret);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_lister_api_keys(
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_is_admin boolean := public.est_admin();
  v_etab_id uuid;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifie');
  END IF;

  IF v_is_admin THEN
    v_etab_id := p_etablissement_id;
  ELSE
    v_etab_id := public.mon_etablissement_id();
    IF v_etab_id IS NULL OR NOT public.fn_a_permission_etablissement('api', v_etab_id)
       OR (p_etablissement_id IS NOT NULL AND p_etablissement_id <> v_etab_id) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Acces refuse');
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', k.id,
    'nom', k.nom,
    'cle_api', k.cle_api,
    'permissions', k.permissions,
    'etablissement_id', k.etablissement_id,
    'groupe_sante_id', k.groupe_sante_id,
    'actif', k.actif,
    'derniere_utilisation', k.derniere_utilisation,
    'cree_le', k.cree_le,
    'expire_le', k.expire_le,
    'secret_configure', k.cle_secret_hash IS NOT NULL
  ) ORDER BY k.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM public.api_keys k
  WHERE v_etab_id IS NULL OR k.etablissement_id = v_etab_id;

  RETURN jsonb_build_object('success', true, 'keys', v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_verifier_api_key(p_cle_api text, p_cle_secret text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  v_key public.api_keys%ROWTYPE;
  v_valid boolean := false;
BEGIN
  IF p_cle_api IS NULL OR p_cle_secret IS NULL OR length(p_cle_secret) > 256 THEN
    RETURN jsonb_build_object('valid', false);
  END IF;
  SELECT * INTO v_key
  FROM public.api_keys
  WHERE cle_api = p_cle_api
    AND actif = true
    AND (expire_le IS NULL OR expire_le > now())
  LIMIT 1;
  IF NOT FOUND OR v_key.etablissement_id IS NULL OR v_key.cle_secret_hash IS NULL THEN
    RETURN jsonb_build_object('valid', false);
  END IF;

  IF v_key.cle_secret_hash ~ '^[0-9a-fA-F]{64}$' THEN
    v_valid := lower(v_key.cle_secret_hash) = public._sha256_hex(p_cle_secret);
  ELSIF v_key.cle_secret_hash LIKE '$2%' THEN
    v_valid := v_key.cle_secret_hash = extensions.crypt(p_cle_secret, v_key.cle_secret_hash);
  END IF;
  IF NOT v_valid THEN RETURN jsonb_build_object('valid', false); END IF;

  UPDATE public.api_keys SET derniere_utilisation = now() WHERE id = v_key.id;
  RETURN jsonb_build_object(
    'valid', true,
    'id', v_key.id,
    'etablissement_id', v_key.etablissement_id,
    'groupe_sante_id', v_key.groupe_sante_id,
    'permissions', v_key.permissions
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_revoquer_api_key(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := public.est_admin();
  v_target public.api_keys%ROWTYPE;
BEGIN
  SELECT * INTO v_target FROM public.api_keys WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Cle introuvable'); END IF;
  IF NOT v_is_admin AND (
    v_target.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
    OR NOT public.fn_a_permission_etablissement('api', v_target.etablissement_id)
  ) THEN RETURN jsonb_build_object('error', 'Acces refuse'); END IF;

  UPDATE public.api_keys SET actif = false WHERE id = p_id;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_actor,
    p_type_acteur := CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'API_KEY_REVOQUEE', p_type_ressource := 'api_key', p_id_ressource := p_id,
    p_details := jsonb_build_object('id', p_id)
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_supprimer_api_key(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := public.est_admin();
  v_target public.api_keys%ROWTYPE;
BEGIN
  SELECT * INTO v_target FROM public.api_keys WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Cle introuvable'); END IF;
  IF NOT v_is_admin AND (
    v_target.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
    OR NOT public.fn_a_permission_etablissement('api', v_target.etablissement_id)
  ) THEN RETURN jsonb_build_object('error', 'Acces refuse'); END IF;

  DELETE FROM public.api_keys WHERE id = p_id;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_actor,
    p_type_acteur := CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'API_KEY_SUPPRIMEE', p_type_ressource := 'api_key', p_id_ressource := p_id,
    p_details := jsonb_build_object('id', p_id, 'nom', v_target.nom)
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Plus aucun SELECT direct : meme un admin passe par fn_lister_api_keys, qui
-- n'expose ni cle_secret_hash ni l'ancienne colonne cle_secret.
REVOKE ALL PRIVILEGES ON TABLE public.api_keys FROM authenticated, anon;

REVOKE ALL ON FUNCTION public.fn_creer_api_key(text, text[], uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_lister_api_keys(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_revoquer_api_key(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_supprimer_api_key(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_verifier_api_key(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_creer_api_key(text, text[], uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_lister_api_keys(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_revoquer_api_key(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_supprimer_api_key(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_verifier_api_key(text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 10. Universal Links : domaine canonique servi sans redirection
-- ---------------------------------------------------------------------------

-- app.jolene.app redirige vers jolene.app et ne peut donc pas servir son AASA
-- sans 3xx. Recompile uniquement les fonctions publiques qui embarquent encore
-- cet ancien host; CREATE OR REPLACE conserve proprietaire et privileges.
DO $canonical_universal_links$
DECLARE
  r record;
  v_definition text;
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.prosrc LIKE '%https://app.jolene.app%'
  LOOP
    v_definition := pg_get_functiondef(r.oid);
    EXECUTE replace(
      v_definition,
      'https://app.jolene.app',
      'https://jolene.app'
    );
  END LOOP;
END;
$canonical_universal_links$;

-- Les actions asynchrones deja en file profitent du meme correctif avant leur
-- prochain retry; aucune donnee metier ou donnee de demonstration n'est retiree.
UPDATE public.externalisation_actions
SET payload = replace(
  payload::text,
  'https://app.jolene.app',
  'https://jolene.app'
)::jsonb
WHERE statut IN ('PENDING', 'ERROR')
  AND payload::text LIKE '%https://app.jolene.app%';
