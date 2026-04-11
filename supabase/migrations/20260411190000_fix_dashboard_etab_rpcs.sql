-- Fix 2 RPCs bloquant le dashboard établissement
--
-- Bug #1 : fn_mon_etablissement_complet référence des colonnes qui n'existent
-- pas dans paliers_commission :
--   - pc.taux_base            → la vraie colonne est pc.taux_commission
--   - pc.seuil_min_missions   → la vraie colonne est pc.missions_min
-- Conséquence : la fonction crash avec "column does not exist" côté SQL,
-- PostgREST renvoie 400, le Dashboard Établissement affiche "Certaines
-- données n'ont pas pu être chargées".
--
-- Bug #2 : fn_analytics_etablissement fait `statut LIKE 'ANNULEE%'` sur
-- la colonne `statut` de type ENUM (statut_mission). PostgreSQL refuse
-- `LIKE` sur un enum sans cast explicite :
--   ERROR: 42883: operator does not exist: statut_mission ~~ unknown
-- Conséquence : la page Gestion → Analytics crashe à l'ouverture.
-- Fix : caster en ::text avant le LIKE.

-- ─── Bug #1 : fn_mon_etablissement_complet ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mon_etablissement_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Établissement introuvable');
    END IF;

    SELECT row_to_json(e)::JSONB INTO v_result FROM (
        SELECT
            et.id, et.nom, et.siret, et.finess, et.type::TEXT, et.groupe_sante_id,
            et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
            et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
            et.stripe_customer_id, et.stripe_account_id,
            et.taux_commission_negocie, et.mode_facturation, et.mode_paiement_commission,
            et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
            et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
            et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
            et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
            et.taux_majoration_nuit_pourcent, et.taux_majoration_dimanche_pourcent,
            et.taux_majoration_ferie_pourcent,
            et.est_secteur_public, et.peut_publier_missions, et.statut_verification,
            et.note_moyenne, et.nb_evaluations, et.description, et.horaires_ouverture,
            et.rist_plafond_actif, et.rist_taux_base_horaire,
            et.cree_le, et.modifie_le,
            -- JOIN paliers_commission (colonnes réelles : taux_commission, missions_min)
            CASE WHEN pc.id IS NOT NULL THEN jsonb_build_object(
                'id', pc.id,
                'nom', pc.nom,
                'taux_commission', pc.taux_commission,
                'missions_min', pc.missions_min
            ) ELSE NULL END AS paliers_commission,
            -- JOIN groupes_sante (le frontend attend etab.groupes_sante.nom)
            CASE WHEN gs.id IS NOT NULL THEN jsonb_build_object(
                'id', gs.id,
                'nom', gs.nom
            ) ELSE NULL END AS groupes_sante
        FROM etablissements et
        LEFT JOIN paliers_commission pc ON pc.id = et.palier_commission_id
        LEFT JOIN groupes_sante gs ON gs.id = et.groupe_sante_id
        WHERE et.id = v_etab_id
    ) e;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Établissement introuvable'));
END;
$function$;

-- ─── Bug #2 : fn_analytics_etablissement — cast enum avant LIKE ───────────
CREATE OR REPLACE FUNCTION public.fn_analytics_etablissement(
    p_etablissement_id uuid,
    p_mois integer DEFAULT 6
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debut DATE;
  v_result JSONB;
  v_taux_remplissage NUMERIC;
  v_cout_heure_moyen NUMERIC;
  v_turnover NUMERIC;
  v_missions_par_mois JSONB;
  v_top_professions JSONB;
  v_soignants_recurrents JSONB;
BEGIN
  v_debut := (CURRENT_DATE - (p_mois || ' months')::INTERVAL)::DATE;

  -- Taux de remplissage: missions pourvues / total missions
  SELECT
    CASE WHEN COUNT(*) > 0
      THEN ROUND(COUNT(*) FILTER(WHERE statut IN ('ASSIGNEE','EN_COURS','TERMINEE')) * 100.0 / COUNT(*), 1)
      ELSE 0
    END INTO v_taux_remplissage
  FROM missions
  WHERE etablissement_id = p_etablissement_id
    AND cree_le >= v_debut;

  -- Coût/heure moyen (missions terminées)
  SELECT COALESCE(
    ROUND(AVG(
      CASE WHEN duree_heures > 0 THEN total_brut / duree_heures ELSE NULL END
    ), 2), 0
  ) INTO v_cout_heure_moyen
  FROM missions
  WHERE etablissement_id = p_etablissement_id
    AND statut = 'TERMINEE'
    AND cree_le >= v_debut;

  -- Turnover: soignants uniques / missions terminées
  SELECT
    CASE WHEN COUNT(*) FILTER(WHERE statut = 'TERMINEE') > 0
      THEN ROUND(
        COUNT(DISTINCT soignant_assigne_id) FILTER(WHERE statut = 'TERMINEE') * 100.0 /
        COUNT(*) FILTER(WHERE statut = 'TERMINEE'), 1
      )
      ELSE 0
    END INTO v_turnover
  FROM missions
  WHERE etablissement_id = p_etablissement_id
    AND cree_le >= v_debut;

  -- Missions par mois (courbe) — cast enum → text avant LIKE
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  INTO v_missions_par_mois
  FROM (
    SELECT
      TO_CHAR(debut_le, 'YYYY-MM') AS mois,
      COUNT(*) AS total,
      COUNT(*) FILTER(WHERE statut = 'TERMINEE') AS terminees,
      COUNT(*) FILTER(WHERE statut::text LIKE 'ANNULEE%') AS annulees,
      ROUND(COALESCE(SUM(total_brut) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS cout_total
    FROM missions
    WHERE etablissement_id = p_etablissement_id
      AND debut_le >= v_debut
    GROUP BY TO_CHAR(debut_le, 'YYYY-MM')
    ORDER BY mois
  ) t;

  -- Top professions demandées
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  INTO v_top_professions
  FROM (
    SELECT profession_requise AS profession, COUNT(*) AS nb_missions,
      ROUND(AVG(CASE WHEN duree_heures > 0 AND statut = 'TERMINEE' THEN total_brut / duree_heures END), 2) AS cout_moyen_heure
    FROM missions
    WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut
    GROUP BY profession_requise
    ORDER BY COUNT(*) DESC
    LIMIT 10
  ) t;

  -- Soignants les plus récurrents
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  INTO v_soignants_recurrents
  FROM (
    SELECT s.id, s.prenom, s.nom, s.profession,
      COUNT(m.id) AS nb_missions,
      COALESCE(ROUND(AVG(ev.note), 1), 0) AS note_moyenne
    FROM missions m
    JOIN soignants s ON s.id = m.soignant_assigne_id
    LEFT JOIN evaluations ev ON ev.evalue_id = s.id AND ev.evaluateur_id = p_etablissement_id
    WHERE m.etablissement_id = p_etablissement_id
      AND m.statut = 'TERMINEE'
      AND m.cree_le >= v_debut
    GROUP BY s.id, s.prenom, s.nom, s.profession
    ORDER BY COUNT(m.id) DESC
    LIMIT 10
  ) t;

  RETURN jsonb_build_object(
    'taux_remplissage', v_taux_remplissage,
    'cout_heure_moyen', v_cout_heure_moyen,
    'turnover_pourcent', v_turnover,
    'missions_par_mois', v_missions_par_mois,
    'top_professions', v_top_professions,
    'soignants_recurrents', v_soignants_recurrents,
    'periode_mois', p_mois
  );
END;
$function$;
