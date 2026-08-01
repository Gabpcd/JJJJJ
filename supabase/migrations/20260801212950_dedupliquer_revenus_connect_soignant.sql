BEGIN;

-- Un paiement Stripe Connect est matérialisé à la fois dans stripe_transfers
-- et, pour la traçabilité métier, dans paiements_soignant. Le second enregistrement
-- porte stripe_transfer_id : il s'agit d'un miroir, pas d'un revenu supplémentaire.

CREATE OR REPLACE FUNCTION public.fn_mes_revenus_connect(p_mois_debut date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_debut date;
    v_connect_mois numeric;
    v_connect_total numeric;
    v_connect_attente numeric;
    v_paiements_mois numeric;
    v_paiements_total numeric;
    v_escrow_mois numeric;
    v_escrow_total numeric;
    v_escrow_attente numeric;
BEGIN
    v_debut := COALESCE(p_mois_debut, DATE_TRUNC('month', CURRENT_DATE)::date);

    SELECT COALESCE(SUM(st.montant_soignant), 0) INTO v_connect_mois
    FROM public.stripe_transfers st
    WHERE st.soignant_id = auth.uid()
      AND st.statut IN ('TRANSFERE', 'PAYE')
      AND st.transfere_le >= v_debut;

    SELECT COALESCE(SUM(st.montant_soignant), 0) INTO v_connect_total
    FROM public.stripe_transfers st
    WHERE st.soignant_id = auth.uid()
      AND st.statut IN ('TRANSFERE', 'PAYE');

    SELECT COALESCE(SUM(st.montant_soignant), 0) INTO v_connect_attente
    FROM public.stripe_transfers st
    WHERE st.soignant_id = auth.uid()
      AND st.statut = 'EN_ATTENTE';

    -- Seuls les paiements réellement manuels sont additionnés. Les lignes liées
    -- à stripe_transfers sont le miroir comptable du même versement Connect.
    SELECT COALESCE(SUM(ps.montant_net), 0) INTO v_paiements_mois
    FROM public.paiements_soignant ps
    WHERE ps.soignant_id = auth.uid()
      AND ps.statut = 'CONFIRME'
      AND ps.stripe_transfer_id IS NULL
      AND ps.confirme_par_soignant_le >= v_debut;

    SELECT COALESCE(SUM(ps.montant_net), 0) INTO v_paiements_total
    FROM public.paiements_soignant ps
    WHERE ps.soignant_id = auth.uid()
      AND ps.statut = 'CONFIRME'
      AND ps.stripe_transfer_id IS NULL;

    SELECT COALESCE(SUM(pe.honoraires_cents), 0) / 100.0 INTO v_escrow_mois
    FROM public.paiements_escrow pe
    WHERE pe.soignant_id = auth.uid()
      AND pe.statut = 'PAYE'
      AND pe.paye_le >= v_debut;

    SELECT COALESCE(SUM(pe.honoraires_cents), 0) / 100.0 INTO v_escrow_total
    FROM public.paiements_escrow pe
    WHERE pe.soignant_id = auth.uid()
      AND pe.statut = 'PAYE';

    SELECT COALESCE(SUM(pe.honoraires_cents), 0) / 100.0 INTO v_escrow_attente
    FROM public.paiements_escrow pe
    WHERE pe.soignant_id = auth.uid()
      AND pe.statut IN ('INITIE', 'DEBITE', 'DISPONIBLE', 'RELEASE_PLANIFIE');

    RETURN jsonb_build_object(
        'mois_en_cours', v_connect_mois + v_paiements_mois + v_escrow_mois,
        'total', v_connect_total + v_paiements_total + v_escrow_total,
        'en_attente', v_connect_attente + v_escrow_attente,
        'stripe_connect_actif', public.fn_soignant_stripe_connect_actif(auth.uid())
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_mes_revenus_connect(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_mes_revenus_connect(date) TO authenticated, service_role;

UPDATE private.security_definer_inventory i
SET definition_md5 = pg_catalog.md5(p.prosrc),
    justification = 'RPC authenticated: revenus du soignant courant; les miroirs paiements_soignant liés à un transfer Connect sont exclus.'
FROM pg_catalog.pg_proc p
WHERE i.signature = 'fn_mes_revenus_connect(date)'
  AND p.oid = 'public.fn_mes_revenus_connect(date)'::pg_catalog.regprocedure;

DO $assert_fn_mes_revenus_connect_inventory$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM private.security_definer_inventory i
    JOIN pg_catalog.pg_proc p
      ON p.oid = 'public.fn_mes_revenus_connect(date)'::pg_catalog.regprocedure
    WHERE i.signature = 'fn_mes_revenus_connect(date)'
      AND i.definition_md5 = pg_catalog.md5(p.prosrc)
  ) THEN
    RAISE EXCEPTION 'Inventaire SECURITY DEFINER non synchronisé pour fn_mes_revenus_connect(date)';
  END IF;
END;
$assert_fn_mes_revenus_connect_inventory$;

COMMIT;
