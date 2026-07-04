-- PR 4 Sprint 4.5 — QR code mission backend
--
-- Mécanisme primaire anti-triche : QR code unique par mission, affiché
-- par l'établissement, scanné par le soignant. Token cryptographique
-- (UUID v4 + suffix 16 chars random) lié à la mission, expirable.
--
-- Création table qr_codes_mission + RPCs génération/validation +
-- colonnes presences pour traçabilité méthode (GPS/QR/CODE_SECOURS/
-- MANUEL_ADMIN).

-- ============================================================
-- 1. Table qr_codes_mission
-- ============================================================
CREATE TABLE IF NOT EXISTS public.qr_codes_mission (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  type text NOT NULL CHECK (type IN ('ARRIVEE', 'DEPART', 'UNIVERSEL')) DEFAULT 'UNIVERSEL',
  genere_le timestamptz NOT NULL DEFAULT NOW(),
  expire_le timestamptz NOT NULL,
  nb_scans int NOT NULL DEFAULT 0,
  dernier_scan_le timestamptz,
  actif boolean NOT NULL DEFAULT true,
  cree_par uuid NOT NULL,
  cree_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_qr_codes_mission ON public.qr_codes_mission(mission_id);
CREATE INDEX IF NOT EXISTS idx_qr_codes_token ON public.qr_codes_mission(token) WHERE actif = true;
CREATE INDEX IF NOT EXISTS idx_qr_codes_actifs ON public.qr_codes_mission(mission_id, type) WHERE actif = true;

COMMENT ON TABLE public.qr_codes_mission IS
  'QR codes uniques par mission pour pointage anti-triche. Token = UUID v4 '
  '+ suffix 16 chars random cryptographique. Sprint 4.5 PR 4.';

-- RLS : lisible par admin Jolene + étab parties + soignant assigné
ALTER TABLE public.qr_codes_mission ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_qr_codes_select ON public.qr_codes_mission;
CREATE POLICY pol_qr_codes_select ON public.qr_codes_mission
  FOR SELECT TO authenticated
  USING (
    est_admin() OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = qr_codes_mission.mission_id
        AND (m.soignant_assigne_id = auth.uid()
             OR m.etablissement_id = mon_etablissement_id())
    )
  );
DROP POLICY IF EXISTS pol_qr_codes_deny_write ON public.qr_codes_mission;
CREATE POLICY pol_qr_codes_deny_write ON public.qr_codes_mission
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- 2. Colonnes presences pour méthode pointage
-- ============================================================
-- Note : methode_pointage_arrivee / _depart existent déjà (PR 3 Sprint 3).
-- On étend la liste des valeurs autorisées + on ajoute les tokens QR.

ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS qr_token_arrivee text,
  ADD COLUMN IF NOT EXISTS qr_token_depart text;

COMMENT ON COLUMN public.presences.qr_token_arrivee IS
  'Token QR utilisé pour valider l''arrivée (référence soft vers '
  'qr_codes_mission.token, pas FK car table peut être purgée).';

-- ============================================================
-- 3. RPC fn_generer_qr_mission(mission_id, type)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_generer_qr_mission(
  p_mission_id uuid,
  p_type text DEFAULT 'UNIVERSEL'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_token text;
  v_expire_le timestamptz;
  v_qr_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, debut_le, fin_le, statut INTO v_mission
  FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;

  -- Auth : étab admin de la mission ou admin Jolene
  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF v_mission.statut IN ('ANNULEE_LITIGE', 'ANNULEE_ETAB', 'TERMINEE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INACTIVE');
  END IF;

  -- Désactiver les QR actifs précédents du même type
  UPDATE public.qr_codes_mission SET actif = false
  WHERE mission_id = p_mission_id AND type = p_type AND actif = true;

  -- Token = UUID v4 + suffix 16 chars random cryptographique
  v_token := gen_random_uuid()::text || '_' ||
             encode(gen_random_bytes(8), 'hex');

  -- Expiration : min(date_fin + 2h, NOW() + 7j)
  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.qr_codes_mission (mission_id, token, type, expire_le, cree_par)
  VALUES (p_mission_id, v_token, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_qr_id;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'qr_code_mission', v_qr_id,
    jsonb_build_object('evenement', 'QR_GENERE',
                        'mission_id', p_mission_id,
                        'type', p_type, 'expire_le', v_expire_le)
  );

  RETURN jsonb_build_object(
    'success', true,
    'qr_id', v_qr_id,
    'token', v_token,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_generer_qr_mission(uuid, text) TO authenticated;

-- ============================================================
-- 4. RPC fn_regenerer_qr_mission(mission_id, type)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_regenerer_qr_mission(
  p_mission_id uuid,
  p_type text DEFAULT 'UNIVERSEL'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Wrapper qui invalide l'ancien et génère un nouveau (idem à
  -- fn_generer_qr_mission grâce au UPDATE ... actif=false interne)
  RETURN public.fn_generer_qr_mission(p_mission_id, p_type);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_regenerer_qr_mission(uuid, text) TO authenticated;

-- ============================================================
-- 5. RPC fn_valider_scan_qr(token, [coords GPS optionnels])
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_valider_scan_qr(
  p_token text,
  p_lat numeric DEFAULT NULL,
  p_lng numeric DEFAULT NULL,
  p_precision numeric DEFAULT NULL,
  p_terminal_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_qr RECORD;
  v_mission RECORD;
  v_etab RECORD;
  v_presence RECORD;
  v_type_detecte text;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_now timestamptz := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_qr FROM public.qr_codes_mission WHERE token = p_token AND actif = true;
  IF v_qr IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_INVALIDE',
                                'error', 'QR non valide ou déjà invalidé.');
  END IF;

  IF v_qr.expire_le < v_now THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_EXPIRE',
                                'error', 'Ce QR a expiré. Demandez à l''établissement de régénérer.');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_qr.mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_MISSION_AUTRE',
                                'error', 'Ce QR ne correspond pas à votre mission active.');
  END IF;

  -- Cohérence temporelle
  IF v_now < v_mission.debut_le - INTERVAL '1 hour' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HEURE_TROP_TOT',
                                'error', 'Trop tôt pour pointer. Mission démarre à ' ||
                                  to_char(v_mission.debut_le, 'DD/MM HH24:MI') || '.');
  END IF;
  IF v_now > COALESCE(v_mission.fin_le, v_now + INTERVAL '1 day') + INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HEURE_TROP_TARD',
                                'error', 'Trop tard pour pointer. Mission terminée depuis plus de 2 heures.');
  END IF;

  -- Détecter le type de pointage selon presences existantes
  SELECT * INTO v_presence FROM public.presences
  WHERE mission_id = v_mission.id AND soignant_id = v_uid LIMIT 1;

  IF v_qr.type = 'ARRIVEE' THEN
    v_type_detecte := 'ARRIVEE';
  ELSIF v_qr.type = 'DEPART' THEN
    v_type_detecte := 'DEPART';
  ELSE
    -- UNIVERSEL : pas de presence → ARRIVEE, sinon DEPART
    v_type_detecte := CASE WHEN v_presence IS NULL THEN 'ARRIVEE' ELSE 'DEPART' END;
  END IF;

  -- Vérif double pointage / cohérence départ > arrivée + 30 min
  IF v_type_detecte = 'ARRIVEE' AND v_presence IS NOT NULL AND v_presence.pointage_arrivee_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_POINTE',
                                'error', 'Vous avez déjà pointé votre arrivée.');
  END IF;
  IF v_type_detecte = 'DEPART' THEN
    IF v_presence IS NULL OR v_presence.pointage_arrivee_le IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_SANS_ARRIVEE',
                                  'error', 'Vous devez d''abord pointer votre arrivée.');
    END IF;
    IF v_presence.pointage_depart_le IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_DEJA_POINTE',
                                  'error', 'Vous avez déjà pointé votre départ.');
    END IF;
    IF v_now < v_presence.pointage_arrivee_le + INTERVAL '30 minutes' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_TROP_RAPIDE',
                                  'error', 'Vous ne pouvez pointer votre départ moins de 30 minutes après l''arrivée.');
    END IF;
  END IF;

  -- Double sécurité GPS : calcul distance si coords fournies (non bloquant)
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 100) AS tolerance_m
    INTO v_etab FROM public.etablissements WHERE id = v_mission.etablissement_id;
    IF v_etab.adresse_lat IS NOT NULL AND v_etab.adresse_lng IS NOT NULL THEN
      v_distance_m := public.fn_haversine_distance_m(
        p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= GREATEST(v_etab.tolerance_m, 1000);
      -- Si distance > 1 km : alerte admin mais pas bloquant (QR = source de vérité)
      IF v_distance_m > 1000 THEN
        INSERT INTO public.journaux_audit (
          acteur_id, type_acteur, action, type_ressource, id_ressource, details
        ) VALUES (
          v_uid, 'SOIGNANT', 'SYSTEM', 'presence', v_mission.id,
          jsonb_build_object(
            'evenement', 'QR_SCAN_GPS_ELOIGNE',
            'niveau', 'WARNING',
            'mission_id', v_mission.id,
            'distance_m', v_distance_m,
            'qr_id', v_qr.id
          )
        );
      END IF;
    END IF;
  END IF;

  -- Insert ou Update presence
  IF v_type_detecte = 'ARRIVEE' THEN
    IF v_presence IS NULL THEN
      INSERT INTO public.presences (
        mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        arrivee_id_terminal,
        methode_pointage_arrivee, qr_token_arrivee,
        distance_etablissement_m, perimetre_gps_valide
      ) VALUES (
        v_mission.id, v_uid, v_now,
        p_lat, p_lng, p_precision,
        p_terminal_id,
        'QR', p_token,
        v_distance_m, v_perimetre_ok
      );
    ELSE
      UPDATE public.presences SET
        pointage_arrivee_le = v_now,
        arrivee_lat = p_lat, arrivee_lng = p_lng,
        arrivee_precision_gps_m = p_precision,
        arrivee_id_terminal = p_terminal_id,
        methode_pointage_arrivee = 'QR',
        qr_token_arrivee = p_token,
        distance_etablissement_m = COALESCE(v_distance_m, distance_etablissement_m),
        perimetre_gps_valide = COALESCE(v_perimetre_ok, perimetre_gps_valide)
      WHERE id = v_presence.id;
    END IF;
    UPDATE public.missions SET statut = 'EN_COURS', modifie_le = NOW()
    WHERE id = v_mission.id AND statut = 'ASSIGNEE';
  ELSE  -- DEPART
    UPDATE public.presences SET
      pointage_depart_le = v_now,
      depart_lat = p_lat, depart_lng = p_lng,
      depart_precision_gps_m = p_precision,
      depart_id_terminal = p_terminal_id,
      methode_pointage_depart = 'QR',
      qr_token_depart = p_token,
      distance_etablissement_m = COALESCE(distance_etablissement_m, v_distance_m),
      perimetre_gps_valide = COALESCE(perimetre_gps_valide, v_perimetre_ok)
    WHERE id = v_presence.id;
  END IF;

  -- Incrémenter compteur QR
  UPDATE public.qr_codes_mission SET
    nb_scans = nb_scans + 1, dernier_scan_le = v_now
  WHERE id = v_qr.id;

  RETURN jsonb_build_object(
    'success', true,
    'methode_detectee', v_type_detecte,
    'mission_id', v_mission.id,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'horodatage', v_now
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_valider_scan_qr(text, numeric, numeric, numeric, text) TO authenticated;

-- ============================================================
-- 6. Trigger auto-génération QR au démarrage mission (SIGNE_COMPLET)
-- ============================================================
CREATE OR REPLACE FUNCTION public.dec_auto_generer_qr_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_existing_qr int;
BEGIN
  -- Trigger sur INSERT presences ou UPDATE contrats SIGNE_COMPLET
  IF TG_TABLE_NAME = 'contrats_mission' THEN
    IF NEW.statut != 'SIGNE_COMPLET' OR (OLD.statut = 'SIGNE_COMPLET') THEN
      RETURN NEW;
    END IF;
    -- Mission n'a pas encore de QR UNIVERSEL actif ?
    SELECT COUNT(*) INTO v_existing_qr FROM public.qr_codes_mission
    WHERE mission_id = NEW.mission_id AND type = 'UNIVERSEL' AND actif = true;
    IF v_existing_qr = 0 THEN
      -- Génère via insertion directe (auth.uid NULL en trigger système)
      INSERT INTO public.qr_codes_mission (mission_id, token, type, expire_le, cree_par)
      SELECT
        NEW.mission_id,
        gen_random_uuid()::text || '_' || encode(gen_random_bytes(8), 'hex'),
        'UNIVERSEL',
        LEAST(COALESCE(m.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
              NOW() + INTERVAL '7 days'),
        '00000000-0000-0000-0000-000000000000'::uuid
      FROM public.missions m WHERE m.id = NEW.mission_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_auto_generer_qr_mission ON public.contrats_mission;
CREATE TRIGGER trg_dec_auto_generer_qr_mission
  AFTER UPDATE OF statut ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_auto_generer_qr_mission();

-- ============================================================
-- 7. Audit
-- ============================================================
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT45_PR4_QR_CODE_INSTALLED',
    'pr', 'PR 4 Sprint 4.5',
    'tables', ARRAY['qr_codes_mission'],
    'colonnes', ARRAY['presences.qr_token_arrivee', 'presences.qr_token_depart'],
    'rpcs', ARRAY['fn_generer_qr_mission', 'fn_regenerer_qr_mission', 'fn_valider_scan_qr'],
    'triggers', ARRAY['trg_dec_auto_generer_qr_mission'],
    'note', 'Mécanisme primaire anti-triche. Token UUID + suffix 16 chars random.'
  )
);
