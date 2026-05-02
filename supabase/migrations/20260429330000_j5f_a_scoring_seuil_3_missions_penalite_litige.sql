-- J5.F.A — Scoring affiné :
--   * Ajout colonne soignants.total_litiges_perdus (compteur litiges RESOLU_ETABLISSEMENT)
--   * Pénalité -10 par litige perdu intégrée dans la formule de dec_mettre_a_jour_fiabilite
--   * fn_resoudre_litige : incrémente le compteur (au lieu de modifier score directement)
--     + audit dédié SCORE_FIABILITE_PENALITE_LITIGE
--   * Audit constraint étendu : SCORE_FIABILITE_PENALITE_LITIGE
--   * fn_pool_urgence_etablissement + fn_recommander_soignants : score=NULL si <3 missions terminées (signature TABLE inchangée)

-- 1) Compteur litiges perdus
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS total_litiges_perdus INTEGER NOT NULL DEFAULT 0;

-- 2) Audit constraint étendu
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY[
  'INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS',
  'CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION',
  'POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION',
  'DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION',
  'RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE','PREFERENCE_NOTIFICATION_MODIFIEE',
  'NOTIFICATION_SKIPPED','SERIE_EMAIL_ENVOYE','SERIE_EMAIL_SKIPPED',
  'FILTRE_CREE','FILTRE_MODIFIE','FILTRE_SUPPRIME',
  'ALERTE_ACTIVEE','ALERTE_DESACTIVEE','ALERTE_ENVOYEE',
  'POOL_URGENCE_NOTIFICATIONS_ENVOYEES','POOL_URGENCE_ACCEPTATION_RAPIDE',
  'POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB','POOL_URGENCE_SMS_TOGGLE',
  'FAVORI_AJOUTE','FAVORI_RETIRE','SCORE_FIABILITE_PENALITE_LITIGE'
]));

-- 3) dec_mettre_a_jour_fiabilite : -10 par litige perdu dans la formule
CREATE OR REPLACE FUNCTION public.dec_mettre_a_jour_fiabilite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

    IF NEW.statut = 'TERMINEE' AND OLD.statut != 'TERMINEE' THEN
        UPDATE soignants SET
            total_missions_terminees = total_missions_terminees + 1,
            heures_cumulees = heures_cumulees +
                EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0,
            eligible_conversion_3200h = (
                heures_cumulees + EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0
            ) >= 3200,
            derniere_activite_le = NOW(), modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;

        UPDATE suivi_conversion_3200h SET
            heures_actuelles = (SELECT heures_cumulees FROM soignants WHERE id = NEW.soignant_assigne_id),
            jalon_800h_atteint  = heures_actuelles >= 800,
            jalon_1600h_atteint = heures_actuelles >= 1600,
            jalon_2400h_atteint = heures_actuelles >= 2400,
            jalon_3200h_atteint = heures_actuelles >= 3200,
            modifie_le = NOW()
        WHERE soignant_id = NEW.soignant_assigne_id;
    END IF;

    IF NEW.statut = 'ABSENCE' AND OLD.statut != 'ABSENCE' THEN
        UPDATE soignants SET total_absences = total_absences + 1, modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;

    IF NEW.statut = 'ANNULEE_PAR_SOIGNANT' AND OLD.statut != 'ANNULEE_PAR_SOIGNANT' THEN
        UPDATE soignants SET total_missions_annulees = total_missions_annulees + 1, modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;

    UPDATE soignants SET
        score_fiabilite = GREATEST(0, LEAST(100,
            50.0
            + (total_missions_terminees * 2.0)
            - (total_missions_annulees * 8.0)
            - (total_absences * 25.0)
            - (total_retards_pointage * 3.0)
            - (COALESCE(total_litiges_perdus, 0) * 10.0)
            + CASE WHEN total_missions_terminees > 20 THEN 10.0 ELSE 0 END
            + CASE WHEN total_absences = 0 AND total_missions_terminees > 5 THEN 5.0 ELSE 0 END
            + CASE WHEN prevoyance_inscrit THEN 3.0 ELSE 0 END
        ))
    WHERE id = NEW.soignant_assigne_id;

    RETURN NEW;
END;
$function$;

-- 4) Helper RPC : recalcule pour un soignant donné (utilisé par fn_resoudre_litige)
CREATE OR REPLACE FUNCTION public.fn_recalculer_score_fiabilite_soignant(p_soignant_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_new_score NUMERIC;
BEGIN
  UPDATE soignants SET
    score_fiabilite = GREATEST(0, LEAST(100,
      50.0
      + (COALESCE(total_missions_terminees, 0) * 2.0)
      - (COALESCE(total_missions_annulees, 0) * 8.0)
      - (COALESCE(total_absences, 0) * 25.0)
      - (COALESCE(total_retards_pointage, 0) * 3.0)
      - (COALESCE(total_litiges_perdus, 0) * 10.0)
      + CASE WHEN COALESCE(total_missions_terminees, 0) > 20 THEN 10.0 ELSE 0 END
      + CASE WHEN COALESCE(total_absences, 0) = 0 AND COALESCE(total_missions_terminees, 0) > 5 THEN 5.0 ELSE 0 END
      + CASE WHEN COALESCE(prevoyance_inscrit, false) THEN 3.0 ELSE 0 END
    )),
    modifie_le = NOW()
  WHERE id = p_soignant_id
  RETURNING score_fiabilite INTO v_new_score;

  RETURN v_new_score;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_recalculer_score_fiabilite_soignant(UUID) TO service_role;

-- 5) fn_resoudre_litige : passe par compteur + audit dédié
CREATE OR REPLACE FUNCTION public.fn_resoudre_litige(p_litige_id uuid, p_statut text, p_resolution text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_litige RECORD;
    v_mission RECORD;
    v_score_avant NUMERIC;
    v_score_apres NUMERIC;
BEGIN
    IF NOT est_admin() THEN
        RETURN '{"error":"Seul l''administrateur peut résoudre un litige"}'::JSONB;
    END IF;
    IF p_statut NOT IN ('RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME') THEN
        RETURN '{"error":"Statut invalide"}'::JSONB;
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN '{"error":"Litige introuvable"}'::JSONB; END IF;

    SELECT * INTO v_mission FROM missions WHERE id = v_litige.mission_id;

    UPDATE litiges SET
        statut = p_statut,
        resolution = p_resolution,
        resolu_par = auth.uid(),
        resolu_le = NOW()
    WHERE id = p_litige_id;

    IF p_statut = 'RESOLU_SOIGNANT' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'TERMINEE', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = TRUE, valide_le = NOW(), motif_litige = NULL
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;
        UPDATE soignants SET score_fiabilite = LEAST(100, COALESCE(score_fiabilite, 50) + 3), modifie_le = NOW()
        WHERE id = v_litige.soignant_id;

    ELSIF p_statut = 'RESOLU_ETABLISSEMENT' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = FALSE, motif_litige = p_resolution
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;

        SELECT score_fiabilite INTO v_score_avant FROM soignants WHERE id = v_litige.soignant_id;

        UPDATE soignants SET total_litiges_perdus = COALESCE(total_litiges_perdus, 0) + 1, modifie_le = NOW()
        WHERE id = v_litige.soignant_id;

        v_score_apres := public.fn_recalculer_score_fiabilite_soignant(v_litige.soignant_id);

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_litige.soignant_id,
          p_type_acteur := 'SYSTEME',
          p_action := 'SCORE_FIABILITE_PENALITE_LITIGE',
          p_type_ressource := 'litige',
          p_id_ressource := p_litige_id,
          p_details := jsonb_build_object(
            'mission_id', v_litige.mission_id,
            'score_avant', v_score_avant,
            'score_apres', v_score_apres,
            'delta', COALESCE(v_score_apres, 0) - COALESCE(v_score_avant, 0)
          )
        );

    ELSIF p_statut = 'RESOLU_ADMIN' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'TERMINEE', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = TRUE, valide_le = NOW()
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;

    ELSIF p_statut = 'FERME' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'TERMINEE', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = TRUE, valide_le = NOW()
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;
    END IF;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire) VALUES
    (v_litige.soignant_id, 'SYSTEM',
        CASE p_statut
            WHEN 'RESOLU_SOIGNANT' THEN 'Litige résolu en votre faveur ✅'
            WHEN 'RESOLU_ETABLISSEMENT' THEN 'Litige résolu en faveur de l''établissement'
            WHEN 'RESOLU_ADMIN' THEN 'Litige résolu par l''administrateur'
            WHEN 'FERME' THEN 'Litige clôturé ✅'
        END,
        COALESCE(p_resolution, 'Le litige a été résolu.'),
        '/soignant/missions', 'SOIGNANT'),
    (v_litige.etablissement_id, 'SYSTEM',
        CASE p_statut
            WHEN 'RESOLU_SOIGNANT' THEN 'Litige résolu en faveur du soignant'
            WHEN 'RESOLU_ETABLISSEMENT' THEN 'Litige résolu en votre faveur ✅'
            WHEN 'RESOLU_ADMIN' THEN 'Litige résolu par l''administrateur'
            WHEN 'FERME' THEN 'Litige clôturé ✅'
        END,
        COALESCE(p_resolution, 'Le litige a été résolu.'),
        '/etablissement/missions', 'ETABLISSEMENT');

    PERFORM fn_ecrire_audit_safe(
        auth.uid(), 'ADMIN_PLATEFORME', 'MISSION_LITIGE',
        'litige', p_litige_id, NULL,
        jsonb_build_object('resolution', p_statut, 'mission_id', v_litige.mission_id,
            'soignant_id', v_litige.soignant_id, 'details', p_resolution),
        NULL, 'rpc'
    );

    RETURN jsonb_build_object('success', true, 'statut', p_statut,
        'mission_statut', CASE
            WHEN p_statut = 'RESOLU_ETABLISSEMENT' THEN 'ANNULEE_PAR_ETABLISSEMENT'
            ELSE 'TERMINEE' END);
END;
$function$;

-- 6) fn_pool_urgence_etablissement : score=NULL si <3 missions terminées (TABLE inchangé)
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
BEGIN
    SELECT e.id, e.adresse_lat, e.adresse_lng INTO v_etab
    FROM etablissements e WHERE e.id = p_etablissement_id;
    IF NOT FOUND THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        s.id AS soignant_id,
        s.prenom::TEXT, s.nom::TEXT, s.profession::TEXT,
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END AS score_fiabilite,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER AS pool_urgence_rayon_km,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_etab.adresse_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_etab.adresse_lng)) +
                SIN(RADIANS(v_etab.adresse_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END AS distance_km,
        (SELECT COUNT(*)::BIGINT FROM missions m WHERE m.soignant_assigne_id = s.id AND COALESCE(m.est_urgente, FALSE) = TRUE AND m.statut = 'TERMINEE') AS missions_urgence_terminees,
        EXISTS(SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le) AS en_mission_maintenant,
        (SELECT MAX(m2.fin_le) FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = p_etablissement_id AND m2.statut = 'TERMINEE') AS derniere_mission_chez_nous,
        s.bio::TEXT, s.avatar_url::TEXT,
        EXISTS(SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = p_etablissement_id) AS est_favori
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE
      AND s.supprime_le IS NULL
      AND s.tous_documents_valides = TRUE
      AND NOT fn_est_exclu(s.id, p_etablissement_id)
      AND (
          s.profession IN (
              SELECT DISTINCT m.profession_requise FROM missions m
              WHERE m.etablissement_id = p_etablissement_id
              AND m.statut IN ('OUVERTE','ASSIGNEE','EN_COURS','ABSENCE','LITIGE')
          )
          OR NOT EXISTS (
              SELECT 1 FROM missions m WHERE m.etablissement_id = p_etablissement_id
              AND m.statut IN ('OUVERTE','ASSIGNEE','EN_COURS','ABSENCE','LITIGE')
          )
      )
    ORDER BY score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;

-- 7) fn_recommander_soignants : score=NULL si <3 missions terminées + note=NULL si <3 évaluations
CREATE OR REPLACE FUNCTION public.fn_recommander_soignants(p_mission_id uuid, p_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, prenom text, nom text, profession type_profession, score_fiabilite integer, distance_km numeric, missions_etab integer, missions_etablissement integer, score_matching numeric, est_favori boolean, type_exercice text, note_moyenne numeric, nb_evaluations integer, tous_documents_valides boolean)
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
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END,
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
            COALESCE(s.score_fiabilite, 0) * 0.3
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
            + CASE WHEN EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id) THEN 20 ELSE 0 END
        )::NUMERIC, 1),
        EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id),
        COALESCE(s.type_exercice, 'SALARIE'),
        CASE WHEN COALESCE(s.nb_evaluations, 0) >= 3 THEN s.note_moyenne ELSE NULL END,
        COALESCE(s.nb_evaluations, 0),
        s.tous_documents_valides
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
    ORDER BY est_favori DESC, score_matching DESC
    LIMIT p_limit;
END;
$function$;

NOTIFY pgrst, 'reload schema';
