-- Restaurer GRANT EXECUTE sur fn_modifier_mon_profil et fn_creer_mission
-- après les DROP des anciennes signatures dans les migrations
-- 20260427150100 (fn_creer_mission) et 20260428180000 (fn_modifier_mon_profil).
--
-- Le DROP/CREATE de fonction PostgreSQL réinitialise toujours proacl à
-- {postgres=X/postgres}. Le CREATE OR REPLACE seul aurait préservé,
-- mais comme on a aussi DROP les anciennes signatures (différentes du
-- CREATE), la nouvelle repart de zéro côté permissions.
--
-- Symptôme : Gabrielle voit un 403 sur fn_modifier_mon_profil quand
-- elle clique « Continuer » dans le wizard de complétion profil.
-- Cause : proacl vide pour authenticated → PostgREST refuse l'appel.

GRANT EXECUTE ON FUNCTION public.fn_modifier_mon_profil(
  text, text, text, date, text, text, text, numeric, numeric, integer,
  text, text, text, text[], text, integer, text[], numeric, text, text,
  text, boolean, integer, boolean, boolean, boolean, boolean, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_creer_mission(
  text, text, type_profession, text, timestamp with time zone,
  timestamp with time zone, numeric, boolean, integer, text, text, boolean
) TO authenticated;

NOTIFY pgrst, 'reload schema';
