-- Fix broken trigger referencing non-existent serie_id column
DROP TRIGGER IF EXISTS dec_limite_serie ON public.missions;
DROP FUNCTION IF EXISTS dec_limiter_missions_serie();
