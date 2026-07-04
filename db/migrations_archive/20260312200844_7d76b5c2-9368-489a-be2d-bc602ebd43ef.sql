
-- 1. CONTRATS_MISSION: Trigger to protect establishment signature fields from soignant tampering
CREATE OR REPLACE FUNCTION fn_protect_contrat_integrity()
RETURNS TRIGGER AS $$
BEGIN
  -- If caller is the soignant, only allow their own signature fields
  IF OLD.soignant_id = auth.uid()
     AND NOT public.est_admin()
     AND NOT public.est_admin_etablissement() THEN
    NEW.signature_etablissement := OLD.signature_etablissement;
    NEW.signature_etablissement_le := OLD.signature_etablissement_le;
    NEW.signature_image_etablissement := OLD.signature_image_etablissement;
    NEW.signature_ip_etablissement := OLD.signature_ip_etablissement;
    NEW.signature_navigateur_etablissement := OLD.signature_navigateur_etablissement;
    NEW.contenu_html := OLD.contenu_html;
    NEW.statut := OLD.statut;
    NEW.numero_contrat := OLD.numero_contrat;
    NEW.type_contrat := OLD.type_contrat;
    NEW.etablissement_id := OLD.etablissement_id;
    NEW.mission_id := OLD.mission_id;
    NEW.pdf_cle_s3 := OLD.pdf_cle_s3;
    NEW.yousign_procedure_id := OLD.yousign_procedure_id;
    NEW.yousign_document_id := OLD.yousign_document_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_protect_contrat_integrity ON public.contrats_mission;
CREATE TRIGGER trg_protect_contrat_integrity
  BEFORE UPDATE ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION fn_protect_contrat_integrity();

-- 2. SUIVI_CONVERSION_3200H: Restrict to SELECT only for soignants
DROP POLICY IF EXISTS pol_3200h_all ON public.suivi_conversion_3200h;

CREATE POLICY pol_3200h_select ON public.suivi_conversion_3200h
  FOR SELECT TO authenticated
  USING ((soignant_id = auth.uid()) OR est_admin());

CREATE POLICY pol_3200h_insert ON public.suivi_conversion_3200h
  FOR INSERT TO authenticated
  WITH CHECK (est_admin());

CREATE POLICY pol_3200h_update ON public.suivi_conversion_3200h
  FOR UPDATE TO authenticated
  USING (est_admin());

CREATE POLICY pol_3200h_delete ON public.suivi_conversion_3200h
  FOR DELETE TO authenticated
  USING (est_admin());
