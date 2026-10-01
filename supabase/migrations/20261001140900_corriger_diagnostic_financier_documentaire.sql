-- Source LIVE prod et staging identique, metadata seules lues le 1 octobre 2026.
-- Correction du diagnostic en lecture seule ; aucun montant ni droit modifié.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid='public.fn_diagnostic_coherence_financiere()'::regprocedure;
  IF md5(pg_get_functiondef(p.oid)) NOT IN ('6b17b9eb7fca289c92f80405fdb5c812','4e60ff931ff08d6759036d51f0ca0894')
    OR md5(p.prosrc) NOT IN ('ba4548f1a05a18f976eee4404039e0fc','c5b97d5373199cf3c7f7d44b661efb73')
    OR pg_get_userbyid(p.proowner) <> 'postgres'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 's'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, auth']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]
    OR NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i
      WHERE i.signature='fn_diagnostic_coherence_financiere()'
        AND i.categorie='ADMIN_EST_ADMIN_VALIDE' AND i.definition_md5=md5(p.prosrc))
    OR EXISTS(SELECT 1 FROM private.security_definer_inventory
      WHERE signature='public.fn_diagnostic_coherence_financiere()')
  THEN RAISE EXCEPTION 'Diagnostic financier : définition, droits ou inventaire inattendus'; END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_diagnostic_coherence_financiere()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_missions jsonb;
  v_factures jsonb;
  v_non_verifiables jsonb;
  v_factures_verifiees bigint;
  v_transfers jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  WITH ecarts AS (
    SELECT m.id, m.intitule, m.total_brut,
           round(COALESCE(m.taux_horaire_base_fige, m.taux_horaire_base) * m.duree_heures, 2) AS attendu
    FROM public.missions m
    WHERE m.total_brut IS NOT NULL
      AND COALESCE(m.taux_horaire_base_fige, m.taux_horaire_base) IS NOT NULL
      AND m.duree_heures IS NOT NULL
      AND abs(m.total_brut - COALESCE(m.taux_horaire_base_fige, m.taux_horaire_base) * m.duree_heures) > 0.5
  )
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'intitule', intitule, 'total_brut', total_brut,
      'attendu', attendu, 'ecart', total_brut - attendu
    ) ORDER BY intitule) FILTER (WHERE id IN (SELECT id FROM ecarts LIMIT 10)), '[]'::jsonb)
  ) INTO v_missions FROM ecarts;

  -- Une pièce rectifiée et une finale de période ne se comparent jamais
  -- au planning courant ni au net global de la mission.
  WITH pieces AS (
    SELECT fh.id, fh.numero_facture, fh.mission_id, fh.montant_ht,
      CASE
        WHEN fh.type_document = 'AVOIR' OR fh.nature_correction = 'COMPLEMENT'
          THEN 'CORRECTION_MONETAIRE'
        WHEN fh.quantite_heures_snapshot IS NULL OR fh.taux_horaire_snapshot IS NULL
          THEN 'SNAPSHOTS_INDISPONIBLES'
        WHEN fh.quantite_heures_snapshot <= 0 OR fh.taux_horaire_snapshot <= 0
          OR fh.quantite_heures_snapshot::text IN ('NaN', 'Infinity', '-Infinity')
          OR fh.taux_horaire_snapshot::text IN ('NaN', 'Infinity', '-Infinity')
          THEN 'SNAPSHOTS_INVALIDES'
        WHEN fh.montant_ht::text IN ('NaN', 'Infinity', '-Infinity')
          THEN 'MONTANT_INVALIDE'
        ELSE NULL
      END AS motif,
      round(fh.quantite_heures_snapshot * fh.taux_horaire_snapshot, 2) AS attendu
    FROM public.factures_honoraires fh
    WHERE fh.type_document IN ('FACTURE', 'AVOIR')
      AND fh.statut NOT IN ('BROUILLON', 'EN_GENERATION', 'REMPLACEE', 'ANNULEE', 'ERREUR_GENERATION')
  ), classes AS (
    SELECT *, motif IS NULL
      AND abs(montant_ht - attendu) > greatest(attendu * 0.01, 1.00) AS en_ecart
    FROM pieces
  )
  SELECT jsonb_build_object(
    'count', count(*) FILTER (WHERE en_ecart),
    'echantillon', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'facture_id', id, 'numero_facture', numero_facture,
      'mission_id', mission_id, 'montant_ht', montant_ht,
      'attendu_ht', attendu, 'mission_net', attendu, 'ecart', montant_ht - attendu
    ) ORDER BY numero_facture, id) FROM (
      SELECT * FROM classes WHERE en_ecart ORDER BY numero_facture, id LIMIT 10
    ) e), '[]'::jsonb)
  ), jsonb_build_object(
    'count', count(*) FILTER (WHERE motif IS NOT NULL),
    'echantillon', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'facture_id', id, 'numero_facture', numero_facture,
      'mission_id', mission_id, 'motif', motif
    ) ORDER BY numero_facture, id) FROM (
      SELECT * FROM classes WHERE motif IS NOT NULL ORDER BY numero_facture, id LIMIT 10
    ) n), '[]'::jsonb)
  ), count(*) FILTER (WHERE motif IS NULL)
  INTO v_factures, v_non_verifiables, v_factures_verifiees FROM classes;

  WITH orphelins AS (
    SELECT st.id, st.mission_id, st.montant_total
    FROM public.stripe_transfers st
    WHERE st.mission_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.factures_honoraires fh
        WHERE fh.mission_id = st.mission_id
          AND COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
          AND fh.statut NOT IN ('BROUILLON', 'ANNULEE', 'ERREUR_GENERATION')
      )
  )
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', COALESCE(jsonb_agg(jsonb_build_object(
      'transfer_id', id, 'mission_id', mission_id, 'montant_total', montant_total
    )) FILTER (WHERE id IN (SELECT id FROM orphelins LIMIT 10)), '[]'::jsonb)
  ) INTO v_transfers FROM orphelins;

  RETURN jsonb_build_object(
    'success', true,
    'controle_documentaire_version', 2,
    'factures_verifiees', v_factures_verifiees,
    'factures_non_verifiables', v_non_verifiables,
    'genere_le', now(),
    'missions_incoherentes', v_missions,
    'factures_ecart_mission', v_factures,
    'stripe_transfers_orphelins', v_transfers
  );
END;
$function$
;

UPDATE private.security_definer_inventory
SET definition_md5='c5b97d5373199cf3c7f7d44b661efb73'
WHERE signature='fn_diagnostic_coherence_financiere()'
  AND categorie='ADMIN_EST_ADMIN_VALIDE'
  AND definition_md5 IN ('ba4548f1a05a18f976eee4404039e0fc','c5b97d5373199cf3c7f7d44b661efb73');

DO $postflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid='public.fn_diagnostic_coherence_financiere()'::regprocedure;
  IF md5(pg_get_functiondef(p.oid)) <> '4e60ff931ff08d6759036d51f0ca0894' OR md5(p.prosrc) <> 'c5b97d5373199cf3c7f7d44b661efb73'
    OR pg_get_userbyid(p.proowner) <> 'postgres'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 's'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, auth']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]
    OR NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i
      WHERE i.signature='fn_diagnostic_coherence_financiere()'
        AND i.categorie='ADMIN_EST_ADMIN_VALIDE' AND i.definition_md5='c5b97d5373199cf3c7f7d44b661efb73')
  THEN RAISE EXCEPTION 'Diagnostic financier : postcondition inattendue'; END IF;
END;
$postflight$;
