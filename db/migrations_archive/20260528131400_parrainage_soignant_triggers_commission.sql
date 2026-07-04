-- Sprint 17-A PR 3 — Triggers validation + suivi seuil commission
--
-- 1) Remplace trg_valider_parrainage_soignant :
--    - Filleul 1ère mission TERMINEE + parrain a ≥1 TERMINEE → FILLEUL_ACTIF
--    - Parrain 1ère mission TERMINEE → vérifie si filleuls EN_ATTENTE à activer
--    - +50h bonus préservé (rétro-compat)
--
-- 2) Nouveau trigger sur factures PAYEE :
--    - Cumule commission encaissée sur parrainages.commission_cumulee_filleul
--    - Quand seuil ≥ 100€ atteint → VALIDE_EN_ATTENTE_SEUIL
--    - Anti-fraude : vérifie signaux → FRAUDE si suspect
--    - Crée action externalisée RECOMPENSE_PARRAINAGE_SOIGNANT

-- ═══════════════════════════════════════════════════════════════
-- 1) Trigger mission TERMINEE → activation parrainage
-- ═══════════════════════════════════════════════════════════════

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
BEGIN
  IF NEW.statut <> 'TERMINEE' OR COALESCE(OLD.statut, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  -- A) Vérifier si le soignant est un FILLEUL avec parrainage EN_ATTENTE
  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE'
  LIMIT 1;

  IF v_parrainage IS NOT NULL THEN
    -- Vérifier que le parrain a au moins 1 mission TERMINEE
    SELECT EXISTS(
      SELECT 1 FROM missions
      WHERE soignant_assigne_id = v_parrainage.parrain_id AND statut = 'TERMINEE'
      LIMIT 1
    ) INTO v_parrain_a_mission;

    IF v_parrain_a_mission THEN
      -- Cap check
      SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages
      WHERE parrain_id = v_parrainage.parrain_id
        AND statut IN ('VALIDE', 'FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL', 'PRIME_VERSEE');

      IF v_nb_filleuls_actifs < 20 THEN
        UPDATE parrainages
        SET statut = 'FILLEUL_ACTIF',
            filleul_active_le = NOW(),
            valide_le = NOW()
        WHERE id = v_parrainage.id;

        -- +50h bonus préservé
        UPDATE soignants SET heures_cumulees = COALESCE(heures_cumulees, 0) + 50
        WHERE id IN (v_parrainage.parrain_id, v_parrainage.filleul_id);

        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE',
          '🎉 Filleul activé !',
          'Votre filleul a terminé sa 1ère mission. +50h cumulées ! La prime de 50€ sera versée après 100€ de commission encaissée.',
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

  -- B) Vérifier si le soignant est un PARRAIN — activer les filleuls EN_ATTENTE
  --    qui ont déjà complété leur 1ère mission
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
      SET statut = 'FILLEUL_ACTIF',
          filleul_active_le = NOW(),
          valide_le = NOW()
      WHERE id = v_filleul_parrainage.id;

      UPDATE soignants SET heures_cumulees = COALESCE(heures_cumulees, 0) + 50
      WHERE id IN (NEW.soignant_assigne_id, v_filleul_parrainage.filleul_id);

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        NEW.soignant_assigne_id, 'SOIGNANT', 'PARRAINAGE',
        '🎉 Filleul activé !',
        'Votre filleul a terminé sa 1ère mission. +50h cumulées !',
        '/soignant/parrainage'
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_valider_parrainage_soignant ON public.missions;
CREATE TRIGGER trg_valider_parrainage_soignant
  AFTER UPDATE OF statut ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission();

-- ═══════════════════════════════════════════════════════════════
-- 2) Trigger factures PAYEE → cumul commission + seuil 100€
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_commission_encaissee()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mission RECORD;
  v_parrainage RECORD;
  v_commission NUMERIC;
  v_new_cumul NUMERIC;
  v_nb_fraude_signals INT;
BEGIN
  -- Ne traiter que les transitions vers PAYEE
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;

  -- Récupérer la mission liée
  IF NEW.mission_id IS NULL THEN RETURN NEW; END IF;

  SELECT id, soignant_assigne_id INTO v_mission FROM missions WHERE id = NEW.mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  -- Vérifier si le soignant de cette mission est un filleul avec parrainage actif
  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = v_mission.soignant_assigne_id
    AND statut IN ('FILLEUL_ACTIF', 'VALIDE_EN_ATTENTE_SEUIL')
  LIMIT 1;

  IF v_parrainage IS NULL THEN RETURN NEW; END IF;

  -- Cumuler la commission HT encaissée
  v_commission := COALESCE(NEW.montant_ht, 0);
  IF v_commission <= 0 THEN RETURN NEW; END IF;

  v_new_cumul := COALESCE(v_parrainage.commission_cumulee_filleul, 0) + v_commission;

  UPDATE parrainages
  SET commission_cumulee_filleul = v_new_cumul
  WHERE id = v_parrainage.id;

  -- Vérifier si le seuil 100€ est atteint (seulement si pas déjà en VALIDE_EN_ATTENTE_SEUIL)
  IF v_new_cumul >= 100 AND v_parrainage.statut = 'FILLEUL_ACTIF' THEN
    -- Anti-fraude : vérifier signaux
    SELECT COUNT(*) INTO v_nb_fraude_signals
    FROM parrainage_fraude_signals
    WHERE parrainage_id = v_parrainage.id AND type = 'MEME_IP';

    IF v_nb_fraude_signals > 0 THEN
      -- Même IP détectée → FRAUDE, pas de versement
      UPDATE parrainages SET statut = 'FRAUDE' WHERE id = v_parrainage.id;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
        p_action := 'PARRAINAGE_SOIGNANT_FRAUDE',
        p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
        p_details := jsonb_build_object(
          'filleul_id', v_parrainage.filleul_id,
          'commission_cumulee', v_new_cumul,
          'raison', 'MEME_IP détectée à inscription'
        )
      );

      -- Notifier admin
      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      SELECT id, 'ADMIN_PLATEFORME', 'SYSTEM',
        '⚠️ Parrainage fraude détectée',
        'Parrainage ' || v_parrainage.id::text || ' : même IP parrain/filleul détectée. Seuil commission atteint mais versement bloqué.',
        '/admin/utilisateurs'
      FROM soignants WHERE role = 'ADMIN_PLATEFORME' LIMIT 3;

      RETURN NEW;
    END IF;

    -- Seuil atteint, pas de fraude → créer action versement
    UPDATE parrainages
    SET statut = 'VALIDE_EN_ATTENTE_SEUIL'
    WHERE id = v_parrainage.id;

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT',
      p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
      p_details := jsonb_build_object(
        'filleul_id', v_parrainage.filleul_id,
        'commission_cumulee', v_new_cumul
      )
    );

    -- Créer action versement via worker async (action atomique 50€+50€)
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('RECOMPENSE_PARRAINAGE_SOIGNANT',
      jsonb_build_object(
        'parrainage_id', v_parrainage.id,
        'parrain_id', v_parrainage.parrain_id,
        'filleul_id', v_parrainage.filleul_id,
        'montant_parrain', 50,
        'montant_filleul', 50,
        'commission_cumulee', v_new_cumul
      ),
      'parrainage_soignant', v_parrainage.id::text
    );

    -- Notifier parrain + filleul
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES
    (
      v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE',
      '💰 Prime de parrainage de 50€ !',
      'Votre filleul a généré suffisamment de commission. 50€ vont être versés sur votre compte Stripe Connect.',
      '/soignant/parrainage'
    ),
    (
      v_parrainage.filleul_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE',
      '💰 Prime de parrainage de 50€ !',
      'Félicitations ! 50€ de prime de parrainage vont être versés sur votre compte Stripe Connect.',
      '/soignant/parrainage'
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_parrainage_commission_encaissee ON public.factures;
CREATE TRIGGER trg_parrainage_commission_encaissee
  AFTER INSERT OR UPDATE OF statut ON public.factures
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_parrainage_commission_encaissee();

NOTIFY pgrst, 'reload schema';
