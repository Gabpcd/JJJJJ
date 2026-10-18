-- Définitions capturées en PROD le 18/10/2026 ; contrôle avant toute mutation.
CREATE TEMP TABLE _avoirs_imputation_attendu(signature text PRIMARY KEY,ancien text,nouveau text,proprietaire text,acl text,config text[]) ON COMMIT DROP;
INSERT INTO _avoirs_imputation_attendu VALUES
('public.dec_bloquer_paiement_manuel_facture()','c7ad4ea15a634d396e3b2b08f7953f68','bb9b7ee7b11322828232821180816cdd','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.dec_bloquer_si_facture_impayee()','ad484e37b5d7b5e9c0c1ffacbc51adfd','85d154560fd0e8d5337cbd6f73f3c2d7','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.dec_idempotence_facture_payee()','c6a36643e3c9b1bec0c170fe306d64c8','43c540dae094cce74de9922ac3810455','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_admin_kpi()','e13823ddd55568e2a4428ba656ff7d58','92d3f5680a9dd94814ac9b6fd116a9bc','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_admin_resoudre_litige_salarie(uuid,text,text,numeric,numeric,text)','139ca12a3fcbff5bd5f65074d3242b53','f07f34e05904c5f7c233a9477b6cdd1c','postgres','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_admin_suspendre_utilisateur(text,uuid,boolean,text)','7eea57c5ad273167a92235f18e9494d2','3e7f91a29f11c8e670812cf75582d00a','postgres','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',ARRAY['search_path=pg_catalog, public, auth']::text[]),
('public.fn_alerter_paiements_retard()','6d20e4848c3f57ca274b8d6c3e6e12d9','24d11b16c5d97baed4a8a7403f1a3cd1','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_auto_facturation_mensuelle()','b2fd6fc7ecb181d6c19690aa1a8f1880','19283979ee6b7b24b1a293b02fc28056','postgres','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_blocage_publication_etab(uuid)','a167d587f55458ff26b3421741beb1f2','e191bce36ffa5f78f5e964a89dcffaef','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=pg_catalog, public']::text[]),
('public.fn_confirmer_virement_admin(uuid)','0c8344864a6b3ba7fbf2b359864ec444','6a2e01ed08cc3c2a65ee05520aaccfff','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_deposer_chorus(uuid,text)','6e08306db1cac7de963a05ff2bb48269','3a42d1cf3e8bb1aecedd28c4e0782cae','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_detail_facture_internal_20260801(uuid)','546e761f7492751f66a04d0838f099a8','fb83ff6c3c71afafe64fdb881275595d','postgres','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, public, auth']::text[]),
('public.fn_email_factures_impayees()','1c01d360267c7f4842a3f7ec44a8c8b3','6c8766aa9a96e6c16f7ff71107f325d6','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_generer_facture_mensuelle_internal_20260801(uuid)','648c0a780609cc69fe276bb37a920b83','d8b46898c57ed2929028e0cfe273abb7','postgres','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, public, auth']::text[]),
('public.fn_gerer_blocage_etabs()','0507950161f5becd5d07ebc6a4b85d8a','8e44c5231fa1d12ea9bd73fe346c8077','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_mes_factures_internal_20260801()','0557af64bf0a322298743d95f120a9b6','47a4615a5c0bc8f5da64e1fd059bf2b2','postgres','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, public, auth']::text[]),
('public.fn_obligations_financieres_internal_20260801()','fb7c4e93ed8946a7713143f344d83d29','85d7c4978638907bab8682cc39186f9d','postgres','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, public, auth']::text[]),
('public.fn_preparer_avoir_commission_honoraires(uuid)','972bff7ed6b0beedc598d2cb815f2130','78993e08045e2c062fa32d0cddecbfdb','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public, pg_temp']::text[]),
('public.fn_recalculer_commissions_post_litige()','bab5c4d69311a6fc38c41ff42cfdf68d','283ca5d6588ecbf94ba1bd34f58f747d','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_reserver_email_facturation(uuid)','5cc8a1f5009992f54e86b0951e5e66e6','def58474fedb532f761e22006cdcf2a1','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=""']::text[]),
('public.fn_reverifier_blocage_etab()','40464fe25dcc1a70cb4afead07bd6753','f309239d07526a76cb280815a3fcd07d','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_stats_dashboard_etablissement()','a006212127f945e5180899aa1f44a521','3b6e1d770f15c3d788236f2b57b77a9a','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_supprimer_mon_compte_etablissement()','35b630a12ed0f755592fdc431031b8cc','a43978aee09ef1ae4a157dbee9911b2f','postgres','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',ARRAY['search_path=public, extensions']::text[]),
('public.fn_trg_parrainage_commission_encaissee()','bc8492fce01b4cb6b1e59edfa8cc3fd3','1a2aa61035fb5421cd5151b6cdcc9dd9','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public']::text[]),
('public.fn_trg_valider_parrainage_etab_commission()','fb20e460bfa7590d948978899edd3815','41388ddfd76c23e618e6c4bf5881650a','postgres','{postgres=X/postgres,service_role=X/postgres}',ARRAY['search_path=public, extensions']::text[]),
('private.fn_admission_virement_commission(uuid)','ec9edafb433d0f53ace64ae109350ed9','cefb5932e5f9d403f48d76465abc22d4','postgres','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, public']::text[]),
('private.mettre_emission_facture_en_file()','27f0ca3f35ab5f2d4f240948fdb0f7e7','7e7ff62fa198c86f2b899cbb4ba4ccca','postgres','{postgres=X/postgres}',ARRAY['search_path=""']::text[]),
('private.mettre_paiement_facture_en_file()','23f2abb1babdfeb6014fac55f52922dd','8107e31657ff4412f563e14434b83e1f','postgres','{postgres=X/postgres}',ARRAY['search_path=""']::text[]);
CREATE TEMP TABLE _avoirs_inventory_attendu(signature text PRIMARY KEY,categorie text,ancien text) ON COMMIT DROP;
INSERT INTO _avoirs_inventory_attendu VALUES
('fn_admin_kpi()','ADMIN_EST_ADMIN_VALIDE','e13823ddd55568e2a4428ba656ff7d58'),
('fn_admin_resoudre_litige_salarie(uuid,text,text,numeric,numeric,text)','ADMIN_EST_ADMIN_VALIDE','139ca12a3fcbff5bd5f65074d3242b53'),
('fn_admin_suspendre_utilisateur(text,uuid,boolean,text)','ADMIN_EST_ADMIN_VALIDE','7eea57c5ad273167a92235f18e9494d2'),
('fn_auto_facturation_mensuelle()','RPC_UTILISATEUR_AUTH_INTERNE','b2fd6fc7ecb181d6c19690aa1a8f1880'),
('fn_confirmer_virement_admin(uuid)','MIXTE_TENANT_ADMIN','0c8344864a6b3ba7fbf2b359864ec444'),
('fn_declarer_virement(uuid,text)','MIXTE_TENANT_ADMIN','d9e957341a75790d1c368c850731d770'),
('fn_deposer_chorus(uuid,text)','MIXTE_TENANT_ADMIN','6e08306db1cac7de963a05ff2bb48269'),
('fn_generer_facture_mensuelle(uuid)','MIXTE_TENANT_ADMIN','18bc7e1ff9b907b5a1a1ea93bd5548fe'),
('fn_modalites_reglement_commission(uuid)','MIXTE_TENANT_ADMIN','91a904be229d21680ef42ade6a769163'),
('fn_preparer_avoir_commission_honoraires(uuid)','SERVICE_ONLY_REVOQUE','972bff7ed6b0beedc598d2cb815f2130'),
('fn_reserver_email_facturation(uuid)','SERVICE_ONLY_REVOQUE','5cc8a1f5009992f54e86b0951e5e66e6'),
('fn_reverifier_blocage_etab()','RPC_UTILISATEUR_AUTH_INTERNE','40464fe25dcc1a70cb4afead07bd6753'),
('fn_stats_dashboard_etablissement()','RPC_UTILISATEUR_AUTH_INTERNE','a006212127f945e5180899aa1f44a521'),
('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','SERVICE_ONLY_REVOQUE','b745cc054c57ea9ec14a983676493fd6'),
('fn_supprimer_mon_compte_etablissement()','RPC_UTILISATEUR_AUTH_INTERNE','35b630a12ed0f755592fdc431031b8cc');
DO $avant$
DECLARE e record; p record;
BEGIN
 FOR e IN SELECT * FROM _avoirs_imputation_attendu LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(e.signature);
  IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM e.ancien OR pg_get_userbyid(p.proowner) IS DISTINCT FROM e.proprietaire
    OR p.proacl::text IS DISTINCT FROM e.acl OR p.proconfig IS DISTINCT FROM e.config THEN
    RAISE EXCEPTION 'AVOIRS_IMPUTATION_SOURCE_DRIFT: %',e.signature; END IF;
  IF (SELECT count(*) FROM private.security_definer_inventory i WHERE i.signature IN (e.signature,replace(e.signature,'public.','')))
    <> (SELECT count(*) FROM _avoirs_inventory_attendu i WHERE i.signature IN (e.signature,replace(e.signature,'public.','')))
    OR EXISTS(SELECT 1 FROM _avoirs_inventory_attendu a WHERE a.signature IN(e.signature,replace(e.signature,'public.',''))
      AND NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i WHERE i.signature=a.signature
        AND i.categorie=a.categorie AND i.definition_md5=a.ancien AND i.definition_md5=e.ancien)) THEN
    RAISE EXCEPTION 'AVOIRS_IMPUTATION_INVENTORY_DRIFT: %',e.signature; END IF;
 END LOOP;
END $avant$;
-- Imputation TTC des seuls avoirs de commission dont l'origine est démontrée.
-- Aucun HT/TVA/TTC documentaire n'est réécrit, aucun remboursement n'est créé.
ALTER TABLE public.factures
  ADD COLUMN montant_avoirs_imputes numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN montant_a_payer numeric(10,2) GENERATED ALWAYS AS
    (montant_ttc - montant_avoirs_imputes) STORED,
  ADD COLUMN rapprochement_paiement_requis boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT factures_imputation_bornes CHECK (
    montant_avoirs_imputes >= 0 AND montant_avoirs_imputes <= montant_ttc
    AND (montant_avoirs_imputes = 0 OR type_document = 'FACTURE'));
ALTER TABLE public.factures DROP CONSTRAINT factures_mode_paiement_check;
ALTER TABLE public.factures ADD CONSTRAINT factures_mode_paiement_check
  CHECK (mode_paiement IN ('STRIPE','VIREMENT','CHORUS_PRO','AVOIR'));
ALTER TABLE public.factures ADD CONSTRAINT factures_reglement_avoir_coherent CHECK (
  mode_paiement IS DISTINCT FROM 'AVOIR' OR (
    type_document = 'FACTURE' AND statut IS NOT DISTINCT FROM 'PAYEE' AND date_paiement IS NOT NULL
    AND montant_ttc > 0 AND montant_avoirs_imputes = montant_ttc
    AND stripe_invoice_id IS NULL AND stripe_payment_intent_id IS NULL
    AND stripe_hosted_url IS NULL AND virement_reference IS NULL));
COMMENT ON COLUMN public.factures.montant_a_payer IS
  'Montant externe convenu : TTC moins avoirs imputés. Ne devient pas zéro après paiement ; le solde à payer UI vaut zéro pour PAYEE.';
COMMENT ON COLUMN public.factures.rapprochement_paiement_requis IS
  'Anomalie financière à rapprocher : suspend les nouvelles demandes de règlement sans réécrire dette, paiement ou allocations.';

CREATE TABLE private.avoirs_commission_sources (
  avoir_id uuid PRIMARY KEY REFERENCES public.factures(id),
  facture_origine_id uuid NOT NULL REFERENCES public.factures(id),
  mission_id uuid NOT NULL REFERENCES public.missions(id),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
  montant_cents bigint NOT NULL CHECK (montant_cents > 0),
  producteur text NOT NULL CHECK (producteur IN ('LITIGE_SALARIE','RECALCUL_COMMISSION','LITIGE_HONORAIRES')),
  preuve jsonb NOT NULL,
  inscrite_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX avoirs_commission_sources_etab ON private.avoirs_commission_sources(etablissement_id,inscrite_le,avoir_id);
CREATE TABLE private.avoirs_commission_mouvements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avoir_id uuid NOT NULL REFERENCES private.avoirs_commission_sources(avoir_id),
  facture_id uuid NOT NULL REFERENCES public.factures(id),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
  nature text NOT NULL CHECK (nature IN ('IMPUTATION','RESTITUTION')),
  montant_cents bigint NOT NULL CHECK (montant_cents > 0),
  imputation_origine_id uuid REFERENCES private.avoirs_commission_mouvements(id),
  cree_le timestamptz NOT NULL DEFAULT now(),
  CHECK ((nature='IMPUTATION' AND imputation_origine_id IS NULL)
    OR (nature='RESTITUTION' AND imputation_origine_id IS NOT NULL))
);
CREATE UNIQUE INDEX avoirs_commission_imputation_unique ON private.avoirs_commission_mouvements(avoir_id,facture_id) WHERE nature='IMPUTATION';
CREATE UNIQUE INDEX avoirs_commission_restitution_unique ON private.avoirs_commission_mouvements(imputation_origine_id) WHERE nature='RESTITUTION';
CREATE INDEX avoirs_commission_mouvements_facture ON private.avoirs_commission_mouvements(facture_id);
ALTER TABLE private.avoirs_commission_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.avoirs_commission_sources FORCE ROW LEVEL SECURITY;
ALTER TABLE private.avoirs_commission_mouvements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.avoirs_commission_mouvements FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.avoirs_commission_sources,private.avoirs_commission_mouvements FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fn_avoirs_commission_immutables()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $immutable$
BEGIN
  RAISE EXCEPTION 'AVOIR_JOURNAL_IMMUABLE' USING ERRCODE='23514';
END $immutable$;
CREATE TRIGGER sources_immuables BEFORE UPDATE OR DELETE ON private.avoirs_commission_sources
FOR EACH ROW EXECUTE FUNCTION private.fn_avoirs_commission_immutables();
CREATE TRIGGER mouvements_immuables BEFORE UPDATE OR DELETE ON private.avoirs_commission_mouvements
FOR EACH ROW EXECUTE FUNCTION private.fn_avoirs_commission_immutables();

CREATE FUNCTION private.fn_inscrire_avoir_commission(p_avoir_id uuid,p_mission_id uuid,p_producteur text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $source$
DECLARE a public.factures; o public.factures; m public.missions; preuve_separee boolean;
BEGIN
  SELECT * INTO a FROM public.factures WHERE id=p_avoir_id;
  PERFORM pg_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||a.etablissement_id::text,0));
  SELECT * INTO a FROM public.factures WHERE id=p_avoir_id FOR UPDATE;
  SELECT * INTO m FROM public.missions WHERE id=p_mission_id;
  SELECT * INTO o FROM public.factures WHERE id=a.facture_precedente_id;
  preuve_separee := m.type_contrat_applique::text='LIBERAL' AND o.statut='PAYEE'
    AND o.mode_paiement='VIREMENT' AND o.date_paiement IS NOT NULL
    AND o.virement_confirme_le IS NOT NULL AND o.virement_confirme_par IS NOT NULL
    AND nullif(btrim(o.virement_reference),'') IS NOT NULL;
  IF a.id IS NULL OR a.type_document IS DISTINCT FROM 'AVOIR' OR a.statut IS DISTINCT FROM 'EMISE'
    OR a.montant_ttc <= 0
    OR a.rapprochement_paiement_requis OR o.id IS NULL
    OR o.type_document NOT IN ('FACTURE','FACTURE_COMPLEMENTAIRE')
    OR o.statut IS NULL OR o.statut NOT IN ('EMISE','EN_RETARD','VIREMENT_DECLARE','PAYEE')
    OR o.rapprochement_paiement_requis
    OR o.etablissement_id IS DISTINCT FROM a.etablissement_id
    OR m.id IS NULL OR m.type_contrat_applique IS NULL OR m.etablissement_id IS DISTINCT FROM a.etablissement_id
    OR NOT (coalesce(preuve_separee,false) OR (m.type_contrat_applique::text='SALARIE'
      AND a.facture_honoraire_id IS NULL AND o.facture_honoraire_id IS NULL
      AND NOT EXISTS(SELECT 1 FROM public.factures_honoraires h WHERE h.mission_id=m.id)))
    OR (m.facture_id IS DISTINCT FROM o.id AND o.mission_id IS DISTINCT FROM m.id)
    OR (a.mission_id IS NOT NULL AND a.mission_id<>m.id)
    OR p_producteur NOT IN ('LITIGE_SALARIE','RECALCUL_COMMISSION','LITIGE_HONORAIRES')
    OR EXISTS(SELECT 1 FROM public.stripe_transfers t WHERE t.mission_id=m.id OR t.facture_id=o.id)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow e WHERE e.mission_id=m.id)
    OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c
      WHERE c.resource_key IN ('FACTURE:'||o.id::text,'MISSION:'||m.id::text)
        AND c.flow IN ('CONNECT_MISSION','CONNECT_INVOICE','LEGACY_UNKNOWN'))
  THEN
    RETURN jsonb_build_object('eligible',false,'motif','ORIGINE_NON_ETABLIE',
      'message','Avoir émis. Son imputation automatique nécessite la vérification de son origine et des règlements déjà effectués.');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||a.etablissement_id::text,0));
  INSERT INTO private.avoirs_commission_sources(avoir_id,facture_origine_id,mission_id,etablissement_id,montant_cents,producteur,preuve)
  VALUES(a.id,o.id,m.id,a.etablissement_id,(a.montant_ttc*100)::bigint,p_producteur,
    jsonb_build_object('version',1,'type_contrat',m.type_contrat_applique::text,'commission_payee_separement',coalesce(preuve_separee,false),'origine_statut',o.statut,
      'facture_origine_id',o.id,'mission_id',m.id,'etablissement_id',a.etablissement_id,
      'avoir_ttc',a.montant_ttc,'origine_ttc',o.montant_ttc,'source','EMISSION_SERVEUR',
      'mode_paiement_origine',o.mode_paiement,'date_paiement_origine',o.date_paiement,
      'virement_reference',o.virement_reference,'virement_confirme_le',o.virement_confirme_le,
      'virement_confirme_par',o.virement_confirme_par))
  ON CONFLICT(avoir_id) DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM private.avoirs_commission_sources s WHERE s.avoir_id=a.id
    AND s.facture_origine_id=o.id AND s.mission_id=m.id AND s.etablissement_id=a.etablissement_id
    AND s.montant_cents=(a.montant_ttc*100)::bigint AND s.producteur=p_producteur) THEN
    RAISE EXCEPTION 'AVOIR_SOURCE_CONFLIT';
  END IF;
  RETURN jsonb_build_object('eligible',true,
    'message','Avoir disponible pour imputation sur une prochaine facture mensuelle éligible.');
END $source$;

CREATE FUNCTION private.fn_garder_mouvement_avoir_commission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $movement$
DECLARE s private.avoirs_commission_sources; f public.factures; a public.factures;
  original private.avoirs_commission_mouvements; consomme bigint; affecte bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||NEW.etablissement_id::text,0));
  SELECT * INTO STRICT s FROM private.avoirs_commission_sources WHERE avoir_id=NEW.avoir_id FOR UPDATE;
  SELECT * INTO STRICT a FROM public.factures WHERE id=NEW.avoir_id FOR UPDATE;
  SELECT * INTO STRICT f FROM public.factures WHERE id=NEW.facture_id FOR UPDATE;
  IF s.etablissement_id<>NEW.etablissement_id OR f.etablissement_id<>NEW.etablissement_id
    OR a.etablissement_id<>NEW.etablissement_id OR f.id=a.id THEN RAISE EXCEPTION 'AVOIR_ETABLISSEMENT_DIFFERENT'; END IF;
  IF NEW.nature='IMPUTATION' THEN
    IF f.type_document IS DISTINCT FROM 'FACTURE' OR f.statut IS DISTINCT FROM 'BROUILLON' OR f.mission_id IS NOT NULL
      OR f.facture_honoraire_id IS NOT NULL OR f.stripe_invoice_id IS NOT NULL
      OR f.stripe_payment_intent_id IS NOT NULL OR f.stripe_hosted_url IS NOT NULL
      OR f.virement_reference IS NOT NULL OR f.rapprochement_paiement_requis
      OR a.statut NOT IN ('EMISE','EN_RETARD') OR a.type_document<>'AVOIR'
      OR a.rapprochement_paiement_requis OR a.montant_ttc*100<>s.montant_cents
      OR EXISTS(SELECT 1 FROM public.stripe_transfers t WHERE t.mission_id=s.mission_id OR t.facture_id=s.facture_origine_id)
      OR EXISTS(SELECT 1 FROM public.paiements_escrow e WHERE e.mission_id=s.mission_id)
      OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c
        WHERE c.resource_key IN ('FACTURE:'||s.facture_origine_id::text,'MISSION:'||s.mission_id::text)
          AND c.flow IN ('CONNECT_MISSION','CONNECT_INVOICE','LEGACY_UNKNOWN'))
      OR EXISTS(SELECT 1 FROM public.factures o WHERE o.id=s.facture_origine_id
        AND (o.rapprochement_paiement_requis OR o.statut IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')))
      OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c WHERE c.resource_key='FACTURE:'||f.id::text
        OR c.resource_key IN (SELECT 'MISSION:'||m.id::text FROM public.missions m WHERE m.facture_id=f.id))
    THEN RAISE EXCEPTION 'AVOIR_CIBLE_NON_ADMISSIBLE'; END IF;
    SELECT coalesce(sum(CASE nature WHEN 'IMPUTATION' THEN montant_cents ELSE -montant_cents END),0)
      INTO consomme FROM private.avoirs_commission_mouvements WHERE avoir_id=a.id;
    SELECT coalesce(sum(montant_cents),0) INTO affecte FROM private.avoirs_commission_mouvements
      WHERE facture_id=f.id AND nature='IMPUTATION';
    IF consomme+NEW.montant_cents>s.montant_cents OR affecte+NEW.montant_cents>f.montant_ttc*100 THEN
      RAISE EXCEPTION 'AVOIR_MONTANT_DEPASSE'; END IF;
  ELSE
    SELECT * INTO STRICT original FROM private.avoirs_commission_mouvements WHERE id=NEW.imputation_origine_id;
    IF original.nature<>'IMPUTATION' OR original.avoir_id<>NEW.avoir_id OR original.facture_id<>NEW.facture_id
      OR original.etablissement_id<>NEW.etablissement_id OR original.montant_cents<>NEW.montant_cents
      OR f.statut NOT IN ('ANNULEE','REMPLACEE') OR f.date_paiement IS NOT NULL
      OR f.stripe_invoice_id IS NOT NULL OR f.stripe_payment_intent_id IS NOT NULL
      OR f.stripe_hosted_url IS NOT NULL OR f.virement_reference IS NOT NULL
      OR f.rapprochement_paiement_requis
      OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c WHERE c.resource_key='FACTURE:'||f.id::text)
    THEN RAISE EXCEPTION 'AVOIR_RESTITUTION_NON_ADMISSIBLE'; END IF;
  END IF;
  RETURN NEW;
END $movement$;
CREATE TRIGGER mouvement_avoir_garde BEFORE INSERT ON private.avoirs_commission_mouvements
FOR EACH ROW EXECUTE FUNCTION private.fn_garder_mouvement_avoir_commission();

CREATE FUNCTION private.fn_emettre_facture_mensuelle_avec_avoirs(p_facture_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $allocate$
DECLARE f public.factures; s record; reste bigint; a_prendre bigint; total bigint:=0;
BEGIN
  SELECT * INTO STRICT f FROM public.factures WHERE id=p_facture_id;
  PERFORM pg_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||f.etablissement_id::text,0));
  SELECT * INTO STRICT f FROM public.factures WHERE id=p_facture_id FOR UPDATE;
  IF f.statut IN ('EMISE','PAYEE') AND EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements WHERE facture_id=f.id) THEN
    RETURN jsonb_build_object('success',true,'montant_avoirs_imputes',f.montant_avoirs_imputes,'montant_a_payer',f.montant_a_payer,'existing',true);
  END IF;
  IF f.type_document IS DISTINCT FROM 'FACTURE' OR f.statut IS DISTINCT FROM 'BROUILLON' OR f.mission_id IS NOT NULL
    OR f.facture_honoraire_id IS NOT NULL OR f.montant_ttc<=0
    OR f.stripe_invoice_id IS NOT NULL OR f.stripe_payment_intent_id IS NOT NULL
    OR f.stripe_hosted_url IS NOT NULL OR f.virement_reference IS NOT NULL
    OR f.rapprochement_paiement_requis
    OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c WHERE c.resource_key='FACTURE:'||f.id::text
      OR c.resource_key IN (SELECT 'MISSION:'||m.id::text FROM public.missions m WHERE m.facture_id=f.id))
    OR NOT EXISTS(SELECT 1 FROM public.missions m WHERE m.facture_id=f.id)
    OR EXISTS(SELECT 1 FROM public.missions m WHERE m.facture_id=f.id AND
      (m.etablissement_id<>f.etablissement_id OR m.type_contrat_applique::text IS DISTINCT FROM 'SALARIE'
          OR EXISTS(SELECT 1 FROM public.stripe_transfers t WHERE t.mission_id=m.id)
       OR EXISTS(SELECT 1 FROM public.paiements_escrow e WHERE e.mission_id=m.id)))
  THEN
    -- Une facture hors périmètre reste émise à son montant documentaire.
    IF f.type_document='FACTURE' AND f.statut='BROUILLON' AND f.montant_avoirs_imputes=0 THEN
      UPDATE public.factures SET statut='EMISE' WHERE id=f.id;
      RETURN jsonb_build_object('success',true,'montant_avoirs_imputes',0,'montant_a_payer',f.montant_ttc,'eligible',false);
    END IF;
    RAISE EXCEPTION 'AVOIR_EMISSION_NON_ADMISSIBLE';
  END IF;
  reste:=(f.montant_ttc*100)::bigint;
  FOR s IN SELECT src.*,a.date_emission,
      src.montant_cents-coalesce((SELECT sum(CASE j.nature WHEN 'IMPUTATION' THEN j.montant_cents ELSE -j.montant_cents END)
        FROM private.avoirs_commission_mouvements j WHERE j.avoir_id=src.avoir_id),0) disponible
    FROM private.avoirs_commission_sources src JOIN public.factures a ON a.id=src.avoir_id
    JOIN public.factures o ON o.id=src.facture_origine_id
    WHERE src.etablissement_id=f.etablissement_id AND a.statut IN ('EMISE','EN_RETARD')
      AND NOT a.rapprochement_paiement_requis AND NOT o.rapprochement_paiement_requis
      AND o.statut IN ('EMISE','EN_RETARD','VIREMENT_DECLARE','PAYEE')
      AND NOT EXISTS(SELECT 1 FROM public.stripe_transfers t WHERE t.mission_id=src.mission_id OR t.facture_id=src.facture_origine_id)
      AND NOT EXISTS(SELECT 1 FROM public.paiements_escrow e WHERE e.mission_id=src.mission_id)
      AND NOT EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c
        WHERE c.resource_key IN ('FACTURE:'||src.facture_origine_id::text,'MISSION:'||src.mission_id::text)
          AND c.flow IN ('CONNECT_MISSION','CONNECT_INVOICE','LEGACY_UNKNOWN'))
    ORDER BY a.date_emission,src.avoir_id
  LOOP
    EXIT WHEN reste=0;
    a_prendre:=least(reste,s.disponible);
    IF a_prendre<=0 THEN CONTINUE; END IF;
    INSERT INTO private.avoirs_commission_mouvements(avoir_id,facture_id,etablissement_id,nature,montant_cents)
    VALUES(s.avoir_id,f.id,f.etablissement_id,'IMPUTATION',a_prendre);
    total:=total+a_prendre; reste:=reste-a_prendre;
  END LOOP;
  UPDATE public.factures SET montant_avoirs_imputes=total/100.0,
    statut=CASE WHEN reste=0 THEN 'PAYEE' ELSE 'EMISE' END,
    mode_paiement=CASE WHEN reste=0 THEN 'AVOIR' ELSE mode_paiement END,
    date_paiement=CASE WHEN reste=0 THEN now() ELSE NULL END,
    modifie_le=now() WHERE id=f.id;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id:=f.etablissement_id,p_type_acteur:='SYSTEME',
    p_action:='FACTURATION',p_type_ressource:='facture',p_id_ressource:=f.id,
    p_details:=jsonb_build_object('evenement','AVOIRS_IMPUTES','montant_ttc',f.montant_ttc,'impute_cents',total,'externe_cents',reste));
  RETURN jsonb_build_object('success',true,'montant_avoirs_imputes',total/100.0,'montant_a_payer',reste/100.0,'existing',false);
END $allocate$;

CREATE FUNCTION private.fn_garder_facture_imputation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
DECLARE total bigint; liee boolean;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.montant_avoirs_imputes<>0 OR NEW.mode_paiement='AVOIR' OR NEW.rapprochement_paiement_requis THEN
      RAISE EXCEPTION 'AVOIR_CHAMPS_SERVEUR'; END IF;
    RETURN NEW;
  END IF;
  SELECT EXISTS(SELECT 1 FROM private.avoirs_commission_sources s WHERE s.avoir_id=OLD.id OR s.facture_origine_id=OLD.id)
    OR EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements j WHERE j.facture_id=OLD.id) INTO liee;
  IF TG_OP='DELETE' THEN
    IF liee THEN RAISE EXCEPTION 'AVOIR_DOCUMENT_LIE_IMMUABLE'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.rapprochement_paiement_requis IS DISTINCT FROM NEW.rapprochement_paiement_requis THEN
    -- La ligne est déjà verrouillée par UPDATE : ne jamais attendre E ici,
    -- une allocation peut détenir E et attendre cette même ligne. Le fournisseur
    -- rejoue la transaction entière après 40001 ; aucune preuve n'est modifiée.
    IF NOT OLD.rapprochement_paiement_requis AND NEW.rapprochement_paiement_requis
      AND NOT pg_try_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||OLD.etablissement_id::text,0)) THEN
      RAISE EXCEPTION 'AVOIR_RAPPROCHEMENT_CONCURRENT_REESSAYER' USING ERRCODE='40001';
    END IF;
    IF coalesce(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role'
      OR OLD.rapprochement_paiement_requis THEN RAISE EXCEPTION 'AVOIR_RAPPROCHEMENT_SERVEUR'; END IF;
    IF ROW(NEW.statut,NEW.stripe_payment_intent_id,NEW.date_paiement,NEW.montant_avoirs_imputes,NEW.mode_paiement,NEW.stripe_invoice_id,NEW.stripe_hosted_url,NEW.virement_reference)
      IS DISTINCT FROM ROW(OLD.statut,OLD.stripe_payment_intent_id,OLD.date_paiement,OLD.montant_avoirs_imputes,OLD.mode_paiement,OLD.stripe_invoice_id,OLD.stripe_hosted_url,OLD.virement_reference) THEN
      RAISE EXCEPTION 'AVOIR_RAPPROCHEMENT_PREUVE_IMMUABLE'; END IF;
  END IF;
  IF liee AND ROW(NEW.montant_ht,NEW.montant_tva,NEW.montant_ttc,NEW.type_document,NEW.etablissement_id,
      NEW.facture_precedente_id,NEW.facture_honoraire_id,NEW.mission_id,NEW.numero_facture)
    IS DISTINCT FROM ROW(OLD.montant_ht,OLD.montant_tva,OLD.montant_ttc,OLD.type_document,OLD.etablissement_id,
      OLD.facture_precedente_id,OLD.facture_honoraire_id,OLD.mission_id,OLD.numero_facture) THEN
    RAISE EXCEPTION 'AVOIR_DOCUMENT_LIE_IMMUABLE'; END IF;
  SELECT coalesce(sum(montant_cents),0) INTO total FROM private.avoirs_commission_mouvements
    WHERE facture_id=OLD.id AND nature='IMPUTATION';
  IF NEW.montant_avoirs_imputes*100<>total OR
    (OLD.montant_avoirs_imputes IS DISTINCT FROM NEW.montant_avoirs_imputes AND OLD.statut<>'BROUILLON') THEN
    RAISE EXCEPTION 'AVOIR_ALLOCATION_IMMUABLE'; END IF;
  IF NEW.mode_paiement='AVOIR' AND (total<=0 OR total<>NEW.montant_ttc*100) THEN RAISE EXCEPTION 'AVOIR_SOLDE_SANS_PREUVE'; END IF;
  IF OLD.rapprochement_paiement_requis AND ROW(NEW.statut,NEW.stripe_payment_intent_id,NEW.date_paiement,NEW.mode_paiement,NEW.chorus_pro_statut,NEW.chorus_pro_id,NEW.virement_reference)
    IS DISTINCT FROM ROW(OLD.statut,OLD.stripe_payment_intent_id,OLD.date_paiement,OLD.mode_paiement,OLD.chorus_pro_statut,OLD.chorus_pro_id,OLD.virement_reference) THEN
    RAISE EXCEPTION 'AVOIR_RAPPROCHEMENT_REQUIS'; END IF;
  IF liee AND NEW.statut IN ('ANNULEE','REMPLACEE') AND NEW.statut IS DISTINCT FROM OLD.statut THEN
    IF EXISTS(SELECT 1 FROM private.avoirs_commission_sources WHERE avoir_id=OLD.id OR facture_origine_id=OLD.id)
      OR OLD.statut='PAYEE' OR OLD.date_paiement IS NOT NULL OR OLD.stripe_payment_intent_id IS NOT NULL
      OR OLD.stripe_invoice_id IS NOT NULL OR OLD.stripe_hosted_url IS NOT NULL
      OR OLD.virement_reference IS NOT NULL OR OLD.rapprochement_paiement_requis
      OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c WHERE c.resource_key='FACTURE:'||OLD.id::text
        OR c.resource_key IN (SELECT 'MISSION:'||m.id::text FROM public.missions m WHERE m.facture_id=OLD.id))
    THEN RAISE EXCEPTION 'AVOIR_ANNULATION_RAPPROCHEMENT_REQUIS'; END IF;
  END IF;
  IF (total>0 OR EXISTS(SELECT 1 FROM private.avoirs_commission_sources WHERE facture_origine_id=OLD.id)) AND OLD.statut='PAYEE' AND NEW.statut IS DISTINCT FROM OLD.statut THEN
    RAISE EXCEPTION 'AVOIR_PAIEMENT_RAPPROCHEMENT_REQUIS'; END IF;
  IF total>0 AND OLD.statut IN ('ANNULEE','REMPLACEE') AND NEW.statut IS DISTINCT FROM OLD.statut THEN
    RAISE EXCEPTION 'AVOIR_FACTURE_ANNULEE_IMMUABLE'; END IF;
  RETURN NEW;
END $guard$;
-- Avant dec_idempotence_facture : ce dernier RETURN OLD sur PAYEE/PAYEE ne doit
-- pas masquer une tentative de falsification ni empêcher un signalement serveur.
CREATE TRIGGER aa_garder_facture_imputation BEFORE INSERT OR UPDATE OR DELETE ON public.factures
FOR EACH ROW EXECUTE FUNCTION private.fn_garder_facture_imputation();

CREATE FUNCTION private.fn_restituer_avoirs_facture_annulee()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $restore$
BEGIN
  IF NEW.statut IN ('ANNULEE','REMPLACEE') AND OLD.statut IS DISTINCT FROM NEW.statut THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||NEW.etablissement_id::text,0));
    INSERT INTO private.avoirs_commission_mouvements(avoir_id,facture_id,etablissement_id,nature,montant_cents,imputation_origine_id)
    SELECT avoir_id,facture_id,etablissement_id,'RESTITUTION',montant_cents,id
    FROM private.avoirs_commission_mouvements j WHERE facture_id=NEW.id AND nature='IMPUTATION'
      AND NOT EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements r WHERE r.imputation_origine_id=j.id);
  END IF;
  RETURN NEW;
END $restore$;
CREATE TRIGGER trg_avoirs_restitution AFTER UPDATE OF statut ON public.factures
FOR EACH ROW EXECUTE FUNCTION private.fn_restituer_avoirs_facture_annulee();

CREATE FUNCTION private.fn_avoirs_commission_detail(p_facture_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $detail$
  SELECT jsonb_build_object('imputations',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'avoir_id',j.avoir_id,'numero_avoir',a.numero_facture,'montant_ttc',j.montant_cents/100.0,
    'restitue',EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements r WHERE r.imputation_origine_id=j.id)) ORDER BY a.date_emission,a.id)
    FROM private.avoirs_commission_mouvements j JOIN public.factures a ON a.id=j.avoir_id
    WHERE j.facture_id=p_facture_id AND j.nature='IMPUTATION'),'[]'::jsonb),
    'avoir_eligible',EXISTS(SELECT 1 FROM private.avoirs_commission_sources s
      JOIN public.factures a ON a.id=s.avoir_id JOIN public.factures o ON o.id=s.facture_origine_id
      WHERE s.avoir_id=p_facture_id AND NOT a.rapprochement_paiement_requis AND NOT o.rapprochement_paiement_requis
        AND a.statut IN ('EMISE','EN_RETARD') AND o.statut IN ('EMISE','EN_RETARD','VIREMENT_DECLARE','PAYEE')
        AND NOT EXISTS(SELECT 1 FROM public.stripe_transfers t WHERE t.mission_id=s.mission_id OR t.facture_id=s.facture_origine_id)
        AND NOT EXISTS(SELECT 1 FROM public.paiements_escrow e WHERE e.mission_id=s.mission_id)
        AND NOT EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims c WHERE c.resource_key IN
          ('FACTURE:'||s.facture_origine_id::text,'MISSION:'||s.mission_id::text)
          AND c.flow IN ('CONNECT_MISSION','CONNECT_INVOICE','LEGACY_UNKNOWN'))),
    'avoir_reliquat', (SELECT (s.montant_cents-coalesce((SELECT sum(CASE j.nature WHEN 'IMPUTATION' THEN j.montant_cents ELSE -j.montant_cents END)
      FROM private.avoirs_commission_mouvements j WHERE j.avoir_id=s.avoir_id),0))/100.0
      FROM private.avoirs_commission_sources s WHERE s.avoir_id=p_facture_id));
$detail$;

-- Un remboursement de l'origine peut invalider une compensation déjà utilisée.
-- Propagation monotone : signalement seulement, jamais dette ni nouvelle allocation.
CREATE FUNCTION private.fn_propager_rapprochement_avoir()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $propagate$
DECLARE cible record; modifies integer;
BEGIN
 IF OLD.rapprochement_paiement_requis OR NOT NEW.rapprochement_paiement_requis THEN RETURN NEW; END IF;
 -- Déjà acquis sans attente par la garde BEFORE ; reste détenu jusqu'au COMMIT.
 -- La lecture suivante prend son snapshot après acquisition (READ COMMITTED).
 PERFORM pg_advisory_xact_lock(hashtextextended('AVOIRS_ETAB:'||NEW.etablissement_id::text,0));
 FOR cible IN SELECT DISTINCT f.id FROM private.avoirs_commission_sources s
   JOIN private.avoirs_commission_mouvements j ON j.avoir_id=s.avoir_id AND j.nature='IMPUTATION'
   JOIN public.factures f ON f.id=j.facture_id
   WHERE s.facture_origine_id=NEW.id AND f.id<>NEW.id
     AND f.etablissement_id=NEW.etablissement_id AND NOT f.rapprochement_paiement_requis
     AND NOT EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements r WHERE r.imputation_origine_id=j.id)
   ORDER BY f.id
 LOOP
   UPDATE public.factures SET rapprochement_paiement_requis=true
   WHERE id=cible.id AND NOT rapprochement_paiement_requis;
   GET DIAGNOSTICS modifies=ROW_COUNT;
   IF modifies=1 THEN
     PERFORM public.fn_ecrire_audit_safe(p_acteur_id:=NEW.etablissement_id,p_type_acteur:='SYSTEME',
       p_action:='FACTURATION',p_type_ressource:='facture',p_id_ressource:=cible.id,
       p_details:=jsonb_build_object('evenement','AVOIR_ORIGINE_A_RAPPROCHER','facture_origine_id',NEW.id));
   END IF;
 END LOOP;
 RETURN NEW;
END $propagate$;
CREATE TRIGGER trg_avoirs_rapprochement AFTER UPDATE OF rapprochement_paiement_requis ON public.factures
FOR EACH ROW EXECUTE FUNCTION private.fn_propager_rapprochement_avoir();

CREATE FUNCTION private.fn_garder_claim_facture_imputation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $claim$
DECLARE f public.factures;
BEGIN
 IF NEW.resource_key LIKE 'FACTURE:%' THEN
  SELECT * INTO f FROM public.factures WHERE id=substring(NEW.resource_key FROM 9)::uuid;
  IF f.id IS NOT NULL AND (f.montant_a_payer<=0 OR f.rapprochement_paiement_requis) THEN
   RAISE EXCEPTION 'AVOIR_CLAIM_SOLDE_OU_RAPPROCHEMENT'; END IF;
 END IF;
 RETURN NEW;
END $claim$;
CREATE TRIGGER trg_avoirs_claim BEFORE INSERT ON public.stripe_payment_flow_claims
FOR EACH ROW EXECUTE FUNCTION private.fn_garder_claim_facture_imputation();

REVOKE ALL ON FUNCTION private.fn_avoirs_commission_immutables(),
  private.fn_inscrire_avoir_commission(uuid,uuid,text),private.fn_garder_mouvement_avoir_commission(),
  private.fn_emettre_facture_mensuelle_avec_avoirs(uuid),private.fn_garder_facture_imputation(),
  private.fn_restituer_avoirs_facture_annulee(),private.fn_avoirs_commission_detail(uuid),
  private.fn_garder_claim_facture_imputation(),private.fn_propager_rapprochement_avoir()
FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.dec_bloquer_paiement_manuel_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si quelqu'un essaie de passer une facture en PAYEE
    IF NEW.statut = 'PAYEE' AND OLD.statut != 'PAYEE' AND NEW.mode_paiement IS DISTINCT FROM 'AVOIR' THEN
        -- Seul l'admin OU le service_role (webhook Stripe) peut faire ça
        IF NOT est_admin() AND auth.uid() IS NOT NULL THEN
            RAISE EXCEPTION 'Le paiement des factures passe exclusivement par Stripe ou virement bancaire.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.dec_bloquer_si_facture_impayee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nb_impayees integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT count(*) INTO v_nb_impayees
    FROM public.factures
    WHERE etablissement_id = NEW.etablissement_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis
      AND date_echeance < current_date;

    IF v_nb_impayees > 0 AND NOT public.est_admin() THEN
      RAISE EXCEPTION
        'Vous avez % facture(s) échue(s) impayée(s) : les nouvelles publications sont suspendues (vos missions en cours ne sont pas affectées). Régularisez depuis Facturation pour republier.',
        v_nb_impayees;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.dec_idempotence_facture_payee()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si la facture est DÉJÀ payée, ne rien faire
    IF OLD.statut = 'PAYEE' AND NEW.statut = 'PAYEE'
      AND NEW.rapprochement_paiement_requis IS NOT DISTINCT FROM OLD.rapprochement_paiement_requis THEN
        RETURN OLD; -- Pas de modification
    END IF;
    RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_admin_kpi()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
  debut_semaine timestamptz := date_trunc('week', now());
  debut_mois timestamptz := date_trunc('month', now());
  fin_mois timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF NOT public.est_admin() THEN
    RETURN '{"error":"Accès réservé aux administrateurs"}'::jsonb;
  END IF;

  WITH missions_reelles AS (
    SELECT m.*
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE e.est_compte_test IS FALSE
       AND COALESCE(s.est_compte_test, false) IS FALSE
  ),
  factures_reelles AS (
    SELECT f.*
      FROM public.factures f
      JOIN public.etablissements e ON e.id = f.etablissement_id
     WHERE e.est_compte_test IS FALSE
  )
  SELECT jsonb_build_object(
    'soignants_total', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
    ),
    'etablissements_total', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
    ),
    'missions_terminees_total', (
      SELECT count(*) FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'missions_terminees_mois', (
      SELECT count(*) FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'missions_ouvertes', (
      SELECT count(*) FROM missions_reelles
       WHERE statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS')
    ),
    'soignants_semaine', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= debut_semaine
    ),
    'etablissements_semaine', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= debut_semaine
    ),
    'litiges_ouverts', (
      SELECT count(*)
        FROM public.litiges l
        JOIN missions_reelles m ON m.id = l.mission_id
       WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE')
    ),
    'ca_commissions_ht_mois', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'ca_potentiel_mois', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles
       WHERE fin_le >= debut_mois AND fin_le < fin_mois
         AND statut IN ('TERMINEE', 'ASSIGNEE', 'EN_COURS')
    ),
    'ca_encaisse_total', (
      SELECT COALESCE(sum(montant_ht), 0)
        FROM factures_reelles WHERE statut = 'PAYEE'
    ),
    'ca_potentiel_total', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'gmv_mois', (
      SELECT COALESCE(sum(total_brut), 0)
        FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'gmv_total', (
      SELECT COALESCE(sum(total_brut), 0)
        FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'taux_acceptation_mois', (
      SELECT CASE
        WHEN count(*) FILTER (WHERE cree_le >= debut_mois) = 0 THEN 0
        ELSE round(
          100.0 * count(*) FILTER (
            WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
              AND cree_le >= debut_mois
          ) / NULLIF(count(*) FILTER (WHERE cree_le >= debut_mois), 0)
        )
      END
      FROM missions_reelles
    ),
    'factures_impayees', (
      SELECT count(*) FROM factures_reelles WHERE statut IN ('EMISE', 'EN_RETARD')
        AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis
    ),
    'docs_en_attente', (
      SELECT count(*)
        FROM public.documents_soignants d
        JOIN public.soignants s ON s.id = d.soignant_id
       WHERE d.statut_verification = 'EN_ATTENTE'
         AND s.est_compte_test IS FALSE
    ),
    'etab_en_attente', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL
         AND est_compte_test IS FALSE
         AND COALESCE(rattachement_verifie, false) = false
         AND COALESCE(statut_verification, '') <> 'REJETE'
    )
  ) INTO result;

  RETURN result;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_salarie(p_litige_id uuid, p_resolution text, p_en_faveur_de text DEFAULT NULL::text, p_ajuster_heures numeric DEFAULT NULL::numeric, p_ajuster_taux numeric DEFAULT NULL::numeric, p_action_financiere text DEFAULT 'AUTO'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_action text := upper(btrim(COALESCE(p_action_financiere, 'AUTO')));
  v_faveur text := upper(btrim(COALESCE(p_en_faveur_de, 'NEUTRE')));
  v_nouveau_statut text;
  v_litige public.litiges%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_mission_apres public.missions%ROWTYPE;
  v_presence public.presences%ROWTYPE;
  v_presence_trouvee boolean := false;
  v_payload jsonb;
  v_type_payload text;
  v_modifications jsonb;
  v_arrivee_payload timestamptz;
  v_depart_payload timestamptz;
  v_heures_payload numeric;
  v_heures_avant numeric;
  v_heures_final numeric;
  v_taux_avant numeric;
  v_taux_final numeric;
  v_ajustement_demande boolean := false;
  v_accord_remplace boolean := false;
  v_helper_result jsonb;
  v_calcul_result jsonb;
  v_cot public.cotisations_sociales%ROWTYPE;
  v_bulletin_precedent public.bulletins_paie%ROWTYPE;
  v_bulletin_precedent_trouve boolean := false;
  v_bulletin_id uuid;
  v_numero_bulletin text;
  v_statut_bulletin text := 'EMIS';
  v_date_paiement date;
  v_total_confirme numeric := 0;
  v_nb_paiements integer := 0;
  v_regularisation_paiement boolean := false;
  v_ecart_paiement numeric := 0;
  v_commission_delta_ht numeric := 0;
  v_commission_delta_tva numeric := 0;
  v_commission_delta_ttc numeric := 0;
  v_document_commission_id uuid;
  v_document_commission_numero text;
  v_document_commission_type text;
  v_rows integer;
  v_audit_result jsonb;
BEGIN
  IF v_uid IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Administrateur requis.');
  END IF;
  IF length(btrim(COALESCE(p_resolution, ''))) < 10
     OR length(btrim(COALESCE(p_resolution, ''))) > 5000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La résolution doit contenir entre 10 et 5 000 caractères.'
    );
  END IF;
  IF v_faveur NOT IN ('SOIGNANT', 'ETABLISSEMENT', 'NEUTRE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'p_en_faveur_de doit être SOIGNANT, ETABLISSEMENT ou NEUTRE.'
    );
  END IF;
  IF v_action NOT IN ('AUTO', 'AUCUNE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Une mission salariée utilise la rectification de paie automatique, pas une action de facture d’honoraires.'
    );
  END IF;
  IF p_ajuster_heures IS NOT NULL
     AND (p_ajuster_heures::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_ajuster_heures <= 0 OR p_ajuster_heures > 168) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Les heures ajustées doivent être strictement positives et au plus égales à 168.'
    );
  END IF;
  IF p_ajuster_taux IS NOT NULL
     AND (p_ajuster_taux::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_ajuster_taux < 0.01 OR p_ajuster_taux > 1000) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Le taux ajusté doit être strictement positif et au plus égal à 1 000 €.'
    );
  END IF;

  SELECT l.* INTO v_litige
  FROM public.litiges l
  WHERE l.id = p_litige_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable.');
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Ce litige est déjà résolu ou non modifiable.'
    );
  END IF;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = v_litige.mission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission du litige introuvable.');
  END IF;
  IF COALESCE(v_mission.type_contrat_applique::text, '') <> 'SALARIE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cette mission ne relève pas du circuit de paie salariée.'
    );
  END IF;
  IF COALESCE(v_mission.commission_facturee, false) AND v_mission.facture_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Commission marquée facturée sans facture d’origine : intervention comptable requise.'
    );
  END IF;
  IF v_mission.facture_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.factures f WHERE f.id = v_mission.facture_id
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La facture de commission d’origine est introuvable.'
    );
  END IF;

  IF v_litige.presence_id IS NOT NULL THEN
    SELECT p.* INTO v_presence
    FROM public.presences p
    WHERE p.id = v_litige.presence_id
      AND p.mission_id = v_litige.mission_id
    FOR UPDATE;
    v_presence_trouvee := FOUND;
  ELSE
    SELECT p.* INTO v_presence
    FROM public.presences p
    WHERE p.mission_id = v_litige.mission_id
    ORDER BY p.valide_le DESC NULLS LAST, p.cree_le DESC
    LIMIT 1
    FOR UPDATE;
    v_presence_trouvee := FOUND;
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NOT NULL THEN
    IF v_litige.modifications_executees IS TRUE THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Les modifications de cet accord ont déjà été exécutées.'
      );
    END IF;
    IF v_litige.statut <> 'REVUE_ADMIN'
       OR v_litige.accord_soignant IS NOT TRUE
       OR v_litige.accord_etablissement IS NOT TRUE
       OR v_litige.accord_soignant_le IS NULL
       OR v_litige.accord_etablissement_le IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Un accord financier exige le double accord horodaté des parties.'
      );
    END IF;
    v_type_payload := v_payload->>'type';
    v_modifications := v_payload->'modifications';
    IF v_type_payload NOT IN ('MODIFICATION_HORAIRES', 'MIXTE') THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Pour une mission salariée, renseignez les heures ou le taux : un montant TTC isolé ne définit pas une paie.'
      );
    END IF;
    BEGIN
      v_arrivee_payload := (v_modifications->>'pointage_arrivee_le')::timestamptz;
      v_depart_payload := (v_modifications->>'pointage_depart_le')::timestamptz;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      RETURN jsonb_build_object('success', false, 'error', 'Format des horaires convenus invalide.');
    END;
    IF v_arrivee_payload IS NULL OR v_depart_payload IS NULL
       OR v_depart_payload <= v_arrivee_payload
       OR v_depart_payload - v_arrivee_payload > interval '7 days' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Plage horaire convenue invalide.');
    END IF;
    IF NOT v_presence_trouvee THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Aucune présence verrouillable pour appliquer les heures.'
      );
    END IF;
    v_heures_payload := round(
      GREATEST(
        0,
        EXTRACT(epoch FROM (v_depart_payload - v_arrivee_payload)) / 3600
          - COALESCE(v_presence.duree_pause_min, 0) / 60
      )::numeric,
      2
    );
    IF v_heures_payload <= 0 OR v_heures_payload > 168 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Durée nette convenue hors limites.');
    END IF;
  END IF;

  v_ajustement_demande := p_ajuster_heures IS NOT NULL
    OR p_ajuster_taux IS NOT NULL
    OR v_payload IS NOT NULL;
  IF v_action = 'AUCUNE' AND v_ajustement_demande THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'AUCUNE est interdite lorsqu’un ajustement de paie existe.'
    );
  END IF;
  IF v_ajustement_demande AND v_mission.statut <> 'TERMINEE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La mission doit être terminée avant de rectifier sa paie.'
    );
  END IF;
  IF (p_ajuster_heures IS NOT NULL OR v_heures_payload IS NOT NULL)
     AND NOT v_presence_trouvee THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Aucune présence verrouillable pour appliquer les heures.'
    );
  END IF;

  v_heures_avant := COALESCE(
    CASE WHEN v_presence_trouvee THEN v_presence.heures_ajustees_litige END,
    CASE WHEN v_presence_trouvee THEN v_presence.heures_reelles END,
    v_mission.duree_heures
  );
  v_taux_avant := COALESCE(
    v_mission.taux_horaire_base_fige,
    v_mission.taux_horaire_base
  );
  v_heures_final := COALESCE(p_ajuster_heures, v_heures_payload, v_heures_avant);
  v_taux_final := COALESCE(p_ajuster_taux, v_taux_avant);

  IF v_ajustement_demande AND (
    v_heures_final IS NULL OR v_heures_final <= 0 OR v_heures_final > 168
    OR v_taux_final IS NULL OR v_taux_final < 0.01 OR v_taux_final > 1000
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Heures ou taux de référence absents ou hors limites.'
    );
  END IF;

  IF v_payload IS NOT NULL THEN
    v_accord_remplace := p_ajuster_taux IS NOT NULL
      OR (
        p_ajuster_heures IS NOT NULL
        AND abs(p_ajuster_heures - v_heures_payload) > 0.005
      );
  END IF;

  IF v_ajustement_demande THEN
    IF v_payload IS NOT NULL AND p_ajuster_heures IS NULL THEN
      v_helper_result := public.fn_modifier_horaires_presence(
        v_presence.id,
        v_arrivee_payload,
        v_depart_payload,
        v_payload->>'justification'
      );
      IF COALESCE(v_helper_result @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Échec atomique de la correction des horaires: %',
          COALESCE(v_helper_result->>'error', 'résultat interne invalide');
      END IF;
      UPDATE public.presences
      SET heures_ajustees_litige = NULL,
          ajustement_litige_id = p_litige_id,
          motif_litige = left('Accord litige : ' || (v_payload->>'justification'), 2000),
          modifie_le = now()
      WHERE id = v_presence.id;
    ELSIF p_ajuster_heures IS NOT NULL THEN
      UPDATE public.presences
      SET heures_ajustees_litige = p_ajuster_heures,
          ajustement_litige_id = p_litige_id,
          motif_litige = left('Décision admin litige : ' || btrim(p_resolution), 2000),
          modifie_le = now()
      WHERE id = v_presence.id;
    END IF;

    PERFORM set_config('jolene.admin_override_gel', v_mission.id::text, true);
    PERFORM set_config(
      'jolene.admin_override_reason',
      'Résolution litige paie salariée ' || p_litige_id::text,
      true
    );
    PERFORM set_config('jolene.heures_litige_mission_id', v_mission.id::text, true);
    PERFORM set_config('jolene.heures_litige_override', v_heures_final::text, true);

    UPDATE public.missions
    SET duree_heures = v_heures_final,
        taux_horaire_base = v_taux_final,
        taux_horaire_base_fige = v_taux_final,
        commission_a_recalculer = false,
        modifie_le = now()
    WHERE id = v_mission.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Recalcul de la mission non appliqué';
    END IF;

    PERFORM set_config('jolene.heures_litige_mission_id', '', true);
    PERFORM set_config('jolene.heures_litige_override', '', true);

    SELECT m.* INTO v_mission_apres
    FROM public.missions m WHERE m.id = v_mission.id;

    v_calcul_result := public.fn_calculer_cotisations(v_mission.id);
    IF COALESCE((v_calcul_result->>'success')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Calcul des cotisations échoué: %',
        COALESCE(v_calcul_result->>'error', 'résultat interne invalide');
    END IF;
    SELECT c.* INTO v_cot
    FROM public.cotisations_sociales c
    WHERE c.mission_id = v_mission.id;
    IF NOT FOUND OR v_cot.type_contrat <> 'CDD' THEN
      RAISE EXCEPTION 'Cotisations salariées rectificatives introuvables';
    END IF;

    SELECT bp.* INTO v_bulletin_precedent
    FROM public.bulletins_paie bp
    WHERE bp.mission_id = v_mission.id
      AND bp.statut <> 'ANNULE'
    ORDER BY bp.cree_le DESC
    LIMIT 1
    FOR UPDATE;
    v_bulletin_precedent_trouve := FOUND;

    IF v_bulletin_precedent_trouve THEN
      UPDATE public.bulletins_paie
      SET statut = 'ANNULE', modifie_le = now()
      WHERE id = v_bulletin_precedent.id
        AND statut <> 'ANNULE';
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Annulation concurrente de la simulation de paie refusée';
      END IF;
    END IF;

    SELECT
      COALESCE(sum(ps.montant_net) FILTER (WHERE ps.statut IN ('CONFIRME', 'RESOLU')), 0),
      max(ps.date_paiement) FILTER (WHERE ps.statut IN ('CONFIRME', 'RESOLU')),
      count(*) FILTER (WHERE ps.statut IN ('DECLARE', 'CONFIRME', 'RESOLU'))
    INTO v_total_confirme, v_date_paiement, v_nb_paiements
    FROM public.paiements_soignant ps
    WHERE ps.mission_id = v_mission.id;

    v_ecart_paiement := round(v_cot.net_avant_impot - v_total_confirme, 2);
    v_regularisation_paiement := v_nb_paiements > 0 AND abs(v_ecart_paiement) > 0.01;
    IF v_nb_paiements > 0 AND abs(v_ecart_paiement) <= 0.01 THEN
      v_statut_bulletin := 'PAYE';
    END IF;

    v_numero_bulletin := public.fn_next_bulletin_paie_number(
      v_mission.soignant_assigne_id
    );
    INSERT INTO public.bulletins_paie (
      numero_bulletin, soignant_id, mission_id, etablissement_id,
      periode_debut, periode_fin, salaire_brut,
      total_cotisations_salariales, total_cotisations_patronales,
      net_avant_impot, ifm, icp, statut, date_emission, date_paiement,
      bulletin_precedent_id, litige_id, nature_document, motif_rectification
    ) VALUES (
      v_numero_bulletin, v_mission.soignant_assigne_id, v_mission.id,
      v_mission.etablissement_id, v_mission.debut_le::date, v_mission.fin_le::date,
      v_cot.salaire_brut, v_cot.total_cotisations_salariales,
      v_cot.total_cotisations_patronales, v_cot.net_avant_impot,
      COALESCE(v_cot.ifm, 0), COALESCE(v_cot.icp, 0),
      v_statut_bulletin, current_date,
      CASE WHEN v_statut_bulletin = 'PAYE' THEN v_date_paiement ELSE NULL END,
      CASE WHEN v_bulletin_precedent_trouve THEN v_bulletin_precedent.id ELSE NULL END,
      p_litige_id,
      CASE WHEN v_bulletin_precedent_trouve THEN 'RECTIFICATIF' ELSE 'SIMULATION' END,
      left(btrim(p_resolution), 2000)
    ) RETURNING id INTO v_bulletin_id;

    v_commission_delta_ht := round(
      COALESCE(v_mission_apres.montant_commission_ht, 0)
        - COALESCE(v_mission.montant_commission_ht, 0),
      2
    );
    IF COALESCE(v_mission.commission_facturee, false)
       AND abs(v_commission_delta_ht) > 0.01 THEN
      v_commission_delta_tva := round(abs(v_commission_delta_ht) * 0.20, 2);
      v_commission_delta_ttc := abs(v_commission_delta_ht) + v_commission_delta_tva;
      IF v_commission_delta_ht < 0 THEN
        v_document_commission_type := 'AVOIR';
        v_document_commission_numero := public.next_avoir_commission_number(
          v_mission.etablissement_id
        );
      ELSE
        v_document_commission_type := 'FACTURE_COMPLEMENTAIRE';
        v_document_commission_numero := public.next_facture_complementaire_number(
          v_mission.etablissement_id
        );
      END IF;
      INSERT INTO public.factures (
        etablissement_id, numero_facture, mission_id, type_document,
        facture_precedente_id, montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, statut, date_emission, date_echeance,
        periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_document_commission_numero, v_mission.id,
        v_document_commission_type, v_mission.facture_id,
        abs(v_commission_delta_ht), 20, v_commission_delta_tva,
        v_commission_delta_ttc, 1, 'EMISE', now(), current_date + 30,
        v_mission.debut_le::date, v_mission.fin_le::date
      ) RETURNING id INTO v_document_commission_id;
      IF v_document_commission_type='AVOIR' THEN
        PERFORM private.fn_inscrire_avoir_commission(v_document_commission_id,v_mission.id,'LITIGE_SALARIE');
      END IF;
    END IF;
  ELSE
    v_mission_apres := v_mission;
    v_action := 'AUCUNE';
  END IF;

  v_nouveau_statut := CASE v_faveur
    WHEN 'SOIGNANT' THEN 'RESOLU_SOIGNANT'
    WHEN 'ETABLISSEMENT' THEN 'RESOLU_ETABLISSEMENT'
    ELSE 'RESOLU_ADMIN'
  END;
  UPDATE public.litiges
  SET statut = v_nouveau_statut,
      resolution = btrim(p_resolution),
      resolu_par = v_uid,
      resolu_le = now(),
      modifications_executees = CASE
        WHEN v_payload IS NOT NULL THEN true ELSE modifications_executees
      END,
      modifications_executees_a = CASE
        WHEN v_payload IS NOT NULL THEN now() ELSE modifications_executees_a
      END,
      modifications_executees_par = CASE
        WHEN v_payload IS NOT NULL THEN v_uid ELSE modifications_executees_par
      END
  WHERE id = p_litige_id
    AND statut IN (
      'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN'
    );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Résolution concurrente refusée';
  END IF;

  v_audit_result := public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_RESOLUTION',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'LITIGE_RESOLUTION_PAIE_SALARIEE',
      'en_faveur_de', v_faveur,
      'heures_avant', v_heures_avant,
      'heures_apres', v_heures_final,
      'taux_avant', v_taux_avant,
      'taux_apres', v_taux_final,
      'brut_mission_avant', v_mission.total_brut,
      'brut_mission_apres', v_mission_apres.total_brut,
      'net_simule_apres', CASE WHEN v_ajustement_demande THEN v_cot.net_avant_impot ELSE NULL END,
      'commission_ht_avant', v_mission.montant_commission_ht,
      'commission_ht_apres', v_mission_apres.montant_commission_ht,
      'bulletin_precedent_id', CASE
        WHEN v_bulletin_precedent_trouve THEN v_bulletin_precedent.id ELSE NULL
      END,
      'bulletin_rectificatif_id', v_bulletin_id,
      'document_commission_id', v_document_commission_id,
      'document_commission_type', v_document_commission_type,
      'regularisation_paiement_requise', v_regularisation_paiement,
      'ecart_paiement', v_ecart_paiement,
      'accord_remplace', v_accord_remplace
    )
  );
  IF COALESCE(v_audit_result @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit de résolution non écrit: %',
      COALESCE(v_audit_result->>'error', 'résultat interne invalide');
  END IF;

  IF v_ajustement_demande THEN
    PERFORM public.fn_litige_push_notification(
      v_litige.soignant_id,
      'SOIGNANT',
      'LITIGE_RESOLU_AJUSTE',
      'Litige résolu — simulation de paie rectifiée',
      CASE WHEN v_regularisation_paiement
        THEN 'Les heures et la simulation de paie ont été rectifiées. Une régularisation du paiement reste à traiter.'
        ELSE 'Les heures, la simulation de paie et la commission ont été recalculées.'
      END,
      p_litige_id,
      jsonb_build_object(
        'bulletin_rectificatif_id', v_bulletin_id,
        'net_simule', v_cot.net_avant_impot,
        'regularisation_paiement_requise', v_regularisation_paiement
      )
    );
    PERFORM public.fn_litige_push_notification(
      v_litige.etablissement_id,
      'ETABLISSEMENT',
      'LITIGE_RESOLU_AJUSTE',
      'Litige résolu — paie salariée rectifiée',
      CASE WHEN v_regularisation_paiement
        THEN 'La paie simulée a été rectifiée. Traitez maintenant la régularisation du paiement.'
        ELSE 'La paie simulée et la commission de la mission ont été recalculées.'
      END,
      p_litige_id,
      jsonb_build_object(
        'bulletin_rectificatif_id', v_bulletin_id,
        'net_simule', v_cot.net_avant_impot,
        'regularisation_paiement_requise', v_regularisation_paiement
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_financiere', CASE
      WHEN v_ajustement_demande THEN 'RECTIFICATION_PAIE_SALARIEE'
      ELSE 'AUCUNE'
    END,
    'statut', v_nouveau_statut,
    'heures_final', v_heures_final,
    'taux_final', v_taux_final,
    'salaire_brut', CASE WHEN v_ajustement_demande THEN v_cot.salaire_brut ELSE NULL END,
    'net_avant_impot', CASE WHEN v_ajustement_demande THEN v_cot.net_avant_impot ELSE NULL END,
    'bulletin_annule_id', CASE
      WHEN v_bulletin_precedent_trouve THEN v_bulletin_precedent.id ELSE NULL
    END,
    'bulletin_rectificatif_id', v_bulletin_id,
    'document_commission_id', v_document_commission_id,
    'document_commission_type', v_document_commission_type,
    'regularisation_paiement_requise', v_regularisation_paiement,
    'ecart_paiement', v_ecart_paiement,
    'accord_remplace', v_accord_remplace
  );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_admin_suspendre_utilisateur(p_table text, p_id uuid, p_suspendre boolean DEFAULT true, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_nom text;
  v_motif text := NULLIF(btrim(COALESCE(p_motif, '')), '');
  v_maintenant timestamptz := transaction_timestamp();
  v_membres integer := 0;
  v_auth_trouve boolean := false;
  v_auth_state_existe boolean := false;
  v_banned_until_courant timestamptz;
  v_banned_until_pose timestamptz;
  v_pose_precedente timestamptz;
  v_peut_publier_avant boolean := false;
  v_supprime_le timestamptz;
  v_est_suppression_rgpd boolean := false;
  v_provenance_suspension boolean := false;
BEGIN
  IF NOT public.est_admin_valide() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin AAL2 uniquement');
  END IF;
  IF p_table NOT IN ('soignants', 'etablissements') THEN
    RETURN jsonb_build_object('error', 'Table invalide');
  END IF;
  IF p_id IS NULL OR p_suspendre IS NULL THEN
    RETURN jsonb_build_object('error', 'Paramètres de suspension invalides');
  END IF;
  IF p_suspendre AND (v_motif IS NULL OR char_length(v_motif) < 3) THEN
    RETURN jsonb_build_object('error', 'Motif obligatoire (3 caractères minimum)');
  END IF;
  IF v_motif IS NOT NULL AND char_length(v_motif) > 1000 THEN
    RETURN jsonb_build_object('error', 'Motif trop long (1000 caractères maximum)');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_table || ':' || p_id::text, 0));

  IF p_table = 'soignants' THEN
    SELECT
      COALESCE(s.prenom || ' ' || s.nom, 'Inconnu'),
      s.supprime_le,
      (
        lower(COALESCE(s.email, '')) LIKE '%@supprime.jolene.app'
        OR EXISTS (
          SELECT 1 FROM public.journaux_audit j
          WHERE j.id_ressource = s.id
            AND j.action = 'RGPD_SUPPRESSION_COMPTE'
        )
      )
    INTO v_nom, v_supprime_le, v_est_suppression_rgpd
    FROM public.soignants s
    WHERE s.id = p_id
    FOR UPDATE;
  ELSE
    SELECT
      COALESCE(e.nom, 'Inconnu'),
      e.peut_publier_missions,
      e.supprime_le,
      (
        lower(COALESCE(e.email_contact, '')) LIKE '%@supprime.jolene.app'
        OR COALESCE(e.bloque_auto_raisons, '[]'::jsonb) ? 'COMPTE_SUPPRIME_RGPD'
        OR EXISTS (
          SELECT 1 FROM public.journaux_audit j
          WHERE j.id_ressource = e.id
            AND j.action = 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'
        )
      )
    INTO v_nom, v_peut_publier_avant, v_supprime_le, v_est_suppression_rgpd
    FROM public.etablissements e
    WHERE e.id = p_id
    FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Compte introuvable');
  END IF;

  SELECT u.banned_until
  INTO v_banned_until_courant
  FROM auth.users u
  WHERE u.id = p_id AND u.deleted_at IS NULL
  FOR UPDATE;
  v_auth_trouve := FOUND;

  SELECT EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = p_table AND sp.id_ressource = p_id
  ) INTO v_provenance_suspension;

  IF v_est_suppression_rgpd THEN
    RETURN jsonb_build_object(
      'error',
      'Compte supprimé au titre du RGPD : suspension et réactivation interdites'
    );
  END IF;

  IF p_suspendre THEN
    IF v_supprime_le IS NOT NULL AND NOT v_provenance_suspension THEN
      RETURN jsonb_build_object(
        'error',
        'Compte déjà supprimé sans provenance de suspension réversible'
      );
    END IF;

    INSERT INTO public.suspensions_profils_admin (
      type_ressource, id_ressource, supprime_le_avant,
      suspendu_le, suspendu_par, motif
    ) VALUES (
      p_table, p_id, v_supprime_le, v_maintenant, auth.uid(), v_motif
    )
    ON CONFLICT (type_ressource, id_ressource) DO UPDATE
      SET suspendu_par = EXCLUDED.suspendu_par,
          motif = EXCLUDED.motif;

    IF v_auth_trouve THEN
      SELECT sa.banned_until_pose
      INTO v_pose_precedente
      FROM public.suspensions_auth_admin sa
      WHERE sa.type_ressource = p_table
        AND sa.id_ressource = p_id
        AND sa.user_id = p_id
      FOR UPDATE;
      v_auth_state_existe := FOUND;

      IF NOT v_auth_state_existe THEN
        v_banned_until_pose := GREATEST(
          COALESCE(v_banned_until_courant, v_maintenant),
          v_maintenant + interval '100 years'
        );

        INSERT INTO public.suspensions_auth_admin (
          type_ressource, id_ressource, user_id,
          banned_until_avant, banned_until_pose,
          suspendu_le, suspendu_par, motif
        ) VALUES (
          p_table, p_id, p_id,
          v_banned_until_courant, v_banned_until_pose,
          v_maintenant, auth.uid(), v_motif
        );

        UPDATE auth.users
        SET banned_until = v_banned_until_pose,
            updated_at = v_maintenant
        WHERE id = p_id
          AND banned_until IS NOT DISTINCT FROM v_banned_until_courant;
      ELSIF v_banned_until_courant IS NOT DISTINCT FROM v_pose_precedente THEN
        -- Suspension répétée : conserver l'état antérieur, mais faire suivre
        -- la valeur CAS réellement posée. Un ban externe divergent est intact.
        v_banned_until_pose := GREATEST(
          COALESCE(v_banned_until_courant, v_maintenant),
          v_maintenant + interval '100 years'
        );

        UPDATE auth.users
        SET banned_until = v_banned_until_pose,
            updated_at = v_maintenant
        WHERE id = p_id
          AND banned_until IS NOT DISTINCT FROM v_pose_precedente;

        UPDATE public.suspensions_auth_admin
        SET banned_until_pose = v_banned_until_pose,
            suspendu_par = auth.uid(),
            motif = v_motif
        WHERE type_ressource = p_table
          AND id_ressource = p_id
          AND user_id = p_id;
      END IF;
    END IF;

    IF p_table = 'soignants' THEN
      UPDATE public.soignants
      SET supprime_le = COALESCE(supprime_le, v_maintenant),
          modifie_le = v_maintenant
      WHERE id = p_id;
    ELSE
      INSERT INTO public.suspensions_etablissement_admin (
        etablissement_id, peut_publier_avant, suspendu_le, suspendu_par, motif
      ) VALUES (
        p_id, v_peut_publier_avant, v_maintenant, auth.uid(), v_motif
      )
      ON CONFLICT (etablissement_id) DO NOTHING;

      INSERT INTO public.suspensions_membres_etablissement_admin (
        etablissement_id, membre_id, user_id, actif_avant, desactive_le,
        suspendu_par, motif
      )
      SELECT p_id, m.id, m.user_id, m.actif, v_maintenant, auth.uid(), v_motif
      FROM public.membres_etablissement m
      WHERE m.etablissement_id = p_id
        AND m.actif IS TRUE
      ON CONFLICT (etablissement_id, membre_id) DO UPDATE
        SET desactive_le = EXCLUDED.desactive_le,
            suspendu_par = EXCLUDED.suspendu_par,
            motif = EXCLUDED.motif;

      UPDATE public.membres_etablissement m
      SET actif = false,
          maj_le = v_maintenant
      WHERE m.etablissement_id = p_id
        AND m.actif IS TRUE;
      GET DIAGNOSTICS v_membres = ROW_COUNT;

      UPDATE public.etablissements
      SET supprime_le = COALESCE(supprime_le, v_maintenant),
          peut_publier_missions = false,
          modifie_le = v_maintenant
      WHERE id = p_id;
    END IF;
  ELSE
    IF NOT v_provenance_suspension THEN
      RETURN jsonb_build_object(
        'error',
        'Aucune suspension administrateur réversible pour ce compte'
      );
    END IF;

    IF p_table = 'soignants' THEN
      UPDATE public.soignants s
      SET supprime_le = sp.supprime_le_avant,
          modifie_le = v_maintenant
      FROM public.suspensions_profils_admin sp
      WHERE s.id = p_id
        AND sp.type_ressource = 'soignants'
        AND sp.id_ressource = s.id;
    ELSE
      DELETE FROM public.suspensions_etablissement_admin se
      WHERE se.etablissement_id = p_id
      RETURNING se.peut_publier_avant INTO v_peut_publier_avant;

      UPDATE public.etablissements e
      SET supprime_le = sp.supprime_le_avant,
          peut_publier_missions = (
            COALESCE(v_peut_publier_avant, false)
            AND e.statut_verification = 'VERIFIE'
            AND e.siret_verifie IS TRUE
            AND e.finess_verifie IS TRUE
            AND e.representant_identite_verifiee IS TRUE
            AND e.rattachement_verifie IS TRUE
            AND e.contrat_service_signe IS TRUE
            AND e.bloque_auto_le IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM public.factures f
              WHERE f.etablissement_id = e.id
                AND f.statut IN ('EMISE', 'EN_RETARD')
                AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis
                AND f.date_echeance < current_date
            )
          ),
          modifie_le = v_maintenant
      FROM public.suspensions_profils_admin sp
      WHERE e.id = p_id
        AND sp.type_ressource = 'etablissements'
        AND sp.id_ressource = e.id;

      UPDATE public.membres_etablissement m
      SET actif = sm.actif_avant,
          maj_le = v_maintenant
      FROM public.suspensions_membres_etablissement_admin sm
      WHERE sm.etablissement_id = p_id
        AND sm.membre_id = m.id
        AND m.etablissement_id = sm.etablissement_id
        AND m.user_id = sm.user_id
        AND m.actif IS FALSE
        AND m.maj_le = sm.desactive_le;
      GET DIAGNOSTICS v_membres = ROW_COUNT;

      DELETE FROM public.suspensions_membres_etablissement_admin sm
      WHERE sm.etablissement_id = p_id;
    END IF;

    UPDATE auth.users u
    SET banned_until = sa.banned_until_avant,
        updated_at = v_maintenant
    FROM public.suspensions_auth_admin sa
    WHERE sa.type_ressource = p_table
      AND sa.id_ressource = p_id
      AND sa.user_id = u.id
      AND u.banned_until IS NOT DISTINCT FROM sa.banned_until_pose;

    DELETE FROM public.suspensions_auth_admin sa
    WHERE sa.type_ressource = p_table
      AND sa.id_ressource = p_id;

    DELETE FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = p_table
      AND sp.id_ressource = p_id;
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    auth.uid(), 'ADMIN',
    CASE WHEN p_suspendre THEN 'SUSPENSION_COMPTE' ELSE 'REACTIVATION_COMPTE' END,
    p_table, p_id,
    jsonb_build_object(
      'nom', v_nom,
      'table', p_table,
      'action', CASE WHEN p_suspendre THEN 'suspendre' ELSE 'réactiver' END,
      'motif', v_motif,
      'auth_synchronise', v_auth_trouve,
      'membres_affectes', v_membres
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', CASE WHEN p_suspendre THEN 'Compte suspendu : ' ELSE 'Compte réactivé : ' END || v_nom,
    'auth_synchronise', v_auth_trouve,
    'membres_affectes', v_membres
  );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_alerter_paiements_retard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_facture RECORD;
    v_montant_estime NUMERIC;
    v_count_emails INT := 0;
    v_count_missions_j7 INT := 0;
    v_count_missions_j21 INT := 0;
    v_count_factures_j7 INT := 0;
    v_count_factures_j21 INT := 0;
BEGIN
    FOR v_mission IN
        SELECT m.id, m.intitule, m.fin_le, m.net_a_payer, m.total_brut,
               m.relance_paiement_1_le, m.relance_paiement_2_le,
               m.soignant_assigne_id, m.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email,
               COALESCE(s.prenom, '') AS soignant_prenom,
               COALESCE(s.nom, '') AS soignant_nom
        FROM public.missions m
        JOIN public.etablissements e ON e.id = m.etablissement_id
        LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.statut = 'TERMINEE'
        AND m.type_contrat_applique = 'SALARIE'
        AND m.fin_le IS NOT NULL
        AND m.soignant_assigne_id IS NOT NULL
        AND (m.relance_paiement_1_le IS NULL OR m.relance_paiement_2_le IS NULL)
        AND NOT EXISTS (
            SELECT 1 FROM public.paiements_soignant ps
            WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME')
        )
    LOOP
        v_montant_estime := COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0);

        IF v_mission.fin_le + INTERVAL '7 days' <= NOW()
           AND v_mission.relance_paiement_1_le IS NULL THEN

            IF v_mission.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_mission.etablissement_id, v_mission.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'PAIEMENT_SOIGNANT',
                        'mission_id', v_mission.id,
                        'mission_intitule', v_mission.intitule,
                        'soignant_prenom', v_mission.soignant_prenom,
                        'soignant_nom', v_mission.soignant_nom,
                        'montant_estime', ROUND(v_montant_estime, 2),
                        'date_fin_mission', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_mission.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Rappel paiement soignant',
                'Rappel : paiement de ' || v_montant_estime || ' EUR a declarer pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || ').',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_1_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j7 := v_count_missions_j7 + 1;
        END IF;

        IF v_mission.fin_le + INTERVAL '21 days' <= NOW()
           AND v_mission.relance_paiement_2_le IS NULL THEN

            IF v_mission.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_mission.etablissement_id, v_mission.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'PAIEMENT_SOIGNANT',
                        'mission_id', v_mission.id,
                        'mission_intitule', v_mission.intitule,
                        'soignant_prenom', v_mission.soignant_prenom,
                        'soignant_nom', v_mission.soignant_nom,
                        'montant_estime', ROUND(v_montant_estime, 2),
                        'date_fin_mission', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_mission.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Paiement en retard (21 jours)',
                'Paiement de ' || v_montant_estime || ' EUR toujours non declare pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || '). Sans regularisation sous 24 jours la publication de nouvelles missions sera suspendue.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_2_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j21 := v_count_missions_j21 + 1;
        END IF;
    END LOOP;

    FOR v_facture IN
        SELECT f.id, f.numero_facture, f.montant_ttc, f.montant_a_payer, f.montant_avoirs_imputes, f.mode_paiement, f.date_emission,
               COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30) AS date_echeance,
               f.relance_1_le, f.relance_2_le, f.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email
        FROM public.factures f
        JOIN public.etablissements e ON e.id = f.etablissement_id
        WHERE f.statut IN ('EMISE', 'EN_RETARD')
        AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis
        AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30) IS NOT NULL
        AND (f.relance_1_le IS NULL OR f.relance_2_le IS NULL)
    LOOP
        IF v_facture.date_echeance + 7 <= (NOW() AT TIME ZONE 'Europe/Paris')::date
           AND v_facture.relance_1_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'montant_avoirs_imputes',v_facture.montant_avoirs_imputes,
                        'montant_a_payer',v_facture.montant_a_payer,'mode_paiement',v_facture.mode_paiement,
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'date_echeance', TO_CHAR(v_facture.date_echeance, 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Rappel facture commission',
                'Rappel : facture ' || COALESCE(v_facture.numero_facture, '-') || ' de ' || v_facture.montant_a_payer || ' EUR en attente de reglement.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_1_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j7 := v_count_factures_j7 + 1;
        END IF;

        IF v_facture.date_echeance + 21 <= (NOW() AT TIME ZONE 'Europe/Paris')::date
           AND v_facture.relance_2_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'montant_avoirs_imputes',v_facture.montant_avoirs_imputes,
                        'montant_a_payer',v_facture.montant_a_payer,'mode_paiement',v_facture.mode_paiement,
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'date_echeance', TO_CHAR(v_facture.date_echeance, 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Facture en retard (21 jours)',
                'Facture ' || COALESCE(v_facture.numero_facture, '-') || ' de ' || v_facture.montant_a_payer || ' EUR toujours impayee. Sans regularisation sous 24 jours la publication de nouvelles missions sera suspendue.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_2_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j21 := v_count_factures_j21 + 1;
        END IF;
    END LOOP;

    FOR v_mission IN
        SELECT p.id AS paiement_id, p.soignant_id, p.mission_id, p.montant_net,
               m.intitule, e.nom AS etab_nom
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.etablissements e ON e.id = p.etablissement_id
        WHERE p.statut = 'DECLARE'
        AND p.confirme_par_soignant = FALSE
        AND p.cree_le < NOW() - INTERVAL '15 days'
        AND p.relance_1_le IS NULL
    LOOP
        UPDATE public.paiements_soignant SET relance_1_le = NOW() WHERE id = v_mission.paiement_id;

        INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.soignant_id, 'SYSTEM',
            'Rappel : confirmez la reception du paiement',
            'L etablissement "' || COALESCE(v_mission.etab_nom, 'Etablissement') || '" a declare vous avoir paye ' || v_mission.montant_net || ' EUR pour "' || COALESCE(v_mission.intitule, 'Mission') || '". Merci de confirmer ou contester.',
            '/soignant/mes-gains', 'SOIGNANT');
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'emails_queued', v_count_emails,
        'missions_j7', v_count_missions_j7,
        'missions_j21', v_count_missions_j21,
        'factures_j7', v_count_factures_j7,
        'factures_j21', v_count_factures_j21
    );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_facture_id UUID;
    v_num TEXT;
    v_compteur INT := 0;
    v_mois TEXT;
    v_recalc_info JSONB;
    v_est_public BOOLEAN;
    v_delai_j INTEGER;
    v_echeance DATE;
BEGIN
    IF NOT fn_est_contexte_cron_ou_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    v_recalc_info := public.fn_recalculer_commissions_post_litige();
    v_mois := TO_CHAR(now(), 'YYYY-MM');

    FOR v_etab IN
        SELECT etablissement_id,
               COUNT(*) as nb,
               SUM(COALESCE(montant_commission_ht, 0)) as sum_ht,
               SUM(COALESCE(montant_commission_tva, 0)) as sum_tva,
               SUM(COALESCE(montant_commission_ttc, 0)) as sum_ttc
        FROM missions m
        WHERE m.statut = 'TERMINEE'
          AND m.commission_facturee = false
          AND NOT (m.mode_remuneration = 'RETROCESSION' AND m.honoraires_confirmes_le IS NULL)
          AND m.facture_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = m.id)
        GROUP BY etablissement_id
    LOOP
        IF v_etab.sum_ht <= 0 THEN CONTINUE; END IF;
        SELECT COALESCE(est_secteur_public, false) INTO v_est_public FROM etablissements WHERE id = v_etab.etablissement_id;
        v_delai_j := CASE WHEN v_est_public
                          THEN (public.fn_param_num('delai_paiement_public_j', 50))::integer
                          ELSE (public.fn_param_num('delai_paiement_prive_j', 30))::integer END;
        v_echeance := (now() + (v_delai_j::text || ' days')::interval)::date;
        v_compteur := v_compteur + 1;
        v_num := 'FACT-' || v_mois || '-' || LPAD(v_compteur::TEXT, 4, '0');
        INSERT INTO factures (etablissement_id, numero_facture, montant_ht, montant_tva, montant_ttc,
            nombre_missions, statut, date_emission, date_echeance, periode_debut, periode_fin)
        VALUES (v_etab.etablissement_id, v_num, v_etab.sum_ht, v_etab.sum_tva, v_etab.sum_ttc,
            v_etab.nb, 'BROUILLON', now(), v_echeance,
            date_trunc('month', now())::date,
            (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date)
        RETURNING id INTO v_facture_id;
        UPDATE missions SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id AND statut = 'TERMINEE'
          AND commission_facturee = false AND facture_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = missions.id);
        PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(v_facture_id);
    END LOOP;

    RETURN jsonb_build_object('success', true, 'factures_generees', v_compteur, 'recalc_post_litige', v_recalc_info);
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_blocage_publication_etab(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v record;
BEGIN
  IF public.est_admin() THEN RETURN NULL; END IF;
  IF p_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;

  SELECT peut_publier_missions, statut_verification, contrat_service_signe,
         bloque_auto_le, bloque_auto_raisons, finess_verifie,
         siret_verifie, representant_identite_verifiee, rattachement_verifie
    INTO v
  FROM public.etablissements
  WHERE id = p_etab_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;

  IF v.peut_publier_missions IS NOT TRUE OR v.statut_verification <> 'VERIFIE' THEN
    RETURN jsonb_build_object(
      'error', 'ETABLISSEMENT_NON_VERIFIE',
      'message', 'Votre établissement doit être vérifié avant de publier des missions.'
    );
  END IF;
  IF v.siret_verifie IS NOT TRUE OR v.finess_verifie IS NOT TRUE
     OR v.representant_identite_verifiee IS NOT TRUE
     OR v.rattachement_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'VERIFICATION_INCOMPLETE',
      'message', 'Les contrôles SIRET, FINESS, identité et habilitation du représentant doivent être validés.',
      'siret_verifie', COALESCE(v.siret_verifie, false),
      'finess_verifie', COALESCE(v.finess_verifie, false),
      'identite_verifiee', COALESCE(v.representant_identite_verifiee, false),
      'rattachement_verifie', COALESCE(v.rattachement_verifie, false)
    );
  END IF;
  IF v.contrat_service_signe IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'CONTRAT_SERVICE_REQUIS',
      'message', 'Le contrat de service Jolene doit être signé avant de publier des missions.'
    );
  END IF;
  IF v.bloque_auto_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'PUBLICATION_SUSPENDUE',
      'message', 'Publication suspendue en raison d obligations de paiement à régulariser.',
      'bloque_auto_le', v.bloque_auto_le,
      'raisons', v.bloque_auto_raisons
    );
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.factures
    WHERE etablissement_id = p_etab_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis
      AND date_echeance < current_date
  ) THEN
    RETURN jsonb_build_object('error', 'FACTURES_IMPAYEES', 'message', 'Vous avez des factures impayées à régulariser.');
  END IF;
  RETURN NULL;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_confirmer_virement_admin(p_facture_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_facture RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN json_build_object('error', 'Réservé aux administrateurs');
  END IF;

  SELECT id, statut, rapprochement_paiement_requis, montant_a_payer INTO v_facture FROM factures WHERE id = p_facture_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Facture introuvable');
  END IF;

  IF v_facture.rapprochement_paiement_requis OR v_facture.montant_a_payer<=0 THEN
    RETURN json_build_object('error','Facture soldée ou paiement à rapprocher.');
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
$function$

;
CREATE OR REPLACE FUNCTION public.fn_deposer_chorus(p_facture_id uuid, p_chorus_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_facture RECORD;
BEGIN
    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN '{"error":"Facture introuvable"}'::JSONB; END IF;
    IF v_facture.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    IF v_facture.rapprochement_paiement_requis OR v_facture.montant_a_payer<=0
      OR v_facture.statut NOT IN ('EMISE','EN_RETARD') THEN
      RETURN jsonb_build_object('error','Facture soldée ou paiement à rapprocher.'); END IF;
    UPDATE factures SET
        chorus_pro_statut = 'DEPOSEE',
        chorus_pro_deposee_le = NOW(),
        chorus_pro_id = p_chorus_id
    WHERE id = p_facture_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_detail_facture_internal_20260801(p_facture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_facture RECORD;
    v_missions JSONB;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN jsonb_build_object('error', 'Facture introuvable'); END IF;
    IF v_facture.etablissement_id != v_etab_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    -- PRIORITÉ 1 : missions liées par facture_id
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', m.id,
            'intitule', m.intitule,
            'service', m.service,
            'debut_le', m.debut_le,
            'fin_le', m.fin_le,
            'duree_heures', m.duree_heures,
            'taux_horaire_base', m.taux_horaire_base,
            'total_brut', m.total_brut,
            'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
            'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
            'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
            'taux_ifm', COALESCE(m.taux_ifm, 0),
            'montant_ifm', COALESCE(m.montant_ifm, 0),
            'taux_icp', COALESCE(m.taux_icp, 0),
            'montant_icp', COALESCE(m.montant_icp, 0),
            'taux_commission', m.taux_commission,
            'montant_commission_ht', m.montant_commission_ht,
            'montant_commission_tva', m.montant_commission_tva,
            'montant_commission_ttc', m.montant_commission_ttc,
            'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
            'profession', m.profession_requise::TEXT,
            'presences', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', p.id,
                    'pointage_arrivee_le', p.pointage_arrivee_le,
                    'pointage_depart_le', p.pointage_depart_le,
                    'methode_pointage_arrivee', p.methode_pointage_arrivee,
                    'methode_pointage_depart', p.methode_pointage_depart,
                    'heures_reelles', p.heures_reelles,
                    'duree_brute_min', p.duree_brute_min,
                    'duree_nette_min', p.duree_nette_min,
                    'duree_pause_min', p.duree_pause_min,
                    'retard_min', p.retard_min,
                    'depart_anticipe_min', p.depart_anticipe_min,
                    'perimetre_gps_valide', p.perimetre_gps_valide,
                    'alerte_teleportation', p.alerte_teleportation,
                    'valide_par_etablissement', p.valide_par_etablissement
                ) ORDER BY p.pointage_arrivee_le)
                FROM presences p
                WHERE p.mission_id = m.id
            ), '[]'::JSONB)
        ) ORDER BY m.debut_le
    ), '[]'::JSONB)
    INTO v_missions
    FROM missions m
    LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
    WHERE m.facture_id = p_facture_id;

    -- PRIORITÉ 2 : si aucune mission liée par FK, chercher par période
    IF v_missions = '[]'::JSONB AND v_facture.periode_debut IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'intitule', m.intitule,
                'service', m.service,
                'debut_le', m.debut_le,
                'fin_le', m.fin_le,
                'duree_heures', m.duree_heures,
                'taux_horaire_base', m.taux_horaire_base,
                'total_brut', m.total_brut,
                'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
                'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
                'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
                'taux_ifm', COALESCE(m.taux_ifm, 0),
                'montant_ifm', COALESCE(m.montant_ifm, 0),
                'taux_icp', COALESCE(m.taux_icp, 0),
                'montant_icp', COALESCE(m.montant_icp, 0),
                'taux_commission', m.taux_commission,
                'montant_commission_ht', m.montant_commission_ht,
                'montant_commission_tva', m.montant_commission_tva,
                'montant_commission_ttc', m.montant_commission_ttc,
                'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
                'profession', m.profession_requise::TEXT,
                'presences', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', p.id,
                        'pointage_arrivee_le', p.pointage_arrivee_le,
                        'pointage_depart_le', p.pointage_depart_le,
                        'methode_pointage_arrivee', p.methode_pointage_arrivee,
                        'methode_pointage_depart', p.methode_pointage_depart,
                        'heures_reelles', p.heures_reelles,
                        'duree_brute_min', p.duree_brute_min,
                        'duree_nette_min', p.duree_nette_min,
                        'duree_pause_min', p.duree_pause_min,
                        'retard_min', p.retard_min,
                        'depart_anticipe_min', p.depart_anticipe_min,
                        'perimetre_gps_valide', p.perimetre_gps_valide,
                        'alerte_teleportation', p.alerte_teleportation,
                        'valide_par_etablissement', p.valide_par_etablissement
                    ) ORDER BY p.pointage_arrivee_le)
                    FROM presences p
                    WHERE p.mission_id = m.id
                ), '[]'::JSONB)
            ) ORDER BY m.debut_le
        ), '[]'::JSONB)
        INTO v_missions
        FROM missions m
        LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
        WHERE m.etablissement_id = v_facture.etablissement_id
        AND m.statut = 'TERMINEE' AND m.commission_facturee = TRUE
        AND m.debut_le >= v_facture.periode_debut::TIMESTAMP
        AND m.debut_le < (v_facture.periode_fin + 1)::TIMESTAMP;
    END IF;

    -- PRIORITÉ 3 : mission unique si facture a mission_id
    IF v_missions = '[]'::JSONB AND v_facture.mission_id IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'intitule', m.intitule,
                'service', m.service,
                'debut_le', m.debut_le,
                'fin_le', m.fin_le,
                'duree_heures', m.duree_heures,
                'taux_horaire_base', m.taux_horaire_base,
                'total_brut', m.total_brut,
                'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
                'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
                'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
                'taux_ifm', COALESCE(m.taux_ifm, 0),
                'montant_ifm', COALESCE(m.montant_ifm, 0),
                'taux_icp', COALESCE(m.taux_icp, 0),
                'montant_icp', COALESCE(m.montant_icp, 0),
                'taux_commission', m.taux_commission,
                'montant_commission_ht', m.montant_commission_ht,
                'montant_commission_tva', m.montant_commission_tva,
                'montant_commission_ttc', m.montant_commission_ttc,
                'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
                'profession', m.profession_requise::TEXT,
                'presences', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', p.id,
                        'pointage_arrivee_le', p.pointage_arrivee_le,
                        'pointage_depart_le', p.pointage_depart_le,
                        'methode_pointage_arrivee', p.methode_pointage_arrivee,
                        'methode_pointage_depart', p.methode_pointage_depart,
                        'heures_reelles', p.heures_reelles,
                        'duree_brute_min', p.duree_brute_min,
                        'duree_nette_min', p.duree_nette_min,
                        'duree_pause_min', p.duree_pause_min,
                        'retard_min', p.retard_min,
                        'depart_anticipe_min', p.depart_anticipe_min,
                        'perimetre_gps_valide', p.perimetre_gps_valide,
                        'alerte_teleportation', p.alerte_teleportation,
                        'valide_par_etablissement', p.valide_par_etablissement
                    ) ORDER BY p.pointage_arrivee_le)
                    FROM presences p
                    WHERE p.mission_id = m.id
                ), '[]'::JSONB)
            )
        ), '[]'::JSONB)
        INTO v_missions
        FROM missions m
        LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
        WHERE m.id = v_facture.mission_id;
    END IF;

    RETURN jsonb_build_object(
        'facture', jsonb_build_object(
            'id', v_facture.id, 'numero_facture', v_facture.numero_facture,
            'statut', v_facture.statut, 'montant_ht', v_facture.montant_ht,
            'taux_tva', v_facture.taux_tva, 'montant_tva', v_facture.montant_tva,
            'montant_ttc', v_facture.montant_ttc,
            'montant_avoirs_imputes',v_facture.montant_avoirs_imputes,'montant_a_payer',v_facture.montant_a_payer,
            'rapprochement_paiement_requis',v_facture.rapprochement_paiement_requis,'type_document',v_facture.type_document,
            'avoirs',private.fn_avoirs_commission_detail(v_facture.id), 'nombre_missions', v_facture.nombre_missions,
            'mode_paiement', v_facture.mode_paiement,
            'periode_debut', v_facture.periode_debut, 'periode_fin', v_facture.periode_fin,
            'date_emission', v_facture.date_emission, 'date_echeance', v_facture.date_echeance,
            'date_paiement', v_facture.date_paiement
        ),
        'missions', v_missions
    );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_email_factures_impayees()
 RETURNS TABLE(email text, nom_etablissement text, numero_facture text, montant_ttc text, jours_depuis integer, etablissement_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.email_contact, e.nom, f.numero_facture,
        ROUND(f.montant_a_payer, 2)::TEXT,
        (CURRENT_DATE - f.date_echeance)::INTEGER, e.id
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE f.statut IN ('EMISE', 'EN_RETARD')
    AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis
      AND f.date_echeance < CURRENT_DATE
      AND e.email_contact IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM emails_envoyes ee
          WHERE ee.type = 'RAPPEL_FACTURE'
            AND ee.sujet LIKE '%' || f.numero_facture || '%'
            AND ee.cree_le > NOW() - INTERVAL '7 days'
      );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_generer_facture_mensuelle_internal_20260801(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
    v_total_ht NUMERIC; v_total_tva NUMERIC; v_total_ttc NUMERIC;
    v_nb INT; v_numero TEXT; v_facture_id UUID;
BEGIN
    IF p_etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;
    SELECT COALESCE(SUM(montant_commission_ht), 0), COALESCE(SUM(montant_commission_tva), 0),
           COALESCE(SUM(montant_commission_ttc), 0), COUNT(*)
    INTO v_total_ht, v_total_tva, v_total_ttc, v_nb
    FROM missions WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND commission_facturee = FALSE;
    IF v_total_ht = 0 THEN RETURN '{"error":"Aucune mission à facturer"}'::JSONB; END IF;
    v_numero := fn_generer_numero_facture();
    INSERT INTO factures (etablissement_id, numero_facture, statut, montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, date_emission, date_echeance, periode_debut, periode_fin)
    VALUES (p_etablissement_id, v_numero, 'BROUILLON', v_total_ht, 20, v_total_tva, v_total_ttc,
        v_nb, NOW(), (NOW() + INTERVAL '30 days')::DATE,
        DATE_TRUNC('month', NOW())::DATE, (DATE_TRUNC('month', NOW()) + INTERVAL '1 month' - INTERVAL '1 day')::DATE)
    RETURNING id INTO v_facture_id;
    UPDATE missions SET commission_facturee = TRUE, facture_id = v_facture_id
    WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND commission_facturee = FALSE;
    PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(v_facture_id);
    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero, 'montant_ttc', v_total_ttc, 'nb_missions', v_nb);
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_gerer_blocage_etabs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_paiements_retard_nb INT;
    v_paiements_retard_montant NUMERIC;
    v_factures_retard_nb INT;
    v_factures_retard_montant NUMERIC;
    v_raisons JSONB;
    v_blocages INT := 0;
    v_deblocages INT := 0;
    v_seuil_j integer := (public.fn_param_num('seuil_blocage_retard_j', 45))::integer;
    v_seuil interval := (v_seuil_j::text || ' days')::interval;
BEGIN
    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NULL
          AND statut_verification = 'VERIFIE'
          AND supprime_le IS NULL
    LOOP
        SELECT COUNT(*), COALESCE(SUM(COALESCE(m.net_a_payer, m.total_brut, 0)), 0)
        INTO v_paiements_retard_nb, v_paiements_retard_montant
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le IS NOT NULL
          AND m.fin_le < NOW() - v_seuil
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*), COALESCE(SUM(f.montant_a_payer), 0)
        INTO v_factures_retard_nb, v_factures_retard_montant
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis
          AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30) IS NOT NULL
          AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30)
          < (NOW() AT TIME ZONE 'Europe/Paris')::date - v_seuil_j;

        IF v_paiements_retard_nb > 0 OR v_factures_retard_nb > 0 THEN
            v_raisons := jsonb_build_object(
                'paiements_retard_nb', v_paiements_retard_nb,
                'paiements_retard_montant', ROUND(v_paiements_retard_montant, 2),
                'factures_retard_nb', v_factures_retard_nb,
                'factures_retard_montant', ROUND(v_factures_retard_montant, 2),
                'seuil_jours', v_seuil_j
            );

            UPDATE public.etablissements
            SET bloque_auto_le = NOW(),
                bloque_auto_raisons = v_raisons
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action, raisons)
            VALUES (v_etab.id, 'BLOCAGE', v_raisons);

            IF v_etab.email_contact IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PUBLICATION_SUSPENDUE', v_etab.id, v_etab.email_contact,
                    jsonb_build_object(
                        'etablissement_nom', v_etab.nom,
                        'obligations_en_cours',
                          CASE WHEN v_paiements_retard_nb > 0 THEN v_paiements_retard_nb || ' paiement(s) soignant(s) en retard (' || ROUND(v_paiements_retard_montant, 2) || ' EUR)' ELSE '' END
                          || CASE WHEN v_paiements_retard_nb > 0 AND v_factures_retard_nb > 0 THEN '<br/>' ELSE '' END
                          || CASE WHEN v_factures_retard_nb > 0 THEN v_factures_retard_nb || ' facture(s) commission en retard (' || ROUND(v_factures_retard_montant, 2) || ' EUR)' ELSE '' END,
                        'total_montant_du', ROUND(v_paiements_retard_montant + v_factures_retard_montant, 2),
                        'date_blocage', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY')
                    ));
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions suspendue',
                'Regularisez vos obligations (paiements soignants et factures commission) pour reactiver votre compte.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT');

            v_blocages := v_blocages + 1;
        END IF;
    END LOOP;

    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NOT NULL
          AND supprime_le IS NULL
    LOOP
        SELECT COUNT(*) INTO v_paiements_retard_nb
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le < NOW() - v_seuil
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*) INTO v_factures_retard_nb
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis
          AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30)
          < (NOW() AT TIME ZONE 'Europe/Paris')::date - v_seuil_j;

        IF v_paiements_retard_nb = 0 AND v_factures_retard_nb = 0 THEN
            UPDATE public.etablissements
            SET bloque_auto_le = NULL,
                bloque_auto_raisons = NULL
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action)
            VALUES (v_etab.id, 'DEBLOCAGE');

            IF v_etab.email_contact IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PUBLICATION_REACTIVEE', v_etab.id, v_etab.email_contact,
                    jsonb_build_object(
                        'etablissement_nom', v_etab.nom,
                        'debloque_le', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI')
                    ));
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions reactivee',
                'Votre compte est a nouveau autorise a publier des missions.',
                '/etablissement/dashboard', 'ETABLISSEMENT');

            v_deblocages := v_deblocages + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'blocages', v_blocages,
        'deblocages', v_deblocages
    );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_mes_factures_internal_20260801()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(f) ORDER BY f.date_emission DESC), '[]'::JSONB)
    INTO v_result
    FROM (
        SELECT 
            id, numero_facture, statut, 
            montant_ht, taux_tva, montant_tva, montant_ttc,
            montant_avoirs_imputes,montant_a_payer,rapprochement_paiement_requis,type_document,
            private.fn_avoirs_commission_detail(id) AS avoirs,
            nombre_missions, mode_paiement,
            periode_debut, periode_fin,
            date_emission, date_echeance, date_paiement,
            stripe_hosted_url, est_secteur_public,
            chorus_pro_statut, chorus_pro_id,
            virement_reference, virement_confirme_le
        FROM factures 
        WHERE etablissement_id = v_etab_id
        ORDER BY date_emission DESC
    ) f;

    RETURN v_result;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_obligations_financieres_internal_20260801()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_total_soignants_du numeric := 0;
  v_total_commissions_du numeric := 0;
  v_lignes jsonb := '[]'::jsonb;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  WITH obligations AS (
    SELECT
      ('facture:' || fh.id::text) AS payment_key,
      m.id::text AS mission_id,
      fh.id::text AS facture_honoraires_id,
      m.intitule,
      m.debut_le,
      m.fin_le,
      fh.periode_debut,
      fh.periode_fin,
      fh.est_facture_finale_mission,
      fh.montant_ttc AS total_brut,
      fh.montant_ttc AS net_a_payer,
      COALESCE(fc.montant_ttc, 0) AS montant_commission_ttc,
      m.soignant_assigne_id::text AS soignant_id,
      GREATEST(0, EXTRACT(EPOCH FROM (
        LEAST(m.fin_le, (fh.periode_fin + 1)::timestamptz)
        - GREATEST(m.debut_le, fh.periode_debut::timestamptz)
      )) / 3600) AS heures,
      (CURRENT_DATE - fh.periode_fin)::integer AS jours_depuis_fin,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
      s.profession::text AS soignant_profession,
      s.type_exercice AS soignant_type_exercice,
      m.type_contrat_applique::text AS type_contrat_applique,
      m.type_paiement_soignant AS type_paiement_soignant,
      COALESCE(m.mode_paiement_soignant, 'STRIPE_CONNECT') AS mode_paiement_soignant,
      (s.stripe_account_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.stripe_connect_onboarding sco
        WHERE sco.soignant_id = s.id
          AND sco.charges_enabled = true
          AND sco.payouts_enabled = true
      )) AS soignant_stripe_connect,
      EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
      ) AS a_paiement_conteste,
      (
        SELECT p.id::text FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
        ORDER BY p.cree_le DESC LIMIT 1
      ) AS paiement_conteste_id,
      fh.periode_fin::timestamptz AS ordre_fin
    FROM public.factures_honoraires fh
    JOIN public.missions m ON m.id = fh.mission_id
    JOIN public.soignants s ON s.id = fh.soignant_id
    LEFT JOIN public.factures fc
      ON fc.facture_honoraire_id = fh.id
     AND fc.type_document = 'FACTURE'
     AND fc.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    WHERE fh.etablissement_id = v_etab_id
      AND fh.type_document = 'FACTURE'
      AND fh.statut IN ('EMISE', 'EN_RETARD')
      AND m.type_contrat_applique = 'LIBERAL'
      AND m.statut IN ('EN_COURS', 'TERMINEE')
      AND (m.statut = 'TERMINEE' OR (NOT fh.est_facture_finale_mission AND fh.periode_fin < CURRENT_DATE))
      AND NOT EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.facture_honoraire_id = fh.id
          AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.stripe_transfers st
        WHERE st.facture_honoraire_id = fh.id
          AND st.statut IN ('TRANSFERE', 'CHARGE_REUSSI', 'PAYE')
      )

    UNION ALL

    SELECT
      ('mission:' || m.id::text), m.id::text, NULL::text, m.intitule,
      m.debut_le, m.fin_le, m.debut_le::date, m.fin_le::date, true,
      m.total_brut, m.net_a_payer, m.montant_commission_ttc,
      m.soignant_assigne_id::text,
      EXTRACT(EPOCH FROM (m.fin_le - m.debut_le)) / 3600,
      EXTRACT(DAY FROM now() - m.fin_le)::integer,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, ''),
      s.profession::text, s.type_exercice,
      m.type_contrat_applique::text, m.type_paiement_soignant,
      m.mode_paiement_soignant, false,
      EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
      ),
      (
        SELECT p.id::text FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
        ORDER BY p.cree_le DESC LIMIT 1
      ),
      m.fin_le
    FROM public.missions m
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE m.etablissement_id = v_etab_id
      AND m.statut = 'TERMINEE'
      AND m.type_contrat_applique = 'SALARIE'
      AND NOT EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
      )
  )
  SELECT
    COALESCE(sum(o.net_a_payer), 0),
    COALESCE(jsonb_agg(to_jsonb(o) - 'ordre_fin' ORDER BY o.ordre_fin), '[]'::jsonb)
  INTO v_total_soignants_du, v_lignes
  FROM obligations o;

  SELECT COALESCE(sum(f.montant_a_payer), 0)
  INTO v_total_commissions_du
  FROM public.factures f
  WHERE f.etablissement_id = v_etab_id
    AND f.statut IN ('EMISE', 'EN_RETARD')
    AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis;

  RETURN jsonb_build_object(
    'total_du', v_total_soignants_du + v_total_commissions_du,
    'total_soignants_du', v_total_soignants_du,
    'total_commissions_du', v_total_commissions_du,
    'nb_missions_non_payees', jsonb_array_length(v_lignes),
    'nb_paiements_en_attente', (
      SELECT count(*) FROM public.paiements_soignant
      WHERE etablissement_id = v_etab_id AND statut = 'DECLARE'
    ),
    'nb_factures_impayees', (
      SELECT count(*) FROM public.factures
      WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
        AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis
    ),
    'nb_factures_commission_historique', (
      SELECT count(*) FROM public.factures
      WHERE etablissement_id = v_etab_id
        AND (statut IN ('PAYEE', 'ANNULEE')
          OR (type_document = 'AVOIR' AND statut IN ('EMISE', 'EN_RETARD')))
    ),
    'missions_non_payees', v_lignes,
    'paiements_soignants_en_attente', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT p.id::text AS paiement_id, p.mission_id::text, p.montant_net,
          p.methode, p.reference_virement, p.date_paiement, p.statut,
          m.intitule AS mission_intitule,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          s.profession::text AS soignant_profession,
          COALESCE(p.facture_honoraire_id::text, (
            SELECT fh.id::text FROM public.factures_honoraires fh
            WHERE fh.mission_id = m.id ORDER BY fh.date_emission DESC LIMIT 1
          )) AS facture_honoraires_id
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.soignants s ON s.id = p.soignant_id
        WHERE p.etablissement_id = v_etab_id AND p.statut = 'DECLARE'
        ORDER BY p.date_paiement DESC
      ) x
    ), '[]'::jsonb),
    'paiements_soignants_confirmes', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT p.id::text AS paiement_id, p.mission_id::text, p.montant_net,
          p.methode, p.reference_virement, p.date_paiement,
          p.confirme_par_soignant_le, m.intitule AS mission_intitule,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          p.facture_honoraire_id::text AS facture_honoraires_id
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.soignants s ON s.id = p.soignant_id
        WHERE p.etablissement_id = v_etab_id AND p.statut = 'CONFIRME'
        ORDER BY p.confirme_par_soignant_le DESC LIMIT 10
      ) x
    ), '[]'::jsonb),
    'factures_impayees', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT f.id::text AS facture_id, f.numero_facture, f.montant_ht,
          f.montant_tva, f.montant_ttc, f.montant_avoirs_imputes, f.montant_a_payer, f.rapprochement_paiement_requis, f.nombre_missions, f.date_echeance,
          f.statut, f.type_document, f.stripe_hosted_url, f.est_secteur_public,
          f.chorus_pro_statut, f.chorus_pro_numero_flux
        FROM public.factures f
        WHERE f.etablissement_id = v_etab_id
          AND f.statut IN ('EMISE', 'EN_RETARD', 'VIREMENT_DECLARE')
          AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
        ORDER BY f.date_echeance
      ) x
    ), '[]'::jsonb),
    'factures_commission_historique', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT f.id::text AS facture_id, f.numero_facture, f.statut, f.type_document,
          f.montant_ttc, f.montant_avoirs_imputes, f.montant_a_payer, f.rapprochement_paiement_requis, f.nombre_missions, f.date_emission, f.date_paiement,
          f.mode_paiement, f.virement_reference, f.stripe_payment_intent_id,
          f.mission_id::text AS mission_id, f.facture_honoraire_id::text,
          f.est_secteur_public, f.chorus_pro_statut
        FROM public.factures f
        WHERE f.etablissement_id = v_etab_id
          AND (f.statut IN ('PAYEE', 'ANNULEE')
            OR (f.type_document = 'AVOIR' AND f.statut IN ('EMISE', 'EN_RETARD')))
        ORDER BY COALESCE(f.date_paiement, f.date_emission) DESC NULLS LAST, f.id DESC LIMIT 10
      ) x
    ), '[]'::jsonb),
    'missions_non_facturees', '[]'::jsonb
  );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_preparer_avoir_commission_honoraires(p_avoir_honoraires_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mission_verrou uuid;
  v_avoir_h public.factures_honoraires%ROWTYPE;
  v_origine_h public.factures_honoraires%ROWTYPE;
  v_origine_c public.factures%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_taux_commission numeric;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_numero text;
  v_avoir_c_id uuid;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  -- Même ordre que réservation, acquisition et résolution : mission avant pièce.
  -- La seconde lecture refuse une réaffectation concurrente, sans réécrire la pièce.
  SELECT mission_id INTO v_mission_verrou FROM public.factures_honoraires WHERE id=p_avoir_honoraires_id;
  PERFORM 1 FROM public.missions WHERE id=v_mission_verrou FOR UPDATE;

  SELECT * INTO v_avoir_h
  FROM public.factures_honoraires
  WHERE id = p_avoir_honoraires_id
    AND mission_id IS NOT DISTINCT FROM v_mission_verrou
    AND type_document = 'AVOIR'
    AND nature_correction = 'AVOIR'
    AND statut IN ('EMISE', 'REMBOURSE')
  FOR UPDATE;
  IF NOT FOUND OR v_avoir_h.facture_precedente_id IS NULL THEN
    RAISE EXCEPTION 'Avoir d''honoraires introuvable ou non émis';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_avoir_h.id
    AND type_document = 'AVOIR'
    AND statut NOT IN ('ANNULEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc, 'existing', true
    );
  END IF;

  SELECT * INTO v_origine_h
  FROM public.factures_honoraires
  WHERE id = v_avoir_h.facture_precedente_id
  FOR UPDATE;
  IF NOT FOUND OR v_origine_h.montant_ht <= 0 THEN
    RAISE EXCEPTION 'Facture d''honoraires d''origine incohérente';
  END IF;

  SELECT * INTO v_origine_c
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_h.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND OR v_origine_c.montant_ht <= 0 THEN
    RAISE EXCEPTION 'Facture Jolene d''origine introuvable';
  END IF;

  v_taux_commission := v_origine_c.montant_ht / v_origine_h.montant_ht;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;
  v_ht := round(v_avoir_h.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  IF v_ht <= 0 OR v_ttc <= 0 THEN
    RAISE EXCEPTION 'Montant de l''avoir Jolene incohérent';
  END IF;

  v_numero := public.next_avoir_commission_number(v_avoir_h.etablissement_id);
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id,
    numero_facture, type_document, facture_precedente_id,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, periode_debut, periode_fin,
    est_secteur_public, mode_paiement
  ) VALUES (
    v_avoir_h.etablissement_id, v_avoir_h.mission_id, v_avoir_h.id,
    v_numero, 'AVOIR', v_origine_c.id,
    v_ht, 20, v_tva, v_ttc, 1,
    'EMISE', now(), CURRENT_DATE,
    v_origine_c.periode_debut, v_origine_c.periode_fin,
    v_origine_c.est_secteur_public, v_origine_c.mode_paiement
  ) RETURNING id INTO v_avoir_c_id;
  PERFORM private.fn_inscrire_avoir_commission(v_avoir_c_id,v_avoir_h.mission_id,'LITIGE_HONORAIRES');

  UPDATE public.missions
  SET total_brut = GREATEST(0, COALESCE(total_brut, 0) - v_avoir_h.montant_ht),
      net_a_payer = GREATEST(0, COALESCE(net_a_payer, 0) - v_avoir_h.montant_ttc),
      montant_commission_ht = GREATEST(0, COALESCE(montant_commission_ht, 0) - v_ht),
      montant_commission_tva = GREATEST(0, COALESCE(montant_commission_tva, 0) - v_tva),
      montant_commission_ttc = GREATEST(0, COALESCE(montant_commission_ttc, 0) - v_ttc),
      commission_a_recalculer = false,
      modifie_le = now()
  WHERE id = v_avoir_h.mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_avoir_h.etablissement_id,
    p_type_acteur := 'SYSTEME',
    p_action := 'FACTURATION',
    p_type_ressource := 'facture',
    p_id_ressource := v_avoir_c_id,
    p_details := jsonb_build_object(
      'evenement', 'AVOIR_COMMISSION_APRES_LITIGE',
      'avoir_honoraires_id', v_avoir_h.id,
      'facture_commission_origine_id', v_origine_c.id,
      'taux_commission_historique', v_taux_commission,
      'montant_ht', v_ht,
      'montant_tva', v_tva,
      'montant_ttc', v_ttc
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_avoir_c_id,
    'numero_facture', v_numero,
    'montant_ht', v_ht, 'montant_tva', v_tva,
    'montant_ttc', v_ttc, 'existing', false
  );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_recalculer_commissions_post_litige()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission            RECORD;
  v_new_brut           NUMERIC(12,2);
  v_new_commission_ht  NUMERIC(12,2);
  v_new_commission_tva NUMERIC(12,2);
  v_new_commission_ttc NUMERIC(12,2);
  v_delta_ht           NUMERIC(12,2);
  v_delta_tva          NUMERIC(12,2);
  v_delta_ttc          NUMERIC(12,2);
  v_doc_number         TEXT;
  v_doc_type           TEXT;
  v_processed_unbilled INT := 0;
  v_avoirs_emis        INT := 0;
  v_fc_emises          INT := 0;
  v_notifs_envoyees    INT := 0;
  v_mission_intitule   TEXT;
  v_litige_id          UUID;
  v_avoir_id uuid;
  v_imputation jsonb;
BEGIN
  FOR v_mission IN
    SELECT id, taux_commission, facture_id, commission_facturee,
           montant_commission_ht, etablissement_id, intitule
      FROM public.missions
     WHERE commission_a_recalculer = TRUE
     ORDER BY id
     FOR UPDATE SKIP LOCKED
  LOOP
    SELECT COALESCE(SUM(fh.montant_signe), 0) INTO v_new_brut
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE')
       AND fh.statut_litige <> 'EN_ATTENTE_LITIGE';

    v_new_commission_ht  := ROUND(v_new_brut * COALESCE(v_mission.taux_commission, 15) / 100.0, 2);
    v_new_commission_tva := ROUND(v_new_commission_ht * 0.20, 2);
    v_new_commission_ttc := v_new_commission_ht + v_new_commission_tva;

    IF v_mission.facture_id IS NULL
       AND COALESCE(v_mission.commission_facturee, FALSE) = FALSE THEN
      UPDATE public.missions
         SET montant_commission_ht  = v_new_commission_ht,
             montant_commission_tva = v_new_commission_tva,
             montant_commission_ttc = v_new_commission_ttc,
             commission_a_recalculer = FALSE
       WHERE id = v_mission.id;
      v_processed_unbilled := v_processed_unbilled + 1;
      CONTINUE;
    END IF;

    v_delta_ht := COALESCE(v_mission.montant_commission_ht, 0) - v_new_commission_ht;

    IF v_delta_ht = 0 THEN
      UPDATE public.missions SET commission_a_recalculer = FALSE
       WHERE id = v_mission.id;
      v_processed_unbilled := v_processed_unbilled + 1;
      CONTINUE;
    END IF;

    v_delta_tva := ROUND(abs(v_delta_ht) * 0.20, 2);
    v_delta_ttc := abs(v_delta_ht) + v_delta_tva;

    IF v_delta_ht > 0 THEN
      v_doc_number := public.next_avoir_commission_number(v_mission.etablissement_id);
      v_doc_type := 'AVOIR';
      INSERT INTO public.factures (
        etablissement_id, numero_facture, type_document, facture_precedente_id,
        montant_ht, montant_tva, montant_ttc, nombre_missions,
        statut, date_emission, date_echeance, periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_doc_number, 'AVOIR', v_mission.facture_id,
        v_delta_ht, v_delta_tva, v_delta_ttc, 1,
        'EMISE', now(), (now() + INTERVAL '30 days')::date,
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
      );
      SELECT id INTO STRICT v_avoir_id FROM public.factures WHERE numero_facture=v_doc_number;
      v_imputation:=private.fn_inscrire_avoir_commission(v_avoir_id,v_mission.id,'RECALCUL_COMMISSION');
      v_avoirs_emis := v_avoirs_emis + 1;
    ELSE
      v_doc_number := public.next_facture_complementaire_number(v_mission.etablissement_id);
      v_doc_type := 'FACTURE_COMPLEMENTAIRE';
      INSERT INTO public.factures (
        etablissement_id, numero_facture, type_document, facture_precedente_id,
        montant_ht, montant_tva, montant_ttc, nombre_missions,
        statut, date_emission, date_echeance, periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_doc_number, 'FACTURE_COMPLEMENTAIRE',
        v_mission.facture_id,
        abs(v_delta_ht), v_delta_tva, v_delta_ttc, 1,
        'EMISE', now(), (now() + INTERVAL '30 days')::date,
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
      );
      v_fc_emises := v_fc_emises + 1;
    END IF;

    UPDATE public.missions
       SET montant_commission_ht  = v_new_commission_ht,
           montant_commission_tva = v_new_commission_tva,
           montant_commission_ttc = v_new_commission_ttc,
           commission_a_recalculer = FALSE
     WHERE id = v_mission.id;

    SELECT DISTINCT fh.litige_id INTO v_litige_id
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.litige_id IS NOT NULL
     ORDER BY fh.litige_id
     LIMIT 1;

    v_mission_intitule := COALESCE(v_mission.intitule, 'Mission #' || v_mission.id::text);

    PERFORM public.fn_litige_push_notification(
      v_mission.etablissement_id,
      'ETABLISSEMENT',
      'COMMISSION_AJUSTEE',
      CASE WHEN v_doc_type = 'AVOIR'
        THEN 'Avoir commission ' || v_doc_number || ' émis'
        ELSE 'Facture complémentaire ' || v_doc_number || ' émise'
      END,
      CASE WHEN v_doc_type = 'AVOIR'
        THEN 'Un avoir de ' || v_delta_ttc || ' € a été émis sur la commission de la mission "' || v_mission_intitule || '". ' || (v_imputation->>'message')
        ELSE 'Une facture complémentaire de ' || v_delta_ttc || ' € a été émise sur la commission de la mission "' || v_mission_intitule || '". Due aux conditions habituelles.'
      END,
      v_litige_id,
      jsonb_build_object(
        'type_document', v_doc_type,
        'numero_document', v_doc_number,
        'montant', v_delta_ttc,
        'mission_id', v_mission.id,
        'mission_intitule', v_mission_intitule,
        'etablissement_id', v_mission.etablissement_id
      )
    );
    v_notifs_envoyees := v_notifs_envoyees + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_unbilled', v_processed_unbilled,
    'deferred_to_fix9_billed', 0,
    'avoirs_commission_emis', v_avoirs_emis,
    'factures_complementaires_emises', v_fc_emises,
    'notifications_envoyees', v_notifs_envoyees
  );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_reserver_email_facturation(p_email_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE l private.facturation_email_livraisons; q public.email_queue; document jsonb; jeton uuid;
BEGIN
  SELECT * INTO l FROM private.facturation_email_livraisons WHERE email_id = p_email_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('statut', 'ABSENT'); END IF;
  SELECT * INTO q FROM public.email_queue WHERE id = p_email_id FOR UPDATE;
  IF q.statut <> 'EN_ATTENTE' THEN RETURN jsonb_build_object('statut', 'ATTENDRE'); END IF;
  IF l.prochaine_tentative_le > now() THEN RETURN jsonb_build_object('statut', 'ATTENDRE'); END IF;
  IF l.famille = 'COMMISSION' THEN
    SELECT to_jsonb(f) INTO document FROM public.factures f WHERE id = l.document_id;
  ELSE
    SELECT to_jsonb(f) INTO document FROM public.factures_honoraires f WHERE id = l.document_id;
  END IF;
  -- Ancien corps immuable : admis uniquement sans aucune allocation. Ne jamais
  -- enrichir une livraison existante ni modifier sa clé d'idempotence.
  IF l.famille='COMMISSION' AND (
    (NOT (l.corps->'data' ? 'montant_a_payer') AND (
      (document->>'montant_avoirs_imputes')::numeric IS DISTINCT FROM 0::numeric
      OR EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements j WHERE j.facture_id=l.document_id)))
    OR ((l.corps->'data' ? 'montant_a_payer') AND (
      round((document->>'montant_a_payer')::numeric,2)::text IS DISTINCT FROM l.corps#>>'{data,montant_a_payer}'
      OR round((document->>'montant_avoirs_imputes')::numeric,2)::text IS DISTINCT FROM l.corps#>>'{data,montant_avoirs_imputes}'
      OR document->>'mode_paiement' IS DISTINCT FROM l.corps#>>'{data,mode_paiement}'))
    OR (document->>'rapprochement_paiement_requis')::boolean IS TRUE
  ) THEN
    UPDATE public.email_queue SET statut='ANNULE',erreur='Montant externe à rapprocher' WHERE id=p_email_id;
    RETURN jsonb_build_object('statut','ANNULE');
  END IF;
  -- Une confirmation n'est pas une deuxième émission. Ses preuves figées
  -- doivent encore désigner le même paiement Checkout, sans réécrire le reçu.
  IF l.evenement = 'PAIEMENT' AND (
    l.famille IS DISTINCT FROM 'COMMISSION'
    OR l.corps->>'type' IS DISTINCT FROM 'FACTURE_PAYEE'
    OR document->>'statut' IS DISTINCT FROM 'PAYEE'
    OR document->>'type_document' IS DISTINCT FROM 'FACTURE'
    OR document->>'stripe_payment_intent_id' IS DISTINCT FROM l.corps#>>'{data,stripe_payment_intent_id}'
    OR to_char((document->>'date_paiement')::timestamptz AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY')
      IS DISTINCT FROM l.corps#>>'{data,date_paiement}'
    OR NOT EXISTS (
      SELECT 1 FROM public.stripe_payment_flow_claims c
      WHERE c.resource_key='FACTURE:'||l.document_id::text AND c.flow='CHECKOUT_INVOICE'
        AND c.owner_token='invoice:'||l.document_id::text
        AND c.stripe_checkout_session_id=l.corps#>>'{data,stripe_checkout_session_id}'
        AND (c.stripe_payment_intent_id IS NULL
          OR c.stripe_payment_intent_id=document->>'stripe_payment_intent_id')
    )
  ) THEN
    UPDATE public.email_queue SET statut='ANNULE', erreur='Confirmation de paiement devenue incohérente'
      WHERE id=p_email_id;
    RETURN jsonb_build_object('statut','ANNULE');
  END IF;
  IF document IS NULL OR document->>'statut' IS NULL OR document->>'statut' IN ('BROUILLON','EN_GENERATION','ERREUR_GENERATION','ANNULEE','REMPLACEE')
    OR q.type <> 'FACTURATION_DOCUMENT' OR q.destinataire_id IS DISTINCT FROM l.destinataire_id OR q.data IS DISTINCT FROM l.corps
    OR document->>'numero_facture' IS DISTINCT FROM l.corps#>>'{data,numero}'
    OR round((document->>'montant_ht')::numeric, 2)::text IS DISTINCT FROM l.corps#>>'{data,montant_ht}'
    OR round((document->>'montant_tva')::numeric, 2)::text IS DISTINCT FROM l.corps#>>'{data,montant_tva}'
    OR round((document->>'montant_ttc')::numeric, 2)::text IS DISTINCT FROM l.corps#>>'{data,montant_ttc}'
    OR to_char((document->>'date_echeance')::date, 'DD/MM/YYYY') IS DISTINCT FROM l.corps#>>'{data,date_echeance}'
    OR NOT (l.destinataire_id::text = document->>'etablissement_id'
      OR (l.famille = 'HONORAIRES' AND l.destinataire_id::text = document->>'soignant_id'))
    OR NOT EXISTS (SELECT 1 FROM public.etablissements e WHERE e.id = (document->>'etablissement_id')::uuid AND e.supprime_le IS NULL)
    OR (l.famille = 'HONORAIRES' AND NOT EXISTS (SELECT 1 FROM public.soignants s WHERE s.id = (document->>'soignant_id')::uuid AND s.supprime_le IS NULL))
  THEN
    UPDATE public.email_queue SET statut = 'ANNULE', erreur = 'Document ou destinataire devenu indisponible' WHERE id = p_email_id;
    RETURN jsonb_build_object('statut', 'ANNULE');
  END IF;
  -- Une copie envoyée pendant le déploiement précédent vaut acquittement.
  IF EXISTS (SELECT 1 FROM private.email_dispatch_idempotency d WHERE d.idempotency_key = l.idempotency_key AND d.statut = 'ENVOYE') THEN
    UPDATE public.email_queue SET statut = 'ENVOYE', envoye = true, envoye_le = now(), erreur = NULL WHERE id = p_email_id;
    RETURN jsonb_build_object('statut', 'DEJA_ENVOYE');
  END IF;
  -- Ne pas rejouer un résultat indéterminé après expiration de la fenêtre
  -- d'idempotence fournisseur. L'erreur reste visible pour rapprochement manuel.
  IF l.tentatives >= 5 OR l.premiere_tentative_le < now() - interval '20 hours' THEN
    UPDATE public.email_queue SET statut = 'ERREUR', erreur = 'Envoi facture à vérifier : limite de reprise atteinte' WHERE id = p_email_id;
    RETURN jsonb_build_object('statut', 'ERREUR');
  END IF;
  jeton := gen_random_uuid();
  UPDATE private.facturation_email_livraisons SET tentatives = tentatives + 1,
    premiere_tentative_le = coalesce(premiere_tentative_le, now()),
    prochaine_tentative_le = now() + interval '15 minutes', reservation = jeton WHERE email_id = p_email_id;
  RETURN jsonb_build_object('statut', 'RESERVE', 'reservation', jeton, 'corps', l.corps, 'idempotency_key', l.idempotency_key);
END $function$

;
CREATE OR REPLACE FUNCTION public.fn_reverifier_blocage_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id uuid := mon_etablissement_id();
    v_paiements_retard_nb int;
    v_factures_retard_nb int;
    v_seuil_j integer := (public.fn_param_num('seuil_blocage_retard_j', 45))::integer;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM etablissements WHERE id = v_etab_id AND bloque_auto_le IS NOT NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE, 'message', 'Votre compte n''est pas bloqué.');
    END IF;

    -- Même seuil paramétré et même échéance que fn_gerer_blocage_etabs
    SELECT COUNT(*) INTO v_paiements_retard_nb
    FROM missions m
    WHERE m.etablissement_id = v_etab_id
      AND m.type_contrat_applique = 'SALARIE'
      AND m.statut = 'TERMINEE'
      AND m.fin_le < NOW() - make_interval(days => v_seuil_j)
      AND NOT EXISTS (
          SELECT 1 FROM paiements_soignant ps
          WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME'));

    SELECT COUNT(*) INTO v_factures_retard_nb
    FROM factures f
    WHERE f.etablissement_id = v_etab_id
      AND f.statut IN ('EMISE', 'EN_RETARD')
      AND f.type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND f.montant_a_payer > 0 AND NOT f.rapprochement_paiement_requis
      AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30)
          < (NOW() AT TIME ZONE 'Europe/Paris')::date - v_seuil_j;

    IF v_paiements_retard_nb = 0 AND v_factures_retard_nb = 0 THEN
        UPDATE etablissements SET bloque_auto_le = NULL, bloque_auto_raisons = NULL WHERE id = v_etab_id;
        INSERT INTO historique_blocages_etablissements (etablissement_id, action)
        VALUES (v_etab_id, 'DEBLOCAGE');
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_etab_id, 'SYSTEM', 'Publication de missions reactivee',
            'Vos obligations sont régularisées : votre compte est à nouveau autorisé à publier des missions.',
            '/etablissement/tableau-de-bord', 'ETABLISSEMENT');
        RETURN jsonb_build_object('success', TRUE, 'debloque', TRUE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE,
        'paiements_retard_nb', v_paiements_retard_nb,
        'factures_retard_nb', v_factures_retard_nb,
        'message', 'Des obligations restent en retard — régularisez-les puis réessayez.');
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_stats_dashboard_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_stats JSONB;
    v_pool_urgence_count INT;
    v_messages_non_lus INT;
    v_missions_a_payer INT;
    v_debut_mois TIMESTAMPTZ;
    v_terminees_ce_mois INT;
    v_soignants_ce_mois INT;
    v_commissions_impayees NUMERIC;
    v_nb_factures_impayees INT;
    v_litiges_ouverts INT;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    
    v_debut_mois := DATE_TRUNC('month', NOW());
    
    SELECT COUNT(*) INTO v_pool_urgence_count FROM fn_pool_urgence_etablissement(v_etab_id);
    
    SELECT COUNT(*) INTO v_messages_non_lus
    FROM messages_chat mc JOIN conversations c ON c.id = mc.conversation_id
    WHERE (c.participant_1_id = v_etab_id OR c.participant_2_id = v_etab_id)
    AND mc.auteur_id != v_etab_id AND mc.lu = FALSE;
    
    SELECT COUNT(*) INTO v_missions_a_payer
    FROM missions m WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME'));
    
    SELECT COUNT(*) INTO v_terminees_ce_mois
    FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois;
    
    SELECT COUNT(DISTINCT soignant_assigne_id) INTO v_soignants_ce_mois
    FROM missions WHERE etablissement_id = v_etab_id AND soignant_assigne_id IS NOT NULL
    AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE') AND debut_le >= v_debut_mois;
    
    SELECT COALESCE(SUM(montant_a_payer), 0), COUNT(*)
    INTO v_commissions_impayees, v_nb_factures_impayees
    FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
      AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis;
    
    -- Litiges ouverts
    SELECT COUNT(*) INTO v_litiges_ouverts
    FROM litiges WHERE etablissement_id = v_etab_id 
    AND statut IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE');
    
    SELECT jsonb_build_object(
        'a_deja_publie', (SELECT COUNT(*) > 0 FROM missions WHERE etablissement_id = v_etab_id),
        'total_missions', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id),
        'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'OUVERTE'),
        'missions_assignees', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'),
        'missions_en_cours', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'EN_COURS'),
        'missions_terminees', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'),
        'missions_terminees_ce_mois', v_terminees_ce_mois,
        'soignants_ce_mois', v_soignants_ce_mois,
        'commissions_cumulees', COALESCE((SELECT SUM(montant_ht) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0),
        'commissions_impayees', v_commissions_impayees,
        'nb_factures_impayees', v_nb_factures_impayees,
        'pool_urgence_count', v_pool_urgence_count,
        'messages_non_lus', v_messages_non_lus,
        'missions_a_payer', v_missions_a_payer,
        'litiges_ouverts', v_litiges_ouverts,
        'candidatures_en_attente', (
            SELECT COUNT(*) FROM candidatures c JOIN missions m ON m.id = c.mission_id
            WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
        ),
        'candidatures_recentes', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT c.id::TEXT AS candidature_id, m.intitule AS mission_intitule,
                    m.id::TEXT AS mission_id,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession,
                    s.score_fiabilite AS soignant_score, c.cree_le
                FROM candidatures c JOIN missions m ON m.id = c.mission_id JOIN soignants s ON s.id = c.soignant_id
                WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
                ORDER BY c.cree_le DESC LIMIT 5
            ) x
        ), '[]'::JSONB),
        'missions_assignees_detail', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession, s.score_fiabilite AS soignant_score
                FROM missions m JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'ASSIGNEE'
                ORDER BY m.debut_le ASC
            ) x
        ), '[]'::JSONB)
    ) INTO v_stats;
    
    RETURN v_stats;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions_actives int;
  v_factures_impayees int;
  v_hash text;
  v_interne text := COALESCE(current_setting('app.internal_operation',true),'');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT id INTO v_etab_id FROM etablissements WHERE id = v_uid FOR UPDATE;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun établissement lié à ce compte');
  END IF;

  IF private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success',true,'deja_anonymise',true);
  END IF;

  -- Garde-fou : missions actives
  SELECT count(*) INTO v_missions_actives FROM missions
   WHERE etablissement_id = v_etab_id
     AND statut IN ('OUVERTE','ASSIGNEE','EN_COURS','LITIGE')
     AND fin_le > NOW();
  IF v_missions_actives > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('Vous avez %s mission(s) ouverte(s) ou en cours.', v_missions_actives));
  END IF;

  -- Garde-fou : factures impayées (la suppression n'efface pas une dette)
  SELECT count(*) INTO v_factures_impayees FROM factures
   WHERE etablissement_id = v_etab_id AND statut IN ('EN_ATTENTE','EN_RETARD')
     AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis;
  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('%s facture(s) impayée(s). Réglez-les avant suppression.', v_factures_impayees));
  END IF;

  -- Bypass trigger fn_protect_etablissement_commercial pour anonymisation
  PERFORM set_config('app.internal_operation', 'true', true);
  v_hash := encode(extensions.digest(v_etab_id::text || NOW()::text, 'sha256'), 'hex');

  BEGIN
  INSERT INTO private.suppression_etablissement_context(backend_pid,transaction_id,utilisateur_id)
  VALUES(pg_backend_pid(),txid_current(),v_uid);
  -- Anonymisation établissement
  UPDATE etablissements SET
    nom = 'Établissement supprimé',
    siret = '99' || LPAD(LEFT(REGEXP_REPLACE(v_hash, '[^0-9]', '', 'g'), 12), 12, '0'),
    finess = NULL,
    email_contact = v_hash || '@supprime.jolene.app',
    telephone_contact = NULL,
    adresse_rue = '[SUPPRIMÉ]',
    adresse_ville = '[SUPPRIMÉ]',
    adresse_code_postal = '00000',
    adresse_departement = NULL, adresse_lat = NULL, adresse_lng = NULL,
    description = NULL, logo_url = NULL, horaires_ouverture = NULL,
    contrat_url = NULL,
    siret_raison_sociale = NULL, siret_categorie_juridique = NULL,
    siret_code_naf = NULL, siret_est_actif = false,
    chorus_pro_actif = false, chorus_pro_identifiant = NULL,
    sms_actif = false, sms_consent_le = NULL,
    peut_publier_missions = false,
    bloque_auto_le = NOW(),
    bloque_auto_raisons = jsonb_build_array('COMPTE_SUPPRIME_RGPD'),
    supprime_le = NOW(),
    stripe_sepa_payment_method_id = NULL
  WHERE id = v_etab_id;

  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.internal_operation',v_interne,true);
    RAISE;
  END;
  DELETE FROM private.suppression_etablissement_context
  WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current() AND utilisateur_id=v_uid;
  PERFORM set_config('app.internal_operation',v_interne,true);

  -- Tables liées
  DELETE FROM admins_groupe_sante WHERE utilisateur_id = v_uid;
  DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
  DELETE FROM notifications WHERE destinataire_id = v_uid;

  UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

  UPDATE evaluations SET commentaire = NULL
   WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

  DELETE FROM exclusions WHERE exclu_par = v_uid OR exclu_id = v_uid;

  UPDATE partages_rib SET actif = false, expire_le = NOW()
   WHERE etablissement_id = v_etab_id;

  -- Contrats : on conserve (preuves légales) mais anonymise IP/UA
  UPDATE contrats_mission SET
    signature_ip_etablissement = NULL,
    signature_navigateur_etablissement = NULL,
    signature_image_etablissement = NULL
   WHERE etablissement_id = v_etab_id;

  DELETE FROM email_queue WHERE destinataire_id = v_uid;
  UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL
   WHERE destinataire_id = v_uid;

  DELETE FROM calendar_events_sync WHERE connection_id IN
    (SELECT id FROM calendar_connections WHERE utilisateur_id = v_uid);
  DELETE FROM calendar_connections WHERE utilisateur_id = v_uid;
  DELETE FROM api_keys WHERE etablissement_id = v_etab_id;

  -- Audit (type_acteur ADMIN_ETABLISSEMENT, action RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT)
  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (v_uid, 'ADMIN_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT', 'etablissement', v_etab_id,
    jsonb_build_object('anonymise', true));

  INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
  SELECT id,'ETABLISSEMENT',supprime_le,email_contact FROM public.etablissements WHERE id=v_etab_id
  ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
  IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN RAISE EXCEPTION 'Anonymisation établissement non confirmée'; END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Établissement anonymisé. Factures conservées 10 ans (LPF L102 B).',
    'etablissement_id', v_etab_id
  );
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_commission_encaissee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mission RECORD; v_parrainage RECORD; v_commission NUMERIC;
BEGIN
  IF NEW.statut <> 'PAYEE' OR NEW.mode_paiement='AVOIR' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.mission_id IS NULL THEN RETURN NEW; END IF;
  SELECT id, soignant_assigne_id INTO v_mission FROM missions WHERE id = NEW.mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = v_mission.soignant_assigne_id AND statut IN ('FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL') LIMIT 1;
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;
  v_commission := COALESCE(NEW.montant_ht, 0);
  IF v_commission <= 0 THEN RETURN NEW; END IF;
  UPDATE parrainages SET commission_cumulee_filleul = COALESCE(commission_cumulee_filleul, 0) + v_commission WHERE id = v_parrainage.id;
  PERFORM public.fn_parrainage_verifier_seuils(v_parrainage.id);
  RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_parrainage RECORD;
  v_gmv_cents NUMERIC;
  v_p1_gmv INTEGER := public.fn_param_num('parrainage_etab_palier1_gmv_cents', 50000)::int;
  v_p1_eur INTEGER := public.fn_param_num('parrainage_etab_palier1_recompense_eur', 50)::int;
  v_p2_gmv INTEGER := public.fn_param_num('parrainage_etab_palier2_gmv_cents', 200000)::int;
  v_p2_eur INTEGER := public.fn_param_num('parrainage_etab_palier2_recompense_eur', 150)::int;
  v_nb_validations_mois INT;
BEGIN
  IF NEW.statut <> 'PAYEE' OR NEW.mode_paiement='AVOIR' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.etablissement_id IS NULL THEN RETURN NEW; END IF;

  -- Parrainage du filleul encore éligible à un palier (palier 2 non atteint).
  SELECT * INTO v_parrainage FROM parrainages_etablissements
  WHERE filleul_etab_id = NEW.etablissement_id
    AND statut IN ('PENDING', 'VALIDATED')
    AND palier2_atteint_le IS NULL
  LIMIT 1;
  IF v_parrainage.id IS NULL THEN RETURN NEW; END IF;

  -- GMV encaissé du filleul = SUM total_brut des missions dont la facture
  -- commission est PAYEE (× 100 pour comparer aux seuils en centimes).
  SELECT COALESCE(SUM(m.total_brut), 0) * 100 INTO v_gmv_cents
  FROM missions m
  JOIN factures f ON f.id = m.facture_id
  WHERE m.etablissement_id = NEW.etablissement_id
    AND f.statut = 'PAYEE' AND f.mode_paiement IS DISTINCT FROM 'AVOIR';

  -- Palier 1 : valide le parrainage + crédite (une seule fois).
  IF v_gmv_cents >= v_p1_gmv AND v_parrainage.palier1_atteint_le IS NULL THEN
    UPDATE parrainages_etablissements
    SET statut = 'VALIDATED', valide_le = COALESCE(valide_le, NOW()),
        palier1_atteint_le = NOW(), mis_a_jour_le = NOW()
    WHERE id = v_parrainage.id;

    PERFORM public.fn_parrainage_etab_crediter_palier(v_parrainage.id, v_p1_eur, 1, v_gmv_cents);

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_parrainage.filleul_etab_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_ETAB_VALIDE', p_type_ressource := 'parrainage_etab',
      p_id_ressource := v_parrainage.id,
      p_details := jsonb_build_object('parrain_etab_id', v_parrainage.parrain_etab_id,
                                      'facture_id', NEW.id, 'palier', 1, 'gmv_cents', v_gmv_cents)
    );

    -- Anti-abus : > 5 validations dans le mois pour un même parrain.
    SELECT COUNT(*) INTO v_nb_validations_mois FROM parrainages_etablissements
    WHERE parrain_etab_id = v_parrainage.parrain_etab_id
      AND statut = 'VALIDATED' AND valide_le >= DATE_TRUNC('month', NOW());
    IF v_nb_validations_mois > 5 THEN
      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
        p_action := 'PARRAINAGE_ETAB_ANOMALIE', p_type_ressource := 'etablissement',
        p_id_ressource := v_parrainage.parrain_etab_id,
        p_details := jsonb_build_object('nb_validations_mois', v_nb_validations_mois)
      );
    END IF;
  END IF;

  -- Palier 2 : crédit additionnel (une seule fois). Peut tomber sur la même
  -- facture que le palier 1 si le GMV franchit d'emblée les 2 seuils.
  IF v_gmv_cents >= v_p2_gmv AND v_parrainage.palier2_atteint_le IS NULL THEN
    UPDATE parrainages_etablissements
    SET palier2_atteint_le = NOW(), mis_a_jour_le = NOW()
    WHERE id = v_parrainage.id;

    PERFORM public.fn_parrainage_etab_crediter_palier(v_parrainage.id, v_p2_eur, 2, v_gmv_cents);
  END IF;

  RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION private.fn_admission_virement_commission(p_facture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  f public.factures%ROWTYPE;
  h public.factures_honoraires%ROWTYPE;
  e public.etablissements%ROWTYPE;
  motif text;
BEGIN
  SELECT * INTO f FROM public.factures WHERE id=p_facture_id;
  SELECT * INTO e FROM public.etablissements WHERE id=f.etablissement_id;
  IF f.id IS NULL OR e.id IS NULL THEN motif:='FACTURE_INDISPONIBLE';
  ELSIF f.rapprochement_paiement_requis THEN motif:='RAPPROCHEMENT_PAIEMENT_REQUIS';
  ELSIF f.montant_a_payer<=0 THEN motif:='FACTURE_SOLDEE';
  ELSIF f.type_document NOT IN ('FACTURE','FACTURE_COMPLEMENTAIRE')
    OR f.statut IS NULL OR f.statut NOT IN ('EMISE','EN_RETARD') THEN motif:='FACTURE_NON_PAYABLE';
  ELSIF f.est_secteur_public IS TRUE OR e.est_secteur_public IS TRUE
    OR e.chorus_pro_actif IS TRUE THEN motif:='FACTURE_PUBLIQUE_CHORUS';
  ELSIF e.mode_paiement_commission='SEPA_DEBIT'
    AND NOT (f.montant_avoirs_imputes>0 AND f.montant_a_payer>0 AND f.montant_a_payer<0.50)
    THEN motif:='PAIEMENT_SEPA_AUTOMATIQUE';
  ELSIF f.stripe_payment_intent_id IS NOT NULL OR f.stripe_hosted_url IS NOT NULL
    OR f.stripe_invoice_id IS NOT NULL THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.stripe_payment_flow_claims c
    WHERE c.resource_key='FACTURE:'||f.id::text
      OR ((c.resource_key='MISSION:'||f.mission_id::text
        OR EXISTS (SELECT 1 FROM public.missions m WHERE m.facture_id=f.id
          AND c.resource_key='MISSION:'||m.id::text))
        AND NOT EXISTS (
          -- Seul le claim carte de l'initiale canonique déjà réglée est distinct
          -- de ce complément salarial. Tout claim de la pièce exacte, autre
          -- flux, propriétaire, session ou contexte reste bloquant.
          SELECT 1 FROM public.missions m
          JOIN public.factures initiale ON initiale.id=f.facture_precedente_id
            AND m.facture_id=initiale.id
          JOIN public.stripe_payment_flow_claims initial_claim
            ON initial_claim.resource_key='FACTURE:'||initiale.id::text
          WHERE f.type_document='FACTURE_COMPLEMENTAIRE' AND f.facture_honoraire_id IS NULL
            AND m.id=f.mission_id AND m.type_contrat_applique='SALARIE'
            AND m.etablissement_id=f.etablissement_id
            AND initiale.etablissement_id=f.etablissement_id AND initiale.type_document='FACTURE'
            AND initiale.facture_honoraire_id IS NULL AND initiale.statut='PAYEE'
            AND (initiale.mission_id IS NULL OR initiale.mission_id=m.id)
            AND nullif(initiale.stripe_payment_intent_id,'') IS NOT NULL
            AND c.resource_key='MISSION:'||m.id::text AND c.flow='CHECKOUT_INVOICE'
            AND c.owner_token='invoice:'||initiale.id::text
            AND initial_claim.flow=c.flow AND initial_claim.owner_token=c.owner_token
            AND nullif(c.stripe_checkout_session_id,'') IS NOT NULL
            AND initial_claim.stripe_checkout_session_id=c.stripe_checkout_session_id
            AND initial_claim.stripe_payment_intent_id IS NOT DISTINCT FROM c.stripe_payment_intent_id
            AND (c.stripe_payment_intent_id IS NULL OR c.stripe_payment_intent_id=initiale.stripe_payment_intent_id)
        ))) THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.stripe_transfers st
    WHERE st.facture_id=f.id OR (st.mission_id=f.mission_id
      AND (st.facture_honoraire_id=f.facture_honoraire_id OR st.facture_honoraire_id IS NULL))
      -- Repli historique seulement : une trace liée à une autre FH de la même
      -- mission ne représente pas la commission de cette période explicite.
      OR (st.facture_honoraire_id IS NULL AND EXISTS (SELECT 1 FROM public.missions m
        WHERE m.facture_id=f.id AND st.mission_id=m.id)))
    THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.factures a WHERE a.facture_precedente_id=f.id
    AND a.type_document='AVOIR' AND a.statut<>'ANNULEE'
    AND NOT EXISTS(SELECT 1 FROM private.avoirs_commission_sources src WHERE src.avoir_id=a.id)) THEN motif:='AVOIR_A_RAPPROCHER';
  END IF;

  IF motif IS NULL AND f.facture_honoraire_id IS NOT NULL THEN
    SELECT * INTO h FROM public.factures_honoraires WHERE id=f.facture_honoraire_id;
    IF h.id IS NULL OR h.type_document<>'FACTURE'
      OR ROW(h.mission_id,h.etablissement_id) IS DISTINCT FROM ROW(f.mission_id,f.etablissement_id)
      OR h.statut NOT IN ('EMISE','EN_RETARD','PAYEE') THEN motif:='HONORAIRES_INDISPONIBLES';
    ELSIF h.stripe_payment_intent_id IS NOT NULL THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
    ELSIF EXISTS (SELECT 1 FROM public.factures_honoraires a
      WHERE a.facture_precedente_id=h.id AND a.type_document='AVOIR'
        AND a.statut NOT IN ('ANNULEE','ERREUR_GENERATION','REMPLACEE')) THEN motif:='AVOIR_A_RAPPROCHER';
    ELSIF (SELECT count(*) FROM public.paiements_soignant p
      WHERE p.facture_honoraire_id=h.id OR (p.mission_id=h.mission_id AND p.facture_honoraire_id IS NULL))<>1
      OR NOT EXISTS (SELECT 1 FROM public.paiements_soignant p
        WHERE p.facture_honoraire_id=h.id AND p.mission_id=h.mission_id
          AND p.etablissement_id=h.etablissement_id AND p.soignant_id=h.soignant_id
          AND p.stripe_transfer_id IS NULL AND p.statut IN ('DECLARE','CONFIRME')
          AND p.methode IN ('VIREMENT','CHEQUE','NOTE_HONORAIRES')
          AND p.montant_net=h.montant_ttc) THEN motif:='HONORAIRES_DIRECTS_REQUIS';
    END IF;
  ELSIF motif IS NULL AND f.mission_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.missions m WHERE m.id=f.mission_id
      AND m.etablissement_id=f.etablissement_id AND m.type_contrat_applique='SALARIE'
  ) THEN
    -- Une ancienne commission libérale sans pièce explicite reste à rapprocher.
    motif:='HONORAIRES_INDISPONIBLES';
  END IF;
  RETURN jsonb_build_object('facture_id',p_facture_id,
    'virement_autorise',motif IS NULL,'motif',motif);
END;
$function$

;
CREATE OR REPLACE FUNCTION private.mettre_emission_facture_en_file()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_famille text := CASE TG_TABLE_NAME WHEN 'factures' THEN 'COMMISSION' ELSE 'HONORAIRES' END;
  v_destinataire uuid;
  v_role_destinataire text;
  v_payload jsonb;
  v_corps jsonb;
  v_email_id uuid;
  v_cle text;
  v_source_mission uuid;
  v_source_soignant uuid;
BEGIN
  IF NEW.statut IS DISTINCT FROM 'EMISE' AND NOT (v_famille='COMMISSION'
    AND NEW.statut IS NOT DISTINCT FROM 'PAYEE' AND (to_jsonb(NEW)->>'mode_paiement') IS NOT DISTINCT FROM 'AVOIR') THEN RETURN NEW; END IF;
  -- Les avoirs commission ont déjà leur notification COMMISSION_AJUSTEE.
  IF v_famille = 'COMMISSION' AND NEW.type_document::text = 'AVOIR' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.statut NOT IN ('BROUILLON', 'EN_GENERATION', 'ERREUR_GENERATION') THEN RETURN NEW; END IF;
  END IF;
  -- Le trigger honoraires ne s'exécute que pour un document réellement émis,
  -- avec ses deux fichiers disponibles, pas lors de la réservation du numéro.
  IF v_famille = 'HONORAIRES' AND (
    nullif(to_jsonb(NEW)->>'pdf_s3_key', '') IS NULL
    OR nullif(to_jsonb(NEW)->>'facturx_xml_url', '') IS NULL
    OR nullif(to_jsonb(NEW)->>'emise_le', '') IS NULL
  ) THEN RETURN NEW; END IF;

  -- Sources métier canoniques, jamais déduites du seul destinataire. La garde
  -- du transport doit aussi reconnaître un soignant TEST adressant un E réel.
  v_source_mission := nullif(to_jsonb(NEW)->>'mission_id', '')::uuid;
  v_source_soignant := nullif(to_jsonb(NEW)->>'soignant_id', '')::uuid;
  IF v_famille = 'COMMISSION' THEN
    IF nullif(to_jsonb(NEW)->>'facture_honoraire_id', '') IS NOT NULL THEN
      SELECT h.soignant_id INTO v_source_soignant FROM public.factures_honoraires h
      WHERE h.id=(to_jsonb(NEW)->>'facture_honoraire_id')::uuid
        AND h.mission_id IS NOT DISTINCT FROM v_source_mission AND h.etablissement_id=NEW.etablissement_id;
    ELSIF v_source_mission IS NOT NULL THEN
      SELECT m.soignant_assigne_id INTO v_source_soignant FROM public.missions m
      WHERE m.id=v_source_mission AND m.etablissement_id=NEW.etablissement_id;
    END IF;
  END IF;

  FOREACH v_destinataire IN ARRAY CASE WHEN v_famille = 'COMMISSION'
    THEN ARRAY[NEW.etablissement_id]
    ELSE ARRAY[(to_jsonb(NEW)->>'soignant_id')::uuid, NEW.etablissement_id] END
  LOOP
    v_role_destinataire := CASE WHEN v_destinataire = NEW.etablissement_id THEN 'ETABLISSEMENT' ELSE 'SOIGNANT' END;
    -- Le soignant reçoit déjà AVOIR_EMIS via le circuit des litiges. Seule
    -- la copie établissement remplace ici l'ancien envoi direct generate-invoice.
    IF NEW.type_document::text = 'AVOIR' AND v_role_destinataire = 'SOIGNANT' THEN CONTINUE; END IF;
    v_payload := jsonb_build_object(
      'numero', NEW.numero_facture, 'facture_id', NEW.id,
      'mission_id', v_source_mission, 'etablissement_id', NEW.etablissement_id, 'soignant_id', v_source_soignant,
      'famille_document', v_famille, 'destinataire_role', v_role_destinataire,
      'libelle_document', CASE WHEN NEW.type_document::text = 'AVOIR' THEN 'Avoir'
        WHEN v_famille = 'COMMISSION' THEN 'Facture de services Jolene' ELSE 'Facture d''honoraires' END,
      'montant_ht', round(NEW.montant_ht, 2)::text,
      'montant_tva', round(NEW.montant_tva, 2)::text,
      'montant_ttc', round(NEW.montant_ttc, 2)::text,
      'date_echeance', to_char(NEW.date_echeance, 'DD/MM/YYYY'),
      'periode', coalesce(to_char(NEW.periode_debut, 'DD/MM/YYYY'), '—')
        || ' → ' || coalesce(to_char(NEW.periode_fin, 'DD/MM/YYYY'), '—')
    );
    IF v_famille='COMMISSION' THEN
      v_payload:=v_payload || jsonb_build_object('montant_avoirs_imputes',round(NEW.montant_avoirs_imputes,2)::text,
        'montant_a_payer',round(NEW.montant_a_payer,2)::text,'mode_paiement',NEW.mode_paiement,
        'rapprochement_paiement_requis',NEW.rapprochement_paiement_requis);
    END IF;
    IF v_famille = 'HONORAIRES' THEN
      v_payload := v_payload || jsonb_build_object('verification_echeance',
        to_char((to_jsonb(NEW)->>'verification_echeance_le')::timestamptz AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY à HH24:MI'));
    END IF;
    -- Reprendre les clés du précédent envoi direct honoraires : un déploiement
    -- progressif ne doit pas produire une deuxième copie du même document.
    v_cle := CASE WHEN v_famille = 'HONORAIRES'
      THEN 'facture-emise-' || lower(v_role_destinataire) || ':' || NEW.id::text
      ELSE 'facture-emise-commission:' || NEW.id::text || ':' || v_destinataire::text END;
    v_corps := jsonb_build_object('type', 'FACTURE_EMISE', 'destinataire_id', v_destinataire, 'data', v_payload);
    INSERT INTO private.facturation_email_livraisons(famille, document_id, destinataire_id, corps, idempotency_key)
    VALUES (v_famille, NEW.id, v_destinataire, v_corps, v_cle)
    ON CONFLICT (famille, document_id, destinataire_id, evenement) DO NOTHING
    RETURNING facturation_email_livraisons.email_id INTO v_email_id;
    IF v_email_id IS NOT NULL THEN
      INSERT INTO public.email_queue(id, type, destinataire_id, data, statut)
      VALUES (v_email_id, 'FACTURATION_DOCUMENT', v_destinataire, v_corps, 'EN_ATTENTE');
    END IF;
  END LOOP;
  RETURN NEW;
END $function$

;
CREATE OR REPLACE FUNCTION private.mettre_paiement_facture_en_file()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_headers jsonb;
  v_claim public.stripe_payment_flow_claims%ROWTYPE;
  v_payload jsonb;
  v_corps jsonb;
  v_email_id uuid;
  v_cle text;
BEGIN
  -- Ce marqueur ne donne aucun droit de payer : le rôle serveur, les RLS,
  -- les gardes financières et le claim canonique restent obligatoires.
  -- Ancien client/absence/JSON invalide : conserver le comportement ancien,
  -- sans exception qui pourrait interrompre sa transaction de paiement.
  BEGIN
    v_headers := nullif(current_setting('request.headers',true),'')::jsonb;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN NEW;
  END;
  IF auth.role() IS DISTINCT FROM 'service_role'
    OR v_headers->>'x-jolene-paid-invoice-email' IS DISTINCT FROM 'durable-v1'
    OR OLD.statut IS NULL OR OLD.statut NOT IN ('EMISE','EN_RETARD')
    OR NEW.statut IS DISTINCT FROM 'PAYEE'
    OR NEW.type_document IS DISTINCT FROM 'FACTURE'
    OR NEW.date_paiement IS NULL
    OR NEW.stripe_payment_intent_id IS NULL
    OR NEW.stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
  THEN RETURN NEW; END IF;

  SELECT * INTO v_claim FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key='FACTURE:'||NEW.id::text;
  IF NOT FOUND OR v_claim.flow IS DISTINCT FROM 'CHECKOUT_INVOICE'
    OR v_claim.owner_token IS DISTINCT FROM 'invoice:'||NEW.id::text
    OR v_claim.stripe_checkout_session_id IS NULL
    OR v_claim.stripe_checkout_session_id !~ '^cs_(test_|live_)?[A-Za-z0-9]+$'
    -- Les claims créés avant Checkout peuvent légitimement garder le PI NULL.
    -- Un PI explicitement contraire n'est jamais adopté ou réécrit.
    OR (v_claim.stripe_payment_intent_id IS NOT NULL
      AND v_claim.stripe_payment_intent_id IS DISTINCT FROM NEW.stripe_payment_intent_id)
  THEN RETURN NEW; END IF;

  v_payload := jsonb_build_object(
    'numero',NEW.numero_facture,'facture_id',NEW.id,
    'famille_document','COMMISSION','destinataire_role','ETABLISSEMENT',
    'mission_id',NEW.mission_id,'etablissement_id',NEW.etablissement_id,
    'montant_ht',round(NEW.montant_ht,2)::text,
    'montant_tva',round(NEW.montant_tva,2)::text,
    'montant_ttc',round(NEW.montant_ttc,2)::text,
    'montant_avoirs_imputes',round(NEW.montant_avoirs_imputes,2)::text,
    'montant_a_payer',round(NEW.montant_a_payer,2)::text,'mode_paiement',NEW.mode_paiement,
    'rapprochement_paiement_requis',NEW.rapprochement_paiement_requis,
    'date_echeance',to_char(NEW.date_echeance,'DD/MM/YYYY'),
    'date_paiement',to_char(NEW.date_paiement AT TIME ZONE 'Europe/Paris','DD/MM/YYYY'),
    'stripe_payment_intent_id',NEW.stripe_payment_intent_id,
    'stripe_checkout_session_id',v_claim.stripe_checkout_session_id
  );
  v_corps := jsonb_build_object('type','FACTURE_PAYEE','destinataire_id',NEW.etablissement_id,'data',v_payload);
  v_cle := 'facture-payee-commission:'||NEW.id::text||':'||NEW.etablissement_id::text;
  INSERT INTO private.facturation_email_livraisons(famille,document_id,destinataire_id,evenement,corps,idempotency_key)
  VALUES ('COMMISSION',NEW.id,NEW.etablissement_id,'PAIEMENT',v_corps,v_cle)
  ON CONFLICT (famille,document_id,destinataire_id,evenement) DO NOTHING
  RETURNING email_id INTO v_email_id;
  IF v_email_id IS NOT NULL THEN
    INSERT INTO public.email_queue(id,type,destinataire_id,data,statut)
    VALUES (v_email_id,'FACTURATION_DOCUMENT',NEW.etablissement_id,v_corps,'EN_ATTENTE');
  END IF;
  RETURN NEW;
END $function$
;
UPDATE private.security_definer_inventory i SET definition_md5=e.nouveau,recense_le=now()
FROM _avoirs_imputation_attendu e JOIN _avoirs_inventory_attendu a ON e.signature='public.'||a.signature
WHERE i.signature=a.signature AND i.categorie=a.categorie AND i.definition_md5=a.ancien;
DO $apres$
DECLARE e record; p record;
BEGIN
 FOR e IN SELECT * FROM _avoirs_imputation_attendu LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(e.signature);
  IF md5(p.prosrc) IS DISTINCT FROM e.nouveau OR pg_get_userbyid(p.proowner) IS DISTINCT FROM e.proprietaire
    OR p.proacl::text IS DISTINCT FROM e.acl OR p.proconfig IS DISTINCT FROM e.config THEN
    RAISE EXCEPTION 'AVOIRS_IMPUTATION_RESULTAT_DRIFT: %',e.signature; END IF;
  IF EXISTS(SELECT 1 FROM _avoirs_inventory_attendu a WHERE e.signature='public.'||a.signature
    AND NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i
      WHERE i.signature=a.signature AND i.categorie=a.categorie AND i.definition_md5=e.nouveau)) THEN
    RAISE EXCEPTION 'AVOIRS_IMPUTATION_INVENTORY_RESULTAT_DRIFT: %',e.signature; END IF;
 END LOOP;
END $apres$;
