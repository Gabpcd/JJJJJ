-- HOTFIX 7f — le trigger réécrit en 20260702175827 comparait
-- COALESCE(OLD.statut, '') sur l'ENUM statut_mission : cast de '' vers l'enum
-- → 22P02 sur TOUTE transition de statut mission (acceptation, clôture…).
-- Fenêtre d'impact prod : 17h58 → 18h19 UTC le 02/07/2026.
-- Correctif : comparaison via ::text (NULL-safe, aucun cast d'enum).
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_parrainage RECORD;
  v_parrain_a_mission BOOLEAN;
  v_nb_filleuls_actifs INT;
  v_filleul_parrainage RECORD;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
BEGIN
  IF NEW.statut::text <> 'TERMINEE' OR COALESCE(OLD.statut::text, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE'
  LIMIT 1;

  IF v_parrainage IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM missions
      WHERE soignant_assigne_id = v_parrainage.parrain_id AND statut = 'TERMINEE'
      LIMIT 1
    ) INTO v_parrain_a_mission;

    IF v_parrain_a_mission THEN
      SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
      WHERE parrain_id = v_parrainage.parrain_id
        AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

      IF v_nb_filleuls_actifs < 20 THEN
        UPDATE parrainages
        SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW()
        WHERE id = v_parrainage.id;

        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE',
          '🎉 Ton filleul a fait sa 1ʳᵉ mission !',
          'Vos primes de ' || v_prime || '€ chacun seront versées quand il aura atteint ' || v_seuil_gmv || '€ de missions encaissées. Suis sa progression sur ta page parrainage.',
          '/soignant/parrainage'
        );

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
          p_action := 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF',
          p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
          p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'mission_id', NEW.id)
        );
      ELSE
        UPDATE parrainages SET statut = 'EXPIRED' WHERE id = v_parrainage.id;
      END IF;
    END IF;
  END IF;

  FOR v_filleul_parrainage IN
    SELECT p.*, s.premiere_mission_le FROM parrainages p
    JOIN soignants s ON s.id = p.filleul_id
    WHERE p.parrain_id = NEW.soignant_assigne_id
      AND p.statut = 'EN_ATTENTE'
      AND s.premiere_mission_le IS NOT NULL
  LOOP
    SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
    WHERE parrain_id = NEW.soignant_assigne_id
      AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

    IF v_nb_filleuls_actifs < 20 THEN
      UPDATE parrainages
      SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW()
      WHERE id = v_filleul_parrainage.id;

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        NEW.soignant_assigne_id, 'SOIGNANT', 'PARRAINAGE',
        '🎉 Ton filleul est activé !',
        'Vos primes de ' || v_prime || '€ chacun seront versées à ' || v_seuil_gmv || '€ de missions encaissées par ton filleul.',
        '/soignant/parrainage'
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
