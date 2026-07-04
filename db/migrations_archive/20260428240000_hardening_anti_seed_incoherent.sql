-- Hardening anti-seed-incohérent (cf. docs/tech-debt.md).
--
-- À l'exécution de cette migration, deux protections sont DÉJÀ EN PLACE
-- en prod (vérifiées par audit MCP) — donc cette migration ajoute
-- uniquement la 3e couche manquante :
--
--   1. ✅ DÉJÀ EN PLACE : trigger BEFORE INSERT/UPDATE sur
--      factures_honoraires (`fn_anti_seed_facture_honoraire`).
--      Seuil 0.50€ entre montant_ht et mission.net_a_payer. Bypass via
--      contexte `jolene.generate_invoice_context='true'` ou override
--      admin via `jolene.admin_seed_override_reason`. Les overrides
--      sont audités dans `journaux_audit` action `OVERRIDE_ANTI_SEED`.
--
--   2. ✅ DÉJÀ EN PLACE : trigger sur missions (`fn_anti_seed_mission`).
--      Vérifie que `total_brut`/`net_a_payer` sont cohérents avec
--      `taux × heures + majorations` ET que `taux`/`heures` sont
--      renseignés. Mêmes mécanismes de bypass que ci-dessus.
--
--   3. AJOUTÉ ICI : RPC `fn_diagnostic_coherence_financiere()`,
--      admin-only, retourne JSONB avec count + samples des écarts pour :
--        - missions où total_brut diverge de taux × heures + majorations
--        - factures_honoraires où montant_ht diverge de mission.net_a_payer
--        - stripe_transfers orphelins (mission sans facture associée)
--      Utilisable depuis dashboard admin, scripts ops, ou cron mensuel.

CREATE OR REPLACE FUNCTION public.fn_diagnostic_coherence_financiere()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, extensions
AS $$
DECLARE
  v_missions_incoherent jsonb;
  v_factures_ecart jsonb;
  v_transfers_orphelins jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  -- 1. Missions où total_brut diverge de taux × heures + majorations
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'intitule', intitule, 'total_brut', total_brut,
        'attendu', taux_horaire_base * duree_heures
          + COALESCE(montant_majoration_nuit,0)
          + COALESCE(montant_majoration_dimanche,0)
          + COALESCE(montant_majoration_ferie,0),
        'ecart', total_brut - (
          taux_horaire_base * duree_heures
          + COALESCE(montant_majoration_nuit,0)
          + COALESCE(montant_majoration_dimanche,0)
          + COALESCE(montant_majoration_ferie,0)
        )
      ))
      FROM missions m2
      WHERE total_brut IS NOT NULL AND taux_horaire_base IS NOT NULL AND duree_heures IS NOT NULL
        AND abs(total_brut - (
          taux_horaire_base * duree_heures
          + COALESCE(montant_majoration_nuit,0)
          + COALESCE(montant_majoration_dimanche,0)
          + COALESCE(montant_majoration_ferie,0)
        )) > 0.5
      LIMIT 10
    )
  ) INTO v_missions_incoherent
  FROM missions m
  WHERE total_brut IS NOT NULL AND taux_horaire_base IS NOT NULL AND duree_heures IS NOT NULL
    AND abs(total_brut - (
      taux_horaire_base * duree_heures
      + COALESCE(montant_majoration_nuit,0)
      + COALESCE(montant_majoration_dimanche,0)
      + COALESCE(montant_majoration_ferie,0)
    )) > 0.5;

  -- 2. Factures où montant_ht diverge de mission.net_a_payer (>1% ou >1€)
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', (
      SELECT jsonb_agg(jsonb_build_object(
        'facture_id', fh.id, 'numero_facture', fh.numero_facture,
        'mission_id', m.id, 'montant_ht', fh.montant_ht,
        'mission_net', m.net_a_payer,
        'ecart', fh.montant_ht - COALESCE(m.net_a_payer, 0)
      ))
      FROM factures_honoraires fh
      JOIN missions m ON m.id = fh.mission_id
      WHERE COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
        AND fh.statut NOT IN ('BROUILLON','REMPLACEE','ANNULEE')
        AND m.net_a_payer IS NOT NULL AND m.net_a_payer > 0
        AND abs(fh.montant_ht - m.net_a_payer) > GREATEST(m.net_a_payer * 0.01, 1.00)
      LIMIT 10
    )
  ) INTO v_factures_ecart
  FROM factures_honoraires fh
  JOIN missions m ON m.id = fh.mission_id
  WHERE COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
    AND fh.statut NOT IN ('BROUILLON','REMPLACEE','ANNULEE')
    AND m.net_a_payer IS NOT NULL AND m.net_a_payer > 0
    AND abs(fh.montant_ht - m.net_a_payer) > GREATEST(m.net_a_payer * 0.01, 1.00);

  -- 3. Transfers Stripe orphelins (mission qui n'a plus de facture)
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', (
      SELECT jsonb_agg(jsonb_build_object(
        'transfer_id', st.id, 'mission_id', st.mission_id,
        'montant_total', st.montant_total
      ))
      FROM stripe_transfers st2
      WHERE st2.mission_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM factures_honoraires fh
          WHERE fh.mission_id = st2.mission_id
            AND COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
            AND fh.statut NOT IN ('BROUILLON','ANNULEE')
        )
      LIMIT 10
    )
  ) INTO v_transfers_orphelins
  FROM stripe_transfers st
  WHERE st.mission_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM factures_honoraires fh
      WHERE fh.mission_id = st.mission_id
        AND COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
        AND fh.statut NOT IN ('BROUILLON','ANNULEE')
    );

  RETURN jsonb_build_object(
    'success', true,
    'genere_le', now(),
    'missions_incoherentes', v_missions_incoherent,
    'factures_ecart_mission', v_factures_ecart,
    'stripe_transfers_orphelins', v_transfers_orphelins
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_diagnostic_coherence_financiere() TO authenticated;

NOTIFY pgrst, 'reload schema';
