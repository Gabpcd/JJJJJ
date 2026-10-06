-- Schéma réduit et données synthétiques. Fonctions métier injectées par le
-- runner depuis git show bf1 ; aucun calcul métier n'est remplacé par un double.
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'UTC';
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
  OR (a->>'duree_periode_heures')::numeric<>16 OR (b->>'duree_periode_heures')::numeric<>16
  OR (a->>'montant_ht_periode')::numeric<>320 OR (b->>'montant_ht_periode')::numeric<>320
 THEN RAISE EXCEPTION 'BF1_BOUNDARY_COUNTEREXAMPLE_NOT_REPRODUCED'; END IF;
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
 IF (SELECT count(*) FROM public.factures)<>2 OR (SELECT sum(montant_ht) FROM public.factures)<>96
  OR (SELECT sum(montant_ttc) FROM public.factures)<>115.20
 THEN RAISE EXCEPTION 'COMMISSION_COUNTEREXAMPLE_NOT_REPRODUCED'; END IF;
 INSERT INTO observations VALUES('commission_replay_same_piece','true');
END;
$witness$;
SELECT jsonb_build_object('qualification','BUG_REPRODUCED','sourceSha','bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84',
 'mode','PG17_ISOLE_FONCTIONS_REELLES_SCHEMA_REDUIT','providerCalled',false,'realUiExecuted',false,
 'physicalHours',24,'invoicedHours',(SELECT sum(quantite_heures_snapshot) FROM public.factures_honoraires),
 'missionHt',480,'invoicedHt',(SELECT sum(montant_ht) FROM public.factures_honoraires),
 'commissionHt',(SELECT sum(montant_ht) FROM public.factures),'commissionTtc',(SELECT sum(montant_ttc) FROM public.factures),
 'invoiceCount',(SELECT count(*) FROM public.factures_honoraires),'commissionCount',(SELECT count(*) FROM public.factures),
 'routineBodyMd5',(SELECT jsonb_object_agg(proname,md5(prosrc)) FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname IN ('fn_calculer_montant_periode',
   'fn_anti_seed_facture_honoraire','fn_verrouiller_periode_facture_honoraires',
   'fn_no_overlap_creneaux','fn_preparer_facture_commission_periode')),
 'cases',(SELECT jsonb_object_agg(name,value) FROM observations));
ROLLBACK;
