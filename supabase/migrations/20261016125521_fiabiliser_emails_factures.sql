-- Nouvelles émissions uniquement : aucun rattrapage des factures historiques.
-- Le reçu et la file sont créés dans la transaction qui émet le document.
CREATE TABLE private.facturation_email_livraisons (
  email_id uuid PRIMARY KEY DEFAULT gen_random_uuid()
    REFERENCES public.email_queue(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  famille text NOT NULL CHECK (famille IN ('COMMISSION', 'HONORAIRES')),
  document_id uuid NOT NULL,
  destinataire_id uuid NOT NULL,
  corps jsonb NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  tentatives integer NOT NULL DEFAULT 0 CHECK (tentatives BETWEEN 0 AND 5),
  premiere_tentative_le timestamptz,
  prochaine_tentative_le timestamptz NOT NULL DEFAULT now(),
  reservation uuid,
  UNIQUE (famille, document_id, destinataire_id)
);
ALTER TABLE private.facturation_email_livraisons ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.facturation_email_livraisons FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX facturation_email_reprise ON private.facturation_email_livraisons(prochaine_tentative_le, email_id);

CREATE FUNCTION private.mettre_emission_facture_en_file()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_famille text := CASE TG_TABLE_NAME WHEN 'factures' THEN 'COMMISSION' ELSE 'HONORAIRES' END;
  v_destinataire uuid;
  v_role_destinataire text;
  v_payload jsonb;
  v_corps jsonb;
  v_email_id uuid;
  v_cle text;
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
REVOKE ALL ON FUNCTION private.mettre_emission_facture_en_file() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_email_emission_commission AFTER INSERT OR UPDATE OF statut ON public.factures
FOR EACH ROW EXECUTE FUNCTION private.mettre_emission_facture_en_file();
CREATE TRIGGER trg_email_emission_honoraires AFTER INSERT OR UPDATE OF statut ON public.factures_honoraires
FOR EACH ROW EXECUTE FUNCTION private.mettre_emission_facture_en_file();

-- La réservation évite deux workers concurrents ; chaque nouvelle tentative
-- garde exactement le même corps et la même identité chez le fournisseur.
CREATE FUNCTION public.fn_reserver_email_facturation(p_email_id uuid)
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

CREATE FUNCTION public.fn_acquitter_email_facturation(p_email_id uuid, p_reservation uuid, p_resultat text, p_erreur text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE l private.facturation_email_livraisons;
BEGIN
  IF p_resultat IS NULL OR p_resultat NOT IN ('ENVOYE', 'ANNULE', 'ERREUR') THEN RAISE EXCEPTION 'Résultat invalide'; END IF;
  SELECT * INTO l FROM private.facturation_email_livraisons WHERE email_id = p_email_id FOR UPDATE;
  IF NOT FOUND OR l.reservation IS NULL OR l.reservation IS DISTINCT FROM p_reservation THEN RAISE EXCEPTION 'Réservation facture invalide'; END IF;
  UPDATE public.email_queue SET statut = p_resultat, envoye = p_resultat = 'ENVOYE',
    envoye_le = CASE WHEN p_resultat = 'ENVOYE' THEN now() ELSE NULL END,
    erreur = CASE p_resultat WHEN 'ERREUR' THEN left(coalesce(p_erreur, 'Transport facture à reprendre'), 1000)
      WHEN 'ANNULE' THEN 'Envoi refusé par les préférences ou les garde-fous du transport' ELSE NULL END
    WHERE id = p_email_id AND statut = 'EN_ATTENTE' AND type = 'FACTURATION_DOCUMENT';
  UPDATE private.facturation_email_livraisons SET reservation = NULL,
    prochaine_tentative_le = now() + make_interval(mins => least(60, 15 * greatest(1, l.tentatives)))
    WHERE email_id = p_email_id;
END $fn$;

CREATE FUNCTION public.fn_reprendre_emails_facturation()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE n integer;
BEGIN
  UPDATE public.email_queue q SET statut = 'EN_ATTENTE'
  FROM private.facturation_email_livraisons l
  WHERE q.id = l.email_id AND q.type = 'FACTURATION_DOCUMENT' AND q.statut = 'ERREUR'
    AND l.prochaine_tentative_le <= now() AND l.tentatives < 5
    -- L'ancien cron peut refuser ce nouveau type entre la migration et son
    -- déploiement. Sans première réservation, aucun appel fournisseur n'a eu lieu.
    AND ((l.premiere_tentative_le IS NULL AND l.tentatives = 0)
      OR l.premiere_tentative_le >= now() - interval '20 hours');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $fn$;
REVOKE ALL ON FUNCTION public.fn_reserver_email_facturation(uuid),
  public.fn_acquitter_email_facturation(uuid,uuid,text,text),public.fn_reprendre_emails_facturation() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_email_facturation(uuid),
  public.fn_acquitter_email_facturation(uuid,uuid,text,text),public.fn_reprendre_emails_facturation() TO service_role;

ALTER FUNCTION private.mettre_emission_facture_en_file() OWNER TO postgres;
ALTER FUNCTION public.fn_reserver_email_facturation(uuid) OWNER TO postgres;
ALTER FUNCTION public.fn_acquitter_email_facturation(uuid,uuid,text,text) OWNER TO postgres;
ALTER FUNCTION public.fn_reprendre_emails_facturation() OWNER TO postgres;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT signature,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),
  'File des nouvelles émissions de factures : service_role seulement, reçu privé immuable, destinataire revalidé, identité stable et reprise bornée sans fournisseur SQL.',now()
FROM unnest(ARRAY['fn_reserver_email_facturation(uuid)',
  'fn_acquitter_email_facturation(uuid,uuid,text,text)','fn_reprendre_emails_facturation()']) AS f(signature)
JOIN pg_proc p ON p.oid=to_regprocedure('public.'||f.signature)
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,
  justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
