-- Conflit gel/recalcul du taux de commission : dec_calculer_commission relisait
-- etablissements.taux_commission_negocie au passage TERMINEE, contournant le
-- taux gelé à l'assignation (taux_commission_fige, posé par
-- fn_geler_mission_a_assignation). Un changement de taux admin entre
-- l'assignation et la fin de mission modifiait la commission d'une mission
-- déjà engagée. Priorité désormais : taux gelé > taux étab courant > 15 %.
CREATE OR REPLACE FUNCTION public.dec_calculer_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_taux NUMERIC;
BEGIN
    IF NEW.statut = 'TERMINEE' AND NEW.net_a_payer IS NOT NULL THEN
        v_taux := COALESCE(
            NEW.taux_commission_fige,
            (SELECT e.taux_commission_negocie FROM etablissements e WHERE e.id = NEW.etablissement_id),
            15.00
        );

        NEW.taux_commission := v_taux;
        NEW.montant_commission_ht := ROUND(NEW.net_a_payer * (v_taux / 100.0), 2);
        NEW.montant_commission_tva := ROUND(NEW.montant_commission_ht * 0.20, 2);
        NEW.montant_commission_ttc := NEW.montant_commission_ht + NEW.montant_commission_tva;
    END IF;
    RETURN NEW;
END;
$function$;
