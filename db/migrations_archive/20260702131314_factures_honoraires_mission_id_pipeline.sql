-- 6d.1 (Lot 6d) — Revenus « une seule histoire d'argent » : l'Aperçu et
-- l'onglet Factures lisent LA MÊME source (fn_mes_factures_honoraires).
-- Ajout de mission_id au retour pour joindre factures ↔ missions côté client
-- (pipeline À valider → En attente de paiement → Payé).
-- Changement du type de retour → DROP + CREATE (OR REPLACE impossible).
DROP FUNCTION IF EXISTS public.fn_mes_factures_honoraires();

CREATE FUNCTION public.fn_mes_factures_honoraires()
RETURNS TABLE(
  id uuid, numero_facture text, etablissement_nom text, mission_intitule text,
  montant_ttc numeric, statut text, date_emission date, date_echeance date,
  date_paiement date, mission_id uuid
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn_mfh$
    SELECT fh.id, fh.numero_facture, e.nom, m.intitule,
           fh.montant_ttc, fh.statut, fh.date_emission, fh.date_echeance, fh.date_paiement,
           fh.mission_id
    FROM factures_honoraires fh
    JOIN etablissements e ON e.id = fh.etablissement_id
    LEFT JOIN missions m ON m.id = fh.mission_id
    WHERE fh.soignant_id = auth.uid()
    ORDER BY fh.date_emission DESC;
$fn_mfh$;

GRANT EXECUTE ON FUNCTION public.fn_mes_factures_honoraires() TO authenticated, service_role;
