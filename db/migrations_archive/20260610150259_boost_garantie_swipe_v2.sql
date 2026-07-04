-- Machine à cash + anti no-show + swipe v2 :
-- ① Mission boostée : flag + prix configurable (0 = offert au lancement) + RPC
--    fn_booster_mission (notifie les soignants compatibles + priorité matching).
-- ② Garantie remplacement : opt-in par mission + confirmation de présence J-1 +
--    détection no-show (30 min sans pointage) → mission de remplacement URGENTE
--    PREMIER_ARRIVE créée automatiquement + pool urgence notifié.
-- ③ Swipe v2 : bonus fraîcheur (+5 dégressif sur 5 jours) + bonus boost (+10)
--    dans fn_calculer_score_matching.
-- NOTE : déjà appliquée en prod via MCP (version 20260610150259), crons testés.

-- Colonnes missions
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS boostee_le timestamptz;
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS montant_boost_ht numeric;
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS garantie_remplacement boolean NOT NULL DEFAULT false;
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS presence_confirmee_le timestamptz;
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS remplacement_de_mission_id uuid;

-- Prix configurables (growth_config) — 0 = inclus offre de lancement
INSERT INTO public.growth_config (cle, valeur) VALUES ('mission_boost_prix_ht', '0')
ON CONFLICT (cle) DO NOTHING;
INSERT INTO public.growth_config (cle, valeur) VALUES ('garantie_remplacement_prix_pct', '0')
ON CONFLICT (cle) DO NOTHING;

-- ① RPC : booster une mission (établissement propriétaire, mission OUVERTE)
CREATE OR REPLACE FUNCTION public.fn_booster_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
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

  SELECT COALESCE(NULLIF(valeur, '')::numeric, 0) INTO v_prix
    FROM growth_config WHERE cle = 'mission_boost_prix_ht';

  UPDATE missions SET boostee_le = NOW(), montant_boost_ht = COALESCE(v_prix, 0), modifie_le = NOW()
   WHERE id = p_mission_id;

  -- Notification immédiate aux soignants compatibles (profession + contrat + rayon), max 50
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
$body$;
GRANT EXECUTE ON FUNCTION public.fn_booster_mission(uuid) TO authenticated;

-- ② RPC : activer/désactiver la garantie remplacement (mission OUVERTE/ASSIGNEE)
CREATE OR REPLACE FUNCTION public.fn_activer_garantie_mission(p_mission_id uuid, p_actif boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut NOT IN ('OUVERTE', 'ASSIGNEE') THEN
    RETURN jsonb_build_object('error', 'La garantie ne peut être modifiée que sur une mission ouverte ou assignée.');
  END IF;
  UPDATE missions SET garantie_remplacement = p_actif, modifie_le = NOW() WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'garantie', p_actif);
END;
$body$;
GRANT EXECUTE ON FUNCTION public.fn_activer_garantie_mission(uuid, boolean) TO authenticated;

-- ② RPC : le soignant confirme sa présence (J-1)
CREATE OR REPLACE FUNCTION public.fn_confirmer_presence_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id AND soignant_assigne_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  UPDATE missions SET presence_confirmee_le = NOW(), modifie_le = NOW() WHERE id = p_mission_id;
  -- L'établissement est rassuré en temps réel
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.etablissement_id, 'SYSTEM', 'Présence confirmée ✓',
    'Le soignant a confirmé sa présence pour "' || fn_html_escape(v_m.intitule) || '" du ' ||
    TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || '.',
    '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');
  RETURN jsonb_build_object('success', TRUE);
END;
$body$;
GRANT EXECUTE ON FUNCTION public.fn_confirmer_presence_mission(uuid) TO authenticated;

-- ② Cron 1/jour 17h : demander la confirmation de présence pour les missions de demain
CREATE OR REPLACE FUNCTION public.fn_demander_confirmations_presence()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE v_m RECORD; v_nb int := 0;
BEGIN
  FOR v_m IN
    SELECT m.id, m.intitule, m.debut_le, m.soignant_assigne_id
    FROM missions m
    WHERE m.statut = 'ASSIGNEE'
      AND m.soignant_assigne_id IS NOT NULL
      AND m.presence_confirmee_le IS NULL
      AND m.debut_le BETWEEN NOW() + INTERVAL '12 hours' AND NOW() + INTERVAL '36 hours'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = m.soignant_assigne_id AND n.type = 'RAPPEL_MISSION'
          AND n.lien = '/soignant/missions/' || m.id
          AND n.cree_le > NOW() - INTERVAL '20 hours')
  LOOP
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'RAPPEL_MISSION', 'Confirmez votre présence pour demain',
      '"' || fn_html_escape(v_m.intitule) || '" démarre le ' ||
      TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
      '. Confirmez votre présence en 1 clic — l''établissement compte sur vous.',
      '/soignant/missions/' || v_m.id, 'SOIGNANT');
    v_nb := v_nb + 1;
  END LOOP;
  RETURN jsonb_build_object('success', TRUE, 'demandes', v_nb);
END;
$body$;

-- ② Cron 10 min : détection no-show → remplacement automatique (missions garanties)
CREATE OR REPLACE FUNCTION public.fn_detecter_noshow_et_remplacer()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_m RECORD;
  v_remplacement_id uuid;
  v_traites int := 0;
  v_remplacements int := 0;
BEGIN
  FOR v_m IN
    SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND m.soignant_assigne_id IS NOT NULL
      AND m.debut_le < NOW() - INTERVAL '30 minutes'
      AND m.debut_le > NOW() - INTERVAL '4 hours'
      AND m.fin_le > NOW() + INTERVAL '1 hour'
      AND NOT EXISTS (SELECT 1 FROM presences p WHERE p.mission_id = m.id AND p.soignant_id = m.soignant_assigne_id)
      AND NOT EXISTS (SELECT 1 FROM missions r WHERE r.remplacement_de_mission_id = m.id)
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = m.etablissement_id AND n.type = 'SYSTEM'
          AND n.lien = '/etablissement/missions/' || m.id
          AND n.titre LIKE 'Aucun pointage%'
          AND n.cree_le > NOW() - INTERVAL '6 hours')
  LOOP
    v_traites := v_traites + 1;

    IF v_m.garantie_remplacement THEN
      -- Mission de remplacement : URGENTE, premier arrivé, durée restante
      INSERT INTO missions (
        etablissement_id, intitule, description, service,
        profession_requise, specialite_medicale_requise, accepte_non_specialises,
        debut_le, fin_le, duree_heures, taux_horaire_base,
        type_contrat_recherche, statut, mode_attribution,
        est_urgente, niveau_urgence, remplacement_de_mission_id
      ) VALUES (
        v_m.etablissement_id,
        'REMPLACEMENT URGENT — ' || v_m.intitule,
        COALESCE(v_m.description, '') || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]',
        v_m.service,
        v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_non_specialises,
        GREATEST(v_m.debut_le, NOW() + INTERVAL '15 minutes'), v_m.fin_le,
        ROUND(EXTRACT(EPOCH FROM (v_m.fin_le - GREATEST(v_m.debut_le, NOW() + INTERVAL '15 minutes'))) / 3600.0, 2),
        v_m.type_contrat_recherche, 'OUVERTE', 'PREMIER_ARRIVE',
        TRUE, 3, v_m.id
      ) RETURNING id INTO v_remplacement_id;

      -- Pool urgence : soignants compatibles disponibles, max 50
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      SELECT s.id, 'POOL_URGENCE',
        '🚨 Remplacement immédiat — premier arrivé, premier servi',
        fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', MAINTENANT à ' ||
        COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Acceptez en 1 clic.',
        '/soignant/missions/' || v_remplacement_id, 'SOIGNANT'
      FROM soignants s
      WHERE s.profession = v_m.profession_requise
        AND s.supprime_le IS NULL
        AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
        AND COALESCE(s.tous_documents_valides, false)
        AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
        AND s.id != v_m.soignant_assigne_id
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
      LIMIT 50;

      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_m.etablissement_id, 'SYSTEM', 'Aucun pointage — remplacement lancé 🚨',
        'Aucun pointage détecté 30 min après le début de "' || fn_html_escape(v_m.intitule) ||
        '". Garantie remplacement activée : une mission de remplacement urgente vient d''être diffusée au pool de soignants disponibles.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

      v_remplacements := v_remplacements + 1;
    ELSE
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_m.etablissement_id, 'SYSTEM', 'Aucun pointage détecté ⚠️',
        'Aucun pointage 30 min après le début de "' || fn_html_escape(v_m.intitule) ||
        '". Contactez le soignant, ou alertez le pool d''urgence depuis la mission.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');
    END IF;

    -- Le soignant absent est notifié dans les deux cas (rappel conséquences score)
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Aucun pointage détecté sur votre mission',
      'Votre mission "' || fn_html_escape(v_m.intitule) || '" a démarré il y a 30 min sans pointage. ' ||
      'Pointez immédiatement ou contactez l''établissement — une absence non justifiée impacte fortement votre score de fiabilité.',
      '/soignant/presences', 'SOIGNANT');
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'detectes', v_traites, 'remplacements', v_remplacements);
END;
$body$;

-- ③ Swipe v2 : fn_calculer_score_matching avec fraîcheur + boost (corps complet
-- repris de la v1, ajouts : v_bonus_fraicheur, v_bonus_boost, breakdown enrichi).
-- Voir la version appliquée en prod (identique) — fonction recréée ci-dessous.
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
  v_distance_km numeric;
  v_score_tarif integer := 0;
  v_score_distance integer := 0;
  v_score_etab integer := 0;
  v_score_urgence integer := 0;
  v_score_soignant_fiabilite integer := 0;
  v_bonus_fraicheur integer := 0;
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
         m.cree_le, m.boostee_le
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

  SELECT id, adresse_lat, adresse_lng, score_qualite
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

  v_score_tarif := LEAST(25, GREATEST(0,
    CASE
      WHEN v_mission.taux_horaire_base IS NULL THEN 12
      WHEN v_mission.taux_horaire_base >= 30 THEN 25
      ELSE round(v_mission.taux_horaire_base / 30.0 * 25)::integer
    END
  ));

  v_score_distance := CASE
    WHEN v_distance_km IS NULL THEN 12
    WHEN v_distance_km < 5 THEN 25
    WHEN v_distance_km >= 50 THEN 0
    ELSE round(25 * (1 - (v_distance_km - 5) / 45.0))::integer
  END;

  v_score_etab := LEAST(20, GREATEST(0,
    CASE
      WHEN v_etab.score_qualite IS NULL THEN 10
      ELSE round(v_etab.score_qualite / 100.0 * 20)::integer
    END
  ));

  v_score_urgence := CASE WHEN v_mission.est_urgente THEN 15 ELSE 0 END;

  v_score_soignant_fiabilite := LEAST(15, GREATEST(0,
    CASE
      WHEN v_soignant.score_fiabilite IS NULL THEN 8
      ELSE round(COALESCE(v_soignant.score_fiabilite, 50) / 100.0 * 15)::integer
    END
  ));

  -- v2 : bonus fraîcheur — une mission publiée aujourd'hui gagne +5, dégressif sur 5 jours.
  v_bonus_fraicheur := LEAST(5, GREATEST(0,
    5 - FLOOR(EXTRACT(EPOCH FROM (NOW() - COALESCE(v_mission.cree_le, NOW()))) / 86400)::integer
  ));

  -- v2 : bonus boost — une mission boostée (< 7 jours) remonte en tête de stack.
  v_bonus_boost := CASE
    WHEN v_mission.boostee_le IS NOT NULL AND v_mission.boostee_le > NOW() - INTERVAL '7 days' THEN 10
    ELSE 0
  END;

  v_score_global := v_score_tarif + v_score_distance + v_score_etab
                  + v_score_urgence + v_score_soignant_fiabilite
                  + v_bonus_fraicheur + v_bonus_boost;

  v_breakdown := jsonb_build_object(
    'tarif', v_score_tarif,
    'distance', v_score_distance,
    'etablissement', v_score_etab,
    'urgence', v_score_urgence,
    'soignant_fiabilite', v_score_soignant_fiabilite,
    'fraicheur', v_bonus_fraicheur,
    'boost', v_bonus_boost,
    'distance_km', CASE WHEN v_distance_km IS NULL THEN NULL ELSE round(v_distance_km, 1) END
  );

  RETURN jsonb_build_object(
    'score', LEAST(100, GREATEST(0, v_score_global)),
    'breakdown', v_breakdown
  );
END;
$function$;

-- Crons
DO $cron$
BEGIN
  PERFORM cron.schedule('confirmations-presence-j1', '0 17 * * *',
    'SELECT fn_demander_confirmations_presence()');
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron$;
DO $cron$
BEGIN
  PERFORM cron.schedule('detecter-noshow-remplacer', '*/10 * * * *',
    'SELECT fn_detecter_noshow_et_remplacer()');
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron$;
