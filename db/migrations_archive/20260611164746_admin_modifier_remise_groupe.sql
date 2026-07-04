-- Remise groupe éditable depuis AdminGroupes (était en lecture seule —
-- la négociation d'une remise nécessitait un UPDATE SQL manuel).
-- NB : la version initiale utilisait l'action d'audit 'COMMISSION_AJUSTEE'
-- (hors CHECK) — corrigée par 20260611165531.
CREATE OR REPLACE FUNCTION public.fn_admin_modifier_remise_groupe(
  p_groupe_id uuid,
  p_remise numeric,
  p_raison text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ancienne numeric;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_remise IS NULL OR p_remise < 0 OR p_remise > 100 THEN
    RETURN jsonb_build_object('error', 'La remise doit être entre 0 et 100 %');
  END IF;

  SELECT remise_groupe_pourcent INTO v_ancienne FROM groupes_sante WHERE id = p_groupe_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Groupe introuvable');
  END IF;

  UPDATE groupes_sante SET remise_groupe_pourcent = p_remise WHERE id = p_groupe_id;

  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (auth.uid(), 'ADMIN', 'TAUX_COMMISSION_MODIFIE', 'groupe', p_groupe_id,
    jsonb_build_object('champ', 'remise_groupe_pourcent', 'ancienne', v_ancienne, 'nouvelle', p_remise, 'raison', p_raison));

  RETURN jsonb_build_object('success', true, 'remise', p_remise);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_admin_modifier_remise_groupe(uuid, numeric, text) TO authenticated;
