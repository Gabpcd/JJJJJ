-- Partie 2 — Step C SQL : fn_verifier_pre_facturation étendue + 2 helpers
-- (fn_calculer_montant_periode, fn_cumul_factures_mission)

-- 1. fn_verifier_pre_facturation : ajout p_periode_debut + p_periode_fin
--    optionnels (NULL = comportement existant sur mission entière).
DROP FUNCTION IF EXISTS public.fn_verifier_pre_facturation(uuid);

CREATE OR REPLACE FUNCTION public.fn_verifier_pre_facturation(
  p_mission_id uuid,
  p_periode_debut date DEFAULT NULL,
  p_periode_fin date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_mission RECORD;
  v_nb_effectif_ouvert integer;
  v_nb_effectif_ferme integer;
  v_nb_previsionnel integer;
  v_duree_previsionnelle numeric;
  v_duree_effective numeric;
  v_ecart_heures numeric;
  v_ecart_pourcent numeric;
  v_source text;
  v_periode_active boolean;
BEGIN
  SELECT id, duree_heures, duree_heures_effective, statut, debut_le, fin_le
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_periode_active := (p_periode_debut IS NOT NULL AND p_periode_fin IS NOT NULL);

  SELECT
    COUNT(*) FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NULL),
    COUNT(*) FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL),
    COUNT(*) FILTER (WHERE type_creneau='PREVISIONNEL')
  INTO v_nb_effectif_ouvert, v_nb_effectif_ferme, v_nb_previsionnel
  FROM mission_creneaux
  WHERE mission_id = p_mission_id
    AND (
      NOT v_periode_active
      OR (debut::date <= p_periode_fin AND COALESCE(fin::date, debut::date) >= p_periode_debut)
    );

  IF v_nb_effectif_ouvert > 0 THEN
    RAISE EXCEPTION 'Facturation bloquée : % créneau(x) effectif(s) ouvert(s) sur la période. Utilisez fn_declarer_fin_retroactive.',
      v_nb_effectif_ouvert USING ERRCODE = 'check_violation';
  END IF;

  SELECT
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
             FILTER (WHERE type_creneau='PREVISIONNEL' AND NOT est_pause)::numeric, 2), 0),
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
             FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)::numeric, 2), 0)
  INTO v_duree_previsionnelle, v_duree_effective
  FROM mission_creneaux
  WHERE mission_id = p_mission_id
    AND (
      NOT v_periode_active
      OR (debut::date <= p_periode_fin AND COALESCE(fin::date, debut::date) >= p_periode_debut)
    );

  v_ecart_heures := ROUND(ABS(v_duree_previsionnelle - v_duree_effective), 2);
  IF v_duree_previsionnelle > 0 THEN
    v_ecart_pourcent := ROUND(v_ecart_heures / v_duree_previsionnelle * 100, 2);
  ELSE
    v_ecart_pourcent := 0;
  END IF;

  IF v_duree_previsionnelle > 0 AND v_duree_effective > v_duree_previsionnelle * 1.10 THEN
    RAISE EXCEPTION 'Facturation bloquée : effectif %h dépasse prévisionnel %h de plus de 10 pct (écart % pct). Validation étab/admin requise.',
      v_duree_effective, v_duree_previsionnelle, v_ecart_pourcent
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_duree_effective = 0 AND v_duree_previsionnelle = 0 THEN
    RAISE EXCEPTION 'Facturation bloquée : aucun créneau (effectif ni prévisionnel) sur la période. Mission probablement absente — passer en statut ABSENCE ou décaler la période.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_source := CASE
    WHEN v_duree_effective > 0 AND v_duree_effective >= v_duree_previsionnelle THEN 'EFFECTIF'
    WHEN v_duree_effective = 0 AND v_duree_previsionnelle > 0 THEN 'PREVISIONNEL_PLANCHER'
    ELSE 'PREVISIONNEL'
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'mode_periode', v_periode_active,
    'periode_debut', p_periode_debut,
    'periode_fin', p_periode_fin,
    'source_facturation', v_source,
    'duree_previsionnelle', v_duree_previsionnelle,
    'duree_effective', v_duree_effective,
    'duree_facturee', GREATEST(v_duree_previsionnelle, v_duree_effective),
    'ecart_heures', v_ecart_heures,
    'ecart_pourcent', v_ecart_pourcent,
    'nb_creneaux_effectif_fermes', v_nb_effectif_ferme,
    'nb_creneaux_previsionnels', v_nb_previsionnel
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_verifier_pre_facturation(uuid, date, date)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_verifier_pre_facturation(uuid, date, date) IS
  'Garde-fou pré-facturation. Si p_periode_* NULL → vérifie mission entière (FINALE_UNIQUE). Sinon → vérifie sur période [p_periode_debut, p_periode_fin]. Block si créneau effectif ouvert / écart > 10 pct / aucun créneau. Retourne source EFFECTIF / PREVISIONNEL_PLANCHER (cas absence) / PREVISIONNEL.';

-- 2. fn_calculer_montant_periode : montant HT pondéré sur période
CREATE OR REPLACE FUNCTION public.fn_calculer_montant_periode(
  p_mission_id uuid,
  p_periode_debut date DEFAULT NULL,
  p_periode_fin date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_mission RECORD;
  v_duree_periode numeric;
  v_duree_totale numeric;
  v_montant_ht_total numeric;
  v_montant_ht_periode numeric;
  v_ratio numeric;
BEGIN
  SELECT id, debut_le, fin_le, taux_horaire_base_fige,
         total_brut, net_a_payer
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable', p_mission_id;
  END IF;

  SELECT COALESCE(ROUND(GREATEST(
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='PREVISIONNEL' AND NOT est_pause),
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)
  )::numeric, 2), 0)
  INTO v_duree_periode
  FROM mission_creneaux
  WHERE mission_id = p_mission_id
    AND (
      p_periode_debut IS NULL
      OR (debut::date <= p_periode_fin AND COALESCE(fin::date, debut::date) >= p_periode_debut)
    );

  SELECT COALESCE(ROUND(GREATEST(
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='PREVISIONNEL' AND NOT est_pause),
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)
  )::numeric, 2), 0)
  INTO v_duree_totale
  FROM mission_creneaux
  WHERE mission_id = p_mission_id;

  v_montant_ht_total := COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0);

  IF p_periode_debut IS NULL OR v_duree_totale = 0 THEN
    v_montant_ht_periode := v_montant_ht_total;
    v_ratio := 1.0;
  ELSE
    v_ratio := v_duree_periode / v_duree_totale;
    v_montant_ht_periode := ROUND(v_montant_ht_total * v_ratio, 2);
  END IF;

  RETURN jsonb_build_object(
    'mission_id', p_mission_id,
    'periode_debut', p_periode_debut,
    'periode_fin', p_periode_fin,
    'duree_periode_heures', v_duree_periode,
    'duree_totale_mission_heures', v_duree_totale,
    'ratio_periode', v_ratio,
    'montant_ht_total_mission', v_montant_ht_total,
    'montant_ht_periode', v_montant_ht_periode,
    'taux_horaire_base_fige', v_mission.taux_horaire_base_fige
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_montant_periode(uuid, date, date)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_calculer_montant_periode(uuid, date, date) IS
  'Partie 2 — calcul montant HT pondéré sur période (créneaux qui chevauchent). Si périodes NULL → mission entière. Approximation : montant_ht_total × (duree_periode / duree_totale_mission). Précision suffisante pour MVP hebdo.';

-- 3. fn_cumul_factures_mission : cumul facturé jusqu'à p_jusqu_au
CREATE OR REPLACE FUNCTION public.fn_cumul_factures_mission(
  p_mission_id uuid,
  p_jusqu_au date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_cumul_ht numeric;
  v_cumul_ttc numeric;
  v_nb_factures integer;
BEGIN
  SELECT
    COALESCE(SUM(montant_ht), 0),
    COALESCE(SUM(montant_ttc), 0),
    COUNT(*)
  INTO v_cumul_ht, v_cumul_ttc, v_nb_factures
  FROM factures_honoraires
  WHERE mission_id = p_mission_id
    AND statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION','EN_GENERATION')
    AND type_document = 'FACTURE'
    AND (p_jusqu_au IS NULL OR periode_fin <= p_jusqu_au);

  RETURN jsonb_build_object(
    'mission_id', p_mission_id,
    'jusqu_au', p_jusqu_au,
    'cumul_ht', v_cumul_ht,
    'cumul_ttc', v_cumul_ttc,
    'nb_factures', v_nb_factures
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cumul_factures_mission(uuid, date)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_cumul_factures_mission(uuid, date) IS
  'Partie 2 — cumul HT/TTC + nombre de factures FACTURE non-ANNULEE/REMPLACEE/ERREUR/EN_GENERATION pour une mission jusqu''à p_jusqu_au (default toutes). Utilisé par generate-invoice pour mention cumul dans le PDF hebdo et finale partielle.';

NOTIFY pgrst, 'reload schema';
