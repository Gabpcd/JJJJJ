-- Itération 1 — Fix B.5 + B.6 + B.7 : parrainage soignant
-- B.6 : cap 20 filleuls validés par parrain (cohérent étab cap 10, soignant cap 20 plus laxiste)
-- B.7 : expiration 12 mois après création si filleul n'a pas fait de mission TERMINEE
-- B.5 : révocation badge Ambassadeur si < 3 filleuls validés (ex. annulation/suspension)

-- 1) Étendre la contrainte CHECK sur statut pour autoriser EXPIRED + ANNULE
ALTER TABLE public.parrainages DROP CONSTRAINT IF EXISTS parrainages_statut_check;
ALTER TABLE public.parrainages ADD CONSTRAINT parrainages_statut_check
  CHECK (statut IN ('EN_ATTENTE','VALIDE','EXPIRED','ANNULE'));

-- 2) Patch fn_appliquer_parrainage : cap 20 + désactiver bonus immédiat (= attendre 1ère mission)
CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_parrain RECORD;
  v_filleul_id UUID := auth.uid();
  v_nb_filleuls_valides INT;
BEGIN
  IF v_filleul_id IS NULL THEN
    RETURN '{"error":"Non authentifié"}'::JSONB;
  END IF;

  SELECT * INTO v_parrain FROM soignants WHERE code_parrainage = p_code AND supprime_le IS NULL;
  IF v_parrain IS NULL THEN RETURN '{"error":"Code de parrainage invalide"}'::JSONB; END IF;
  IF v_parrain.id = v_filleul_id THEN RETURN '{"error":"Vous ne pouvez pas vous parrainer vous-même"}'::JSONB; END IF;

  -- Itération 1 fix B.6 : cap 20 filleuls validés par parrain
  SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages
  WHERE parrain_id = v_parrain.id AND statut = 'VALIDE';
  IF v_nb_filleuls_valides >= 20 THEN
    RETURN '{"error":"Le parrain a atteint la limite de 20 filleuls validés"}'::JSONB;
  END IF;

  IF EXISTS (SELECT 1 FROM parrainages WHERE filleul_id = v_filleul_id) THEN
    RETURN '{"error":"Vous avez déjà appliqué un code de parrainage"}'::JSONB;
  END IF;

  INSERT INTO parrainages (parrain_id, filleul_id, code_parrainage, statut)
  VALUES (v_parrain.id, v_filleul_id, p_code, 'EN_ATTENTE');

  UPDATE soignants SET parraine_par = v_parrain.id WHERE id = v_filleul_id AND parraine_par IS NULL;

  RETURN jsonb_build_object('success', true, 'message', 'Code accepté. Bonus +50h débloqué après votre 1ère mission terminée.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_appliquer_parrainage(TEXT) TO authenticated;

-- 3) Trigger sur missions TERMINEE : valider parrainage EN_ATTENTE + appliquer bonus
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_parrainage RECORD;
  v_nb_filleuls_valides INT;
BEGIN
  IF NEW.statut <> 'TERMINEE' OR COALESCE(OLD.statut, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE'
  LIMIT 1;

  IF v_parrainage IS NOT NULL THEN
    SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages
    WHERE parrain_id = v_parrainage.parrain_id AND statut = 'VALIDE';

    IF v_nb_filleuls_valides < 20 THEN
      UPDATE parrainages SET statut = 'VALIDE', valide_le = NOW()
      WHERE id = v_parrainage.id;

      UPDATE soignants SET heures_cumulees = COALESCE(heures_cumulees, 0) + 50
      WHERE id IN (v_parrainage.parrain_id, v_parrainage.filleul_id);

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE',
        '🎉 Filleul validé !',
        'Votre filleul a terminé sa 1ère mission. Vous gagnez +50h cumulées !',
        '/soignant/parrainage'
      );

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
        p_action := 'PARRAINAGE_ETAB_VALIDE',
        p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
        p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'mission_declencheur', NEW.id)
      );
    ELSE
      UPDATE parrainages SET statut = 'EXPIRED' WHERE id = v_parrainage.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_valider_parrainage_soignant ON public.missions;
CREATE TRIGGER trg_valider_parrainage_soignant
  AFTER UPDATE OF statut ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission();

-- 4) RPC cron : expirer parrainages > 12 mois sans mission TERMINEE
CREATE OR REPLACE FUNCTION public.fn_expirer_parrainages_inactifs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_count INT := 0;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  WITH expired AS (
    UPDATE parrainages SET statut = 'EXPIRED'
    WHERE statut = 'EN_ATTENTE'
      AND cree_le < NOW() - INTERVAL '12 months'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_count FROM expired;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_expirer_parrainages_inactifs() TO service_role;

-- 5) Fix B.5 : Trigger sur soignants UPDATE → recalcul badge Ambassadeur
CREATE OR REPLACE FUNCTION public.fn_trg_recalcul_badge_ambassadeur()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_parrain_id UUID;
  v_nb_filleuls INT;
BEGIN
  IF (OLD.supprime_le IS NULL AND NEW.supprime_le IS NOT NULL)
     OR (COALESCE(OLD.statut_compte::text, '') <> 'SUSPENDU' AND NEW.statut_compte::text = 'SUSPENDU') THEN
    v_parrain_id := NEW.parraine_par;
    IF v_parrain_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_nb_filleuls FROM soignants
      WHERE parraine_par = v_parrain_id
        AND premiere_mission_le IS NOT NULL
        AND supprime_le IS NULL
        AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
      IF v_nb_filleuls < 3 THEN
        UPDATE soignants SET badge_ambassadeur = false
        WHERE id = v_parrain_id AND COALESCE(badge_ambassadeur, false) = true;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalcul_badge_ambassadeur ON public.soignants;
CREATE TRIGGER trg_recalcul_badge_ambassadeur
  AFTER UPDATE OF supprime_le, statut_compte ON public.soignants
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_recalcul_badge_ambassadeur();

NOTIFY pgrst, 'reload schema';
