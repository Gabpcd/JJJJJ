-- ============================================================================
-- Sprint 6 PR 5 — Persistance onboarding tutoriel (P1-1)
-- ============================================================================
-- Sauvegarde progression onboarding côté DB (au lieu de localStorage seul) pour
-- survivre aux changements de device + permettre le reset.
-- ============================================================================

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS onboarding_etapes_completees jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS onboarding_termine_le timestamptz;

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS onboarding_etapes_completees jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS onboarding_termine_le timestamptz;

CREATE OR REPLACE FUNCTION public.fn_marquer_etape_onboarding(
  p_etape_id text,
  p_termine boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_etape_id IS NULL OR length(trim(p_etape_id)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAPE_INVALIDE');
  END IF;

  -- Soignant
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    UPDATE public.soignants
    SET onboarding_etapes_completees = CASE
          WHEN onboarding_etapes_completees @> to_jsonb(p_etape_id::text)
          THEN onboarding_etapes_completees
          ELSE onboarding_etapes_completees || to_jsonb(p_etape_id::text)
        END,
        onboarding_termine_le = CASE WHEN p_termine THEN now() ELSE onboarding_termine_le END
    WHERE id = v_uid;
    RETURN jsonb_build_object('success', true, 'role', 'SOIGNANT');
  END IF;

  -- Étab
  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    UPDATE public.etablissements
    SET onboarding_etapes_completees = CASE
          WHEN onboarding_etapes_completees @> to_jsonb(p_etape_id::text)
          THEN onboarding_etapes_completees
          ELSE onboarding_etapes_completees || to_jsonb(p_etape_id::text)
        END,
        onboarding_termine_le = CASE WHEN p_termine THEN now() ELSE onboarding_termine_le END
    WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', true, 'role', 'ETAB');
  END IF;

  RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_marquer_etape_onboarding(text, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_reset_onboarding()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    UPDATE public.soignants
    SET onboarding_etapes_completees = '[]'::jsonb,
        onboarding_termine_le = NULL
    WHERE id = v_uid;
    RETURN jsonb_build_object('success', true, 'role', 'SOIGNANT');
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    UPDATE public.etablissements
    SET onboarding_etapes_completees = '[]'::jsonb,
        onboarding_termine_le = NULL
    WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', true, 'role', 'ETAB');
  END IF;

  RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_reset_onboarding() TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_etat_onboarding()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_etapes jsonb;
  v_termine_le timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    SELECT onboarding_etapes_completees, onboarding_termine_le
    INTO v_etapes, v_termine_le
    FROM public.soignants WHERE id = v_uid;
    RETURN jsonb_build_object('success', true, 'role', 'SOIGNANT',
                                'etapes', v_etapes,
                                'termine_le', v_termine_le);
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    SELECT onboarding_etapes_completees, onboarding_termine_le
    INTO v_etapes, v_termine_le
    FROM public.etablissements WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', true, 'role', 'ETAB',
                                'etapes', v_etapes,
                                'termine_le', v_termine_le);
  END IF;

  RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_etat_onboarding() TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT6_PR5_ONBOARDING_PERSISTENCE_INSTALLED',
    'pr', 'PR 5 Sprint 6',
    'rpcs', jsonb_build_array('fn_marquer_etape_onboarding', 'fn_reset_onboarding', 'fn_etat_onboarding'),
    'tables_etendues', jsonb_build_array('soignants.onboarding_etapes_completees', 'etablissements.onboarding_etapes_completees')
  )
);
