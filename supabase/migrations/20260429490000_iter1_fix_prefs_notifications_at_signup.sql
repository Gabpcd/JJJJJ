-- Itération 1 — Fix B.9 : préfs notifications à l'inscription
-- FK contrainte sur auth.users → seuls les soignants/étabs avec auth.users existant ont une pref

CREATE OR REPLACE FUNCTION public.fn_trg_init_preferences_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.id) THEN
    INSERT INTO preferences_notifications (utilisateur_id, canal_email, canal_sms, canal_push, canal_in_app)
    VALUES (NEW.id, true, false, true, true)
    ON CONFLICT (utilisateur_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_init_prefs_soignant ON public.soignants;
CREATE TRIGGER trg_init_prefs_soignant
  AFTER INSERT ON public.soignants
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_init_preferences_notifications();

DROP TRIGGER IF EXISTS trg_init_prefs_etab ON public.etablissements;
CREATE TRIGGER trg_init_prefs_etab
  AFTER INSERT ON public.etablissements
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_init_preferences_notifications();

INSERT INTO preferences_notifications (utilisateur_id, canal_email, canal_sms, canal_push, canal_in_app)
SELECT s.id, true, false, true, true
FROM soignants s
JOIN auth.users u ON u.id = s.id
LEFT JOIN preferences_notifications p ON p.utilisateur_id = s.id
WHERE p.utilisateur_id IS NULL AND s.supprime_le IS NULL
ON CONFLICT (utilisateur_id) DO NOTHING;

INSERT INTO preferences_notifications (utilisateur_id, canal_email, canal_sms, canal_push, canal_in_app)
SELECT e.id, true, false, true, true
FROM etablissements e
JOIN auth.users u ON u.id = e.id
LEFT JOIN preferences_notifications p ON p.utilisateur_id = e.id
WHERE p.utilisateur_id IS NULL AND e.supprime_le IS NULL
ON CONFLICT (utilisateur_id) DO NOTHING;

NOTIFY pgrst, 'reload schema';
