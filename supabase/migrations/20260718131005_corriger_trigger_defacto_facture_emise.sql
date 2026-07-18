-- Le trigger affectait une colonne d'un RECORD jamais initialisé :
--   INTO v_opt_in, v_soignant.mandat_facturation_signe
-- PostgreSQL levait donc « record v_soignant is not assigned yet » au passage
-- de toute note d'honoraires vers EMISE, même sans option d'affacturage.
CREATE OR REPLACE FUNCTION public.fn_trg_defacto_auto_cession()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_opt_in boolean;
BEGIN
  IF NEW.statut = 'EMISE'
     AND OLD.statut IS DISTINCT FROM 'EMISE'
     AND NEW.type_document = 'FACTURE' THEN
    SELECT s.defacto_opt_in
    INTO v_opt_in
    FROM public.soignants s
    WHERE s.id = NEW.soignant_id;

    IF COALESCE(v_opt_in, false) THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.cessions_creance c
        WHERE c.facture_honoraire_id = NEW.id
      ) THEN
        INSERT INTO public.cessions_creance (
          soignant_id, facture_honoraire_id, montant,
          version_texte, contenu_hash, signed_at, ip_address, user_agent
        ) VALUES (
          NEW.soignant_id, NEW.id, NEW.montant_ttc,
          'auto_defacto_opt_in_v1', 'auto', now(), 'system',
          'weekly-invoicing-cron'
        );

        UPDATE public.factures_honoraires
        SET factor_assigned = true
        WHERE id = NEW.id;

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := NEW.soignant_id,
          p_type_acteur := 'SYSTEME',
          p_action := 'FACTURATION',
          p_type_ressource := 'facture_honoraire',
          p_id_ressource := NEW.id,
          p_details := jsonb_build_object(
            'event', 'DEFACTO_AUTO_CESSION',
            'montant_ttc', NEW.montant_ttc,
            'opt_in', true
          )
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_trg_defacto_auto_cession()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_defacto_auto_cession()
  TO service_role;
