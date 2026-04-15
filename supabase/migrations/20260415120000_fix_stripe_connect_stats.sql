-- Fix fn_admin_stripe_connect_stats : 6 métriques financières distinctes
-- Bug d'origine : SUM(montant) crashait (colonne inexistante).
-- Les vraies colonnes sont montant_total, montant_soignant, montant_commission.

CREATE OR REPLACE FUNCTION public.fn_admin_stripe_connect_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_total_comptes integer := 0;
    v_complets integer := 0;
    v_en_cours integer := 0;
    v_total_verse_soignants numeric := 0;
    v_en_attente_soignants numeric := 0;
    v_total_commission_jolene numeric := 0;
    v_en_attente_commission numeric := 0;
    v_volume_total numeric := 0;
    v_volume_en_attente numeric := 0;
BEGIN
    IF NOT est_admin() THEN
        RETURN '{"error":"Accès réservé aux administrateurs"}'::JSONB;
    END IF;

    SELECT COUNT(*) INTO v_total_comptes FROM stripe_connect_onboarding;
    SELECT COUNT(*) INTO v_complets FROM stripe_connect_onboarding WHERE statut = 'COMPLETE';
    SELECT COUNT(*) INTO v_en_cours FROM stripe_connect_onboarding WHERE statut IN ('PENDING', 'EN_COURS');

    -- Versé aux soignants (net après commission)
    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_total_verse_soignants
    FROM stripe_transfers WHERE statut = 'COMPLETED';
    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_en_attente_soignants
    FROM stripe_transfers WHERE statut = 'PENDING';

    -- Commission Jolene (CA réel plateforme)
    SELECT COALESCE(SUM(montant_commission), 0) INTO v_total_commission_jolene
    FROM stripe_transfers WHERE statut = 'COMPLETED';
    SELECT COALESCE(SUM(montant_commission), 0) INTO v_en_attente_commission
    FROM stripe_transfers WHERE statut = 'PENDING';

    -- Volume total transité (GMV = soignant + commission)
    SELECT COALESCE(SUM(montant_total), 0) INTO v_volume_total
    FROM stripe_transfers WHERE statut = 'COMPLETED';
    SELECT COALESCE(SUM(montant_total), 0) INTO v_volume_en_attente
    FROM stripe_transfers WHERE statut = 'PENDING';

    RETURN jsonb_build_object(
        'total_comptes', v_total_comptes,
        'complets', v_complets,
        'en_cours', v_en_cours,
        'total_verse_soignants', v_total_verse_soignants,
        'en_attente_soignants', v_en_attente_soignants,
        'total_commission_jolene', v_total_commission_jolene,
        'en_attente_commission', v_en_attente_commission,
        'volume_total', v_volume_total,
        'volume_en_attente', v_volume_en_attente
    );
END;
$function$;
