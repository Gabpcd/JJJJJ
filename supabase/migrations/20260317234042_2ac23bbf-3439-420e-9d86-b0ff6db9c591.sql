-- Function called by verify-document edge function to update verification results
-- Runs as postgres owner, bypassing triggers that check est_admin()
CREATE OR REPLACE FUNCTION public.fn_update_document_verification(
  p_document_id uuid,
  p_statut_verification text,
  p_motif_rejet text DEFAULT NULL,
  p_valide_depuis date DEFAULT NULL,
  p_valide_jusqua date DEFAULT NULL,
  p_verifie_le timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Disable the protective triggers temporarily for this session
  ALTER TABLE public.documents_soignants DISABLE TRIGGER trg_protect_document_verification;
  ALTER TABLE public.documents_soignants DISABLE TRIGGER trg_proteger_document_verification;
  ALTER TABLE public.documents_soignants DISABLE TRIGGER dec_proteger_valid_docs;

  UPDATE public.documents_soignants
  SET
    statut_verification = p_statut_verification::statut_verification,
    motif_rejet = p_motif_rejet,
    valide_depuis = COALESCE(p_valide_depuis, valide_depuis),
    valide_jusqua = COALESCE(p_valide_jusqua, valide_jusqua),
    verifie_le = p_verifie_le,
    modifie_le = now()
  WHERE id = p_document_id;

  -- Re-enable triggers
  ALTER TABLE public.documents_soignants ENABLE TRIGGER trg_protect_document_verification;
  ALTER TABLE public.documents_soignants ENABLE TRIGGER trg_proteger_document_verification;
  ALTER TABLE public.documents_soignants ENABLE TRIGGER dec_proteger_valid_docs;
END;
$$;

-- Grant execute to service_role only
GRANT EXECUTE ON FUNCTION public.fn_update_document_verification TO service_role;