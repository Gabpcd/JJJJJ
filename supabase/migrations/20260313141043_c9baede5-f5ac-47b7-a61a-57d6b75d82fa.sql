-- P1: Restreindre UPDATE sur documents_soignants
DROP POLICY IF EXISTS pol_doc_update ON public.documents_soignants;

CREATE POLICY pol_doc_update_admin ON public.documents_soignants
  FOR UPDATE TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

CREATE POLICY pol_doc_update_self ON public.documents_soignants
  FOR UPDATE TO authenticated
  USING (soignant_id = auth.uid())
  WITH CHECK (soignant_id = auth.uid());

CREATE OR REPLACE FUNCTION fn_protect_document_verification()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT est_admin() THEN
    IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN
      RAISE EXCEPTION 'Modification du statut de vérification interdite';
    END IF;
    IF NEW.verifie_par IS DISTINCT FROM OLD.verifie_par THEN
      RAISE EXCEPTION 'Modification du vérificateur interdite';
    END IF;
    IF NEW.verifie_le IS DISTINCT FROM OLD.verifie_le THEN
      RAISE EXCEPTION 'Modification de la date de vérification interdite';
    END IF;
    IF NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet THEN
      RAISE EXCEPTION 'Modification du motif de rejet interdite';
    END IF;
    IF NEW.est_critique IS DISTINCT FROM OLD.est_critique THEN
      RAISE EXCEPTION 'Modification du caractère critique interdite';
    END IF;
    IF NEW.rappel_j7_envoye IS DISTINCT FROM OLD.rappel_j7_envoye
       OR NEW.rappel_j30_envoye IS DISTINCT FROM OLD.rappel_j30_envoye
       OR NEW.rappel_expire_envoye IS DISTINCT FROM OLD.rappel_expire_envoye THEN
      RAISE EXCEPTION 'Modification des rappels interdite';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_document_verification ON public.documents_soignants;
CREATE TRIGGER trg_protect_document_verification
  BEFORE UPDATE ON public.documents_soignants
  FOR EACH ROW EXECUTE FUNCTION fn_protect_document_verification();

-- P1: Fix demandes_rgpd — remplacer ALL par policies séparées
DROP POLICY IF EXISTS pol_rgpd_all ON public.demandes_rgpd;

CREATE POLICY pol_rgpd_select ON public.demandes_rgpd
  FOR SELECT TO authenticated
  USING (demandeur_id = auth.uid() OR est_admin());

CREATE POLICY pol_rgpd_insert ON public.demandes_rgpd
  FOR INSERT TO authenticated
  WITH CHECK (demandeur_id = auth.uid() AND statut = 'EN_ATTENTE');

CREATE POLICY pol_rgpd_update ON public.demandes_rgpd
  FOR UPDATE TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

CREATE POLICY pol_rgpd_delete ON public.demandes_rgpd
  FOR DELETE TO authenticated
  USING (est_admin());

-- P1: Renforcer conversions_liberal INSERT
DROP POLICY IF EXISTS pol_conv_insert ON public.conversions_liberal;
CREATE POLICY pol_conv_insert ON public.conversions_liberal
  FOR INSERT TO authenticated
  WITH CHECK (
    est_admin() OR (
      soignant_id = auth.uid()
      AND free_transition_eligible = false
      AND taux_prise_en_charge = 0
      AND montant_pris_en_charge = 0
      AND statut = 'INITIE'
      AND indy_active = false
      AND qonto_active = false
      AND macsf_active = false
      AND guide_pdf_genere = false
      AND complete_le IS NULL
      AND indy_lien_affiliation IS NULL
      AND qonto_lien_affiliation IS NULL
      AND macsf_lien_affiliation IS NULL
    )
  );