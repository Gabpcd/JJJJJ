
DROP FUNCTION IF EXISTS public.fn_admin_stripe_connect_stats();

CREATE OR REPLACE FUNCTION public.fn_admin_stripe_connect_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_comptes integer := 0;
  v_complets integer := 0;
  v_en_cours integer := 0;
  v_total_transfere numeric := 0;
  v_total_en_attente numeric := 0;
BEGIN
  SELECT COUNT(*) INTO v_total_comptes FROM stripe_connect_onboarding;
  SELECT COUNT(*) INTO v_complets FROM stripe_connect_onboarding WHERE statut = 'COMPLET';
  SELECT COUNT(*) INTO v_en_cours FROM stripe_connect_onboarding WHERE statut = 'EN_COURS';
  SELECT COALESCE(SUM(montant_soignant_cents), 0) / 100.0 INTO v_total_transfere FROM stripe_transfers WHERE statut = 'TRANSFERE';
  SELECT COALESCE(SUM(montant_soignant_cents), 0) / 100.0 INTO v_total_en_attente FROM stripe_transfers WHERE statut = 'EN_ATTENTE';
  RETURN json_build_object('total_comptes', v_total_comptes, 'complets', v_complets, 'en_cours', v_en_cours, 'total_transfere', v_total_transfere, 'total_en_attente', v_total_en_attente);
END;
$$;
