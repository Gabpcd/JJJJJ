-- AUDIT FONCTIONNEL — FIX BUG CRITIQUE #3
-- Table notations_missions a colonnes signale, masque, masque_par, masque_le mais
-- aucune RPC ne permet de signaler ou masquer une notation. Modération impossible.
--
-- Solution : créer 2 RPCs :
--  fn_signaler_notation(p_notation_id, p_motif?) — appelable par la cible (note_id)
--  fn_admin_masquer_notation(p_notation_id, p_raison) — appelable par admin uniquement

CREATE OR REPLACE FUNCTION public.fn_signaler_notation(p_notation_id UUID, p_motif TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_notation RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_notation FROM notations_missions WHERE id = p_notation_id;
  IF v_notation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation introuvable');
  END IF;

  -- Seule la cible (note_id) peut signaler — soit soignant, soit étab via mon_etablissement_id()
  IF v_notation.note_id <> v_uid AND v_notation.note_id <> COALESCE(v_etab_id, '00000000-0000-0000-0000-000000000000'::uuid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez signaler que les notations vous concernant');
  END IF;

  IF v_notation.signale = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation déjà signalée');
  END IF;

  UPDATE notations_missions SET signale = true, mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_SIGNALE',
    p_type_ressource := 'notation',
    p_id_ressource := p_notation_id,
    p_details := jsonb_build_object('motif', p_motif, 'mission_id', v_notation.mission_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_signaler_notation(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_masquer_notation(p_notation_id UUID, p_raison TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_notation RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seul l''administrateur peut masquer une notation');
  END IF;

  IF p_raison IS NULL OR LENGTH(TRIM(p_raison)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison requise (min 10 caractères)');
  END IF;

  SELECT * INTO v_notation FROM notations_missions WHERE id = p_notation_id;
  IF v_notation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation introuvable');
  END IF;

  UPDATE notations_missions SET
    masque = true, masque_par = v_uid, masque_le = NOW(), mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'NOTATION_MASQUEE',
    p_type_ressource := 'notation',
    p_id_ressource := p_notation_id,
    p_details := jsonb_build_object('raison', p_raison, 'mission_id', v_notation.mission_id)
  );

  -- Recalculer le score de la cible (notation masquée sort du calcul)
  IF v_notation.sens = 'ETAB_VERS_SOIGNANT' THEN
    PERFORM public.fn_calculer_score_fiabilite_v2(v_notation.note_id, 'notation_masquee');
  ELSIF v_notation.sens = 'SOIGNANT_VERS_ETAB' THEN
    PERFORM public.fn_calculer_score_etablissement(v_notation.note_id);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_masquer_notation(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
