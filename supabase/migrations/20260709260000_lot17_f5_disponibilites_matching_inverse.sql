-- Lot 17 — F5 : calendrier de disponibilités soignant + matching inversé
-- + vivier de disponibilités côté établissement + traçage republication.
--
-- Constats (09/07/2026) :
--   F5 : aucune table de disponibilités — le seul « calendrier » existant est
--     l'export ICS sortant des missions assignées (calendar-feed). Pas de
--     matching inversé (« N missions correspondent à tes dispos »), pas de
--     vivier visible côté établissement.
--   F2 : « Republier » (F3) passe par fn_creer_mission et ne renseignait pas
--     mission_source — la valeur REPUBLICATION n'existait pas dans le CHECK.

-- ── 1. Table disponibilites_soignant ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.disponibilites_soignant (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  jour date NOT NULL,
  creneau text NOT NULL CHECK (creneau IN ('JOURNEE', 'MATIN', 'APRES_MIDI', 'NUIT')),
  cree_le timestamptz NOT NULL DEFAULT now(),
  UNIQUE (soignant_id, jour, creneau)
);
CREATE INDEX IF NOT EXISTS idx_dispos_soignant_jour ON public.disponibilites_soignant (jour, creneau);
CREATE INDEX IF NOT EXISTS idx_dispos_soignant_soignant ON public.disponibilites_soignant (soignant_id, jour);

ALTER TABLE public.disponibilites_soignant ENABLE ROW LEVEL SECURITY;
-- Le soignant lit ses propres disponibilités ; écriture via RPC uniquement.
DROP POLICY IF EXISTS dispos_soignant_select ON public.disponibilites_soignant;
CREATE POLICY dispos_soignant_select ON public.disponibilites_soignant
  FOR SELECT USING (soignant_id = auth.uid() OR est_admin());
GRANT SELECT ON public.disponibilites_soignant TO authenticated;

-- ── 2. RPC de saisie (upsert/suppression) ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_definir_disponibilite(p_jour date, p_creneau text, p_disponible boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM soignants s WHERE s.id = v_uid AND s.supprime_le IS NULL) THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;
  IF p_creneau NOT IN ('JOURNEE', 'MATIN', 'APRES_MIDI', 'NUIT') THEN
    RETURN jsonb_build_object('error', 'Créneau invalide');
  END IF;
  IF p_jour < CURRENT_DATE OR p_jour > CURRENT_DATE + 90 THEN
    RETURN jsonb_build_object('error', 'La disponibilité doit être entre aujourd''hui et J+90');
  END IF;

  IF p_disponible THEN
    INSERT INTO disponibilites_soignant (soignant_id, jour, creneau)
    VALUES (v_uid, p_jour, p_creneau)
    ON CONFLICT (soignant_id, jour, creneau) DO NOTHING;
  ELSE
    DELETE FROM disponibilites_soignant
    WHERE soignant_id = v_uid AND jour = p_jour AND creneau = p_creneau;
  END IF;

  RETURN jsonb_build_object('success', TRUE);
END;
$fn$;

-- ── 3. Matching inversé — « N missions correspondent à tes disponibilités » ──
-- Quotidien : pour chaque soignant ayant des dispos sur J..J+14, compte les
-- missions OUVERTE compatibles (profession, jour, créneau jour/nuit, distance,
-- non swipées). Notification MISSION_A_POURVOIR (respecte le cap A2 partagé
-- alerte_filtre_cap_h — jamais deux MISSION_A_POURVOIR dans la fenêtre du cap).
CREATE OR REPLACE FUNCTION public.fn_matching_inverse_dispos()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_s RECORD;
  v_count int;
  v_notifies int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  v_cap_h int := GREATEST(1, fn_param_num('alerte_filtre_cap_h', 20)::int);
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  FOR v_s IN
    SELECT DISTINCT s.id, s.profession, s.adresse_lat, s.adresse_lng, s.rayon_deplacement_km
    FROM soignants s
    JOIN disponibilites_soignant d ON d.soignant_id = s.id
    WHERE d.jour BETWEEN CURRENT_DATE AND CURRENT_DATE + 14
      AND s.supprime_le IS NULL
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND COALESCE(s.tous_documents_valides, false)
      -- respecte le cap MISSION_A_POURVOIR partagé (A2)
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = s.id AND n.type = 'MISSION_A_POURVOIR'
          AND n.cree_le > NOW() - make_interval(hours => v_cap_h))
  LOOP
    SELECT COUNT(*) INTO v_count
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.profession_requise = v_s.profession
      AND m.debut_le > NOW()
      AND m.intitule NOT LIKE '[%'
      AND NOT fn_est_exclu(v_s.id, m.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM swipes sw WHERE sw.mission_id = m.id AND sw.soignant_id = v_s.id)
      AND (v_s.adresse_lat IS NULL OR e.adresse_lat IS NULL
           OR fn_haversine_distance_m(v_s.adresse_lat, v_s.adresse_lng, e.adresse_lat, e.adresse_lng)
              <= COALESCE(v_s.rayon_deplacement_km, 50) * 1000)
      AND EXISTS (
        SELECT 1 FROM disponibilites_soignant d
        WHERE d.soignant_id = v_s.id
          AND d.jour = (m.debut_le AT TIME ZONE 'Europe/Paris')::date
          AND (
            d.creneau = 'JOURNEE'
            OR (d.creneau = 'NUIT' AND (
                  EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') >= 20
                  OR EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') < 7))
            OR (d.creneau IN ('MATIN', 'APRES_MIDI') AND
                  EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') BETWEEN 7 AND 19)
          ));

    IF v_count > 0 THEN
      v_corps := v_count || ' mission' || CASE WHEN v_count > 1 THEN 's correspondent' ELSE ' correspond' END ||
                 ' à tes disponibilités des 2 prochaines semaines. Premier arrivé, premier servi.';

      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_s.id, 'MISSION_A_POURVOIR', '📅 Des missions collent à ton planning',
        v_corps, '/soignant/recherche-missions?vue=swipe', 'SOIGNANT');

      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s.id, 'type_evenement', 'MISSION_A_POURVOIR',
              'titre', '📅 Des missions collent à ton planning', 'corps', v_corps,
              'data', jsonb_build_object('lien', '/soignant/recherche-missions?vue=swipe')
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      v_notifies := v_notifies + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'notifies', v_notifies);
END;
$fn$;

-- Cron quotidien 06:30 UTC (08:30 Paris été). Garde pg_cron : les branches
-- preview n'ont pas l'extension.
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron absent — cron matching inversé non planifié (branche preview)';
    RETURN;
  END IF;
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'jolene_matching_inverse_dispos';
  PERFORM cron.schedule('jolene_matching_inverse_dispos', '30 6 * * *',
                        'SELECT public.fn_matching_inverse_dispos()');
END;
$do$;

-- ── 4. Vivier côté établissement ──────────────────────────────────────────────
-- « N soignants disponibles ce jour-là » au moment de créer une mission.
-- RGPD : compte + échantillon prénom/score uniquement, aucune coordonnée.
CREATE OR REPLACE FUNCTION public.fn_vivier_disponibilites(p_jour date, p_profession text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_etab RECORD;
  v_nb int;
  v_echantillon jsonb;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Réservé aux établissements');
  END IF;
  IF p_jour IS NULL OR p_jour < CURRENT_DATE OR p_jour > CURRENT_DATE + 90 THEN
    RETURN jsonb_build_object('nb', 0);
  END IF;

  SELECT adresse_lat, adresse_lng INTO v_etab FROM etablissements WHERE id = v_etab_id;

  WITH dispo AS (
    SELECT DISTINCT s.id, s.prenom, s.score_fiabilite
    FROM soignants s
    JOIN disponibilites_soignant d ON d.soignant_id = s.id AND d.jour = p_jour
    WHERE s.supprime_le IS NULL
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND COALESCE(s.tous_documents_valides, false)
      AND (p_profession IS NULL OR s.profession::text = p_profession)
      AND (v_etab_id IS NULL OR NOT fn_est_exclu(s.id, v_etab_id))
      AND (s.adresse_lat IS NULL OR v_etab.adresse_lat IS NULL
           OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_etab.adresse_lat, v_etab.adresse_lng)
              <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
  )
  SELECT COUNT(*),
         COALESCE(jsonb_agg(jsonb_build_object('prenom', prenom, 'score_fiabilite', score_fiabilite)
                            ORDER BY score_fiabilite DESC NULLS LAST) FILTER (WHERE rn <= 5), '[]'::jsonb)
    INTO v_nb, v_echantillon
    FROM (SELECT *, row_number() OVER (ORDER BY score_fiabilite DESC NULLS LAST) AS rn FROM dispo) t;

  RETURN jsonb_build_object('nb', COALESCE(v_nb, 0), 'echantillon', COALESCE(v_echantillon, '[]'::jsonb));
END;
$fn$;

-- ── 5. F2 : traçage de la republication (mission_source) ──────────────────────
ALTER TABLE public.missions DROP CONSTRAINT IF EXISTS missions_mission_source_check;
ALTER TABLE public.missions ADD CONSTRAINT missions_mission_source_check
  CHECK (mission_source = ANY (ARRAY['SWIPE'::text, 'CANDIDATURE'::text, 'REBOOK'::text,
                                     'PROPOSITION_DIRECTE'::text, 'REMPLACEMENT'::text,
                                     'REPUBLICATION'::text]));

-- Appelée par le front juste après fn_creer_mission quand le formulaire vient
-- d'un « Republier »/« Dupliquer » (?dupliquer=<id>). Volontairement étroite :
-- mission de MON établissement, fraîchement créée, source encore NULL.
CREATE OR REPLACE FUNCTION public.fn_marquer_source_mission(p_mission_id uuid, p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
BEGIN
  IF p_source <> 'REPUBLICATION' THEN
    RETURN jsonb_build_object('error', 'Source non autorisée');
  END IF;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Réservé aux établissements');
  END IF;

  UPDATE missions
     SET mission_source = p_source
   WHERE id = p_mission_id
     AND etablissement_id = v_etab_id
     AND mission_source IS NULL
     AND cree_le > NOW() - INTERVAL '10 minutes';

  RETURN jsonb_build_object('success', FOUND);
END;
$fn$;
