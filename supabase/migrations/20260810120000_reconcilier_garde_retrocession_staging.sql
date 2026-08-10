-- Réconcilie le garde-fou de lancement sur les environnements où la version
-- 20260808150856 avait été enregistrée avant sa correction finale.
--
-- Cette migration est volontairement idempotente : la production possède
-- déjà cette définition, tandis que le staging CI exécute encore l'ancienne.

CREATE OR REPLACE FUNCTION public.fn_bloquer_retrocession_prelaunch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_role text := COALESCE(
    current_setting('request.jwt.claim.role', true), ''
  );
  v_seed_reason text := COALESCE(
    current_setting('jolene.admin_seed_override_reason', true), ''
  );
  v_empechement_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
  v_empechement_validated text := COALESCE(
    current_setting('jolene.empechement_mission_validated', true), ''
  );
BEGIN
  IF NEW.mode_remuneration = 'TAUX_HORAIRE'
     AND NEW.retrocession_pct IS NULL THEN
    RETURN NEW;
  END IF;

  -- Une édition qui ne change pas un ancien montage reste possible : les
  -- litiges, annulations et opérations de support ne doivent pas être cassés.
  IF TG_OP = 'UPDATE'
     AND NEW.mode_remuneration IS NOT DISTINCT FROM OLD.mode_remuneration
     AND NEW.retrocession_pct IS NOT DISTINCT FROM OLD.retrocession_pct THEN
    RETURN NEW;
  END IF;

  -- Les fixtures/migrations contrôlées conservent la capacité de représenter
  -- un historique antérieur au lancement, jamais via une session client.
  IF v_role = 'service_role' AND v_seed_reason <> '' THEN
    RETURN NEW;
  END IF;

  -- Le remplacement automatique peut recopier une ancienne rétrocession
  -- seulement après validation exacte par dec_00_guard_empechement. Un client
  -- ne peut donc ni choisir ce mode, ni fabriquer un remplacement arbitraire.
  IF TG_OP = 'INSERT'
     AND NEW.mission_source = 'REMPLACEMENT'
     AND NEW.remplacement_de_mission_id IS NOT NULL
     AND v_empechement_context <> ''
     AND v_empechement_context = v_empechement_validated THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION '[RETROCESSION_DESACTIVEE] La rétrocession de cabinet n’est pas disponible au lancement. Publiez une mission libérale directe à taux horaire.'
    USING ERRCODE = 'feature_not_supported';
END;
$body$;
