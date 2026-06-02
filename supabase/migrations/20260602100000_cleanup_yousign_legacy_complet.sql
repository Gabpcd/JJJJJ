-- Nettoyage complet du flux Yousign legacy (déprécié Sprint 6 PR 6, 0 ligne en prod).
-- Le flux de signature actif est CANVAS (manuscrit) + JOLENE_OTP (SMS, art. 1366-1367
-- Code civil). Yousign n'est plus un sous-traitant de données : retrait DB + front + edge.
-- 1) Patcher les 2 fonctions qui référencent yousign AVANT de drop table/colonnes.
-- 2) DROP table signatures_yousign (+ policy pol_yousign_select en cascade) + colonnes.
-- 3) Resserrer la contrainte mode_signature (retrait de YOUSIGN).
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  -- fn_protect_contrat_integrity : retirer les 2 lignes de protection des colonnes yousign
  v_def := pg_get_functiondef('public.fn_protect_contrat_integrity()'::regprocedure);
  v_new := replace(v_def, E'    NEW.yousign_procedure_id := OLD.yousign_procedure_id;\n', '');
  v_new := replace(v_new, E'    NEW.yousign_document_id := OLD.yousign_document_id;\n', '');
  IF v_new ILIKE '%yousign%' THEN RAISE EXCEPTION 'protect: refs yousign restantes'; END IF;
  IF v_new = v_def THEN RAISE EXCEPTION 'protect: aucun remplacement'; END IF;
  EXECUTE v_new;

  -- fn_supprimer_mon_compte : retirer l'UPDATE signatures_yousign + l'entrée tableau de tables
  v_def := pg_get_functiondef('public.fn_supprimer_mon_compte()'::regprocedure);
  v_new := replace(v_def, E'    -- Signatures Yousign\n    UPDATE signatures_yousign SET signataire_soignant_id = NULL WHERE signataire_soignant_id = v_uid::text;\n', '');
  v_new := replace(v_new, '''signatures_yousign'',', '');
  v_new := replace(v_new, ',''signatures_yousign''', '');
  v_new := replace(v_new, '''signatures_yousign''', '');
  IF v_new ILIKE '%yousign%' THEN RAISE EXCEPTION 'supprimer_compte: refs yousign restantes'; END IF;
  IF v_new = v_def THEN RAISE EXCEPTION 'supprimer_compte: aucun remplacement'; END IF;
  EXECUTE v_new;
END $mig$;

-- DROP table (cascade : policy pol_yousign_select + éventuelles FK) + colonnes legacy
DROP TABLE IF EXISTS public.signatures_yousign CASCADE;
ALTER TABLE public.contrats_mission DROP COLUMN IF EXISTS yousign_procedure_id;
ALTER TABLE public.contrats_mission DROP COLUMN IF EXISTS yousign_document_id;
ALTER TABLE public.missions DROP COLUMN IF EXISTS yousign_id_procedure;
ALTER TABLE public.missions DROP COLUMN IF EXISTS yousign_statut;

-- Resserrer la contrainte mode_signature (retrait de YOUSIGN, 0 ligne concernée)
ALTER TABLE public.contrats_mission DROP CONSTRAINT IF EXISTS contrats_mission_mode_signature_check;
ALTER TABLE public.contrats_mission ADD CONSTRAINT contrats_mission_mode_signature_check
  CHECK (mode_signature = ANY (ARRAY['CANVAS'::text, 'JOLENE_OTP'::text]));
