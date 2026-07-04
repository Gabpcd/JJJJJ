
-- F15: Restreindre la mise à jour des notifications aux seuls champs lue/lue_le
DROP POLICY IF EXISTS pol_notif_update ON public.notifications;

CREATE POLICY pol_notif_update ON public.notifications
  FOR UPDATE TO authenticated
  USING (destinataire_id = auth.uid())
  WITH CHECK (destinataire_id = auth.uid());

-- Trigger pour bloquer la modification de colonnes autres que lue/lue_le
CREATE OR REPLACE FUNCTION public.fn_protect_notification_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.titre IS DISTINCT FROM OLD.titre
    OR NEW.corps IS DISTINCT FROM OLD.corps
    OR NEW.type IS DISTINCT FROM OLD.type
    OR NEW.lien IS DISTINCT FROM OLD.lien
    OR NEW.destinataire_id IS DISTINCT FROM OLD.destinataire_id
    OR NEW.type_destinataire IS DISTINCT FROM OLD.type_destinataire
    OR NEW.id_ressource IS DISTINCT FROM OLD.id_ressource
    OR NEW.type_ressource IS DISTINCT FROM OLD.type_ressource
    OR NEW.email_envoye IS DISTINCT FROM OLD.email_envoye
    OR NEW.email_envoye_le IS DISTINCT FROM OLD.email_envoye_le
    OR NEW.push_envoyee IS DISTINCT FROM OLD.push_envoyee
    OR NEW.push_envoyee_le IS DISTINCT FROM OLD.push_envoyee_le
    OR NEW.cree_le IS DISTINCT FROM OLD.cree_le
  THEN
    RAISE EXCEPTION 'Seuls les champs lue et lue_le peuvent être modifiés';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_notification_update ON public.notifications;
CREATE TRIGGER trg_protect_notification_update
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW
  WHEN (NOT public.est_admin())
  EXECUTE FUNCTION public.fn_protect_notification_update();
