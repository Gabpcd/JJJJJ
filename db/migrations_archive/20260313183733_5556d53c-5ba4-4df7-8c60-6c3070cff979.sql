
-- M5: Atomic serie cancellation RPC
CREATE OR REPLACE FUNCTION public.fn_annuler_serie_etablissement(p_mission_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
  v_count int := 0;
  v_mid uuid;
BEGIN
  -- Get caller's establishment
  SELECT mon_etablissement_id() INTO v_etab_id;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé');
  END IF;

  -- Cancel all missions in a single transaction
  FOREACH v_mid IN ARRAY p_mission_ids LOOP
    UPDATE missions 
    SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = now()
    WHERE id = v_mid 
      AND etablissement_id = v_etab_id 
      AND statut = 'OUVERTE';
    IF FOUND THEN v_count := v_count + 1; END IF;
  END LOOP;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    auth.uid(), 'ADMIN_ETABLISSEMENT', 'MISSION_ANNULATION_SERIE',
    'mission', v_etab_id, NULL,
    jsonb_build_object('nb_annulees', v_count, 'mission_ids', to_jsonb(p_mission_ids)),
    NULL, NULL
  );

  RETURN jsonb_build_object('success', true, 'nb_annulees', v_count);
END;
$$;

-- M7: Allow soignants to UPDATE contrats_mission for signature fields only (via trigger protection)
CREATE POLICY pol_contrat_update_soignant ON public.contrats_mission
  FOR UPDATE
  TO authenticated
  USING (soignant_id = auth.uid())
  WITH CHECK (soignant_id = auth.uid());

-- L5: Create scheduled function to anonymize GPS data older than 90 days
CREATE OR REPLACE FUNCTION public.fn_anonymiser_gps_anciennes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE presences
  SET arrivee_lat = NULL, arrivee_lng = NULL,
      depart_lat = NULL, depart_lng = NULL,
      arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
      arrivee_ip = NULL, depart_ip = NULL
  WHERE (pointage_arrivee_le < now() - interval '90 days')
    AND (arrivee_lat IS NOT NULL OR depart_lat IS NOT NULL);
END;
$$;
