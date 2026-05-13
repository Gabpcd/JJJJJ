-- ============================================================================
-- Sprint 5.7 PR 7 — Admin contrats consultation (P0-9)
-- ============================================================================
-- Permet à un admin de lister + consulter en détail tous les contrats
-- (hash, certificat, audit trail) pour audit légal.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_admin_lister_contrats(
  p_filtre_statut text DEFAULT NULL,
  p_recherche text DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_contrats jsonb;
  v_total int;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT count(*) INTO v_total
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  LEFT JOIN public.soignants s ON s.id = cm.soignant_id
  LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id
  WHERE (p_filtre_statut IS NULL OR cm.statut = p_filtre_statut)
    AND (p_recherche IS NULL OR
         m.intitule ILIKE '%' || p_recherche || '%' OR
         cm.numero_contrat ILIKE '%' || p_recherche || '%' OR
         s.nom ILIKE '%' || p_recherche || '%' OR
         s.prenom ILIKE '%' || p_recherche || '%' OR
         e.nom ILIKE '%' || p_recherche || '%');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cm.id,
    'numero_contrat', cm.numero_contrat,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'soignant_id', cm.soignant_id,
    'soignant_nom', s.prenom || ' ' || s.nom,
    'etablissement_id', cm.etablissement_id,
    'etablissement_nom', e.nom,
    'type_contrat', cm.type_contrat,
    'statut', cm.statut,
    'hash_court', CASE WHEN cm.hash_document IS NOT NULL THEN substring(cm.hash_document, 1, 12) || '...' ELSE NULL END,
    'signature_soignant', cm.signature_soignant,
    'signature_etablissement', cm.signature_etablissement,
    'signature_soignant_le', cm.signature_soignant_le,
    'signature_etablissement_le', cm.signature_etablissement_le,
    'mode_signature', cm.mode_signature,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_numero', cm.dpae_numero,
    'cree_le', cm.cree_le
  ) ORDER BY cm.cree_le DESC), '[]'::jsonb)
  INTO v_contrats
  FROM (
    SELECT cm.* FROM public.contrats_mission cm
    JOIN public.missions m ON m.id = cm.mission_id
    LEFT JOIN public.soignants s ON s.id = cm.soignant_id
    LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id
    WHERE (p_filtre_statut IS NULL OR cm.statut = p_filtre_statut)
      AND (p_recherche IS NULL OR
           m.intitule ILIKE '%' || p_recherche || '%' OR
           cm.numero_contrat ILIKE '%' || p_recherche || '%' OR
           s.nom ILIKE '%' || p_recherche || '%' OR
           s.prenom ILIKE '%' || p_recherche || '%' OR
           e.nom ILIKE '%' || p_recherche || '%')
    ORDER BY cm.cree_le DESC
    LIMIT p_limit OFFSET p_offset
  ) cm
  JOIN public.missions m ON m.id = cm.mission_id
  LEFT JOIN public.soignants s ON s.id = cm.soignant_id
  LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset,
    'contrats', v_contrats
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_contrats(text, text, int, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_detail_contrat(p_contrat_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_contrat jsonb;
  v_audit jsonb;
  v_signatures jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT jsonb_build_object(
    'id', cm.id,
    'numero_contrat', cm.numero_contrat,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'mission_debut_le', m.debut_le,
    'mission_fin_le', m.fin_le,
    'soignant_id', cm.soignant_id,
    'soignant_nom', s.prenom || ' ' || s.nom,
    'soignant_email', su.email,
    'soignant_rpps', s.numero_rpps,
    'etablissement_id', cm.etablissement_id,
    'etablissement_nom', e.nom,
    'etablissement_siret', e.siret,
    'type_contrat', cm.type_contrat,
    'statut', cm.statut,
    'mode_signature', cm.mode_signature,
    'hash_document', cm.hash_document,
    'signature_soignant', cm.signature_soignant,
    'signature_soignant_le', cm.signature_soignant_le,
    'signature_ip_soignant', cm.signature_ip_soignant::text,
    'signature_navigateur_soignant', cm.signature_navigateur_soignant,
    'signature_etablissement', cm.signature_etablissement,
    'signature_etablissement_le', cm.signature_etablissement_le,
    'signature_ip_etablissement', cm.signature_ip_etablissement::text,
    'signature_navigateur_etablissement', cm.signature_navigateur_etablissement,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_effectuee_le', cm.dpae_effectuee_le,
    'dpae_numero', cm.dpae_numero,
    'storage_path', cm.storage_path,
    'pdf_cle_s3', cm.pdf_cle_s3,
    'cree_le', cm.cree_le,
    'modifie_le', cm.modifie_le
  )
  INTO v_contrat
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  LEFT JOIN public.soignants s ON s.id = cm.soignant_id
  LEFT JOIN auth.users su ON su.id = cm.soignant_id
  LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id
  WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE');
  END IF;

  -- Signatures détaillées si existantes (Sprint 2)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', sc.id,
    'signataire_role', sc.signataire_role,
    'signe_a', sc.signe_a,
    'ip_signature', sc.ip_signature::text,
    'user_agent', sc.user_agent,
    'hash_document', sc.hash_document,
    'otp_valide_a', sc.otp_valide_a,
    'statut_signature', sc.statut_signature
  ) ORDER BY sc.signe_a DESC), '[]'::jsonb)
  INTO v_signatures
  FROM public.signatures_contrats sc
  WHERE sc.contrat_id = p_contrat_id;

  -- Audit trail
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', ja.id,
    'acteur_id', ja.acteur_id,
    'type_acteur', ja.type_acteur,
    'action', ja.action,
    'details', ja.details,
    'cree_le', ja.cree_le
  ) ORDER BY ja.cree_le DESC), '[]'::jsonb)
  INTO v_audit
  FROM public.journaux_audit ja
  WHERE (ja.type_ressource = 'contrat_mission' OR ja.type_ressource = 'contrats_mission')
    AND ja.id_ressource = p_contrat_id
  LIMIT 100;

  RETURN jsonb_build_object(
    'success', true,
    'contrat', v_contrat,
    'signatures', v_signatures,
    'audit_trail', v_audit
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_detail_contrat(uuid) TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT57_PR7_ADMIN_CONTRATS_INSTALLED',
    'pr', 'PR 7 Sprint 5.7',
    'rpcs', jsonb_build_array('fn_admin_lister_contrats', 'fn_admin_detail_contrat')
  )
);
