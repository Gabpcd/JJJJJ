-- FRAGMENT NON EXECUTE : après moteur privé 2cf6b7bb et barrière fermée190fea,
-- avant leur unique COMMIT. Aucun BEGIN/COMMIT ni activation dans ce fragment.
-- Dépendances RO staging observées le 01/10/2026 à18:04 et18:06UTC.
SET LOCAL search_path=pg_catalog;
DO $suivi_preflight$
DECLARE v_expected record; v_proc record;
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17 THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_CONTEXTE';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='fn_suivi_remboursements_connect_facture')
   OR EXISTS(SELECT 1 FROM private.security_definer_inventory
     WHERE signature ~ '^(public[.])?fn_suivi_remboursements_connect_facture[(]') THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_EXISTANTE';
 END IF;
 IF to_regclass('private.stripe_connect_avant_transfert') IS NULL
   OR to_regclass('private.stripe_connect_release_gate') IS NULL THEN
   RAISE EXCEPTION 'SUIVI_MOTEUR_ABSENT';
 END IF;
 IF (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
     WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE) THEN
   RAISE EXCEPTION 'SUIVI_PROTOCOLE_NON_FERME';
 END IF;
 FOR v_expected IN SELECT * FROM (VALUES
    ('auth.uid()','cdef18c69c4f4cbbced2eaf81e628b49','ea3b41bf29e2ad573067939329aa088e','supabase_auth_admin',NULL,'{=X/supabase_auth_admin,supabase_auth_admin=X/supabase_auth_admin,dashboard_user=X/supabase_auth_admin}',false,'s','sql','uuid',NULL,NULL),
    ('public.est_admin()','ef86d65809c3f76a1ac08eb737796fad','7e2b7825e43b9ea73c540f5f1ca9b264','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',true,'s','sql','boolean','est_admin()','ADMIN_EST_ADMIN_VALIDE'),
    ('public.est_admin_valide()','7954bb4e079865c63c4ba1096bd1fc76','ac1b087cbbf231e4b0ac8523054c25bc','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',true,'s','sql','boolean','est_admin_valide()','ADMIN_EST_ADMIN_VALIDE'),
    ('public.fn_a_permission_etablissement(text,uuid)','1ee98c0e7094db4e98277b85ce71c6ec','324d479198251e9c91524f28496780ba','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s','plpgsql','boolean','fn_a_permission_etablissement(text,uuid)','MIXTE_TENANT_ADMIN'),
    ('public.fn_compte_auth_actif()','8246c4c1f1b0a8053adb176a06c96766','cba1336dbd147cadc94bc6baf06ceb43','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s','sql','boolean','fn_compte_auth_actif()','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('public.fn_role_etablissement_courant(uuid)','ceb4e333f4b7f69a3be422b9753b559a','c263e1db47a25c67de3a2308dc8aa81c','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s','plpgsql','text','fn_role_etablissement_courant(uuid)','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('public.mon_etablissement_id()','dc3ef839d2920fb33cf6d7b320842c10','c460c68169ff164cb109501d6dde885d','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',true,'s','sql','uuid','mon_etablissement_id()','RPC_UTILISATEUR_AUTH_INTERNE')) AS x(signature,corps,definition,proprietaire,configuration,acl,secdef,volatilite,langage,resultat,inventaire,categorie) LOOP
   SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(v_expected.signature);
   IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
     OR md5(pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM v_expected.definition
     OR pg_get_userbyid(v_proc.proowner) IS DISTINCT FROM v_expected.proprietaire
     OR v_proc.prosecdef IS DISTINCT FROM v_expected.secdef
     OR v_proc.provolatile IS DISTINCT FROM v_expected.volatilite::"char"
     OR v_proc.lanname IS DISTINCT FROM v_expected.langage
     OR v_proc.prokind IS DISTINCT FROM 'f'::"char"
     OR pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.resultat
     OR v_proc.proconfig IS DISTINCT FROM (CASE WHEN v_expected.configuration IS NULL THEN NULL::text[] ELSE ARRAY[v_expected.configuration]::text[] END)
     OR v_proc.proacl IS DISTINCT FROM v_expected.acl::aclitem[] THEN
     RAISE EXCEPTION 'SUIVI_DEPENDANCE_INATTENDUE (%)',v_expected.signature;
   END IF;
   IF v_expected.inventaire IS NOT NULL AND (
     (SELECT count(*) FROM private.security_definer_inventory
       WHERE signature=v_expected.inventaire AND categorie=v_expected.categorie
       AND definition_md5=v_expected.corps)<>1
     OR EXISTS(SELECT 1 FROM private.security_definer_inventory
       WHERE signature='public.'||v_expected.inventaire)) THEN
     RAISE EXCEPTION 'SUIVI_DEPENDANCE_INVENTAIRE (%)',v_expected.signature;
   END IF;
 END LOOP;
END;
$suivi_preflight$;

-- CANDIDAT DE LECTURE, NON MIGRE / NON EXECUTE.
-- A composer avec le schéma privé Connect avant transfert, après revue.
-- Aucun accès direct nouveau aux tables, aucun effet fournisseur.
CREATE FUNCTION public.fn_suivi_remboursements_connect_facture(
  p_facture_honoraire_id uuid,
  p_checkout_session_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $suivi$
DECLARE
  v_uid uuid := auth.uid();
  v_h public.factures_honoraires;
  v_s public.stripe_transfers;
  v_admin boolean;
  v_finance boolean;
  v_count bigint;
  v_paiement_statut text := NULL;
  v_operations jsonb;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès refusé.' USING ERRCODE = '42501';
  END IF;

  SELECT h.* INTO v_h FROM public.factures_honoraires h
  WHERE h.id = p_facture_honoraire_id;
  v_admin := public.est_admin_valide() IS TRUE;
  v_finance := v_admin OR (
    v_h.etablissement_id = public.mon_etablissement_id()
    AND public.fn_a_permission_etablissement('lecture_paiement', v_h.etablissement_id) IS TRUE
  );
  IF v_h.id IS NULL OR v_h.type_document IS DISTINCT FROM 'FACTURE'
     OR (v_h.soignant_id IS DISTINCT FROM v_uid AND v_finance IS NOT TRUE) THEN
    RAISE EXCEPTION 'Accès refusé.' USING ERRCODE = '42501';
  END IF;
  IF v_h.mission_id IS NULL THEN
    RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
  END IF;

  -- NULL demande l'historique. Une chaîne vide ou mal formée n'est jamais NULL.
  IF p_checkout_session_id IS NOT NULL AND (
    length(p_checkout_session_id) > 255 OR p_checkout_session_id !~ '^cs_[A-Za-z0-9_]+$'
  ) THEN
    RAISE EXCEPTION 'Session de paiement invalide.' USING ERRCODE = '22023';
  END IF;

  -- Ne pas affecter une trace ancienne sans FK à une facture par déduction.
  -- Une Session étrangère ou inconnue donne la même absence de trace propre.
  IF p_checkout_session_id IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM public.stripe_transfers s
    WHERE s.facture_honoraire_id = v_h.id
      AND s.stripe_checkout_session_id = p_checkout_session_id;
    IF v_count > 1 THEN
      RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
    ELSIF v_count = 1 THEN
      SELECT s.* INTO STRICT v_s FROM public.stripe_transfers s
      WHERE s.facture_honoraire_id = v_h.id
        AND s.stripe_checkout_session_id = p_checkout_session_id;
      IF v_s.mission_id IS DISTINCT FROM v_h.mission_id
         OR v_s.etablissement_id IS DISTINCT FROM v_h.etablissement_id
         OR v_s.soignant_id IS DISTINCT FROM v_h.soignant_id
         OR v_s.statut NOT IN ('EN_ATTENTE','CHARGE_REUSSI','TRANSFERE','PAYE','ECHOUE','REMBOURSE','ANNULEE')
         OR (SELECT count(*) FROM public.stripe_transfers s
             WHERE s.stripe_checkout_session_id = p_checkout_session_id) <> 1 THEN
        RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
      END IF;
      v_paiement_statut := v_s.statut;
    END IF;
  END IF;

  -- Toutes les lectures partagent le snapshot STABLE de l'appel. On valide la
  -- filiation persistée, pas l'affectation ou l'activité actuelles de la mission.
  -- Aucun appel au helper privé de mutation / admissibilité d'un nouveau POST.
  IF EXISTS (
    SELECT 1
    FROM private.stripe_connect_avant_transfert o
    LEFT JOIN public.stripe_transfers s ON s.id = o.trace_id
    LEFT JOIN public.factures c ON c.id = o.facture_commission_id
    WHERE o.facture_honoraire_id = v_h.id AND o.orientation = 'REFUND'
      AND (p_checkout_session_id IS NULL OR o.session_id = p_checkout_session_id)
      AND (
        o.mission_id IS DISTINCT FROM v_h.mission_id
        OR o.etablissement_id IS DISTINCT FROM v_h.etablissement_id
        OR o.soignant_id IS DISTINCT FROM v_h.soignant_id
        OR o.session_id IS NULL OR o.trace_id IS NULL
        OR s.id IS NULL OR s.facture_honoraire_id IS DISTINCT FROM v_h.id
        OR s.mission_id IS DISTINCT FROM o.mission_id
        OR s.etablissement_id IS DISTINCT FROM o.etablissement_id
        OR s.soignant_id IS DISTINCT FROM o.soignant_id
        OR s.facture_id IS DISTINCT FROM o.facture_commission_id
        OR s.stripe_checkout_session_id IS DISTINCT FROM o.session_id
        OR s.stripe_transfer_id IS NOT NULL
        OR (s.stripe_payment_intent_id IS NOT NULL AND s.stripe_payment_intent_id IS DISTINCT FROM o.payment_intent_id)
        OR (s.stripe_charge_id IS NOT NULL AND s.stripe_charge_id IS DISTINCT FROM o.charge_id)
        OR c.id IS NULL OR c.type_document IS DISTINCT FROM 'FACTURE'
        OR c.facture_honoraire_id IS DISTINCT FROM v_h.id
        OR c.mission_id IS DISTINCT FROM o.mission_id
        OR c.etablissement_id IS DISTINCT FROM o.etablissement_id
        OR round(v_h.montant_ttc * 100) IS DISTINCT FROM o.soignant_cents
        OR round(c.montant_ttc * 100) IS DISTINCT FROM o.commission_cents
        OR round(s.montant_soignant * 100) IS DISTINCT FROM o.soignant_cents
        OR round(s.montant_commission * 100) IS DISTINCT FROM o.commission_cents
        OR round(s.montant_total * 100) IS DISTINCT FROM o.total_cents
        OR o.soignant_cents <= 0 OR o.commission_cents <= 0
        OR o.total_cents IS DISTINCT FROM o.soignant_cents + o.commission_cents
        OR o.total_cents > 9007199254740991
        OR o.refund_status IS NULL
        OR o.refund_status NOT IN ('READY','PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED','REVIEW')
        OR (o.refund_status = 'SUCCEEDED' AND (o.succeeded_at IS NULL OR o.review_code IS NOT NULL))
        OR s.statut IS DISTINCT FROM CASE
          WHEN o.refund_status = 'SUCCEEDED' THEN 'REMBOURSE'
          WHEN o.refund_status IN ('READY','PENDING','REQUIRES_ACTION') THEN 'EN_ATTENTE'
          WHEN o.refund_status IN ('FAILED','CANCELED','REVIEW') THEN 'ECHOUE'
          ELSE NULL END
        OR (o.review_code IS NOT NULL AND o.review_code NOT IN (
          'CREATE_WINDOW_CLOSED','REFUND_FAILED','REFUND_CANCELED',
          'REFUND_RETURNED_AFTER_SUCCESS','REFUND_REQUIRES_ACTION_AFTER_SUCCESS','REFUND_STATUS_CONTRADICTORY'))
        OR (SELECT count(*) FROM public.stripe_transfers sx
            WHERE sx.stripe_checkout_session_id = o.session_id) <> 1
      )
  ) THEN
    RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id,
    'checkout_session_id', o.session_id,
    'statut', o.refund_status,
    'montant_honoraires_centimes', o.soignant_cents,
    'montant_commission_centimes', CASE WHEN v_finance IS TRUE THEN o.commission_cents ELSE NULL END,
    'montant_total_centimes', CASE WHEN v_finance IS TRUE THEN o.total_cents ELSE NULL END,
    'cree_le', o.created_at,
    'mis_a_jour_le', NULL,
    'succeeded_at', o.succeeded_at,
    'review_code', o.review_code
  ) ORDER BY o.created_at, o.id), '[]'::jsonb)
  INTO v_operations
  FROM private.stripe_connect_avant_transfert o
  WHERE o.facture_honoraire_id = v_h.id AND o.orientation = 'REFUND'
    AND (p_checkout_session_id IS NULL OR o.session_id = p_checkout_session_id);

  RETURN jsonb_build_object(
    'facture_honoraire_id', v_h.id,
    'mission_id', v_h.mission_id,
    'checkout_session_id_filtre', p_checkout_session_id,
    'source', 'CONNECT_AVANT_TRANSFERT',
    'visibilite_montants', CASE WHEN v_finance IS TRUE THEN 'TOTAL_ETABLISSEMENT' ELSE 'HONORAIRES' END,
    'paiement_statut', v_paiement_statut,
    'operations', v_operations,
    'lecture_complete', true
  );
END;
$suivi$;
ALTER FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) TO authenticated;
COMMENT ON FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) IS
  'Lecture du suivi Connect avant transfert par facture autorisée et Session optionnelle exacte. Aucun effet financier, aucun secret fournisseur ; commissions et total réservés au périmètre établissement/admin.';

DO $suivi_installation$
DECLARE v_proc record;
BEGIN
 SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid=to_regprocedure('public.fn_suivi_remboursements_connect_facture(uuid,text)');
 IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM 'd2fd95bb65a2ba7f02089d8e53666893'
   OR pg_get_userbyid(v_proc.proowner)<>'postgres' OR v_proc.prosecdef IS DISTINCT FROM TRUE
   OR v_proc.provolatile<>'s' OR v_proc.prokind<>'f' OR v_proc.lanname<>'plpgsql'
   OR pg_get_function_result(v_proc.oid)<>'jsonb'
   OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
   OR v_proc.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}'::aclitem[]
   OR v_proc.proargnames IS DISTINCT FROM ARRAY['p_facture_honoraire_id','p_checkout_session_id']::text[]
   OR v_proc.pronargdefaults<>1 OR pg_get_expr(v_proc.proargdefaults,0) IS DISTINCT FROM 'NULL::text' THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_INATTENDUE';
 END IF;
 INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
 VALUES('fn_suivi_remboursements_connect_facture(uuid,text)','MIXTE_TENANT_ADMIN',
   'd2fd95bb65a2ba7f02089d8e53666893',
   'Lecture seule par facture : appelant actif, propriétaire soignant ou établissement avec lecture_paiement ou admin valide ; commission et total masqués au soignant.',now());
 IF (SELECT count(*) FROM private.security_definer_inventory
     WHERE signature='fn_suivi_remboursements_connect_facture(uuid,text)'
       AND categorie='MIXTE_TENANT_ADMIN' AND definition_md5='d2fd95bb65a2ba7f02089d8e53666893')<>1
   OR EXISTS(SELECT 1 FROM private.security_definer_inventory
     WHERE signature='public.fn_suivi_remboursements_connect_facture(uuid,text)') THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_INVENTAIRE';
 END IF;
END;
$suivi_installation$;
