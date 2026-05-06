-- Révocation du mandat de facturation par le soignant lui-même.
--
-- Effet :
--   - mandats_facturation_signatures.revoked_at = now() sur la dernière
--     signature active (revoked_at IS NULL).
--   - soignants.mandat_facturation_signe = false
--     soignants.mandat_facturation_signe_le = NULL
--     soignants.mandat_facturation_version = NULL
--   - Audit via fn_ecrire_audit_safe (action MANDAT_FACTURATION_REVOQUE).
--
-- Conséquence métier : generate-invoice refusera de créer de nouvelles
-- factures (vérification soignants.mandat_facturation_signe). Les factures
-- déjà émises restent immutables et exigibles (cohérent avec art. 289 I-2 :
-- la révocation n'a pas d'effet rétroactif sur les actes déjà accomplis).
--
-- Le soignant peut re-signer un nouveau mandat à tout moment (la nouvelle
-- signature crée une nouvelle row dans mandats_facturation_signatures).

DROP FUNCTION IF EXISTS public.fn_revoquer_mandat_facturation(text);
DROP FUNCTION IF EXISTS public.fn_revoquer_mandat_facturation();

CREATE OR REPLACE FUNCTION public.fn_revoquer_mandat_facturation(p_motif text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_signature_id uuid;
  v_version text;
  v_signed_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM soignants
    WHERE id = v_uid AND mandat_facturation_signe = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun mandat actif à révoquer');
  END IF;

  UPDATE mandats_facturation_signatures
  SET revoked_at = now()
  WHERE soignant_id = v_uid AND revoked_at IS NULL
  RETURNING id, version, signed_at INTO v_signature_id, v_version, v_signed_at;

  UPDATE soignants
  SET mandat_facturation_signe = false,
      mandat_facturation_signe_le = NULL,
      mandat_facturation_version = NULL
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'MANDAT_FACTURATION_REVOQUE',
    p_type_ressource := 'mandat_facturation',
    p_id_ressource := v_signature_id,
    p_details := jsonb_build_object(
      'version', v_version,
      'signed_at', v_signed_at,
      'revoked_at', now(),
      'motif', p_motif
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'signature_id', v_signature_id,
    'version', v_version,
    'revoked_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_revoquer_mandat_facturation(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
