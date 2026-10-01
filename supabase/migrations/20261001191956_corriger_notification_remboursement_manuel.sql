-- Source LIVE prod/staging identique, contrôlée le 1 octobre 2026.
-- Corrige uniquement les futures notifications. Aucun paiement, ancienne action,
-- ancienne notification, trigger, destinataire ou privilège n'est modifié.
-- REMBOURSEMENT_AVOIR_SWAN était refusé par le worker : ne plus créer cette tâche.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO STRICT p FROM pg_proc WHERE oid='public.fn_trg_notif_admin_remboursement_manuel()'::regprocedure;
  IF (md5(p.prosrc),md5(pg_get_functiondef(p.oid))) NOT IN
    (('082194c068b4978307c318a7d40caa3c','ad38ca7df98815b9996e60d9593f81c0'),('5b2f553588a1c2d6ae7ef0a7dbded12f','03f2fff285767ce417352bfb62ef5584'))
    OR pg_get_userbyid(p.proowner) <> 'postgres'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
    OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature IN
      ('fn_trg_notif_admin_remboursement_manuel()','public.fn_trg_notif_admin_remboursement_manuel()'))
    OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.factures_honoraires'::regclass
      AND t.tgname='trg_notif_admin_remboursement_manuel' AND t.tgenabled='O'
      AND pg_get_triggerdef(t.oid)='CREATE TRIGGER trg_notif_admin_remboursement_manuel AFTER INSERT OR UPDATE OF mode_remboursement, type_document ON public.factures_honoraires FOR EACH ROW EXECUTE FUNCTION fn_trg_notif_admin_remboursement_manuel()')

  THEN RAISE EXCEPTION 'Notification avoir : définition, droits ou déclencheur inattendus'; END IF;
  SELECT * INTO STRICT p FROM pg_proc WHERE oid='public.fn_list_admin_user_ids()'::regprocedure;
  IF md5(p.prosrc)<>'e906ed6475c6d01f125d125e734988bf'
    OR md5(pg_get_functiondef(p.oid))<>'e2525859fa4f203e559a6a22341826c0'
    OR pg_get_userbyid(p.proowner)<>'postgres' OR p.prosecdef IS DISTINCT FROM true OR p.provolatile<>'s'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, auth']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
  THEN RAISE EXCEPTION 'Notification avoir : sélection des administrateurs inattendue'; END IF;

END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_trg_notif_admin_remboursement_manuel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_montant NUMERIC;
BEGIN
  IF NEW.type_document <> 'AVOIR' OR NEW.mode_remboursement <> 'VIREMENT_MANUEL'
     OR NEW.date_remboursement IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.mode_remboursement = 'VIREMENT_MANUEL'
     AND OLD.type_document = 'AVOIR' THEN
    RETURN NEW;
  END IF;

  v_montant := COALESCE(NEW.montant_ttc, NEW.montant_ht, 0);

  FOR v_admin_id IN SELECT public.fn_list_admin_user_ids() LOOP
    INSERT INTO public.notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_admin_id, 'ADMIN', 'REMBOURSEMENT_MANUEL_A_FAIRE',
      '💸 Remboursement manuel à traiter',
      'Avoir ' || COALESCE(NEW.numero_facture, '') || ' — ' ||
        replace(to_char(v_montant, 'FM999999999999990.00'), '.', ',') ||
        ' €. Remboursement manuel à traiter et à confirmer après vérification de la preuve bancaire.',
      '/admin/moderation?onglet=avoirs',
      'facture_honoraire', NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$function$
;

DO $postflight$
DECLARE p record;
BEGIN
  SELECT * INTO STRICT p FROM pg_proc WHERE oid='public.fn_trg_notif_admin_remboursement_manuel()'::regprocedure;
  IF md5(p.prosrc)<>'5b2f553588a1c2d6ae7ef0a7dbded12f' OR md5(pg_get_functiondef(p.oid))<>'03f2fff285767ce417352bfb62ef5584'
    OR pg_get_userbyid(p.proowner) <> 'postgres'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
    OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature IN
      ('fn_trg_notif_admin_remboursement_manuel()','public.fn_trg_notif_admin_remboursement_manuel()'))
    OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.factures_honoraires'::regclass
      AND t.tgname='trg_notif_admin_remboursement_manuel' AND t.tgenabled='O'
      AND pg_get_triggerdef(t.oid)='CREATE TRIGGER trg_notif_admin_remboursement_manuel AFTER INSERT OR UPDATE OF mode_remboursement, type_document ON public.factures_honoraires FOR EACH ROW EXECUTE FUNCTION fn_trg_notif_admin_remboursement_manuel()')

  THEN RAISE EXCEPTION 'Notification avoir : postcondition inattendue'; END IF;
  SELECT * INTO STRICT p FROM pg_proc WHERE oid='public.fn_list_admin_user_ids()'::regprocedure;
  IF md5(p.prosrc)<>'e906ed6475c6d01f125d125e734988bf'
    OR md5(pg_get_functiondef(p.oid))<>'e2525859fa4f203e559a6a22341826c0'
    OR pg_get_userbyid(p.proowner)<>'postgres' OR p.prosecdef IS DISTINCT FROM true OR p.provolatile<>'s'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, auth']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
  THEN RAISE EXCEPTION 'Notification avoir : sélection des administrateurs inattendue'; END IF;

END;
$postflight$;

NOTIFY pgrst, 'reload schema';
