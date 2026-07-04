-- 7b-B (Lot 7 v2 §2.1/F1) — la validation des présences devient un prérequis de
-- la facturation, décision produit 02/07/2026 :
--   « présence horodatée → validation établissement 1 tap → facture → release ».
--
-- Règles (bornées, jamais de blocage indéfini) :
--   - FINALE : bloquée tant qu'une présence à pointage COMPLET (départ pointé)
--     n'est pas validée — validation manuelle (fn_valider_presence) ou
--     auto-72h (fn_valider_presences_72h_auto, paramétrable). Une présence
--     contestée (motif_litige) bloque aussi : l'auto-72h la skippe, la facture
--     attend la résolution du litige.
--   - HEBDO (missions longues) : bloquée UNIQUEMENT sur présence contestée.
--     La présence-résumé n'est complète qu'en fin de mission : gater l'hebdo
--     sur la validation gèlerait le cash-flow hebdo du soignant. La finale
--     régularise.
--   - Présence sans départ pointé (oubli de check-out) : ne bloque pas la
--     FINALE (statu quo — l'auto-72h ne peut pas la couvrir, et les incidents
--     de cohérence la flaguent déjà côté admin).
--   - Aucune présence (facturation sur prévisionnel pur, plancher garanti) :
--     rien à valider → passe.

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_facturer(
  p_today date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_finales jsonb;
  v_hebdo jsonb;
BEGIN
  -- 1. Missions TERMINEE non encore facturées en finale.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'FINALE',
    'mission_id', m.id,
    'soignant_id', m.soignant_assigne_id,
    'etablissement_id', m.etablissement_id,
    'periode_debut', m.debut_le::date,
    'periode_fin', m.fin_le::date,
    'numero_semaine_iso', NULL,
    'annee_iso', NULL,
    'strategie_facturation', m.strategie_facturation::text,
    'est_facture_finale_mission', true
  )), '[]'::jsonb)
  INTO v_finales
  FROM missions m
  JOIN soignants s ON s.id = m.soignant_assigne_id
  WHERE m.statut = 'TERMINEE'
    AND m.fin_le::date < p_today
    AND m.type_contrat_applique = 'LIBERAL'
    AND COALESCE(s.mandat_facturation_signe, false) = true
    AND NOT EXISTS (
      SELECT 1 FROM factures_honoraires fh
      WHERE fh.mission_id = m.id
        AND fh.est_facture_finale_mission = true
        AND fh.statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')
    )
    AND EXISTS (
      SELECT 1 FROM mission_creneaux mc
      WHERE mc.mission_id = m.id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
    )
    -- 7b-B : gate validation des présences (voir en-tête de la migration).
    AND NOT EXISTS (
      SELECT 1 FROM presences p
      WHERE p.mission_id = m.id
        AND COALESCE(p.valide_par_etablissement, false) = false
        AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
    );

  -- 2. Missions HEBDO_ET_FINALE → semaines ISO closes non facturées.
  WITH semaines AS (
    SELECT
      m.id AS mission_id,
      m.soignant_assigne_id,
      m.etablissement_id,
      m.debut_le, m.fin_le,
      m.strategie_facturation,
      gs.lundi_semaine
    FROM missions m
    JOIN soignants s ON s.id = m.soignant_assigne_id
    CROSS JOIN LATERAL generate_series(
      date_trunc('week', m.debut_le)::date,
      LEAST(m.fin_le::date, p_today - INTERVAL '1 day')::date,
      '7 days'::interval
    ) AS gs(lundi_semaine)
    WHERE m.statut IN ('EN_COURS','TERMINEE')
      AND m.strategie_facturation = 'HEBDO_ET_FINALE'
      AND m.type_contrat_applique = 'LIBERAL'
      AND COALESCE(s.mandat_facturation_signe, false) = true
      -- 7b-B : une présence contestée gèle aussi les factures hebdo.
      AND NOT EXISTS (
        SELECT 1 FROM presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) = false
          AND p.motif_litige IS NOT NULL
      )
  ),
  semaines_closes AS (
    SELECT
      sm.*,
      (sm.lundi_semaine + INTERVAL '6 days')::date AS dimanche_semaine,
      EXTRACT(WEEK FROM sm.lundi_semaine)::smallint AS num_sem,
      EXTRACT(ISOYEAR FROM sm.lundi_semaine)::smallint AS ann_iso,
      GREATEST(sm.lundi_semaine::date, sm.debut_le::date) AS periode_d,
      LEAST((sm.lundi_semaine + INTERVAL '6 days')::date, sm.fin_le::date) AS periode_f
    FROM semaines sm
    WHERE (sm.lundi_semaine + INTERVAL '6 days')::date < p_today
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'HEBDO',
    'mission_id', sa.mission_id,
    'soignant_id', sa.soignant_assigne_id,
    'etablissement_id', sa.etablissement_id,
    'periode_debut', sa.periode_d,
    'periode_fin', sa.periode_f,
    'numero_semaine_iso', sa.num_sem,
    'annee_iso', sa.ann_iso,
    'strategie_facturation', sa.strategie_facturation::text,
    'est_facture_finale_mission', false
  )), '[]'::jsonb)
  INTO v_hebdo
  FROM semaines_closes sa
  WHERE NOT EXISTS (
    SELECT 1 FROM factures_honoraires fh
    WHERE fh.mission_id = sa.mission_id
      AND fh.annee_iso = sa.ann_iso
      AND fh.numero_semaine_iso = sa.num_sem
      AND fh.est_facture_finale_mission = false
      AND fh.statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')
  )
  AND EXISTS (
    SELECT 1 FROM mission_creneaux mc
    WHERE mc.mission_id = sa.mission_id
      AND (
        (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
        OR mc.type_creneau = 'PREVISIONNEL'
      )
      AND mc.debut::date <= sa.periode_f
      AND COALESCE(mc.fin::date, mc.debut::date) >= sa.periode_d
  );

  RETURN jsonb_build_object(
    'today', p_today,
    'finales', v_finales,
    'hebdo', v_hebdo,
    'total', jsonb_array_length(v_finales) + jsonb_array_length(v_hebdo)
  );
END;
$$;

-- iter3 (20260429560000) a révoqué authenticated : cron/service_role uniquement.
REVOKE EXECUTE ON FUNCTION public.fn_lister_missions_a_facturer(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lister_missions_a_facturer(date) TO service_role;

COMMENT ON FUNCTION public.fn_lister_missions_a_facturer(date) IS
  'Liste des missions à facturer pour p_today. 7b-B : la validation des présences (manuelle 1 tap ou auto-72h) est un prérequis de la facture FINALE ; une présence contestée gèle finale ET hebdo. Skip ABSENCE/SALARIE/sans mandat/sans pointage ni prévisionnel.';
