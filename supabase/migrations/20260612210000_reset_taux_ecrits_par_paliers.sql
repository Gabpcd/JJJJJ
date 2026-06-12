-- Complément de 20260612200000 (paliers désactivés) : le recalcul mensuel
-- ÉCRIVAIT le taux du palier directement dans etablissements.taux_commission_negocie
-- (cf. fn_recalculer_palier_commission). Des taux de palier historiques
-- (12,5/10/8 %) peuvent donc persister et être facturés. Décision produit :
-- 15 % unique, taux négocié uniquement par accord explicite.
-- → remise au défaut (NULL = 15 %) de tout taux posé par le mécanisme de
-- paliers (identifiable par palier_commission_id non NULL). Les futurs taux
-- négociés seront posés via Admin → Taux commission, sans palier_commission_id.
DO $reset$
BEGIN
  PERFORM set_config('app.internal_operation', 'true', true);
  UPDATE public.etablissements
     SET taux_commission_negocie = NULL,
         palier_commission_id = NULL,
         modifie_le = now()
   WHERE palier_commission_id IS NOT NULL;
END;
$reset$;
