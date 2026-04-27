-- Phase Audit Fix : matching enrichi (P1-A + P1-B)
--
-- Avant ce patch, fn_postuler_mission faisait un match strict
-- profession_requise = soignant.profession et ignorait à la fois la
-- hiérarchie professionnelle (IBODE/IADE ⊃ IDE) et le flag
-- accepte_non_specialises côté missions, ainsi que la spécialité
-- médicale requise. Conséquences :
--   - IBODE ne peut pas candidater à mission IDE (P1-A)
--   - IDE ne peut pas candidater à mission IBODE même si l'étab
--     accepte les non-spécialisés (P1-A)
--   - Médecin généraliste accepté sur mission cardio (P1-B)
--
-- Fix : helper fn_soignant_compatible_mission(...) IMMUTABLE qui
-- encapsule la règle métier, utilisé par fn_postuler_mission.
-- Reproductibilité validée par tests SQL avec comptes audit Phase 1.

CREATE OR REPLACE FUNCTION public.fn_soignant_compatible_mission(
  p_soignant_profession type_profession,
  p_soignant_specialite text,
  p_mission_profession type_profession,
  p_mission_specialite text,
  p_accepte_non_specialises boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT CASE
    -- Cas 1 : match exact profession
    WHEN p_soignant_profession = p_mission_profession THEN
      CASE
        -- Pour MEDECIN avec spécialité requise, filtrer selon le flag
        WHEN p_mission_profession = 'MEDECIN'
             AND p_mission_specialite IS NOT NULL
             AND p_mission_specialite <> '' THEN
          COALESCE(p_accepte_non_specialises, true)
          OR COALESCE(p_soignant_specialite, '') = p_mission_specialite
        ELSE TRUE
      END
    -- Cas 2 : hiérarchie IDE — IBODE et IADE sont diplômés IDE de base,
    -- ils peuvent toujours candidater à une mission IDE (pas besoin du
    -- flag accepte_non_specialises côté IDE)
    WHEN p_mission_profession = 'IDE'
         AND p_soignant_profession IN ('IBODE', 'IADE') THEN TRUE
    -- Cas 3 : IDE peut candidater à mission IBODE/IADE uniquement si
    -- l'étab accepte les non-spécialisés
    WHEN p_soignant_profession = 'IDE'
         AND p_mission_profession IN ('IBODE', 'IADE') THEN
      COALESCE(p_accepte_non_specialises, true)
    ELSE FALSE
  END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_soignant_compatible_mission(type_profession, text, type_profession, text, boolean) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_rcp_valide BOOLEAN;
    v_choix_final TEXT;
    v_compatible BOOLEAN;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'CANDIDATURE' THEN RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    -- Compatibilité profession + spécialité + hiérarchie
    v_compatible := fn_soignant_compatible_mission(
      v_soignant.profession,
      v_soignant.specialite_medicale,
      v_mission.profession_requise,
      v_mission.specialite_medicale_requise,
      v_mission.accepte_non_specialises
    );

    IF NOT v_compatible THEN
      IF v_mission.profession_requise = 'MEDECIN'
         AND v_mission.specialite_medicale_requise IS NOT NULL
         AND v_soignant.profession = 'MEDECIN' THEN
        RETURN jsonb_build_object('error',
          'Cette mission requiert la spécialité ' || v_mission.specialite_medicale_requise || '.');
      ELSIF v_mission.profession_requise IN ('IBODE', 'IADE')
            AND v_soignant.profession = 'IDE'
            AND COALESCE(v_mission.accepte_non_specialises, true) = false THEN
        RETURN jsonb_build_object('error',
          'Cette mission ' || v_mission.profession_requise::text || ' n''accepte pas les IDE non spécialisés.');
      ELSE
        RETURN jsonb_build_object('error',
          'Votre profession ne correspond pas à la mission requise (' || v_mission.profession_requise::text || ').');
      END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN
        RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.'); END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.'); END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL OR p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object(
                'error', 'Veuillez choisir votre mode de contrat.',
                'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDDU)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')
                ));
        END IF;
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM documents_soignants
        WHERE soignant_id = auth.uid()
        AND type_document = 'RCP_ASSURANCE'
        AND statut_verification = 'VERIFIE'
        AND supprime_le IS NULL
        AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
    ) INTO v_rcp_valide;
    IF NOT v_rcp_valide THEN
        RETURN jsonb_build_object('error', 'Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée. Veuillez la téléverser dans vos documents.');
    END IF;

    IF EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 86400 < 7 THEN
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Documents obligatoires non validés (mission < 7 jours).'); END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission'); END IF;

    IF v_mission.type_contrat_recherche = 'SALARIE' THEN
        v_choix_final := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
        v_choix_final := 'LIBERAL';
    ELSIF v_soignant.type_exercice = 'MIXTE' THEN
        v_choix_final := p_choix_contrat;
    ELSE
        v_choix_final := COALESCE(v_soignant.type_exercice, 'SALARIE');
    END IF;

    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, auth.uid(), fn_html_escape(p_message), 'EN_ATTENTE', v_choix_final);

    RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final);
END;
$function$;
