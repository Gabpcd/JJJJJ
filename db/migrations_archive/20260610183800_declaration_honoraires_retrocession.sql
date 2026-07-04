-- Boucle financière rétrocession : en fin de mission TERMINEE en mode RETROCESSION,
-- le titulaire déclare les honoraires bruts encaissés (feuilles de soins) →
-- total_brut/net_a_payer = montant rétrocédé (pct) et commission Jolene calculée
-- dessus (taux figé/négocié/15%). Le paiement au remplaçant suit le circuit
-- standard (déclaration de virement). Notification du soignant avec le détail.
-- RPC : fn_declarer_honoraires_retrocession(p_mission_id, p_montant_honoraires)
-- + colonne missions.montant_honoraires_bruts.
-- NOTE : appliquée prod via MCP (version 20260610183800), corps complet en prod.
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS montant_honoraires_bruts numeric;
