-- CONSOLIDATION notification mission urgente (élimine le doublon SMS).
-- Il existait DEUX triggers sur missions pour les missions urgentes :
--   * trg_auto_notify_mission_urgente (fn_trg_auto_notify_mission_urgente) : COMPLET
--     → notif in-app + EMAIL (à tous les soignants du pool compatibles) + SMS (si
--     pool_urgence_sms_opt_in), avec filtrage distance/docs/compatibilité. Référence.
--   * trg_sms_mission_urgente (fn_trg_sms_mission_urgente) : REDONDANT, ne faisait
--     qu'un SMS (via email_queue). Avant le fix #437 il était mort (filtrait sms_actif,
--     défaut false) ; le réactiver créerait un SMS en double avec auto_notify.
-- On supprime le trigger + la fonction redondants : une seule source de vérité pour
-- la notification urgente (in-app + email + SMS opt-in). Le "mail + SMS" reste assuré
-- par auto_notify (email à tous les soignants du pool, SMS aux opt-in).
DROP TRIGGER IF EXISTS trg_sms_mission_urgente ON public.missions;
DROP FUNCTION IF EXISTS public.fn_trg_sms_mission_urgente();
