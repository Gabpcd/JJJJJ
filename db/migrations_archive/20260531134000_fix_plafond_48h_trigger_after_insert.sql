-- BUG : dec_verifier_plafond_48h (trigger BEFORE INSERT sur missions) insère dans
-- conformite_travail avec NEW.id → la mission n'existe pas encore dans la table →
-- FK violation (conformite_travail_mission_id_fkey). Le cycle normal (fn_creer_mission
-- sans soignant, puis UPDATE ASSIGNEE via fn_traiter_candidature) évitait le chemin,
-- mais tout INSERT direct avec soignant_assigne_id non NULL plantait.
-- Fix : séparer INSERT et UPDATE en 2 triggers :
--   AFTER INSERT (la mission existe, FK OK — le soignant_assigne_id peut être set au CREATE)
--   BEFORE UPDATE (le cas normal via acceptation de candidature — le BEFORE permet de bloquer)
DROP TRIGGER IF EXISTS dec_mission_plafond_48h ON public.missions;
CREATE TRIGGER dec_mission_plafond_48h_after_insert
  AFTER INSERT ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_plafond_48h();
CREATE TRIGGER dec_mission_plafond_48h_before_update
  BEFORE UPDATE ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_plafond_48h();
