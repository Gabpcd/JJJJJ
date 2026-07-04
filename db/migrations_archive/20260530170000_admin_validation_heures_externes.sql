-- UI admin de validation des heures externes (parcours 3200h libéral)
--
-- Les déclarations d'heures externes passent EN_ATTENTE quand la vérification IA
-- détecte un écart (heures lues ≠ déclarées) ou ne peut pas extraire le volume.
-- Un admin doit alors trancher manuellement. Ces 2 RPC alimentent la page
-- /admin/heures-externes (liste + décision VALIDE/REJETE).

-- =============================================================
-- 1. fn_admin_lister_heures_externes : liste pour la page admin
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_admin_lister_heures_externes(
  p_statut TEXT DEFAULT 'EN_ATTENTE',
  p_limit INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_lignes JSONB;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  SELECT COALESCE(jsonb_agg(ligne ORDER BY (ligne->>'cree_le') DESC), '[]'::jsonb)
    INTO v_lignes
  FROM (
    SELECT jsonb_build_object(
      'id', h.id,
      'soignant_id', h.soignant_id,
      'soignant_nom', s.nom,
      'soignant_prenom', s.prenom,
      'profession', s.profession,
      'type_exercice', s.type_exercice,
      'etablissement_nom', h.etablissement_nom,
      'etablissement_type', h.etablissement_type,
      'date_debut', h.date_debut,
      'date_fin', h.date_fin,
      'heures_declarees', h.heures_declarees,
      'heures_extraites_ia', h.heures_extraites_ia,
      'coherence_ia', h.coherence_ia,
      'statut_validation', h.statut_validation,
      'commentaire_validation', h.commentaire_validation,
      'attestation_url', h.attestation_url,
      'attestation_nom_fichier', h.attestation_nom_fichier,
      'verifie_ia_le', h.verifie_ia_le,
      'cree_le', h.cree_le
    ) AS ligne
    FROM public.heures_externes_soignants h
    JOIN public.soignants s ON s.id = h.soignant_id
    WHERE (p_statut = 'TOUS' OR h.statut_validation = p_statut)
    ORDER BY h.cree_le DESC
    LIMIT GREATEST(1, LEAST(p_limit, 500))
  ) sub;

  RETURN jsonb_build_object('success', true, 'heures', v_lignes);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_heures_externes(TEXT, INT) TO authenticated;

-- =============================================================
-- 2. fn_admin_valider_heures_externes : décision VALIDE / REJETE
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_admin_valider_heures_externes(
  p_id UUID,
  p_decision TEXT,
  p_commentaire TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_ligne public.heures_externes_soignants%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  IF p_decision NOT IN ('VALIDE', 'REJETE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Décision invalide (VALIDE ou REJETE)');
  END IF;

  IF p_decision = 'REJETE' AND COALESCE(length(trim(p_commentaire)), 0) < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Motif requis pour un rejet (min 5 caractères)');
  END IF;

  SELECT * INTO v_ligne FROM public.heures_externes_soignants WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Déclaration introuvable');
  END IF;

  UPDATE public.heures_externes_soignants
     SET statut_validation = p_decision,
         commentaire_validation = COALESCE(NULLIF(trim(p_commentaire), ''), commentaire_validation),
         valide_par = v_uid,
         valide_le = NOW(),
         mis_a_jour_le = NOW()
   WHERE id = p_id;

  -- Audit (best-effort : ne bloque pas la décision si l'audit échoue)
  BEGIN
    PERFORM public.fn_ecrire_audit_safe(
      v_uid, 'ADMIN', 'HEURES_EXTERNES_VALIDATION_MANUELLE',
      'heures_externes_soignants', p_id, v_ligne.attestation_url,
      jsonb_build_object(
        'decision', p_decision,
        'soignant_id', v_ligne.soignant_id,
        'heures_declarees', v_ligne.heures_declarees,
        'heures_extraites_ia', v_ligne.heures_extraites_ia,
        'commentaire', p_commentaire
      ),
      NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'statut', p_decision);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_valider_heures_externes(UUID, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
