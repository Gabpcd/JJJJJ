
-- RPC: Generate monthly invoice server-side (prevents client-side amount manipulation)
CREATE OR REPLACE FUNCTION public.fn_generer_facture_mensuelle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
  v_total_ht numeric := 0;
  v_total_tva numeric := 0;
  v_total_ttc numeric := 0;
  v_nb_missions integer := 0;
  v_mission_ids uuid[];
  v_numero text;
  v_facture_id uuid;
  v_now timestamp with time zone := now();
  v_debut_mois date;
  v_fin_mois date;
BEGIN
  -- Auth check
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  -- Compute totals from unfactured TERMINEE missions
  SELECT
    COALESCE(SUM(montant_commission_ht), 0),
    COALESCE(SUM(montant_commission_tva), 0),
    COALESCE(SUM(montant_commission_ttc), 0),
    COUNT(*),
    ARRAY_AGG(id)
  INTO v_total_ht, v_total_tva, v_total_ttc, v_nb_missions, v_mission_ids
  FROM missions
  WHERE etablissement_id = v_etab_id
    AND statut = 'TERMINEE'
    AND commission_facturee = false;

  IF v_nb_missions = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucune mission à facturer');
  END IF;

  -- Generate invoice number
  SELECT fn_generer_numero_facture() INTO v_numero;

  v_debut_mois := date_trunc('month', v_now)::date;
  v_fin_mois := (date_trunc('month', v_now) + interval '1 month' - interval '1 day')::date;

  -- Insert invoice
  INSERT INTO factures (
    etablissement_id, numero_facture,
    montant_ht, montant_tva, montant_ttc,
    nombre_missions, periode_debut, periode_fin,
    date_emission, date_echeance, statut
  ) VALUES (
    v_etab_id, v_numero,
    ROUND(v_total_ht, 2), ROUND(v_total_tva, 2), ROUND(v_total_ttc, 2),
    v_nb_missions, v_debut_mois, v_fin_mois,
    v_now, (v_now + interval '30 days')::date, 'EMISE'
  )
  RETURNING id INTO v_facture_id;

  -- Mark missions as invoiced
  UPDATE missions
  SET commission_facturee = true,
      facture_id = v_facture_id,
      modifie_le = v_now
  WHERE id = ANY(v_mission_ids);

  -- Audit log
  PERFORM fn_ecrire_audit_safe(
    v_etab_id, 'ADMIN_ETABLISSEMENT', 'FACTURE_GENEREE',
    'facture', v_facture_id, NULL,
    jsonb_build_object('numero', v_numero, 'montant_ttc', v_total_ttc, 'nb_missions', v_nb_missions),
    NULL, 'server-rpc'
  );

  RETURN jsonb_build_object(
    'success', true,
    'facture_id', v_facture_id,
    'numero_facture', v_numero,
    'montant_ttc', ROUND(v_total_ttc, 2),
    'nb_missions', v_nb_missions
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_generer_facture_mensuelle() TO authenticated;
