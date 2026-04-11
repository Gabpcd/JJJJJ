-- fn_detail_facture : enrichissement de la réponse avec breakdown financier complet
-- + pointages par mission.
--
-- Champs ajoutés par mission :
--   - duree_heures, service
--   - montant_majoration_nuit / dimanche / ferie
--   - taux_ifm, montant_ifm, taux_icp, montant_icp
--   - presences[] (pointage_arrivee/depart_le, méthode, heures_reelles, retard, validation...)
--
-- Objectif : permettre à la page Détail Facture d'afficher le calcul détaillé
-- (majoration nuit/dimanche/férié, IFM, ICP, pointages par jour, etc.) au lieu
-- d'une simple ligne par mission. Architecture côté serveur pour éviter
-- plusieurs round-trips depuis le frontend.

CREATE OR REPLACE FUNCTION public.fn_detail_facture(p_facture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_facture RECORD;
    v_missions JSONB;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN jsonb_build_object('error', 'Facture introuvable'); END IF;
    IF v_facture.etablissement_id != v_etab_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    -- PRIORITÉ 1 : missions liées par facture_id (lien direct)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', m.id,
            'intitule', m.intitule,
            'service', m.service,
            'debut_le', m.debut_le,
            'fin_le', m.fin_le,
            'duree_heures', m.duree_heures,
            'taux_horaire_base', m.taux_horaire_base,
            'total_brut', m.total_brut,
            'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
            'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
            'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
            'taux_ifm', COALESCE(m.taux_ifm, 0),
            'montant_ifm', COALESCE(m.montant_ifm, 0),
            'taux_icp', COALESCE(m.taux_icp, 0),
            'montant_icp', COALESCE(m.montant_icp, 0),
            'taux_commission', m.taux_commission,
            'montant_commission_ht', m.montant_commission_ht,
            'montant_commission_tva', m.montant_commission_tva,
            'montant_commission_ttc', m.montant_commission_ttc,
            'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
            'profession', m.profession_requise::TEXT,
            'presences', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', p.id,
                    'pointage_arrivee_le', p.pointage_arrivee_le,
                    'pointage_depart_le', p.pointage_depart_le,
                    'methode_pointage_arrivee', p.methode_pointage_arrivee,
                    'methode_pointage_depart', p.methode_pointage_depart,
                    'heures_reelles', p.heures_reelles,
                    'duree_brute_min', p.duree_brute_min,
                    'duree_nette_min', p.duree_nette_min,
                    'duree_pause_min', p.duree_pause_min,
                    'retard_min', p.retard_min,
                    'depart_anticipe_min', p.depart_anticipe_min,
                    'perimetre_gps_valide', p.perimetre_gps_valide,
                    'alerte_teleportation', p.alerte_teleportation,
                    'valide_par_etablissement', p.valide_par_etablissement
                ) ORDER BY p.pointage_arrivee_le)
                FROM presences p
                WHERE p.mission_id = m.id
            ), '[]'::JSONB)
        ) ORDER BY m.debut_le
    ), '[]'::JSONB)
    INTO v_missions
    FROM missions m
    LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
    WHERE m.facture_id = p_facture_id;

    -- PRIORITÉ 2 : si aucune mission liée par FK, chercher par période
    IF v_missions = '[]'::JSONB AND v_facture.periode_debut IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'intitule', m.intitule,
                'service', m.service,
                'debut_le', m.debut_le,
                'fin_le', m.fin_le,
                'duree_heures', m.duree_heures,
                'taux_horaire_base', m.taux_horaire_base,
                'total_brut', m.total_brut,
                'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
                'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
                'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
                'taux_ifm', COALESCE(m.taux_ifm, 0),
                'montant_ifm', COALESCE(m.montant_ifm, 0),
                'taux_icp', COALESCE(m.taux_icp, 0),
                'montant_icp', COALESCE(m.montant_icp, 0),
                'taux_commission', m.taux_commission,
                'montant_commission_ht', m.montant_commission_ht,
                'montant_commission_tva', m.montant_commission_tva,
                'montant_commission_ttc', m.montant_commission_ttc,
                'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
                'profession', m.profession_requise::TEXT,
                'presences', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', p.id,
                        'pointage_arrivee_le', p.pointage_arrivee_le,
                        'pointage_depart_le', p.pointage_depart_le,
                        'methode_pointage_arrivee', p.methode_pointage_arrivee,
                        'methode_pointage_depart', p.methode_pointage_depart,
                        'heures_reelles', p.heures_reelles,
                        'duree_brute_min', p.duree_brute_min,
                        'duree_nette_min', p.duree_nette_min,
                        'duree_pause_min', p.duree_pause_min,
                        'retard_min', p.retard_min,
                        'depart_anticipe_min', p.depart_anticipe_min,
                        'perimetre_gps_valide', p.perimetre_gps_valide,
                        'alerte_teleportation', p.alerte_teleportation,
                        'valide_par_etablissement', p.valide_par_etablissement
                    ) ORDER BY p.pointage_arrivee_le)
                    FROM presences p
                    WHERE p.mission_id = m.id
                ), '[]'::JSONB)
            ) ORDER BY m.debut_le
        ), '[]'::JSONB)
        INTO v_missions
        FROM missions m
        LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
        WHERE m.etablissement_id = v_facture.etablissement_id
        AND m.statut = 'TERMINEE' AND m.commission_facturee = TRUE
        AND m.debut_le >= v_facture.periode_debut::TIMESTAMP
        AND m.debut_le < (v_facture.periode_fin + 1)::TIMESTAMP;
    END IF;

    -- PRIORITÉ 3 : mission unique si facture a mission_id
    IF v_missions = '[]'::JSONB AND v_facture.mission_id IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'intitule', m.intitule,
                'service', m.service,
                'debut_le', m.debut_le,
                'fin_le', m.fin_le,
                'duree_heures', m.duree_heures,
                'taux_horaire_base', m.taux_horaire_base,
                'total_brut', m.total_brut,
                'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
                'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
                'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
                'taux_ifm', COALESCE(m.taux_ifm, 0),
                'montant_ifm', COALESCE(m.montant_ifm, 0),
                'taux_icp', COALESCE(m.taux_icp, 0),
                'montant_icp', COALESCE(m.montant_icp, 0),
                'taux_commission', m.taux_commission,
                'montant_commission_ht', m.montant_commission_ht,
                'montant_commission_tva', m.montant_commission_tva,
                'montant_commission_ttc', m.montant_commission_ttc,
                'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
                'profession', m.profession_requise::TEXT,
                'presences', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', p.id,
                        'pointage_arrivee_le', p.pointage_arrivee_le,
                        'pointage_depart_le', p.pointage_depart_le,
                        'methode_pointage_arrivee', p.methode_pointage_arrivee,
                        'methode_pointage_depart', p.methode_pointage_depart,
                        'heures_reelles', p.heures_reelles,
                        'duree_brute_min', p.duree_brute_min,
                        'duree_nette_min', p.duree_nette_min,
                        'duree_pause_min', p.duree_pause_min,
                        'retard_min', p.retard_min,
                        'depart_anticipe_min', p.depart_anticipe_min,
                        'perimetre_gps_valide', p.perimetre_gps_valide,
                        'alerte_teleportation', p.alerte_teleportation,
                        'valide_par_etablissement', p.valide_par_etablissement
                    ) ORDER BY p.pointage_arrivee_le)
                    FROM presences p
                    WHERE p.mission_id = m.id
                ), '[]'::JSONB)
            )
        ), '[]'::JSONB)
        INTO v_missions
        FROM missions m
        LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
        WHERE m.id = v_facture.mission_id;
    END IF;

    RETURN jsonb_build_object(
        'facture', jsonb_build_object(
            'id', v_facture.id, 'numero_facture', v_facture.numero_facture,
            'statut', v_facture.statut, 'montant_ht', v_facture.montant_ht,
            'taux_tva', v_facture.taux_tva, 'montant_tva', v_facture.montant_tva,
            'montant_ttc', v_facture.montant_ttc, 'nombre_missions', v_facture.nombre_missions,
            'mode_paiement', v_facture.mode_paiement,
            'periode_debut', v_facture.periode_debut, 'periode_fin', v_facture.periode_fin,
            'date_emission', v_facture.date_emission, 'date_echeance', v_facture.date_echeance,
            'date_paiement', v_facture.date_paiement
        ),
        'missions', v_missions
    );
END;
$function$;
