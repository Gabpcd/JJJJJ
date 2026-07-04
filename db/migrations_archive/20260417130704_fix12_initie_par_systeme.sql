-- ============================================================
-- CP-LITIGES-7a FIX 12 — litiges.initie_par : ajout valeur 'SYSTEME'
-- ============================================================
-- `initie_par` est une colonne TEXT NOT NULL avec un CHECK constraint
-- nommé `litiges_initie_par_check` qui n'accepte aujourd'hui que
-- ('SOIGNANT', 'ETABLISSEMENT') — vérifié via MCP execute_sql.
--
-- On étend la contrainte à ('SOIGNANT', 'ETABLISSEMENT', 'SYSTEME') pour
-- permettre aux litiges auto-créés par fn_auto_creation_litiges_presence
-- d'être distingués des litiges ouverts par un humain (soignant/étab).
--
-- Ce FIX livre uniquement la STRUCTURE. La consommation (bascule de
-- fn_auto_creation_litiges_presence : initie_par='ETABLISSEMENT' →
-- initie_par='SYSTEME', wording email LITIGE_OUVERTURE_SYSTEME) est
-- livrée dans un FIX suivant.
-- ============================================================

BEGIN;

-- DROP + recreate : ALTER CONSTRAINT ne permet pas de changer le corps.
ALTER TABLE public.litiges
  DROP CONSTRAINT IF EXISTS litiges_initie_par_check;

ALTER TABLE public.litiges
  ADD CONSTRAINT litiges_initie_par_check
  CHECK (initie_par IN ('SOIGNANT', 'ETABLISSEMENT', 'SYSTEME'));

COMMENT ON COLUMN public.litiges.initie_par IS
  'CP-LITIGES-7a FIX 12 — origine de l''ouverture du litige : '
  'SOIGNANT (action manuelle soignant), ETABLISSEMENT (action manuelle '
  'établissement), SYSTEME (auto-création par fn_auto_creation_litiges_'
  'presence sur ABSENCE / DEPART_ANTICIPE / RETARD_IMPORTANT).';

COMMIT;
