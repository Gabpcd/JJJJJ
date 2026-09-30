-- Régression réelle du BEFORE INSERT sur public.factures, contraintes actives.
-- Aucun workflow d'émission, paiement, fournisseur, mission ou contrat exécuté.
-- Le sous-bloc sentinelle protège aussi le runner CI qui retire BEGIN/ROLLBACK.
BEGIN;
DO $recette$
DECLARE
  v_etab uuid := 'a9305902-0000-4000-8000-000000000001';
  v_mois text := to_char(now(),'YYYYMM');
  v_annee text := to_char(now(),'YYYY');
  v_base numeric;
  v_numero text;
  v_contrainte text;
  v_n integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p
    JOIN pg_trigger t ON t.tgfoid=p.oid
    WHERE p.oid='public.dec_verifier_numerotation_facture()'::regprocedure
      AND md5(p.prosrc)='28e45c95fead8a886f594f163a67961a'
      AND NOT p.prosecdef
      AND p.proacl='{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
      AND t.tgrelid='public.factures'::regclass AND t.tgname='dec_num_facture'
      AND t.tgtype=7 AND t.tgenabled='O') THEN
    RAISE EXCEPTION 'Trigger de numérotation ou droits divergents';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=v_etab)
    OR EXISTS (SELECT 1 FROM public.etablissements WHERE id=v_etab)
    OR EXISTS (SELECT 1 FROM public.factures WHERE etablissement_id=v_etab) THEN
    RAISE EXCEPTION 'Identité synthétique déjà présente';
  END IF;

  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES(v_etab,'00000000-0000-0000-0000-000000000000',
      'numerotation-rollback@example.invalid','authenticated','authenticated',
      '{"role":"ADMIN_ETABLISSEMENT","is_test_playwright":true}',now());
    INSERT INTO public.preferences_notifications
      (utilisateur_id,canal_email,canal_sms,canal_push,canal_in_app)
    VALUES(v_etab,false,false,false,false);
    INSERT INTO public.etablissements
      (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
       est_compte_test,code_parrainage,source_acquisition)
    VALUES(v_etab,'Recette numérotation','99305902000001','CLINIQUE_PRIVEE',
      'Test','Paris','75001','numerotation-rollback@example.invalid',true,
      'NUMEROTATION-ROLLBACK','TEST');

    -- Aucune ligne préexistante modifiée. Le maximum n'est jamais restitué.
    SELECT coalesce(max(split_part(numero_facture,'-',3)::numeric),0)+1 INTO v_base
    FROM public.factures
    WHERE numero_facture ~ ('^(SD|JOL)-'||v_mois||'-[0-9]+$');
    INSERT INTO public.factures(etablissement_id,numero_facture,montant_ht,montant_tva,montant_ttc,statut,cree_le)
    VALUES(v_etab,'SD-'||v_mois||'-'||v_base,10,2,12,'BROUILLON',now()+interval '1 minute');

    -- Ce SD du mois rendait chacune des insertions H/HC/HR impossible (22P02).
    FOREACH v_numero IN ARRAY ARRAY[
      'JOL-'||v_annee||'-H-A930590201',
      'JOL-'||v_annee||'-HC-A930590202',
      'JOL-'||v_annee||'-HR-A930590203',
      'AVC-'||to_char(now(),'YYYY-MM')||'-9305902',
      'FC-'||to_char(now(),'YYYY-MM')||'-9305902',
      'JOL-'||v_annee||'-9305902',
      'FACT-STRIPE-'||to_char(now(),'YYYY-MM-DD')||'-a9305902'
    ] LOOP
      INSERT INTO public.factures(etablissement_id,numero_facture,montant_ht,montant_tva,montant_ttc,statut)
      VALUES(v_etab,v_numero,10,2,12,'BROUILLON');
      v_n:=v_n+1;
    END LOOP;

    -- Suite mensuelle comparable, puis saut volontaire : reste un WARNING,
    -- pas une exception ni un renumérotage. La contrainte UNIQUE reste l'arbitre.
    INSERT INTO public.factures(etablissement_id,numero_facture,montant_ht,montant_tva,montant_ttc,statut,cree_le)
    VALUES(v_etab,'JOL-'||v_mois||'-'||(v_base+1),10,2,12,'BROUILLON',now()+interval '2 minutes'),
      (v_etab,'SD-'||v_mois||'-'||(v_base+3),10,2,12,'BROUILLON',now()+interval '3 minutes');
    BEGIN
      INSERT INTO public.factures(etablissement_id,numero_facture,montant_ht,montant_tva,montant_ttc,statut)
      VALUES(v_etab,'JOL-'||v_annee||'-H-A930590201',10,2,12,'BROUILLON');
      RAISE EXCEPTION 'Doublon de numéro accepté';
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_contrainte=CONSTRAINT_NAME;
      IF v_contrainte IS DISTINCT FROM 'factures_numero_facture_key' THEN
        RAISE EXCEPTION 'Le doublon a été refusé pour une autre contrainte';
      END IF;
    END;
    IF v_n<>7 OR (SELECT count(*) FROM public.factures WHERE etablissement_id=v_etab)<>10
      OR NOT EXISTS (SELECT 1 FROM public.factures WHERE etablissement_id=v_etab
        AND numero_facture='SD-'||v_mois||'-'||(v_base+3))
      OR EXISTS (SELECT 1 FROM public.factures WHERE etablissement_id=v_etab
        AND (statut IS DISTINCT FROM 'BROUILLON' OR montant_ttc IS DISTINCT FROM 12)) THEN
      RAISE EXCEPTION 'Factures de recette manquantes ou altérées';
    END IF;
    RAISE EXCEPTION USING ERRCODE='ZN001', MESSAGE='ROLLBACK_NUMEROTATION_OK';
  EXCEPTION WHEN SQLSTATE 'ZN001' THEN
    IF SQLERRM<>'ROLLBACK_NUMEROTATION_OK' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=v_etab)
    OR EXISTS (SELECT 1 FROM public.etablissements WHERE id=v_etab)
    OR EXISTS (SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id=v_etab)
    OR EXISTS (SELECT 1 FROM public.factures WHERE etablissement_id=v_etab) THEN
    RAISE EXCEPTION 'Résidu après sentinelle de rollback';
  END IF;
END;
$recette$;
ROLLBACK;
