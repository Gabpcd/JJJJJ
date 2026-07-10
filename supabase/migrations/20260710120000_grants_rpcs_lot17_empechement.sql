-- Recapture hotfix prod (10/07/2026, règle 9.0 exception incident) : les RPCs
-- créées de zéro par les migrations 20260709260000 (Lot 17 F5/F2) et
-- 20260710090000 (empêchement impérieux) n'avaient AUCUN GRANT EXECUTE pour
-- authenticated — contrairement aux CREATE OR REPLACE de fonctions existantes
-- qui conservent leurs ACLs, une fonction NOUVELLE n'hérite de rien dans cette
-- base (pas de default privilege vers authenticated). Résultat : 42501
-- « permission denied » pour tout utilisateur connecté (page Mes disponibilités,
-- vivier, déclaration d'empêchement, traçage republication inopérants).
-- GRANTs appliqués en prod via SQL direct le 10/07/2026, recapturés ici.
GRANT EXECUTE ON FUNCTION public.fn_declarer_empechement_imperieux(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_definir_disponibilite(date, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_vivier_disponibilites(date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_marquer_source_mission(uuid, text) TO authenticated;
