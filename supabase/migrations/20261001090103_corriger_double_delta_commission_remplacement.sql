-- Correction bornée depuis la définition LIVE staging/production du 01/10/2026.
-- md5(pg_get_functiondef) avant : b35b9b246690238ccb77e19e484c2a77.
-- Le cas de taux corrigé à quantité stable ne réapplique plus le delta global.
-- Les autres chemins sont conservés. Aucun changement de droit, taux ou paiement.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid='public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure;
  IF NOT FOUND OR md5(p.prosrc) NOT IN ('e206148ca3a7073ccc05d76e68d710fa', 'c8b2603eda031d12d75a294ffb87d522')
    OR md5(pg_get_functiondef(p.oid)) NOT IN ('b35b9b246690238ccb77e19e484c2a77', 'c793ac81eaef0fe18fb5920c9264c675')
    OR p.prosecdef IS DISTINCT FROM true
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
    RAISE EXCEPTION 'Commission rectificative : définition ou droits inattendus';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory
    WHERE signature='fn_preparer_commission_remplacement_honoraires(uuid)'
      AND categorie='SERVICE_ONLY_REVOQUE'
      AND definition_md5=md5(p.prosrc)) THEN
    RAISE EXCEPTION 'Commission rectificative : inventaire divergent';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_preparer_commission_remplacement_honoraires(p_facture_honoraire_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_origine_honoraires public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_origine_commission public.factures%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_delta_ht numeric(10,2);
  v_delta_tva numeric(10,2);
  v_delta_ttc numeric(10,2);
  v_taux_commission numeric;
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND nature_correction = 'REMPLACEMENT'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Facture rectificative introuvable ou non émise'; END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success', true, 'facture_id', v_existing.id, 'existing', true);
  END IF;

  SELECT * INTO v_origine_honoraires
  FROM public.factures_honoraires
  WHERE id = v_fh.facture_precedente_id
  FOR UPDATE;
  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF v_origine_honoraires.id IS NULL OR v_mission.id IS NULL OR v_etab.id IS NULL THEN
    RAISE EXCEPTION 'Chaîne de rectification incomplète';
  END IF;

  SELECT * INTO v_origine_commission
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_honoraires.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF FOUND AND v_origine_commission.statut NOT IN ('BROUILLON', 'EMISE', 'EN_RETARD') THEN
    RAISE EXCEPTION 'La facture de services d''origine est déjà payée : un avoir est requis';
  END IF;

  v_taux_commission := CASE
    WHEN v_origine_honoraires.montant_ht > 0 AND v_origine_commission.montant_ht > 0
      THEN v_origine_commission.montant_ht / v_origine_honoraires.montant_ht
    ELSE COALESCE(v_mission.taux_commission, 15) / 100
  END;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;
  v_ht := round(v_fh.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  v_delta_ht := v_ht - COALESCE(v_origine_commission.montant_ht, 0);
  v_delta_tva := v_tva - COALESCE(v_origine_commission.montant_tva, 0);
  v_delta_ttc := v_ttc - COALESCE(v_origine_commission.montant_ttc, 0);

  IF v_origine_commission.id IS NOT NULL THEN
    UPDATE public.factures
    SET statut = 'REMPLACEE', modifie_le = now()
    WHERE id = v_origine_commission.id
      AND statut IN ('BROUILLON', 'EMISE', 'EN_RETARD');
  END IF;

  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-HR-'
    || upper(left(replace(v_fh.id::text, '-', ''), 10));
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    facture_precedente_id, periode_debut, periode_fin,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, est_secteur_public,
    mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_origine_commission.id, v_fh.periode_debut, v_fh.periode_fin,
    v_ht, 20, v_tva, v_ttc, 1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  ) RETURNING * INTO v_existing;

  -- Cas reproduit : taux corrigé, quantité facturée inchangée sur une mission
  -- EN_COURS. Le moteur de mission a déjà recalculé ses agrégats au nouveau
  -- taux ; le delta de cette période ne doit pas être appliqué une seconde fois.
  -- Les autres corrections conservent le chemin historique (notamment heures
  -- seules et finale), sans prétendre corriger leurs propres écarts financiers.
  IF v_mission.statut = 'EN_COURS'
     AND v_fh.quantite_heures_snapshot > 0
     AND v_fh.quantite_heures_snapshot::text NOT IN ('NaN', 'Infinity', '-Infinity')
     AND v_fh.quantite_heures_snapshot = v_origine_honoraires.quantite_heures_snapshot
     AND v_fh.taux_horaire_snapshot > 0
     AND v_origine_honoraires.taux_horaire_snapshot > 0
     AND v_fh.taux_horaire_snapshot::text NOT IN ('NaN', 'Infinity', '-Infinity')
     AND v_origine_honoraires.taux_horaire_snapshot::text NOT IN ('NaN', 'Infinity', '-Infinity')
     AND v_fh.taux_horaire_snapshot <> v_origine_honoraires.taux_horaire_snapshot
     AND v_mission.taux_horaire_base = v_fh.taux_horaire_snapshot THEN
    UPDATE public.missions
    SET commission_a_recalculer = false,
        modifie_le = now()
    WHERE id = v_mission.id;
  ELSE
    UPDATE public.missions
    SET total_brut = round(
          COALESCE(total_brut, 0)
            + v_fh.montant_ht - v_origine_honoraires.montant_ht,
          2
        ),
        net_a_payer = round(
          COALESCE(net_a_payer, 0)
            + v_fh.montant_ttc - v_origine_honoraires.montant_ttc,
          2
        ),
        montant_commission_ht = round(COALESCE(montant_commission_ht, 0) + v_delta_ht, 2),
        montant_commission_tva = round(COALESCE(montant_commission_tva, 0) + v_delta_tva, 2),
        montant_commission_ttc = round(COALESCE(montant_commission_ttc, 0) + v_delta_ttc, 2),
        commission_a_recalculer = false,
        modifie_le = now()
    WHERE id = v_mission.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc, 'existing', false
  );
END;
$function$;

DO $inventory$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid='public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure;
  IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM 'c8b2603eda031d12d75a294ffb87d522'
    OR p.prosecdef IS DISTINCT FROM true
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
    RAISE EXCEPTION 'Commission rectificative : installation ou droits inattendus';
  END IF;
  UPDATE private.security_definer_inventory
  SET definition_md5=md5(p.prosrc), recense_le=now()
  WHERE signature='fn_preparer_commission_remplacement_honoraires(uuid)'
    AND categorie='SERVICE_ONLY_REVOQUE'
    AND definition_md5 IN ('e206148ca3a7073ccc05d76e68d710fa', 'c8b2603eda031d12d75a294ffb87d522');
  IF NOT FOUND THEN RAISE EXCEPTION 'Commission rectificative : inventaire non actualisé'; END IF;
END;
$inventory$;
