-- Un échec de débit ne peut faire régresser un escrow déjà débité, libéré,
-- payé, remboursé ou contesté. Cette RPC est volontairement distincte de
-- fn_escrow_marquer_incident, utilisée aussi par les incidents post-débit.
CREATE OR REPLACE FUNCTION public.fn_escrow_marquer_echec_debit(
  p_paiement_escrow_id uuid,
  p_detail text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.paiements_escrow%ROWTYPE;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT pe.*
    INTO v_row
  FROM public.paiements_escrow pe
  WHERE pe.id = p_paiement_escrow_id
    AND pe.statut = 'INITIE'
  FOR UPDATE;

  IF v_row.id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.paiements_escrow
  SET statut = 'ECHOUE',
      erreur = left(p_detail, 500),
      relance_prevue_le = now() + interval '3 days',
      modifie_le = now()
  WHERE id = v_row.id
    AND statut = 'INITIE';

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  PERFORM public.fn_escrow_geler_etablissement(
    v_row.etablissement_id,
    format(
      'ECHEC escrow mission %s : %s',
      v_row.mission_id,
      COALESCE(left(p_detail, 500), '')
    )
  );

  UPDATE public.escrow_etablissement_etat
  SET missions_sans_incident = 0,
      modifie_le = now()
  WHERE etablissement_id = v_row.etablissement_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_escrow_marquer_echec_debit(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_escrow_marquer_echec_debit(uuid, text) TO service_role;
