-- ============================================================
-- CP-LITIGES-2 FIXES — ajustements post-validation
-- ============================================================
-- Dépend de CP-LITIGES-1 (20260417130000) + CP-LITIGES-2 (20260417130100)
--
-- Fixes :
--   FIX-A : renomme la clé seed 'rate_limit_litiges_par_24h' →
--           'rate_limit_litiges_par_heure' pour cohérence avec le code
--           (la fenêtre d'application reste 1h, inchangée).
--   FIX-C : ajoute un appel fn_ecrire_audit dans la nouvelle signature
--           fn_ouvrir_litige_rate_limited(UUID, type_litige, TEXT)
--           (wrapper rétrocompat 2-arg inchangé).
--
-- FIX-B (docs/tech-debt.md) : traité hors SQL — ajout ticket T9 (gel par
-- période post-Partie 2) et T10 (évaluer 3/24h vs 3/1h).
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- FIX-A — Renomme la clé du rate limit pour refléter le code
-- ──────────────────────────────────────────────────────────────

UPDATE public.parametres_litiges
   SET cle = 'rate_limit_litiges_par_heure',
       description = 'Rate limit : 3 litiges par heure par entité (aligné sur le code de fn_ouvrir_litige_rate_limited).',
       modifie_le = NOW()
 WHERE cle = 'rate_limit_litiges_par_24h';

-- ──────────────────────────────────────────────────────────────
-- FIX-C — Ajoute audit RGPD dans fn_ouvrir_litige_rate_limited (3-arg)
-- ──────────────────────────────────────────────────────────────
-- Le wrapper 2-arg (DEPRECATED) n'est pas modifié ; il délègue toujours
-- à la version 3-arg, qui logge maintenant systématiquement une entrée
-- audit LITIGE_OUVERTURE.

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

  -- Unicité par (mission, type) garantie par index unique partiel (CP1).
  SELECT COUNT(*) INTO v_existing
    FROM public.litiges
   WHERE mission_id = p_mission_id
     AND type_litige = p_type_litige
     AND statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION');
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('error', 'Un litige de ce type est déjà ouvert pour cette mission.');
  END IF;

  -- Rate limit paramétrable (3/heure par défaut, clé renommée par FIX-A)
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

  -- Vérification fenêtre
  v_fenetre_ouverte := public.fn_fenetre_contestation_ouverte(p_type_litige, p_mission_id, NULL);
  v_est_informatif := NOT v_fenetre_ouverte;

  -- Si fenêtre fermée ET type pas éligible informatif → refus
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
    mission_id, soignant_id, etablissement_id, presence_id,
    initie_par, motif, statut, type_litige, est_informatif
  )
  VALUES (
    p_mission_id, v_soignant_id, v_etab_id, v_presence_id,
    v_initie_par, trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif
  )
  RETURNING id INTO v_litige_id;

  -- [FIX-C] Audit RGPD systématique
  PERFORM public.fn_ecrire_audit(
    v_user_id, v_initie_par, 'LITIGE_OUVERTURE',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'initie_par', v_initie_par,
      'est_informatif', v_est_informatif
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif
  );
END;
$$;

COMMIT;
