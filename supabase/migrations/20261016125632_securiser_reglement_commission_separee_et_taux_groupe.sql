-- Le virement d'honoraires et la commission Jolene sont deux règlements.
-- Une admission UI ne réserve rien : la déclaration refait le contrôle sous
-- les mêmes advisory locks que les claims Stripe, puis mission -> FH -> FC.
BEGIN;

CREATE FUNCTION private.fn_admission_virement_commission(p_facture_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $admission$
DECLARE
  f public.factures%ROWTYPE;
  h public.factures_honoraires%ROWTYPE;
  e public.etablissements%ROWTYPE;
  motif text;
BEGIN
  SELECT * INTO f FROM public.factures WHERE id=p_facture_id;
  SELECT * INTO e FROM public.etablissements WHERE id=f.etablissement_id;
  IF f.id IS NULL OR e.id IS NULL THEN motif:='FACTURE_INDISPONIBLE';
  ELSIF f.type_document NOT IN ('FACTURE','FACTURE_COMPLEMENTAIRE')
    OR f.statut IS NULL OR f.statut NOT IN ('EMISE','EN_RETARD') THEN motif:='FACTURE_NON_PAYABLE';
  ELSIF f.est_secteur_public IS TRUE OR e.est_secteur_public IS TRUE
    OR e.chorus_pro_actif IS TRUE THEN motif:='FACTURE_PUBLIQUE_CHORUS';
  ELSIF e.mode_paiement_commission='SEPA_DEBIT' THEN motif:='PAIEMENT_SEPA_AUTOMATIQUE';
  ELSIF f.stripe_payment_intent_id IS NOT NULL OR f.stripe_hosted_url IS NOT NULL
    OR f.stripe_invoice_id IS NOT NULL THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.stripe_payment_flow_claims c
    WHERE c.resource_key='FACTURE:'||f.id::text
      OR c.resource_key='MISSION:'||f.mission_id::text
      OR EXISTS (SELECT 1 FROM public.missions m WHERE m.facture_id=f.id
        AND c.resource_key='MISSION:'||m.id::text)) THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.stripe_transfers st
    WHERE st.facture_id=f.id OR (st.mission_id=f.mission_id
      AND (st.facture_honoraire_id=f.facture_honoraire_id OR st.facture_honoraire_id IS NULL))
      OR EXISTS (SELECT 1 FROM public.missions m WHERE m.facture_id=f.id AND st.mission_id=m.id))
    THEN motif:='PAIEMENT_EN_LIGNE_ENGAGE';
  ELSIF EXISTS (SELECT 1 FROM public.factures a WHERE a.facture_precedente_id=f.id
    AND a.type_document='AVOIR' AND a.statut<>'ANNULEE') THEN motif:='AVOIR_A_RAPPROCHER';
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
$admission$;
ALTER FUNCTION private.fn_admission_virement_commission(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.fn_admission_virement_commission(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.fn_modalites_reglement_commission(p_facture_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, auth AS $modalites$
DECLARE f public.factures%ROWTYPE;
BEGIN
  SELECT * INTO f FROM public.factures WHERE id=p_facture_id;
  IF f.id IS NULL OR (NOT public.est_admin() AND COALESCE(auth.role(),'')<>'service_role'
    AND (f.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
      OR NOT (public.fn_a_permission_etablissement('lecture_paiement',f.etablissement_id) IS TRUE
        OR public.fn_a_permission_etablissement('paiement',f.etablissement_id) IS TRUE))) THEN
    RETURN jsonb_build_object('error','Facture indisponible ou accès refusé');
  END IF;
  RETURN private.fn_admission_virement_commission(f.id);
END;
$modalites$;
ALTER FUNCTION public.fn_modalites_reglement_commission(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_modalites_reglement_commission(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_modalites_reglement_commission(uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_declarer_virement(p_facture_id uuid,p_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, auth AS $virement$
DECLARE
  f public.factures%ROWTYPE;
  initiale public.factures%ROWTYPE;
  ressource text;
  admission jsonb;
BEGIN
  SELECT * INTO initiale FROM public.factures WHERE id=p_facture_id;
  IF initiale.id IS NULL THEN RETURN jsonb_build_object('error','Facture introuvable'); END IF;
  IF NOT public.est_admin() AND COALESCE(auth.role(),'')<>'service_role'
    AND (initiale.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
      OR public.fn_a_permission_etablissement('paiement',initiale.etablissement_id) IS NOT TRUE) THEN
    RETURN jsonb_build_object('error','Non autorisé');
  END IF;
  IF p_reference IS NULL OR length(btrim(p_reference))<3 THEN
    RETURN jsonb_build_object('error','Référence de virement requise.');
  END IF;
  FOR ressource IN SELECT DISTINCT r FROM (
    SELECT 'FACTURE:'||initiale.id::text r
    UNION ALL SELECT 'MISSION:'||initiale.mission_id::text WHERE initiale.mission_id IS NOT NULL
    UNION ALL SELECT 'MISSION:'||m.id::text FROM public.missions m WHERE m.facture_id=initiale.id
  ) ressources ORDER BY r LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(ressource,0));
  END LOOP;
  PERFORM 1 FROM public.missions m WHERE m.id=initiale.mission_id OR m.facture_id=initiale.id
    ORDER BY m.id FOR UPDATE;
  PERFORM 1 FROM public.factures_honoraires WHERE id=initiale.facture_honoraire_id FOR UPDATE;
  SELECT * INTO f FROM public.factures WHERE id=initiale.id FOR UPDATE;
  IF f.id IS NULL OR ROW(f.etablissement_id,f.mission_id,f.facture_honoraire_id)
    IS DISTINCT FROM ROW(initiale.etablissement_id,initiale.mission_id,initiale.facture_honoraire_id) THEN
    RETURN jsonb_build_object('error','Contexte facture modifié. Rechargez la facture.');
  END IF;
  admission:=private.fn_admission_virement_commission(f.id);
  IF (admission->>'virement_autorise')::boolean IS NOT TRUE THEN
    RETURN jsonb_build_object('error',admission->>'motif',
      'message','Ce virement ne peut pas être déclaré. Consultez les modalités de règlement actualisées.');
  END IF;
  UPDATE public.factures SET virement_reference=btrim(p_reference),mode_paiement='VIREMENT',
    statut='VIREMENT_DECLARE',modifie_le=now() WHERE id=f.id;
  RETURN jsonb_build_object('success',true);
END;
$virement$;
ALTER FUNCTION public.fn_declarer_virement(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_declarer_virement(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_virement(uuid,text) TO authenticated,service_role;

-- Le claim possède déjà ses advisory locks FACTURE/MISSION. Si le virement
-- gagne la course, aucun Checkout/SEPA ne peut ensuite revendiquer cette dette.
CREATE FUNCTION private.fn_garder_claim_commission_virement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $claim$
BEGIN
  IF NEW.flow IN ('CHECKOUT_INVOICE','SEPA_INVOICE') AND EXISTS (
    SELECT 1 FROM public.factures f WHERE f.statut='VIREMENT_DECLARE'
      AND (NEW.resource_key='FACTURE:'||f.id::text OR NEW.resource_key='MISSION:'||f.mission_id::text
        OR EXISTS (SELECT 1 FROM public.missions m WHERE m.facture_id=f.id
          AND NEW.resource_key='MISSION:'||m.id::text))
  ) THEN RAISE EXCEPTION 'COMMISSION_VIREMENT_DEJA_DECLARE' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END;
$claim$;
ALTER FUNCTION private.fn_garder_claim_commission_virement() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.fn_garder_claim_commission_virement() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_commission_virement_claim BEFORE INSERT ON public.stripe_payment_flow_claims
FOR EACH ROW EXECUTE FUNCTION private.fn_garder_claim_commission_virement();

-- Exposer le taux résolu sans modifier le taux négocié de l’établissement.
CREATE OR REPLACE FUNCTION "public"."fn_mon_etablissement_complet"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  SELECT row_to_json(e)::jsonb
  INTO v_result
  FROM (
    SELECT
      et.id, et.nom, et.siret, et.finess, et.type::text, et.groupe_sante_id,
      et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
      et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
      et.stripe_customer_id, et.stripe_account_id,
      et.taux_commission_negocie,
      COALESCE(et.taux_commission_negocie, gs.taux_commission_negocie, 15) AS taux_commission_effectif,
      et.mode_facturation, et.mode_paiement_commission,
      et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
      et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
      et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
      et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
      et.contrat_service_signe, et.contrat_service_signe_le,
      et.rib_s3_key, et.rib_ia_coherent, et.iban_last4, et.sms_actif,
      et.taux_majoration_nuit_pourcent, et.taux_majoration_dimanche_pourcent,
      et.taux_majoration_ferie_pourcent,
      et.est_secteur_public, et.peut_publier_missions, et.statut_verification,
      et.note_moyenne, et.nb_evaluations, et.description, et.horaires_ouverture,
      et.rist_plafond_actif, et.rist_taux_base_horaire,
      et.bloque_auto_le, et.bloque_auto_raisons,
      et.cree_le, et.modifie_le,
      CASE WHEN pc.id IS NOT NULL THEN jsonb_build_object(
        'id', pc.id,
        'nom', pc.nom,
        'taux_commission', pc.taux_commission,
        'missions_min', pc.missions_min
      ) ELSE NULL END AS paliers_commission,
      CASE WHEN gs.id IS NOT NULL THEN jsonb_build_object(
        'id', gs.id,
        'nom', gs.nom,
        'taux_commission_negocie', gs.taux_commission_negocie
      ) ELSE NULL END AS groupes_sante
    FROM public.etablissements et
    LEFT JOIN public.paliers_commission pc ON pc.id = et.palier_commission_id
    LEFT JOIN public.groupes_sante gs ON gs.id = et.groupe_sante_id
    WHERE et.id = v_etab_id
  ) e;

  RETURN COALESCE(v_result, jsonb_build_object('error', 'Etablissement introuvable'));
END;
$$;


ALTER FUNCTION "public"."fn_mon_etablissement_complet"() OWNER TO "postgres";

INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification) VALUES
  ('fn_declarer_virement(uuid,text)','MIXTE_TENANT_ADMIN','d9e957341a75790d1c368c850731d770','Commission séparée : permission paiement, verrous communs aux claims et refus de tout encaissement déjà engagé.'),
  ('fn_modalites_reglement_commission(uuid)','MIXTE_TENANT_ADMIN','91a904be229d21680ef42ade6a769163','Lecture des modalités de la facture exacte, établissement autorisé et aucune réservation ni débit.'),
  ('fn_mon_etablissement_complet()','RPC_UTILISATEUR_AUTH_INTERNE','adec3cf8c4d9bc8c317500222ed2675d','Profil établissement courant et taux effectif établissement/groupe/défaut, sans modification de montant figé.')
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification;

COMMIT;
