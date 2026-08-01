-- Élargit la précision avant que le planning exact puisse stocker la somme
-- de plusieurs centaines de créneaux. Cette migration reste volontairement
-- courte pour libérer immédiatement le verrou pris par ALTER COLUMN.
BEGIN;

ALTER TABLE public.missions
  ALTER COLUMN duree_heures TYPE numeric(7, 2);

DO $verifier_precision_duree$
DECLARE
  v_precision integer;
  v_echelle integer;
BEGIN
  SELECT c.numeric_precision, c.numeric_scale
  INTO v_precision, v_echelle
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'missions'
    AND c.column_name = 'duree_heures';

  IF v_precision IS DISTINCT FROM 7 OR v_echelle IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION
      'La colonne missions.duree_heures doit être de type numeric(7,2).';
  END IF;
END;
$verifier_precision_duree$;

COMMIT;
