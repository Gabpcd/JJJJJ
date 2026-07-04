-- ============================================================
-- SMS opt-out + alignement des canaux SMS
--
-- Ajoute le flag sms_alertes_actives sur soignants pour :
--   - Mission urgente (alerte pool urgence)
--   - Rappel mission J-1
--
-- Ce flag s'ajoute aux mécanismes existants :
--   - sms_actif : flag historique (consentement initial à recevoir des SMS,
--     posé à l'inscription). Ne couvre pas la granularité opt-out par type.
--   - fn_doit_notifier : RPC qui consulte les préférences fines par type
--     d'événement (URGENCE, LITIGE_OUVERT, etc.) et par canal.
--
-- send-sms va désormais checker AND sms_actif AND sms_alertes_actives
-- (principe de l'opt-in cumulatif) avant tout envoi pour ces 2 types.
-- ============================================================

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS sms_alertes_actives boolean DEFAULT true;

-- Backfill : tous les soignants existants opt-in par défaut, sauf ceux qui
-- ont explicitement désactivé sms_actif (consentement initial = NON).
UPDATE public.soignants
SET sms_alertes_actives = COALESCE(sms_actif, true)
WHERE sms_alertes_actives IS NULL;

COMMENT ON COLUMN public.soignants.sms_alertes_actives IS
  'Opt-in granulaire pour les SMS d''alerte (mission urgente, rappel J-1). Différent de sms_actif (consentement initial à recevoir des SMS). Les 2 flags sont vérifiés en cumulatif côté edge function send-sms.';
