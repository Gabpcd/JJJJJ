-- Gardes du format fournisseur uniquement ; la recette staging vérifie aussi
-- le rapprochement du vrai remboursement SEPA Stripe TEST. Tout est annulé.
BEGIN;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
DO $formats$
DECLARE candidate text; blocked boolean;
BEGIN
  FOREACH candidate IN ARRAY ARRAY['re_CardRefund123','pyr_SepaRefund123'] LOOP
    blocked:=false;
    BEGIN PERFORM public.fn_stripe_refund_rapprocher(gen_random_uuid(),candidate,'SUCCEEDED');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM <> 'Queue refund introuvable' THEN RAISE; END IF;
      blocked:=true;
    END;
    IF NOT blocked THEN RAISE EXCEPTION 'Queue inexistante acceptée'; END IF;
  END LOOP;
  FOREACH candidate IN ARRAY ARRAY[NULL,'','re_','pyr_','pi_123','pyr_123/456',' re_123','re_123 '] LOOP
    blocked:=false;
    BEGIN PERFORM public.fn_stripe_refund_rapprocher(gen_random_uuid(),candidate,'SUCCEEDED');
    EXCEPTION WHEN invalid_parameter_value THEN blocked:=true; END;
    IF NOT blocked THEN RAISE EXCEPTION 'Identifiant invalide accepté'; END IF;
  END LOOP;
END $formats$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $acl$
DECLARE blocked boolean:=false;
BEGIN
  BEGIN PERFORM public.fn_stripe_refund_rapprocher(gen_random_uuid(),'pyr_SepaRefund123','SUCCEEDED');
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'Rapprochement accessible à un utilisateur'; END IF;
END $acl$;
RESET ROLE;
ROLLBACK;
