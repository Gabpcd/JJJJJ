-- Témoin négatif historique v5, uniquement PG17 éphémère sous ROLLBACK.
-- Jamais chargé par la migration produit.
CREATE FUNCTION public.fn_connect_remboursement_constater(p_operation_id uuid,p_owner_token uuid,p_refund jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; st text; a jsonb; touched integer; incident text; retour text;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 st:=upper(p_refund->>'status');
 IF o.orientation IS DISTINCT FROM 'REFUND' OR o.first_attempt_at IS NULL OR p_owner_token IS NULL OR o.owner_token IS DISTINCT FROM p_owner_token
   OR o.lease_until IS NULL OR o.lease_until<=clock_timestamp() OR COALESCE(p_refund->>'id','')!~'^re_[A-Za-z0-9_]+$'
   OR (o.refund_id IS NOT NULL AND o.refund_id IS DISTINCT FROM p_refund->>'id')
   OR p_refund->>'payment_intent_id' IS DISTINCT FROM o.payment_intent_id OR p_refund->>'charge_id' IS DISTINCT FROM o.charge_id
   OR p_refund->>'currency' IS DISTINCT FROM 'eur' OR (p_refund->>'amount')::bigint IS DISTINCT FROM o.total_cents
   OR st IS NULL OR st NOT IN('PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED')
 THEN RAISE EXCEPTION 'CONNECT_REFUND_RECEIPT'; END IF;
 IF o.refund_status='REVIEW' THEN
   UPDATE private.stripe_connect_avant_transfert SET owner_token=NULL,lease_until=NULL WHERE id=o.id;
   RETURN jsonb_build_object('operation_id',o.id,'refund_id',o.refund_id,'status','REVIEW','review_code',o.review_code);
 END IF;
 IF o.refund_status='SUCCEEDED' AND st='PENDING' THEN st:='SUCCEEDED'; END IF;
 IF o.refund_status='SUCCEEDED' AND st IN('FAILED','CANCELED','REQUIRES_ACTION') THEN
   retour:=p_refund->>'failure_balance_transaction_id';
   IF st IN('FAILED','CANCELED') AND COALESCE(retour,'')!~'^txn_[A-Za-z0-9_]+$' THEN RAISE EXCEPTION 'CONNECT_REFUND_RETURN_NOT_PROVEN'; END IF;
   incident:=CASE WHEN st='REQUIRES_ACTION' THEN 'REFUND_REQUIRES_ACTION_AFTER_SUCCESS' ELSE 'REFUND_RETURNED_AFTER_SUCCESS' END;
   st:='REVIEW';
 END IF;
 UPDATE private.stripe_connect_avant_transfert SET refund_id=p_refund->>'id',refund_status=st WHERE id=o.id;
 IF st='SUCCEEDED' AND o.refund_status<>'SUCCEEDED' THEN
   UPDATE public.stripe_transfers SET statut='REMBOURSE',erreur='Paiement remboursé avant transfert après ouverture d’un litige'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL AND statut IN('EN_ATTENTE','ECHOUE','CHARGE_REUSSI');
   GET DIAGNOSTICS touched=ROW_COUNT;
   IF touched<>1 THEN RAISE EXCEPTION 'CONNECT_REFUND_TRACE_NOT_FINALIZED'; END IF;
   a:=public.fn_ecrire_audit_safe(o.etablissement_id,'SYSTEME','ADMIN_ACTION','factures_honoraires',o.facture_honoraire_id,NULL,
     jsonb_build_object('evenement','CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE','operation_id',o.id,'litige_id',o.litige_id,
       'stripe_session_id',o.session_id,'stripe_payment_intent_id',o.payment_intent_id,'stripe_refund_id',p_refund->>'id'),NULL,'connect-pretransfer');
   IF (a->>'success')::boolean IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'CONNECT_REFUND_AUDIT_FAILED'; END IF;
 END IF;
 IF st IN('FAILED','CANCELED','REVIEW') AND o.refund_status IS DISTINCT FROM st THEN
   UPDATE public.stripe_transfers SET statut='ECHOUE',erreur='Le remboursement requiert un rapprochement ; aucun nouveau transfert autorisé'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL AND statut IN('EN_ATTENTE','CHARGE_REUSSI','REMBOURSE','ECHOUE');
   GET DIAGNOSTICS touched=ROW_COUNT;
   IF touched<>1 THEN RAISE EXCEPTION 'CONNECT_REFUND_FAILURE_NOT_RECORDED'; END IF;
   a:=public.fn_ecrire_audit_safe(o.etablissement_id,'SYSTEME','ADMIN_ACTION','factures_honoraires',o.facture_honoraire_id,NULL,
     jsonb_build_object('evenement','CONNECT_REMBOURSEMENT_INCIDENT','operation_id',o.id,'stripe_refund_id',p_refund->>'id',
       'statut_courant',p_refund->>'status','incident',COALESCE(incident,'REFUND_'||st),'failure_balance_transaction_id',retour),NULL,'connect-pretransfer');
   IF (a->>'success')::boolean IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'CONNECT_REFUND_AUDIT_FAILED'; END IF;
 END IF;
 UPDATE private.stripe_connect_avant_transfert SET refund_id=p_refund->>'id',refund_status=st,
   succeeded_at=CASE WHEN st='SUCCEEDED' THEN COALESCE(succeeded_at,clock_timestamp()) ELSE succeeded_at END,
   failure_balance_transaction_id=COALESCE(failure_balance_transaction_id,retour),
   review_code=CASE WHEN incident IS NOT NULL THEN incident WHEN st='FAILED' THEN 'REFUND_FAILED' WHEN st='CANCELED' THEN 'REFUND_CANCELED' ELSE review_code END,
   owner_token=NULL,lease_until=NULL,next_read_at=clock_timestamp()+CASE WHEN st='SUCCEEDED' THEN interval '1 hour' ELSE interval '5 minutes' END
 WHERE id=o.id;
 RETURN jsonb_build_object('operation_id',o.id,'refund_id',p_refund->>'id','status',st,'review_code',COALESCE(incident,o.review_code));
END;$f$;
