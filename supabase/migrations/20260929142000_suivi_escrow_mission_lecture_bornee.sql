-- La table financière reste privée. Seuls deux champs du paiement de cette
-- mission sont exposés à son soignant ou aux membres autorisés de l'établissement.
CREATE OR REPLACE FUNCTION public.fn_suivi_escrow_mission(p_mission_id uuid)
RETURNS TABLE(statut text, paye_le timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $suivi$
DECLARE
  v_etablissement uuid;
  v_soignant uuid;
  v_finance boolean;
BEGIN
  IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès refusé.' USING ERRCODE='42501';
  END IF;
  SELECT m.etablissement_id, m.soignant_assigne_id
  INTO v_etablissement, v_soignant FROM public.missions m WHERE m.id=p_mission_id;
  v_finance := public.fn_a_permission_etablissement('lecture_paiement',v_etablissement) IS TRUE
    OR public.fn_a_permission_etablissement('paiement',v_etablissement) IS TRUE;
  IF v_etablissement IS NULL OR (v_soignant IS DISTINCT FROM auth.uid() AND NOT v_finance) THEN
    RAISE EXCEPTION 'Accès refusé.' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT pe.statut::text, pe.paye_le
  FROM public.paiements_escrow pe
  WHERE pe.mission_id=p_mission_id AND pe.etablissement_id=v_etablissement
    AND (v_finance OR pe.soignant_id=auth.uid());
END;
$suivi$;
REVOKE ALL ON FUNCTION public.fn_suivi_escrow_mission(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_suivi_escrow_mission(uuid) TO authenticated;
COMMENT ON FUNCTION public.fn_suivi_escrow_mission(uuid) IS 'Lecture du seul statut escrow de la mission autorisée ; aucun montant, aucun identifiant Stripe, aucune mutation.';
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT p.oid::regprocedure::text,'RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),
  'Statut escrow par mission : compte actif, soignant affecté ou permission financière sur cet établissement ; deux champs sans montant ni identifiant fournisseur.',now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_suivi_escrow_mission'
ON CONFLICT(signature) DO UPDATE SET definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
