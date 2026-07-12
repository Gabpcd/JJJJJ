-- Lot 19 — Cockpit fondateur à source unique (métriques d'argent)
--
-- Objectif (passation MODE AUTONOME §3) : UNE RPC par métrique d'argent, lue par
-- le KPI ET la carte (jamais un champ dénormalisé qui diverge), montants HT/TTC
-- explicites, données de test (est_compte_test) séparées du réel, compteur
-- « établissements à valider » = count réel de la file de vérification.
--
-- Contexte prod tracé (12/07/2026) — divergences constatées :
--   • « Encaissé » avait 3 définitions : factures PAYEE (HT) / missions
--     commission_facturee / paiements_mission TTC (part soignant incluse).
--   • « GMV » 2-3 sources : missions.total_brut (avec seeds) vs stripe_transfers
--     vs fn_admin_cockpit_fondateur — aucune ne filtrait les comptes test.
--   • « Commission » 3 sources ; fn_admin_kpi bucketise au fin_le,
--     fn_admin_cockpit_fondateur au debut_le → chiffres différents.
--   • Compteur étab à valider : file réelle (rattachement_verifie=false AND
--     statut<>REJETE) = 10 vs fn_admin_kpi.etab_en_attente (statut='EN_ATTENTE') = 6.
--
-- Rail argent canonique : missions (accrual commission/GMV) + factures PAYEE et
-- paiements_escrow débité (cash « encaissé »). Une mission/facture/escrow est
-- « réelle » si NI l'établissement NI le soignant n'est un compte test.
-- Prédicat cash robuste = debite_le IS NOT NULL (indépendant du libellé de statut).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Source unique de TOUTES les métriques d'argent du cockpit fondateur.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_admin_metriques_argent()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
  debut_mois timestamptz := date_trunc('month', now());
  fin_mois   timestamptz := date_trunc('month', now()) + INTERVAL '1 month';
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès réservé aux administrateurs');
  END IF;

  WITH m AS (
    SELECT mi.montant_commission_ht, mi.montant_commission_tva, mi.total_brut, mi.fin_le,
           NOT (COALESCE(e.est_compte_test,false) OR COALESCE(s.est_compte_test,false)) AS est_reel
    FROM missions mi
    LEFT JOIN etablissements e ON e.id = mi.etablissement_id
    LEFT JOIN soignants s ON s.id = mi.soignant_assigne_id
    WHERE mi.statut = 'TERMINEE'
  ),
  f AS (
    SELECT fa.montant_ht, fa.montant_ttc, fa.statut,
           NOT COALESCE(e.est_compte_test,false) AS est_reel
    FROM factures fa
    LEFT JOIN etablissements e ON e.id = fa.etablissement_id
  ),
  esc AS (
    SELECT pe.commission_cents, pe.debite_le,
           NOT (COALESCE(e.est_compte_test,false) OR COALESCE(s.est_compte_test,false)) AS est_reel
    FROM paiements_escrow pe
    LEFT JOIN etablissements e ON e.id = pe.etablissement_id
    LEFT JOIN soignants s ON s.id = pe.soignant_id
  )
  SELECT jsonb_build_object(
    -- ══ COMMISSION JOLENE (CA) — HT — accrual sur missions TERMINEE ══
    'commission', jsonb_build_object(
      'unite', 'HT',
      'total_reel', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE est_reel),
      'total_test', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE NOT est_reel),
      'mois_reel',  (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE est_reel     AND fin_le>=debut_mois AND fin_le<fin_mois),
      'mois_test',  (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE NOT est_reel AND fin_le>=debut_mois AND fin_le<fin_mois),
      'tva_reel',   (SELECT COALESCE(SUM(montant_commission_tva),0) FROM m WHERE est_reel)
    ),
    -- ══ ENCAISSÉ (commission réellement perçue) — cash : factures PAYEE + escrow débité ══
    -- escrow.commission_cents compté en HT (la TVA sur commission est portée par la facture émise séparément).
    'encaisse', jsonb_build_object(
      'ht_reel',  ROUND((SELECT COALESCE(SUM(montant_ht),0)  FROM f   WHERE statut='PAYEE' AND est_reel)
                + (SELECT COALESCE(SUM(commission_cents),0)/100.0 FROM esc WHERE debite_le IS NOT NULL AND est_reel), 2),
      'ttc_reel', ROUND((SELECT COALESCE(SUM(montant_ttc),0) FROM f   WHERE statut='PAYEE' AND est_reel)
                + (SELECT COALESCE(SUM(commission_cents),0)/100.0 FROM esc WHERE debite_le IS NOT NULL AND est_reel), 2),
      'ht_test',  ROUND((SELECT COALESCE(SUM(montant_ht),0)  FROM f   WHERE statut='PAYEE' AND NOT est_reel)
                + (SELECT COALESCE(SUM(commission_cents),0)/100.0 FROM esc WHERE debite_le IS NOT NULL AND NOT est_reel), 2)
    ),
    -- ══ FACTURABLE (plafond commission encaissable, HT) = commission des missions TERMINEE ══
    'facturable', jsonb_build_object(
      'unite', 'HT',
      'ht_reel', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE est_reel),
      'ht_test', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE NOT est_reel)
    ),
    -- ══ GMV (volume brut transité = honoraires bruts des missions) ══
    'gmv', jsonb_build_object(
      'unite', 'brut',
      'total_reel', (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE est_reel),
      'total_test', (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE NOT est_reel),
      'mois_reel',  (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE est_reel     AND fin_le>=debut_mois AND fin_le<fin_mois),
      'mois_test',  (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE NOT est_reel AND fin_le>=debut_mois AND fin_le<fin_mois)
    ),
    -- ══ Divers cockpit ══
    'nb_missions_terminees_reel', (SELECT COUNT(*) FROM m WHERE est_reel),
    'nb_missions_terminees_test', (SELECT COUNT(*) FROM m WHERE NOT est_reel),
    -- Compteur « établissements à valider » = MÊME filtre que la file de travail
    -- (fn_admin_lister_etablissements_a_verifier) — source unique du KPI et de l'alerte.
    'etab_a_valider', (SELECT COUNT(*) FROM etablissements
        WHERE supprime_le IS NULL AND COALESCE(rattachement_verifie,false)=false AND COALESCE(statut_verification,'')<>'REJETE'),
    'a_des_donnees_test', (SELECT EXISTS(SELECT 1 FROM etablissements WHERE COALESCE(est_compte_test,false))
                              OR EXISTS(SELECT 1 FROM soignants WHERE COALESCE(est_compte_test,false)))
  ) INTO result;

  RETURN result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_metriques_argent() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) fn_admin_kpi — réaligne UNIQUEMENT etab_en_attente sur le filtre de la file
--    de travail (rattachement_verifie=false AND statut<>REJETE), pour qu'aucune
--    surface ne montre « 6 » quand la file en contient « 10 ». Le reste inchangé.
--    (Les champs argent restent pour rétro-compat AdminDemo mais ne sont plus la
--    source du cockpit — cf. fn_admin_metriques_argent.)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_admin_kpi()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    result jsonb;
    debut_semaine timestamptz := date_trunc('week', now());
    debut_mois timestamptz := date_trunc('month', now());
    fin_mois timestamptz := date_trunc('month', now()) + INTERVAL '1 month';
BEGIN
    IF NOT est_admin() THEN RETURN '{"error":"Accès réservé aux administrateurs"}'::JSONB; END IF;

    SELECT jsonb_build_object(
        'soignants_total', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL),
        'etablissements_total', (SELECT COUNT(*) FROM etablissements WHERE supprime_le IS NULL),
        'missions_terminees_total', (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE'),
        'missions_terminees_mois', (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois),
        'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE statut IN ('OUVERTE','ASSIGNEE','EN_COURS')),

        'soignants_semaine', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL AND cree_le >= debut_semaine),
        'etablissements_semaine', (SELECT COUNT(*) FROM etablissements WHERE supprime_le IS NULL AND cree_le >= debut_semaine),

        'litiges_ouverts', (SELECT COUNT(*) FROM litiges WHERE statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE')),

        'ca_commissions_ht_mois', (
            SELECT COALESCE(SUM(montant_commission_ht), 0)
            FROM missions
            WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
        ),
        'ca_potentiel_mois', (
            SELECT COALESCE(SUM(montant_commission_ht), 0)
            FROM missions
            WHERE fin_le >= debut_mois AND fin_le < fin_mois
              AND statut IN ('TERMINEE','ASSIGNEE','EN_COURS')
        ),
        'ca_encaisse_total', (
            SELECT COALESCE(SUM(montant_ht), 0)
            FROM factures
            WHERE statut = 'PAYEE'
        ),
        'ca_potentiel_total', (
            SELECT COALESCE(SUM(montant_commission_ht), 0)
            FROM missions
            WHERE statut = 'TERMINEE'
        ),
        'gmv_mois', (
            SELECT COALESCE(SUM(total_brut), 0)
            FROM missions
            WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
        ),
        'gmv_total', (
            SELECT COALESCE(SUM(total_brut), 0)
            FROM missions
            WHERE statut = 'TERMINEE'
        ),

        'taux_acceptation_mois', (
            SELECT CASE
                WHEN COUNT(*) FILTER (WHERE cree_le >= debut_mois) = 0 THEN 0
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE statut IN ('ASSIGNEE','EN_COURS','TERMINEE') AND cree_le >= debut_mois)
                    / NULLIF(COUNT(*) FILTER (WHERE cree_le >= debut_mois), 0))
            END
            FROM missions
        ),

        'factures_impayees', (SELECT COUNT(*) FROM factures WHERE statut IN ('EMISE','EN_RETARD')),
        'docs_en_attente', (SELECT COUNT(*) FROM documents_soignants WHERE statut_verification = 'EN_ATTENTE'),
        -- Aligné sur la file de travail réelle (source unique) — plus de divergence 10 vs 6.
        'etab_en_attente', (SELECT COUNT(*) FROM etablissements
            WHERE supprime_le IS NULL AND COALESCE(rattachement_verifie,false)=false AND COALESCE(statut_verification,'')<>'REJETE')
    ) INTO result;

    RETURN result;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) fn_admin_cockpit_fondateur — exclut les comptes test des montants d'argent
--    (gmv/revenue/timeseries) pour cohérence avec la source unique. Gate, counts,
--    acquisition et charges équipe inchangés.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_total_soignants int;
  v_total_etabs int;
  v_soignants_7j int;
  v_etabs_7j int;
  v_soignants_30j int;
  v_etabs_30j int;
  v_missions_terminees int;
  v_missions_mois int;
  v_argent jsonb;
  v_gmv_total numeric;
  v_revenue_total numeric;
  v_revenue_mois numeric;
  v_taux_activation_soignant numeric;
  v_taux_activation_etab numeric;
  v_acquisition_mensuelle jsonb;
  v_revenue_mensuel jsonb;
  v_charges_equipe numeric;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
    AND raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ) THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  SELECT count(*) INTO v_total_soignants FROM soignants;
  SELECT count(*) INTO v_total_etabs FROM etablissements WHERE supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_7j FROM soignants WHERE cree_le >= now() - interval '7 days';
  SELECT count(*) INTO v_etabs_7j FROM etablissements WHERE cree_le >= now() - interval '7 days' AND supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_30j FROM soignants WHERE cree_le >= now() - interval '30 days';
  SELECT count(*) INTO v_etabs_30j FROM etablissements WHERE cree_le >= now() - interval '30 days' AND supprime_le IS NULL;

  SELECT count(*) INTO v_missions_terminees FROM missions WHERE statut = 'TERMINEE';
  SELECT count(*) INTO v_missions_mois FROM missions
    WHERE statut = 'TERMINEE' AND debut_le >= date_trunc('month', now());

  -- Montants headline (GMV, revenus) lus depuis la SOURCE UNIQUE
  -- fn_admin_metriques_argent — jamais recalculés ici, pour des chiffres
  -- strictement identiques au tableau de bord (réel, hors comptes test).
  v_argent := public.fn_admin_metriques_argent();
  v_gmv_total := COALESCE((v_argent#>>'{gmv,total_reel}')::numeric, 0);
  v_revenue_total := COALESCE((v_argent#>>'{commission,total_reel}')::numeric, 0);
  v_revenue_mois := COALESCE((v_argent#>>'{commission,mois_reel}')::numeric, 0);

  SELECT CASE WHEN v_total_soignants = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT soignant_id) FROM candidatures) / v_total_soignants, 1)
  END INTO v_taux_activation_soignant;

  SELECT CASE WHEN v_total_etabs = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT etablissement_id) FROM missions) / v_total_etabs, 1)
  END INTO v_taux_activation_etab;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
  INTO v_acquisition_mensuelle
  FROM (
    SELECT
      to_char(m.mois, 'YYYY-MM') AS mois,
      (SELECT count(*) FROM soignants s WHERE date_trunc('month', s.cree_le) = m.mois) AS soignants,
      (SELECT count(*) FROM etablissements e WHERE date_trunc('month', e.cree_le) = m.mois AND e.supprime_le IS NULL) AS etablissements
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  -- Timeseries revenus : exclut aussi les comptes test.
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
  INTO v_revenue_mensuel
  FROM (
    SELECT
      to_char(m.mois, 'YYYY-MM') AS mois,
      coalesce((
        SELECT sum(mi.montant_commission_ht)
        FROM missions mi
        LEFT JOIN etablissements e ON e.id = mi.etablissement_id
        LEFT JOIN soignants s ON s.id = mi.soignant_assigne_id
        WHERE mi.statut = 'TERMINEE'
        AND mi.montant_commission_ht IS NOT NULL
        AND date_trunc('month', mi.debut_le) = m.mois
        AND NOT (COALESCE(e.est_compte_test,false) OR COALESCE(s.est_compte_test,false))
      ), 0) AS revenue_ht,
      coalesce((
        SELECT sum(mi.total_brut)
        FROM missions mi
        LEFT JOIN etablissements e ON e.id = mi.etablissement_id
        LEFT JOIN soignants s ON s.id = mi.soignant_assigne_id
        WHERE mi.statut = 'TERMINEE'
        AND date_trunc('month', mi.debut_le) = m.mois
        AND NOT (COALESCE(e.est_compte_test,false) OR COALESCE(s.est_compte_test,false))
      ), 0) AS gmv
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  SELECT coalesce(sum(salaire_brut_mensuel * 1.45), 0)
  INTO v_charges_equipe
  FROM equipe_admin WHERE actif = true AND salaire_brut_mensuel > 0;

  v_result := jsonb_build_object(
    'total_soignants', v_total_soignants,
    'total_etabs', v_total_etabs,
    'soignants_7j', v_soignants_7j,
    'etabs_7j', v_etabs_7j,
    'soignants_30j', v_soignants_30j,
    'etabs_30j', v_etabs_30j,
    'missions_terminees', v_missions_terminees,
    'missions_mois', v_missions_mois,
    'gmv_total', v_gmv_total,
    'revenue_total', v_revenue_total,
    'revenue_mois', v_revenue_mois,
    'taux_activation_soignant', v_taux_activation_soignant,
    'taux_activation_etab', v_taux_activation_etab,
    'acquisition_mensuelle', v_acquisition_mensuelle,
    'revenue_mensuel', v_revenue_mensuel,
    'charges_equipe_mensuel', v_charges_equipe
  );

  RETURN v_result;
END;
$function$;
