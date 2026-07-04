-- Sprint 17-A PR 2 — RPCs parrainage soignant prime cash
--
-- Remplace fn_appliquer_parrainage : ajoute log anti-fraude (IP/device)
-- Remplace fn_mes_filleuls : enrichi avec commission_cumulee_filleul + statuts
-- fn_generer_code_parrainage inchangé (trigger auto à l'inscription, déjà OK)

-- 1) fn_appliquer_parrainage — enrichi anti-fraude IP/device
CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage(p_code TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_parrain RECORD;
  v_filleul_id UUID := auth.uid();
  v_nb_filleuls_valides INT;
  v_parrainage_id UUID;
  v_ip TEXT;
  v_user_agent TEXT;
BEGIN
  IF v_filleul_id IS NULL THEN
    RETURN '{"error":"Non authentifié"}'::JSONB;
  END IF;

  SELECT * INTO v_parrain FROM soignants
  WHERE code_parrainage = UPPER(TRIM(p_code)) AND supprime_le IS NULL;

  IF v_parrain IS NULL THEN
    RETURN '{"error":"Code de parrainage invalide"}'::JSONB;
  END IF;

  IF v_parrain.id = v_filleul_id THEN
    RETURN '{"error":"Vous ne pouvez pas vous parrainer vous-même"}'::JSONB;
  END IF;

  SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages
  WHERE parrain_id = v_parrain.id AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');
  IF v_nb_filleuls_valides >= 20 THEN
    RETURN '{"error":"Le parrain a atteint la limite de 20 filleuls validés"}'::JSONB;
  END IF;

  IF EXISTS (SELECT 1 FROM parrainages WHERE filleul_id = v_filleul_id) THEN
    RETURN '{"error":"Vous avez déjà appliqué un code de parrainage"}'::JSONB;
  END IF;

  INSERT INTO parrainages (parrain_id, filleul_id, code_parrainage, statut)
  VALUES (v_parrain.id, v_filleul_id, UPPER(TRIM(p_code)), 'EN_ATTENTE')
  RETURNING id INTO v_parrainage_id;

  UPDATE soignants SET parraine_par = v_parrain.id
  WHERE id = v_filleul_id AND parraine_par IS NULL;

  -- Anti-fraude : log IP et user-agent (signaux, pas blocage dur)
  BEGIN
    v_ip := COALESCE(
      current_setting('request.headers', true)::json->>'x-forwarded-for',
      current_setting('request.headers', true)::json->>'x-real-ip',
      'unknown'
    );
    v_user_agent := COALESCE(
      current_setting('request.headers', true)::json->>'user-agent',
      'unknown'
    );
  EXCEPTION WHEN OTHERS THEN
    v_ip := 'unknown';
    v_user_agent := 'unknown';
  END;

  -- Vérifier si le parrain a la même IP (signal anti-fraude)
  IF v_ip <> 'unknown' THEN
    DECLARE
      v_parrain_last_ip TEXT;
    BEGIN
      SELECT (details->>'ip')::text INTO v_parrain_last_ip
      FROM journaux_audit
      WHERE acteur_id = v_parrain.id AND action = 'CONNEXION'
      ORDER BY cree_le DESC LIMIT 1;

      IF v_parrain_last_ip IS NOT NULL AND v_parrain_last_ip = v_ip THEN
        INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail)
        VALUES (v_parrainage_id, 'MEME_IP',
          jsonb_build_object('ip', v_ip, 'parrain_id', v_parrain.id, 'filleul_id', v_filleul_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL; -- best-effort
    END;
  END IF;

  -- Log device info
  INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail)
  VALUES (v_parrainage_id, 'MEME_DEVICE',
    jsonb_build_object(
      'ip_filleul', v_ip,
      'user_agent_filleul', v_user_agent,
      'filleul_id', v_filleul_id,
      'parrain_id', v_parrain.id
    ));

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Code accepté ! Votre prime de 50€ sera versée après votre 1ère mission terminée et 100€ de commission encaissée par Jolene.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_appliquer_parrainage(TEXT) TO authenticated;

-- 2) fn_mes_filleuls — enrichi avec suivi commission + prime
CREATE OR REPLACE FUNCTION public.fn_mes_filleuls()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::JSONB;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'filleul_id', p.filleul_id,
    'prenom', s.prenom,
    'statut', p.statut,
    'cree_le', p.cree_le,
    'valide_le', p.valide_le,
    'filleul_active_le', p.filleul_active_le,
    'commission_cumulee_filleul', p.commission_cumulee_filleul,
    'prime_versee_le', p.prime_versee_le,
    'premiere_mission_le', s.premiere_mission_le,
    'bonus_heures_parrain', p.bonus_heures_parrain
  ) ORDER BY p.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM parrainages p
  JOIN soignants s ON s.id = p.filleul_id
  WHERE p.parrain_id = v_uid;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_filleuls() TO authenticated;

-- 3) fn_obtenir_mes_parrainages — vue complète pour la page parrainage
CREATE OR REPLACE FUNCTION public.fn_obtenir_mes_parrainages()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_filleuls JSONB;
  v_parrain_info JSONB;
  v_total_gains NUMERIC;
  v_nb_primes_versees INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  -- Filleuls en tant que parrain
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'filleul_id', p.filleul_id,
    'prenom', s.prenom,
    'statut', p.statut,
    'cree_le', p.cree_le,
    'filleul_active_le', p.filleul_active_le,
    'commission_cumulee_filleul', COALESCE(p.commission_cumulee_filleul, 0),
    'seuil_atteint', COALESCE(p.commission_cumulee_filleul, 0) >= 100,
    'prime_versee_le', p.prime_versee_le,
    'premiere_mission_le', s.premiere_mission_le,
    'bonus_heures', COALESCE(p.bonus_heures_parrain, 0)
  ) ORDER BY p.cree_le DESC), '[]'::jsonb)
  INTO v_filleuls
  FROM parrainages p
  JOIN soignants s ON s.id = p.filleul_id
  WHERE p.parrain_id = v_uid;

  -- Totaux
  SELECT COUNT(*), COALESCE(SUM(50), 0) INTO v_nb_primes_versees, v_total_gains
  FROM parrainages
  WHERE parrain_id = v_uid AND statut = 'PRIME_VERSEE';

  -- Info en tant que filleul
  SELECT jsonb_build_object(
    'parrain_prenom', sp.prenom,
    'statut', p.statut,
    'prime_versee_le', p.prime_versee_le
  ) INTO v_parrain_info
  FROM parrainages p
  JOIN soignants sp ON sp.id = p.parrain_id
  WHERE p.filleul_id = v_uid
  LIMIT 1;

  RETURN jsonb_build_object(
    'filleuls', v_filleuls,
    'total_gains_eur', v_total_gains,
    'nb_primes_versees', v_nb_primes_versees,
    'mon_parrain', COALESCE(v_parrain_info, 'null'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_mes_parrainages() TO authenticated;

NOTIFY pgrst, 'reload schema';
