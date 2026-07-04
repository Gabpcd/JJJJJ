-- ============================================================================
-- Sprint 5.5 PR 8 — RPC dédiée pour modifier tolerance_pointage_m établissement
-- ============================================================================
-- Fix P0-4 audit Sprint 5 : la colonne etablissements.tolerance_pointage_m
-- existait (CHECK [30, 1000], DEFAULT 100) mais aucune RPC pour la régler
-- côté UI étab. fn_modifier_mon_etablissement n'accepte pas ce paramètre.
--
-- Cette RPC isolée valide le range et persiste avec audit.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_modifier_tolerance_pointage_etab(
  p_tolerance_pointage_m integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_ancienne_valeur integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_tolerance_pointage_m IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'VALEUR_REQUISE');
  END IF;

  IF p_tolerance_pointage_m < 30 OR p_tolerance_pointage_m > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'HORS_RANGE',
      'error', 'Tolérance doit être entre 30 et 1000 mètres'
    );
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT tolerance_pointage_m INTO v_ancienne_valeur FROM public.etablissements WHERE id = v_etab_id;

  UPDATE public.etablissements
  SET tolerance_pointage_m = p_tolerance_pointage_m,
      mis_a_jour_le = now()
  WHERE id = v_etab_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'etablissement', v_etab_id,
    jsonb_build_object(
      'champ', 'tolerance_pointage_m',
      'ancienne_valeur', v_ancienne_valeur,
      'nouvelle_valeur', p_tolerance_pointage_m,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'tolerance_pointage_m', p_tolerance_pointage_m,
    'horodatage', now()
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_modifier_tolerance_pointage_etab(integer) TO authenticated;

-- Audit migration
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT55_PR8_TOLERANCE_GPS_RPC_INSTALLED',
    'pr', 'PR 8 Sprint 5.5',
    'rpc', 'fn_modifier_tolerance_pointage_etab',
    'range', '[30, 1000]'
  )
);
