-- ============================================================
-- FIX T20 — fn_cloturer_litige_mutuel : audit RGPD manquant
-- ============================================================
-- Bug : fn_cloturer_litige_mutuel ne traçait aucune entrée audit lors
-- de l'accord individuel (soignant ou étab) ni lors de la clôture
-- amiable bilatérale. Incohérent avec les autres RPCs litiges qui
-- loguent systématiquement via fn_ecrire_audit.
--
-- Impact : demande d'accès RGPD, impossible de retracer la clôture.
--
-- Correction :
--   1) Après chaque accord individuel : audit LITIGE_ACCORD_CLOTURE
--      avec partie + état des accords
--   2) Si le 2e accord déclenche la résolution : audit
--      LITIGE_CLOTURE_AMIABLE avec flag cloture_par_accord_bilateral
--
-- fn_litiges_escalader_auto : déjà couvert (LITIGE_ESCALADE_AUTO
-- dans CP-LITIGES-4, confirmé en FIX T19). Pas de changement.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_mutuel(p_litige_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_litige RECORD;
  v_is_soignant BOOLEAN := FALSE;
  v_is_etab BOOLEAN := FALSE;
  v_partie TEXT;
  v_ancien_accord_s BOOLEAN;
  v_ancien_accord_e BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;

  IF v_litige.statut NOT IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé.');
  END IF;

  IF v_litige.soignant_id = v_user_id THEN
    v_is_soignant := TRUE;
    v_partie := 'SOIGNANT';
  ELSIF v_litige.etablissement_id = mon_etablissement_id() THEN
    v_is_etab := TRUE;
    v_partie := 'ETABLISSEMENT';
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante.');
  END IF;

  v_ancien_accord_s := COALESCE(v_litige.accord_soignant, FALSE);
  v_ancien_accord_e := COALESCE(v_litige.accord_etablissement, FALSE);

  IF v_is_soignant THEN
    UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
  ELSIF v_is_etab THEN
    UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
  END IF;

  -- [FIX T20] Audit RGPD : accord individuel
  PERFORM public.fn_ecrire_audit(
    v_user_id, v_partie, 'LITIGE_ACCORD_CLOTURE',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'partie', v_partie,
      'accord', TRUE,
      'accords_precedents', jsonb_build_object(
        'soignant', v_ancien_accord_s,
        'etablissement', v_ancien_accord_e
      )
    ),
    NULL, NULL
  );

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige.accord_soignant AND v_litige.accord_etablissement THEN
    UPDATE litiges SET statut = 'RESOLU', resolution = 'Clôturé d''un commun accord', resolu_le = NOW() WHERE id = p_litige_id;

    -- [FIX T20] Audit RGPD : clôture bilatérale
    PERFORM public.fn_ecrire_audit(
      v_user_id, v_partie, 'LITIGE_CLOTURE_AMIABLE',
      'litige', p_litige_id, NULL,
      jsonb_build_object(
        'resolution', 'Clôturé d''un commun accord',
        'cloture_par_accord_bilateral', TRUE
      ),
      NULL, NULL
    );

    RETURN jsonb_build_object('ok', true, 'cloture', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'cloture', false);
END;
$$;

COMMENT ON FUNCTION public.fn_cloturer_litige_mutuel(UUID) IS
  'Clôture amiable bilatérale. Chaque partie appelle pour marquer son accord. '
  'Quand les 2 accords sont TRUE → statut RESOLU automatiquement. '
  'FIX T20 : audit RGPD LITIGE_ACCORD_CLOTURE + LITIGE_CLOTURE_AMIABLE.';

COMMIT;
