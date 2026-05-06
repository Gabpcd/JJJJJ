-- Itération 1 — Fix B.1 : RPC upload contrat travail mission SALARIE
-- Aucune RPC n'inserait dans contrats_travail_missions, table jamais peuplée → cron rappel inutilisable.

CREATE OR REPLACE FUNCTION public.fn_uploader_contrat_travail_mission(
  p_mission_id UUID,
  p_pdf_s3_key TEXT,
  p_nom_fichier TEXT DEFAULT NULL,
  p_taille_octets INT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_mission RECORD;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut, type_contrat_applique, type_paiement_soignant
  INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND v_mission.etablissement_id <> v_etab_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas l''établissement de cette mission');
  END IF;

  IF NOT (COALESCE(v_mission.type_contrat_applique::text, '') = 'SALARIE'
          OR COALESCE(v_mission.type_paiement_soignant::text, '') = 'BULLETIN_PAIE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat travail réservé aux missions SALARIE');
  END IF;

  IF p_pdf_s3_key IS NULL OR LENGTH(TRIM(p_pdf_s3_key)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'pdf_s3_key requis');
  END IF;

  INSERT INTO contrats_travail_missions (
    mission_id, etablissement_id, soignant_id,
    pdf_s3_key, nom_fichier, taille_octets, uploaded_by
  ) VALUES (
    p_mission_id, v_mission.etablissement_id, v_mission.soignant_assigne_id,
    p_pdf_s3_key, NULLIF(TRIM(p_nom_fichier), ''), p_taille_octets, v_uid
  )
  ON CONFLICT (mission_id) DO UPDATE SET
    pdf_s3_key = EXCLUDED.pdf_s3_key,
    nom_fichier = EXCLUDED.nom_fichier,
    taille_octets = EXCLUDED.taille_octets,
    uploaded_by = EXCLUDED.uploaded_by,
    uploaded_at = NOW()
  RETURNING id INTO v_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE', p_type_ressource := 'mission', p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('contrat_travail_id', v_id, 'type', 'SALARIE')
  );

  RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

ALTER TABLE public.contrats_travail_missions DROP CONSTRAINT IF EXISTS contrats_travail_missions_mission_id_key;
ALTER TABLE public.contrats_travail_missions ADD CONSTRAINT contrats_travail_missions_mission_id_key UNIQUE (mission_id);

GRANT EXECUTE ON FUNCTION public.fn_uploader_contrat_travail_mission(UUID, TEXT, TEXT, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';
