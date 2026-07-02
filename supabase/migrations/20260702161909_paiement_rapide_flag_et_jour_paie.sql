-- 7c (Lot 7 v2 §2.1) — infrastructure badge « ⚡ Paiement rapide » + jour de paie.
--
-- ⚠️ Feature flag SERVEUR éteint par défaut (`feature_paiement_rapide_actif` = 0) :
-- règle transversale n°2 du Lot 7 — « aucune promesse de paiement que Jolene ne
-- contrôle pas techniquement ». Tant que l'escrow (7b-D : débit à la confirmation
-- + release après validation) n'est pas livré, la promesse « payée sous 24-72 h »
-- n'est pas tenable → le flag reste à 0 et aucun badge ne s'affiche. Le jour où
-- l'escrow est en prod : passer le paramètre à 1, tout s'allume sans redéploiement.
--
-- Gating ⚡ (calculé serveur, jamais côté client) :
--   flag actif ET mission LIBERAL ET étab en prélèvement SEPA actif
--   (mode_paiement_commission = 'SEPA_DEBIT' + stripe_sepa_payment_method_id).

-- 1) Paramètre système (levier admin, pas de redéploiement pour activer).
INSERT INTO public.parametres_systeme (cle, valeur, label, description, categorie, val_min, val_max, cablee)
VALUES (
  'feature_paiement_rapide_actif', 0,
  'Badge ⚡ Paiement rapide',
  'Active le badge « ⚡ Paiement rapide » sur les missions libérales des établissements en prélèvement SEPA. NE PAS activer avant la mise en prod de l''escrow (débit à la confirmation + release 24-72 h après validation des présences) — la promesse doit être tenable techniquement.',
  'FINANCE', 0, 1, true
)
ON CONFLICT (cle) DO NOTHING;

-- 2) Jour de paie habituel de l'établissement (§2.2 prévisibilité salarié :
--    « Salaire versé vers le 28 par l'établissement » sur la carte mission).
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS jour_paie_habituel smallint
    CONSTRAINT etablissements_jour_paie_check CHECK (jour_paie_habituel BETWEEN 1 AND 31);

-- 3) Payload swipe : + paiement_rapide (gating complet serveur).
CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_soignant_id uuid := auth.uid(); v_sg soignants%ROWTYPE; v_missions jsonb;
        v_flag_pr boolean := (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1);
BEGIN
  IF v_soignant_id IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT * INTO v_sg FROM soignants WHERE id = v_soignant_id;
  SELECT COALESCE(jsonb_agg(payload ORDER BY (payload->>'score')::int DESC), '[]'::jsonb) INTO v_missions
  FROM (
    SELECT jsonb_build_object(
      'mission_id', m.id, 'intitule', m.intitule, 'profession_requise', m.profession_requise,
      'etablissement_id', m.etablissement_id, 'etablissement_nom', e.nom, 'etablissement_ville', e.adresse_ville,
      'etablissement_code_postal', e.adresse_code_postal, 'etablissement_logo_url', e.logo_url,
      'etablissement_score', e.score_qualite, 'taux_horaire_base', m.taux_horaire_base, 'duree_heures', m.duree_heures,
      'debut_le', m.debut_le, 'fin_le', m.fin_le, 'est_urgente', m.est_urgente, 'service', m.service,
      'type_contrat_applique', m.type_contrat_applique, 'type_contrat_recherche', m.type_contrat_recherche,
      'nb_creneaux', m.nb_creneaux, 'total_brut', m.total_brut, 'net_a_payer', m.net_a_payer,
      'net_estime', m.net_estime, 'montant_ifm', COALESCE(m.montant_ifm, 0), 'montant_icp', COALESCE(m.montant_icp, 0),
      'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0), 'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
      'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0), 'score', COALESCE(ms.score_global, 0),
      'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),
      -- 7c : ⚡ Paiement rapide — gating complet serveur (flag + LIBERAL + SEPA actif).
      'paiement_rapide', (
        v_flag_pr
        AND m.type_contrat_recherche = 'LIBERAL'
        AND e.mode_paiement_commission = 'SEPA_DEBIT'
        AND e.stripe_sepa_payment_method_id IS NOT NULL
      ),
      'distance_km', CASE
        WHEN v_sg.adresse_lat IS NOT NULL AND v_sg.adresse_lng IS NOT NULL
         AND e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
        THEN ROUND((fn_haversine_distance_m(v_sg.adresse_lat, v_sg.adresse_lng, e.adresse_lat, e.adresse_lng) / 1000.0)::numeric, 1)
        ELSE NULL END
    ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
     WHERE m.statut = 'OUVERTE'
       AND (m.intitule NOT LIKE '[%' OR v_sg.email LIKE 'playwright-%')
       AND fn_soignant_compatible_mission(
             v_sg.profession, v_sg.specialite_medicale,
             m.profession_requise, m.specialite_medicale_requise, m.accepte_non_specialises)
       AND (m.type_contrat_recherche = 'TOUS' OR v_sg.type_exercice IS NULL OR v_sg.type_exercice = 'MIXTE'
            OR (m.type_contrat_recherche = 'SALARIE' AND v_sg.type_exercice IN ('SALARIE', 'MIXTE'))
            OR (m.type_contrat_recherche = 'LIBERAL' AND v_sg.type_exercice IN ('LIBERAL', 'MIXTE')))
       AND (v_sg.taux_horaire_minimum IS NULL OR m.taux_horaire_base IS NULL
            OR m.taux_horaire_base >= v_sg.taux_horaire_minimum)
       AND m.id NOT IN (SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id)
     ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
     LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_missions_swipe(integer) TO authenticated, service_role;

-- 4) fn_etablissements_safe : + paiement_rapide + jour_paie_habituel (le type de
--    retour change → DROP + CREATE, re-GRANT identique authenticated/service_role).
DROP FUNCTION IF EXISTS public.fn_etablissements_safe(uuid[]);
CREATE FUNCTION public.fn_etablissements_safe(p_ids uuid[])
RETURNS TABLE(
  id uuid, nom text, adresse_rue text, adresse_code_postal text, adresse_ville text,
  adresse_departement text, adresse_lat numeric, adresse_lng numeric, type text, finess text,
  taux_majoration_nuit_pourcent numeric, taux_majoration_dimanche_pourcent numeric,
  taux_majoration_ferie_pourcent numeric, logo_url text, couleur_theme text,
  paiement_rapide boolean, jour_paie_habituel smallint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        e.id, e.nom::TEXT, e.adresse_rue::TEXT, e.adresse_code_postal::TEXT,
        e.adresse_ville::TEXT, e.adresse_departement::TEXT, e.adresse_lat, e.adresse_lng,
        e.type::TEXT, e.finess::TEXT,
        e.taux_majoration_nuit_pourcent, e.taux_majoration_dimanche_pourcent,
        e.taux_majoration_ferie_pourcent, e.logo_url::TEXT, e.couleur_theme::TEXT,
        -- 7c : capacité ⚡ de l'ÉTABLISSEMENT (flag + SEPA). La condition mission
        -- LIBERAL est appliquée par le consommateur (le régime est une propriété
        -- de la mission, jamais de l'établissement).
        (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
         AND e.mode_paiement_commission = 'SEPA_DEBIT'
         AND e.stripe_sepa_payment_method_id IS NOT NULL) AS paiement_rapide,
        e.jour_paie_habituel
    FROM etablissements e
    WHERE e.id = ANY(p_ids)
      AND (
        EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.soignant_assigne_id = auth.uid())
        OR EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE')
        OR e.id = mon_etablissement_id()
        OR est_admin()
      );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_etablissements_safe(uuid[]) TO authenticated, service_role;
