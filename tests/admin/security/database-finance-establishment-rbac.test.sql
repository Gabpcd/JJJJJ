-- Invariants runtime des finances établissement.
-- Prérequis : migration 20260801180304 appliquée.

\set ON_ERROR_STOP on
BEGIN;

DO $finance_rbac$
DECLARE
  v_bad text;
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.fn_export_fec(integer)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT LIKE '%e.est_compte_test IS FALSE%'
     OR v_definition NOT LIKE '%f.statut NOT IN (''BROUILLON'', ''ANNULEE'')%'
     OR v_definition NOT LIKE '%411000%'
     OR v_definition NOT LIKE '%706000%'
     OR v_definition NOT LIKE '%445710%'
     OR pg_get_function_result('public.fn_export_fec(integer)'::regprocedure)
        NOT LIKE '%"JournalCode" text%"Idevise" text%' THEN
    RAISE EXCEPTION 'Export FEC incomplet, non équilibré ou non borné à la production';
  END IF;

  WITH reviewed(signature) AS (VALUES
    ('public.fn_mes_permissions_etab(uuid)'::regprocedure),
    ('public.fn_obligations_financieres()'::regprocedure),
    ('public.fn_mes_factures()'::regprocedure),
    ('public.fn_paiements_etablissement()'::regprocedure),
    ('public.fn_detail_facture(uuid)'::regprocedure),
    ('public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure),
    ('public.fn_modifier_reference_paiement(uuid,text)'::regprocedure),
    ('public.fn_consulter_rib_soignant(uuid)'::regprocedure),
    ('public.fn_generer_facture_mensuelle(uuid)'::regprocedure),
    ('public.fn_generer_facture_rate_limited()'::regprocedure),
    ('public.fn_declarer_virement(uuid,text)'::regprocedure),
    ('public.fn_mode_paiement_mission(uuid)'::regprocedure)
  )
  SELECT string_agg(r.signature::text, ', ' ORDER BY r.signature::text)
  INTO v_bad
  FROM reviewed r
  JOIN pg_proc p ON p.oid = r.signature
  LEFT JOIN private.security_definer_inventory i
    ON i.signature = p.oid::regprocedure::text
  WHERE p.prosecdef IS NOT TRUE
     OR p.proconfig IS NULL
     OR p.proconfig @> ARRAY['search_path=pg_catalog, public, auth']::text[] IS NOT TRUE
     OR has_function_privilege('anon', p.oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
     OR i.signature IS NULL
     OR i.definition_md5 <> md5(p.prosrc);

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY DEFINER/ACL/inventaire finances invalides : %', v_bad;
  END IF;

  WITH internal(signature) AS (VALUES
    ('public.fn_obligations_financieres_internal_20260801()'::regprocedure),
    ('public.fn_mes_factures_internal_20260801()'::regprocedure),
    ('public.fn_paiements_etablissement_internal_20260801()'::regprocedure),
    ('public.fn_detail_facture_internal_20260801(uuid)'::regprocedure),
    ('public.fn_declarer_paiement_soignant_internal_20260801(uuid,numeric,text,text,date,boolean)'::regprocedure),
    ('public.fn_modifier_reference_paiement_internal_20260801(uuid,text)'::regprocedure),
    ('public.fn_consulter_rib_soignant_internal_20260801(uuid)'::regprocedure),
    ('public.fn_generer_facture_mensuelle_internal_20260801(uuid)'::regprocedure)
  )
  SELECT string_agg(i.signature::text, ', ' ORDER BY i.signature::text)
  INTO v_bad
  FROM internal i
  JOIN pg_proc p ON p.oid = i.signature
  WHERE p.prosecdef
     OR has_function_privilege('anon', p.oid, 'EXECUTE')
     OR has_function_privilege('authenticated', p.oid, 'EXECUTE');

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Sous-routines financières internes exposées : %', v_bad;
  END IF;

  SELECT pg_get_functiondef('public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT LIKE '%fn_a_permission_etablissement(''paiement''%'
     OR v_definition LIKE '%v_mission.net_a_payer, 0) * 0.78%'
     OR v_definition NOT LIKE '%MONTANT_NET_SALARIE_SUPERIEUR_AU_BRUT%'
     OR v_definition NOT LIKE '%v_montant_du := round(p_montant, 2)%' THEN
    RAISE EXCEPTION 'Déclaration de paiement non bornée au rôle, au montant réel ou au plafond brut';
  END IF;

  SELECT pg_get_functiondef('public.fn_declarer_virement(uuid,text)'::regprocedure)
  INTO v_definition;
  IF v_definition NOT LIKE '%PAIEMENT_SEPA_AUTOMATIQUE%'
     OR v_definition NOT LIKE '%v_facture.est_secteur_public%'
     OR v_definition NOT LIKE '%fn_a_permission_etablissement(''paiement''%' THEN
    RAISE EXCEPTION 'Virement manuel non borné pour SEPA/Chorus/RBAC';
  END IF;

  SELECT string_agg(policyname, ', ' ORDER BY policyname)
  INTO v_bad
  FROM pg_policies
  WHERE schemaname = 'public'
    AND policyname IN ('pol_fact_select', 'fh_select_own', 'pol_paim_select', 'pol_transfer_select')
    AND COALESCE(qual, '') NOT LIKE '%lecture_paiement%';

  IF v_bad IS NOT NULL OR (
    SELECT count(*)
    FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname IN ('pol_fact_select', 'fh_select_own', 'pol_paim_select', 'pol_transfer_select')
  ) <> 4 THEN
    RAISE EXCEPTION 'Politiques SELECT financières incomplètes ou trop larges : %', COALESCE(v_bad, 'manquantes');
  END IF;

  SELECT qual
  INTO v_definition
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'partages_rib'
    AND policyname = 'pol_rib_select';
  IF v_definition IS NULL
     OR v_definition NOT LIKE '%fn_a_permission_etablissement(''paiement''%'
     OR v_definition NOT LIKE '%soignant_id%auth.uid%' THEN
    RAISE EXCEPTION 'Lecture des partages RIB insuffisamment bornée';
  END IF;
END;
$finance_rbac$;

ROLLBACK;
