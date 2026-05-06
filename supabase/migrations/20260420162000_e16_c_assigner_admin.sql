-- ============================================================
-- E16 — Micro-passe 1C : fn_assigner_mission_admin param choix
-- ============================================================
-- Ajoute p_choix_contrat TEXT DEFAULT NULL + check strict pour
-- MIXTE×TOUS. Supprime fallback CASE arbitraire qui figeait
-- SALARIE/CDDU. Persiste les 4 champs missions cohérents.
-- ============================================================

-- Drop de l'ancienne signature (2 params) pour éviter collision
DROP FUNCTION IF EXISTS public.fn_assigner_mission_admin(uuid, uuid);

CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_etab RECORD;
    v_type_contrat TEXT;
    v_numero TEXT;
    v_html TEXT;
    v_heures_semaine NUMERIC;
    v_debut_semaine TIMESTAMPTZ;
    v_fin_semaine TIMESTAMPTZ;
    v_choix_applique TEXT;
    v_type_paiement TEXT;
    v_mode_paiement TEXT;
BEGIN
    IF NOT (est_admin() OR est_admin_etablissement()) THEN
        RETURN '{"error":"Non autorise"}'::JSONB;
    END IF;

    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN '{"error":"Cette mission n est plus disponible"}'::JSONB; END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN '{"error":"Soignant introuvable"}'::JSONB; END IF;

    SELECT * INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Ce soignant est ' || v_soignant.profession::TEXT || ', la mission requiert un(e) ' || v_mission.profession_requise::TEXT || '.');
    END IF;

    IF fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
        RETURN jsonb_build_object('error', 'Ce soignant est dans la liste d exclusions de cet etablissement.');
    END IF;

    -- Type contrat compat mission×soignant
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') = 'LIBERAL' THEN
        RETURN jsonb_build_object('error', 'Cette mission est reservee aux salaries.');
    END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est reservee aux liberaux.');
    END IF;

    -- Validation format p_choix_contrat si fourni
    IF p_choix_contrat IS NOT NULL AND p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
        RETURN jsonb_build_object('error', 'p_choix_contrat invalide (attendu SALARIE ou LIBERAL).');
    END IF;

    -- E16 : determination du choix applique
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL THEN
            RETURN jsonb_build_object(
                'error', 'E16_CHOIX_CONTRAT_REQUIS',
                'message', 'Mission MIXTE avec soignant MIXTE : specifiez p_choix_contrat SALARIE ou LIBERAL.',
                'mission_id', p_mission_id,
                'soignant_id', p_soignant_id
            );
        END IF;
        v_choix_applique := p_choix_contrat;
    ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN
        v_choix_applique := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
        v_choix_applique := 'LIBERAL';
    ELSE
        -- mission TOUS avec soignant SALARIE pur ou LIBERAL pur
        v_choix_applique := COALESCE(v_soignant.type_exercice, 'SALARIE');
    END IF;

    -- Plafond 48h applicable seulement si mode salarié appliqué
    IF v_choix_applique = 'SALARIE' THEN
        v_debut_semaine := DATE_TRUNC('week', v_mission.debut_le);
        v_fin_semaine := v_debut_semaine + INTERVAL '7 days';
        SELECT COALESCE(SUM(duree_heures), 0) INTO v_heures_semaine
        FROM missions WHERE soignant_assigne_id = p_soignant_id
          AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
          AND debut_le >= v_debut_semaine AND debut_le < v_fin_semaine;
        IF v_heures_semaine + COALESCE(v_mission.duree_heures, 0) > 48 THEN
            RETURN jsonb_build_object('error', 'Depasse 48h/semaine (' || ROUND(v_heures_semaine, 1) || 'h planifiees).');
        END IF;
    END IF;

    -- E16 : derivation coherente des 4 champs missions
    IF v_choix_applique = 'LIBERAL' THEN
        v_type_contrat := 'REMPLACEMENT_LIBERAL';
        v_type_paiement := 'NOTE_HONORAIRES';
        v_mode_paiement := 'STRIPE_CONNECT';
    ELSE
        v_type_contrat := 'CDDU';
        v_type_paiement := 'BULLETIN_PAIE';
        v_mode_paiement := 'DIRECT';
    END IF;

    UPDATE missions SET
        soignant_assigne_id = p_soignant_id,
        statut = 'ASSIGNEE',
        type_contrat_applique = v_choix_applique::type_contrat_applique_enum,
        choix_contrat_soignant = v_choix_applique,
        type_paiement_soignant = v_type_paiement,
        mode_paiement_soignant = v_mode_paiement,
        modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';

    IF NOT FOUND THEN RETURN '{"error":"Mission deja prise"}'::JSONB; END IF;

    v_numero := fn_generer_numero_contrat(v_type_contrat);

    SELECT contenu_html INTO v_html FROM templates_contrat
    WHERE type_contrat = v_type_contrat AND est_actif = TRUE LIMIT 1;

    IF v_html IS NOT NULL THEN
        v_html := REPLACE(v_html, '{{etablissement_nom}}', fn_html_escape(v_etab.nom));
        v_html := REPLACE(v_html, '{{etablissement_siret}}', fn_html_escape(v_etab.siret));
        v_html := REPLACE(v_html, '{{etablissement_finess}}', fn_html_escape(COALESCE(v_etab.finess, 'N/A')));
        v_html := REPLACE(v_html, '{{etablissement_adresse}}', fn_html_escape(COALESCE(v_etab.adresse_rue || ', ' || v_etab.adresse_code_postal || ' ' || v_etab.adresse_ville, '')));
        v_html := REPLACE(v_html, '{{soignant_prenom}}', fn_html_escape(v_soignant.prenom));
        v_html := REPLACE(v_html, '{{soignant_nom}}', fn_html_escape(v_soignant.nom));
        v_html := REPLACE(v_html, '{{soignant_rpps}}', fn_html_escape(COALESCE(v_soignant.numero_rpps, '')));
        v_html := REPLACE(v_html, '{{soignant_siret}}', fn_html_escape(COALESCE(v_soignant.siret_liberal, '')));
        v_html := REPLACE(v_html, '{{profession}}', fn_html_escape(COALESCE(v_soignant.profession::TEXT, '')));
        v_html := REPLACE(v_html, '{{service}}', fn_html_escape(COALESCE(v_mission.service, '')));
        v_html := REPLACE(v_html, '{{debut_date}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{debut_heure}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
        v_html := REPLACE(v_html, '{{fin_date}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{fin_heure}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
        v_html := REPLACE(v_html, '{{duree_heures}}', COALESCE(v_mission.duree_heures::TEXT, ''));
        v_html := REPLACE(v_html, '{{taux_horaire}}', COALESCE(v_mission.taux_horaire_base::TEXT, ''));
        v_html := REPLACE(v_html, '{{numero_contrat}}', fn_html_escape(v_numero));
        v_html := REPLACE(v_html, '{{date_signature}}', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{lieu}}', fn_html_escape(COALESCE(v_etab.adresse_ville, '')));
    END IF;

    INSERT INTO contrats_mission (
        mission_id, etablissement_id, soignant_id,
        type_contrat, numero_contrat, contenu_html, statut
    ) VALUES (
        p_mission_id, v_mission.etablissement_id, p_soignant_id,
        v_type_contrat, v_numero, v_html, 'EN_ATTENTE_SIGNATURES'
    );

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (p_soignant_id, 'MISSION_ACCEPTEE', 'Mission assignee',
        'Vous avez ete assigne(e) a la mission "' || fn_html_escape(v_mission.intitule) || '". Signez votre contrat.',
        '/soignant/missions/' || p_mission_id, 'SOIGNANT');

    RETURN jsonb_build_object(
        'success', true,
        'contrat_numero', v_numero,
        'choix_applique', v_choix_applique
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_assigner_mission_admin(uuid, uuid, text) IS
  'E16 p_choix_contrat obligatoire pour MIXTE TOUS RAISE E16_CHOIX_CONTRAT_REQUIS sinon persiste 4 champs missions coherents';
