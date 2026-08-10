-- La première version appliquée au staging imposait encore TAUX_HORAIRE par
-- une contrainte CHECK. La version finale délègue ce verrou au trigger afin de
-- préserver les litiges historiques et les remplacements automatiques validés.
-- La production a déjà supprimé cette contrainte ; IF EXISTS rend le replay sûr.

ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS missions_mode_remuneration_lancement_check;
