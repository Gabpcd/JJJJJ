
-- RPC: Exclude a user (with audit)
CREATE OR REPLACE FUNCTION public.fn_exclure_utilisateur(
  p_exclu_id uuid,
  p_type text,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_type_acteur text;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_type NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Type invalide');
  END IF;

  -- Prevent self-exclusion
  IF v_caller_id = p_exclu_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Impossible de s''exclure soi-même');
  END IF;

  -- Check duplicate
  IF EXISTS (SELECT 1 FROM exclusions WHERE exclu_par = v_caller_id AND exclu_id = p_exclu_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Exclusion déjà existante');
  END IF;

  INSERT INTO exclusions (exclu_id, exclu_par, type_exclu_par, motif)
  VALUES (p_exclu_id, v_caller_id, p_type, p_motif);

  -- Determine actor type
  IF p_type = 'ETABLISSEMENT' THEN
    v_type_acteur := 'ADMIN_ETABLISSEMENT';
  ELSE
    v_type_acteur := 'SOIGNANT';
  END IF;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    v_caller_id, v_type_acteur, 'EXCLUSION_CREEE',
    'exclusion', p_exclu_id, NULL,
    jsonb_build_object('type_exclu_par', p_type, 'motif', COALESCE(p_motif, '')),
    NULL, 'rpc'
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- RPC: Remove an exclusion (with audit)
CREATE OR REPLACE FUNCTION public.fn_retirer_exclusion(p_exclu_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_exclusion_id uuid;
  v_type text;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT id, type_exclu_par INTO v_exclusion_id, v_type
  FROM exclusions
  WHERE exclu_par = v_caller_id AND exclu_id = p_exclu_id
  LIMIT 1;

  IF v_exclusion_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Exclusion introuvable');
  END IF;

  DELETE FROM exclusions WHERE id = v_exclusion_id;

  PERFORM fn_ecrire_audit_safe(
    v_caller_id,
    CASE WHEN v_type = 'ETABLISSEMENT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    'EXCLUSION_SUPPRIMEE',
    'exclusion', p_exclu_id, NULL,
    jsonb_build_object('exclusion_id', v_exclusion_id),
    NULL, 'rpc'
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_exclure_utilisateur(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_retirer_exclusion(uuid) TO authenticated;
