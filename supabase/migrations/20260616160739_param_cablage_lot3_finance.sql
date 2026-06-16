-- Lot 3 : câblage des leviers FINANCE + boost sur fn_param_num.
-- Commission/boost = default-preserving (15 % et 0 € restent les défauts).
-- Délais de paiement : on introduit le distinguo public/privé attendu par la loi
-- (privé 30 j, public 50 j max — Code commande publique L.2192-10). Jusqu'ici
-- TOUTES les factures avaient une échéance à 30 j ; les établissements PUBLICS
-- passent désormais à 50 j (échéance plus réaliste, évite un faux « en retard »).

UPDATE public.parametres_systeme SET cablee = true
WHERE cle IN ('commission_defaut_pct', 'delai_paiement_prive_j', 'delai_paiement_public_j', 'mission_boost_prix_ht');

-- 1) Trigger commission (figée à TERMINEE).
CREATE OR REPLACE FUNCTION public.dec_calculer_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_taux NUMERIC;
BEGIN
    IF NEW.statut = 'TERMINEE' AND NEW.net_a_payer IS NOT NULL THEN
        v_taux := COALESCE(
            NEW.taux_commission_fige,
            (SELECT e.taux_commission_negocie FROM etablissements e WHERE e.id = NEW.etablissement_id),
            public.fn_param_num('commission_defaut_pct', 15)
        );

        NEW.taux_commission := v_taux;
        NEW.montant_commission_ht := ROUND(NEW.net_a_payer * (v_taux / 100.0), 2);
        NEW.montant_commission_tva := ROUND(NEW.montant_commission_ht * 0.20, 2);
        NEW.montant_commission_ttc := NEW.montant_commission_ht + NEW.montant_commission_tva;
    END IF;
    RETURN NEW;
END;
$function$;

-- 2) Trigger calcul financier mission (la commission par défaut y est aussi figée).
CREATE OR REPLACE FUNCTION public.fn_calculer_financier_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_duree numeric;
  v_taux_effectif numeric;
  v_brut_base numeric;
  v_total_majorations numeric;
  v_total_brut numeric;
  v_etab record;
  v_commission_taux numeric;
  v_commission_ht numeric;
  v_commission_tva numeric;
  v_commission_ttc numeric;
  v_has_creneaux boolean;
  v_est_salarie boolean;
BEGIN
  SELECT GREATEST(
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause), 0),
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause), 0)
  )
  INTO v_duree
  FROM mission_creneaux WHERE mission_id = NEW.id;

  SELECT EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id) INTO v_has_creneaux;

  IF NOT v_has_creneaux THEN
    v_duree := COALESCE(NEW.duree_heures, EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0);
  END IF;

  NEW.duree_heures := v_duree;

  SELECT taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
         taux_majoration_ferie_pourcent, taux_commission_negocie,
         rist_plafond_actif, rist_taux_base_horaire
  INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  v_taux_effectif := NEW.taux_horaire_base;
  IF COALESCE(v_etab.rist_plafond_actif, true) AND NEW.taux_horaire_base > COALESCE(v_etab.rist_taux_base_horaire, 25) THEN
    NEW.rist_plafond_applique := true;
    NEW.taux_rist_plafonne := COALESCE(v_etab.rist_taux_base_horaire, 25);
    v_taux_effectif := NEW.taux_rist_plafonne;
  ELSE
    NEW.rist_plafond_applique := false;
    NEW.taux_rist_plafonne := NULL;
  END IF;

  v_brut_base := v_taux_effectif * v_duree;

  NEW.montant_majoration_nuit := ROUND(COALESCE(NEW.heures_nuit, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_nuit_pourcent, 25) / 100.0, 2);
  NEW.montant_majoration_dimanche := ROUND(COALESCE(NEW.heures_dimanche, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50) / 100.0, 2);
  NEW.montant_majoration_ferie := ROUND(COALESCE(NEW.heures_ferie, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_ferie_pourcent, 100) / 100.0, 2);

  v_total_majorations := COALESCE(NEW.montant_majoration_nuit, 0) + COALESCE(NEW.montant_majoration_dimanche, 0) + COALESCE(NEW.montant_majoration_ferie, 0);
  v_total_brut := ROUND(v_brut_base + v_total_majorations, 2);
  NEW.total_brut := v_total_brut;

  NEW.montant_ifm := ROUND(v_total_brut * COALESCE(NEW.taux_ifm, 0.10), 2);
  NEW.montant_icp := ROUND(v_total_brut * COALESCE(NEW.taux_icp, 0.10), 2);
  NEW.net_a_payer := ROUND(v_total_brut + NEW.montant_ifm + NEW.montant_icp, 2);
  NEW.net_estime := ROUND(NEW.net_a_payer * 0.78, 2);

  -- AUDIT FIX : missions SALARIE → commission = 0 (l'étab paie le soignant en direct)
  v_est_salarie := COALESCE(NEW.type_paiement_soignant::text, '') = 'BULLETIN_PAIE'
                   OR COALESCE(NEW.type_contrat_applique::text, '') = 'SALARIE';

  IF v_est_salarie THEN
    v_commission_taux := 0;
  ELSE
    v_commission_taux := COALESCE(NEW.taux_commission, COALESCE(v_etab.taux_commission_negocie, public.fn_param_num('commission_defaut_pct', 15)));
  END IF;
  NEW.taux_commission := v_commission_taux;
  v_commission_ht := ROUND(v_total_brut * v_commission_taux / 100.0, 2);
  v_commission_tva := ROUND(v_commission_ht * 0.20, 2);
  v_commission_ttc := ROUND(v_commission_ht + v_commission_tva, 2);
  NEW.montant_commission_ht := v_commission_ht;
  NEW.montant_commission_tva := v_commission_tva;
  NEW.montant_commission_ttc := v_commission_ttc;

  RETURN NEW;
END;
$function$;

-- 3) Facturation mensuelle : échéance privé 30 j / public 50 j.
CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_facture_id UUID;
    v_num TEXT;
    v_compteur INT := 0;
    v_mois TEXT;
    v_recalc_info JSONB;
    v_est_public BOOLEAN;
    v_delai_j INTEGER;
    v_echeance DATE;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    v_recalc_info := public.fn_recalculer_commissions_post_litige();

    v_mois := TO_CHAR(now(), 'YYYY-MM');

    FOR v_etab IN
        SELECT etablissement_id,
               COUNT(*) as nb,
               SUM(COALESCE(montant_commission_ht, 0)) as sum_ht,
               SUM(COALESCE(montant_commission_tva, 0)) as sum_tva,
               SUM(COALESCE(montant_commission_ttc, 0)) as sum_ttc
        FROM missions m
        WHERE m.statut = 'TERMINEE'
          AND m.commission_facturee = false
          AND NOT (m.mode_remuneration = 'RETROCESSION' AND m.honoraires_confirmes_le IS NULL)
          AND m.facture_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM factures f
              WHERE f.mission_id = m.id
          )
        GROUP BY etablissement_id
    LOOP
        IF v_etab.sum_ht <= 0 THEN CONTINUE; END IF;

        SELECT COALESCE(est_secteur_public, false) INTO v_est_public
        FROM etablissements WHERE id = v_etab.etablissement_id;

        v_delai_j := CASE WHEN v_est_public
                          THEN (public.fn_param_num('delai_paiement_public_j', 50))::integer
                          ELSE (public.fn_param_num('delai_paiement_prive_j', 30))::integer END;
        v_echeance := (now() + (v_delai_j::text || ' days')::interval)::date;

        v_compteur := v_compteur + 1;
        v_num := 'FACT-' || v_mois || '-' || LPAD(v_compteur::TEXT, 4, '0');

        INSERT INTO factures (
            etablissement_id, numero_facture, montant_ht, montant_tva, montant_ttc,
            nombre_missions, statut, date_emission, date_echeance, periode_debut, periode_fin
        ) VALUES (
            v_etab.etablissement_id, v_num, v_etab.sum_ht, v_etab.sum_tva, v_etab.sum_ttc,
            v_etab.nb, 'EMISE', now(), v_echeance,
            date_trunc('month', now())::date,
            (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
        ) RETURNING id INTO v_facture_id;

        UPDATE missions
        SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id
          AND statut = 'TERMINEE'
          AND commission_facturee = false
          AND facture_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM factures f
              WHERE f.mission_id = missions.id
          );
    END LOOP;

    RETURN jsonb_build_object(
      'success', true,
      'factures_generees', v_compteur,
      'recalc_post_litige', v_recalc_info
    );
END;
$function$;

-- 4) Boost mission : lire le prix depuis parametres_systeme (source unique).
CREATE OR REPLACE FUNCTION public.fn_booster_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_prix numeric;
  v_nb int := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    INTO v_m
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Seule une mission ouverte peut être boostée.'); END IF;
  IF v_m.boostee_le IS NOT NULL THEN RETURN jsonb_build_object('error', 'Cette mission est déjà boostée.'); END IF;

  v_prix := public.fn_param_num('mission_boost_prix_ht', 0);

  UPDATE missions SET boostee_le = NOW(), montant_boost_ht = COALESCE(v_prix, 0), modifie_le = NOW()
   WHERE id = p_mission_id;

  WITH cibles AS (
    SELECT s.id
    FROM soignants s
    WHERE s.profession = v_m.profession_requise
      AND s.supprime_le IS NULL
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND (v_m.type_contrat_recherche = 'TOUS'
           OR (v_m.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice,'SALARIE') IN ('SALARIE','MIXTE'))
           OR (v_m.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice,'SALARIE') IN ('LIBERAL','MIXTE')))
      AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = v_m.id AND c.soignant_id = s.id)
      AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
           OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
              <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
    LIMIT 50
  )
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  SELECT id, 'MISSION_A_POURVOIR',
    '🚀 Mission mise en avant près de chez vous',
    fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
    TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
    COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L''établissement recherche activement.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT'
  FROM cibles;
  GET DIAGNOSTICS v_nb = ROW_COUNT;

  RETURN jsonb_build_object('success', TRUE, 'soignants_notifies', v_nb, 'prix_ht', COALESCE(v_prix, 0));
END;
$function$;
