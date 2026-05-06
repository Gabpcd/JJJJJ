-- Fix: fn_dashboard_soignant_complet ne filtre plus par profession quand NULL
-- Avant: AND m.profession_requise = (SELECT profession FROM soignants WHERE id = v_uid)
-- Après: AND (v_profession IS NULL OR m.profession_requise = v_profession)
-- Permet aux soignants sans RPPS vérifié (profession NULL) de voir toutes les missions.

CREATE OR REPLACE FUNCTION public.fn_dashboard_soignant_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := NOW();
  v_lundi DATE;
  v_dimanche DATE;
  v_debut_mois DATE;
  v_fin_mois DATE;
  v_six_mois_ago DATE;
  v_profession type_profession;
  v_result JSONB;
BEGIN
  v_lundi := date_trunc('week', v_now)::DATE;
  v_dimanche := v_lundi + 7;
  v_debut_mois := date_trunc('month', v_now)::DATE;
  v_fin_mois := (date_trunc('month', v_now) + INTERVAL '1 month' - INTERVAL '1 second')::DATE;
  v_six_mois_ago := date_trunc('month', v_now - INTERVAL '5 months')::DATE;

  SELECT profession INTO v_profession FROM soignants WHERE id = v_uid;

  SELECT jsonb_build_object(
    'profil', (
      SELECT row_to_json(s)::jsonb FROM (
        SELECT prenom, nom, telephone, date_naissance, profession, type_contrat,
          numero_rpps, numero_adeli, rpps_verifie, adresse_lat, adresse_lng,
          tous_documents_valides, identite_verifiee, score_fiabilite,
          total_missions_terminees, heures_cumulees, eligible_conversion_3200h,
          type_exercice, mandat_facturation_signe
        FROM soignants WHERE id = v_uid
      ) s
    ),
    'missions_ouvertes', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb) FROM (
        SELECT m.id, m.intitule, m.service, m.debut_le, m.fin_le, m.taux_horaire_base,
          m.est_urgente, m.etablissement_id,
          e.nom AS etab_nom
        FROM missions m
        LEFT JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.statut = 'OUVERTE'
          AND (v_profession IS NULL OR m.profession_requise = v_profession)
        ORDER BY m.debut_le LIMIT 3
      ) m
    ),
    'mes_missions', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb) FROM (
        SELECT m.id, m.intitule, m.debut_le, m.fin_le, m.statut, m.etablissement_id,
          e.nom AS etab_nom
        FROM missions m
        LEFT JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.soignant_assigne_id = v_uid AND m.statut IN ('ASSIGNEE', 'EN_COURS')
        ORDER BY m.debut_le LIMIT 3
      ) m
    ),
    'documents', (
      SELECT COALESCE(jsonb_agg(row_to_json(d)::jsonb), '[]'::jsonb) FROM (
        SELECT id, type_document, valide_jusqua, statut_verification
        FROM documents_soignants WHERE soignant_id = v_uid AND supprime_le IS NULL
      ) d
    ),
    'heures_semaine', (
      SELECT COALESCE(SUM(duree_heures), 0) FROM missions
      WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        AND debut_le >= v_lundi AND debut_le < v_dimanche
    ),
    'gains_mois', (
      SELECT jsonb_build_object(
        'net_total', COALESCE(SUM(COALESCE(net_a_payer, net_estime, total_brut)), 0),
        'brut_total', COALESCE(SUM(total_brut), 0),
        'nb_missions', COUNT(*)
      ) FROM missions
      WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
        AND debut_le >= v_debut_mois AND debut_le <= v_fin_mois
    ),
    'gains_6mois', (
      SELECT COALESCE(jsonb_agg(row_to_json(g)::jsonb ORDER BY g.mois), '[]'::jsonb) FROM (
        SELECT TO_CHAR(debut_le, 'YYYY-MM') AS mois,
          ROUND(COALESCE(SUM(net_a_payer), 0)::NUMERIC, 2) AS net
        FROM missions
        WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE' AND debut_le >= v_six_mois_ago
        GROUP BY TO_CHAR(debut_le, 'YYYY-MM')
      ) g
    ),
    'missions_semaine_cal', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb) FROM (
        SELECT debut_le, statut FROM missions
        WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE', 'EN_COURS')
          AND debut_le >= v_lundi AND debut_le < v_dimanche
      ) m
    ),
    'propositions', (
      SELECT COALESCE(jsonb_agg(row_to_json(p)::jsonb), '[]'::jsonb) FROM (
        SELECT c.id, c.mission_id, c.cree_le,
          m.intitule, m.debut_le, m.fin_le, m.taux_horaire_base, m.etablissement_id, m.est_urgente,
          e.nom AS etab_nom
        FROM candidatures c
        JOIN missions m ON m.id = c.mission_id
        LEFT JOIN etablissements e ON e.id = m.etablissement_id
        WHERE c.soignant_id = v_uid AND c.statut = 'PROPOSEE'
        ORDER BY c.cree_le DESC LIMIT 5
      ) p
    ),
    'heures_totales_terminees', (
      SELECT COALESCE(SUM(duree_heures), 0) FROM missions
      WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
    ),
    'missions_oubliees_count', (
      SELECT COUNT(*) FROM missions m
      WHERE m.soignant_assigne_id = v_uid AND m.statut = 'EN_COURS'
        AND m.fin_le < (v_now - INTERVAL '30 minutes')
        AND NOT EXISTS (SELECT 1 FROM presences p WHERE p.mission_id = m.id AND p.pointage_arrivee_le IS NOT NULL)
    ),
    'notifs_non_lues', (
      SELECT COUNT(*) FROM notifications WHERE destinataire_id = v_uid AND lue = FALSE
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
