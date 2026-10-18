-- Les seules nouvelles demandes remplacent l'ancienne insertion EMISE sans PDF.
-- Aucun backfill : ni pièce historique, ni email, ni paiement n'est rejoué.
DO $guard$
BEGIN
 IF to_regprocedure('public.fn_prendre_demandes_facturation_honoraires(integer)') IS NOT NULL
  OR to_regprocedure('public.fn_constater_demande_facturation_honoraires(uuid,uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'HONORAIRES_NOUVELLE_SIGNATURE_EXISTANTE'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_generer_facture_honoraires_mission(uuid)'::regprocedure)
      IS DISTINCT FROM '0e12272c819f28526ca58978a90adbd7' THEN
  RAISE EXCEPTION 'HONORAIRES_PRODUCTEUR_SOURCE_INATTENDUE';
 END IF;
END $guard$;

CREATE TABLE private.demandes_facturation_honoraires (
 mission_id uuid PRIMARY KEY REFERENCES public.missions(id),
 cree_le timestamptz NOT NULL DEFAULT now(),
 prochain_essai_le timestamptz NOT NULL DEFAULT now(),
 tentatives integer NOT NULL DEFAULT 0 CHECK (tentatives>=0),
 token uuid,
 expire_le timestamptz,
 terminee_le timestamptz,
 facture_id uuid REFERENCES public.factures_honoraires(id),
 facture_commission_id uuid REFERENCES public.factures(id),
 dernier_echec text CHECK (dernier_echec IS NULL OR dernier_echec='GENERATION_NON_TERMINEE'),
 CHECK ((token IS NULL)=(expire_le IS NULL)),
 CHECK ((terminee_le IS NULL)=(facture_id IS NULL)),
 CHECK ((terminee_le IS NULL)=(facture_commission_id IS NULL))
);
ALTER TABLE private.demandes_facturation_honoraires ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.demandes_facturation_honoraires FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON private.demandes_facturation_honoraires TO service_role;
CREATE POLICY demandes_facturation_honoraires_service_lecture
 ON private.demandes_facturation_honoraires FOR SELECT TO service_role USING (true);
CREATE INDEX demandes_facturation_honoraires_attente
 ON private.demandes_facturation_honoraires(prochain_essai_le,mission_id) WHERE terminee_le IS NULL;

CREATE OR REPLACE FUNCTION "public"."fn_generer_facture_honoraires_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_numero TEXT;
    v_facture_id UUID;
    v_existing_id UUID;
    v_periode_debut DATE;
    v_periode_fin DATE;
BEGIN
    SELECT m.*, e.nom AS etab_nom
    INTO v_mission
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_mission_id AND m.statut = 'TERMINEE';

    IF v_mission IS NULL THEN
        RETURN '{"error":"Mission introuvable ou non terminée"}'::JSONB;
    END IF;

    IF v_mission.soignant_assigne_id IS NULL THEN
        RETURN '{"error":"Aucun soignant assigné"}'::JSONB;
    END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
    IF v_soignant IS NULL THEN
        RETURN '{"error":"Soignant introuvable"}'::JSONB;
    END IF;

    IF NOT COALESCE(v_soignant.mandat_facturation_signe, FALSE) THEN
        RETURN '{"error":"Le soignant n''a pas encore signé le mandat de facturation"}'::JSONB;
    END IF;

    SELECT id INTO v_existing_id FROM factures_honoraires WHERE mission_id = p_mission_id LIMIT 1;
    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'facture_id', v_existing_id, 'message', 'Facture déjà existante');
    END IF;

    -- Périmètre observé uniquement. Les autres stratégies et la rétrocession
    -- conservent ci-dessous leur corps historique, sans changement de calendrier.
    IF v_mission.type_contrat_applique = 'LIBERAL'
       AND v_mission.mode_remuneration = 'TAUX_HORAIRE'
       AND v_mission.strategie_facturation = 'FINALE_UNIQUE' THEN
        INSERT INTO private.demandes_facturation_honoraires(mission_id)
        VALUES(p_mission_id) ON CONFLICT(mission_id) DO NOTHING;
        RETURN jsonb_build_object('success',true,'emission_en_attente',true,'mission_id',p_mission_id);
    END IF;

    v_numero := 'FH-' || to_char(now(), 'YYYY-MM') || '-' || lpad(
        (COALESCE((SELECT COUNT(*) FROM factures_honoraires WHERE date_emission >= date_trunc('month', now())), 0) + 1)::TEXT,
        4, '0'
    );

    -- Période de la facture = bornes de la mission (NOT NULL en base)
    v_periode_debut := COALESCE(v_mission.debut_le::date, CURRENT_DATE);
    v_periode_fin := COALESCE(v_mission.fin_le::date, v_mission.debut_le::date, CURRENT_DATE);

    INSERT INTO factures_honoraires (
        numero_facture, soignant_id, etablissement_id, mission_id,
        montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
        date_emission, date_echeance, statut, mandat_version,
        periode_debut, periode_fin,
        numero_semaine_iso, annee_iso
    ) VALUES (
        v_numero,
        v_mission.soignant_assigne_id,
        v_mission.etablissement_id,
        p_mission_id,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        TRUE,
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        'EMISE',
        v_soignant.mandat_facturation_version,
        v_periode_debut,
        v_periode_fin,
        EXTRACT(WEEK FROM v_periode_debut)::smallint,
        EXTRACT(ISOYEAR FROM v_periode_debut)::smallint
    ) RETURNING id INTO v_facture_id;

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_generer_facture_honoraires_mission(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_generer_facture_honoraires_mission(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_prendre_demandes_facturation_honoraires(p_limit integer DEFAULT 3)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' SET timezone TO 'UTC' AS $fn$
DECLARE r record; token_bail uuid; resultat jsonb:='[]'::jsonb;
BEGIN
 IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' THEN
  RAISE EXCEPTION 'Réservé au service de facturation' USING ERRCODE='42501'; END IF;
 FOR r IN SELECT d.mission_id
  FROM private.demandes_facturation_honoraires d JOIN public.missions m ON m.id=d.mission_id
  WHERE d.terminee_le IS NULL AND d.prochain_essai_le<=now()
   AND (d.expire_le IS NULL OR d.expire_le<=clock_timestamp())
   AND m.statut='TERMINEE' AND m.type_contrat_applique='LIBERAL'
   AND private.fn_mission_est_reelle(m.id) IS TRUE
   AND m.mode_remuneration='TAUX_HORAIRE' AND m.strategie_facturation='FINALE_UNIQUE'
   AND NOT EXISTS(SELECT FROM public.presences p WHERE p.mission_id=m.id
     AND COALESCE(p.valide_par_etablissement,false) IS FALSE
     AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL))
  ORDER BY d.prochain_essai_le,d.mission_id
  LIMIT greatest(1,least(COALESCE(p_limit,3),3)) FOR UPDATE OF d SKIP LOCKED
 LOOP
  token_bail:=gen_random_uuid();
  UPDATE private.demandes_facturation_honoraires d SET token=token_bail,
   expire_le=clock_timestamp()+interval '10 minutes',tentatives=d.tentatives+1
   WHERE d.mission_id=r.mission_id;
  resultat:=resultat||jsonb_build_array(jsonb_build_object('mission_id',r.mission_id,'token',token_bail,'body',jsonb_build_object('mission_id',r.mission_id)));
 END LOOP;
 RETURN resultat;
END $fn$;
REVOKE ALL ON FUNCTION public.fn_prendre_demandes_facturation_honoraires(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_prendre_demandes_facturation_honoraires(integer) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_constater_demande_facturation_honoraires(p_mission_id uuid,p_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE demande private.demandes_facturation_honoraires%ROWTYPE; fh_id uuid; fc_id uuid; n integer;
BEGIN
 IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' THEN
  RAISE EXCEPTION 'Réservé au service de facturation' USING ERRCODE='42501'; END IF;
 SELECT * INTO demande FROM private.demandes_facturation_honoraires d WHERE d.mission_id=p_mission_id FOR UPDATE;
 IF NOT FOUND OR p_token IS NULL OR demande.token IS DISTINCT FROM p_token THEN
  RAISE EXCEPTION 'DEMANDE_FACTURATION_TOKEN_INVALIDE' USING ERRCODE='23514'; END IF;
 IF demande.terminee_le IS NOT NULL THEN RETURN jsonb_build_object('success',true,'facture_id',demande.facture_id,'facture_commission_id',demande.facture_commission_id); END IF;
 IF demande.expire_le<=clock_timestamp() THEN
  RAISE EXCEPTION 'DEMANDE_FACTURATION_BAIL_EXPIRE' USING ERRCODE='23514'; END IF;
 -- Le résultat HTTP ne suffit jamais : constater les pièces canoniques émises,
 -- snapshots, version PDF/XML et FC liée. Une erreur FC reste reprenable.
 SELECT count(*),(array_agg(f.id))[1],(array_agg(c.id))[1] INTO n,fh_id,fc_id
 FROM public.factures_honoraires f JOIN public.missions m ON m.id=f.mission_id
 JOIN public.factures c ON c.facture_honoraire_id=f.id AND c.mission_id=f.mission_id
   AND c.etablissement_id=f.etablissement_id AND c.type_document='FACTURE'
 WHERE f.mission_id=p_mission_id AND f.soignant_id=m.soignant_assigne_id AND f.etablissement_id=m.etablissement_id
   AND f.type_document='FACTURE' AND f.nature_correction='ORIGINALE' AND f.est_facture_finale_mission IS TRUE
   AND f.statut IN('EMISE','PAYEE','EN_RETARD') AND c.statut IN('EMISE','PAYEE','EN_RETARD','VIREMENT_DECLARE')
   AND f.template_version='v2_facturx' AND f.regime_tva_snapshot IS NOT NULL
   AND f.emise_le IS NOT NULL AND f.pdf_s3_key IS NOT NULL AND f.facturx_xml_url IS NOT NULL
   AND EXISTS(SELECT FROM public.factures_honoraires_documents v WHERE v.facture_honoraire_id=f.id
     AND v.pdf_s3_key=f.pdf_s3_key AND v.facturx_xml_url=f.facturx_xml_url
     AND v.pdf_sha256 ~ '^[a-f0-9]{64}$' AND v.xml_sha256 ~ '^[a-f0-9]{64}$');
 IF n=1 THEN
  UPDATE private.demandes_facturation_honoraires SET terminee_le=now(),facture_id=fh_id,
    facture_commission_id=fc_id,dernier_echec=NULL WHERE mission_id=p_mission_id;
  RETURN jsonb_build_object('success',true,'facture_id',fh_id,'facture_commission_id',fc_id);
 END IF;
 UPDATE private.demandes_facturation_honoraires SET token=NULL,expire_le=NULL,
   prochain_essai_le=now()+interval '5 minutes',dernier_echec='GENERATION_NON_TERMINEE' WHERE mission_id=p_mission_id;
 RETURN jsonb_build_object('success',false,'reason','GENERATION_NON_TERMINEE');
END $fn$;
REVOKE ALL ON FUNCTION public.fn_constater_demande_facturation_honoraires(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_constater_demande_facturation_honoraires(uuid,uuid) TO service_role;

-- Deuxième passage borné au même worker ; calendrier global inchangé.
-- Son arrêt, sa sonde sans effet et son activation suivent les gardes existantes.
DO $cron_source$
DECLARE spec record; definition text; ancien text; nouveau text; changement jsonb; job_id bigint;
BEGIN
 FOR spec IN SELECT * FROM (VALUES
  ('private.fn_appeler_edge_critique(text,boolean)','0608d26209d67ac41d60713417aa51e4','[["WHEN ''weekly-invoicing-cron'' THEN\n      v_endpoint := ''weekly-invoicing-cron'';", "WHEN ''weekly-invoicing-cron'' THEN\n      v_endpoint := ''weekly-invoicing-cron'';\n    WHEN ''honoraires-emission-demandes'' THEN\n      v_endpoint := ''weekly-invoicing-cron'';\n      v_body := jsonb_build_object(''mode'',''demandes'');"]]'::jsonb),
  ('private.fn_sonder_crons_edge_critiques()','113e9484e52bbb6031f2f38a10d822e3','[["    ''weekly-invoicing-cron''", "    ''honoraires-emission-demandes'',\n    ''weekly-invoicing-cron''"]]'::jsonb),
  ('private.fn_etat_sondes_crons_edge_critiques(jsonb)','efc54d970fd5b508c7f15003c258776f','[["    ''weekly-invoicing-cron''", "    ''honoraires-emission-demandes'',\n    ''weekly-invoicing-cron''"], ["v_ok = 8", "v_ok = 9"]]'::jsonb),
  ('private.fn_activer_crons_edge_critiques(jsonb,text)','ddca2434ee6bb69affe20504e7d70b90','[["    ''weekly-invoicing-cron''", "    ''honoraires-emission-demandes'',\n    ''weekly-invoicing-cron''"], ["Les huit sondes", "Les neuf sondes"], ["que les neuf", "que les dix"]]'::jsonb),
  ('private.fn_etat_activation_crons_edge_critiques()','ffbb5ae789f7b43a1771ab7db81de123','[["    ''weekly-invoicing-cron''", "    ''honoraires-emission-demandes'',\n    ''weekly-invoicing-cron''"], ["cardinality(v_actifs) = 9", "cardinality(v_actifs) = 10"]]'::jsonb),
  ('private.fn_desactiver_crons_edge_critiques()','80595b78264d83b333c99d964e405e91','[["    ''weekly-invoicing-cron''", "    ''honoraires-emission-demandes'',\n    ''weekly-invoicing-cron''"], ["cardinality(v_desactives) = 9", "cardinality(v_desactives) = 10"]]'::jsonb),
  ('private.fn_reconcilier_crons_edge_critiques_inactifs()','6139da08be0d0d5a0328edd3b4e5ba28','[["(''weekly-invoicing-cron'', ''0 4,5 * * *'')", "(''weekly-invoicing-cron'', ''0 4,5 * * *''),\n        (''honoraires-emission-demandes'', ''*/5 * * * *'')"], ["''weekly-invoicing-cron'',\n       ''jolene-monitor-crons-edge-critiques''", "''weekly-invoicing-cron'',\n       ''honoraires-emission-demandes'',\n       ''jolene-monitor-crons-edge-critiques''"], ["''jobs_critiques'', 9", "''jobs_critiques'', 10"]]'::jsonb)
 ) AS sources(signature,empreinte,changements)
 LOOP
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(spec.signature)) IS DISTINCT FROM spec.empreinte THEN
   RAISE EXCEPTION 'HONORAIRES_CRON_EMPREINTE_INATTENDUE: %',spec.signature; END IF;
  definition:=pg_get_functiondef(to_regprocedure(spec.signature));
  FOR changement IN SELECT value FROM jsonb_array_elements(spec.changements) LOOP
   ancien:=changement->>0; nouveau:=changement->>1;
   IF (length(definition)-length(replace(definition,ancien,'')))/length(ancien)<>1 THEN
    RAISE EXCEPTION 'HONORAIRES_CRON_SOURCE_INATTENDUE: %',spec.signature; END IF;
   definition:=replace(definition,ancien,nouveau);
  END LOOP;
  EXECUTE definition;
 END LOOP;
 IF EXISTS(SELECT FROM pg_extension WHERE extname='pg_cron') THEN
  IF EXISTS(SELECT FROM cron.job WHERE jobname='honoraires-emission-demandes') THEN
   RAISE EXCEPTION 'HONORAIRES_CRON_DEJA_PRESENT'; END IF;
  job_id:=cron.schedule('honoraires-emission-demandes','*/5 * * * *',
    'SELECT private.fn_appeler_edge_critique(''honoraires-emission-demandes'',false)');
  -- Ne jamais activer avec l'ancien worker : activation normale après déploiement
  -- et neuf sondes auth-only exactes HTTP 2xx. STAGING reste fermé.
  PERFORM cron.alter_job(job_id:=job_id,active:=false);
 END IF;
END $cron_source$;
COMMENT ON FUNCTION private.fn_activer_crons_edge_critiques(jsonb,text) IS
 'Activation explicite post-déploiement : neuf sondes auth-only exactes, puis neuf jobs Edge et leur monitor.';

-- ACL explicites et empreintes de toutes les routines modifiées enregistrées.
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),
 'Demandes honoraires : service seul, pièces canoniques et bail exact.',now()
FROM pg_proc p WHERE p.oid IN('public.fn_prendre_demandes_facturation_honoraires(integer)'::regprocedure,
 'public.fn_constater_demande_facturation_honoraires(uuid,uuid)'::regprocedure)
ON CONFLICT(signature) DO UPDATE SET categorie=excluded.categorie,definition_md5=excluded.definition_md5,
 justification=excluded.justification,recense_le=excluded.recense_le;
UPDATE private.security_definer_inventory i SET definition_md5=md5(p.prosrc),recense_le=now()
FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
WHERE p.oid IN('public.fn_generer_facture_honoraires_mission(uuid)'::regprocedure,
 'private.fn_appeler_edge_critique(text,boolean)'::regprocedure,

 'private.fn_sonder_crons_edge_critiques()'::regprocedure,
 'private.fn_etat_sondes_crons_edge_critiques(jsonb)'::regprocedure,
 'private.fn_activer_crons_edge_critiques(jsonb,text)'::regprocedure,
 'private.fn_etat_activation_crons_edge_critiques()'::regprocedure,
 'private.fn_desactiver_crons_edge_critiques()'::regprocedure,
 'private.fn_reconcilier_crons_edge_critiques_inactifs()'::regprocedure)
 AND i.signature IN(p.oid::regprocedure::text,replace(p.oid::regprocedure::text,'public.',''));
