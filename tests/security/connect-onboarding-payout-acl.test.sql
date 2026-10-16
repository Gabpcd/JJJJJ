-- PostgreSQL éphémère de CI, aucune API fournisseur. La transaction rend
-- les privilèges et toutes les fixtures à leur état initial.
BEGIN;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES('98400000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000',
 'connect-onboarding-fixture@example.invalid','authenticated','authenticated',
 '{"role":"SOIGNANT","is_test_playwright":true}',now());
INSERT INTO public.soignants(id,prenom,nom,email,profession,est_compte_test,type_exercice,date_naissance,source_acquisition,
  sms_actif,sms_alertes_actives,defacto_opt_in,identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
VALUES('98400000-0000-4000-8000-000000000003','Fixture','Connect',
 'connect-onboarding-fixture@example.invalid','IDE',true,'LIBERAL','1990-01-01','RECETTE_SQL_CONNECT',
 false,false,false,false,false,false,false);

DO $acl$
DECLARE op text; f regprocedure;
BEGIN
  FOREACH op IN ARRAY ARRAY['INSERT','UPDATE','DELETE'] LOOP
    IF has_table_privilege('authenticated','public.stripe_connect_onboarding',op)
      OR has_table_privilege('anon','public.stripe_connect_onboarding',op) THEN
      RAISE EXCEPTION 'Écriture client Connect encore autorisée : %',op;
    END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated','public.stripe_connect_onboarding','SELECT') THEN
    RAISE EXCEPTION 'Lecture client Connect supprimée'; END IF;
  FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
    ('fn_connect_payouts_a_traiter','fn_connect_payout_prendre','fn_connect_payout_demarrer',
     'fn_connect_payout_reessayer','fn_connect_payout_constater','fn_connect_payout_est_connu','fn_connect_payout_reporter') LOOP
    IF has_function_privilege('authenticated',f,'EXECUTE') OR has_function_privilege('anon',f,'EXECUTE')
      OR NOT has_function_privilege('service_role',f,'EXECUTE') THEN RAISE EXCEPTION 'ACL payout incorrecte : %',f; END IF;
  END LOOP;
END;$acl$;

-- Le vrai rôle SQL authenticated ne peut pas forger sa première référence.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000003"}',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $client_refuse$
BEGIN
  BEGIN
    INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut,onboarding_complete,charges_enabled,payouts_enabled)
    VALUES('98400000-0000-4000-8000-000000000003','acct_forged','COMPLET',true,true,true);
    RAISE EXCEPTION 'Premier INSERT client autorisé';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.fn_connect_payout_prendre('98400000-0000-4000-8000-000000000001','98400000-0000-4000-8000-000000000090');
    RAISE EXCEPTION 'Lease payout client autorisé';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;$client_refuse$;
RESET ROLE;

-- Défense supplémentaire : même une future réintroduction accidentelle du
-- GRANT/policy INSERT ne permet pas de contourner le trigger serveur.
GRANT INSERT ON public.stripe_connect_onboarding TO authenticated;
CREATE POLICY fixture_connect_insert ON public.stripe_connect_onboarding FOR INSERT TO authenticated
WITH CHECK(soignant_id=auth.uid());
SET LOCAL ROLE authenticated;
DO $trigger_refuse$
BEGIN
  BEGIN
    INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut)
    VALUES('98400000-0000-4000-8000-000000000003','acct_forged','COMPLET');
    RAISE EXCEPTION 'Défense trigger premier INSERT absente';
  EXCEPTION WHEN insufficient_privilege THEN
    IF SQLERRM<>'CONNECT_ONBOARDING_SERVER_REQUIRED' THEN RAISE; END IF;
  END;
END;$trigger_refuse$;
RESET ROLE;

-- Les vrais writers serveur (onboard/account.updated) restent autorisés.
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SET LOCAL ROLE service_role;
INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut)
VALUES('98400000-0000-4000-8000-000000000003','acct_server','EN_COURS');
UPDATE public.stripe_connect_onboarding SET statut='COMPLET',onboarding_complete=true,charges_enabled=true,payouts_enabled=true
WHERE soignant_id='98400000-0000-4000-8000-000000000003';
RESET ROLE;
DO $serveur$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE soignant_id='98400000-0000-4000-8000-000000000003'
    AND stripe_account_id='acct_server' AND statut='COMPLET') THEN RAISE EXCEPTION 'Writer serveur cassé'; END IF;
END;$serveur$;
ROLLBACK;
