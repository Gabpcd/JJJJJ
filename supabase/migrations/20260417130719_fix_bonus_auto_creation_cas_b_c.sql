-- ============================================================
-- FIX BONUS — fn_auto_creation_litiges_presence : Cas B (DEPART_ANTICIPE)
--              + consommation FIX 11 (anti-boucle litige_auto_cree_le)
--              + bascule initie_par='SYSTEME' (FIX 12 consommation)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b (notamment 130400 CRON,
--             130703 FIX 11 litige_auto_cree_le, 130704 FIX 12 enum SYSTEME).
--
-- Avant ce FIX bonus, fn_auto_creation_litiges_presence ne couvrait que
-- le Cas A (ABSENCE_SOIGNANT : heures_reelles IS NULL OR = 0). Les
-- cas B (DEPART_ANTICIPE) et C (DESACCORD_HEURES_POINTAGE) étaient
-- absents — seul le flux manuel via fn_ouvrir_litige_rate_limited les
-- couvrait.
--
-- SCOPE livré :
--   1) Cas A — ABSENCE_SOIGNANT (inchangé, restructuré)
--   2) Cas B — DEPART_ANTICIPE  (NOUVEAU)
--              Déclencheur : heures_reelles > 0
--                         ET heures_reelles < missions.duree_heures * 0.80
--              (seuil 20 % d'écart pour éviter les faux positifs sur
--               petites minorations légitimes de 5-10 min).
--   3) initie_par='SYSTEME' sur les litiges auto (FIX 12 consommation)
--   4) Anti-boucle : presences.litige_auto_cree_le renseigné au INSERT,
--      filtré à NULL dans la boucle (FIX 11 consommation).
--
-- NON LIVRÉ (documenté) — Cas C DESACCORD_HEURES_POINTAGE :
--   Le schéma actuel n'expose qu'une seule colonne heures_reelles (pas
--   de distinction heures_declarees_etab vs heures_declarees_soignant).
--   Détecter un désaccord auto demanderait soit un schéma dual, soit
--   une comparaison heures_reelles vs duree_heures planifiée (qui
--   recouvre déjà Cas A/B). Le cas C reste donc couvert manuellement
--   via fn_ouvrir_litige_rate_limited(mission_id, 'DESACCORD_HEURES_
--   POINTAGE', motif) côté frontend soignant/étab — comportement
--   existant conservé. Cf. /docs/sub-pr-2-quater-recap.md (à écrire
--   en CP8c) pour le suivi.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_auto_creation_litiges_presence()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_delai_pointage_h INT;
  v_nb_abs INT := 0;
  v_nb_dep INT := 0;
  v_presence RECORD;
  v_litige_id UUID;
  v_type_litige public.type_litige;
  v_motif TEXT;
  v_notif_corps TEXT;
BEGIN
  SELECT valeur::INT INTO v_delai_pointage_h
    FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';

  FOR v_presence IN
    SELECT p.id AS presence_id,
           p.mission_id,
           p.soignant_id,
           p.heures_reelles,
           m.duree_heures,
           m.etablissement_id,
           m.soignant_assigne_id
      FROM public.presences p
      JOIN public.missions m ON m.id = p.mission_id
     WHERE p.valide_par_etablissement = TRUE
       AND p.valide_le IS NOT NULL
       AND p.valide_le < NOW() - make_interval(hours => v_delai_pointage_h)
       AND p.motif_litige IS NOT NULL
       -- Anti-boucle FIX 11 : on ne traite pas les présences déjà traitées.
       AND p.litige_auto_cree_le IS NULL
  LOOP
    -- Classification Cas A / Cas B
    IF v_presence.heures_reelles IS NULL OR v_presence.heures_reelles = 0 THEN
      v_type_litige := 'ABSENCE_SOIGNANT';
      v_motif       := 'Auto-création : soignant marqué absent sans contestation dans les 48h';
      v_notif_corps := 'Votre établissement a signalé une absence. Répondez sous 72h pour éviter l''escalade automatique.';
    ELSIF v_presence.duree_heures IS NOT NULL
      AND v_presence.duree_heures > 0
      AND v_presence.heures_reelles < v_presence.duree_heures * 0.80
    THEN
      v_type_litige := 'DEPART_ANTICIPE';
      v_motif       := format(
        'Auto-création : départ anticipé (%sh effectuées sur %sh prévues, soit %s %%).',
        v_presence.heures_reelles,
        v_presence.duree_heures,
        round((v_presence.heures_reelles / v_presence.duree_heures) * 100)
      );
      v_notif_corps := 'Votre établissement a signalé un départ anticipé. Répondez sous 72h pour éviter l''escalade automatique.';
    ELSE
      CONTINUE;  -- ni Cas A ni Cas B : on ignore (écart < 20 %).
    END IF;

    -- Unicité mission+type (défense en profondeur, l'index uq_litige_mission_
    -- type_ouvert le garantit côté DB mais on évite une exception).
    IF EXISTS (
      SELECT 1 FROM public.litiges l
       WHERE l.mission_id = v_presence.mission_id
         AND l.type_litige = v_type_litige
         AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION')
    ) THEN
      -- Marque la présence comme traitée (anti-boucle) même si litige
      -- déjà ouvert manuellement : évite de repasser dessus au prochain run.
      UPDATE public.presences
         SET litige_auto_cree_le = NOW()
       WHERE id = v_presence.presence_id;
      CONTINUE;
    END IF;

    INSERT INTO public.litiges (
      mission_id, soignant_id, etablissement_id, presence_id,
      initie_par, motif, statut, type_litige, est_informatif
    ) VALUES (
      v_presence.mission_id,
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      v_presence.etablissement_id,
      v_presence.presence_id,
      'SYSTEME',           -- FIX 12 consommation
      v_motif,
      'OUVERT',
      v_type_litige,
      FALSE
    )
    RETURNING id INTO v_litige_id;

    -- FIX 11 consommation : verrou anti-boucle
    UPDATE public.presences
       SET litige_auto_cree_le = NOW()
     WHERE id = v_presence.presence_id;

    PERFORM public.fn_ecrire_audit(
      NULL, 'SYSTEM', 'LITIGE_AUTO_CREATION',
      'litige', v_litige_id, NULL,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'presence_id', v_presence.presence_id,
        'heures_reelles', v_presence.heures_reelles,
        'duree_heures_prevues', v_presence.duree_heures,
        'raison', CASE v_type_litige
          WHEN 'ABSENCE_SOIGNANT' THEN 'Absence non contestée dans les 48h post-validation présence'
          WHEN 'DEPART_ANTICIPE'  THEN 'Départ anticipé (< 80 % heures prévues) non contesté dans les 48h'
        END
      ),
      NULL, NULL
    );

    PERFORM public.fn_litige_push_notification(
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      'SOIGNANT',
      'LITIGE_OUVERTURE',
      'Litige ouvert sur votre mission',
      v_notif_corps,
      v_litige_id,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'auto_cree', TRUE
      )
    );

    IF v_type_litige = 'ABSENCE_SOIGNANT' THEN
      v_nb_abs := v_nb_abs + 1;
    ELSE
      v_nb_dep := v_nb_dep + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'litiges_crees', v_nb_abs + v_nb_dep,
    'absence_soignant', v_nb_abs,
    'depart_anticipe', v_nb_dep
  );
END;
$$;

COMMENT ON FUNCTION public.fn_auto_creation_litiges_presence() IS
  'Cron : crée automatiquement des litiges ABSENCE_SOIGNANT (heures_reelles=0/NULL) '
  'et DEPART_ANTICIPE (< 80 % des heures prévues) pour les présences non contestées '
  'dans les 48h post-validation étab. Anti-boucle via presences.litige_auto_cree_le. '
  'initie_par=SYSTEME. Retourne { litiges_crees, absence_soignant, depart_anticipe }. '
  'Cas DESACCORD_HEURES_POINTAGE non auto-détectable (schéma presences mono-colonne) '
  '— reste manuel via fn_ouvrir_litige_rate_limited.';

GRANT EXECUTE ON FUNCTION public.fn_auto_creation_litiges_presence() TO service_role;

COMMIT;
