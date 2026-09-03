-- La contrainte litiges_initie_par_check autorise SYSTEME mais pas ADMIN.
-- La RPC admin écrivait pourtant ADMIN et rendait son propre formulaire
-- inutilisable. On conserve la contrainte fermée et on utilise SYSTEME comme
-- origine métier ; l'identité admin exacte et sa justification restent dans
-- journaux_audit via fn_ecrire_audit.
CREATE OR REPLACE FUNCTION public.fn_admin_creer_litige_force(
  p_mission_id uuid,
  p_type_litige public.type_litige,
  p_motif text,
  p_raison_bypass text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_mission record;
  v_litige_id uuid;
  v_est_informatif boolean;
  v_facture_id uuid;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis pour cette opération.');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;
  IF length(trim(COALESCE(p_raison_bypass, ''))) < 10 THEN
    RETURN jsonb_build_object('error', 'La raison du bypass doit contenir au moins 10 caractères (traçabilité).');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id
    INTO v_mission
    FROM public.missions
   WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_mission.soignant_assigne_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Un soignant doit être assigné avant de créer une intervention.');
  END IF;

  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES') THEN
    SELECT id INTO v_facture_id
      FROM public.factures_honoraires
     WHERE mission_id = p_mission_id
       AND statut <> 'BROUILLON'
     ORDER BY date_emission DESC NULLS LAST
     LIMIT 1;
  END IF;

  v_est_informatif := NOT public.fn_fenetre_contestation_ouverte(
    p_type_litige, p_mission_id, v_facture_id
  );

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, est_informatif, facture_id
  )
  VALUES (
    p_mission_id, v_mission.soignant_assigne_id,
    v_mission.etablissement_id, 'SYSTEME', trim(p_motif), 'OUVERT',
    p_type_litige, v_est_informatif, v_facture_id
  )
  RETURNING id INTO v_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_FORCE_CREATION',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'est_informatif', v_est_informatif,
      'raison_bypass', trim(p_raison_bypass),
      'facture_id', v_facture_id,
      'origine_litige', 'SYSTEME_ADMIN'
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif,
    'facture_id', v_facture_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_creer_litige_force(uuid, public.type_litige, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_creer_litige_force(uuid, public.type_litige, text, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_creer_litige_force(uuid, public.type_litige, text, text) IS
  'Admin-only : crée une intervention avec origine SYSTEME compatible avec la contrainte ; l admin et sa raison sont consignés dans journaux_audit.';
