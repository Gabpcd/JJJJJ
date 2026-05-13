-- ============================================================================
-- Sprint 5.7 PR 1 — Gestion équipe étab multi-utilisateurs (P0-5)
-- ============================================================================
-- Permet à un compte étab d'avoir plusieurs utilisateurs avec rôles distincts.
-- Fix P0-5 audit Sprint 5.
--
-- Rôles :
--  - PROPRIETAIRE : tout (création mission, paiement, équipe, profil, suppression)
--  - ADMIN_GROUPE : tout sauf gestion équipe + suppression compte
--  - RH          : missions, candidatures, contrats, pointage, RH (pas profil étab ni paiement)
--  - POINTAGE_ONLY : pointage uniquement (validation présences, codes secours, QR)
--  - LECTURE_SEULE : consultations sans actions
-- ============================================================================

-- 1. Table membres_etablissement
CREATE TABLE IF NOT EXISTS public.membres_etablissement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE')),
  invite_par uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  invite_le timestamptz,
  accepte_le timestamptz NOT NULL DEFAULT now(),
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now(),
  UNIQUE (etablissement_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_membres_etab_user ON public.membres_etablissement(user_id) WHERE actif = true;
CREATE INDEX IF NOT EXISTS idx_membres_etab_etab ON public.membres_etablissement(etablissement_id) WHERE actif = true;

ALTER TABLE public.membres_etablissement ENABLE ROW LEVEL SECURITY;

-- RLS : un user peut voir les membres de l'étab où il est membre actif
DROP POLICY IF EXISTS pol_membres_etab_select ON public.membres_etablissement;
CREATE POLICY pol_membres_etab_select ON public.membres_etablissement
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.membres_etablissement m
      WHERE m.etablissement_id = membres_etablissement.etablissement_id
        AND m.user_id = auth.uid()
        AND m.actif = true
    )
    OR public.est_admin()
  );

-- Writes uniquement via RPC sécurisées
DROP POLICY IF EXISTS pol_membres_etab_deny_write ON public.membres_etablissement;
CREATE POLICY pol_membres_etab_deny_write ON public.membres_etablissement
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- 2. Table invitations_etablissement
CREATE TABLE IF NOT EXISTS public.invitations_etablissement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  email_invite text NOT NULL,
  role_propose text NOT NULL CHECK (role_propose IN ('ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE')),
  token text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(24), 'hex'),
  expire_le timestamptz NOT NULL DEFAULT (now() + INTERVAL '7 days'),
  statut text NOT NULL DEFAULT 'EN_ATTENTE'
    CHECK (statut IN ('EN_ATTENTE', 'ACCEPTEE', 'EXPIREE', 'ANNULEE')),
  invite_par uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invite_le timestamptz NOT NULL DEFAULT now(),
  acceptee_le timestamptz,
  acceptee_par_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  cree_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invitations_etab_token ON public.invitations_etablissement(token) WHERE statut = 'EN_ATTENTE';
CREATE INDEX IF NOT EXISTS idx_invitations_etab_email ON public.invitations_etablissement(email_invite, statut);
CREATE INDEX IF NOT EXISTS idx_invitations_etab_etab ON public.invitations_etablissement(etablissement_id, statut);

ALTER TABLE public.invitations_etablissement ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_invitations_etab_select ON public.invitations_etablissement;
CREATE POLICY pol_invitations_etab_select ON public.invitations_etablissement
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.membres_etablissement m
      WHERE m.etablissement_id = invitations_etablissement.etablissement_id
        AND m.user_id = auth.uid()
        AND m.actif = true
        AND m.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    )
    OR invite_par = auth.uid()
    OR public.est_admin()
  );

DROP POLICY IF EXISTS pol_invitations_etab_deny_write ON public.invitations_etablissement;
CREATE POLICY pol_invitations_etab_deny_write ON public.invitations_etablissement
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- 3. Helper : récupérer le rôle du user pour un établissement
CREATE OR REPLACE FUNCTION public.fn_mes_permissions_etab(p_etablissement_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_role text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'role', NULL);
  END IF;

  v_etab_id := COALESCE(p_etablissement_id, public.mon_etablissement_id());

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'permissions', '{}'::jsonb);
  END IF;

  SELECT role INTO v_role
  FROM public.membres_etablissement
  WHERE etablissement_id = v_etab_id
    AND user_id = v_uid
    AND actif = true
  LIMIT 1;

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('success', true, 'role', NULL, 'permissions', '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'permissions', jsonb_build_object(
      'gerer_equipe', v_role = 'PROPRIETAIRE',
      'supprimer_compte', v_role = 'PROPRIETAIRE',
      'profil_etab', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE'),
      'paiement', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE'),
      'missions', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'candidatures', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'contrats', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'pointage', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY'),
      'rh', v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH'),
      'lecture', v_role IS NOT NULL
    )
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_mes_permissions_etab(uuid) TO authenticated;

-- 4. RPC : inviter un membre
CREATE OR REPLACE FUNCTION public.fn_inviter_membre_etab(
  p_email text,
  p_role text,
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_invitation_id uuid;
  v_token text;
  v_perms jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_role NOT IN ('ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ROLE_INVALIDE');
  END IF;

  IF p_email IS NULL OR length(trim(p_email)) = 0 OR p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EMAIL_INVALIDE');
  END IF;

  v_etab_id := COALESCE(p_etablissement_id, public.mon_etablissement_id());

  -- Vérif autorisation : seul PROPRIETAIRE peut inviter
  SELECT public.fn_mes_permissions_etab(v_etab_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Seul un PROPRIETAIRE peut inviter des membres');
  END IF;

  -- Pas déjà membre actif
  IF EXISTS (
    SELECT 1 FROM public.membres_etablissement m
    JOIN auth.users u ON u.id = m.user_id
    WHERE m.etablissement_id = v_etab_id
      AND lower(u.email) = lower(trim(p_email))
      AND m.actif = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_MEMBRE');
  END IF;

  -- Pas déjà invité en attente
  IF EXISTS (
    SELECT 1 FROM public.invitations_etablissement
    WHERE etablissement_id = v_etab_id
      AND lower(email_invite) = lower(trim(p_email))
      AND statut = 'EN_ATTENTE'
      AND expire_le > now()
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_DEJA_EN_ATTENTE');
  END IF;

  INSERT INTO public.invitations_etablissement (
    etablissement_id, email_invite, role_propose, invite_par
  ) VALUES (
    v_etab_id, lower(trim(p_email)), p_role, v_uid
  )
  RETURNING id, token INTO v_invitation_id, v_token;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'invitation_etab', v_invitation_id,
    jsonb_build_object(
      'evenement', 'INVITATION_MEMBRE_CREEE',
      'email', lower(trim(p_email)),
      'role', p_role,
      'etablissement_id', v_etab_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'invitation_id', v_invitation_id,
    'token', v_token,
    'expire_le', (now() + INTERVAL '7 days')
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_inviter_membre_etab(text, text, uuid) TO authenticated;

-- 5. RPC : accepter invitation
CREATE OR REPLACE FUNCTION public.fn_accepter_invitation_membre(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_invitation RECORD;
  v_membre_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_invitation
  FROM public.invitations_etablissement
  WHERE token = p_token
  LIMIT 1;

  IF v_invitation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TOKEN_INVALIDE');
  END IF;

  IF v_invitation.statut != 'EN_ATTENTE' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_TRAITEE');
  END IF;

  IF v_invitation.expire_le < now() THEN
    UPDATE public.invitations_etablissement SET statut = 'EXPIREE' WHERE id = v_invitation.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_EXPIREE');
  END IF;

  -- Optionnel : vérifier que l'email du user correspond à l'invitation
  IF lower(COALESCE((SELECT email FROM auth.users WHERE id = v_uid), '')) != lower(v_invitation.email_invite) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EMAIL_INCORRECT',
                                'error', 'Cette invitation est pour une autre adresse e-mail');
  END IF;

  -- Créer le membre (upsert au cas où réactivation)
  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, invite_par, invite_le, accepte_le, actif
  ) VALUES (
    v_invitation.etablissement_id, v_uid, v_invitation.role_propose,
    v_invitation.invite_par, v_invitation.invite_le, now(), true
  )
  ON CONFLICT (etablissement_id, user_id) DO UPDATE SET
    role = EXCLUDED.role,
    actif = true,
    accepte_le = now(),
    maj_le = now()
  RETURNING id INTO v_membre_id;

  -- Marquer invitation comme acceptée
  UPDATE public.invitations_etablissement SET
    statut = 'ACCEPTEE',
    acceptee_le = now(),
    acceptee_par_user_id = v_uid
  WHERE id = v_invitation.id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', v_membre_id,
    jsonb_build_object(
      'evenement', 'INVITATION_MEMBRE_ACCEPTEE',
      'invitation_id', v_invitation.id,
      'etablissement_id', v_invitation.etablissement_id,
      'role', v_invitation.role_propose
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'membre_id', v_membre_id,
    'etablissement_id', v_invitation.etablissement_id,
    'role', v_invitation.role_propose
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_accepter_invitation_membre(text) TO authenticated;

-- 6. RPC : modifier rôle d'un membre
CREATE OR REPLACE FUNCTION public.fn_modifier_role_membre(
  p_membre_id uuid,
  p_nouveau_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_membre RECORD;
  v_perms jsonb;
  v_ancien_role text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_nouveau_role NOT IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ROLE_INVALIDE');
  END IF;

  SELECT * INTO v_membre FROM public.membres_etablissement WHERE id = p_membre_id;
  IF v_membre IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MEMBRE_INTROUVABLE');
  END IF;

  SELECT public.fn_mes_permissions_etab(v_membre.etablissement_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Ne pas pouvoir se rétrograder soi-même PROPRIETAIRE → autre
  IF v_membre.user_id = v_uid AND v_membre.role = 'PROPRIETAIRE' AND p_nouveau_role != 'PROPRIETAIRE' THEN
    -- Vérifier qu'au moins un autre PROPRIETAIRE existe
    IF NOT EXISTS (
      SELECT 1 FROM public.membres_etablissement
      WHERE etablissement_id = v_membre.etablissement_id
        AND role = 'PROPRIETAIRE'
        AND actif = true
        AND user_id != v_uid
    ) THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DERNIER_PROPRIETAIRE',
                                  'error', 'Au moins un PROPRIETAIRE doit rester actif');
    END IF;
  END IF;

  v_ancien_role := v_membre.role;

  UPDATE public.membres_etablissement
  SET role = p_nouveau_role, maj_le = now()
  WHERE id = p_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', p_membre_id,
    jsonb_build_object(
      'evenement', 'MEMBRE_ROLE_MODIFIE',
      'ancien_role', v_ancien_role,
      'nouveau_role', p_nouveau_role
    )
  );

  RETURN jsonb_build_object('success', true, 'role', p_nouveau_role);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_modifier_role_membre(uuid, text) TO authenticated;

-- 7. RPC : révoquer un membre
CREATE OR REPLACE FUNCTION public.fn_revoquer_membre(p_membre_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_membre RECORD;
  v_perms jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_membre FROM public.membres_etablissement WHERE id = p_membre_id;
  IF v_membre IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MEMBRE_INTROUVABLE');
  END IF;

  SELECT public.fn_mes_permissions_etab(v_membre.etablissement_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Empêcher la révocation du dernier PROPRIETAIRE
  IF v_membre.role = 'PROPRIETAIRE' AND NOT EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = v_membre.etablissement_id
      AND role = 'PROPRIETAIRE'
      AND actif = true
      AND id != p_membre_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DERNIER_PROPRIETAIRE');
  END IF;

  UPDATE public.membres_etablissement
  SET actif = false, maj_le = now()
  WHERE id = p_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', p_membre_id,
    jsonb_build_object(
      'evenement', 'MEMBRE_REVOQUE',
      'role', v_membre.role,
      'etablissement_id', v_membre.etablissement_id
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_revoquer_membre(uuid) TO authenticated;

-- 8. RPC : lister membres + invitations en attente
CREATE OR REPLACE FUNCTION public.fn_lister_membres_etab(p_etablissement_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_perms jsonb;
  v_membres jsonb;
  v_invitations jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_etab_id := COALESCE(p_etablissement_id, public.mon_etablissement_id());
  SELECT public.fn_mes_permissions_etab(v_etab_id) INTO v_perms;
  IF (v_perms->>'role') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'user_id', m.user_id,
    'email', u.email,
    'role', m.role,
    'accepte_le', m.accepte_le,
    'actif', m.actif
  ) ORDER BY m.accepte_le DESC), '[]'::jsonb)
  INTO v_membres
  FROM public.membres_etablissement m
  JOIN auth.users u ON u.id = m.user_id
  WHERE m.etablissement_id = v_etab_id
    AND m.actif = true;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'email_invite', email_invite,
    'role_propose', role_propose,
    'statut', statut,
    'invite_le', invite_le,
    'expire_le', expire_le
  ) ORDER BY invite_le DESC), '[]'::jsonb)
  INTO v_invitations
  FROM public.invitations_etablissement
  WHERE etablissement_id = v_etab_id
    AND statut = 'EN_ATTENTE'
    AND expire_le > now();

  RETURN jsonb_build_object(
    'success', true,
    'role_courant', v_perms->>'role',
    'membres', v_membres,
    'invitations', v_invitations
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_lister_membres_etab(uuid) TO authenticated;

-- 9. RPC : annuler invitation
CREATE OR REPLACE FUNCTION public.fn_annuler_invitation_membre(p_invitation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_invitation RECORD;
  v_perms jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_invitation FROM public.invitations_etablissement WHERE id = p_invitation_id;
  IF v_invitation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_INTROUVABLE');
  END IF;

  SELECT public.fn_mes_permissions_etab(v_invitation.etablissement_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  UPDATE public.invitations_etablissement
  SET statut = 'ANNULEE'
  WHERE id = p_invitation_id AND statut = 'EN_ATTENTE';

  RETURN jsonb_build_object('success', true);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_annuler_invitation_membre(uuid) TO authenticated;

-- 10. Bootstrap : créer PROPRIETAIRE pour tous les étabs existants
-- Recherche le user_id du créateur via email_contact (pas de cree_par en DB).
DO $body$
DECLARE
  v_etab RECORD;
  v_user_id uuid;
BEGIN
  FOR v_etab IN
    SELECT e.id, e.email_contact
    FROM public.etablissements e
    WHERE e.email_contact IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.membres_etablissement m
        WHERE m.etablissement_id = e.id AND m.actif = true
      )
  LOOP
    SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(v_etab.email_contact) LIMIT 1;
    IF v_user_id IS NOT NULL THEN
      INSERT INTO public.membres_etablissement (
        etablissement_id, user_id, role, accepte_le, actif
      ) VALUES (
        v_etab.id, v_user_id, 'PROPRIETAIRE', now(), true
      )
      ON CONFLICT (etablissement_id, user_id) DO NOTHING;
    END IF;
  END LOOP;
END;
$body$;

-- 11. RPC d'initialisation : à appeler par register-etablissement edge function
-- après la création d'un nouvel établissement, pour ajouter le user créateur
-- comme PROPRIETAIRE.
CREATE OR REPLACE FUNCTION public.fn_init_proprietaire_etab(
  p_etablissement_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := COALESCE(p_user_id, auth.uid());
  v_membre_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  -- Si déjà un membre actif sur cet étab, ne rien faire
  IF EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = p_etablissement_id AND actif = true
  ) THEN
    RETURN jsonb_build_object('success', true, 'message', 'Membres déjà présents');
  END IF;

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, accepte_le, actif
  ) VALUES (
    p_etablissement_id, v_uid, 'PROPRIETAIRE', now(), true
  )
  RETURNING id INTO v_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', v_membre_id,
    jsonb_build_object(
      'evenement', 'PROPRIETAIRE_INITIALISE',
      'etablissement_id', p_etablissement_id
    )
  );

  RETURN jsonb_build_object('success', true, 'membre_id', v_membre_id);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_init_proprietaire_etab(uuid, uuid) TO authenticated, service_role;

-- Audit migration
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT57_PR1_EQUIPE_ETAB_INSTALLED',
    'pr', 'PR 1 Sprint 5.7',
    'tables', jsonb_build_array('membres_etablissement', 'invitations_etablissement'),
    'rpcs', jsonb_build_array(
      'fn_mes_permissions_etab',
      'fn_inviter_membre_etab',
      'fn_accepter_invitation_membre',
      'fn_modifier_role_membre',
      'fn_revoquer_membre',
      'fn_lister_membres_etab',
      'fn_annuler_invitation_membre',
      'fn_init_proprietaire_etab'
    ),
    'bootstrap', 'PROPRIETAIRE auto-créé via email_contact pour étabs existants',
    'roles', jsonb_build_array('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE')
  )
);
