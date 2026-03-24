DROP FUNCTION IF EXISTS public.fn_declarer_virement(uuid, text);

CREATE FUNCTION public.fn_declarer_virement(p_facture_id uuid, p_reference text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facture RECORD;
BEGIN
  SELECT id, statut, etablissement_id
    INTO v_facture
    FROM factures
   WHERE id = p_facture_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Facture introuvable');
  END IF;

  IF v_facture.etablissement_id != auth.uid() AND NOT est_admin() THEN
    RETURN json_build_object('error', 'Non autorisé');
  END IF;

  IF v_facture.statut NOT IN ('EMISE', 'EN_RETARD') THEN
    RETURN json_build_object('error', 'Cette facture ne peut pas être payée par virement (statut: ' || v_facture.statut || ')');
  END IF;

  UPDATE factures
     SET virement_reference = p_reference,
         mode_paiement = 'VIREMENT',
         statut = 'VIREMENT_DECLARE',
         modifie_le = now()
   WHERE id = p_facture_id;

  RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_confirmer_virement_admin(p_facture_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facture RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN json_build_object('error', 'Réservé aux administrateurs');
  END IF;

  SELECT id, statut INTO v_facture FROM factures WHERE id = p_facture_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Facture introuvable');
  END IF;

  IF v_facture.statut != 'VIREMENT_DECLARE' THEN
    RETURN json_build_object('error', 'Cette facture n''est pas en attente de vérification de virement');
  END IF;

  UPDATE factures
     SET statut = 'PAYEE',
         date_paiement = now(),
         virement_confirme_le = now(),
         virement_confirme_par = auth.uid(),
         modifie_le = now()
   WHERE id = p_facture_id;

  RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_rejeter_virement_admin(p_facture_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_facture RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN json_build_object('error', 'Réservé aux administrateurs');
  END IF;

  SELECT id, statut INTO v_facture FROM factures WHERE id = p_facture_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Facture introuvable');
  END IF;

  IF v_facture.statut != 'VIREMENT_DECLARE' THEN
    RETURN json_build_object('error', 'Cette facture n''est pas en attente de vérification de virement');
  END IF;

  UPDATE factures
     SET statut = 'EMISE',
         virement_reference = NULL,
         mode_paiement = 'STRIPE',
         modifie_le = now()
   WHERE id = p_facture_id;

  RETURN json_build_object('success', true);
END;
$$;