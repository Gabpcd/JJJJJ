-- Missions à rétrocession : taux horaire 0 = sentinelle « non applicable » (le
-- remplaçant est payé en % des honoraires encaissés par le titulaire). Le SMIC
-- reste le plancher pour toutes les missions à taux horaire réel.
-- NOTE : appliquée prod via MCP (version 20260610181036).
ALTER TABLE public.missions DROP CONSTRAINT IF EXISTS chk_taux_horaire_min;
ALTER TABLE public.missions DROP CONSTRAINT IF EXISTS chk_taux_horaire_raisonnable;
ALTER TABLE public.missions ADD CONSTRAINT chk_taux_horaire_raisonnable
  CHECK (taux_horaire_base = 0 OR (taux_horaire_base >= 11.88 AND taux_horaire_base <= 1000));
