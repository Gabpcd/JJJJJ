-- J2.1.B — Onboarding étab : contrat service Jolene + RIB + contrat travail SALARIE

-- 1. Table contrats_service_signatures
CREATE TABLE IF NOT EXISTS public.contrats_service_signatures (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
  version text NOT NULL DEFAULT 'v1.0',
  signed_at timestamptz NOT NULL DEFAULT now(),
  ip_address text,
  user_agent text,
  contenu_hash text,
  pdf_url text,
  revoked_at timestamptz,
  motif_revocation text,
  cree_le timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_contrat_service_actif
  ON public.contrats_service_signatures (etablissement_id) WHERE revoked_at IS NULL;
ALTER TABLE public.contrats_service_signatures ENABLE ROW LEVEL SECURITY;
CREATE POLICY css_select ON public.contrats_service_signatures FOR SELECT
  TO authenticated USING (etablissement_id = mon_etablissement_id() OR est_admin());
CREATE POLICY css_insert ON public.contrats_service_signatures FOR INSERT
  TO authenticated WITH CHECK (etablissement_id = mon_etablissement_id());
GRANT SELECT, INSERT ON public.contrats_service_signatures TO authenticated;

-- 2. Colonnes etablissements
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS contrat_service_signe boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS contrat_service_signe_le timestamptz,
  ADD COLUMN IF NOT EXISTS rib_s3_key text;

-- 3. Table contrats_travail_missions
CREATE TABLE IF NOT EXISTS public.contrats_travail_missions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL REFERENCES public.missions(id),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
  soignant_id uuid REFERENCES public.soignants(id),
  pdf_s3_key text NOT NULL,
  nom_fichier text,
  taille_octets integer,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  uploaded_by uuid NOT NULL,
  cree_le timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_contrat_travail_mission
  ON public.contrats_travail_missions (mission_id);
ALTER TABLE public.contrats_travail_missions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ctm_select ON public.contrats_travail_missions FOR SELECT
  TO authenticated USING (etablissement_id = mon_etablissement_id() OR soignant_id = auth.uid() OR est_admin());
CREATE POLICY ctm_insert ON public.contrats_travail_missions FOR INSERT
  TO authenticated WITH CHECK (etablissement_id = mon_etablissement_id());
GRANT SELECT, INSERT ON public.contrats_travail_missions TO authenticated;

-- 4. RPC fn_signer_contrat_service
CREATE OR REPLACE FUNCTION public.fn_signer_contrat_service(
  p_version text, p_ip text, p_user_agent text, p_contenu_hash text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_etab_id uuid := mon_etablissement_id(); v_existing uuid;
BEGIN
  IF v_etab_id IS NULL THEN RETURN jsonb_build_object('success',false,'error','Accès refusé'); END IF;
  SELECT id INTO v_existing FROM contrats_service_signatures WHERE etablissement_id=v_etab_id AND revoked_at IS NULL;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('success',false,'error','Contrat déjà signé et actif'); END IF;
  INSERT INTO contrats_service_signatures (etablissement_id, version, ip_address, user_agent, contenu_hash) VALUES (v_etab_id, p_version, p_ip, p_user_agent, p_contenu_hash);
  PERFORM set_config('app.internal_operation','true',true);
  UPDATE etablissements SET contrat_service_signe=true, contrat_service_signe_le=now() WHERE id=v_etab_id;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id:=auth.uid(), p_type_acteur:='ADMIN_ETABLISSEMENT', p_action:='CONTRAT_SIGNE', p_type_ressource:='etablissement', p_id_ressource:=v_etab_id, p_details:=jsonb_build_object('type','contrat_service_jolene','version',p_version));
  RETURN jsonb_build_object('success',true);
END; $$;
GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_service(text,text,text,text) TO authenticated;

-- 5. RPC fn_revoquer_contrat_service
CREATE OR REPLACE FUNCTION public.fn_revoquer_contrat_service(p_motif text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_etab_id uuid := mon_etablissement_id(); v_sig_id uuid;
BEGIN
  IF v_etab_id IS NULL THEN RETURN jsonb_build_object('success',false,'error','Accès refusé'); END IF;
  SELECT id INTO v_sig_id FROM contrats_service_signatures WHERE etablissement_id=v_etab_id AND revoked_at IS NULL;
  IF v_sig_id IS NULL THEN RETURN jsonb_build_object('success',false,'error','Aucun contrat actif'); END IF;
  UPDATE contrats_service_signatures SET revoked_at=now(), motif_revocation=p_motif WHERE id=v_sig_id;
  PERFORM set_config('app.internal_operation','true',true);
  UPDATE etablissements SET contrat_service_signe=false, contrat_service_signe_le=NULL WHERE id=v_etab_id;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id:=auth.uid(), p_type_acteur:='ADMIN_ETABLISSEMENT', p_action:='CONTRAT_SIGNE', p_type_ressource:='etablissement', p_id_ressource:=v_etab_id, p_details:=jsonb_build_object('type','contrat_service_jolene_revoque','motif',p_motif));
  RETURN jsonb_build_object('success',true,'message','Contrat révoqué.');
END; $$;
GRANT EXECUTE ON FUNCTION public.fn_revoquer_contrat_service(text) TO authenticated;

-- 6. Trigger bloquer mission si onboarding incomplet
CREATE OR REPLACE FUNCTION public.fn_trg_verifier_onboarding_etab()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_etab RECORD;
BEGIN
  IF est_admin() THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('app.internal_operation',true),'') = 'true' THEN RETURN NEW; END IF;
  SELECT contrat_service_signe, rib_s3_key INTO v_etab FROM etablissements WHERE id=NEW.etablissement_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  IF NOT COALESCE(v_etab.contrat_service_signe,false) THEN
    RAISE EXCEPTION 'Inscription incomplète : vous devez signer le contrat de service Jolene avant de publier des missions. Rendez-vous sur /etablissement/finaliser-inscription.' USING ERRCODE='check_violation';
  END IF;
  IF v_etab.rib_s3_key IS NULL OR v_etab.rib_s3_key = '' THEN
    RAISE EXCEPTION 'Inscription incomplète : vous devez fournir un RIB avant de publier des missions. Rendez-vous sur /etablissement/finaliser-inscription.' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_verifier_onboarding_etab ON public.missions;
CREATE TRIGGER trg_verifier_onboarding_etab BEFORE INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION public.fn_trg_verifier_onboarding_etab();

-- 7. Backfill étabs existants vérifiés
UPDATE public.etablissements
SET contrat_service_signe=true, contrat_service_signe_le=cree_le, rib_s3_key='legacy/auto-backfill'
WHERE contrat_service_signe=false AND peut_publier_missions=true;

NOTIFY pgrst, 'reload schema';
