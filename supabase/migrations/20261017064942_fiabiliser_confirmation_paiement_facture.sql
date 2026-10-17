-- Confirmation des nouveaux paiements Checkout seulement. Aucun backfill.
-- La migration précède les nouveaux producteurs Edge. Le marqueur constant
-- distingue leur UPDATE de l'ancien code qui envoie encore directement.
-- Aucun BEGIN/COMMIT : la CLI ou le témoin appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

ALTER TABLE private.facturation_email_livraisons
  ADD COLUMN evenement text NOT NULL DEFAULT 'EMISSION'
  CHECK (evenement IN ('EMISSION','PAIEMENT'));

-- Ne pas supposer le nom tronqué d'une contrainte auto-nommée par PostgreSQL.
DO $unique_event$
DECLARE ancien_nom text;
BEGIN
  SELECT c.conname INTO STRICT ancien_nom
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='private.facturation_email_livraisons'::regclass AND c.contype='u'
    AND (SELECT array_agg(a.attname::text ORDER BY k.ordinality)
      FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum,ordinality)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum)
      =ARRAY['famille','document_id','destinataire_id']::text[];
  EXECUTE format('ALTER TABLE private.facturation_email_livraisons DROP CONSTRAINT %I',ancien_nom);
END $unique_event$;
ALTER TABLE private.facturation_email_livraisons
  ADD CONSTRAINT facturation_email_evenement_unique UNIQUE (famille,document_id,destinataire_id,evenement);
COMMENT ON COLUMN private.facturation_email_livraisons.evenement IS
  'Émission et paiement sont deux événements distincts. Les anciens reçus restent EMISSION, corps et clés inchangés.';

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
    ON CONFLICT (famille, document_id, destinataire_id, evenement) DO NOTHING
    RETURNING facturation_email_livraisons.email_id INTO v_email_id;
    IF v_email_id IS NOT NULL THEN
      INSERT INTO public.email_queue(id, type, destinataire_id, data, statut)
      VALUES (v_email_id, 'FACTURATION_DOCUMENT', v_destinataire, v_corps, 'EN_ATTENTE');
    END IF;
  END LOOP;
  RETURN NEW;
END $fn$;

CREATE FUNCTION private.mettre_paiement_facture_en_file()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $paid$
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
END $paid$;
ALTER FUNCTION private.mettre_paiement_facture_en_file() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.mettre_paiement_facture_en_file() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_email_paiement_commission AFTER UPDATE OF statut ON public.factures
FOR EACH ROW EXECUTE FUNCTION private.mettre_paiement_facture_en_file();
COMMENT ON TRIGGER trg_email_paiement_commission ON public.factures IS
  'Nouveaux producteurs service_role durable-v1 seulement ; première transition Checkout acquise vers PAYEE, jamais replay historique ni autres flux.';

CREATE OR REPLACE FUNCTION public.fn_reserver_email_facturation(p_email_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
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
END $fn$;

-- Les RPC d'acquittement et de reprise existantes restent inchangées : même
-- file, mêmes baux, même clé fournisseur et bornes cinq tentatives/vingt heures.
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT 'fn_reserver_email_facturation(uuid)','SERVICE_ONLY_REVOQUE',md5(p.prosrc),
  'Réservation service_role des reçus émission/paiement : document et preuve Checkout revalidés, corps/clé immuables, reprise bornée.',now()
FROM pg_catalog.pg_proc p WHERE p.oid='public.fn_reserver_email_facturation(uuid)'::regprocedure
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,
  justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
