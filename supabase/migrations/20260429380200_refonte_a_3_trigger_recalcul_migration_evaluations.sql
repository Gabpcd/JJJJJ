-- Refonte.A.3 — Trigger recalcul score v2 + bulk migration evaluations → notations_missions
--
-- Trigger : INSERT/UPDATE notations_missions OR UPDATE missions(statut) OR UPDATE litiges(statut)
-- → recalcule score soignant + score étab si applicable
-- Idempotent : EXCEPTION WHEN OTHERS THEN RETURN NEW (recalcul ne bloque jamais les triggers métier).

CREATE OR REPLACE FUNCTION public.fn_trg_recalculer_score_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_soignant_id UUID;
  v_etab_id UUID;
BEGIN
  IF TG_TABLE_NAME = 'notations_missions' THEN
    IF NEW.sens = 'ETAB_VERS_SOIGNANT' THEN
      v_soignant_id := NEW.note_id; v_etab_id := NEW.notateur_id;
    ELSE
      v_soignant_id := NEW.notateur_id; v_etab_id := NEW.note_id;
    END IF;
    PERFORM public.fn_calculer_score_fiabilite_v2(v_soignant_id, 'notation_recue');
    IF v_etab_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_etablissement(v_etab_id);
    END IF;

  ELSIF TG_TABLE_NAME = 'missions' THEN
    IF NEW.statut IN ('TERMINEE','ABSENCE') AND COALESCE(OLD.statut, '') <> NEW.statut::text
       AND NEW.soignant_assigne_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_assigne_id, 'mission_' || NEW.statut::text);
    END IF;

  ELSIF TG_TABLE_NAME = 'litiges' THEN
    IF NEW.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE','RESOLU_ACCORD_PARTIES')
       AND COALESCE(OLD.statut, '') <> NEW.statut::text
       AND NEW.soignant_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_id, 'litige_resolu');
      IF NEW.etablissement_id IS NOT NULL THEN
        PERFORM public.fn_calculer_score_etablissement(NEW.etablissement_id);
      END IF;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalcul_score_v2_notations ON public.notations_missions;
CREATE TRIGGER trg_recalcul_score_v2_notations
  AFTER INSERT OR UPDATE OF critere_1, critere_2, critere_3, critere_4, masque ON public.notations_missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_recalculer_score_v2();

DROP TRIGGER IF EXISTS trg_recalcul_score_v2_missions ON public.missions;
CREATE TRIGGER trg_recalcul_score_v2_missions
  AFTER UPDATE OF statut ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_recalculer_score_v2();

DROP TRIGGER IF EXISTS trg_recalcul_score_v2_litiges ON public.litiges;
CREATE TRIGGER trg_recalcul_score_v2_litiges
  AFTER UPDATE OF statut ON public.litiges
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_recalculer_score_v2();

-- Bulk migration evaluations → notations_missions (rétrocompat)
INSERT INTO public.notations_missions (
  mission_id, notateur_id, note_id, sens, critere_1, critere_2, critere_3, critere_4, commentaire, cree_le
)
SELECT
  e.mission_id, e.evaluateur_id, e.evalue_id,
  CASE WHEN e.type_evaluateur = 'ETABLISSEMENT' THEN 'ETAB_VERS_SOIGNANT'::public.sens_notation
       ELSE 'SOIGNANT_VERS_ETAB'::public.sens_notation END,
  GREATEST(1, LEAST(5, e.note)), GREATEST(1, LEAST(5, e.note)),
  GREATEST(1, LEAST(5, e.note)), GREATEST(1, LEAST(5, e.note)),
  e.commentaire, e.cree_le
FROM public.evaluations e
WHERE NOT EXISTS (
  SELECT 1 FROM public.notations_missions n
  WHERE n.mission_id = e.mission_id
    AND n.sens = CASE WHEN e.type_evaluateur = 'ETABLISSEMENT' THEN 'ETAB_VERS_SOIGNANT'::public.sens_notation ELSE 'SOIGNANT_VERS_ETAB'::public.sens_notation END
)
ON CONFLICT (mission_id, sens) DO NOTHING;

-- Bulk recalcul scores soignants existants
DO $$
DECLARE v_soignant RECORD;
BEGIN
  FOR v_soignant IN
    SELECT DISTINCT s.id FROM soignants s
    WHERE s.supprime_le IS NULL
      AND EXISTS (SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id)
  LOOP
    BEGIN
      PERFORM public.fn_calculer_score_fiabilite_v2(v_soignant.id, 'bulk_initial_v2');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
