-- Admin awareness + fallback : prévenir les admins dès qu'un avoir requiert un
-- virement MANUEL (montant + bénéficiaire), pour qu'ils sachent quoi payer et
-- via quel IBAN, puis confirment avec fn_confirmer_remboursement_avoir.
CREATE OR REPLACE FUNCTION public.fn_trg_notif_admin_remboursement_manuel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_soignant RECORD;
  v_montant NUMERIC;
BEGIN
  -- Seulement à la création (ou bascule) d'un AVOIR en VIREMENT_MANUEL non remboursé.
  IF NEW.type_document <> 'AVOIR' OR NEW.mode_remboursement <> 'VIREMENT_MANUEL'
     OR NEW.date_remboursement IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.mode_remboursement = 'VIREMENT_MANUEL'
     AND OLD.type_document = 'AVOIR' THEN
    RETURN NEW; -- déjà notifié à l'insert / bascule précédente
  END IF;

  SELECT prenom, nom, iban_virement INTO v_soignant
  FROM public.soignants WHERE id = NEW.soignant_id;

  v_montant := COALESCE(NEW.montant_ttc, NEW.montant_ht, 0);

  FOR v_admin_id IN SELECT public.fn_list_admin_user_ids() LOOP
    INSERT INTO public.notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_admin_id, 'ADMIN_PLATEFORME', 'REMBOURSEMENT_MANUEL_A_FAIRE',
      '💸 Remboursement par virement à effectuer',
      'Avoir ' || COALESCE(NEW.numero_facture, '') || ' — ' ||
        to_char(v_montant, 'FM999G999D00') || ' € à virer à ' ||
        COALESCE(v_soignant.prenom, '') || ' ' || COALESCE(v_soignant.nom, '') ||
        CASE WHEN v_soignant.iban_virement IS NOT NULL
             THEN ' (IBAN renseigné)' ELSE ' (IBAN MANQUANT — relancer le soignant)' END ||
        '. Confirmez le virement dans Admin > Litiges > Avoirs.',
      '/admin/litiges',
      'facture_honoraire', NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notif_admin_remboursement_manuel ON public.factures_honoraires;
CREATE TRIGGER trg_notif_admin_remboursement_manuel
  AFTER INSERT OR UPDATE OF mode_remboursement, type_document ON public.factures_honoraires
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_notif_admin_remboursement_manuel();

NOTIFY pgrst, 'reload schema';
