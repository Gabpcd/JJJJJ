-- Lot 15 — D8 : publication double-aveugle des notations (simultanée dès
-- réciprocité, sinon J+7) + score qualité établissement enfin branché.
--
-- Constats (09/07/2026, définitions LIVE — règle 9.0) :
--   1. Aucune mécanique de publication : une note était visible et impactait
--      le score de l'autre partie INSTANTANÉMENT → représailles possibles.
--   2. fn_calculer_score_etablissement n'était déclenchée QUE par trigger
--      (notation soignant→étab, litige résolu, masquage). Sans ces événements,
--      jamais appelée → score_qualite NULL sur tous les établissements, et le
--      swipe soignant n'affichait donc jamais le score étab.
--
-- Politique de publication (D8) :
--   - À l'INSERT, publie_le = NULL (note posée mais NON publiée).
--   - Dès que les DEUX sens existent sur la mission → publication simultanée.
--   - Sinon, publication à J+7 (cron quotidien, délai paramétrable).
--   - Le recalcul de score ne se déclenche qu'à la PUBLICATION (ou modération).
--   - L'existant est grandfathered (publie_le = cree_le : déjà visible/compté).

-- ── 1. Colonne de publication + grandfathering ───────────────────────────────
ALTER TABLE public.notations_missions ADD COLUMN IF NOT EXISTS publie_le timestamptz;
UPDATE public.notations_missions SET publie_le = cree_le WHERE publie_le IS NULL;

INSERT INTO parametres_systeme(cle, valeur, label, description, unite, categorie)
VALUES('notation_publication_jours', 7,
       'Notations — publication auto (jours)',
       'Délai après lequel une notation non réciproquée est publiée automatiquement (double-aveugle D8 : publication simultanée dès que les deux parties ont noté, sinon à J+N).',
       'jours', 'GENERAL')
ON CONFLICT (cle) DO NOTHING;

-- ── 2. fn_creer_notation_mission : INSERT non publié + publication réciproque ─
-- Base = définition LIVE. Ajout : bloc D8 après l'INSERT (aucune autre logique
-- modifiée).
CREATE OR REPLACE FUNCTION public.fn_creer_notation_mission(p_mission_id uuid, p_sens text, p_critere_1 integer, p_critere_2 integer, p_critere_3 integer, p_critere_4 integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_mission RECORD;
  v_sens public.sens_notation;
  v_notateur_id UUID;
  v_note_id UUID;
  v_id UUID;
  v_tardive BOOLEAN := false;
  v_litige_actif_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  BEGIN v_sens := UPPER(TRIM(p_sens))::public.sens_notation;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sens invalide');
  END;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut, fin_le INTO v_mission
  FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  -- 7b-C : TERMINEE, ou EN_COURS avec départ pointé (check-out fait, le cron
  -- de transition n'est simplement pas encore passé).
  IF v_mission.statut <> 'TERMINEE'
     AND NOT (v_mission.statut = 'EN_COURS' AND EXISTS (
       SELECT 1 FROM presences pr
       WHERE pr.mission_id = p_mission_id AND pr.pointage_depart_le IS NOT NULL
     ))
     AND NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions TERMINEE peuvent être notées');
  END IF;

  -- Itération 1 fix B.8 : bloquer notation pendant litige actif (médiation/arbitrage)
  IF NOT est_admin() THEN
    SELECT COUNT(*) INTO v_litige_actif_count FROM litiges
    WHERE mission_id = p_mission_id
      AND statut IN ('MEDIATION_EN_COURS', 'REVUE_ADMIN');
    IF v_litige_actif_count > 0 THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution.');
    END IF;
  END IF;

  IF v_sens = 'ETAB_VERS_SOIGNANT' THEN
    IF NOT est_admin() AND v_mission.etablissement_id <> v_etab_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas l''établissement de cette mission');
    END IF;
    IF v_mission.soignant_assigne_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Mission sans soignant assigné');
    END IF;
    v_notateur_id := COALESCE(v_etab_id, v_mission.etablissement_id);
    v_note_id := v_mission.soignant_assigne_id;
  ELSE
    IF NOT est_admin() AND v_mission.soignant_assigne_id <> v_uid THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas le soignant de cette mission');
    END IF;
    v_notateur_id := v_uid;
    v_note_id := v_mission.etablissement_id;
  END IF;

  IF v_mission.fin_le < NOW() - INTERVAL '30 days' THEN
    v_tardive := true;
  END IF;

  INSERT INTO notations_missions (
    mission_id, notateur_id, note_id, sens,
    critere_1, critere_2, critere_3, critere_4, commentaire
  ) VALUES (
    p_mission_id, v_notateur_id, v_note_id, v_sens,
    p_critere_1, p_critere_2, p_critere_3, p_critere_4, NULLIF(TRIM(p_commentaire), '')
  )
  ON CONFLICT (mission_id, sens) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission déjà notée pour ce sens');
  END IF;

  -- D8 (Lot 15) : double-aveugle — l'INSERT part NON publié (publie_le NULL).
  -- Dès que les deux sens existent, publication SIMULTANÉE des deux notes
  -- (l'UPDATE déclenche le recalcul des scores via le trigger). Sinon le cron
  -- fn_publier_notations_echues publie à J+7.
  IF EXISTS (
    SELECT 1 FROM notations_missions
    WHERE mission_id = p_mission_id AND sens <> v_sens
  ) THEN
    UPDATE notations_missions SET publie_le = NOW()
    WHERE mission_id = p_mission_id AND publie_le IS NULL;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_notateur_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text, 'note_id', v_note_id, 'tardive', v_tardive)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_note_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'NOTATION_RECUE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text)
  );

  RETURN jsonb_build_object('success', true, 'id', v_id, 'tardive', v_tardive);
END;
$function$;

-- ── 3. Recalcul des scores : à la PUBLICATION (plus à l'insertion) ───────────
-- Base = définition LIVE. La branche notations ne recalcule que quand
-- publie_le vient d'être posé, ou quand la modération (masque) change.
CREATE OR REPLACE FUNCTION public.fn_trg_recalculer_score_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_soignant_id UUID;
  v_etab_id UUID;
BEGIN
  IF TG_TABLE_NAME = 'notations_missions' THEN
    -- D8 : la note n'existe pour les scores qu'une fois PUBLIÉE.
    IF NOT (
      (NEW.publie_le IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.publie_le IS NULL))
      OR (TG_OP = 'UPDATE' AND COALESCE(OLD.masque, false) <> COALESCE(NEW.masque, false))
    ) THEN
      RETURN NEW;
    END IF;
    IF NEW.sens = 'ETAB_VERS_SOIGNANT' THEN
      v_soignant_id := NEW.note_id; v_etab_id := NEW.notateur_id;
    ELSE
      v_soignant_id := NEW.notateur_id; v_etab_id := NEW.note_id;
    END IF;
    PERFORM public.fn_calculer_score_fiabilite_v2(v_soignant_id, 'notation_recue');
    IF v_etab_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_etablissement(v_etab_id);
    END IF;

  ELSIF TG_TABLE_NAME = 'missions' THEN
    IF NEW.statut IN ('TERMINEE','ABSENCE') AND COALESCE(OLD.statut, '') <> NEW.statut::text
       AND NEW.soignant_assigne_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_assigne_id, 'mission_' || NEW.statut::text);
    END IF;

  ELSIF TG_TABLE_NAME = 'litiges' THEN
    IF NEW.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE','RESOLU_ACCORD_PARTIES')
       AND COALESCE(OLD.statut, '') <> NEW.statut::text
       AND NEW.soignant_id IS NOT NULL THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_id, 'litige_resolu');
      IF NEW.etablissement_id IS NOT NULL THEN
        PERFORM public.fn_calculer_score_etablissement(NEW.etablissement_id);
      END IF;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;

-- Le trigger écoute désormais aussi publie_le.
DROP TRIGGER IF EXISTS trg_recalcul_score_v2_notations ON public.notations_missions;
CREATE TRIGGER trg_recalcul_score_v2_notations
  AFTER INSERT OR UPDATE OF critere_1, critere_2, critere_3, critere_4, masque, publie_le
  ON public.notations_missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_recalculer_score_v2();

-- ── 4. Les agrégats ne comptent que les notes publiées ───────────────────────
-- fn_calculer_score_etablissement — base LIVE, ajout du filtre publie_le.
CREATE OR REPLACE FUNCTION public.fn_calculer_score_etablissement(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_since TIMESTAMPTZ := NOW() - INTERVAL '12 months';
  v_notation_pct NUMERIC;
  v_paiement_pct NUMERIC;
  v_litiges_malus NUMERIC := 0;
  v_score NUMERIC := 0;
  v_niveau public.niveau_qualitatif;
  v_nb_notations INT;
  v_nb_litiges INT;
  v_total_factures INT;
  v_factures_a_temps INT;
BEGIN
  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_pct
  FROM notations_missions
  WHERE note_id = p_etab_id AND sens = 'SOIGNANT_VERS_ETAB' AND cree_le >= v_since AND masque = false
    AND publie_le IS NOT NULL; -- D8

  IF v_nb_notations < 3 OR v_notation_pct IS NULL THEN
    v_notation_pct := NULL;
  ELSE
    v_notation_pct := GREATEST(0, LEAST(100, (v_notation_pct - 1) * 25));
  END IF;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE date_paiement IS NOT NULL AND date_paiement <= date_echeance)
  INTO v_total_factures, v_factures_a_temps
  FROM factures
  WHERE etablissement_id = p_etab_id AND statut = 'PAYEE' AND COALESCE(date_emission, cree_le) >= v_since;

  IF v_total_factures = 0 THEN v_paiement_pct := NULL;
  ELSE v_paiement_pct := (v_factures_a_temps::NUMERIC / v_total_factures) * 100; END IF;

  SELECT LEAST(2, COUNT(*)) * 10 INTO v_nb_litiges
  FROM litiges
  WHERE etablissement_id = p_etab_id
    AND statut IN ('RESOLU_SOIGNANT', 'RESOLU_FAVEUR_SOIGNANT')
    AND COALESCE(resolu_le, NOW()) >= v_since;
  v_litiges_malus := -COALESCE(v_nb_litiges, 0);

  DECLARE v_total_poids NUMERIC := 0; v_facteur NUMERIC;
  BEGIN
    IF v_notation_pct IS NOT NULL THEN v_total_poids := v_total_poids + 50; END IF;
    IF v_paiement_pct IS NOT NULL THEN v_total_poids := v_total_poids + 30; END IF;
    IF v_total_poids > 0 THEN
      v_facteur := 80.0 / v_total_poids;
      v_score := COALESCE(v_notation_pct, 0) * 50 * v_facteur / 100
               + COALESCE(v_paiement_pct, 0) * 30 * v_facteur / 100
               + 20 + v_litiges_malus;
    ELSE v_score := 50 + v_litiges_malus; END IF;
    v_score := GREATEST(0, LEAST(100, v_score));
  END;

  v_niveau := CASE
    WHEN v_score >= 90 THEN 'PLATINE'
    WHEN v_score >= 70 THEN 'OR'
    WHEN v_score >= 50 THEN 'ARGENT'
    ELSE 'BRONZE'
  END::public.niveau_qualitatif;

  UPDATE etablissements SET score_qualite = v_score, niveau = v_niveau WHERE id = p_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'SCORE_ETAB_RECALCULE', p_type_ressource := 'etablissement', p_id_ressource := p_etab_id,
    p_details := jsonb_build_object('score', v_score, 'niveau', v_niveau::text, 'notation_pct', v_notation_pct, 'paiement_pct', v_paiement_pct, 'litiges_malus', v_litiges_malus)
  );

  RETURN jsonb_build_object('success', true, 'score', v_score, 'niveau', v_niveau);
END;
$function$;

-- fn_lister_notations_recues — base LIVE, seule modification : notes publiées.
CREATE OR REPLACE FUNCTION public.fn_lister_notations_recues(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_target_id UUID;
  v_target_sens public.sens_notation;
  v_result JSONB;
  v_limit INT;
BEGIN
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);

  IF v_etab_id IS NOT NULL THEN
    v_target_id := v_etab_id;
    v_target_sens := 'SOIGNANT_VERS_ETAB';
  ELSIF v_uid IS NOT NULL THEN
    v_target_id := v_uid;
    v_target_sens := 'ETAB_VERS_SOIGNANT';
  ELSE
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'mission_id', n.mission_id,
    'mission_intitule', m.intitule,
    'mission_fin_le', m.fin_le,
    'critere_1', n.critere_1,
    'critere_2', n.critere_2,
    'critere_3', n.critere_3,
    'critere_4', n.critere_4,
    'note_moyenne', ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1),
    'commentaire', n.commentaire,
    'cree_le', n.cree_le
  ) ORDER BY n.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM notations_missions n
  JOIN missions m ON m.id = n.mission_id
  WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false
    AND n.publie_le IS NOT NULL -- D8 : une note non publiée n'est visible de personne
  LIMIT v_limit;

  RETURN v_result;
END;
$function$;

-- ── 5. Publication J+7 + recalcul périodique des scores étab ─────────────────
CREATE OR REPLACE FUNCTION public.fn_publier_notations_echues()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_jours numeric := public.fn_param_num('notation_publication_jours', 7);
  v_count int;
BEGIN
  UPDATE notations_missions
  SET publie_le = NOW()
  WHERE publie_le IS NULL
    AND cree_le + make_interval(days => v_jours::int) < NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'publiees', v_count);
END;
$fn$;

-- Recalcul quotidien des scores étab (les étabs sans événement déclencheur
-- restaient à NULL pour toujours — c'est la cause des 26 scores NULL).
CREATE OR REPLACE FUNCTION public.fn_recalculer_scores_etablissements()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_etab record;
  v_count int := 0;
BEGIN
  FOR v_etab IN SELECT id FROM etablissements WHERE supprime_le IS NULL LOOP
    PERFORM public.fn_calculer_score_etablissement(v_etab.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'recalcules', v_count);
END;
$fn$;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron absent (branche preview) — crons notation sautés.';
    RETURN;
  END IF;
  PERFORM cron.schedule('jolene_publier_notations_j7', '30 5 * * *',
    'SELECT public.fn_publier_notations_echues()');
  PERFORM cron.schedule('jolene_recalcul_scores_etab', '45 5 * * *',
    'SELECT public.fn_recalculer_scores_etablissements()');
END $do$;

-- ── 6. Backfill immédiat des scores étab (les 26 NULL) ───────────────────────
SELECT public.fn_recalculer_scores_etablissements();
