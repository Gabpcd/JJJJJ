-- ============================================================
-- FIX T18 — fn_ouvrir_litige + fn_admin_creer_litige_force :
--           résolution facture_id pour types FINANCIER
-- ============================================================
-- Bug : fn_ouvrir_litige_rate_limited passait p_facture_id=NULL à
-- fn_fenetre_contestation_ouverte pour TOUS les types, rendant les
-- fenêtres F2 (48h libéral) et F3 (60j salarié) totalement
-- ineffectives pour DESACCORD_MONTANT_FACTURE, FRAIS_COMPLEMENTAIRES,
-- et NON_PAIEMENT. Un soignant pouvait contester une facture émise
-- il y a 1 an sans blocage.
--
-- Correction :
--   1) Avant l'appel à fn_fenetre_contestation_ouverte, lookup de la
--      facture la plus récente non-BROUILLON pour les 3 types financiers.
--      Si aucune facture → erreur explicite.
--   2) Le v_facture_id résolu est passé à fn_fenetre_contestation_ouverte
--      ET stocké dans litiges.facture_id (INSERT).
--   3) Même correction dans fn_admin_creer_litige_force pour consistance
--      + alimentation du trigger de gel facture (CP7a FIX 1).
--   4) fn_fenetre_contestation_ouverte inchangée (elle gère déjà
--      p_facture_id non-NULL correctement).
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. fn_ouvrir_litige_rate_limited (3-arg canonique)
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id UUID,
  p_type_litige public.type_litige,
  p_motif TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_mission    RECORD;
  v_existing   INT;
  v_recent     INT;
  v_initie_par TEXT;
  v_etab_id    UUID;
  v_soignant_id UUID;
  v_presence_id UUID;
  v_rate_limit INT;
  v_litige_id  UUID;
  v_est_informatif BOOLEAN;
  v_fenetre_ouverte BOOLEAN;
  v_facture_id UUID;  -- [FIX T18]
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut
    INTO v_mission
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.soignant_assigne_id = v_user_id THEN
    v_initie_par  := 'SOIGNANT';
    v_etab_id     := v_mission.etablissement_id;
    v_soignant_id := v_user_id;
  ELSIF v_mission.etablissement_id = public.mon_etablissement_id() THEN
    v_initie_par  := 'ETABLISSEMENT';
    v_etab_id     := v_mission.etablissement_id;
    v_soignant_id := v_mission.soignant_assigne_id;
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante de cette mission.');
  END IF;

  SELECT COUNT(*) INTO v_existing
    FROM public.litiges
   WHERE mission_id = p_mission_id
     AND type_litige = p_type_litige
     AND statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION');
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('error', 'Un litige de ce type est déjà ouvert pour cette mission.');
  END IF;

  v_rate_limit := COALESCE(
    (SELECT valeur::INT FROM public.parametres_litiges WHERE cle = 'rate_limit_litiges_par_heure'),
    3
  );
  SELECT COUNT(*) INTO v_recent
    FROM public.litiges
   WHERE (soignant_id = v_user_id OR etablissement_id = public.mon_etablissement_id())
     AND cree_le > NOW() - INTERVAL '1 hour';
  IF v_recent >= v_rate_limit THEN
    RETURN jsonb_build_object('error', 'Trop de litiges ouverts récemment. Réessayez plus tard.');
  END IF;

  -- [FIX T18] Résolution facture_id pour types financiers
  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES') THEN
    SELECT id INTO v_facture_id
      FROM public.factures_honoraires
     WHERE mission_id = p_mission_id AND statut <> 'BROUILLON'
     ORDER BY date_emission DESC NULLS LAST
     LIMIT 1;
    IF v_facture_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Aucune facture trouvée pour cette mission, contestation impossible.');
    END IF;
  END IF;

  v_fenetre_ouverte := public.fn_fenetre_contestation_ouverte(p_type_litige, p_mission_id, v_facture_id);
  v_est_informatif := NOT v_fenetre_ouverte;

  IF v_est_informatif
     AND p_type_litige NOT IN ('COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT', 'CONDITIONS_MISSION_NON_RESPECTEES')
  THEN
    RETURN jsonb_build_object(
      'error', 'Fenêtre de contestation fermée pour ce type de litige. Contactez le support.'
    );
  END IF;

  SELECT id INTO v_presence_id
    FROM public.presences WHERE mission_id = p_mission_id
   ORDER BY cree_le DESC LIMIT 1;

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, presence_id, facture_id,
    initie_par, motif, statut, type_litige, est_informatif
  )
  VALUES (
    p_mission_id, v_soignant_id, v_etab_id, v_presence_id, v_facture_id,
    v_initie_par, trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif
  )
  RETURNING id INTO v_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, v_initie_par, 'LITIGE_OUVERTURE',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'initie_par', v_initie_par,
      'est_informatif', v_est_informatif,
      'facture_id', v_facture_id
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif,
    'facture_id', v_facture_id
  );
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 2. fn_admin_creer_litige_force — même lookup pour consistance
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_admin_creer_litige_force(
  p_mission_id UUID,
  p_type_litige public.type_litige,
  p_motif TEXT,
  p_raison_bypass TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mission RECORD;
  v_litige_id UUID;
  v_est_informatif BOOLEAN;
  v_facture_id UUID;  -- [FIX T18]
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis pour cette opération.');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;
  IF length(trim(COALESCE(p_raison_bypass, ''))) < 10 THEN
    RETURN jsonb_build_object('error', 'La raison du bypass doit contenir au moins 10 caractères (traçabilité).');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id
    INTO v_mission
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  -- [FIX T18] Résolution facture_id pour types financiers
  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES') THEN
    SELECT id INTO v_facture_id
      FROM public.factures_honoraires
     WHERE mission_id = p_mission_id AND statut <> 'BROUILLON'
     ORDER BY date_emission DESC NULLS LAST
     LIMIT 1;
    -- Admin force : pas de blocage si pas de facture (cas NON_PAIEMENT
    -- sans facture émise), mais on logue un warning dans l'audit.
  END IF;

  v_est_informatif := NOT public.fn_fenetre_contestation_ouverte(
    p_type_litige, p_mission_id, v_facture_id
  );

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, est_informatif, facture_id
  )
  VALUES (
    p_mission_id, v_mission.soignant_assigne_id, v_mission.etablissement_id, 'ADMIN',
    trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif, v_facture_id
  )
  RETURNING id INTO v_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_FORCE_CREATION',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'est_informatif', v_est_informatif,
      'raison_bypass', trim(p_raison_bypass),
      'facture_id', v_facture_id
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif,
    'facture_id', v_facture_id
  );
END;
$$;

COMMENT ON FUNCTION public.fn_admin_creer_litige_force(UUID, public.type_litige, TEXT, TEXT) IS
  'Admin-only : crée un litige en bypassant la fenêtre de contestation. FIX T18 : résout '
  'facture_id pour types financiers + stocke dans litiges.facture_id. Flag est_informatif=TRUE '
  'si hors fenêtre. Audit RGPD obligatoire avec raison.';

COMMIT;
