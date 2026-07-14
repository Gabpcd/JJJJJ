-- Le compteur du cockpit doit appliquer exactement le même prédicat que
-- fn_admin_lister_etablissements_a_verifier. Depuis le durcissement de la file
-- (20260714063000), l'ancien raccourci rattachement_verifie=false sous-comptait
-- les établissements EN_ATTENTE / EN_COURS ayant déjà un rattachement vérifié.

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
    'commission', jsonb_build_object(
      'unite', 'HT',
      'total_reel', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE est_reel),
      'total_test', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE NOT est_reel),
      'mois_reel',  (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE est_reel AND fin_le>=debut_mois AND fin_le<fin_mois),
      'mois_test',  (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE NOT est_reel AND fin_le>=debut_mois AND fin_le<fin_mois),
      'tva_reel',   (SELECT COALESCE(SUM(montant_commission_tva),0) FROM m WHERE est_reel)
    ),
    'encaisse', jsonb_build_object(
      'ht_reel',  ROUND((SELECT COALESCE(SUM(montant_ht),0) FROM f WHERE statut='PAYEE' AND est_reel)
                + (SELECT COALESCE(SUM(commission_cents),0)/100.0 FROM esc WHERE debite_le IS NOT NULL AND est_reel), 2),
      'ttc_reel', ROUND((SELECT COALESCE(SUM(montant_ttc),0) FROM f WHERE statut='PAYEE' AND est_reel)
                + (SELECT COALESCE(SUM(commission_cents),0)/100.0 FROM esc WHERE debite_le IS NOT NULL AND est_reel), 2),
      'ht_test',  ROUND((SELECT COALESCE(SUM(montant_ht),0) FROM f WHERE statut='PAYEE' AND NOT est_reel)
                + (SELECT COALESCE(SUM(commission_cents),0)/100.0 FROM esc WHERE debite_le IS NOT NULL AND NOT est_reel), 2)
    ),
    'facturable', jsonb_build_object(
      'unite', 'HT',
      'ht_reel', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE est_reel),
      'ht_test', (SELECT COALESCE(SUM(montant_commission_ht),0) FROM m WHERE NOT est_reel)
    ),
    'gmv', jsonb_build_object(
      'unite', 'brut',
      'total_reel', (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE est_reel),
      'total_test', (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE NOT est_reel),
      'mois_reel', (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE est_reel AND fin_le>=debut_mois AND fin_le<fin_mois),
      'mois_test', (SELECT COALESCE(SUM(total_brut),0) FROM m WHERE NOT est_reel AND fin_le>=debut_mois AND fin_le<fin_mois)
    ),
    'nb_missions_terminees_reel', (SELECT COUNT(*) FROM m WHERE est_reel),
    'nb_missions_terminees_test', (SELECT COUNT(*) FROM m WHERE NOT est_reel),
    'etab_a_valider', (
      SELECT COUNT(*)
      FROM etablissements e
      WHERE e.supprime_le IS NULL
        AND (
          COALESCE(e.statut_verification, 'EN_ATTENTE') IN ('EN_ATTENTE', 'EN_COURS')
          OR (
            e.statut_verification = 'VERIFIE'
            AND (
              e.siret_verifie IS NOT TRUE
              OR e.finess_verifie IS NOT TRUE
              OR e.representant_identite_verifiee IS NOT TRUE
              OR e.rattachement_verifie IS NOT TRUE
              OR e.contrat_service_signe IS NOT TRUE
            )
          )
        )
    ),
    'a_des_donnees_test', (
      SELECT EXISTS(SELECT 1 FROM etablissements WHERE COALESCE(est_compte_test,false))
        OR EXISTS(SELECT 1 FROM soignants WHERE COALESCE(est_compte_test,false))
    )
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_metriques_argent() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_metriques_argent() TO authenticated, service_role;
