-- ============================================================
-- CP5b Step 6a — Protection PREVISIONNEL post-gel
-- ============================================================
-- Audit: /docs/cp5b-creneaux-et-pointage.md section 1.3
-- Extends fn_protect_creneaux_si_facture to also block
-- PREVISIONNEL modifications when mission.fige_le IS NOT NULL.
-- EFFECTIF créneaux remain dynamic (no gel protection).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_protect_creneaux_si_facture()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission_id uuid;
  v_type_creneau text;
  v_has_facture boolean;
  v_correction_mission uuid;
  v_correction_reason text;
  v_fige_le timestamptz;
  v_override_gel_mission uuid;
  v_override_gel_reason text;
BEGIN
  v_mission_id := COALESCE(NEW.mission_id, OLD.mission_id);
  v_type_creneau := COALESCE(NEW.type_creneau, OLD.type_creneau);

  -- ────────────────────────────────────────────────────
  -- CHECK 1 (CP5b): PREVISIONNEL immutables après gel
  -- ────────────────────────────────────────────────────
  IF v_type_creneau = 'PREVISIONNEL' THEN
    SELECT fige_le INTO v_fige_le FROM missions WHERE id = v_mission_id;

    IF v_fige_le IS NOT NULL THEN
      v_override_gel_mission := NULLIF(current_setting('jolene.admin_override_gel', true), '')::uuid;
      v_override_gel_reason := NULLIF(current_setting('jolene.admin_override_reason', true), '');

      IF v_override_gel_mission = v_mission_id AND v_override_gel_reason IS NOT NULL THEN
        INSERT INTO journaux_audit
          (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
        VALUES (
          auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_CHAMP_POST_GEL', 'mission_creneaux',
          COALESCE(NEW.id, OLD.id),
          jsonb_build_object(
            'reason', v_override_gel_reason,
            'mission_id', v_mission_id,
            'operation', TG_OP,
            'type_creneau', 'PREVISIONNEL'
          )
        );
      ELSE
        RAISE EXCEPTION 'Créneaux PREVISIONNEL immutables après gel (mission gelée le %). Les créneaux prévisionnels ne peuvent pas être modifiés après assignation. Pour corriger, un admin doit définir jolene.admin_override_gel et jolene.admin_override_reason.',
          v_fige_le USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  -- ────────────────────────────────────────────────────
  -- CHECK 2 (CP3): Facture émise bloque TOUS les créneaux
  -- ────────────────────────────────────────────────────
  SELECT EXISTS (
    SELECT 1 FROM factures_honoraires
    WHERE mission_id = v_mission_id
      AND statut NOT IN ('BROUILLON', 'ANNULEE')
  ) INTO v_has_facture;

  IF NOT v_has_facture THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_correction_mission := NULLIF(current_setting('jolene.admin_correction_mission_id', true), '')::uuid;
  v_correction_reason := NULLIF(current_setting('jolene.admin_correction_reason', true), '');

  IF v_correction_mission = v_mission_id AND v_correction_reason IS NOT NULL THEN
    INSERT INTO invoice_audit_log (invoice_id, action, performed_by, payload_before)
    SELECT fh.id, 'CRENEAUX_MODIFIED_POST_FACTURE', auth.uid(),
      jsonb_build_object(
        'reason', v_correction_reason,
        'mission_id', v_mission_id,
        'operation', TG_OP,
        'creneau_id', COALESCE(NEW.id, OLD.id)
      )
    FROM factures_honoraires fh
    WHERE fh.mission_id = v_mission_id AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
    LIMIT 1;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  RAISE EXCEPTION 'Impossible de modifier les créneaux : une facture émise existe pour cette mission (mission_id=%). Pour corriger, un admin doit définir jolene.admin_correction_mission_id et jolene.admin_correction_reason.',
    v_mission_id USING ERRCODE = 'check_violation';
END;
$$;
