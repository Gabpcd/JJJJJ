-- Itération 1 — Fix B.3 : idempotence SMS + Fix B.11 : RPC admin force re-upload RIB legacy

-- B.3 : idempotence SMS
ALTER TABLE public.sms_envoyes
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS sms_envoyes_idempotency_key_uniq
  ON public.sms_envoyes(idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sms_anti_spam
  ON public.sms_envoyes(destinataire_id, type, cree_le DESC);

CREATE OR REPLACE FUNCTION public.fn_sms_doit_envoyer(
  p_destinataire_id UUID,
  p_type TEXT,
  p_fenetre_minutes INT DEFAULT 5
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
STABLE
AS $$
DECLARE
  v_existe BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM sms_envoyes
    WHERE destinataire_id = p_destinataire_id
      AND type = p_type
      AND statut IN ('SENT','DELIVERED','PENDING')
      AND cree_le > NOW() - (p_fenetre_minutes || ' minutes')::INTERVAL
  ) INTO v_existe;
  RETURN NOT v_existe;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_sms_doit_envoyer(UUID, TEXT, INT) TO authenticated, service_role;

-- B.11 : RPC admin pour forcer re-upload RIB legacy
CREATE OR REPLACE FUNCTION public.fn_admin_forcer_reupload_rib(p_etablissement_id UUID, p_raison TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès admin uniquement');
  END IF;

  IF p_raison IS NULL OR LENGTH(TRIM(p_raison)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison requise (min 10 caractères)');
  END IF;

  SELECT id, nom, rib_s3_key INTO v_etab FROM etablissements WHERE id = p_etablissement_id;
  IF v_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  UPDATE etablissements SET rib_s3_key = NULL, modifie_le = NOW()
  WHERE id = p_etablissement_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    p_etablissement_id, 'ETABLISSEMENT', 'SYSTEM',
    '⚠️ RIB à re-uploader',
    'Pour des raisons de conformité, vous devez re-uploader votre RIB. Raison : ' || p_raison,
    '/etablissement/finaliser-inscription'
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'ADMIN_ACTION', p_type_ressource := 'etablissement', p_id_ressource := p_etablissement_id,
    p_details := jsonb_build_object(
      'sous_action', 'FORCER_REUPLOAD_RIB',
      'rib_avant', v_etab.rib_s3_key,
      'raison', p_raison
    )
  );

  RETURN jsonb_build_object('success', true, 'etablissement_id', p_etablissement_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_forcer_reupload_rib(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
