-- PR 9 Sprint 4.5 — Code numérique de secours pointage
--
-- Fallback si caméra indisponible ou QR perdu. Code 6 chiffres généré
-- par l'étab, donné verbalement au soignant. Hash bcrypt via pgcrypto
-- (jamais stocké en clair). Usage unique, expirable.

-- Activer pgcrypto si pas déjà fait
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. Table codes_secours_mission
-- ============================================================
CREATE TABLE IF NOT EXISTS public.codes_secours_mission (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  code_hash text NOT NULL,  -- bcrypt via crypt() + gen_salt('bf')
  type text NOT NULL CHECK (type IN ('ARRIVEE', 'DEPART', 'UNIVERSEL')) DEFAULT 'UNIVERSEL',
  genere_le timestamptz NOT NULL DEFAULT NOW(),
  expire_le timestamptz NOT NULL,
  utilise boolean NOT NULL DEFAULT false,
  utilise_le timestamptz,
  utilise_par uuid,
  cree_par uuid NOT NULL,
  cree_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_codes_secours_mission ON public.codes_secours_mission(mission_id, utilise);
CREATE INDEX IF NOT EXISTS idx_codes_secours_actifs ON public.codes_secours_mission(mission_id, type) WHERE utilise = false;

COMMENT ON TABLE public.codes_secours_mission IS
  'Codes 6 chiffres de secours pour pointage si caméra/QR indisponibles. '
  'Hash bcrypt via pgcrypto, jamais stocké en clair. Usage unique. '
  'Sprint 4.5 PR 9.';

-- RLS : SELECT admin + étab parties (lecture limitée car contient hash)
-- + soignant assigné peut valider via RPC sécurisée
ALTER TABLE public.codes_secours_mission ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_codes_secours_select ON public.codes_secours_mission;
CREATE POLICY pol_codes_secours_select ON public.codes_secours_mission
  FOR SELECT TO authenticated
  USING (
    est_admin() OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = codes_secours_mission.mission_id
        AND m.etablissement_id = mon_etablissement_id()
    )
  );
DROP POLICY IF EXISTS pol_codes_secours_deny_write ON public.codes_secours_mission;
CREATE POLICY pol_codes_secours_deny_write ON public.codes_secours_mission
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- 2. RPC fn_generer_code_secours_mission
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_generer_code_secours_mission(
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
  v_code text;
  v_code_hash text;
  v_expire_le timestamptz;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, fin_le, statut INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;
  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Invalider codes précédents non utilisés du même type
  UPDATE public.codes_secours_mission
  SET utilise = true, utilise_le = NOW()
  WHERE mission_id = p_mission_id AND type = p_type AND utilise = false;

  -- Générer 6 chiffres aléatoires (uniformément distribués 0-999999)
  v_code := lpad((floor(random() * 1000000))::text, 6, '0');
  v_code_hash := crypt(v_code, gen_salt('bf'));

  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.codes_secours_mission (mission_id, code_hash, type, expire_le, cree_par)
  VALUES (p_mission_id, v_code_hash, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_id;

  -- Audit (sans le code en clair !)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'code_secours_mission', v_id,
    jsonb_build_object('evenement', 'CODE_SECOURS_GENERE',
                        'mission_id', p_mission_id, 'type', p_type,
                        'expire_le', v_expire_le)
  );

  -- Retourne le code EN CLAIR (une seule fois — jamais re-affiché)
  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'code', v_code,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_generer_code_secours_mission(uuid, text) TO authenticated;

-- ============================================================
-- 3. RPC fn_valider_code_secours
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_valider_code_secours(
  p_mission_id uuid,
  p_code text,
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
  v_mission RECORD;
  v_code_row RECORD;
  v_presence RECORD;
  v_type_detecte text;
  v_now timestamptz := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_FORMAT_INVALIDE',
                                'error', 'Le code doit être 6 chiffres.');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas assigné à cette mission.');
  END IF;

  -- Trouver le code matching (non utilisé, non expiré)
  -- Boucle car bcrypt nécessite la comparaison hash par hash
  SELECT * INTO v_code_row FROM public.codes_secours_mission
  WHERE mission_id = p_mission_id
    AND utilise = false
    AND expire_le > v_now
    AND code_hash = crypt(p_code, code_hash)
  LIMIT 1;

  IF v_code_row IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INVALIDE',
                                'error', 'Code incorrect, déjà utilisé ou expiré.');
  END IF;

  -- Déterminer type pointage selon presences
  SELECT * INTO v_presence FROM public.presences
  WHERE mission_id = v_mission.id AND soignant_id = v_uid LIMIT 1;

  IF v_code_row.type = 'ARRIVEE' THEN
    v_type_detecte := 'ARRIVEE';
  ELSIF v_code_row.type = 'DEPART' THEN
    v_type_detecte := 'DEPART';
  ELSE
    v_type_detecte := CASE WHEN v_presence IS NULL THEN 'ARRIVEE' ELSE 'DEPART' END;
  END IF;

  -- Vérifs identiques scan QR
  IF v_type_detecte = 'ARRIVEE' AND v_presence IS NOT NULL AND v_presence.pointage_arrivee_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_POINTE');
  END IF;
  IF v_type_detecte = 'DEPART' THEN
    IF v_presence IS NULL OR v_presence.pointage_arrivee_le IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_SANS_ARRIVEE');
    END IF;
    IF v_presence.pointage_depart_le IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_DEJA_POINTE');
    END IF;
    IF v_now < v_presence.pointage_arrivee_le + INTERVAL '30 minutes' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_TROP_RAPIDE');
    END IF;
  END IF;

  -- Marquer code utilisé
  UPDATE public.codes_secours_mission SET
    utilise = true, utilise_le = v_now, utilise_par = v_uid
  WHERE id = v_code_row.id;

  -- INSERT/UPDATE presence
  IF v_type_detecte = 'ARRIVEE' THEN
    IF v_presence IS NULL THEN
      INSERT INTO public.presences (
        mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        arrivee_id_terminal, methode_pointage_arrivee
      ) VALUES (v_mission.id, v_uid, v_now, p_lat, p_lng, p_precision,
        p_terminal_id, 'CODE_SECOURS');
    ELSE
      UPDATE public.presences SET
        pointage_arrivee_le = v_now,
        arrivee_lat = p_lat, arrivee_lng = p_lng,
        arrivee_precision_gps_m = p_precision,
        arrivee_id_terminal = p_terminal_id,
        methode_pointage_arrivee = 'CODE_SECOURS'
      WHERE id = v_presence.id;
    END IF;
    UPDATE public.missions SET statut = 'EN_COURS', modifie_le = NOW()
    WHERE id = v_mission.id AND statut = 'ASSIGNEE';
  ELSE
    UPDATE public.presences SET
      pointage_depart_le = v_now,
      depart_lat = p_lat, depart_lng = p_lng,
      depart_precision_gps_m = p_precision,
      depart_id_terminal = p_terminal_id,
      methode_pointage_depart = 'CODE_SECOURS'
    WHERE id = v_presence.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'methode_detectee', v_type_detecte,
    'mission_id', v_mission.id,
    'horodatage', v_now
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_valider_code_secours(uuid, text, numeric, numeric, numeric, text) TO authenticated;

-- ============================================================
-- 4. Audit
-- ============================================================
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT45_PR9_CODE_SECOURS_INSTALLED',
    'pr', 'PR 9 Sprint 4.5',
    'rpcs', ARRAY['fn_generer_code_secours_mission', 'fn_valider_code_secours'],
    'note', 'Code 6 chiffres bcrypt usage unique fallback caméra. methode_pointage_*=CODE_SECOURS.'
  )
);
