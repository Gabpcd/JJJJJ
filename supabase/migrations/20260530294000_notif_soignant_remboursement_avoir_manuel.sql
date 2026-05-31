-- Amélioration : sur confirmation MANUELLE d'un remboursement d'avoir, le
-- soignant n'était pas notifié (seul le chemin SWAN auto envoyait
-- REMBOURSEMENT_CONFIRME via l'edge function). On notifie désormais le soignant
-- (in-app + push + email) avec la référence du virement, comme le chemin auto.
CREATE OR REPLACE FUNCTION public.fn_confirmer_remboursement_avoir(p_avoir_id uuid, p_reference_virement text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_avoir RECORD;
  v_montant NUMERIC;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis.');
  END IF;
  IF length(trim(COALESCE(p_reference_virement, ''))) < 4 THEN
    RETURN jsonb_build_object('error', 'Référence virement requise (min 4 caractères).');
  END IF;

  SELECT * INTO v_avoir FROM public.factures_honoraires WHERE id = p_avoir_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Avoir introuvable.');
  END IF;
  IF v_avoir.type_document <> 'AVOIR' THEN
    RETURN jsonb_build_object('error', 'Ce document n''est pas un avoir.');
  END IF;
  IF v_avoir.mode_remboursement <> 'VIREMENT_MANUEL' THEN
    RETURN jsonb_build_object('error', 'Mode de remboursement incompatible (attendu : VIREMENT_MANUEL).');
  END IF;
  IF v_avoir.date_remboursement IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Remboursement déjà confirmé.');
  END IF;

  UPDATE public.factures_honoraires
     SET statut = 'REMBOURSE',
         date_remboursement = NOW(),
         reference_remboursement = trim(p_reference_virement)
   WHERE id = p_avoir_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'AVOIR_REMBOURSEMENT_CONFIRME',
    'facture_honoraire', p_avoir_id, NULL,
    jsonb_build_object(
      'numero_avoir', v_avoir.numero_facture,
      'montant_ht', v_avoir.montant_ht,
      'reference_virement', trim(p_reference_virement),
      'mode_remboursement', 'VIREMENT_MANUEL'
    ),
    NULL, NULL
  );

  -- Notifier le soignant (in-app + push + email), comme le chemin SWAN auto
  v_montant := COALESCE(v_avoir.montant_ttc, v_avoir.montant_ht, 0);
  IF v_avoir.soignant_id IS NOT NULL THEN
    PERFORM public.fn_litige_push_notification(
      v_avoir.soignant_id,
      'SOIGNANT',
      'REMBOURSEMENT_CONFIRME',
      'Remboursement effectué',
      'Le remboursement de ' || to_char(v_montant, 'FM999G999D00') || ' € (avoir ' ||
        COALESCE(v_avoir.numero_facture, '') || ') a été effectué par virement. Référence : ' ||
        trim(p_reference_virement) || '.',
      v_avoir.litige_id,
      jsonb_build_object(
        'montant', v_montant,
        'numero_avoir', v_avoir.numero_facture,
        'reference_virement', trim(p_reference_virement)
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'avoir_id', p_avoir_id,
    'statut', 'REMBOURSE',
    'date_remboursement', NOW()
  );
END;
$function$;
