-- Phase Audit Fix : nettoyage des overloads fn_creer_mission (P2-B)
--
-- Trois signatures coexistaient :
--   - 10 args (ancienne — sans spécialité)
--   - 11 args (avec p_serie_id — utilisée nulle part en pratique)
--   - 12 args (actuelle — avec spécialité + accepte_non_specialises)
--
-- Le frontend (FormulaireMission.tsx:304-317) appelle exclusivement la
-- signature 12 args. Aucune fonction SQL interne ni edge function ne
-- référence les 10/11 args. Drop des 2 anciennes pour éviter toute
-- ambiguïté future de résolution PostgREST/PL.

DROP FUNCTION IF EXISTS public.fn_creer_mission(
  text, text, type_profession, text, timestamp with time zone,
  timestamp with time zone, numeric, boolean, integer, text
);

DROP FUNCTION IF EXISTS public.fn_creer_mission(
  text, text, type_profession, text, timestamp with time zone,
  timestamp with time zone, numeric, boolean, integer, uuid, text
);
