-- FIN-01 : chaque fraction de créneau appartient à une seule période.
-- Définition LIVE du 06/10/2026. Aucune facture passée ni aucun paiement modifié.
DO $source_guard$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_calculer_montant_periode(uuid,date,date)'::regprocedure)
      IS DISTINCT FROM 'e081b0e03baaa71aca630678749f90eb' THEN
    RAISE EXCEPTION 'FACTURATION_SOURCE_CHANGED_RECAPTURE_REQUIRED';
  END IF;
END;
$source_guard$;

CREATE OR REPLACE FUNCTION public.fn_calculer_montant_periode(p_mission_id uuid, p_periode_debut date DEFAULT NULL::date, p_periode_fin date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_mission RECORD;
  v_duree_periode numeric;
  v_duree_totale numeric;
  v_montant_ht_total numeric;
  v_montant_ht_periode numeric;
  v_ratio numeric;
  v_debut timestamptz;
  v_fin timestamptz;
  v_secondes_totales numeric;
  v_secondes_avant numeric;
  v_secondes_jusqua numeric;
BEGIN
  SELECT id, debut_le, fin_le, taux_horaire_base_fige,
         total_brut, net_a_payer
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable', p_mission_id;
  END IF;

  IF (p_periode_debut IS NULL) <> (p_periode_fin IS NULL)
     OR p_periode_fin < p_periode_debut
     OR (p_periode_debut IS NOT NULL AND
         (NOT isfinite(p_periode_debut) OR NOT isfinite(p_periode_fin))) THEN
    RAISE EXCEPTION 'PERIODE_FACTURATION_INVALIDE' USING ERRCODE='22023';
  END IF;

  -- Les dates des périodes existantes sont celles du circuit serveur UTC
  -- (listeur, cron et generate-invoice). Ne pas déplacer les factures acquises.
  v_debut := p_periode_debut::timestamp AT TIME ZONE 'UTC';
  v_fin := (p_periode_fin + 1)::timestamp AT TIME ZONE 'UTC';

  -- Conserver la règle globale MAX(prévisionnel, effectif), hors pauses.
  -- La même base s'applique à toutes les périodes : un MAX indépendant par
  -- semaine pourrait dépasser le MAX global même après découpage des nuits.
  WITH creneaux AS (
    SELECT type_creneau, debut, fin, EXTRACT(EPOCH FROM (fin-debut)) AS secondes
    FROM public.mission_creneaux
    WHERE mission_id=p_mission_id AND NOT est_pause AND fin > debut
      AND type_creneau IN ('PREVISIONNEL','EFFECTIF')
  ), bases AS (
    SELECT type_creneau, sum(secondes) AS total,
      sum(GREATEST(0, EXTRACT(EPOCH FROM (LEAST(fin, v_debut)-debut)))) AS avant,
      sum(GREATEST(0, EXTRACT(EPOCH FROM (LEAST(fin, v_fin)-debut)))) AS jusqua
    FROM creneaux GROUP BY type_creneau
  )
  SELECT total, avant, jusqua INTO v_secondes_totales, v_secondes_avant, v_secondes_jusqua
  FROM bases ORDER BY total DESC, (type_creneau='PREVISIONNEL') DESC LIMIT 1;

  v_secondes_totales := COALESCE(v_secondes_totales, 0);
  v_duree_totale := ROUND(v_secondes_totales / 3600, 2);
  v_montant_ht_total := COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0);

  IF p_periode_debut IS NULL THEN
    v_duree_periode := v_duree_totale;
    v_montant_ht_periode := v_montant_ht_total;
    v_ratio := 1.0;
  ELSIF v_secondes_totales = 0 THEN
    -- Une mission sans durée ne peut pas refacturer son total à chaque semaine.
    RAISE EXCEPTION 'DUREE_FACTURATION_INDISPONIBLE' USING ERRCODE='22023';
  ELSE
    v_duree_periode := ROUND(v_secondes_jusqua / 3600, 2)
                         - ROUND(v_secondes_avant / 3600, 2);
    v_ratio := (v_secondes_jusqua - v_secondes_avant) / v_secondes_totales;
    -- Différence de cumuls arrondis : la somme de périodes disjointes et
    -- contiguës conserve le total au centime, y compris trois tiers de 100 EUR.
    v_montant_ht_periode := ROUND(v_montant_ht_total * v_secondes_jusqua / v_secondes_totales, 2)
                            - ROUND(v_montant_ht_total * v_secondes_avant / v_secondes_totales, 2);
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
$function$;

-- Conserver la classification existante si cette fonction est recensée.
UPDATE private.security_definer_inventory i
SET definition_md5=md5(p.prosrc), recense_le=now(),
    justification=i.justification || ' FIN-01 : périodes disjointes, total conservé.'
FROM pg_proc p
WHERE p.oid='public.fn_calculer_montant_periode(uuid,date,date)'::regprocedure
  AND i.signature='fn_calculer_montant_periode(uuid,date,date)';
