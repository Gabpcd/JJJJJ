-- Élargit la précision avant que le planning exact puisse stocker la somme
-- de plusieurs centaines de créneaux. Cette migration reste volontairement
-- courte pour libérer immédiatement le verrou pris par ALTER COLUMN.
BEGIN;

-- PostgreSQL refuse de changer le type d'une colonne citée dans la définition
-- d'un trigger (notamment UPDATE OF duree_heures). On sauvegarde uniquement
-- les triggers réellement dépendants, puis on les recrée à l'identique dans
-- la même transaction. Les fonctions de trigger et leurs droits ne changent
-- pas.
CREATE TEMP TABLE jolene_triggers_duree_mission (
  nom name PRIMARY KEY,
  definition text NOT NULL
) ON COMMIT DROP;

INSERT INTO pg_temp.jolene_triggers_duree_mission (nom, definition)
SELECT DISTINCT
  t.tgname,
  pg_catalog.pg_get_triggerdef(t.oid, true)
FROM pg_catalog.pg_trigger t
WHERE t.tgrelid = 'public.missions'::pg_catalog.regclass
  AND NOT t.tgisinternal
  AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_depend d
    JOIN pg_catalog.pg_attribute a
      ON a.attrelid = d.refobjid
     AND a.attnum = d.refobjsubid
    WHERE d.classid = 'pg_catalog.pg_trigger'::pg_catalog.regclass
      AND d.objid = t.oid
      AND d.refclassid = 'pg_catalog.pg_class'::pg_catalog.regclass
      AND d.refobjid = t.tgrelid
      AND a.attname = 'duree_heures'
  );

DO $detacher_triggers_duree$
DECLARE
  v_trigger record;
BEGIN
  FOR v_trigger IN
    SELECT nom
    FROM pg_temp.jolene_triggers_duree_mission
    ORDER BY nom
  LOOP
    EXECUTE pg_catalog.format(
      'DROP TRIGGER %I ON public.missions',
      v_trigger.nom
    );
  END LOOP;
END;
$detacher_triggers_duree$;

ALTER TABLE public.missions
  ALTER COLUMN duree_heures TYPE numeric(7, 2);

DO $restaurer_triggers_duree$
DECLARE
  v_trigger record;
BEGIN
  FOR v_trigger IN
    SELECT definition
    FROM pg_temp.jolene_triggers_duree_mission
    ORDER BY nom
  LOOP
    EXECUTE v_trigger.definition;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.jolene_triggers_duree_mission sauvegarde
    LEFT JOIN pg_catalog.pg_trigger t
      ON t.tgrelid = 'public.missions'::pg_catalog.regclass
     AND t.tgname = sauvegarde.nom
     AND NOT t.tgisinternal
    WHERE t.oid IS NULL
  ) THEN
    RAISE EXCEPTION
      'Un trigger dépendant de missions.duree_heures n''a pas été restauré.';
  END IF;
END;
$restaurer_triggers_duree$;

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
