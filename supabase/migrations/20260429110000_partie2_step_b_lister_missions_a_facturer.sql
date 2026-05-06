-- Partie 2 — Step B : RPC fn_lister_missions_a_facturer
-- Retourne la liste des missions à facturer pour un jour donné selon la
-- stratégie figée + l'avancement de la semaine ISO + les garde-fous D9.
--
-- Logique :
--   1. Missions TERMINEE (fin avant aujourd'hui) jamais facturées en finale
--      → mode FINALE pour la période [debut_le, fin_le]
--   2. Missions EN_COURS ou TERMINEE avec strategie HEBDO_ET_FINALE et
--      semaines ISO terminées (dimanche < today) non encore facturées
--      → mode HEBDO pour chaque semaine close, période bornée à [debut_le, fin_le]
--   3. Skip statut ABSENCE (par WHERE statut IN ('TERMINEE','EN_COURS'))
--   4. Skip type_contrat_applique = SALARIE (D7 inchangé) — l'enum
--      type_contrat_applique_enum n'a que LIBERAL/SALARIE.
--   5. Skip soignant sans mandat actif
--   6. Skip si ni pointage (EFFECTIF avec fin) ni créneau prévisionnel
--      sur la période (D9)

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

GRANT EXECUTE ON FUNCTION public.fn_lister_missions_a_facturer(date)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_lister_missions_a_facturer(date) IS
  'Partie 2 — liste des missions à facturer pour p_today (default CURRENT_DATE). Retourne JSONB { today, finales[], hebdo[], total }. Mode FINALE pour missions TERMINEE non facturées + LIBERAL + mandat signé + au moins un créneau effectif fermé ou prévisionnel. Mode HEBDO pour missions EN_COURS/TERMINEE strategie HEBDO_ET_FINALE avec semaine ISO close non facturée. Skip ABSENCE/SALARIE/sans mandat/sans pointage ni prévisionnel.';

NOTIFY pgrst, 'reload schema';
