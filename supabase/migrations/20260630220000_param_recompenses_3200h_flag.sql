-- B6 — Flag « recompenses_3200h_actives » (avantages par palier du Parcours 3200h :
-- formations offertes, -15 % RCP, accompagnement installation, kit libéral).
-- Ces avantages ne sont pas encore branchés → OFF par défaut. Le composant
-- ProgressionJalons3200h garde les paliers/heures mais masque la promesse d'avantage
-- tant que le flag est à 0. Passer à 1 quand les partenariats sont en place.
-- Idempotent ; lu côté front via fn_param_bool (GRANT authenticated déjà posé).

INSERT INTO public.parametres_systeme (cle, valeur, label, description, categorie, cablee)
VALUES (
  'recompenses_3200h_actives', 0, 'Récompenses Parcours 3200h actives',
  'Affiche les avantages concrets par palier (formations, -15 % RCP, accompagnement, kit libéral) sur le Parcours 3200h. OFF tant que les partenariats ne sont pas branchés — 1 pour activer, 0 pour masquer la promesse.',
  'PRODUIT', true
)
ON CONFLICT (cle) DO NOTHING;
