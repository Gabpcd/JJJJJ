-- ============================================================================
-- Sprint 5.7 PR 8 — RPCs admin templates contrats (P0-10)
-- ============================================================================
-- 14 templates Sprint 2 gérables via UI admin (liste, édition, activation).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_admin_lister_templates_contrats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_templates jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'nom', t.nom,
    'type_contrat', t.type_contrat,
    'version', t.version,
    'est_actif', t.est_actif,
    'variables', t.variables,
    'contenu_taille', length(t.contenu_html),
    'cree_le', t.cree_le,
    'modifie_le', t.modifie_le
  ) ORDER BY t.type_contrat, t.version DESC, t.nom), '[]'::jsonb)
  INTO v_templates
  FROM public.templates_contrat t;

  RETURN jsonb_build_object('success', true, 'templates', v_templates);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_templates_contrats() TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_detail_template_contrat(p_template_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_template jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT jsonb_build_object(
    'id', t.id,
    'nom', t.nom,
    'type_contrat', t.type_contrat,
    'version', t.version,
    'est_actif', t.est_actif,
    'variables', t.variables,
    'contenu_html', t.contenu_html,
    'cree_le', t.cree_le,
    'modifie_le', t.modifie_le
  )
  INTO v_template
  FROM public.templates_contrat t
  WHERE t.id = p_template_id;

  IF v_template IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEMPLATE_INTROUVABLE');
  END IF;

  RETURN jsonb_build_object('success', true, 'template', v_template);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_detail_template_contrat(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_template_contrat(
  p_template_id uuid,
  p_contenu_html text,
  p_nom text DEFAULT NULL,
  p_variables jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_ancien_version int;
  v_nouvelle_version int;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF p_contenu_html IS NULL OR length(p_contenu_html) < 50 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTENU_TROP_COURT',
                                'error', 'Le contenu HTML doit faire au moins 50 caractères');
  END IF;

  SELECT version INTO v_ancien_version FROM public.templates_contrat WHERE id = p_template_id;
  IF v_ancien_version IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEMPLATE_INTROUVABLE');
  END IF;

  v_nouvelle_version := v_ancien_version + 1;

  UPDATE public.templates_contrat
  SET contenu_html = p_contenu_html,
      nom = COALESCE(p_nom, nom),
      variables = COALESCE(p_variables, variables),
      version = v_nouvelle_version,
      modifie_le = now()
  WHERE id = p_template_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'template_contrat', p_template_id,
    jsonb_build_object(
      'evenement', 'TEMPLATE_CONTRAT_MODIFIE',
      'ancienne_version', v_ancien_version,
      'nouvelle_version', v_nouvelle_version,
      'taille_contenu', length(p_contenu_html)
    )
  );

  RETURN jsonb_build_object('success', true, 'version', v_nouvelle_version);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_modifier_template_contrat(uuid, text, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_toggle_template_contrat(p_template_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_ancien_statut boolean;
  v_nouveau_statut boolean;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT est_actif INTO v_ancien_statut FROM public.templates_contrat WHERE id = p_template_id;
  IF v_ancien_statut IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEMPLATE_INTROUVABLE');
  END IF;

  v_nouveau_statut := NOT v_ancien_statut;

  UPDATE public.templates_contrat
  SET est_actif = v_nouveau_statut, modifie_le = now()
  WHERE id = p_template_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'template_contrat', p_template_id,
    jsonb_build_object(
      'evenement', CASE WHEN v_nouveau_statut THEN 'TEMPLATE_CONTRAT_ACTIVE' ELSE 'TEMPLATE_CONTRAT_DESACTIVE' END,
      'ancien_statut', v_ancien_statut,
      'nouveau_statut', v_nouveau_statut
    )
  );

  RETURN jsonb_build_object('success', true, 'est_actif', v_nouveau_statut);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_toggle_template_contrat(uuid) TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT57_PR8_ADMIN_TEMPLATES_CONTRATS_INSTALLED',
    'pr', 'PR 8 Sprint 5.7',
    'rpcs', jsonb_build_array(
      'fn_admin_lister_templates_contrats',
      'fn_admin_detail_template_contrat',
      'fn_admin_modifier_template_contrat',
      'fn_admin_toggle_template_contrat'
    )
  )
);
