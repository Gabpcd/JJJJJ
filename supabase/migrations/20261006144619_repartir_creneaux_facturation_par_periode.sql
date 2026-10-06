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
  v_borne_debut timestamptz;
  v_borne_fin timestamptz;
  v_historique_incompatible boolean;
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

  SELECT LEAST(v_mission.debut_le, min(debut)), GREATEST(v_mission.fin_le, max(fin))
  INTO v_borne_debut, v_borne_fin
  FROM public.mission_creneaux
  WHERE mission_id=p_mission_id AND NOT est_pause AND fin > debut
    AND type_creneau IN ('PREVISIONNEL','EFFECTIF');

  -- Les dates des périodes existantes sont celles du circuit serveur UTC
  -- (listeur, cron et generate-invoice). Ne pas déplacer les factures acquises.
  v_debut := p_periode_debut::timestamp AT TIME ZONE 'UTC';
  v_fin := (p_periode_fin + 1)::timestamp AT TIME ZONE 'UTC';

  -- Conserver la règle globale MAX(prévisionnel, effectif), hors pauses.
  -- Différence des MAX cumulés, et non MAX de chaque période ou choix d'une
  -- base globale : les heures effectives d'une semaine close restent acquises
  -- quand les pointages des semaines suivantes arrivent.
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
  SELECT max(total), max(avant), max(jusqua)
  INTO v_secondes_totales, v_secondes_avant, v_secondes_jusqua FROM bases;

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

  IF p_periode_debut IS NOT NULL THEN
    -- Une pièce ancienne peut avoir été produite par le calcul défectueux ou
    -- avant une correction des heures/tarifs. Refuser une suite incohérente ;
    -- la régularisation passe par le circuit documentaire existant, jamais par
    -- une modification silencieuse des factures déjà émises.
    -- Solde par période : les compléments et avoirs régularisent sans changer
    -- les snapshots historiques. Le lien predecessor chaîne aussi les semaines.
    WITH historique AS (
      SELECT round(sum(CASE WHEN fh.type_document='AVOIR' THEN -fh.montant_ht ELSE fh.montant_ht END),2) AS montant_ht,
        fh.periode_debut::timestamp AT TIME ZONE 'UTC' AS debut,
        (fh.periode_fin+1)::timestamp AT TIME ZONE 'UTC' AS fin
      FROM public.factures_honoraires fh
      WHERE fh.mission_id=p_mission_id AND fh.type_document IN ('FACTURE','AVOIR')
        AND fh.statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION')
        AND (fh.periode_fin < p_periode_debut OR fh.periode_debut > p_periode_fin)
      GROUP BY fh.periode_debut,fh.periode_fin
    )
    SELECT EXISTS (
      SELECT 1 FROM historique h
      CROSS JOIN LATERAL (
        SELECT max(avant) AS avant, max(jusqua) AS jusqua FROM (
          SELECT
            sum(GREATEST(0,EXTRACT(EPOCH FROM (LEAST(mc.fin,h.debut)-mc.debut)))) AS avant,
            sum(GREATEST(0,EXTRACT(EPOCH FROM (LEAST(mc.fin,h.fin)-mc.debut)))) AS jusqua
          FROM public.mission_creneaux mc
          WHERE mc.mission_id=p_mission_id AND NOT mc.est_pause AND mc.fin > mc.debut
            AND mc.type_creneau IN ('PREVISIONNEL','EFFECTIF')
          GROUP BY mc.type_creneau
        ) par_type
      ) cumuls
      WHERE h.montant_ht IS DISTINCT FROM
        ROUND(v_montant_ht_total*cumuls.jusqua/v_secondes_totales,2)
          - ROUND(v_montant_ht_total*cumuls.avant/v_secondes_totales,2)

    ) INTO v_historique_incompatible;
    IF v_historique_incompatible THEN
      RAISE EXCEPTION 'FACTURATION_HISTORIQUE_A_RECONCILIER'
        USING ERRCODE='23514', HINT='Vérifier et régulariser les pièces existantes avant une nouvelle période.';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'mission_id', p_mission_id,
    'periode_debut', p_periode_debut,
    'periode_fin', p_periode_fin,
    'borne_debut_facturation', (v_borne_debut AT TIME ZONE 'UTC')::date,
    'borne_fin_facturation', (v_borne_fin AT TIME ZONE 'UTC')::date,
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

-- Inclure une arrivée anticipée ou un départ après minuit au-delà du planning.
-- Sinon le découpage supprimerait une fraction que le listeur ne proposerait jamais.
DO $lister_source_guard$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_lister_missions_a_facturer(date)'::regprocedure)
      IS DISTINCT FROM 'c01e9f584cdc9f0806fcc3455657cdd9' THEN
    RAISE EXCEPTION 'LISTEUR_SOURCE_CHANGED_RECAPTURE_REQUIRED';
  END IF;
END;
$lister_source_guard$;

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_facturer(p_today date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET timezone TO 'UTC'
AS $function$
DECLARE
  v_finales jsonb;
  v_hebdo jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'FINALE',
    'mission_id', m.id,
    'soignant_id', m.soignant_assigne_id,
    'etablissement_id', m.etablissement_id,
    'periode_debut', CASE
      WHEN m.strategie_facturation = 'HEBDO_ET_FINALE'
        THEN COALESCE(derniere_periode.prochain_debut, bornes.debut_le::date)
      ELSE bornes.debut_le::date
    END,
    'periode_fin', bornes.fin_le::date,
    'numero_semaine_iso', NULL,
    'annee_iso', NULL,
    'strategie_facturation', m.strategie_facturation::text,
    'est_facture_finale_mission', true
  )), '[]'::jsonb)
  INTO v_finales
  FROM public.missions m
  CROSS JOIN LATERAL (
    SELECT LEAST(m.debut_le,min(mc.debut)) AS debut_le,
           GREATEST(m.fin_le,max(mc.fin)) AS fin_le
    FROM public.mission_creneaux mc
    WHERE mc.mission_id=m.id AND NOT mc.est_pause AND mc.fin > mc.debut
      AND mc.type_creneau IN ('PREVISIONNEL','EFFECTIF')
  ) bornes
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  LEFT JOIN LATERAL (
    SELECT (max(fh.periode_fin) + 1)::date AS prochain_debut
    FROM public.factures_honoraires fh
    WHERE fh.mission_id = m.id
      AND fh.type_document = 'FACTURE'
      AND fh.est_facture_finale_mission IS FALSE
      AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ) derniere_periode ON true
  WHERE m.statut = 'TERMINEE'
    AND COALESCE(m.est_arret_maladie, false) IS FALSE
    AND bornes.fin_le::date < p_today
    AND m.type_contrat_applique = 'LIBERAL'
    AND m.mode_remuneration = 'TAUX_HORAIRE'
    AND COALESCE(s.mandat_facturation_signe, false) IS TRUE
    AND s.mandat_facturation_version = '1.4'
    AND s.statut_tva_honoraires IN ('FRANCHISE_EN_BASE', 'REDEVABLE_TVA')
    AND m.statut_validation_tva = 'CONFIRMEE'
    AND m.nature_tva_prestation IN (
      'SOIN_THERAPEUTIQUE_EXONERE', 'PRESTATION_TAXABLE'
    )
    AND m.nature_tva_confirmee_soignant = m.nature_tva_prestation
    AND m.nature_tva_confirmee_par = m.soignant_assigne_id
    AND NOT EXISTS (
      SELECT 1 FROM public.missions r
      WHERE r.remplacement_de_mission_id = m.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.factures_honoraires fh
      WHERE fh.mission_id = m.id
        AND fh.est_facture_finale_mission IS TRUE
        AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    )
    AND (
      m.strategie_facturation = 'FINALE_UNIQUE'
      OR COALESCE(derniere_periode.prochain_debut, bornes.debut_le::date) <= bornes.fin_le::date
    )
    AND EXISTS (
      SELECT 1 FROM public.mission_creneaux mc
      WHERE mc.mission_id = m.id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.presences p
      WHERE p.mission_id = m.id
        AND COALESCE(p.valide_par_etablissement, false) IS FALSE
        AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
    );

  WITH semaines AS (
    SELECT
      m.id AS mission_id,
      m.soignant_assigne_id,
      m.etablissement_id,
      bornes.debut_le,
      bornes.fin_le,
      m.strategie_facturation,
      gs.lundi_semaine
    FROM public.missions m
  CROSS JOIN LATERAL (
    SELECT LEAST(m.debut_le,min(mc.debut)) AS debut_le,
           GREATEST(m.fin_le,max(mc.fin)) AS fin_le
    FROM public.mission_creneaux mc
    WHERE mc.mission_id=m.id AND NOT mc.est_pause AND mc.fin > mc.debut
      AND mc.type_creneau IN ('PREVISIONNEL','EFFECTIF')
  ) bornes
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    CROSS JOIN LATERAL generate_series(
      date_trunc('week', bornes.debut_le)::date,
      least(bornes.fin_le::date, p_today - interval '1 day')::date,
      '7 days'::interval
    ) AS gs(lundi_semaine)
    WHERE m.statut IN ('EN_COURS', 'TERMINEE')
      AND COALESCE(m.est_arret_maladie, false) IS FALSE
      AND m.strategie_facturation = 'HEBDO_ET_FINALE'
      AND m.type_contrat_applique = 'LIBERAL'
      AND m.mode_remuneration = 'TAUX_HORAIRE'
      AND COALESCE(s.mandat_facturation_signe, false) IS TRUE
      AND s.mandat_facturation_version = '1.4'
      AND s.statut_tva_honoraires IN ('FRANCHISE_EN_BASE', 'REDEVABLE_TVA')
      AND m.statut_validation_tva = 'CONFIRMEE'
      AND m.nature_tva_prestation IN (
        'SOIN_THERAPEUTIQUE_EXONERE', 'PRESTATION_TAXABLE'
      )
      AND m.nature_tva_confirmee_soignant = m.nature_tva_prestation
      AND m.nature_tva_confirmee_par = m.soignant_assigne_id
      AND NOT EXISTS (
        SELECT 1 FROM public.missions r
        WHERE r.remplacement_de_mission_id = m.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) IS FALSE
          AND p.motif_litige IS NOT NULL
      )
  ),
  semaines_closes AS (
    SELECT
      sm.*,
      (sm.lundi_semaine + interval '6 days')::date AS dimanche_semaine,
      extract(week FROM sm.lundi_semaine)::smallint AS num_sem,
      extract(isoyear FROM sm.lundi_semaine)::smallint AS ann_iso,
      greatest(sm.lundi_semaine::date, sm.debut_le::date) AS periode_d,
      least((sm.lundi_semaine + interval '6 days')::date, sm.fin_le::date) AS periode_f
    FROM semaines sm
    WHERE (sm.lundi_semaine + interval '6 days')::date < p_today
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
    SELECT 1 FROM public.factures_honoraires fh
    WHERE fh.mission_id = sa.mission_id
      AND fh.annee_iso = sa.ann_iso
      AND fh.numero_semaine_iso = sa.num_sem
      AND fh.est_facture_finale_mission IS FALSE
      AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  )
    AND EXISTS (
      SELECT 1 FROM public.mission_creneaux mc
      WHERE mc.mission_id = sa.mission_id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
        AND NOT mc.est_pause
        AND mc.debut < (sa.periode_f+1)::timestamp AT TIME ZONE 'UTC'
        AND mc.fin > sa.periode_d::timestamp AT TIME ZONE 'UTC'
    );

  RETURN jsonb_build_object(
    'today', p_today,
    'finales', v_finales,
    'hebdo', v_hebdo,
    'total', jsonb_array_length(v_finales) + jsonb_array_length(v_hebdo)
  );
END;
$function$;
UPDATE private.security_definer_inventory i
SET definition_md5=md5(p.prosrc),recense_le=now(),
 justification=i.justification || ' FIN-01 : inclure les bornes des créneaux effectifs.'
FROM pg_proc p
WHERE p.oid='public.fn_lister_missions_a_facturer(date)'::regprocedure
 AND i.signature='fn_lister_missions_a_facturer(date)';
