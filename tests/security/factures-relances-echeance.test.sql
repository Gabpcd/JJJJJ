-- Exécuter sur staging isolé, sous ROLLBACK. Aucun transport fournisseur.
BEGIN;
DO $recette$
DECLARE
  e uuid := 'a0161000-0000-4000-8000-000000000001';
  f_future uuid := 'a0161000-0000-4000-8000-000000000011';
  f_j7 uuid := 'a0161000-0000-4000-8000-000000000012';
  f_j21 uuid := 'a0161000-0000-4000-8000-000000000013';
  f_date_emission_nulle uuid := 'a0161000-0000-4000-8000-000000000014';
  f_dates_nulles uuid := 'a0161000-0000-4000-8000-000000000015';
  n integer;
  resultat jsonb;
  seuil integer := public.fn_param_num('seuil_blocage_retard_j',45)::integer;
  aujourd_hui date := (now() AT TIME ZONE 'Europe/Paris')::date;
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=e) THEN RAISE EXCEPTION 'Fixture déjà présente'; END IF;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES(e,'00000000-0000-0000-0000-000000000000','echeance-rollback@example.invalid',
      'authenticated','authenticated','{"role":"ADMIN_ETABLISSEMENT","is_test_playwright":true}',now());
    INSERT INTO public.preferences_notifications(utilisateur_id,canal_email,canal_sms,canal_push,canal_in_app)
    VALUES(e,false,false,false,false) ON CONFLICT(utilisateur_id) DO UPDATE
      SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false;
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,
      email_contact,est_compte_test,code_parrainage,source_acquisition,statut_verification,
      siret_verifie,finess_verifie,representant_identite_verifiee,rattachement_verifie,contrat_service_signe)
    VALUES(e,'Recette échéances','99301610000001','CLINIQUE_PRIVEE','Test','Paris','75001',
      'echeance-rollback@example.invalid',true,'ECHEANCE-ROLLBACK','TEST','VERIFIE',true,true,true,true,true);
    INSERT INTO public.factures(id,etablissement_id,numero_facture,montant_ht,montant_tva,montant_ttc,
      statut,date_emission,date_echeance)
    VALUES
      (f_future,e,'JOL-'||to_char(now(),'YYYY')||'-H-A016100011',10,2,12,'EMISE',now()-interval '60 days',aujourd_hui+5),
      (f_j7,e,'JOL-'||to_char(now(),'YYYY')||'-H-A016100012',10,2,12,'EMISE',now()-interval '60 days',aujourd_hui-7),
      (f_j21,e,'JOL-'||to_char(now(),'YYYY')||'-H-A016100013',10,2,12,'EMISE',now()-interval '60 days',aujourd_hui-21),
      (f_date_emission_nulle,e,'JOL-'||to_char(now(),'YYYY')||'-H-A016100014',10,2,12,'EMISE',NULL,aujourd_hui-7),
      (f_dates_nulles,e,'JOL-'||to_char(now(),'YYYY')||'-H-A016100015',10,2,12,'EMISE',NULL,NULL);

    PERFORM public.fn_alerter_paiements_retard();
    IF EXISTS(SELECT 1 FROM public.factures WHERE id=f_future AND (relance_1_le IS NOT NULL OR relance_2_le IS NOT NULL)) THEN
      RAISE EXCEPTION 'Relance envoyée avant échéance malgré émission ancienne';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id=f_j7 AND relance_1_le IS NOT NULL AND relance_2_le IS NULL)
      OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=f_j21 AND relance_1_le IS NOT NULL AND relance_2_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Seuils J+7/J+21 après échéance non respectés';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id=f_date_emission_nulle AND relance_1_le IS NOT NULL AND relance_2_le IS NULL)
      OR EXISTS(SELECT 1 FROM public.factures WHERE id=f_dates_nulles AND (relance_1_le IS NOT NULL OR relance_2_le IS NOT NULL)) THEN
      RAISE EXCEPTION 'Dates nulles : une échéance connue doit être suivie, une date absente ne doit pas être inventée';
    END IF;
    SELECT count(*) INTO n FROM public.email_queue WHERE destinataire_id=e AND type IN ('RAPPEL_PAIEMENT_J7','PAIEMENT_RETARD_J21');
    IF n<>4 THEN RAISE EXCEPTION 'Quatre relances attendues : %',n; END IF;
    IF EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id=e AND type IN ('RAPPEL_PAIEMENT_J7','PAIEMENT_RETARD_J21') AND NOT(data ? 'date_echeance')) THEN
      RAISE EXCEPTION 'Échéance absente du rappel';
    END IF;
    PERFORM public.fn_alerter_paiements_retard();
    IF (SELECT count(*) FROM public.email_queue WHERE destinataire_id=e AND type IN ('RAPPEL_PAIEMENT_J7','PAIEMENT_RETARD_J21'))<>n THEN
      RAISE EXCEPTION 'Relance dupliquée au rejeu';
    END IF;

    -- Toutes les factures sont émises depuis >45j, mais aucune n'est en retard de 45j.
    UPDATE public.etablissements SET bloque_auto_le=now(),bloque_auto_raisons='{}' WHERE id=e;
    PERFORM public.fn_gerer_blocage_etabs();
    IF EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND bloque_auto_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Blocage conservé à partir de la seule émission';
    END IF;
    -- Même décision par la revérification déclenchée depuis l'espace établissement.
    UPDATE public.etablissements SET bloque_auto_le=now(),bloque_auto_raisons='{}' WHERE id=e;
    PERFORM set_config('request.jwt.claim.sub',e::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',e)::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    resultat:=public.fn_reverifier_blocage_etab();
    IF resultat->>'debloque' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Revérification ne débloque pas'; END IF;
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    PERFORM set_config('request.jwt.claim.sub','',true);
    -- Positif : la facture est effectivement au-delà du seuil après son échéance.
    -- État de qualification fictif posé à l'INSERT dans cette transaction annulée.
    -- Aucun vérificateur externe ni contournement de trigger n'est utilisé.
    UPDATE public.factures SET date_echeance=aujourd_hui-seuil-1 WHERE id=f_j21;
    PERFORM public.fn_gerer_blocage_etabs();
    IF NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND bloque_auto_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Retard supérieur au seuil non bloqué';
    END IF;
    PERFORM set_config('request.jwt.claim.sub',e::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',e)::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    resultat:=public.fn_reverifier_blocage_etab();
    IF resultat->>'debloque' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Revérification libère un impayé'; END IF;
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    PERFORM set_config('request.jwt.claim.sub','',true);
    -- Historique sans échéance : trente jours sont ajoutés à l'émission.
    UPDATE public.factures SET date_echeance=NULL,date_emission=now()-interval '10 days' WHERE id=f_j21;
    PERFORM public.fn_gerer_blocage_etabs();
    IF EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND bloque_auto_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Échéance historique future ne débloque pas';
    END IF;
    UPDATE public.factures SET date_emission=now()-make_interval(days=>seuil+31) WHERE id=f_j21;
    PERFORM public.fn_gerer_blocage_etabs();
    IF NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND bloque_auto_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Échéance historique dépassée ne bloque pas';
    END IF;
    RAISE EXCEPTION USING ERRCODE='ZT016', MESSAGE='ROLLBACK_ECHEANCES_OK';
  EXCEPTION WHEN SQLSTATE 'ZT016' THEN
    IF SQLERRM<>'ROLLBACK_ECHEANCES_OK' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.factures WHERE etablissement_id=e) OR EXISTS(SELECT 1 FROM auth.users WHERE id=e) THEN
    RAISE EXCEPTION 'Résidu de recette';
  END IF;
END;
$recette$;
ROLLBACK;
