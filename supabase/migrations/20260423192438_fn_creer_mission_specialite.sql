-- Phase C Session 2.5 : ajout specialite_medicale_requise + accepte_non_specialises
-- à fn_creer_mission pour atomicité INSERT (supprime le besoin d'UPDATE séparé).

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
    p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text,
    p_specialite_medicale_requise text DEFAULT NULL,
    p_accepte_non_specialises boolean DEFAULT true
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
        taux_horaire_base, est_urgente, niveau_urgence, mode_attribution,
        specialite_medicale_requise, accepte_non_specialises
    ) VALUES (
        v_etab_id, p_intitule, p_description,
        p_profession_requise, p_service, p_debut_le, p_fin_le,
        p_taux_horaire_base, p_est_urgente,
        CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
        v_mode,
        p_specialite_medicale_requise, p_accepte_non_specialises
    ) RETURNING id INTO v_mission_id;

    RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

NOTIFY pgrst, 'reload schema';
