-- 7d-A (Lot 7 v2 — A1 scoring v2 + A2 deck) — le « 72/100 » qui paraît intelligent.
--
-- 1) marche_taux_medians : médiane des taux par profession (90 j), rafraîchie
--    par le cron horaire — le tarif est scoré RELATIF au marché local, plus
--    jamais contre un seuil fixe 30 €.
-- 2) matching_preferences_soignant : pattern horaire APPRIS des swipes
--    (jour/nuit × semaine/weekend, lissage de Laplace). Chaque swipe = signal.
-- 3) fn_calculer_score_matching v3 : pondérations rééquilibrées
--    tarif-vs-médiane 20 + distance 20 + horaire appris 15 + étab 15 +
--    urgence 10 + fiabilité soignant 10 + fraîcheur 5
--    + bonus : connaissance étab +8, ⚡ paiement rapide +5, boost +10. Cap 100.
--    (Temps de trajet transit : hors périmètre sans clé API — fallback distance,
--    prévu par la spec.)
-- 4) Deck : exploration 10-15 % via jitter de tri (±12 pts) dans
--    fn_obtenir_missions_swipe — le stack reste « meilleures d'abord » mais
--    ne fige plus le même ordre à chaque session.
-- 5) Cap push : fn_evaluer_alertes_filtres n'envoie plus qu'UNE notification
--    MISSION_A_POURVOIR par 20 h et par soignant (l'email suit son propre rythme).

-- ── 1. Médianes de marché ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.marche_taux_medians (
  profession text PRIMARY KEY,
  taux_median numeric NOT NULL,
  nb_missions integer NOT NULL DEFAULT 0,
  calcule_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.marche_taux_medians ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_marche_medians_select ON public.marche_taux_medians;
CREATE POLICY pol_marche_medians_select ON public.marche_taux_medians
  FOR SELECT TO authenticated USING (true);

-- ── 2. Préférences horaires apprises ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.matching_preferences_soignant (
  soignant_id uuid PRIMARY KEY REFERENCES public.soignants(id) ON DELETE CASCADE,
  pref_nuit numeric NOT NULL DEFAULT 0.5,
  pref_jour numeric NOT NULL DEFAULT 0.5,
  pref_weekend numeric NOT NULL DEFAULT 0.5,
  pref_semaine numeric NOT NULL DEFAULT 0.5,
  nb_signaux integer NOT NULL DEFAULT 0,
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.matching_preferences_soignant ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_matching_prefs_select ON public.matching_preferences_soignant;
CREATE POLICY pol_matching_prefs_select ON public.matching_preferences_soignant
  FOR SELECT TO authenticated USING (soignant_id = (SELECT auth.uid()));

-- ── 3. Rafraîchissement des données d'appui (appelé en tête du cron) ────────
CREATE OR REPLACE FUNCTION public.fn_rafraichir_donnees_matching()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  -- Médiane des taux par profession sur les missions des 90 derniers jours.
  INSERT INTO public.marche_taux_medians (profession, taux_median, nb_missions, calcule_le)
  SELECT m.profession_requise::text,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.taux_horaire_base),
         COUNT(*)::integer,
         now()
    FROM public.missions m
   WHERE m.taux_horaire_base IS NOT NULL
     AND m.profession_requise IS NOT NULL
     AND m.cree_le > now() - interval '90 days'
   GROUP BY m.profession_requise
  HAVING COUNT(*) >= 3
  ON CONFLICT (profession) DO UPDATE SET
    taux_median = EXCLUDED.taux_median,
    nb_missions = EXCLUDED.nb_missions,
    calcule_le = EXCLUDED.calcule_le;

  -- Pattern horaire appris : ratio de likes par tranche (nuit 20h-7h / jour,
  -- weekend / semaine), lissage de Laplace (+1/+2) — neutre 0,5 sans signal.
  INSERT INTO public.matching_preferences_soignant
    (soignant_id, pref_nuit, pref_jour, pref_weekend, pref_semaine, nb_signaux, maj_le)
  SELECT agg.sid,
         (agg.likes_nuit + 1.0) / (agg.tot_nuit + 2.0),
         (agg.likes_jour + 1.0) / (agg.tot_jour + 2.0),
         (agg.likes_we   + 1.0) / (agg.tot_we   + 2.0),
         (agg.likes_sem  + 1.0) / (agg.tot_sem  + 2.0),
         agg.total::integer,
         now()
  FROM (
    SELECT b.sid,
           COUNT(*) FILTER (WHERE b.est_nuit)              AS tot_nuit,
           COUNT(*) FILTER (WHERE b.est_nuit AND b.aime)   AS likes_nuit,
           COUNT(*) FILTER (WHERE NOT b.est_nuit)           AS tot_jour,
           COUNT(*) FILTER (WHERE NOT b.est_nuit AND b.aime) AS likes_jour,
           COUNT(*) FILTER (WHERE b.est_we)                 AS tot_we,
           COUNT(*) FILTER (WHERE b.est_we AND b.aime)      AS likes_we,
           COUNT(*) FILTER (WHERE NOT b.est_we)             AS tot_sem,
           COUNT(*) FILTER (WHERE NOT b.est_we AND b.aime)  AS likes_sem,
           COUNT(*) AS total
    FROM (
      SELECT sw.soignant_id AS sid,
             (EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') >= 20
              OR EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') < 7) AS est_nuit,
             (EXTRACT(DOW FROM m.debut_le AT TIME ZONE 'Europe/Paris') IN (0, 6)) AS est_we,
             (sw.direction::text IN ('LIKE', 'SUPER_LIKE', 'FAVORI')) AS aime
        FROM public.swipes sw
        JOIN public.missions m ON m.id = sw.mission_id
       WHERE sw.created_at > now() - interval '90 days'
         AND m.debut_le IS NOT NULL
    ) b
    GROUP BY b.sid
  ) agg
  ON CONFLICT (soignant_id) DO UPDATE SET
    pref_nuit = EXCLUDED.pref_nuit,
    pref_jour = EXCLUDED.pref_jour,
    pref_weekend = EXCLUDED.pref_weekend,
    pref_semaine = EXCLUDED.pref_semaine,
    nb_signaux = EXCLUDED.nb_signaux,
    maj_le = EXCLUDED.maj_le;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_rafraichir_donnees_matching() TO service_role;

-- ── 4. Scoring v3 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_calculer_score_matching(p_soignant_id uuid, p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant record;
  v_mission record;
  v_etab record;
  v_prefs record;
  v_taux_median numeric;
  v_distance_km numeric;
  v_ratio numeric;
  v_est_nuit boolean;
  v_est_we boolean;
  v_score_tarif integer := 0;
  v_score_distance integer := 0;
  v_score_horaire integer := 0;
  v_score_etab integer := 0;
  v_score_urgence integer := 0;
  v_score_soignant_fiabilite integer := 0;
  v_bonus_fraicheur integer := 0;
  v_bonus_connaissance integer := 0;
  v_bonus_paiement_rapide integer := 0;
  v_bonus_boost integer := 0;
  v_score_global integer := 0;
  v_breakdown jsonb;
BEGIN
  SELECT id, profession, adresse_lat, adresse_lng, score_fiabilite, type_contrat
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id;

  IF v_soignant.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'soignant_introuvable'));
  END IF;

  SELECT m.id, m.profession_requise, m.etablissement_id, m.taux_horaire_base,
         m.statut, m.est_urgente, m.debut_le, m.fin_le, m.duree_heures,
         m.cree_le, m.boostee_le, m.type_contrat_recherche
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id;

  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'mission_introuvable'));
  END IF;

  IF v_mission.profession_requise IS NOT NULL
     AND v_soignant.profession IS NOT NULL
     AND v_mission.profession_requise <> v_soignant.profession THEN
    RETURN jsonb_build_object(
      'score', 0,
      'breakdown', jsonb_build_object('filtre_dur_ko', 'profession_incompatible')
    );
  END IF;

  SELECT id, adresse_lat, adresse_lng, score_qualite,
         mode_paiement_commission, stripe_sepa_payment_method_id
    INTO v_etab
    FROM public.etablissements
   WHERE id = v_mission.etablissement_id;

  IF v_soignant.adresse_lat IS NOT NULL
     AND v_soignant.adresse_lng IS NOT NULL
     AND v_etab.adresse_lat IS NOT NULL
     AND v_etab.adresse_lng IS NOT NULL THEN
    v_distance_km := 6371 * acos(
      cos(radians(v_soignant.adresse_lat)) * cos(radians(v_etab.adresse_lat))
      * cos(radians(v_etab.adresse_lng) - radians(v_soignant.adresse_lng))
      + sin(radians(v_soignant.adresse_lat)) * sin(radians(v_etab.adresse_lat))
    );

    IF v_distance_km > 50 THEN
      RETURN jsonb_build_object(
        'score', 0,
        'breakdown', jsonb_build_object(
          'filtre_dur_ko', 'distance_excessive',
          'distance_km', round(v_distance_km, 1)
        )
      );
    END IF;
  ELSE
    v_distance_km := NULL;
  END IF;

  -- v3 : tarif RELATIF à la médiane de marché de la profession (90 j).
  -- ratio 0,7× → 2 pts, 1,0× → ~13 pts, ≥1,2× → 20 pts. Fallback ancien
  -- barème (seuil 30 €) si pas assez de données de marché.
  SELECT taux_median INTO v_taux_median
    FROM public.marche_taux_medians
   WHERE profession = v_mission.profession_requise::text;

  IF v_mission.taux_horaire_base IS NULL THEN
    v_score_tarif := 10;
  ELSIF v_taux_median IS NOT NULL AND v_taux_median > 0 THEN
    v_ratio := v_mission.taux_horaire_base / v_taux_median;
    v_score_tarif := LEAST(20, GREATEST(2, round(2 + (v_ratio - 0.7) / 0.5 * 18)::integer));
  ELSE
    v_score_tarif := LEAST(20, GREATEST(0,
      CASE WHEN v_mission.taux_horaire_base >= 30 THEN 20
           ELSE round(v_mission.taux_horaire_base / 30.0 * 20)::integer END));
  END IF;

  v_score_distance := CASE
    WHEN v_distance_km IS NULL THEN 10
    WHEN v_distance_km < 5 THEN 20
    WHEN v_distance_km >= 50 THEN 0
    ELSE round(20 * (1 - (v_distance_km - 5) / 45.0))::integer
  END;

  -- v3 : pattern horaire appris — 15 × moyenne(pref tranche-heure, pref
  -- tranche-semaine). Neutre (7-8 pts) sans historique de swipe.
  v_est_nuit := v_mission.debut_le IS NOT NULL AND (
    EXTRACT(HOUR FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') >= 20
    OR EXTRACT(HOUR FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') < 7);
  v_est_we := v_mission.debut_le IS NOT NULL
    AND EXTRACT(DOW FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') IN (0, 6);

  SELECT * INTO v_prefs
    FROM public.matching_preferences_soignant
   WHERE soignant_id = p_soignant_id;

  v_score_horaire := round(15 * (
    (CASE WHEN v_est_nuit THEN COALESCE(v_prefs.pref_nuit, 0.5) ELSE COALESCE(v_prefs.pref_jour, 0.5) END
     + CASE WHEN v_est_we THEN COALESCE(v_prefs.pref_weekend, 0.5) ELSE COALESCE(v_prefs.pref_semaine, 0.5) END
    ) / 2.0))::integer;

  v_score_etab := LEAST(15, GREATEST(0,
    CASE
      WHEN v_etab.score_qualite IS NULL THEN 7
      ELSE round(v_etab.score_qualite / 100.0 * 15)::integer
    END
  ));

  v_score_urgence := CASE WHEN v_mission.est_urgente THEN 10 ELSE 0 END;

  v_score_soignant_fiabilite := LEAST(10, GREATEST(0,
    CASE
      WHEN v_soignant.score_fiabilite IS NULL THEN 5
      ELSE round(COALESCE(v_soignant.score_fiabilite, 50) / 100.0 * 10)::integer
    END
  ));

  v_bonus_fraicheur := LEAST(5, GREATEST(0,
    5 - FLOOR(EXTRACT(EPOCH FROM (NOW() - COALESCE(v_mission.cree_le, NOW()))) / 86400)::integer
  ));

  -- v3 : bonus fort « tu connais cet établissement » (mission déjà réalisée).
  v_bonus_connaissance := CASE WHEN EXISTS (
    SELECT 1 FROM public.missions mh
     WHERE mh.soignant_assigne_id = p_soignant_id
       AND mh.etablissement_id = v_mission.etablissement_id
       AND mh.statut = 'TERMINEE'
  ) THEN 8 ELSE 0 END;

  -- v3 : bonus ⚡ paiement rapide (même gating serveur que le badge 7c).
  v_bonus_paiement_rapide := CASE WHEN
    public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
    AND v_mission.type_contrat_recherche = 'LIBERAL'
    AND v_etab.mode_paiement_commission = 'SEPA_DEBIT'
    AND v_etab.stripe_sepa_payment_method_id IS NOT NULL
  THEN 5 ELSE 0 END;

  v_bonus_boost := CASE
    WHEN v_mission.boostee_le IS NOT NULL AND v_mission.boostee_le > NOW() - INTERVAL '7 days' THEN 10
    ELSE 0
  END;

  v_score_global := v_score_tarif + v_score_distance + v_score_horaire + v_score_etab
                  + v_score_urgence + v_score_soignant_fiabilite
                  + v_bonus_fraicheur + v_bonus_connaissance
                  + v_bonus_paiement_rapide + v_bonus_boost;

  v_breakdown := jsonb_build_object(
    'tarif', v_score_tarif,
    'distance', v_score_distance,
    'horaire', v_score_horaire,
    'etablissement', v_score_etab,
    'urgence', v_score_urgence,
    'soignant_fiabilite', v_score_soignant_fiabilite,
    'fraicheur', v_bonus_fraicheur,
    'connaissance_etab', v_bonus_connaissance,
    'paiement_rapide', v_bonus_paiement_rapide,
    'boost', v_bonus_boost,
    'distance_km', CASE WHEN v_distance_km IS NULL THEN NULL ELSE round(v_distance_km, 1) END,
    'taux_median', v_taux_median
  );

  RETURN jsonb_build_object(
    'score', LEAST(100, GREATEST(0, v_score_global)),
    'breakdown', v_breakdown
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_score_matching(uuid, uuid) TO authenticated, service_role;

-- ── 5. Cron : rafraîchir les données d'appui avant le recalcul ──────────────
CREATE OR REPLACE FUNCTION public.fn_recalculer_scores_soignants_actifs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant record;
  v_mission record;
  v_result jsonb;
  v_count integer := 0;
  v_start timestamptz := clock_timestamp();
BEGIN
  -- 7d : médianes de marché + préférences horaires apprises, en amont du calcul.
  PERFORM public.fn_rafraichir_donnees_matching();

  -- Soignants actifs : ont swipé ou ont eu activité auth récente (24h)
  FOR v_soignant IN
    SELECT DISTINCT s.id
      FROM public.soignants s
      LEFT JOIN public.swipes sw ON sw.soignant_id = s.id
        AND sw.created_at > now() - interval '24 hours'
     WHERE sw.id IS NOT NULL
        OR EXISTS (
          SELECT 1 FROM auth.users u
           WHERE u.id = s.id AND u.last_sign_in_at > now() - interval '24 hours'
        )
     LIMIT 200
  LOOP
    FOR v_mission IN
      SELECT m.id
        FROM public.missions m
       WHERE m.statut = 'OUVERTE'
         AND m.id NOT IN (
           SELECT mission_id FROM public.swipes WHERE soignant_id = v_soignant.id
         )
       LIMIT 50
    LOOP
      v_result := public.fn_calculer_score_matching(v_soignant.id, v_mission.id);

      INSERT INTO public.matching_scores (soignant_id, mission_id, score_global, breakdown)
        VALUES (
          v_soignant.id,
          v_mission.id,
          (v_result->>'score')::integer,
          v_result->'breakdown'
        )
        ON CONFLICT (soignant_id, mission_id)
          DO UPDATE SET
            score_global = EXCLUDED.score_global,
            breakdown = EXCLUDED.breakdown,
            calcule_le = now();

      v_count := v_count + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'scores_calcules', v_count,
    'duree_ms', extract(epoch from (clock_timestamp() - v_start)) * 1000
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_recalculer_scores_soignants_actifs() TO service_role;

-- ── 6. Deck : exploration 10-15 % (jitter de tri ±12 pts) ───────────────────
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
  -- 7d-A2 : tri = score + jitter aléatoire 0-12 pts → les meilleures restent
  -- devant, mais 10-15 % de missions à score moyen remontent (exploration).
  SELECT COALESCE(jsonb_agg(payload ORDER BY tri DESC), '[]'::jsonb) INTO v_missions
  FROM (
    SELECT (COALESCE(ms.score_global, 0) + floor(random() * 13))::int AS tri,
      jsonb_build_object(
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

-- ── 7. Cap push : max 1 notification MISSION_A_POURVOIR / 20 h / soignant ───
CREATE OR REPLACE FUNCTION public.fn_evaluer_alertes_filtres(p_frequence text DEFAULT NULL::text)
 RETURNS TABLE(filtre_id uuid, utilisateur_id uuid, audience filtre_audience, nom text, nb_nouveaux integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  r RECORD;
  v_count integer;
BEGIN
  FOR r IN
    SELECT * FROM filtres_sauvegardes
    WHERE alerte_active = true
      AND (
        (p_frequence IS NULL OR frequence_alerte::text = p_frequence)
        AND (
          (frequence_alerte = 'QUOTIDIENNE'   AND dernier_check_le < now() - interval '23 hours') OR
          (frequence_alerte = 'HEBDOMADAIRE'  AND dernier_check_le < now() - interval '6 days 23 hours') OR
          (frequence_alerte = 'IMMEDIATE'     AND dernier_check_le < now() - interval '55 minutes')
        )
      )
  LOOP
    v_count := fn_compter_nouveaux_pour_filtre(r.id, r.dernier_check_le);
    UPDATE filtres_sauvegardes
    SET dernier_check_le = now(),
        nb_resultats_dernier_check = v_count
    WHERE id = r.id;
    IF v_count > 0 THEN
      -- 6c.4 : notification in-app/push (soignant) avec deep-link direct dans
      -- le deck de swipe. L'email (pipeline existant) part en parallèle via
      -- les lignes retournées par cette fonction.
      -- 7d-A2 : CAP DE FRÉQUENCE — au plus une notification MISSION_A_POURVOIR
      -- par 20 h et par soignant, toutes recherches confondues (anti-spam).
      IF r.audience = 'SOIGNANT_RECHERCHE_MISSIONS' AND NOT EXISTS (
        SELECT 1 FROM notifications n
         WHERE n.destinataire_id = r.utilisateur_id
           AND n.type = 'MISSION_A_POURVOIR'
           AND n.cree_le > now() - interval '20 hours'
      ) THEN
        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          r.utilisateur_id, 'SOIGNANT', 'MISSION_A_POURVOIR',
          '✨ ' || v_count || ' nouvelle' || CASE WHEN v_count > 1 THEN 's' ELSE '' END
            || ' mission' || CASE WHEN v_count > 1 THEN 's' ELSE '' END
            || ' pour « ' || r.nom || ' »',
          'De nouvelles missions correspondent à ta recherche sauvegardée — découvre-les avant les autres.',
          '/soignant/recherche-missions?vue=swipe'
        );
      END IF;

      filtre_id := r.id;
      utilisateur_id := r.utilisateur_id;
      audience := r.audience;
      nom := r.nom;
      nb_nouveaux := v_count;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$;
