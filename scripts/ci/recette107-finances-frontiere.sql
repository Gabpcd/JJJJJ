-- Schéma réduit et données synthétiques. Fonctions métier injectées par le
-- runner depuis git show bf1 ; aucun calcul métier n'est remplacé par un double.
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'UTC';
CREATE SCHEMA private;
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,definition_md5 text,recense_le timestamptz,justification text);
CREATE SCHEMA auth;
CREATE SCHEMA extensions;
CREATE TYPE public.strategie_facturation AS ENUM ('FINALE_UNIQUE','HEBDO_ET_FINALE');
-- Doubles explicites : identité de service, jamais administrateur ; aucun JWT réel.
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"role":"service_role"}'::jsonb $$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT NULL::uuid $$;
CREATE FUNCTION public.est_admin() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE TABLE public.missions (
 id uuid PRIMARY KEY, debut_le timestamptz, fin_le timestamptz,
 taux_horaire_base_fige numeric, total_brut numeric, net_a_payer numeric,
 strategie_facturation public.strategie_facturation, type_contrat_applique text,
 soignant_assigne_id uuid, etablissement_id uuid, taux_commission_fige numeric,
 taux_commission numeric, commission_facturee boolean DEFAULT false,
 facture_id uuid, modifie_le timestamptz
);
CREATE TABLE public.etablissements(id uuid PRIMARY KEY, est_secteur_public boolean);
CREATE TABLE public.mission_creneaux (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid,
 debut timestamptz, fin timestamptz, type_creneau text, est_pause boolean,
 CHECK(fin IS NULL OR fin>debut), CHECK(extract(epoch FROM(fin-debut))<=86400)
);
CREATE TABLE public.factures_honoraires (
 id uuid PRIMARY KEY, numero_facture text UNIQUE, mission_id uuid,
 soignant_id uuid, etablissement_id uuid, type_document text,
 nature_correction text DEFAULT 'ORIGINALE', statut text,
 periode_debut date, periode_fin date, est_facture_finale_mission boolean,
 facture_precedente_id uuid, montant_ht numeric, montant_ttc numeric,
 quantite_heures_snapshot numeric
);
CREATE TABLE public.factures (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), etablissement_id uuid,
 mission_id uuid, facture_honoraire_id uuid, numero_facture text UNIQUE,
 periode_debut date, periode_fin date, montant_ht numeric, taux_tva numeric,
 montant_tva numeric, montant_ttc numeric, nombre_missions integer, statut text,
 date_emission timestamptz, date_echeance date, est_secteur_public boolean,
 mode_paiement text, chorus_pro_statut text, type_document text
);
CREATE TABLE public.journaux_audit (
 acteur_id uuid, type_acteur text, action text, type_ressource text,
 id_ressource uuid, details jsonb
);
ALTER TABLE public.missions
 ADD COLUMN statut text DEFAULT 'TERMINEE',
 ADD COLUMN est_arret_maladie boolean DEFAULT false,
 ADD COLUMN mode_remuneration text DEFAULT 'TAUX_HORAIRE',
 ADD COLUMN statut_validation_tva text DEFAULT 'CONFIRMEE',
 ADD COLUMN nature_tva_prestation text DEFAULT 'SOIN_THERAPEUTIQUE_EXONERE',
 ADD COLUMN nature_tva_confirmee_soignant text DEFAULT 'SOIN_THERAPEUTIQUE_EXONERE',
 ADD COLUMN nature_tva_confirmee_par uuid DEFAULT 'f1070000-0000-4000-8000-000000000001',
 ADD COLUMN remplacement_de_mission_id uuid;
ALTER TABLE public.factures_honoraires ADD COLUMN annee_iso integer, ADD COLUMN numero_semaine_iso integer;
CREATE TABLE public.soignants(id uuid PRIMARY KEY,mandat_facturation_signe boolean DEFAULT true,
 mandat_facturation_version text DEFAULT '1.4',statut_tva_honoraires text DEFAULT 'FRANCHISE_EN_BASE');
CREATE TABLE public.presences(mission_id uuid,valide_par_etablissement boolean,pointage_depart_le timestamptz,motif_litige text);
INSERT INTO public.soignants(id) VALUES ('f1070000-0000-4000-8000-000000000001');
-- SOURCE_FUNCTIONS_EXACTES
CREATE TRIGGER trg_anti_seed_facture_honoraire BEFORE INSERT ON public.factures_honoraires
 FOR EACH ROW EXECUTE FUNCTION public.fn_anti_seed_facture_honoraire();
CREATE TRIGGER trg_verrouiller_periode_facture_honoraires BEFORE INSERT OR UPDATE OF
 mission_id,periode_debut,periode_fin,statut,type_document,nature_correction,facture_precedente_id
 ON public.factures_honoraires FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_periode_facture_honoraires();
CREATE TRIGGER trg_no_overlap_creneaux BEFORE INSERT OR UPDATE ON public.mission_creneaux
 FOR EACH ROW EXECUTE FUNCTION public.fn_no_overlap_creneaux();
INSERT INTO public.etablissements VALUES ('f1070000-0000-4000-8000-000000000002',false);
INSERT INTO public.missions VALUES (
 'f1070000-0000-4000-8000-000000000003','2026-08-31 09:00Z','2026-09-08 17:00Z',
 20,480,480,'HEBDO_ET_FINALE','LIBERAL','f1070000-0000-4000-8000-000000000001',
 'f1070000-0000-4000-8000-000000000002',15,15,false,NULL,NULL
);
-- Trois shifts de huit heures, prévus ET effectués ; celui de nuit traverse
-- deux semaines ISO. Total physique : 24h, montant mission : 480 EUR HT.
INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
SELECT 'f1070000-0000-4000-8000-000000000003',d,f,t,false FROM (VALUES
 ('2026-08-31 09:00Z'::timestamptz,'2026-08-31 17:00Z'::timestamptz),
 ('2026-09-06 22:00Z'::timestamptz,'2026-09-07 06:00Z'::timestamptz),
 ('2026-09-08 09:00Z'::timestamptz,'2026-09-08 17:00Z'::timestamptz)
) c(d,f) CROSS JOIN (VALUES('PREVISIONNEL'),('EFFECTIF')) k(t);
CREATE TEMP TABLE observations(name text PRIMARY KEY, value jsonb);
DO $witness$
DECLARE c jsonb; a jsonb; b jsonb; first_commission jsonb; replay jsonb;
BEGIN
 a:=public.fn_calculer_montant_periode('f1070000-0000-4000-8000-000000000003','2026-08-31','2026-09-06');
 b:=public.fn_calculer_montant_periode('f1070000-0000-4000-8000-000000000003','2026-09-07','2026-09-08');
 IF (a->>'duree_totale_mission_heures')::numeric<>24 OR (b->>'duree_totale_mission_heures')::numeric<>24
  OR (a->>'duree_periode_heures')::numeric<>10 OR (b->>'duree_periode_heures')::numeric<>14
  OR (a->>'montant_ht_periode')::numeric<>200 OR (b->>'montant_ht_periode')::numeric<>280
 THEN RAISE EXCEPTION 'BOUNDARY_ALLOCATION_FAILED'; END IF;
 INSERT INTO observations VALUES('period_one',a),('period_two',b);
 -- Les deux gardes réelles doivent accepter ces insertions : période disjointe,
 -- montant conforme au calcul réel. Ce n'est pas une émission PDF/Edge complète.
 INSERT INTO public.factures_honoraires VALUES
 ('f1070001-0000-4000-8000-000000000004','BF1-S1','f1070000-0000-4000-8000-000000000003',
  'f1070000-0000-4000-8000-000000000001','f1070000-0000-4000-8000-000000000002','FACTURE','ORIGINALE','EMISE',
  '2026-08-31','2026-09-06',false,NULL,(a->>'montant_ht_periode')::numeric,(a->>'montant_ht_periode')::numeric,(a->>'duree_periode_heures')::numeric),
 ('f1070002-0000-4000-8000-000000000005','BF1-S2','f1070000-0000-4000-8000-000000000003',
  'f1070000-0000-4000-8000-000000000001','f1070000-0000-4000-8000-000000000002','FACTURE','ORIGINALE','EMISE',
  '2026-09-07','2026-09-08',true,NULL,(b->>'montant_ht_periode')::numeric,(b->>'montant_ht_periode')::numeric,(b->>'duree_periode_heures')::numeric);
 -- Témoins négatifs : les vrais triggers sont actifs et refusent leurs défauts.
 BEGIN
  INSERT INTO public.factures_honoraires SELECT
   'f1070003-0000-4000-8000-000000000006','BAD-AMOUNT',mission_id,soignant_id,etablissement_id,type_document,nature_correction,statut,
   periode_debut,periode_fin,est_facture_finale_mission,facture_precedente_id,999,999,quantite_heures_snapshot
   FROM public.factures_honoraires WHERE numero_facture='BF1-S1';
  RAISE EXCEPTION 'INVALID_AMOUNT_ACCEPTED';
 EXCEPTION WHEN check_violation THEN INSERT INTO observations VALUES('anti_seed_rejected_invalid_amount','true'); END;
 BEGIN
  INSERT INTO public.factures_honoraires SELECT
   'f1070004-0000-4000-8000-000000000007','BAD-OVERLAP',mission_id,soignant_id,etablissement_id,type_document,nature_correction,statut,
   periode_debut,periode_fin,est_facture_finale_mission,facture_precedente_id,montant_ht,montant_ttc,quantite_heures_snapshot
   FROM public.factures_honoraires WHERE numero_facture='BF1-S1';
  RAISE EXCEPTION 'OVERLAPPING_INVOICE_ACCEPTED';
 EXCEPTION WHEN exclusion_violation THEN INSERT INTO observations VALUES('period_guard_rejected_overlap','true'); END;
 first_commission:=public.fn_preparer_facture_commission_periode('f1070001-0000-4000-8000-000000000004');
 replay:=public.fn_preparer_facture_commission_periode('f1070001-0000-4000-8000-000000000004');
 IF replay->>'facture_id' IS DISTINCT FROM first_commission->>'facture_id' OR replay->>'existing'<>'true'
 THEN RAISE EXCEPTION 'COMMISSION_REPLAY_NOT_IDEMPOTENT'; END IF;
 c:=public.fn_preparer_facture_commission_periode('f1070002-0000-4000-8000-000000000005');
 IF (SELECT count(*) FROM public.factures)<>2 OR (SELECT sum(montant_ht) FROM public.factures)<>72
  OR (SELECT sum(montant_ttc) FROM public.factures)<>86.40
 THEN RAISE EXCEPTION 'COMMISSION_TOTAL_FAILED'; END IF;
 INSERT INTO observations VALUES('commission_replay_same_piece','true');
END;
$witness$;
DO $boundaries$
DECLARE mid uuid := 'f1070000-0000-4000-8000-000000000003';
  a jsonb; b jsonb; c jsonb; total numeric; cas text; ok boolean;
BEGIN
 FOREACH cas IN ARRAY ARRAY['minuit','arrondi','bases-differentes','heure-ete','heure-hiver','hors-periode','periode-invalide','sans-duree','timezone'] LOOP
  ok:=false;
  BEGIN
   DELETE FROM public.factures_honoraires WHERE mission_id=mid;
   DELETE FROM public.mission_creneaux WHERE mission_id=mid;
   IF cas IN ('minuit','hors-periode','timezone') THEN
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
      VALUES(mid,'2026-09-06 16:00Z','2026-09-07 00:00Z','PREVISIONNEL',false);
    IF cas='timezone' THEN PERFORM set_config('TimeZone','Pacific/Auckland',true); END IF;
    a:=public.fn_calculer_montant_periode(mid,'2026-08-31','2026-09-06');
    b:=public.fn_calculer_montant_periode(mid,'2026-09-07','2026-09-13');
    c:=public.fn_calculer_montant_periode(mid,'2026-08-01','2026-08-30');
    ok:=(a->>'montant_ht_periode')::numeric=480 AND (b->>'montant_ht_periode')::numeric=0
      AND (c->>'montant_ht_periode')::numeric=0;
   ELSIF cas='arrondi' THEN
    UPDATE public.missions SET net_a_payer=100 WHERE id=mid;
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
     SELECT mid,d,d+interval '1 hour','PREVISIONNEL',false
     FROM generate_series('2026-09-01 12:00Z'::timestamptz,'2026-09-03 12:00Z','1 day') d;
    a:=public.fn_calculer_montant_periode(mid,'2026-09-01','2026-09-01');
    b:=public.fn_calculer_montant_periode(mid,'2026-09-02','2026-09-02');
    c:=public.fn_calculer_montant_periode(mid,'2026-09-03','2026-09-03');
    ok:=(a->>'montant_ht_periode')::numeric=33.33 AND (b->>'montant_ht_periode')::numeric=33.34
      AND (c->>'montant_ht_periode')::numeric=33.33;
   ELSIF cas='bases-differentes' THEN
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause) VALUES
      (mid,'2026-09-01 09:00Z','2026-09-01 11:00Z','PREVISIONNEL',false),
      (mid,'2026-09-02 09:00Z','2026-09-02 12:00Z','EFFECTIF',false),
      (mid,'2026-09-02 13:00Z','2026-09-02 14:00Z','EFFECTIF',true),
      (mid,'2026-09-03 09:00Z',NULL,'EFFECTIF',false);
    a:=public.fn_calculer_montant_periode(mid,'2026-09-01','2026-09-01');
    b:=public.fn_calculer_montant_periode(mid,'2026-09-02','2026-09-03');
    c:=public.fn_calculer_montant_periode(mid);
    ok:=(a->>'montant_ht_periode')::numeric+(b->>'montant_ht_periode')::numeric=480
      AND (c->>'duree_totale_mission_heures')::numeric=3;
   ELSIF cas IN ('heure-ete','heure-hiver') THEN
    IF cas='heure-ete' THEN
     INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
      VALUES(mid,'2026-03-28 22:00 Europe/Paris','2026-03-29 06:00 Europe/Paris','EFFECTIF',false);
     a:=public.fn_calculer_montant_periode(mid,'2026-03-28','2026-03-28');
     b:=public.fn_calculer_montant_periode(mid,'2026-03-29','2026-03-29');
     total:=7;
    ELSE
     INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
      VALUES(mid,'2026-10-24 22:00 Europe/Paris','2026-10-25 06:00 Europe/Paris','EFFECTIF',false);
     a:=public.fn_calculer_montant_periode(mid,'2026-10-24','2026-10-24');
     b:=public.fn_calculer_montant_periode(mid,'2026-10-25','2026-10-25');
     total:=9;
    END IF;
    ok:=(a->>'montant_ht_periode')::numeric+(b->>'montant_ht_periode')::numeric=480
      AND (a->>'duree_periode_heures')::numeric+(b->>'duree_periode_heures')::numeric=total;
   ELSIF cas='periode-invalide' THEN
    BEGIN
     PERFORM public.fn_calculer_montant_periode(mid,'2026-09-01',NULL);
    EXCEPTION WHEN invalid_parameter_value THEN ok:=true; END;
   ELSE
    BEGIN
     PERFORM public.fn_calculer_montant_periode(mid,'2026-09-01','2026-09-02');
    EXCEPTION WHEN invalid_parameter_value THEN ok:=true; END;
   END IF;
   IF ok IS NOT TRUE THEN RAISE EXCEPTION 'PERIOD_CASE_FAILED: %',cas; END IF;
   RAISE EXCEPTION SQLSTATE 'Z1070' USING MESSAGE='ROLLBACK_SYNTHETIC_CASE';
  EXCEPTION WHEN SQLSTATE 'Z1070' THEN NULL;
  END;
  INSERT INTO observations VALUES(cas,'true');
 END LOOP;
END;
$boundaries$;
DO $evolution$
DECLARE mid uuid:='f1070000-0000-4000-8000-000000000003';
 a jsonb; b jsonb; bornes jsonb; liste jsonb; cas text; refuse boolean; ancien jsonb; correction numeric;
BEGIN
 FOREACH cas IN ARRAY ARRAY['hebdo-puis-pointage','majorations-evolutives','historique-double','historique-complement','fin-hors-planning'] LOOP
  BEGIN
   DELETE FROM public.factures_honoraires WHERE mission_id=mid;
   DELETE FROM public.mission_creneaux WHERE mission_id=mid;
   UPDATE public.missions SET debut_le='2026-08-31 09:00Z',fin_le='2026-09-08 17:00Z',
     net_a_payer=320,total_brut=320,statut='EN_COURS' WHERE id=mid;
   INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause) VALUES
     (mid,'2026-08-31 09:00Z','2026-08-31 17:00Z','PREVISIONNEL',false),
     (mid,'2026-09-08 09:00Z','2026-09-08 17:00Z','PREVISIONNEL',false),
     (mid,'2026-08-31 09:00Z','2026-08-31 17:30Z','EFFECTIF',false);
   IF cas='majorations-evolutives' THEN UPDATE public.missions SET net_a_payer=330 WHERE id=mid; END IF;
   IF cas='historique-double' THEN
    DELETE FROM public.mission_creneaux WHERE type_creneau='EFFECTIF';
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
     VALUES(mid,'2026-09-06 22:00Z','2026-09-07 06:00Z','PREVISIONNEL',false);
    UPDATE public.missions SET net_a_payer=480,total_brut=480 WHERE id=mid;
    -- BASELINE_CALCULATOR_FOR_HISTORY
   END IF;
   IF cas='historique-complement' THEN
    UPDATE public.mission_creneaux SET fin='2026-08-31 17:00Z' WHERE type_creneau='EFFECTIF';
   END IF;
   a:=public.fn_calculer_montant_periode(mid,'2026-08-31','2026-09-06');
   INSERT INTO public.factures_honoraires(id,numero_facture,mission_id,soignant_id,etablissement_id,
    type_document,nature_correction,statut,periode_debut,periode_fin,est_facture_finale_mission,
    montant_ht,montant_ttc,quantite_heures_snapshot)
   VALUES('f1070009-0000-4000-8000-000000000009','EVOLUTION-S1',mid,
    'f1070000-0000-4000-8000-000000000001','f1070000-0000-4000-8000-000000000002',
    'FACTURE','ORIGINALE','EMISE','2026-08-31','2026-09-06',false,
    (a->>'montant_ht_periode')::numeric,(a->>'montant_ht_periode')::numeric,(a->>'duree_periode_heures')::numeric);
   IF cas IN ('majorations-evolutives','historique-double','historique-complement') THEN
    UPDATE public.factures_honoraires SET statut='PAYEE' WHERE numero_facture='EVOLUTION-S1';
   END IF;
   SELECT to_jsonb(fh) INTO ancien FROM public.factures_honoraires fh WHERE numero_facture='EVOLUTION-S1';
   IF cas='historique-double' THEN
    -- CANDIDATE_CALCULATOR_AFTER_HISTORY
   ELSE
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause)
     VALUES(mid,'2026-09-08 09:00Z','2026-09-08 17:00Z','EFFECTIF',false);
    UPDATE public.missions SET net_a_payer=CASE WHEN cas='majorations-evolutives' THEN 340 ELSE 330 END,
     statut='TERMINEE' WHERE id=mid;
   END IF;
   IF cas='historique-complement' THEN
    UPDATE public.mission_creneaux SET fin='2026-08-31 17:30Z'
     WHERE type_creneau='EFFECTIF' AND debut<'2026-09-07';
   END IF;
   IF cas IN ('majorations-evolutives','historique-double','historique-complement') THEN
    refuse:=false;
    BEGIN PERFORM public.fn_calculer_montant_periode(mid,'2026-09-07','2026-09-08');
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM<>'FACTURATION_HISTORIQUE_A_RECONCILIER' THEN RAISE; END IF;
      refuse:=true;
    END;
    IF NOT refuse THEN RAISE EXCEPTION 'INCOMPATIBLE_HISTORY_ACCEPTED'; END IF;
    -- Fixtures documentaires équivalentes aux corrections du circuit existant.
    -- Le contexte de génération est celui prévu par le vrai trigger anti-seed.
    correction:=CASE cas WHEN 'historique-double' THEN -120
      WHEN 'majorations-evolutives' THEN -0.16 ELSE 10 END;
    PERFORM set_config('jolene.generate_invoice_context','true',true);
    INSERT INTO public.factures_honoraires(id,numero_facture,mission_id,soignant_id,etablissement_id,
      type_document,nature_correction,statut,periode_debut,periode_fin,est_facture_finale_mission,
      facture_precedente_id,montant_ht,montant_ttc,quantite_heures_snapshot)
    VALUES('f1070010-0000-4000-8000-000000000010','REGULARISATION-S1',mid,
      'f1070000-0000-4000-8000-000000000001','f1070000-0000-4000-8000-000000000002',
      CASE WHEN correction<0 THEN 'AVOIR' ELSE 'FACTURE' END,
      CASE WHEN correction<0 THEN 'AVOIR' ELSE 'COMPLEMENT' END,
      'EMISE','2026-08-31','2026-09-06',false,'f1070009-0000-4000-8000-000000000009',
      abs(correction),abs(correction),NULL);
    PERFORM set_config('jolene.generate_invoice_context','',true);
    b:=public.fn_calculer_montant_periode(mid,'2026-09-07','2026-09-08');
    IF (a->>'montant_ht_periode')::numeric+correction+(b->>'montant_ht_periode')::numeric
      IS DISTINCT FROM (SELECT net_a_payer FROM public.missions WHERE id=mid)
    THEN RAISE EXCEPTION 'RECONCILED_HISTORY_CANNOT_RESUME'; END IF;
   ELSE
    b:=public.fn_calculer_montant_periode(mid,'2026-09-07','2026-09-08');
    IF (a->>'montant_ht_periode')::numeric<>170 OR (b->>'montant_ht_periode')::numeric<>160
      OR (a->>'montant_ht_periode')::numeric+(b->>'montant_ht_periode')::numeric<>330
    THEN RAISE EXCEPTION 'EVOLVING_MISSION_TOTAL_LOST'; END IF;
   END IF;
   IF (SELECT to_jsonb(fh) FROM public.factures_honoraires fh WHERE numero_facture='EVOLUTION-S1') IS DISTINCT FROM ancien
    THEN RAISE EXCEPTION 'HISTORICAL_INVOICE_CHANGED'; END IF;
   IF cas='fin-hors-planning' THEN
    DELETE FROM public.factures_honoraires WHERE mission_id=mid;
    DELETE FROM public.mission_creneaux WHERE debut>='2026-09-07';
    UPDATE public.missions SET fin_le='2026-09-08 23:45Z',net_a_payer=335 WHERE id=mid;
    INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause) VALUES
     (mid,'2026-09-08 16:00Z','2026-09-08 23:45Z','PREVISIONNEL',false),
     (mid,'2026-09-08 16:00Z','2026-09-09 00:15Z','EFFECTIF',false);
    bornes:=public.fn_calculer_montant_periode(mid);
    liste:=public.fn_lister_missions_a_facturer('2026-09-10');
    IF bornes->>'borne_fin_facturation' IS DISTINCT FROM '2026-09-09'
      OR liste->'finales'->0->>'periode_fin' IS DISTINCT FROM '2026-09-09'
    THEN RAISE EXCEPTION 'EFFECTIVE_END_NOT_LISTED'; END IF;
    a:=public.fn_calculer_montant_periode(mid,'2026-08-31','2026-09-06');
    b:=public.fn_calculer_montant_periode(mid,'2026-09-07','2026-09-09');
    IF (a->>'montant_ht_periode')::numeric+(b->>'montant_ht_periode')::numeric<>335
     OR (a->>'duree_periode_heures')::numeric+(b->>'duree_periode_heures')::numeric<>16.75
    THEN RAISE EXCEPTION 'EFFECTIVE_OVERRUN_LOST'; END IF;
   END IF;
   RAISE EXCEPTION SQLSTATE 'Z1070' USING MESSAGE='ROLLBACK_SYNTHETIC_CASE';
  EXCEPTION WHEN SQLSTATE 'Z1070' THEN NULL;
  END;
  INSERT INTO observations VALUES(cas,'true');
 END LOOP;
END;
$evolution$;
SELECT jsonb_build_object('qualification','FIX_VERIFIED','sourceSha','bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84',
 'mode','PG17_ISOLE_FONCTIONS_REELLES_SCHEMA_REDUIT','providerCalled',false,'realUiExecuted',false,
 'physicalHours',24,'invoicedHours',(SELECT sum(quantite_heures_snapshot) FROM public.factures_honoraires),
 'missionHt',480,'invoicedHt',(SELECT sum(montant_ht) FROM public.factures_honoraires),
 'commissionHt',(SELECT sum(montant_ht) FROM public.factures),'commissionTtc',(SELECT sum(montant_ttc) FROM public.factures),
 'honoraires',(SELECT jsonb_agg(to_jsonb(f) ORDER BY periode_debut) FROM public.factures_honoraires f),
 'commissions',(SELECT jsonb_agg(to_jsonb(f) ORDER BY periode_debut) FROM public.factures f),
 'invoiceCount',(SELECT count(*) FROM public.factures_honoraires),'commissionCount',(SELECT count(*) FROM public.factures),
 'routineBodyMd5',(SELECT jsonb_object_agg(proname,md5(prosrc)) FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname IN ('fn_calculer_montant_periode',
   'fn_anti_seed_facture_honoraire','fn_verrouiller_periode_facture_honoraires',
   'fn_no_overlap_creneaux','fn_preparer_facture_commission_periode','fn_lister_missions_a_facturer')),
 'cases',(SELECT jsonb_object_agg(name,value) FROM observations));
ROLLBACK;
