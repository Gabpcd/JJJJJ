
DROP FUNCTION IF EXISTS public.fn_auto_facturation_mensuelle();

CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debut_mois date := date_trunc('month', now() - interval '1 month')::date;
  v_fin_mois date := (date_trunc('month', now()) - interval '1 day')::date;
  v_etab record;
  v_count integer := 0;
  v_errors text[] := '{}';
  v_montant_ht numeric;
  v_montant_tva numeric;
  v_montant_ttc numeric;
  v_nb_missions integer;
  v_numero text;
  v_facture_id uuid;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NON_AUTORISE');
  END IF;

  FOR v_etab IN
    SELECT DISTINCT e.id, e.nom
    FROM etablissements e
    INNER JOIN missions m ON m.etablissement_id = e.id
    WHERE m.statut = 'TERMINEE' AND m.commission_facturee = false
      AND m.fin_le >= v_debut_mois::timestamp with time zone
      AND m.fin_le < (v_fin_mois + 1)::timestamp with time zone
      AND e.supprime_le IS NULL
  LOOP
    BEGIN
      SELECT count(*), coalesce(sum(montant_commission_ht), 0)
      INTO v_nb_missions, v_montant_ht
      FROM missions
      WHERE etablissement_id = v_etab.id AND statut = 'TERMINEE' AND commission_facturee = false
        AND fin_le >= v_debut_mois::timestamp with time zone
        AND fin_le < (v_fin_mois + 1)::timestamp with time zone;

      IF v_nb_missions = 0 OR v_montant_ht = 0 THEN CONTINUE; END IF;

      v_montant_tva := round(v_montant_ht * 0.20, 2);
      v_montant_ttc := v_montant_ht + v_montant_tva;
      v_numero := 'FACT-' || to_char(now(), 'YYYYMM') || '-' || lpad((v_count + 1)::text, 4, '0');

      INSERT INTO factures (etablissement_id, numero_facture, periode_debut, periode_fin, montant_ht, montant_tva, montant_ttc, nombre_missions, date_emission, date_echeance, statut)
      VALUES (v_etab.id, v_numero, v_debut_mois, v_fin_mois, v_montant_ht, v_montant_tva, v_montant_ttc, v_nb_missions, now(), (now() + interval '30 days')::date, 'EMISE')
      RETURNING id INTO v_facture_id;

      UPDATE missions SET commission_facturee = true, facture_id = v_facture_id
      WHERE etablissement_id = v_etab.id AND statut = 'TERMINEE' AND commission_facturee = false
        AND fin_le >= v_debut_mois::timestamp with time zone
        AND fin_le < (v_fin_mois + 1)::timestamp with time zone;

      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, v_etab.nom || ': ' || SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'factures_generees', v_count, 'erreurs', v_errors);
END;
$$;
