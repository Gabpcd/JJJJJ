-- ============================================================
-- CP-C-3 A — Blocage auto étab : colonnes + historique + check
-- ============================================================
-- Objectifs :
-- - Colonnes distinctes du flag manuel peut_publier_missions :
--   bloque_auto_le, bloque_auto_raisons (posées par CP-C-3 C cron)
-- - Table historique_blocages_etablissements append-only (audit)
-- - fn_creer_mission : vérifier les 2 cadenas avant publication
--   (peut_publier_missions=TRUE AND bloque_auto_le IS NULL)
-- Tickets : préparation E1, E7, E9
-- ============================================================

-- A. Colonnes blocage auto sur etablissements
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS bloque_auto_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bloque_auto_raisons JSONB;

COMMENT ON COLUMN public.etablissements.bloque_auto_le IS
  'CP-C-3 : date blocage auto pour retards paiement soignant ou facture commission >45j. NULL = non bloqué.';
COMMENT ON COLUMN public.etablissements.bloque_auto_raisons IS
  'CP-C-3 : snapshot JSONB au moment du blocage { paiements_retard_nb, paiements_retard_montant, factures_retard_nb, factures_retard_montant }.';

-- B. Table historique dédiée (append-only, audit)
CREATE TABLE IF NOT EXISTS public.historique_blocages_etablissements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id UUID NOT NULL REFERENCES public.etablissements(id),
  action TEXT NOT NULL CHECK (action IN ('BLOCAGE', 'DEBLOCAGE')),
  raisons JSONB,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hist_blocages_etab
  ON public.historique_blocages_etablissements(etablissement_id, cree_le DESC);

-- RLS : admins + étab propriétaire en lecture
ALTER TABLE public.historique_blocages_etablissements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS historique_blocages_admin_read ON public.historique_blocages_etablissements;
CREATE POLICY historique_blocages_admin_read
  ON public.historique_blocages_etablissements
  FOR SELECT TO authenticated
  USING (est_admin());

DROP POLICY IF EXISTS historique_blocages_etab_read ON public.historique_blocages_etablissements;
CREATE POLICY historique_blocages_etab_read
  ON public.historique_blocages_etablissements
  FOR SELECT TO authenticated
  USING (etablissement_id = mon_etablissement_id());

-- C. Update fn_creer_mission (signature 10 params) : check 2 cadenas
CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL::text,
  p_profession_requise type_profession DEFAULT NULL::type_profession,
  p_service text DEFAULT NULL::text,
  p_debut_le timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_fin_le timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_taux_horaire_base numeric DEFAULT NULL::numeric,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID;
    v_etab RECORD;
    v_mission_id UUID;
    v_mode TEXT;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Acces refuse"}'::JSONB;
    END IF;

    SELECT peut_publier_missions, statut_verification, contrat_valide,
           bloque_auto_le, bloque_auto_raisons
    INTO v_etab FROM etablissements WHERE id = v_etab_id;

    -- Cadenas 1 : vérification admin (peut_publier_missions)
    IF NOT est_admin() AND (v_etab.peut_publier_missions IS NOT TRUE) THEN
        IF v_etab.statut_verification = 'EN_ATTENTE' THEN
            RETURN '{"error":"Votre etablissement est en attente de verification. Vous pourrez publier des missions une fois verifie."}'::JSONB;
        ELSIF v_etab.statut_verification = 'REJETE' THEN
            RETURN '{"error":"Votre etablissement a ete rejete. Contactez support@jolene.app."}'::JSONB;
        ELSIF v_etab.statut_verification = 'SUSPENDU' THEN
            RETURN '{"error":"Votre compte est suspendu."}'::JSONB;
        ELSE
            RETURN '{"error":"Votre etablissement doit etre verifie avant de publier des missions."}'::JSONB;
        END IF;
    END IF;

    -- Cadenas 2 : blocage auto CP-C-3 (retards paiement >45j)
    IF NOT est_admin() AND v_etab.bloque_auto_le IS NOT NULL THEN
        RETURN jsonb_build_object(
            'error', 'PUBLICATION_SUSPENDUE',
            'message', 'Publication de nouvelles missions suspendue en raison de retards de paiement. Regularisez vos obligations pour reactiver votre compte.',
            'bloque_auto_le', v_etab.bloque_auto_le,
            'raisons', v_etab.bloque_auto_raisons
        );
    END IF;

    IF NOT est_admin() AND (v_etab.contrat_valide IS NOT TRUE) THEN
        RETURN '{"error":"Votre contrat de service Jolene doit etre valide avant de publier des missions."}'::JSONB;
    END IF;

    IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
        RETURN '{"error":"Champs obligatoires manquants."}'::JSONB;
    END IF;
    IF p_fin_le <= p_debut_le THEN
        RETURN '{"error":"La fin doit etre apres le debut."}'::JSONB;
    END IF;
    IF p_debut_le < NOW() AND NOT est_admin() THEN
        RETURN '{"error":"La mission ne peut pas commencer dans le passe."}'::JSONB;
    END IF;

    IF EXISTS (
        SELECT 1 FROM factures
        WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
          AND date_echeance < CURRENT_DATE
    ) AND NOT est_admin() THEN
        RETURN '{"error":"Vous avez des factures impayees. Veuillez regulariser."}'::JSONB;
    END IF;

    v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
    IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
        v_mode := 'PREMIER_ARRIVE';
    END IF;

    PERFORM set_config('jolene.creer_mission_context', 'true', true);

    INSERT INTO missions (
        etablissement_id, intitule, description,
        profession_requise, service, debut_le, fin_le,
        taux_horaire_base, est_urgente, niveau_urgence, mode_attribution
    ) VALUES (
        v_etab_id, p_intitule, p_description,
        p_profession_requise, p_service, p_debut_le, p_fin_le,
        p_taux_horaire_base, p_est_urgente,
        CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
        v_mode
    ) RETURNING id INTO v_mission_id;

    RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

-- D. Update fn_creer_mission (signature 11 params avec p_serie_id) : idem check 2 cadenas
CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL::text,
  p_profession_requise type_profession DEFAULT NULL::type_profession,
  p_service text DEFAULT NULL::text,
  p_debut_le timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_fin_le timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_taux_horaire_base numeric DEFAULT NULL::numeric,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_serie_id uuid DEFAULT NULL::uuid,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID;
    v_etab RECORD;
    v_mission_id UUID;
    v_mode TEXT;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Acces refuse"}'::JSONB;
    END IF;

    SELECT peut_publier_missions, statut_verification, contrat_valide,
           bloque_auto_le, bloque_auto_raisons
    INTO v_etab FROM etablissements WHERE id = v_etab_id;

    IF NOT est_admin() AND (v_etab.peut_publier_missions IS NOT TRUE) THEN
        IF v_etab.statut_verification = 'EN_ATTENTE' THEN
            RETURN '{"error":"Votre etablissement est en attente de verification. Vous pourrez publier des missions une fois verifie."}'::JSONB;
        ELSIF v_etab.statut_verification = 'REJETE' THEN
            RETURN '{"error":"Votre etablissement a ete rejete. Contactez support@jolene.app."}'::JSONB;
        ELSIF v_etab.statut_verification = 'SUSPENDU' THEN
            RETURN '{"error":"Votre compte est suspendu."}'::JSONB;
        ELSE
            RETURN '{"error":"Votre etablissement doit etre verifie avant de publier des missions."}'::JSONB;
        END IF;
    END IF;

    IF NOT est_admin() AND v_etab.bloque_auto_le IS NOT NULL THEN
        RETURN jsonb_build_object(
            'error', 'PUBLICATION_SUSPENDUE',
            'message', 'Publication de nouvelles missions suspendue en raison de retards de paiement. Regularisez vos obligations pour reactiver votre compte.',
            'bloque_auto_le', v_etab.bloque_auto_le,
            'raisons', v_etab.bloque_auto_raisons
        );
    END IF;

    IF NOT est_admin() AND (v_etab.contrat_valide IS NOT TRUE) THEN
        RETURN '{"error":"Votre contrat de service Jolene doit etre valide avant de publier des missions."}'::JSONB;
    END IF;

    IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
        RETURN '{"error":"Champs obligatoires manquants."}'::JSONB;
    END IF;
    IF p_fin_le <= p_debut_le THEN
        RETURN '{"error":"La fin doit etre apres le debut."}'::JSONB;
    END IF;
    IF p_debut_le < NOW() AND NOT est_admin() THEN
        RETURN '{"error":"La mission ne peut pas commencer dans le passe."}'::JSONB;
    END IF;

    IF EXISTS (
        SELECT 1 FROM factures
        WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
          AND date_echeance < CURRENT_DATE
    ) AND NOT est_admin() THEN
        RETURN '{"error":"Vous avez des factures impayees. Veuillez regulariser."}'::JSONB;
    END IF;

    v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
    IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
        v_mode := 'PREMIER_ARRIVE';
    END IF;

    PERFORM set_config('jolene.creer_mission_context', 'true', true);

    INSERT INTO missions (
        etablissement_id, intitule, description,
        profession_requise, service, debut_le, fin_le,
        taux_horaire_base, est_urgente, niveau_urgence,
        serie_id, mode_attribution
    ) VALUES (
        v_etab_id, p_intitule, p_description,
        p_profession_requise, p_service, p_debut_le, p_fin_le,
        p_taux_horaire_base, p_est_urgente,
        CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
        p_serie_id, v_mode
    ) RETURNING id INTO v_mission_id;

    RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;
