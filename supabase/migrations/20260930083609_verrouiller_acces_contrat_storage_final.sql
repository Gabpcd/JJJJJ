-- Définition LIVE relue le 30/09/2026. Même réponse, mêmes ACL ; la lecture
-- privilégiée suit désormais les gardes canoniques de la table contrats_mission.
CREATE OR REPLACE FUNCTION public.fn_contrat_storage_path(p_contrat_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fonction$
DECLARE
  v_uid uuid := auth.uid();
  v_cm RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;
  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT storage_path, hash_document, contenu_html_rendu_le, soignant_id, etablissement_id
  INTO v_cm FROM public.contrats_mission
  WHERE id = p_contrat_id
    AND (public.est_admin() IS TRUE
      OR soignant_id = v_uid
      OR (etablissement_id = public.mon_etablissement_id()
        AND public.fn_a_permission_etablissement('lecture_contrats', etablissement_id) IS TRUE));
  -- Un contrat absent et un contrat étranger sont indiscernables : aucune
  -- métadonnée ni preuve d'existence n'est révélée avant l'autorisation.
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;
  RETURN jsonb_build_object('success', true,
    'storage_path', v_cm.storage_path, 'hash_document', v_cm.hash_document,
    'rendu_le', v_cm.contenu_html_rendu_le);
END;
$fonction$;
REVOKE ALL ON FUNCTION public.fn_contrat_storage_path(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_contrat_storage_path(uuid) TO authenticated, service_role;

-- Seul corps revu dans cette migration. Catégorie MIXTE_TENANT_ADMIN conservée.
UPDATE private.security_definer_inventory
SET definition_md5 = '69ae0378704ad8110ada1cbbf0c0b6ef',
    justification = 'Lecture du contrat : compte actif obligatoire, soignant concerné ou tenant canonique avec lecture_contrats ; élévation administrateur valide conservée.',
    recense_le = now()
WHERE signature = 'fn_contrat_storage_path(uuid)';
