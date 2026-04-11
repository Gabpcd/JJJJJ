-- ─── Fix drift RPC critique post-migration Lovable→Vercel ───
--
-- 8 bugs bloquants identifiés par audit exhaustif :
-- 1-5. 5 admin RPCs insèrent dans journaux_audit avec colonne `ressource_id`
--      qui n'existe pas (la vraie colonne est `id_ressource`). Toutes les
--      actions admin échouent silencieusement.
-- 6. fn_admin_moderer_evaluation accepte 'masquer'/'supprimer' (lowercase)
--    mais frontend envoie 'PUBLIER'/'SUPPRIMER'. Modération évaluations
--    impossible.
-- 7. fn_admin_incoherences_identite ne retourne pas les champs
--    nom_profil/prenom_profil/nom_rpps/nom_cni attendus par le frontend.
-- 8. fn_repondre_contestation_paiement compare etablissement_id à
--    auth.uid() (Lovable legacy) au lieu de mon_etablissement_id().
-- 9. fn_soignants_urgence retourne `id` mais frontend attend `soignant_id`.
-- 10. fn_recommander_soignants retourne `missions_etab` mais frontend
--     attend `missions_etablissement` + `tous_documents_valides`.

-- ═══════════════════════════════════════════════════════════════════
-- 1. fn_admin_moderer_document
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document(p_document_id uuid, p_action text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_doc RECORD;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    IF p_action NOT IN ('VALIDER', 'REJETER') THEN
        RETURN jsonb_build_object('error', 'Action invalide. Valeurs acceptées : VALIDER, REJETER');
    END IF;

    SELECT id, soignant_id, type_document, statut_verification
    INTO v_doc FROM documents_soignants WHERE id = p_document_id;

    IF v_doc IS NULL THEN
        RETURN jsonb_build_object('error', 'Document introuvable');
    END IF;

    IF p_action = 'VALIDER' THEN
        UPDATE documents_soignants SET
            statut_verification = 'VALIDE',
            verifie_le = NOW(),
            verifie_par = auth.uid()
        WHERE id = p_document_id;
    ELSE
        UPDATE documents_soignants SET
            statut_verification = 'REJETE',
            verifie_le = NOW(),
            verifie_par = auth.uid(),
            motif_rejet = COALESCE(p_motif, 'Rejeté par l''administrateur')
        WHERE id = p_document_id;
    END IF;

    -- Audit (fix: id_ressource au lieu de ressource_id)
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'MODERATION_DOCUMENT', 'document', p_document_id,
        jsonb_build_object('action', p_action, 'type_document', v_doc.type_document, 'soignant_id', v_doc.soignant_id));

    -- Recalculer tous_documents_valides du soignant
    UPDATE soignants SET tous_documents_valides = NOT EXISTS(
        SELECT 1 FROM documents_soignants
        WHERE soignant_id = v_doc.soignant_id
        AND statut_verification != 'VALIDE'
        AND type_document IN ('PIECE_IDENTITE', 'DIPLOME', 'ASSURANCE_RCP')
    ) WHERE id = v_doc.soignant_id;

    RETURN jsonb_build_object('success', true, 'action', p_action);
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 2. fn_admin_moderer_evaluation (fix id_ressource + ajout PUBLIER)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_moderer_evaluation(p_evaluation_id uuid, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_action_norm TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    v_action_norm := UPPER(COALESCE(p_action, ''));

    IF v_action_norm IN ('PUBLIER', 'AFFICHER', 'DEMASQUER') THEN
        UPDATE evaluations SET visible = TRUE WHERE id = p_evaluation_id;
    ELSIF v_action_norm IN ('MASQUER', 'CACHER') THEN
        UPDATE evaluations SET visible = FALSE WHERE id = p_evaluation_id;
    ELSIF v_action_norm IN ('SUPPRIMER', 'SUPPRESSION') THEN
        DELETE FROM evaluations WHERE id = p_evaluation_id;
    ELSE
        RETURN jsonb_build_object('error', 'Action invalide : PUBLIER, MASQUER ou SUPPRIMER');
    END IF;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'MODERATION_EVALUATION', 'evaluation', p_evaluation_id,
        jsonb_build_object('action', v_action_norm));

    RETURN jsonb_build_object('success', TRUE, 'action', v_action_norm);
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 3. fn_admin_valider_etablissement
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_valider_etablissement(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    SELECT id, nom, statut_verification, siret_verifie, contrat_valide
    INTO v_etab FROM etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;

    IF v_etab IS NULL THEN
        RETURN jsonb_build_object('error', 'Établissement introuvable');
    END IF;

    IF v_etab.statut_verification = 'VERIFIE' THEN
        RETURN jsonb_build_object('error', 'Cet établissement est déjà vérifié');
    END IF;

    UPDATE etablissements SET
        statut_verification = 'VERIFIE',
        peut_publier_missions = TRUE,
        verifie_le = NOW(),
        verifie_par = auth.uid()
    WHERE id = p_etablissement_id;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'VALIDATION_ETABLISSEMENT', 'etablissement', p_etablissement_id,
        jsonb_build_object('nom', v_etab.nom));

    RETURN jsonb_build_object('success', true, 'nom', v_etab.nom);
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 4. fn_admin_rejeter_etablissement
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_rejeter_etablissement(p_etablissement_id uuid, p_motif text DEFAULT 'Non conforme aux critères de la plateforme'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_nom TEXT;
    v_motif_safe TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    v_motif_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_motif), ''), 'Non conforme'), '<[^>]*>', '', 'g'), 500);

    UPDATE etablissements SET
        statut_verification = 'REJETE',
        peut_publier_missions = FALSE,
        motif_rejet = v_motif_safe
    WHERE id = p_etablissement_id;

    SELECT COALESCE(nom, 'Inconnu') INTO v_nom FROM etablissements WHERE id = p_etablissement_id;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'REJET_ETABLISSEMENT', 'etablissement', p_etablissement_id,
        jsonb_build_object('nom', v_nom, 'motif', v_motif_safe));

    RETURN jsonb_build_object('success', TRUE, 'message', 'Établissement rejeté : ' || v_nom);
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 5. fn_admin_suspendre_utilisateur
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_suspendre_utilisateur(p_table text, p_id uuid, p_suspendre boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_nom TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    IF p_table NOT IN ('soignants', 'etablissements') THEN
        RETURN jsonb_build_object('error', 'Table invalide');
    END IF;

    IF p_table = 'soignants' THEN
        IF p_suspendre THEN
            UPDATE soignants SET supprime_le = NOW() WHERE id = p_id AND supprime_le IS NULL;
        ELSE
            UPDATE soignants SET supprime_le = NULL WHERE id = p_id AND supprime_le IS NOT NULL;
        END IF;
        SELECT COALESCE(prenom || ' ' || nom, 'Inconnu') INTO v_nom FROM soignants WHERE id = p_id;
    ELSIF p_table = 'etablissements' THEN
        IF p_suspendre THEN
            UPDATE etablissements SET supprime_le = NOW(), peut_publier_missions = FALSE WHERE id = p_id AND supprime_le IS NULL;
        ELSE
            UPDATE etablissements SET supprime_le = NULL WHERE id = p_id AND supprime_le IS NOT NULL;
        END IF;
        SELECT COALESCE(nom, 'Inconnu') INTO v_nom FROM etablissements WHERE id = p_id;
    END IF;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
        auth.uid(), 'ADMIN',
        CASE WHEN p_suspendre THEN 'SUSPENSION_COMPTE' ELSE 'REACTIVATION_COMPTE' END,
        p_table, p_id,
        jsonb_build_object('nom', v_nom, 'table', p_table, 'action', CASE WHEN p_suspendre THEN 'suspendre' ELSE 'réactiver' END)
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', CASE WHEN p_suspendre THEN 'Compte suspendu : ' ELSE 'Compte réactivé : ' END || v_nom
    );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 6. fn_admin_incoherences_identite — ajouter champs attendus frontend
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_admin_incoherences_identite();
CREATE FUNCTION public.fn_admin_incoherences_identite()
 RETURNS TABLE(
   soignant_id uuid,
   prenom text,
   nom text,
   prenom_profil text,
   nom_profil text,
   nom_rpps text,
   nom_cni text,
   coherence_identite text,
   coherence_details jsonb,
   rpps_verifie boolean,
   identite_verifiee boolean
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN; END IF;
    RETURN QUERY
    SELECT
      s.id,
      s.prenom::TEXT,
      s.nom::TEXT,
      s.prenom::TEXT AS prenom_profil,
      s.nom::TEXT AS nom_profil,
      (s.coherence_details->>'nom_rpps')::TEXT,
      (s.coherence_details->>'nom_cni')::TEXT,
      s.coherence_identite,
      s.coherence_details,
      s.rpps_verifie,
      s.identite_verifiee
    FROM soignants s
    WHERE s.coherence_identite = 'INCOHERENT'
    AND s.supprime_le IS NULL
    ORDER BY s.modifie_le DESC;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_admin_incoherences_identite() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- 7. fn_repondre_contestation_paiement — fix guard legacy
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_repondre_contestation_paiement(p_paiement_id uuid, p_action text, p_nouvelle_reference text DEFAULT NULL::text, p_reponse text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_paiement RECORD;
    v_litige RECORD;
BEGIN
    SELECT * INTO v_paiement FROM paiements_soignant WHERE id = p_paiement_id;
    IF v_paiement IS NULL THEN RETURN '{"error":"Paiement introuvable"}'::JSONB; END IF;
    -- Fix: utiliser mon_etablissement_id() + est_admin() au lieu du pattern Lovable legacy
    IF v_paiement.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
      RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;
    IF v_paiement.statut != 'CONTESTE' THEN RETURN '{"error":"Ce paiement n''est pas contesté"}'::JSONB; END IF;

    SELECT * INTO v_litige FROM litiges WHERE paiement_soignant_id = p_paiement_id ORDER BY cree_le DESC LIMIT 1;

    IF p_action = 'MODIFIER_REF' THEN
        IF p_nouvelle_reference IS NULL OR length(trim(p_nouvelle_reference)) < 5 THEN
            RETURN '{"error":"Référence invalide (min 5 caractères)"}'::JSONB;
        END IF;
        UPDATE paiements_soignant SET
            reference_virement = trim(p_nouvelle_reference),
            statut = 'DECLARE',
            conteste = FALSE,
            motif_contestation = NULL,
            confirme_par_soignant = FALSE,
            confirme_par_soignant_le = NULL,
            modifie_le = NOW()
        WHERE id = p_paiement_id;
        IF v_litige IS NOT NULL THEN
            UPDATE litiges SET statut = 'FERME', resolution = 'Référence corrigée par l''établissement : ' || trim(p_nouvelle_reference), resolu_le = NOW() WHERE id = v_litige.id;
        END IF;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_paiement.soignant_id, 'PAIEMENT_MODIFIE', 'Référence de paiement modifiée', 'L''établissement a corrigé la référence de paiement. Veuillez vérifier et confirmer.', '/soignant/gains', 'SOIGNANT');
        RETURN '{"success":true, "action":"reference_modifiee"}'::JSONB;

    ELSIF p_action = 'ACCEPTER' THEN
        UPDATE paiements_soignant SET statut = 'ANNULE', modifie_le = NOW() WHERE id = p_paiement_id;
        IF v_litige IS NOT NULL THEN
            UPDATE litiges SET statut = 'RESOLUE_ETABLISSEMENT', resolution = 'Paiement annulé par l''établissement', resolu_le = NOW() WHERE id = v_litige.id;
        END IF;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_paiement.soignant_id, 'PAIEMENT_ANNULE', 'Paiement annulé', 'L''établissement a annulé le paiement contesté. Un nouveau paiement devra être effectué.', '/soignant/gains', 'SOIGNANT');
        RETURN '{"success":true, "action":"paiement_annule"}'::JSONB;

    ELSIF p_action = 'CONTESTER' THEN
        IF v_litige IS NOT NULL THEN
            UPDATE litiges SET statut = 'EN_DISCUSSION', reponse = COALESCE(p_reponse, 'L''établissement maintient le paiement') WHERE id = v_litige.id;
        END IF;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        SELECT id, 'SYSTEM', 'Litige paiement — escalade',
            'Un litige de paiement nécessite une intervention admin.',
            '/admin/moderation', 'ADMIN'
        FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME' LIMIT 1;
        RETURN '{"success":true, "action":"escalade_admin"}'::JSONB;
    END IF;

    RETURN '{"error":"Action inconnue"}'::JSONB;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 8. fn_soignants_urgence — ajouter `soignant_id` alias
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_soignants_urgence(uuid);
CREATE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
 RETURNS TABLE(
   soignant_id uuid,
   id uuid,
   prenom text,
   nom text,
   score_fiabilite integer,
   distance_km numeric,
   urgence_rayon_km integer,
   telephone text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
BEGIN
    SELECT m.id, m.profession_requise, e.id AS etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission FROM missions m JOIN etablissements e ON e.id = m.etablissement_id WHERE m.id = p_mission_id;
    IF NOT FOUND THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        s.id AS soignant_id,  -- alias pour compatibilité frontend
        s.id,
        s.prenom::TEXT, s.nom::TEXT,
        COALESCE(s.score_fiabilite, 0)::INTEGER,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
                SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER,
        s.telephone::TEXT
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE
      AND s.supprime_le IS NULL
      AND s.tous_documents_valides = TRUE
      AND s.profession = v_mission.profession_requise
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le)
      AND (
          s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
              COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
              SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
          )))) <= COALESCE(s.urgence_rayon_km, 15)
      )
    ORDER BY s.score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_soignants_urgence(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- 9. fn_recommander_soignants — alias missions_etablissement + tous_documents_valides
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_recommander_soignants(uuid, integer);
CREATE FUNCTION public.fn_recommander_soignants(p_mission_id uuid, p_limit integer DEFAULT 20)
 RETURNS TABLE(
   id uuid,
   prenom text,
   nom text,
   profession type_profession,
   score_fiabilite integer,
   distance_km numeric,
   missions_etab integer,
   missions_etablissement integer,
   score_matching numeric,
   est_favori boolean,
   type_exercice text,
   note_moyenne numeric,
   nb_evaluations integer,
   tous_documents_valides boolean
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_etab RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE missions.id = p_mission_id;
    SELECT * INTO v_etab FROM etablissements WHERE etablissements.id = v_mission.etablissement_id;

    RETURN QUERY
    SELECT
        s.id, s.prenom, s.nom, s.profession,
        s.score_fiabilite::INTEGER,
        ROUND((CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
            )))
        ELSE 999 END)::NUMERIC, 1),
        (SELECT COUNT(*)::INTEGER FROM missions m2
         WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = v_mission.etablissement_id AND m2.statut = 'TERMINEE'),
        (SELECT COUNT(*)::INTEGER FROM missions m2b
         WHERE m2b.soignant_assigne_id = s.id AND m2b.etablissement_id = v_mission.etablissement_id AND m2b.statut = 'TERMINEE') AS missions_etablissement,
        ROUND((
            s.score_fiabilite * 0.3
            + COALESCE(s.note_moyenne, 3) * 20 * 0.2
            + LEAST(100, (SELECT COUNT(*) FROM missions m3
                WHERE m3.soignant_assigne_id = s.id AND m3.etablissement_id = v_mission.etablissement_id AND m3.statut = 'TERMINEE') * 10) * 0.2
            + CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
                GREATEST(0, 100 - (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                    COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                    COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                    SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
                )))))
              ELSE 0 END * 0.2
            + CASE WHEN EXISTS (SELECT 1 FROM favoris f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id) THEN 20 ELSE 0 END
        )::NUMERIC, 1),
        EXISTS (SELECT 1 FROM favoris f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id),
        COALESCE(s.type_exercice, 'SALARIE'),
        s.note_moyenne,
        s.nb_evaluations,
        s.tous_documents_valides  -- toujours TRUE via le WHERE mais exposé au frontend
    FROM soignants s
    WHERE s.profession = v_mission.profession_requise
      AND s.supprime_le IS NULL
      AND s.tous_documents_valides = TRUE
      AND (
          v_mission.type_contrat_recherche IS NULL
          OR v_mission.type_contrat_recherche = 'TOUS'
          OR s.type_exercice = 'MIXTE'
          OR (v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice, 'SALARIE') IN ('SALARIE', 'MIXTE'))
          OR (v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE'))
      )
      AND (s.adresse_lat IS NULL OR v_etab.adresse_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
              COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
              SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
          )))) <= COALESCE(s.rayon_deplacement_km, 50)
      )
      AND s.id NOT IN (
          SELECT m4.soignant_assigne_id FROM missions m4
          WHERE m4.soignant_assigne_id IS NOT NULL AND m4.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m4.debut_le < v_mission.fin_le AND m4.fin_le > v_mission.debut_le
      )
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
    ORDER BY score_matching DESC
    LIMIT p_limit;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_recommander_soignants(uuid, integer) TO authenticated;
