-- ============================================================
-- FIX T19 — fn_litiges_escalader_auto + fn_fenetre_contestation_ouverte :
--           utiliser missions.type_contrat_applique (figé)
-- ============================================================
-- Bug : ces deux RPCs utilisaient soignants.est_salarie_etablissement
-- (flag global) pour calculer les délais. Pour un profil MIXTE
-- (soignant salarié dans étab A et libéral dans étab B), le flag global
-- est faux pour la mission en cours → délais incorrects (72h appliqué à
-- une mission salariée, ou 5 j.o. à une mission libérale).
--
-- Correction :
--   1) Lecture prioritaire de missions.type_contrat_applique (enum
--      'LIBERAL'/'SALARIE', figé à l'assignation, cf. FIX 3).
--   2) Fallback documenté quand type_contrat_applique IS NULL (missions
--      antérieures au FIX 3 non backfillées) : on retombe sur
--      soignants.est_salarie_etablissement pour préserver la rétrocompat.
--   3) Application cohérente dans :
--      - fn_litiges_escalader_auto (escalade 72h libéral / 5 j.o. salarié)
--      - fn_fenetre_contestation_ouverte (F2/F3 : 48h libéral / 60j salarié)
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. fn_litiges_escalader_auto : utilise type_contrat_applique
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_litiges_escalader_auto()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_delai_liberal_h INT;
  v_delai_salarie_j_ouvres INT;
  v_nb_escalades INT := 0;
  v_litige RECORD;
  v_admin_id UUID;
BEGIN
  SELECT valeur::INT INTO v_delai_liberal_h
    FROM public.parametres_litiges WHERE cle = 'delai_escalade_liberal_h';
  SELECT valeur::INT INTO v_delai_salarie_j_ouvres
    FROM public.parametres_litiges WHERE cle = 'delai_escalade_salarie_jours_ouvres';

  FOR v_litige IN
    -- [FIX T19] type effectif = mission.type_contrat_applique en priorité,
    -- fallback sur est_salarie_etablissement si NULL (rétrocompat backfill).
    SELECT l.id, l.mission_id, l.soignant_id, l.etablissement_id,
           l.type_litige, l.cree_le,
           CASE
             WHEN m.type_contrat_applique = 'SALARIE' THEN TRUE
             WHEN m.type_contrat_applique = 'LIBERAL' THEN FALSE
             ELSE COALESCE(s.est_salarie_etablissement, FALSE)
           END AS est_salarie
      FROM public.litiges l
      LEFT JOIN public.soignants s ON s.id = l.soignant_id
      LEFT JOIN public.missions  m ON m.id = l.mission_id
     WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
       AND NOT l.est_informatif
       AND (
         (CASE
            WHEN m.type_contrat_applique = 'SALARIE' THEN TRUE
            WHEN m.type_contrat_applique = 'LIBERAL' THEN FALSE
            ELSE COALESCE(s.est_salarie_etablissement, FALSE)
          END = FALSE
          AND l.cree_le < NOW() - make_interval(hours => v_delai_liberal_h))
         OR
         (CASE
            WHEN m.type_contrat_applique = 'SALARIE' THEN TRUE
            WHEN m.type_contrat_applique = 'LIBERAL' THEN FALSE
            ELSE COALESCE(s.est_salarie_etablissement, FALSE)
          END = TRUE
          AND l.cree_le < public.fn_ajouter_jours_ouvres(NOW(), -v_delai_salarie_j_ouvres))
       )
  LOOP
    UPDATE public.litiges
       SET statut = 'EN_MEDIATION',
           escalade_auto_le = NOW(),
           escalade_auto_motif = CASE
             WHEN v_litige.est_salarie THEN 'Pas de réponse dans le délai salarié (5 jours ouvrés)'
             ELSE 'Pas de réponse dans le délai libéral (72h)'
           END
     WHERE id = v_litige.id;

    PERFORM public.fn_ecrire_audit(
      NULL, 'SYSTEM', 'LITIGE_ESCALADE_AUTO',
      'litige', v_litige.id, NULL,
      jsonb_build_object(
        'type_litige', v_litige.type_litige,
        'mission_id', v_litige.mission_id,
        'est_salarie', v_litige.est_salarie
      ),
      NULL, NULL
    );

    FOR v_admin_id IN SELECT * FROM public.fn_list_admin_user_ids()
    LOOP
      PERFORM public.fn_litige_push_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_ESCALADE_ADMIN',
        'Litige escaladé : ' || v_litige.type_litige,
        'Un litige ' || v_litige.type_litige || ' sur mission '
          || v_litige.mission_id::text
          || ' a été auto-escaladé en médiation.',
        v_litige.id,
        jsonb_build_object(
          'type_litige', v_litige.type_litige,
          'mission_id', v_litige.mission_id,
          'prioritaire', TRUE
        )
      );
    END LOOP;

    v_nb_escalades := v_nb_escalades + 1;
  END LOOP;

  RETURN jsonb_build_object('escalades', v_nb_escalades);
END;
$$;

COMMENT ON FUNCTION public.fn_litiges_escalader_auto() IS
  'Cron : escalade les litiges OUVERT/EN_DISCUSSION sans réponse après délai (libéral 72h / salarié 5 jours ouvrés). '
  'FIX T19 : type effectif via missions.type_contrat_applique (figé à l''assignation), fallback est_salarie_etablissement si NULL. '
  'Retourne { escalades: N }.';

-- ──────────────────────────────────────────────────────────────
-- 2. fn_fenetre_contestation_ouverte : même logique
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_fenetre_contestation_ouverte(
  p_type_litige public.type_litige,
  p_mission_id UUID,
  p_facture_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_presence_validee TIMESTAMPTZ;
  v_facture_emise    TIMESTAMPTZ;
  v_facture_payee    TIMESTAMPTZ;
  v_mission_fin      TIMESTAMPTZ;
  v_est_salarie      BOOLEAN;
  v_type_applique    public.type_contrat_applique_enum;
  v_soignant_id      UUID;
  v_delai_pointage   INTEGER;
  v_delai_liberal    INTEGER;
  v_delai_salarie    INTEGER;
  v_delai_compo_mois INTEGER;
BEGIN
  IF p_type_litige IN ('SECURITE_DANGER', 'NON_PAIEMENT', 'AUTRE') THEN
    RETURN TRUE;
  END IF;

  SELECT valeur::INTEGER INTO v_delai_pointage   FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';
  SELECT valeur::INTEGER INTO v_delai_liberal    FROM public.parametres_litiges WHERE cle = 'delai_contestation_facture_liberal_h';
  SELECT valeur::INTEGER INTO v_delai_salarie    FROM public.parametres_litiges WHERE cle = 'delai_contestation_paiement_salarie_j';
  SELECT valeur::INTEGER INTO v_delai_compo_mois FROM public.parametres_litiges WHERE cle = 'delai_comportement_mois';

  IF p_type_litige IN ('ABSENCE_SOIGNANT', 'DEPART_ANTICIPE', 'RETARD_IMPORTANT', 'DESACCORD_HEURES_POINTAGE') THEN
    SELECT valide_le INTO v_presence_validee
      FROM public.presences
     WHERE mission_id = p_mission_id
       AND valide_le IS NOT NULL
     ORDER BY valide_le DESC
     LIMIT 1;
    IF v_presence_validee IS NULL THEN
      RETURN TRUE;
    END IF;
    RETURN v_presence_validee + make_interval(hours => v_delai_pointage) > NOW();
  END IF;

  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'FRAIS_COMPLEMENTAIRES') THEN
    IF p_facture_id IS NULL THEN
      RETURN TRUE;
    END IF;

    SELECT f.date_emission, f.date_paiement
      INTO v_facture_emise, v_facture_payee
      FROM public.factures_honoraires f
     WHERE f.id = p_facture_id;

    IF v_facture_emise IS NULL THEN
      RETURN FALSE;
    END IF;

    -- [FIX T19] Type effectif : mission.type_contrat_applique en priorité,
    -- fallback est_salarie_etablissement si NULL (missions pré-backfill).
    SELECT m.soignant_assigne_id, m.type_contrat_applique
      INTO v_soignant_id, v_type_applique
      FROM public.missions m WHERE m.id = p_mission_id;

    IF v_type_applique = 'SALARIE' THEN
      v_est_salarie := TRUE;
    ELSIF v_type_applique = 'LIBERAL' THEN
      v_est_salarie := FALSE;
    ELSE
      SELECT COALESCE(s.est_salarie_etablissement, FALSE) INTO v_est_salarie
        FROM public.soignants s WHERE s.id = v_soignant_id;
    END IF;

    IF v_est_salarie AND v_facture_payee IS NOT NULL THEN
      RETURN v_facture_payee + make_interval(days => v_delai_salarie) > NOW();
    ELSE
      RETURN v_facture_emise + make_interval(hours => v_delai_liberal) > NOW();
    END IF;
  END IF;

  IF p_type_litige IN ('COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT', 'CONDITIONS_MISSION_NON_RESPECTEES') THEN
    SELECT m.fin_le INTO v_mission_fin FROM public.missions m WHERE m.id = p_mission_id;
    IF v_mission_fin IS NULL THEN
      RETURN TRUE;
    END IF;
    RETURN v_mission_fin + make_interval(months => v_delai_compo_mois) > NOW();
  END IF;

  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.fn_fenetre_contestation_ouverte(public.type_litige, UUID, UUID) IS
  'Vérifie si la fenêtre de contestation est ouverte (F1 pointage 48h / F2 facture 48h libéral / F3 paiement 60j salarié / 6 mois COMPORTEMENT). '
  'FIX T19 : type effectif via missions.type_contrat_applique (figé), fallback est_salarie_etablissement si NULL.';

COMMIT;
