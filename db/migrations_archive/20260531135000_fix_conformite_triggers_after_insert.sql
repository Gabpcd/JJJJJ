-- BUG systémique : 3 triggers BEFORE INSERT/UPDATE sur missions (repos_11h,
-- moyenne_44h, repos_hebdo_35h) insèrent dans conformite_travail avec NEW.id →
-- la mission n'existe pas encore (BEFORE INSERT) → FK violation. Fix identique
-- au plafond_48h : séparer en AFTER INSERT + BEFORE UPDATE.
DROP TRIGGER IF EXISTS dec_mission_repos_11h ON public.missions;
CREATE TRIGGER dec_mission_repos_11h_after_insert
  AFTER INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_repos_11h();
CREATE TRIGGER dec_mission_repos_11h_before_update
  BEFORE UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_repos_11h();

DROP TRIGGER IF EXISTS trg_dec_verifier_moyenne_44h ON public.missions;
CREATE TRIGGER trg_dec_verifier_moyenne_44h_after_insert
  AFTER INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_moyenne_44h_12_semaines();
CREATE TRIGGER trg_dec_verifier_moyenne_44h_before_update
  BEFORE UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_moyenne_44h_12_semaines();

DROP TRIGGER IF EXISTS trg_dec_verifier_repos_hebdo_35h ON public.missions;
CREATE TRIGGER trg_dec_verifier_repos_hebdo_35h_after_insert
  AFTER INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_repos_hebdo_35h();
CREATE TRIGGER trg_dec_verifier_repos_hebdo_35h_before_update
  BEFORE UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_repos_hebdo_35h();
