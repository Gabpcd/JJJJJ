-- Paiements libéraux : pièce TTC explicite, aucun recalcul ni backfill historique.
-- Sources LIVE lues le 01/10/2026 ; exécution uniquement par le chemin de migration CI.
DO $preflight$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)','6fb67c1130997254cf44a0629363ecff','8c3c151f43cada391532529ea30384e0','8d7a283f517d1a6a091d8e89036ec878','5838b24137ed6a5c3d339baea5d8d079','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}','MIXTE_TENANT_ADMIN'),
    ('fn_declarer_paiement_facture_soignant(uuid,numeric,text,text,date,boolean)','1158b95fdf7a8efa7fb307a9aec29fe9','76ef2eca4bfbd9ab1c3d1e684d2938c5','4a3cad7cf864927ebbd02ed7c85f0239','6adb4ee4d8ce4e93bb34e8139d61759b','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('fn_stripe_connect_rapprocher_local(uuid,uuid,uuid,uuid,uuid,text,text,text,text,integer,integer,integer,timestamp with time zone)','d9e11dfde160642e08c1795802cbd0af','3be6ed641d4275e6232d475043fa6304','0ebde09e402e76b7da5adacaff3f42a6','7f6e56bcf109b4f6901da91fb5dc9d7c','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}','SERVICE_ONLY_REVOQUE')
  ) AS attendu(signature,ancien_corps,nouveau_corps,ancienne_definition,nouvelle_definition,configuration,acl,categorie) LOOP
    SELECT * INTO p FROM pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF md5(pg_get_functiondef(p.oid)) NOT IN (r.ancienne_definition,r.nouvelle_definition)
      OR md5(p.prosrc) NOT IN (r.ancien_corps,r.nouveau_corps)
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner)<>'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR p.proacl IS DISTINCT FROM r.acl::aclitem[]
      OR EXISTS (SELECT 1 FROM private.security_definer_inventory
        WHERE signature=r.signature AND (definition_md5 IS DISTINCT FROM md5(p.prosrc)
          OR categorie IS DISTINCT FROM r.categorie))
      OR EXISTS (SELECT 1 FROM private.security_definer_inventory WHERE signature='public.'||r.signature)
      OR (r.signature NOT LIKE 'fn_stripe_connect_rapprocher_local(%' AND NOT EXISTS
        (SELECT 1 FROM private.security_definer_inventory WHERE signature=r.signature)) THEN
      RAISE EXCEPTION 'Paiement : définition, droits ou inventaire inattendus (%)',r.signature;
    END IF;
  END LOOP;
  IF to_regprocedure('private.fn_garder_paiement_liberal_facture()') IS NOT NULL
    OR to_regprocedure('private.fn_garder_reservation_connect()') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname IN ('trg_paiement_liberal_facture','trg_reservation_connect_paiement') AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Paiement : nouvel objet déjà présent, migration refusée';
  END IF;
  IF md5(pg_get_functiondef('public.fn_stripe_payment_flow_claim(text,text,uuid,uuid)'::regprocedure))
       IS DISTINCT FROM '82f09bcf1334fb9041ae9a1628e4cd42'
    OR md5(pg_get_functiondef('public.fn_protect_stripe_transfer()'::regprocedure))
       IS DISTINCT FROM '39b6e0f0439e4efc59ac4c6bfe0d1e08' THEN
    RAISE EXCEPTION 'Paiement : prérequis claims/transferts différent';
  END IF;
END;
$preflight$;

-- Une déclaration est rattachée à une pièce précise ; le planning n'est pas une dette.
CREATE OR REPLACE FUNCTION private.fn_garder_paiement_liberal_facture()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $garde$
DECLARE
  v_m public.missions%ROWTYPE;
  v_f public.factures_honoraires%ROWTYPE;
  v_st public.stripe_transfers%ROWTYPE;
  v_old_type text;
  v_service boolean := COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_n integer;
BEGIN
  SELECT * INTO v_m FROM public.missions WHERE id = NEW.mission_id;
  IF TG_OP = 'UPDATE' THEN
    SELECT type_contrat_applique::text INTO v_old_type FROM public.missions WHERE id = OLD.mission_id;
    IF v_old_type IS DISTINCT FROM 'LIBERAL' AND v_m.type_contrat_applique IS DISTINCT FROM 'LIBERAL' THEN
      RETURN NEW;
    END IF;
    -- Aucun rôle, y compris service, ne peut réattribuer une déclaration acquise.
    -- Une correction passe par son circuit métier ; il n'y a aucun backfill ici.
    IF ROW(NEW.mission_id, NEW.soignant_id, NEW.etablissement_id, NEW.facture_honoraire_id,
           NEW.montant_net, NEW.montant_du_reference, NEW.solde_restant, NEW.est_partiel,
           NEW.source_montant_du, NEW.stripe_transfer_id, NEW.methode, NEW.date_paiement)
       IS DISTINCT FROM
       ROW(OLD.mission_id, OLD.soignant_id, OLD.etablissement_id, OLD.facture_honoraire_id,
           OLD.montant_net, OLD.montant_du_reference, OLD.solde_restant, OLD.est_partiel,
           OLD.source_montant_du, OLD.stripe_transfer_id, OLD.methode, OLD.date_paiement) THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_FINANCIER_IMMUABLE',
        DETAIL='Le montant, les parties et la facture d’un paiement existant ne peuvent pas être réattribués.';
    END IF;
    -- Les confirmations historiques sans FK restent sans FK : aucune pièce n'est
    -- choisie silencieusement. Une FK existante doit en revanche être cohérente.
    IF NEW.facture_honoraire_id IS NOT NULL AND NEW.statut = 'CONFIRME'
       AND OLD.statut IS DISTINCT FROM 'CONFIRME' THEN
      SELECT * INTO v_f FROM public.factures_honoraires WHERE id = NEW.facture_honoraire_id;
      IF v_f.id IS NULL OR v_f.type_document IS DISTINCT FROM 'FACTURE'
         OR v_f.statut NOT IN ('EMISE','EN_RETARD','PAYEE')
         OR ROW(v_f.mission_id,v_f.soignant_id,v_f.etablissement_id,v_f.montant_ttc)
            IS DISTINCT FROM ROW(NEW.mission_id,NEW.soignant_id,NEW.etablissement_id,NEW.montant_net) THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_HISTORIQUE_A_RAPPROCHER',
          DETAIL='Le paiement antérieur et sa facture doivent être rapprochés avant confirmation.';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF v_m.type_contrat_applique IS DISTINCT FROM 'LIBERAL' THEN RETURN NEW; END IF;
  -- Même ordre que les rapprochements serveur : mission, puis facture.
  SELECT * INTO v_m FROM public.missions WHERE id = NEW.mission_id FOR UPDATE;
  IF NEW.facture_honoraire_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='LIBERAL_FACTURE_REQUISE',
      DETAIL='Pour une mission libérale, ouvrez Facturation et choisissez la facture à régler.';
  END IF;
  SELECT * INTO v_f FROM public.factures_honoraires WHERE id = NEW.facture_honoraire_id FOR UPDATE;
  IF v_f.id IS NULL OR v_f.type_document IS DISTINCT FROM 'FACTURE'
     OR ROW(v_f.mission_id,v_f.soignant_id,v_f.etablissement_id)
        IS DISTINCT FROM ROW(v_m.id,v_m.soignant_assigne_id,v_m.etablissement_id)
     OR ROW(NEW.soignant_id,NEW.etablissement_id) IS DISTINCT FROM ROW(v_f.soignant_id,v_f.etablissement_id)
     OR NEW.montant_net IS NULL OR NOT (NEW.montant_net > 0 AND NEW.montant_net < 'Infinity'::numeric)
     OR NEW.montant_net IS DISTINCT FROM v_f.montant_ttc THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MONTANT_FACTURE_INCOHERENT',
      DETAIL='Le règlement doit correspondre exactement à la facture et à ses destinataires.';
  END IF;
  IF v_m.statut NOT IN ('EN_COURS','TERMINEE') OR (v_m.statut = 'EN_COURS' AND
      (v_m.strategie_facturation IS DISTINCT FROM 'HEBDO_ET_FINALE'
       OR v_f.est_facture_finale_mission IS DISTINCT FROM false
       OR v_f.periode_fin IS NULL OR v_f.periode_fin >= CURRENT_DATE)) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PERIODE_NON_PAYABLE',
      DETAIL='Seule une période hebdomadaire close ou une mission terminée peut être réglée.';
  END IF;
  IF NEW.stripe_transfer_id IS NOT NULL THEN
    -- Le rôle JWT service et une trace acquise liée à la pièce sont nécessaires.
    -- Un champ client, un administrateur authenticated ou un PI commun ne suffisent pas.
    IF NOT v_service OR NEW.statut <> 'CONFIRME'
       OR NEW.confirme_par_soignant IS DISTINCT FROM true
       OR NEW.confirme_par_etablissement IS DISTINCT FROM true THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PREUVE_STRIPE_REQUISE';
    END IF;
    SELECT count(*) INTO v_n FROM public.stripe_transfers WHERE stripe_transfer_id = NEW.stripe_transfer_id;
    SELECT * INTO v_st FROM public.stripe_transfers WHERE stripe_transfer_id = NEW.stripe_transfer_id;
    IF v_n <> 1 OR v_st.statut NOT IN ('CHARGE_REUSSI','TRANSFERE','PAYE')
       OR ROW(v_st.mission_id,v_st.soignant_id,v_st.etablissement_id,v_st.facture_honoraire_id,v_st.montant_soignant)
          IS DISTINCT FROM ROW(NEW.mission_id,NEW.soignant_id,NEW.etablissement_id,NEW.facture_honoraire_id,NEW.montant_net)
       OR NULLIF(v_st.stripe_checkout_session_id,'') IS NULL
       OR NULLIF(v_st.stripe_payment_intent_id,'') IS NULL
       OR NULLIF(v_st.stripe_charge_id,'') IS NULL
       OR v_f.statut NOT IN ('EMISE','EN_RETARD','PAYEE') THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PREUVE_STRIPE_REQUISE';
    END IF;
    -- BEFORE INSERT s'exécute également sur ON CONFLICT DO NOTHING. Seul le
    -- rejeu serveur strict de la même trace est admissible ; l'historique reste intact.
    IF EXISTS (SELECT 1 FROM public.paiements_soignant p WHERE p.stripe_transfer_id=NEW.stripe_transfer_id) THEN
      IF NOT EXISTS (SELECT 1 FROM public.paiements_soignant p
        WHERE p.stripe_transfer_id=NEW.stripe_transfer_id
          AND ROW(p.mission_id,p.soignant_id,p.etablissement_id,p.montant_net,p.statut)
              IS NOT DISTINCT FROM ROW(NEW.mission_id,NEW.soignant_id,NEW.etablissement_id,NEW.montant_net,'CONFIRME'::text)
          AND (p.facture_honoraire_id=NEW.facture_honoraire_id OR p.facture_honoraire_id IS NULL)) THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_STRIPE_REJEU_INCOHERENT';
      END IF;
      RETURN NEW;
    END IF;
  ELSE
    IF v_f.statut NOT IN ('EMISE','EN_RETARD') OR NEW.statut <> 'DECLARE'
       OR NEW.confirme_par_etablissement IS DISTINCT FROM true
       OR NEW.confirme_par_soignant IS DISTINCT FROM false
       OR NEW.methode IS NULL OR NEW.methode NOT IN ('VIREMENT','CHEQUE','NOTE_HONORAIRES') THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='DECLARATION_FACTURE_INVALIDE';
    END IF;
    IF EXISTS (SELECT 1 FROM public.stripe_transfers st WHERE st.mission_id=v_m.id
      AND (st.facture_honoraire_id=v_f.id OR st.facture_honoraire_id IS NULL)
      AND st.statut IN ('EN_ATTENTE','CHARGE_REUSSI','TRANSFERE','PAYE'))
      OR EXISTS (SELECT 1 FROM public.stripe_payment_flow_claims c WHERE
        (c.resource_key='MISSION:'||v_m.id::text AND c.flow='CONNECT_MISSION') OR
        (c.flow='CONNECT_INVOICE' AND EXISTS (SELECT 1 FROM public.factures fc
          WHERE fc.facture_honoraire_id=v_f.id AND c.resource_key='FACTURE:'||fc.id::text))) THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_STRIPE_EN_COURS',
        DETAIL='Un règlement Stripe est déjà engagé pour cette facture.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.factures_honoraires a WHERE a.facture_precedente_id=v_f.id
      AND a.type_document='AVOIR' AND a.statut NOT IN ('ANNULEE','ERREUR_GENERATION','REMPLACEE')) THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='AVOIR_A_RAPPROCHER',
        DETAIL='Cette facture possède un avoir : son règlement doit être rapproché explicitement.';
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM public.paiements_soignant p WHERE p.mission_id=v_m.id AND p.facture_honoraire_id IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_HISTORIQUE_A_RAPPROCHER',
      DETAIL='Un paiement antérieur doit être rapproché de sa facture avant de déclarer un nouveau règlement.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.paiements_soignant p WHERE p.facture_honoraire_id=v_f.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_FACTURE_DEJA_DECLARE';
  END IF;
  IF (NEW.montant_du_reference IS NOT NULL AND NEW.montant_du_reference IS DISTINCT FROM v_f.montant_ttc)
     OR (NEW.solde_restant IS NOT NULL AND NEW.solde_restant <> 0)
     OR NEW.est_partiel IS DISTINCT FROM false
     OR (NEW.source_montant_du IS NOT NULL AND NEW.source_montant_du <> 'FACTURE_HONORAIRES') THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MONTANT_FACTURE_INCOHERENT';
  END IF;
  NEW.montant_du_reference := v_f.montant_ttc;
  NEW.solde_restant := 0;
  NEW.source_montant_du := 'FACTURE_HONORAIRES';
  RETURN NEW;
END;
$garde$;
ALTER FUNCTION private.fn_garder_paiement_liberal_facture() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.fn_garder_paiement_liberal_facture() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_paiement_liberal_facture
BEFORE INSERT OR UPDATE ON public.paiements_soignant
FOR EACH ROW EXECUTE FUNCTION private.fn_garder_paiement_liberal_facture();

CREATE OR REPLACE FUNCTION private.fn_garder_reservation_connect()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $claim$
DECLARE
  v_mission uuid;
  v_fh uuid;
  v_m public.missions%ROWTYPE;
  v_c public.stripe_payment_flow_claims%ROWTYPE;
BEGIN
  IF NEW.flow NOT IN ('CONNECT_MISSION','CONNECT_INVOICE') THEN RETURN NEW; END IF;
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'') <> 'service_role' THEN
    RAISE EXCEPTION 'Réservation Connect réservée au service' USING ERRCODE='42501';
  END IF;
  IF NEW.flow='CONNECT_MISSION' AND NEW.resource_key ~ '^MISSION:[0-9a-f-]{36}$' THEN
    v_mission := substring(NEW.resource_key FROM 9)::uuid;
    IF NEW.owner_token IS DISTINCT FROM 'connect:'||v_mission::text THEN
      RAISE EXCEPTION 'Réservation Connect incohérente' USING ERRCODE='23514';
    END IF;
  ELSIF NEW.flow='CONNECT_INVOICE' AND NEW.resource_key ~ '^FACTURE:[0-9a-f-]{36}$' THEN
    SELECT f.mission_id,h.id INTO v_mission,v_fh FROM public.factures f
    JOIN public.factures_honoraires h ON h.id=f.facture_honoraire_id
    WHERE f.id=substring(NEW.resource_key FROM 9)::uuid
      AND f.type_document='FACTURE' AND h.type_document='FACTURE'
      AND f.mission_id=h.mission_id AND f.etablissement_id=h.etablissement_id
      AND NEW.owner_token='connect-invoice:'||h.id::text;
  END IF;
  IF v_mission IS NULL THEN RAISE EXCEPTION 'Réservation Connect incohérente' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id=v_mission FOR UPDATE;
  IF v_m.id IS NULL OR v_m.type_contrat_applique IS DISTINCT FROM 'LIBERAL' THEN
    RAISE EXCEPTION 'Réservation Connect incohérente' USING ERRCODE='23514';
  END IF;
  -- Aucun verrou de ligne claim/advisory après mission : le RPC détient déjà
  -- son advisory et l'autre chemin ne l'acquiert jamais dans l'ordre inverse.
  SELECT * INTO v_c FROM public.stripe_payment_flow_claims WHERE resource_key=NEW.resource_key;
  IF EXISTS (SELECT 1 FROM public.paiements_soignant p WHERE p.mission_id=v_mission
    AND (v_fh IS NULL OR p.facture_honoraire_id=v_fh OR p.facture_honoraire_id IS NULL)) THEN
    -- Le propriétaire d'un ancien claim ne prouve pas l'absence d'un virement
    -- déclaré depuis. Exception seulement pour une reprise acquise identique.
    IF v_c.flow=NEW.flow AND v_c.owner_token=NEW.owner_token
      AND v_c.stripe_checkout_session_id IS NOT NULL
      AND (SELECT count(*) FROM public.paiements_soignant p WHERE p.mission_id=v_mission
        AND (v_fh IS NULL OR p.facture_honoraire_id=v_fh OR p.facture_honoraire_id IS NULL))=1
      AND (SELECT count(*) FROM public.stripe_transfers st WHERE st.mission_id=v_mission
        AND st.stripe_checkout_session_id=v_c.stripe_checkout_session_id)=1
      AND EXISTS (SELECT 1 FROM public.paiements_soignant p
        JOIN public.stripe_transfers st ON st.stripe_transfer_id=p.stripe_transfer_id
        WHERE p.mission_id=v_mission AND st.mission_id=v_mission AND p.statut='CONFIRME'
          AND st.statut IN ('CHARGE_REUSSI','TRANSFERE','PAYE')
          AND st.stripe_checkout_session_id=v_c.stripe_checkout_session_id
          AND NULLIF(st.stripe_payment_intent_id,'') IS NOT NULL
          AND NULLIF(st.stripe_charge_id,'') IS NOT NULL
          AND NULLIF(st.stripe_transfer_id,'') IS NOT NULL
          AND (v_c.stripe_payment_intent_id IS NULL OR v_c.stripe_payment_intent_id=st.stripe_payment_intent_id)
          AND ROW(p.soignant_id,p.etablissement_id,p.montant_net)
            IS NOT DISTINCT FROM ROW(st.soignant_id,st.etablissement_id,st.montant_soignant)
          AND p.soignant_id=v_m.soignant_assigne_id AND p.etablissement_id=v_m.etablissement_id
          AND ((v_fh IS NOT NULL AND p.facture_honoraire_id=v_fh AND st.facture_honoraire_id=v_fh)
            OR (v_fh IS NULL AND (p.facture_honoraire_id=st.facture_honoraire_id
              OR p.facture_honoraire_id IS NULL)))) THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_FACTURE_DEJA_DECLARE',
      DETAIL='Un règlement a déjà été déclaré pour cette facture.';
  END IF;
  -- Pas de nouvelle tentative sur une dette diminuée par un avoir. Le seul
  -- cas sans paiement local encore présent est une reprise après transfert
  -- acquis, identifié sur la pièce exacte ; le handler doit encore relire Stripe.
  IF EXISTS (SELECT 1 FROM public.factures_honoraires a
    WHERE a.mission_id=v_mission AND a.type_document='AVOIR'
      AND a.statut NOT IN ('ANNULEE','ERREUR_GENERATION','REMPLACEE')
      AND (v_fh IS NULL OR a.facture_precedente_id=v_fh))
    AND NOT COALESCE((v_c.flow=NEW.flow AND v_c.owner_token=NEW.owner_token
      AND NULLIF(v_c.stripe_checkout_session_id,'') IS NOT NULL
      AND (SELECT count(*) FROM public.stripe_transfers st WHERE st.mission_id=v_mission
        AND st.stripe_checkout_session_id=v_c.stripe_checkout_session_id)=1
      AND EXISTS (SELECT 1 FROM public.stripe_transfers st
        JOIN public.factures_honoraires h ON h.id=st.facture_honoraire_id
        WHERE st.mission_id=v_mission AND h.mission_id=v_mission
          AND st.stripe_checkout_session_id=v_c.stripe_checkout_session_id
          AND st.statut IN ('CHARGE_REUSSI','TRANSFERE','PAYE')
          AND NULLIF(st.stripe_payment_intent_id,'') IS NOT NULL
          AND NULLIF(st.stripe_charge_id,'') IS NOT NULL
          AND NULLIF(st.stripe_transfer_id,'') IS NOT NULL
          AND (v_c.stripe_payment_intent_id IS NULL OR v_c.stripe_payment_intent_id=st.stripe_payment_intent_id)
          AND h.type_document='FACTURE' AND h.statut IN ('EMISE','EN_RETARD','PAYEE')
          AND (v_fh IS NULL OR h.id=v_fh)
          AND ROW(h.soignant_id,h.etablissement_id,h.montant_ttc)
            IS NOT DISTINCT FROM ROW(st.soignant_id,st.etablissement_id,st.montant_soignant)
          AND h.soignant_id=v_m.soignant_assigne_id AND h.etablissement_id=v_m.etablissement_id)),false) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='AVOIR_A_RAPPROCHER',
      DETAIL='Cette facture possède un avoir : son règlement doit être rapproché explicitement.';
  END IF;
  -- MISSION et FACTURE sont des clés différentes, mais ne créent pas deux dettes.
  IF EXISTS (SELECT 1 FROM public.stripe_payment_flow_claims c WHERE c.resource_key<>NEW.resource_key
    AND ((c.flow='CONNECT_MISSION' AND c.resource_key='MISSION:'||v_mission::text)
      OR (c.flow='CONNECT_INVOICE' AND EXISTS (SELECT 1 FROM public.factures fc
        WHERE fc.mission_id=v_mission AND c.resource_key='FACTURE:'||fc.id::text
          AND (v_fh IS NULL OR fc.facture_honoraire_id=v_fh))))) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='PAIEMENT_STRIPE_EN_COURS';
  END IF;
  RETURN NEW;
END;
$claim$;
ALTER FUNCTION private.fn_garder_reservation_connect() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.fn_garder_reservation_connect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_reservation_connect_paiement
BEFORE INSERT ON public.stripe_payment_flow_claims
FOR EACH ROW EXECUTE FUNCTION private.fn_garder_reservation_connect();

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant_v2(p_mission_id uuid, p_montant_verse numeric, p_montant_total_du numeric, p_methode text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_date_paiement date DEFAULT CURRENT_DATE, p_attestation_sur_l_honneur boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_result jsonb;
  v_paiement_id uuid;
  v_plafond_brut numeric;
  v_source text;
  v_solde numeric;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('error', 'MISSION_INTROUVABLE', 'message', 'Mission introuvable.');
  END IF;

  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', v_mission.etablissement_id) IS NOT TRUE
     )
  THEN
    RETURN jsonb_build_object('error', 'ACCES_REFUSE', 'message', 'Accès refusé.');
  END IF;

  IF v_mission.type_contrat_applique = 'LIBERAL' THEN
    RETURN jsonb_build_object('error', 'LIBERAL_FACTURE_REQUISE',
      'message', 'Pour une mission libérale, ouvrez Facturation et choisissez la facture à régler.');
  END IF;

  IF p_montant_verse IS NULL OR p_montant_verse <= 0
     OR p_montant_total_du IS NULL OR p_montant_total_du <= 0
  THEN
    RETURN jsonb_build_object(
      'error', 'MONTANTS_REQUIS',
      'message', 'Renseignez le total net dû et le montant réellement versé.'
    );
  END IF;

  IF round(p_montant_verse, 2) > round(p_montant_total_du, 2) THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_VERSE_SUPERIEUR_AU_DU',
      'message', 'Le montant versé ne peut pas dépasser le total net dû.'
    );
  END IF;

  IF round(p_montant_verse, 2) < round(p_montant_total_du, 2) THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_INCOMPLET',
      'message', 'Le montant versé doit correspondre exactement au total net dû. Les paiements partiels ne sont pas acceptés.',
      'montant_verse', round(p_montant_verse, 2),
      'montant_total_du', round(p_montant_total_du, 2),
      'solde_manquant', round(p_montant_total_du - p_montant_verse, 2)
    );
  END IF;

  IF v_mission.type_contrat_applique = 'SALARIE' THEN
    v_plafond_brut := COALESCE(v_mission.total_brut, 0)
      + COALESCE(v_mission.montant_ifm, 0)
      + COALESCE(v_mission.montant_icp, 0)
      + COALESCE(v_mission.montant_majoration_nuit, 0)
      + COALESCE(v_mission.montant_majoration_dimanche, 0)
      + COALESCE(v_mission.montant_majoration_ferie, 0);
    IF v_plafond_brut <= 0 THEN
      RETURN jsonb_build_object(
        'error', 'BRUT_SALARIE_INDISPONIBLE',
        'message', 'La rémunération brute de référence est indisponible.'
      );
    END IF;
    IF round(p_montant_total_du, 2) > round(v_plafond_brut, 2) THEN
      RETURN jsonb_build_object(
        'error', 'MONTANT_NET_SALARIE_SUPERIEUR_AU_BRUT',
        'message', 'Le total net dû ne peut pas dépasser le brut de référence (' || round(v_plafond_brut, 2) || ' €).',
        'montant_maximum', round(v_plafond_brut, 2)
      );
    END IF;
    v_source := 'BULLETIN_OFFICIEL_ETABLISSEMENT';
  ELSE
    v_source := 'FACTURE_HONORAIRES';
  END IF;

  v_result := public.fn_declarer_paiement_soignant_internal_20260801(
    p_mission_id,
    round(p_montant_verse, 2),
    p_methode,
    p_reference,
    p_date_paiement,
    p_attestation_sur_l_honneur
  );
  IF v_result ? 'error' THEN
    RETURN v_result;
  END IF;

  v_paiement_id := (v_result->>'paiement_id')::uuid;
  v_solde := greatest(round(p_montant_total_du - p_montant_verse, 2), 0);

  UPDATE public.paiements_soignant
  SET montant_du_reference = round(p_montant_total_du, 2),
      solde_restant = v_solde,
      est_partiel = v_solde > 0,
      source_montant_du = v_source,
      modifie_le = now()
  WHERE id = v_paiement_id;

  RETURN v_result || jsonb_build_object(
    'montant_verse', round(p_montant_verse, 2),
    'montant_total_du', round(p_montant_total_du, 2),
    'solde_restant', v_solde,
    'est_partiel', v_solde > 0,
    'source_montant_du', v_source
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_facture_soignant(p_facture_honoraire_id uuid, p_montant numeric, p_methode text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_date_paiement date DEFAULT CURRENT_DATE, p_attestation_sur_l_honneur boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_etab_id uuid := public.mon_etablissement_id();
  v_methode text;
  v_ref text;
  v_echeance date;
  v_paiement_id uuid;
  v_detail text;
BEGIN
  IF NOT p_attestation_sur_l_honneur THEN
    RETURN jsonb_build_object(
      'error', 'ATTESTATION_REQUISE',
      'message', 'L''attestation sur l''honneur est obligatoire pour déclarer un paiement soignant.'
    );
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id;
  IF v_fh.id IS NULL OR v_fh.type_document <> 'FACTURE' THEN
    RETURN jsonb_build_object('error', 'Facture d''honoraires introuvable');
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = v_fh.mission_id
  FOR UPDATE;
  -- Relecture verrouillée après mission : même ordre que le rapprochement Stripe.
  SELECT * INTO v_fh FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id FOR UPDATE;
  IF v_mission.id IS NULL OR v_fh.id IS NULL
     OR v_fh.etablissement_id <> v_mission.etablissement_id
     OR v_fh.soignant_id <> v_mission.soignant_assigne_id THEN
    RETURN jsonb_build_object('error', 'Facture et mission incohérentes');
  END IF;

  IF v_etab_id IS NULL
     OR v_etab_id <> v_mission.etablissement_id
     OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_mission.type_contrat_applique <> 'LIBERAL' THEN
    RETURN jsonb_build_object(
      'error', 'CONTRAT_INCOMPATIBLE',
      'message', 'Le paiement par facture est réservé aux missions libérales.'
    );
  END IF;
  IF v_fh.statut NOT IN ('EMISE', 'EN_RETARD') THEN
    RETURN jsonb_build_object('error', 'Cette facture n''est plus payable');
  END IF;
  IF v_mission.statut NOT IN ('EN_COURS', 'TERMINEE')
     OR (
       v_mission.statut = 'EN_COURS'
       AND (
         v_mission.strategie_facturation <> 'HEBDO_ET_FINALE'
         OR v_fh.est_facture_finale_mission
         OR v_fh.periode_fin >= CURRENT_DATE
       )
     ) THEN
    RETURN jsonb_build_object(
      'error', 'PERIODE_NON_PAYABLE',
      'message', 'Seule une période hebdomadaire close ou une mission terminée peut être payée.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.paiements_soignant p
    WHERE p.facture_honoraire_id = v_fh.id
      AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
  ) OR EXISTS (
    SELECT 1 FROM public.stripe_transfers st
    WHERE st.facture_honoraire_id = v_fh.id
      AND st.statut IN ('CHARGE_REUSSI', 'TRANSFERE', 'PAYE')
  ) THEN
    RETURN jsonb_build_object('error', 'Paiement déjà déclaré pour cette période');
  END IF;

  IF p_montant IS NULL OR NOT (p_montant > 0 AND p_montant < 'Infinity'::numeric) THEN
    RETURN jsonb_build_object('error', 'Le montant doit être supérieur à 0.');
  END IF;
  IF p_montant IS DISTINCT FROM v_fh.montant_ttc THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_FACTURE_INCOHERENT',
      'message', 'Le montant déclaré doit correspondre au montant exact de la facture (' || v_fh.montant_ttc || ' €).'
    );
  END IF;
  IF p_date_paiement > CURRENT_DATE THEN
    RETURN jsonb_build_object('error', 'La date de paiement ne peut pas être dans le futur.');
  END IF;

  IF p_methode IS NOT NULL
     AND p_methode NOT IN ('VIREMENT', 'CHEQUE', 'NOTE_HONORAIRES') THEN
    RETURN jsonb_build_object(
      'error', 'METHODE_INVALIDE',
      'message', 'Pour une note d''honoraires, utilisez VIREMENT, CHEQUE ou NOTE_HONORAIRES.'
    );
  END IF;
  v_methode := COALESCE(p_methode, 'NOTE_HONORAIRES');
  v_ref := btrim(COALESCE(p_reference, ''));
  IF length(v_ref) < 5 OR v_ref !~ '[0-9]' THEN
    RETURN jsonb_build_object(
      'error', 'REFERENCE_INVALIDE',
      'message', 'La référence doit contenir au moins 5 caractères et un chiffre.'
    );
  END IF;

  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_fh.soignant_id;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_etab_id;
  v_echeance := p_date_paiement + COALESCE(v_etab.delai_paiement_jours, 30);

  INSERT INTO public.paiements_soignant (
    mission_id, facture_honoraire_id, soignant_id, etablissement_id,
    montant_net, methode, reference_virement, date_paiement, echeance_le,
    statut, confirme_par_etablissement, confirme_par_etablissement_le
  ) VALUES (
    v_mission.id, v_fh.id, v_fh.soignant_id, v_etab_id,
    round(p_montant, 2), v_methode, v_ref, p_date_paiement, v_echeance,
    'DECLARE', true, now()
  )
  RETURNING id INTO v_paiement_id;

  INSERT INTO public.notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_fh.soignant_id,
    'SYSTEM',
    'Paiement hebdomadaire déclaré',
    'Paiement de ' || round(p_montant, 2) || ' € déclaré pour la période du '
      || to_char(v_fh.periode_debut, 'DD/MM/YYYY') || ' au '
      || to_char(v_fh.periode_fin, 'DD/MM/YYYY') || ' de « '
      || public.fn_html_escape(v_mission.intitule) || ' » (réf. ' || v_ref || ').',
    '/soignant/mes-gains',
    'SOIGNANT'
  );

  PERFORM public.fn_ecrire_audit_safe(
    auth.uid(), 'ETABLISSEMENT', 'PAIEMENT_SOIGNANT_DECLARE_ETAB',
    'factures_honoraires', v_fh.id, NULL,
    jsonb_build_object(
      'mission_id', v_mission.id,
      'facture_honoraire_id', v_fh.id,
      'periode_debut', v_fh.periode_debut,
      'periode_fin', v_fh.periode_fin,
      'montant_net', round(p_montant, 2),
      'methode', v_methode,
      'reference_virement', v_ref,
      'date_paiement', p_date_paiement,
      'attestation_sur_l_honneur', true
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'paiement_id', v_paiement_id,
    'facture_honoraires_id', v_fh.id,
    'soignant_id', v_fh.soignant_id,
    'mission_intitule', v_mission.intitule,
    'echeance', v_echeance
  );
EXCEPTION WHEN check_violation THEN
  IF SQLERRM IN ('PAIEMENT_HISTORIQUE_A_RAPPROCHER','PAIEMENT_STRIPE_EN_COURS',
    'PAIEMENT_FACTURE_DEJA_DECLARE','AVOIR_A_RAPPROCHER','MONTANT_FACTURE_INCOHERENT',
    'PERIODE_NON_PAYABLE','DECLARATION_FACTURE_INVALIDE','LIBERAL_FACTURE_REQUISE') THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN jsonb_build_object('error',SQLERRM,'message',COALESCE(NULLIF(v_detail,''),
      'Ce règlement doit être vérifié avant une nouvelle déclaration.'));
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_stripe_connect_rapprocher_local(p_mission_id uuid, p_soignant_id uuid, p_etablissement_id uuid, p_facture_honoraires_id uuid, p_facture_commission_id uuid, p_stripe_checkout_session_id text, p_stripe_payment_intent_id text, p_stripe_charge_id text, p_stripe_transfer_id text, p_montant_soignant_cts integer, p_montant_commission_cts integer, p_montant_total_cts integer, p_rapproche_le timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_transfer public.stripe_transfers%ROWTYPE;
  v_honoraires public.factures_honoraires%ROWTYPE;
  v_commission public.factures%ROWTYPE;
  v_numero_commission text;
  v_rows integer;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_mission_id IS NULL OR p_soignant_id IS NULL OR p_etablissement_id IS NULL
     OR p_facture_honoraires_id IS NULL
     OR p_stripe_checkout_session_id !~ '^cs_[A-Za-z0-9_]+$'
     OR p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
     OR p_stripe_charge_id !~ '^ch_[A-Za-z0-9]+'
     OR p_stripe_transfer_id !~ '^tr_[A-Za-z0-9]+$'
     OR p_montant_soignant_cts <= 0
     OR p_montant_commission_cts <= 0
     OR p_montant_total_cts <> p_montant_soignant_cts + p_montant_commission_cts THEN
    RAISE EXCEPTION 'Paramètres de rapprochement Connect invalides'
      USING ERRCODE = '22023';
  END IF;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_mission.etablissement_id <> p_etablissement_id
     OR v_mission.soignant_assigne_id <> p_soignant_id
     OR v_mission.statut <> 'TERMINEE'
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR round(v_mission.net_a_payer * 100)::integer <> p_montant_soignant_cts
     OR round(v_mission.montant_commission_ttc * 100)::integer <> p_montant_commission_cts THEN
    RAISE EXCEPTION 'Mission Connect incohérente' USING ERRCODE = 'P0001';
  END IF;

  IF (SELECT count(*) FROM public.stripe_transfers WHERE mission_id=p_mission_id
      AND stripe_checkout_session_id=p_stripe_checkout_session_id) <> 1 THEN
    RAISE EXCEPTION 'Trace Connect absente ou ambiguë' USING ERRCODE='23514';
  END IF;
  SELECT st.* INTO v_transfer
  FROM public.stripe_transfers st
  WHERE st.mission_id = p_mission_id
    AND st.stripe_checkout_session_id = p_stripe_checkout_session_id
  ORDER BY st.cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND
     OR (v_transfer.facture_honoraire_id IS NOT NULL
         AND v_transfer.facture_honoraire_id <> p_facture_honoraires_id)
     OR v_transfer.soignant_id <> p_soignant_id
     OR v_transfer.etablissement_id <> p_etablissement_id
     OR round(v_transfer.montant_soignant * 100)::integer <> p_montant_soignant_cts
     OR round(v_transfer.montant_commission * 100)::integer <> p_montant_commission_cts
     OR round(v_transfer.montant_total * 100)::integer <> p_montant_total_cts
     OR v_transfer.statut NOT IN ('EN_ATTENTE', 'ECHOUE', 'CHARGE_REUSSI', 'TRANSFERE', 'PAYE')
     OR (v_transfer.stripe_payment_intent_id IS NOT NULL
         AND v_transfer.stripe_payment_intent_id <> p_stripe_payment_intent_id)
     OR (v_transfer.stripe_charge_id IS NOT NULL
         AND v_transfer.stripe_charge_id <> p_stripe_charge_id)
     OR (v_transfer.stripe_transfer_id IS NOT NULL
         AND v_transfer.stripe_transfer_id <> p_stripe_transfer_id) THEN
    RAISE EXCEPTION 'Trace Connect incohérente' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.stripe_transfers
  SET statut = CASE
        WHEN statut = 'PAYE' THEN 'PAYE'
        ELSE 'TRANSFERE'
      END,
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      stripe_charge_id = p_stripe_charge_id,
      stripe_transfer_id = p_stripe_transfer_id,
      transfere_le = COALESCE(transfere_le, p_rapproche_le, now()),
      erreur = NULL
  WHERE id = v_transfer.id;

  SELECT fh.* INTO v_honoraires
  FROM public.factures_honoraires fh
  WHERE fh.id = p_facture_honoraires_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_honoraires.type_document <> 'FACTURE'
     OR v_honoraires.mission_id <> p_mission_id
     OR v_honoraires.soignant_id <> p_soignant_id
     OR v_honoraires.etablissement_id <> p_etablissement_id
     OR round(v_honoraires.montant_ttc * 100)::integer <> p_montant_soignant_cts
     OR v_honoraires.statut NOT IN ('EMISE', 'EN_RETARD', 'PAYEE')
     OR (v_honoraires.stripe_payment_intent_id IS NOT NULL
         AND v_honoraires.stripe_payment_intent_id <> p_stripe_payment_intent_id) THEN
    RAISE EXCEPTION 'Facture honoraires Connect incohérente' USING ERRCODE = 'P0001';
  END IF;

  -- Le producteur possède la FH explicite validée contre la Session Stripe.
  -- Rattachement courant de cette trace seulement ; aucun paiement ancien réécrit.
  UPDATE public.stripe_transfers SET facture_honoraire_id=v_honoraires.id
  WHERE id=v_transfer.id AND facture_honoraire_id IS NULL;

  UPDATE public.factures_honoraires
  SET statut = 'PAYEE',
      stripe_payment_intent_id = p_stripe_payment_intent_id,
      date_paiement = COALESCE(date_paiement, (COALESCE(p_rapproche_le, now()))::date),
      modifie_le = now()
  WHERE id = v_honoraires.id;

  IF p_facture_commission_id IS NOT NULL THEN
    SELECT f.* INTO v_commission
    FROM public.factures f
    WHERE f.id = p_facture_commission_id
    FOR UPDATE;
    IF NOT FOUND
       OR v_commission.type_document <> 'FACTURE'
       OR v_commission.mission_id <> p_mission_id
       OR v_commission.etablissement_id <> p_etablissement_id
       OR (v_commission.facture_honoraire_id IS NOT NULL
           AND v_commission.facture_honoraire_id <> p_facture_honoraires_id)
       OR round(v_commission.montant_ttc * 100)::integer <> p_montant_commission_cts
       OR v_commission.statut NOT IN ('EMISE', 'EN_RETARD', 'PAYEE')
       OR (v_commission.stripe_payment_intent_id IS NOT NULL
           AND v_commission.stripe_payment_intent_id <> p_stripe_payment_intent_id) THEN
      RAISE EXCEPTION 'Facture commission Connect incohérente' USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.factures
    SET statut = 'PAYEE',
        stripe_payment_intent_id = p_stripe_payment_intent_id,
        date_paiement = COALESCE(date_paiement, p_rapproche_le, now()),
        mode_paiement = 'STRIPE',
        modifie_le = now()
    WHERE id = v_commission.id;
  ELSE
    v_numero_commission := 'FACT-STRIPE-'
      || to_char(COALESCE(p_rapproche_le, now()), 'YYYY-MM-DD')
      || '-' || split_part(p_mission_id::text, '-', 1);
    INSERT INTO public.factures (
      etablissement_id, mission_id, numero_facture,
      montant_ht, montant_tva, montant_ttc, taux_tva, nombre_missions,
      statut, date_emission, date_paiement, mode_paiement,
      stripe_payment_intent_id, type_document
    ) VALUES (
      p_etablissement_id, p_mission_id, v_numero_commission,
      v_mission.montant_commission_ht,
      v_mission.montant_commission_tva,
      v_mission.montant_commission_ttc,
      20, 1,
      'PAYEE', COALESCE(p_rapproche_le, now()), COALESCE(p_rapproche_le, now()),
      'STRIPE', p_stripe_payment_intent_id, 'FACTURE'
    )
    ON CONFLICT (numero_facture) DO NOTHING;

    SELECT f.* INTO v_commission
    FROM public.factures f
    WHERE f.numero_facture = v_numero_commission
    FOR UPDATE;
    IF NOT FOUND
       OR v_commission.mission_id <> p_mission_id
       OR v_commission.etablissement_id <> p_etablissement_id
       OR (v_commission.facture_honoraire_id IS NOT NULL
           AND v_commission.facture_honoraire_id <> p_facture_honoraires_id)
       OR v_commission.statut <> 'PAYEE'
       OR v_commission.stripe_payment_intent_id <> p_stripe_payment_intent_id
       OR round(v_commission.montant_ttc * 100)::integer <> p_montant_commission_cts THEN
      RAISE EXCEPTION 'Création facture commission Connect incohérente'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  INSERT INTO public.paiements_soignant (
    mission_id, facture_honoraire_id, soignant_id, etablissement_id, montant_net, methode,
    reference_virement, date_paiement, statut,
    confirme_par_etablissement, confirme_par_etablissement_le,
    confirme_par_soignant, confirme_par_soignant_le, stripe_transfer_id
  ) VALUES (
    p_mission_id, p_facture_honoraires_id, p_soignant_id, p_etablissement_id,
    p_montant_soignant_cts::numeric / 100, 'NOTE_HONORAIRES',
    'STRIPE-' || p_stripe_transfer_id,
    (COALESCE(p_rapproche_le, now()))::date, 'CONFIRME',
    true, COALESCE(p_rapproche_le, now()),
    true, COALESCE(p_rapproche_le, now()), p_stripe_transfer_id
  )
  ON CONFLICT (stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL
  DO NOTHING;

  SELECT count(*) INTO v_rows
  FROM public.paiements_soignant ps
  WHERE ps.stripe_transfer_id = p_stripe_transfer_id
    AND ps.mission_id = p_mission_id
    AND ps.soignant_id = p_soignant_id
    AND ps.etablissement_id = p_etablissement_id
    AND round(ps.montant_net * 100)::integer = p_montant_soignant_cts
    AND ps.statut = 'CONFIRME';
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Paiement soignant Connect incohérent' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.missions
  SET mode_paiement_soignant = 'STRIPE_CONNECT',
      commission_facturee = true,
      modifie_le = now()
  WHERE id = p_mission_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    details, navigateur_acteur
  ) VALUES (
    p_soignant_id,
    'SYSTEME',
    'FINANCE_TRANSFER_CONNECT',
    'mission',
    p_mission_id,
    jsonb_build_object(
      'stripe_transfer_id', p_stripe_transfer_id,
      'stripe_charge_id', p_stripe_charge_id,
      'stripe_payment_intent_id', p_stripe_payment_intent_id,
      'stripe_session_id', p_stripe_checkout_session_id,
      'facture_honoraires_id', p_facture_honoraires_id,
      'facture_commission_id', v_commission.id,
      'montant_cents', p_montant_soignant_cts,
      'evenement', 'CONNECT_RAPPROCHEMENT_LOCAL_ATOMIQUE'
    ),
    'fn_stripe_connect_rapprocher_local'
  );

  RETURN jsonb_build_object(
    'success', true,
    'stripe_transfer_id', p_stripe_transfer_id,
    'facture_commission_id', v_commission.id
  );
END;
$function$;
DO $inventory$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)','6fb67c1130997254cf44a0629363ecff','8c3c151f43cada391532529ea30384e0','8d7a283f517d1a6a091d8e89036ec878','5838b24137ed6a5c3d339baea5d8d079','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}','MIXTE_TENANT_ADMIN'),
    ('fn_declarer_paiement_facture_soignant(uuid,numeric,text,text,date,boolean)','1158b95fdf7a8efa7fb307a9aec29fe9','76ef2eca4bfbd9ab1c3d1e684d2938c5','4a3cad7cf864927ebbd02ed7c85f0239','6adb4ee4d8ce4e93bb34e8139d61759b','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('fn_stripe_connect_rapprocher_local(uuid,uuid,uuid,uuid,uuid,text,text,text,text,integer,integer,integer,timestamp with time zone)','d9e11dfde160642e08c1795802cbd0af','3be6ed641d4275e6232d475043fa6304','0ebde09e402e76b7da5adacaff3f42a6','7f6e56bcf109b4f6901da91fb5dc9d7c','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}','SERVICE_ONLY_REVOQUE')
  ) AS attendu(signature,ancien_corps,nouveau_corps,ancienne_definition,nouvelle_definition,configuration,acl,categorie) LOOP
    SELECT * INTO p FROM pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM r.nouvelle_definition
      OR md5(p.prosrc) IS DISTINCT FROM r.nouveau_corps
      OR p.proacl IS DISTINCT FROM r.acl::aclitem[]
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner)<>'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR EXISTS (SELECT 1 FROM private.security_definer_inventory
        WHERE signature=r.signature AND (categorie IS DISTINCT FROM r.categorie
          OR definition_md5 NOT IN(r.ancien_corps,r.nouveau_corps)))
      OR EXISTS (SELECT 1 FROM private.security_definer_inventory WHERE signature='public.'||r.signature) THEN
      RAISE EXCEPTION 'Paiement : installation inattendue (%)',r.signature;
    END IF;
    IF r.signature LIKE 'fn_stripe_connect_rapprocher_local(%' THEN
      -- Absence constatée dans le catalogue LIVE ; entrée unique et nommée,
      -- après preuve du corps, du propriétaire et des ACL service seules.
      INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification)
      VALUES(r.signature,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),
        'Rapprochement Connect service : trace acquise, pièce explicite, montants et parties validés ; aucun rattachement de paiement historique.')
      ON CONFLICT(signature) DO UPDATE SET definition_md5=excluded.definition_md5,recense_le=now()
        WHERE private.security_definer_inventory.definition_md5 IN(r.ancien_corps,r.nouveau_corps)
          AND private.security_definer_inventory.categorie=r.categorie;
    ELSE
      UPDATE private.security_definer_inventory SET definition_md5=md5(p.prosrc),recense_le=now()
        WHERE signature=r.signature AND categorie=r.categorie AND definition_md5 IN (r.ancien_corps,r.nouveau_corps);
    END IF;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.security_definer_inventory
      WHERE signature=r.signature AND categorie=r.categorie AND definition_md5=r.nouveau_corps) THEN
      RAISE EXCEPTION 'Paiement : inventaire non actualisé (%)',r.signature; END IF;
  END LOOP;
END;
$inventory$;
