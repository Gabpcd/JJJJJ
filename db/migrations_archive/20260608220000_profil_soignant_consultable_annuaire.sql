-- Fix : « Profil soignant indisponible » depuis l'annuaire établissement.
--
-- L'annuaire (fn_rechercher_soignants_etab) laisse l'établissement parcourir et
-- cliquer sur N'IMPORTE quel soignant, mais fn_soignant_pour_etablissement
-- renvoyait « Accès refusé » sans relation préalable (mission/candidature) →
-- cul-de-sac « Profil soignant indisponible » pour tout soignant jamais croisé.
--
-- La fonction anonymise DÉJÀ correctement (nom complet + téléphone uniquement si
-- relation contractuelle / mission du jour ; sinon prénom + initiale). On retire
-- donc le hard-block et on autorise tout établissement authentifié à consulter le
-- profil ANONYMISÉ — exactement les infos que l'annuaire affiche déjà. La
-- protection nom/téléphone reste intacte (gate v_a_relation_contractuelle).

CREATE OR REPLACE FUNCTION public.fn_soignant_pour_etablissement(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_a_mission_aujourdhui BOOLEAN;
    v_a_relation_contractuelle BOOLEAN;
BEGIN
    -- Garde : réservé aux établissements authentifiés (ou admin). Plus de blocage
    -- sur la relation préalable : l'annuaire expose déjà ces soignants.
    IF NOT est_admin() AND v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM missions
        WHERE soignant_assigne_id = p_soignant_id
          AND etablissement_id = v_etab_id
          AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE','ABSENCE','LITIGE')
    ) INTO v_a_relation_contractuelle;

    SELECT EXISTS (
        SELECT 1 FROM missions
        WHERE soignant_assigne_id = p_soignant_id
          AND etablissement_id = v_etab_id
          AND statut IN ('ASSIGNEE','EN_COURS')
          AND debut_le::DATE <= CURRENT_DATE + 1
    ) INTO v_a_mission_aujourdhui;

    RETURN (
        SELECT jsonb_build_object(
            'id', id,
            'prenom', prenom,
            'nom', CASE
                WHEN est_admin() OR v_a_relation_contractuelle THEN nom
                ELSE LEFT(COALESCE(nom, ''), 1) || '.'
            END,
            'nom_anonymise', NOT (est_admin() OR v_a_relation_contractuelle),
            'profession', profession::TEXT,
            'specialite_medicale', specialite_medicale,
            'telephone', CASE WHEN v_a_mission_aujourdhui OR est_admin() THEN telephone ELSE NULL END,
            'numero_rpps', numero_rpps,
            'score_fiabilite', score_fiabilite,
            'note_moyenne', note_moyenne,
            'nb_evaluations', nb_evaluations,
            'total_missions_terminees', total_missions_terminees,
            'rpps_verifie', rpps_verifie,
            'tous_documents_valides', tous_documents_valides,
            'avatar_url', avatar_url,
            'type_exercice', COALESCE(type_exercice, 'SALARIE'),
            'bio', bio,
            'annees_experience', annees_experience,
            'specialites', specialites,
            'disponible_urgence', disponible_urgence
        )
        FROM soignants WHERE id = p_soignant_id AND supprime_le IS NULL
    );
END;
$function$;
