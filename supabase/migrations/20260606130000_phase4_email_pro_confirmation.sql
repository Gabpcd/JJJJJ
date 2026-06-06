-- PHASE 4 (point 2) — Confirmation e-mail professionnel (gros établissements).
-- Un gros établissement (CHU, AP-HP, clinique de groupe) prouve son rattachement
-- par la validation d'un e-mail au domaine professionnel de l'établissement.
-- Le lien contient un token hex 64 chars, expire après 24h.
-- Une fois confirmé, fn_evaluer_rattachement_etablissement route vers EMAIL_PRO.

-- ── 1) Colonnes token ──────────────────────────────────────────────────────────
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS email_contact_token text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS email_contact_token_expire_le timestamptz;

-- ── 2) RPC : demander la confirmation ──────────────────────────────────────────
-- Appelée par le front quand l'établissement saisit son e-mail pro.
-- Génère un token, l'insère, enqueue un e-mail CONFIRMATION_EMAIL_PRO_ETAB.
-- Autorisation : service-role OU membre PROPRIETAIRE/ADMIN_GROUPE de l'étab.
CREATE OR REPLACE FUNCTION public.fn_demander_confirmation_email_etab(
  p_etablissement_id uuid,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_token text;
  v_expire timestamptz;
  v_etab RECORD;
BEGIN
  -- Autorisation
  IF NOT est_admin() THEN
    IF mon_etablissement_id() IS NULL OR mon_etablissement_id() <> p_etablissement_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;
  END IF;

  -- Validation e-mail basique
  IF p_email IS NULL OR p_email !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Adresse e-mail invalide');
  END IF;

  -- Vérifier que l'établissement existe
  SELECT id, nom INTO v_etab FROM etablissements WHERE id = p_etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  -- Génération du token (hex 64 chars = 32 bytes)
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expire := now() + interval '24 hours';

  -- Mise à jour
  UPDATE etablissements SET
    email_contact = p_email,
    email_contact_token = v_token,
    email_contact_token_expire_le = v_expire,
    email_contact_verifie = false,
    email_contact_verifie_le = NULL
  WHERE id = p_etablissement_id;

  -- Mise en file d'attente de l'e-mail de confirmation
  INSERT INTO email_queue (id, type, destinataire_email, data, statut, cree_le)
  VALUES (
    gen_random_uuid(),
    'CONFIRMATION_EMAIL_PRO_ETAB',
    p_email,
    jsonb_build_object(
      'etablissement_id', p_etablissement_id,
      'etablissement_nom', v_etab.nom,
      'token', v_token,
      'expire_le', v_expire
    ),
    'EN_ATTENTE',
    now()
  );

  RETURN jsonb_build_object('success', true, 'email', p_email, 'expire_le', v_expire);
END;
$body$;

-- ── 3) RPC : valider le token (appelée par l'edge function confirm-email-etab) ─
-- Publique (pas d'auth user requise — le token est la preuve), mais appelée via
-- service-role depuis l'edge function pour éviter un accès RLS direct.
CREATE OR REPLACE FUNCTION public.fn_confirmer_email_etab(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_etab_id uuid;
  v_expire timestamptz;
  v_rattachement jsonb;
BEGIN
  IF p_token IS NULL OR length(p_token) < 32 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token invalide');
  END IF;

  SELECT id, email_contact_token_expire_le
    INTO v_etab_id, v_expire
  FROM etablissements
  WHERE email_contact_token = p_token;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token inconnu ou déjà utilisé');
  END IF;

  IF v_expire < now() THEN
    -- Nettoyer le token expiré
    UPDATE etablissements SET email_contact_token = NULL, email_contact_token_expire_le = NULL
    WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', false, 'error', 'Token expiré. Veuillez renvoyer un e-mail de confirmation.');
  END IF;

  -- Confirmation réussie
  UPDATE etablissements SET
    email_contact_verifie = true,
    email_contact_verifie_le = now(),
    email_contact_token = NULL,
    email_contact_token_expire_le = NULL
  WHERE id = v_etab_id;

  -- Évaluation du rattachement adaptatif
  BEGIN
    SELECT fn_evaluer_rattachement_etablissement(v_etab_id) INTO v_rattachement;
  EXCEPTION WHEN OTHERS THEN
    v_rattachement := NULL;
  END;

  RETURN jsonb_build_object('success', true, 'etablissement_id', v_etab_id, 'rattachement', v_rattachement);
END;
$body$;

-- Grant pour appel côté client (fn_demander) et service-role (fn_confirmer)
GRANT EXECUTE ON FUNCTION public.fn_demander_confirmation_email_etab(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_confirmer_email_etab(text) TO service_role;
