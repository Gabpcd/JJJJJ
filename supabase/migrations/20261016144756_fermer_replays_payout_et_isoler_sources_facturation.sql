-- Correctifs additifs après installation des cinq migrations du 16 octobre.
-- Aucun rejeu de migration, backfill, ouverture Connect ou appel fournisseur.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- PAYOUT : REVIEW reste fermé sur tout constat ultérieur.
CREATE OR REPLACE FUNCTION public.fn_connect_payout_constater(p_trace_id uuid,p_account_id text,p_payout jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.stripe_transfers; st text:=p_payout->>'status'; pid text:=p_payout->>'id'; expected_live boolean;
BEGIN
  PERFORM private.fn_connect_exiger_service();
  SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id FOR UPDATE;
  SELECT livemode INTO STRICT expected_live FROM private.stripe_connect_avant_transfert WHERE trace_id=s.id;
  IF s.standard_payout_state IS NULL OR p_account_id IS DISTINCT FROM s.standard_payout_account_id
     OR COALESCE(pid,'')!~'^po_[A-Za-z0-9_]+$' OR st IS NULL OR st NOT IN('pending','in_transit','paid','failed','canceled')
     OR (p_payout->>'amount')::bigint IS DISTINCT FROM round(s.montant_soignant*100)::bigint
     OR p_payout->>'currency' IS DISTINCT FROM 'eur' OR p_payout#>>'{metadata,type}' IS DISTINCT FROM 'CONNECT_STANDARD_PAYOUT'
     OR p_payout#>>'{metadata,trace_id}' IS DISTINCT FROM s.id::text
     OR p_payout#>>'{metadata,transfer_id}' IS DISTINCT FROM s.stripe_transfer_id
     OR p_payout#>>'{metadata,mission_id}' IS DISTINCT FROM s.mission_id::text
     OR p_payout#>>'{metadata,soignant_id}' IS DISTINCT FROM s.soignant_id::text THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_IDENTITY'; END IF;
  IF p_payout->'livemode' IS DISTINCT FROM to_jsonb(expected_live) OR p_payout->'automatic' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_MODE'; END IF;
  -- Une anomalie exige une résolution explicite. Aucun webhook rejoué ni GET
  -- ultérieur ne peut convertir REVIEW en FAILED/PAID et rouvrir une tentative.
  IF s.standard_payout_state='REVIEW' THEN RETURN jsonb_build_object('review',true); END IF;
  IF p_payout#>>'{metadata,attempt}' IS DISTINCT FROM s.standard_payout_attempt::text THEN
    -- Une ancienne tentative connue ne peut ni solder ni écraser la courante.
    IF COALESCE(p_payout#>>'{metadata,attempt}','')~'^[0-3]$'
      AND (p_payout#>>'{metadata,attempt}')::integer<s.standard_payout_attempt
      AND st IN('failed','canceled') THEN RETURN jsonb_build_object('ignored',true); END IF;
    UPDATE public.stripe_transfers SET standard_payout_state='REVIEW',standard_payout_error_code='OLD_PAYOUT_CONTRADICTORY'
      WHERE id=s.id;
    RETURN jsonb_build_object('review',true);
  END IF;
  IF s.stripe_payout_id IS NOT NULL AND s.stripe_payout_id<>pid THEN RAISE EXCEPTION 'CONNECT_PAYOUT_DUPLICATE'; END IF;
  -- Un GET pending/in_transit commencé avant un webhook terminal peut finir
  -- après lui. Il ne remet jamais en cause le constat terminal du même objet.
  IF s.standard_payout_state IN('PAID','FAILED') AND st IN('pending','in_transit') THEN
    RETURN jsonb_build_object('ignored',true);
  END IF;
  IF (s.standard_payout_state='PAID' AND st<>'paid') OR (s.standard_payout_state='FAILED' AND st NOT IN('failed','canceled')) THEN
    UPDATE public.stripe_transfers SET standard_payout_state='REVIEW',standard_payout_error_code='PAYOUT_STATUS_CONTRADICTORY',
      statut=CASE WHEN statut='PAYE' THEN 'TRANSFERE' ELSE statut END,
      erreur='Le virement bancaire nécessite une vérification.'
      WHERE id=s.id;
    RETURN jsonb_build_object('review',true);
  END IF;
  UPDATE public.stripe_transfers SET stripe_payout_id=pid,
    standard_payout_known_ids=CASE WHEN pid=ANY(standard_payout_known_ids) THEN standard_payout_known_ids
      ELSE array_append(standard_payout_known_ids,pid) END,
    standard_payout_state=CASE WHEN st='paid' THEN 'PAID' WHEN st IN('failed','canceled') THEN 'FAILED' ELSE 'SUBMITTED' END,
    statut=CASE WHEN st='paid' AND statut='TRANSFERE' THEN 'PAYE' ELSE statut END,
    paye_le=CASE WHEN st='paid' THEN COALESCE(paye_le,clock_timestamp()) ELSE paye_le END,
    standard_payout_next_read_at=clock_timestamp()+CASE WHEN st IN('failed','canceled') THEN interval '1 day' ELSE interval '30 minutes' END,
    standard_payout_error_code=CASE WHEN st IN('failed','canceled') THEN 'PAYOUT_TERMINAL_FAILURE' ELSE NULL END
    WHERE id=s.id;
  IF (st='paid' AND s.standard_payout_state<>'PAID')
     OR (st IN('failed','canceled') AND s.standard_payout_state<>'FAILED') THEN
    INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details,navigateur_acteur)
    VALUES(s.soignant_id,'SYSTEME',CASE WHEN st='paid' THEN 'FINANCE_PAYOUT_PAID'
      ELSE 'FINANCE_PAYOUT_FAILED' END,
      'mission',s.mission_id,jsonb_build_object('evenement','CONNECT_STANDARD_PAYOUT_STATUS',
        'trace_id',s.id,'stripe_payout_id',pid,'statut',st,'tentative',s.standard_payout_attempt),
      'fn_connect_payout_constater');
  END IF;
  RETURN jsonb_build_object('recorded',true,'state',st);
END;$$;

-- COMMISSION : préserver les périodes explicitement distinctes.
CREATE OR REPLACE FUNCTION private.fn_admission_virement_commission(p_facture_id uuid)
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
      -- Repli historique seulement : une trace liée à une autre FH de la même
      -- mission ne représente pas la commission de cette période explicite.
      OR (st.facture_honoraire_id IS NULL AND EXISTS (SELECT 1 FROM public.missions m
        WHERE m.facture_id=f.id AND st.mission_id=m.id)))
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

-- EMAIL : sources canoniques pour l'isolation opérationnelle TEST.
CREATE OR REPLACE FUNCTION private.mettre_emission_facture_en_file()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
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
  IF NEW.statut IS DISTINCT FROM 'EMISE' THEN RETURN NEW; END IF;
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
    ON CONFLICT (famille, document_id, destinataire_id) DO NOTHING
    RETURNING facturation_email_livraisons.email_id INTO v_email_id;
    IF v_email_id IS NOT NULL THEN
      INSERT INTO public.email_queue(id, type, destinataire_id, data, statut)
      VALUES (v_email_id, 'FACTURATION_DOCUMENT', v_destinataire, v_corps, 'EN_ATTENTE');
    END IF;
  END LOOP;
  RETURN NEW;
END $fn$;

-- CREATE OR REPLACE conserve les propriétaires/ACL ; inventaire public seul.
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification)
SELECT 'fn_connect_payout_constater(uuid,text,jsonb)','SERVICE_ONLY_REVOQUE',md5(p.prosrc),
  'Constat payout exact et service-only ; REVIEW persiste jusqu’à résolution explicite.'
FROM pg_proc p WHERE p.oid='public.fn_connect_payout_constater(uuid,text,jsonb)'::regprocedure
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,
  justification=EXCLUDED.justification;
COMMIT;
