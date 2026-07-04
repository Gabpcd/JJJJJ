-- Éradication de CDDU partout (décision : CDD uniquement).
-- 1) Données : supprime les plafonds RIST CDDU_USAGE (équivalents CDD présents).
-- 2) Fonctions : remplace CDDU_USAGE puis CDDU par CDD dans tous les corps.
-- 3) Enum type_contrat : retire la valeur CDDU_USAGE (recréation du type).

-- 1) Données
DELETE FROM public.rist_plafonds WHERE type_contrat::text = 'CDDU_USAGE';

-- 2) Fonctions (boucle dynamique, _USAGE remplacé avant CDDU)
DO $mig$
DECLARE r RECORD; v_def text; v_new text;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p
    WHERE p.pronamespace='public'::regnamespace
      AND pg_get_functiondef(p.oid) LIKE '%CDDU%'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(replace(v_def, 'CDDU_USAGE', 'CDD'), 'CDDU', 'CDD');
    IF v_new <> v_def THEN EXECUTE v_new; END IF;
  END LOOP;
END $mig$;

-- 3) Enum : retirer CDDU_USAGE (seulement s'il existe encore)
DO $enum$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
    WHERE t.typname='type_contrat' AND e.enumlabel='CDDU_USAGE'
  ) THEN
    ALTER TABLE public.soignants ALTER COLUMN type_contrat DROP DEFAULT;
    ALTER TYPE public.type_contrat RENAME TO type_contrat_old;
    CREATE TYPE public.type_contrat AS ENUM ('CDD','VACATION','LIBERAL','SALARIE');
    ALTER TABLE public.soignants ALTER COLUMN type_contrat TYPE public.type_contrat USING type_contrat::text::public.type_contrat;
    ALTER TABLE public.rist_plafonds ALTER COLUMN type_contrat TYPE public.type_contrat USING type_contrat::text::public.type_contrat;
    ALTER TABLE public.soignants ALTER COLUMN type_contrat SET DEFAULT 'CDD';
    DROP TYPE public.type_contrat_old;
  END IF;
END $enum$;

NOTIFY pgrst, 'reload schema';
