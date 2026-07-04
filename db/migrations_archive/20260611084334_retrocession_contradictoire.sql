-- Déclaration contradictoire des honoraires de rétrocession (appliquée prod via
-- MCP, version 20260611084334, cron testé) : le cabinet déclare avec justificatif
-- → le REMPLAÇANT confirme en 1 clic (fn_confirmer_honoraires_retrocession) ou
-- conteste sous 48h (litige) → note d'honoraires et commission ne deviennent
-- définitives qu'à la confirmation (ou auto-confirmation 48h sans litige ouvert,
-- cron horaire fn_auto_confirmer_honoraires). Le run mensuel de commission attend
-- désormais honoraires_confirmes_le (patch ciblé fn_auto_facturation_mensuelle).
-- Colonne : missions.honoraires_confirmes_le. Corps complets en prod.
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS honoraires_confirmes_le timestamptz;
