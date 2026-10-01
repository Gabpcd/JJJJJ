-- Numérotation par émetteur complet ; réservation et première émission atomiques.
-- Les numéros/pièces existants ne sont pas modifiés. Aucun appel fournisseur.
DO $preflight$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('next_invoice_number(uuid)','2a65c5c4cb8411baed63382dc4099d45','4b272f2577af4638f601c174a33941f1'),
    ('next_avoir_number(uuid)','4d1e82b79823490e820d813ba9cf2a63','14c74e73a0938b942f1e730128d3c7e0')
  ) AS attendu(signature,corps,definition) LOOP
    SELECT * INTO p FROM pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF md5(p.prosrc) IS DISTINCT FROM r.corps OR md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM r.definition
      OR NOT p.prosecdef OR pg_get_userbyid(p.proowner)<>'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature IN(r.signature,'public.'||r.signature)) THEN
      RAISE EXCEPTION 'Numérotation : source, droits ou registre inattendus (%)',r.signature;
    END IF;
  END LOOP;
  IF md5(pg_get_functiondef('public.fn_emettre_document_facturation_honoraires(uuid,text,text)'::regprocedure))
      IS DISTINCT FROM '9ce904aa006bdf9f736538f37f096883'
    OR to_regclass('private.generations_factures_honoraires') IS NOT NULL
    OR to_regprocedure('public.fn_reserver_facture_honoraires(jsonb)') IS NOT NULL
    OR to_regprocedure('public.fn_acquerir_generation_honoraires(uuid)') IS NOT NULL
    OR to_regprocedure('public.fn_terminer_generation_honoraires(uuid,uuid,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Numérotation : prérequis émission ou nouveaux objets inattendus';
  END IF;
END;
$preflight$;

CREATE TABLE private.generations_factures_honoraires (
  facture_id uuid PRIMARY KEY REFERENCES public.factures_honoraires(id),
  token uuid NOT NULL,
  expire_le timestamptz NOT NULL,
  resultat jsonb,
  documents jsonb
);
ALTER TABLE private.generations_factures_honoraires OWNER TO postgres;
ALTER TABLE private.generations_factures_honoraires ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.generations_factures_honoraires FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.generations_factures_honoraires FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.next_invoice_number(p_soignant_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public
AS $numero$
DECLARE v_seq bigint; v_prefixe text;
BEGIN
  IF p_soignant_id IS NULL THEN RAISE EXCEPTION 'Émetteur requis' USING ERRCODE='22004'; END IF;
  PERFORM pg_advisory_xact_lock(('x'||left(md5(''||p_soignant_id::text),15))::bit(64)::bigint);
  v_prefixe:=replace(p_soignant_id::text,'-','');
  -- Continuité historique tous millésimes, y compris les pièces en erreur.
  SELECT COALESCE(MAX(NULLIF(split_part(numero_facture,'-',4),'')::bigint),0)+1 INTO v_seq
  FROM public.factures_honoraires WHERE soignant_id=p_soignant_id AND numero_facture LIKE 'JOL-%';
  RETURN 'JOL-'||v_prefixe||'-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(v_seq::text,greatest(5,length(v_seq::text)),'0');
END;
$numero$;

CREATE OR REPLACE FUNCTION public.next_avoir_number(p_soignant_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public
AS $numero$
DECLARE v_seq bigint; v_prefixe text;
BEGIN
  IF p_soignant_id IS NULL THEN RAISE EXCEPTION 'Émetteur requis' USING ERRCODE='22004'; END IF;
  PERFORM pg_advisory_xact_lock(('x'||left(md5('AV:'||p_soignant_id::text),15))::bit(64)::bigint);
  v_prefixe:=replace(p_soignant_id::text,'-','');
  -- Continuité historique tous millésimes, y compris les pièces en erreur.
  SELECT COALESCE(MAX(NULLIF(split_part(numero_facture,'-',4),'')::bigint),0)+1 INTO v_seq
  FROM public.factures_honoraires WHERE soignant_id=p_soignant_id AND numero_facture LIKE 'AV-%' AND type_document='AVOIR';
  RETURN 'AV-'||v_prefixe||'-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(v_seq::text,greatest(5,length(v_seq::text)),'0');
END;
$numero$;

CREATE OR REPLACE FUNCTION public.fn_acquerir_generation_honoraires(p_facture_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $bail$
DECLARE v_f public.factures_honoraires%ROWTYPE; v_m uuid; v_b private.generations_factures_honoraires%ROWTYPE; v_token uuid;
BEGIN
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' THEN
    RAISE EXCEPTION 'Réservé au service de facturation' USING ERRCODE='42501'; END IF;
  SELECT mission_id INTO v_m FROM public.factures_honoraires WHERE id=p_facture_id;
  PERFORM 1 FROM public.missions WHERE id=v_m FOR UPDATE;
  SELECT * INTO v_f FROM public.factures_honoraires WHERE id=p_facture_id FOR UPDATE;
  IF NOT FOUND OR v_f.mission_id IS DISTINCT FROM v_m THEN RAISE EXCEPTION 'FACTURE_GENERATION_INTROUVABLE'; END IF;
  IF v_f.statut NOT IN('BROUILLON','EN_GENERATION','ERREUR_GENERATION') THEN
    RETURN jsonb_build_object('acquise',false,'statut',v_f.statut,'facture_id',v_f.id); END IF;
  SELECT * INTO v_b FROM private.generations_factures_honoraires WHERE facture_id=p_facture_id FOR UPDATE;
  IF FOUND AND v_b.resultat IS NULL AND v_b.expire_le>clock_timestamp() THEN
    RETURN jsonb_build_object('acquise',false,'statut','EN_GENERATION','facture_id',v_f.id); END IF;
  -- Le trigger de période et les index normaux refusent une autre pièce active.
  UPDATE public.factures_honoraires SET statut='EN_GENERATION' WHERE id=p_facture_id AND statut<>'EN_GENERATION';
  v_token:=gen_random_uuid();
  INSERT INTO private.generations_factures_honoraires(facture_id,token,expire_le)
    VALUES(p_facture_id,v_token,clock_timestamp()+interval '10 minutes')
    ON CONFLICT(facture_id) DO UPDATE SET token=EXCLUDED.token,expire_le=EXCLUDED.expire_le,resultat=NULL,documents=NULL;
  RETURN jsonb_build_object('acquise',true,'token',v_token,'facture_id',v_f.id,'statut','EN_GENERATION');
END;
$bail$;

CREATE OR REPLACE FUNCTION public.fn_reserver_facture_honoraires(p_document jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $reservation$
DECLARE v_d public.factures_honoraires%ROWTYPE; v_m public.missions%ROWTYPE; v_f public.factures_honoraires%ROWTYPE;
  v_ids uuid[]; v_numero text; v_bail jsonb;
BEGIN
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' THEN
    RAISE EXCEPTION 'Réservé au service de facturation' USING ERRCODE='42501'; END IF;
  IF jsonb_typeof(p_document) IS DISTINCT FROM 'object' OR EXISTS(
    SELECT 1 FROM jsonb_object_keys(p_document) k WHERE k<>ALL(ARRAY[
      'soignant_id',
      'etablissement_id',
      'mission_id',
      'montant_ht',
      'montant_tva',
      'montant_ttc',
      'taux_tva',
      'exoneration_tva',
      'date_emission',
      'date_echeance',
      'mandat_version',
      'template_version',
      'is_public_sector',
      'siret_client',
      'service_code_chorus',
      'periode_debut',
      'periode_fin',
      'numero_semaine_iso',
      'annee_iso',
      'est_facture_finale_mission',
      'facture_precedente_id',
      'regime_tva_snapshot',
      'base_legale_tva_snapshot',
      'nature_prestation_snapshot',
      'description_prestation_snapshot',
      'quantite_heures_snapshot',
      'taux_horaire_snapshot',
      'emetteur_identite_snapshot',
      'emetteur_profession_snapshot',
      'emetteur_siret_snapshot',
      'emetteur_numero_professionnel_snapshot',
      'emetteur_adresse_snapshot',
      'emetteur_adresse_rue_snapshot',
      'emetteur_adresse_code_postal_snapshot',
      'emetteur_adresse_ville_snapshot',
      'emetteur_email_snapshot',
      'emetteur_numero_tva_snapshot',
      'destinataire_nom_snapshot',
      'destinataire_siret_snapshot',
      'destinataire_adresse_rue_snapshot',
      'destinataire_adresse_code_postal_snapshot',
      'destinataire_adresse_ville_snapshot'
    ]::text[])) THEN RAISE EXCEPTION 'FACTURE_RESERVATION_CHAMPS_INVALIDES' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_d FROM jsonb_populate_record(NULL::public.factures_honoraires,p_document);
  SELECT * INTO v_m FROM public.missions WHERE id=v_d.mission_id FOR UPDATE;
  IF NOT FOUND OR v_m.type_contrat_applique IS DISTINCT FROM 'LIBERAL'
    OR v_m.soignant_assigne_id IS DISTINCT FROM v_d.soignant_id
    OR v_m.etablissement_id IS DISTINCT FROM v_d.etablissement_id
    OR v_d.periode_debut IS NULL OR v_d.periode_fin IS NULL OR v_d.periode_fin<v_d.periode_debut
    OR v_d.est_facture_finale_mission IS NULL THEN
    RAISE EXCEPTION 'FACTURE_RESERVATION_MISSION_INCOHERENTE' USING ERRCODE='23514'; END IF;
  -- Un original/correctif déjà actif n'est jamais remplacé par une nouvelle émission.
  SELECT array_agg(id) INTO v_ids FROM public.factures_honoraires
  WHERE mission_id=v_d.mission_id AND type_document='FACTURE' AND nature_correction<>'COMPLEMENT'
    AND statut NOT IN('ANNULEE','REMPLACEE')
    AND (est_facture_finale_mission=v_d.est_facture_finale_mission AND
      (v_d.est_facture_finale_mission OR (annee_iso=v_d.annee_iso AND numero_semaine_iso=v_d.numero_semaine_iso)));
  IF cardinality(v_ids)>1 THEN RAISE EXCEPTION 'FACTURE_RESERVATION_HISTORIQUE_AMBIGU' USING ERRCODE='23514'; END IF;
  IF cardinality(v_ids)=1 THEN
    SELECT * INTO v_f FROM public.factures_honoraires WHERE id=v_ids[1] FOR UPDATE;
    IF v_f.soignant_id IS DISTINCT FROM v_d.soignant_id OR v_f.etablissement_id IS DISTINCT FROM v_d.etablissement_id
      OR v_f.periode_debut IS DISTINCT FROM v_d.periode_debut OR v_f.periode_fin IS DISTINCT FROM v_d.periode_fin THEN
      RAISE EXCEPTION 'FACTURE_RESERVATION_PERIODE_DIFFERENTE' USING ERRCODE='23514'; END IF;
    RETURN jsonb_build_object('cree',false,'facture_id',v_f.id,'numero_facture',v_f.numero_facture,'statut',v_f.statut,'nature_correction',v_f.nature_correction);
  END IF;
  v_numero:=public.next_invoice_number(v_d.soignant_id);
  INSERT INTO public.factures_honoraires(numero_facture,statut,type_document,nature_correction,
    soignant_id,
    etablissement_id,
    mission_id,
    montant_ht,
    montant_tva,
    montant_ttc,
    taux_tva,
    exoneration_tva,
    date_emission,
    date_echeance,
    mandat_version,
    template_version,
    is_public_sector,
    siret_client,
    service_code_chorus,
    periode_debut,
    periode_fin,
    numero_semaine_iso,
    annee_iso,
    est_facture_finale_mission,
    facture_precedente_id,
    regime_tva_snapshot,
    base_legale_tva_snapshot,
    nature_prestation_snapshot,
    description_prestation_snapshot,
    quantite_heures_snapshot,
    taux_horaire_snapshot,
    emetteur_identite_snapshot,
    emetteur_profession_snapshot,
    emetteur_siret_snapshot,
    emetteur_numero_professionnel_snapshot,
    emetteur_adresse_snapshot,
    emetteur_adresse_rue_snapshot,
    emetteur_adresse_code_postal_snapshot,
    emetteur_adresse_ville_snapshot,
    emetteur_email_snapshot,
    emetteur_numero_tva_snapshot,
    destinataire_nom_snapshot,
    destinataire_siret_snapshot,
    destinataire_adresse_rue_snapshot,
    destinataire_adresse_code_postal_snapshot,
    destinataire_adresse_ville_snapshot
  ) VALUES(v_numero,'EN_GENERATION','FACTURE','ORIGINALE',
    v_d.soignant_id,
    v_d.etablissement_id,
    v_d.mission_id,
    v_d.montant_ht,
    v_d.montant_tva,
    v_d.montant_ttc,
    v_d.taux_tva,
    v_d.exoneration_tva,
    v_d.date_emission,
    v_d.date_echeance,
    v_d.mandat_version,
    v_d.template_version,
    v_d.is_public_sector,
    v_d.siret_client,
    v_d.service_code_chorus,
    v_d.periode_debut,
    v_d.periode_fin,
    v_d.numero_semaine_iso,
    v_d.annee_iso,
    v_d.est_facture_finale_mission,
    v_d.facture_precedente_id,
    v_d.regime_tva_snapshot,
    v_d.base_legale_tva_snapshot,
    v_d.nature_prestation_snapshot,
    v_d.description_prestation_snapshot,
    v_d.quantite_heures_snapshot,
    v_d.taux_horaire_snapshot,
    v_d.emetteur_identite_snapshot,
    v_d.emetteur_profession_snapshot,
    v_d.emetteur_siret_snapshot,
    v_d.emetteur_numero_professionnel_snapshot,
    v_d.emetteur_adresse_snapshot,
    v_d.emetteur_adresse_rue_snapshot,
    v_d.emetteur_adresse_code_postal_snapshot,
    v_d.emetteur_adresse_ville_snapshot,
    v_d.emetteur_email_snapshot,
    v_d.emetteur_numero_tva_snapshot,
    v_d.destinataire_nom_snapshot,
    v_d.destinataire_siret_snapshot,
    v_d.destinataire_adresse_rue_snapshot,
    v_d.destinataire_adresse_code_postal_snapshot,
    v_d.destinataire_adresse_ville_snapshot
  ) RETURNING * INTO v_f;
  v_bail:=public.fn_acquerir_generation_honoraires(v_f.id);
  IF (v_bail->>'acquise')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FACTURE_RESERVATION_BAIL_REFUSE'; END IF;
  RETURN v_bail||jsonb_build_object('cree',true,'numero_facture',v_numero);
END;
$reservation$;

CREATE OR REPLACE FUNCTION public.fn_terminer_generation_honoraires(p_facture_id uuid,p_token uuid,p_documents jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $terminer$
DECLARE v_f public.factures_honoraires%ROWTYPE; v_b private.generations_factures_honoraires%ROWTYPE;
  v_m uuid; v_resultat jsonb; v_prefixe text; v_pdf text; v_xml text; v_uuid_regex constant text:='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
BEGIN
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' THEN
    RAISE EXCEPTION 'Réservé au service de facturation' USING ERRCODE='42501'; END IF;
  -- Le trigger de période d'un complément lit aussi l'origine : sérialiser
  -- avec les résolveurs avant de prendre la pièce, le bail et cet advisory.
  SELECT mission_id INTO v_m FROM public.factures_honoraires WHERE id=p_facture_id;
  PERFORM 1 FROM public.missions WHERE id=v_m FOR UPDATE;
  SELECT * INTO v_f FROM public.factures_honoraires
    WHERE id=p_facture_id AND mission_id IS NOT DISTINCT FROM v_m FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'FACTURE_GENERATION_INTROUVABLE'; END IF;
  SELECT * INTO v_b FROM private.generations_factures_honoraires WHERE facture_id=p_facture_id FOR UPDATE;
  IF NOT FOUND OR p_token IS NULL OR v_b.token IS DISTINCT FROM p_token THEN
    RAISE EXCEPTION 'FACTURE_GENERATION_TOKEN_PERIME' USING ERRCODE='23514'; END IF;
  IF v_b.resultat IS NOT NULL THEN
    IF p_documents IS NOT NULL AND p_documents IS DISTINCT FROM v_b.documents THEN
      RAISE EXCEPTION 'FACTURE_GENERATION_REJEU_DIFFERENT' USING ERRCODE='23514'; END IF;
    RETURN v_b.resultat;
  END IF;
  -- Un succès acquis reste rejouable ; un renderer expiré ne peut plus écrire.
  IF v_b.expire_le<=clock_timestamp() THEN
    RAISE EXCEPTION 'FACTURE_GENERATION_BAIL_EXPIRE' USING ERRCODE='23514'; END IF;
  IF v_f.statut IS DISTINCT FROM 'EN_GENERATION' THEN RAISE EXCEPTION 'FACTURE_GENERATION_ETAT_INVALIDE' USING ERRCODE='23514'; END IF;
  IF p_documents IS NULL THEN
    UPDATE public.factures_honoraires SET statut='ERREUR_GENERATION' WHERE id=p_facture_id;
    UPDATE private.generations_factures_honoraires SET expire_le=clock_timestamp() WHERE facture_id=p_facture_id;
    RETURN jsonb_build_object('success',false,'statut','ERREUR_GENERATION','facture_id',p_facture_id);
  END IF;
  v_prefixe:=(CASE WHEN v_f.type_document='AVOIR' THEN 'avoirs/' ELSE 'invoices/' END)||v_f.soignant_id::text||'/'||v_f.numero_facture||'/';
  v_pdf:=p_documents->>'pdf_s3_key'; v_xml:=p_documents->>'facturx_xml_url';
  IF jsonb_typeof(p_documents) IS DISTINCT FROM 'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_documents))<>4
    OR v_pdf IS NULL OR v_xml IS NULL
    OR left(v_pdf,length(v_prefixe))<>v_prefixe OR left(v_xml,length(v_prefixe))<>v_prefixe
    OR substring(v_pdf from length(v_prefixe)+1) !~ ('^'||v_uuid_regex||'\.pdf$')
    OR substring(v_xml from length(v_prefixe)+1) !~ ('^'||v_uuid_regex||'\.xml$')
    OR COALESCE(p_documents->>'pdf_sha256','') !~ '^[a-f0-9]{64}$'
    OR COALESCE(p_documents->>'xml_sha256','') !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'FACTURE_GENERATION_DOCUMENTS_INVALIDES' USING ERRCODE='23514'; END IF;
  INSERT INTO public.factures_honoraires_documents(facture_honoraire_id,pdf_s3_key,facturx_xml_url,pdf_sha256,xml_sha256,motif_generation)
    VALUES(p_facture_id,v_pdf,v_xml,p_documents->>'pdf_sha256',p_documents->>'xml_sha256',
      CASE WHEN v_f.nature_correction='ORIGINALE' THEN 'EMISSION_INITIALE' ELSE 'EMISSION_DOCUMENT_CORRECTION' END);
  IF v_f.type_document='AVOIR' THEN
    UPDATE public.factures_honoraires cible
      SET chorus_avoir_reference_invoice=origine.numero_facture
      FROM public.factures_honoraires origine
      WHERE cible.id=p_facture_id AND origine.id=v_f.facture_precedente_id
        AND origine.mission_id=v_f.mission_id AND origine.soignant_id=v_f.soignant_id
        AND origine.etablissement_id=v_f.etablissement_id AND origine.type_document='FACTURE';
    IF NOT FOUND THEN RAISE EXCEPTION 'FACTURE_GENERATION_REFERENCE_INVALIDE' USING ERRCODE='23514'; END IF;
  END IF;
  v_resultat:=public.fn_emettre_document_facturation_honoraires(p_facture_id,v_pdf,v_xml);
  IF (v_resultat->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FACTURE_GENERATION_EMISSION_REFUSEE'; END IF;
  UPDATE private.generations_factures_honoraires SET resultat=v_resultat,documents=p_documents WHERE facture_id=p_facture_id;
  RETURN v_resultat;
END;
$terminer$;

ALTER FUNCTION public.next_invoice_number(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.next_invoice_number(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.next_invoice_number(uuid) TO service_role;
ALTER FUNCTION public.next_avoir_number(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.next_avoir_number(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.next_avoir_number(uuid) TO service_role;
ALTER FUNCTION public.fn_acquerir_generation_honoraires(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_acquerir_generation_honoraires(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acquerir_generation_honoraires(uuid) TO service_role;
ALTER FUNCTION public.fn_reserver_facture_honoraires(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_reserver_facture_honoraires(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_facture_honoraires(jsonb) TO service_role;
ALTER FUNCTION public.fn_terminer_generation_honoraires(uuid,uuid,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_terminer_generation_honoraires(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_terminer_generation_honoraires(uuid,uuid,jsonb) TO service_role;

DO $postflight$
DECLARE v_signature text; p record;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY['next_invoice_number(uuid)','next_avoir_number(uuid)','fn_acquerir_generation_honoraires(uuid)','fn_reserver_facture_honoraires(jsonb)','fn_terminer_generation_honoraires(uuid,uuid,jsonb)'] LOOP
    SELECT * INTO p FROM pg_proc WHERE oid=('public.'||v_signature)::regprocedure;
    IF NOT p.prosecdef OR pg_get_userbyid(p.proowner)<>'postgres'
      OR EXISTS(SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee NOT IN('postgres'::regrole,'service_role'::regrole)
        OR a.privilege_type<>'EXECUTE' OR a.is_grantable)
      OR (SELECT count(*) FROM aclexplode(p.proacl))<>2 THEN RAISE EXCEPTION 'Numérotation : ACL finale invalide'; END IF;
    INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification)
      VALUES(v_signature,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Réservation et émission documentaires : JWT service, aucune invocation fournisseur.');
  END LOOP;
END;
$postflight$;
