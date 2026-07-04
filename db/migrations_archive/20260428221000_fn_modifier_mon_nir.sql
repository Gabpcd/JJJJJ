-- RPC pour permettre au soignant de renseigner son numéro de sécurité
-- sociale (NIR) depuis son profil. Mention obligatoire bulletin de paie
-- art. R3243-1 CTW.
--
-- Validation : 13 chiffres (sans clé) ou 15 (avec clé). Les caractères
-- non numériques (espaces, slashs) sont silencieusement supprimés avant
-- stockage. Une chaîne vide ou null efface le NIR (le soignant peut
-- vouloir le retirer).

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_nir(p_nir text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_normalized text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  v_normalized := NULLIF(regexp_replace(COALESCE(p_nir, ''), '[^0-9]', '', 'g'), '');

  IF v_normalized IS NOT NULL AND length(v_normalized) NOT IN (13, 15) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'NIR invalide : 13 chiffres (sans clé) ou 15 chiffres (avec clé) requis');
  END IF;

  UPDATE soignants SET numero_securite_sociale = v_normalized WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'NIR_MODIFIE',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('nir_renseigne', v_normalized IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'nir_renseigne', v_normalized IS NOT NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_modifier_mon_nir(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
