-- Ajouter la colonne attestation_sante_signee_le aux soignants
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS attestation_sante_signee_le timestamptz DEFAULT NULL;

-- RPC pour signer l'attestation santé
CREATE OR REPLACE FUNCTION public.fn_signer_attestation_sante()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  -- Vérifier que c'est bien un soignant
  IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_user_id) THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  UPDATE soignants
  SET attestation_sante_signee_le = now(),
      modifie_le = now()
  WHERE id = v_user_id;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    v_user_id, 'SOIGNANT', 'ATTESTATION_SANTE_SIGNEE',
    'soignant', v_user_id, NULL,
    jsonb_build_object('vaccinations', true, 'medecine_travail', true),
    NULL, NULL
  );

  RETURN jsonb_build_object('success', true, 'signe_le', now());
END;
$$;