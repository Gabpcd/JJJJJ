-- Écritures d'audit réelles, toutes annulées ; aucun appel Stripe.
BEGIN;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
DO $service_json$
DECLARE r jsonb; a text;
BEGIN
  FOREACH a IN ARRAY ARRAY['FINANCE_CHARGE_PENDING','FINANCE_TRANSFER_CREATED'] LOOP
    r:=public.fn_ecrire_audit_safe('00000000-0000-0000-0000-000000000000','SYSTEME',a,'recette',NULL,NULL,'{"test":"jwt_audit"}',NULL,'stripe-webhook');
    IF (r->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'Audit service JSON refusé : %',r; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.journaux_audit WHERE id=(r->>'id')::uuid
      AND acteur_id='00000000-0000-0000-0000-000000000000' AND action=a AND type_acteur='SYSTEME')
    THEN RAISE EXCEPTION 'Audit fournisseur non persisté'; END IF;
  END LOOP;
END $service_json$;
-- Le service atteint les gardes métier des payouts ; l'identité inexistante
-- reste rejetée. Ces sondes ne simulent aucun virement bancaire.
DO $payout_json$
DECLARE blocked boolean;
BEGIN
  IF public.fn_stripe_lier_payout_transfers('po_recette_jwt',gen_random_uuid(),ARRAY[]::text[])<>0
  THEN RAISE EXCEPTION 'Liaison vide incorrecte'; END IF;
  blocked:=false;
  BEGIN PERFORM public.fn_escrow_confirmer_payout(gen_random_uuid(),'po_recette_jwt','acct_recette');
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'Payout escrow incohérent' THEN RAISE; END IF;
    blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Payout inconnu confirmé'; END IF;
  blocked:=false;
  BEGIN PERFORM public.fn_escrow_echouer_payout(gen_random_uuid(),'po_recette_jwt','acct_recette','Recette');
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'Payout escrow incohérent' THEN RAISE; END IF;
    blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Payout inconnu modifié'; END IF;
END $payout_json$;
RESET ROLE;
-- Le JWT authenticated doit prévaloir sur un ancien GUC privilégié. L'acteur
-- passé par l'appelant est remplacé par le sub signé, même si metadata ment.
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"56c5cad3-9725-4b10-a768-6c0d5e6250f1","user_metadata":{"role":"service_role"}}',true);
SET LOCAL ROLE authenticated;
DO $acteur_lie$
DECLARE r jsonb;
BEGIN
  r:=public.fn_ecrire_audit_safe('00000000-0000-0000-0000-000000000000','SOIGNANT','MODIFICATION_PROFIL','recette',NULL);
  IF (r->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'Audit utilisateur refusé : %',r; END IF;
  PERFORM set_config('recette.audit_id',r->>'id',true);
END $acteur_lie$;
RESET ROLE;
DO $verifier_acteur$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.journaux_audit WHERE id=current_setting('recette.audit_id')::uuid
    AND acteur_id='56c5cad3-9725-4b10-a768-6c0d5e6250f1')
  THEN RAISE EXCEPTION 'Usurpation de l acteur via paramètre ou rôle legacy'; END IF;
END $verifier_acteur$;
-- EXECUTE accordé au rôle SQL service_role : le refus doit venir du contrôle
-- interne, sans confondre cette preuve avec une simple protection ACL.
SELECT set_config('request.jwt.claims','{"role":"authenticated","user_metadata":{"role":"service_role"}}',true);
SET LOCAL ROLE service_role;
DO $refus_sans_identite$
DECLARE r jsonb;
BEGIN
  r:=public.fn_ecrire_audit_safe(NULL,'SYSTEME','FINANCE_CHARGE_PENDING','recette',NULL);
  IF (r->>'success')::boolean IS DISTINCT FROM false OR r->>'error' IS DISTINCT FROM 'Non authentifié'
  THEN RAISE EXCEPTION 'Rôle legacy ou metadata a contourné le JWT : %',r; END IF;
END $refus_sans_identite$;
DO $refus_payout$
DECLARE blocked boolean;
BEGIN
  blocked:=false;
  BEGIN PERFORM public.fn_stripe_lier_payout_transfers('po_recette_jwt',gen_random_uuid(),ARRAY[]::text[]);
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Liaison payout ouverte au JWT utilisateur'; END IF;
  blocked:=false;
  BEGIN PERFORM public.fn_escrow_confirmer_payout(gen_random_uuid(),'po_recette_jwt','acct_recette');
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Confirmation payout ouverte au JWT utilisateur'; END IF;
  blocked:=false;
  BEGIN PERFORM public.fn_escrow_echouer_payout(gen_random_uuid(),'po_recette_jwt','acct_recette','Recette');
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Échec payout ouvert au JWT utilisateur'; END IF;
END $refus_payout$;
RESET ROLE;
SELECT set_config('request.jwt.claim.role','',true);
SELECT set_config('request.jwt.claims','{"role":"anon"}',true);
SET LOCAL ROLE service_role;
DO $refus_anon$
DECLARE r jsonb;
BEGIN
  r:=public.fn_ecrire_audit_safe(NULL,'SYSTEME','FINANCE_CHARGE_PENDING','recette',NULL);
  IF (r->>'success')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'Audit anonyme accepté'; END IF;
END $refus_anon$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{}',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SET LOCAL ROLE service_role;
DO $compatibilite$
DECLARE r jsonb;
BEGIN
  r:=public.fn_ecrire_audit_safe(NULL,'SYSTEME','FINANCE_TRANSFER_CREATED','recette',NULL);
  IF (r->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'Ancien appel service refusé'; END IF;
  r:=public.fn_ecrire_audit_safe(NULL,'SYSTEME','ACTION_INVALIDE_RECETTE','recette',NULL);
  IF (r->>'success')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'Faux succès sur audit invalide'; END IF;
END $compatibilite$;
RESET ROLE;
ROLLBACK;
