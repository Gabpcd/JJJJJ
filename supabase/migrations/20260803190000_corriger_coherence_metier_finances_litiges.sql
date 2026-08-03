-- Cohérence métier transversale : paiements partiels, litiges, évaluations et diagnostics.

ALTER TABLE public.paiements_soignant
  ADD COLUMN IF NOT EXISTS montant_du_reference numeric,
  ADD COLUMN IF NOT EXISTS solde_restant numeric,
  ADD COLUMN IF NOT EXISTS est_partiel boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS source_montant_du text;

ALTER TABLE public.paiements_soignant
  DROP CONSTRAINT IF EXISTS paiements_soignant_montants_coherents;

ALTER TABLE public.paiements_soignant
  ADD CONSTRAINT paiements_soignant_montants_coherents CHECK (
    montant_net > 0
    AND (montant_du_reference IS NULL OR montant_du_reference > 0)
    AND (solde_restant IS NULL OR solde_restant >= 0)
    AND (montant_du_reference IS NULL OR montant_net <= montant_du_reference)
  );

-- L'interface actuelle autorise une évaluation tardive : l'ancien trigger de
-- 30 jours contredisait cette règle et créait une action impossible à terminer.
DROP TRIGGER IF EXISTS trg_evaluer_dans_delai ON public.evaluations;

-- Une proposition de résolution déjà en attente ne peut pas être remplacée
-- silencieusement par son auteur. L'autre partie doit d'abord accepter/refuser.
CREATE OR REPLACE FUNCTION public.fn_verrouiller_proposition_litige_en_attente()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
BEGIN
  IF OLD.payload_modifications IS NOT NULL
     AND NEW.payload_modifications IS DISTINCT FROM OLD.payload_modifications
     AND OLD.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS')
     AND (
       (COALESCE(OLD.accord_soignant, false) AND NOT COALESCE(OLD.accord_etablissement, false))
       OR
       (COALESCE(OLD.accord_etablissement, false) AND NOT COALESCE(OLD.accord_soignant, false))
     )
     AND NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
  THEN
    RAISE EXCEPTION 'PROPOSITION_LITIGE_EN_ATTENTE'
      USING ERRCODE = 'P0001',
            HINT = 'L autre partie doit répondre à la proposition existante avant toute nouvelle proposition.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_verrouiller_proposition_litige_en_attente ON public.litiges;
CREATE TRIGGER trg_verrouiller_proposition_litige_en_attente
BEFORE UPDATE OF payload_modifications ON public.litiges
FOR EACH ROW
EXECUTE FUNCTION public.fn_verrouiller_proposition_litige_en_attente();

-- Le défaut NON_PROPOSE est une politique de prévention de la requalification,
-- pas l'affirmation erronée que tout exercice libéral en clinique serait illégal.
CREATE OR REPLACE FUNCTION public.fn_mode_exercice(
  p_profession text,
  p_type_etab text,
  p_finess_secteur text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_cat text;
  v_row public.matrice_modes_exercice%ROWTYPE;
BEGIN
  v_cat := public.fn_categorie_etablissement(p_type_etab, p_finess_secteur);
  SELECT * INTO v_row
  FROM public.matrice_modes_exercice
  WHERE profession = p_profession
    AND categorie_etablissement = v_cat;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'niveau', v_row.niveau,
      'categorie', v_cat,
      'source_libelle', v_row.source_libelle,
      'source_force', v_row.source_force,
      'source_url', v_row.source_url,
      'source_url_complementaire', v_row.source_url_complementaire
    );
  END IF;

  RETURN jsonb_build_object(
    'niveau', 'NON_PROPOSE',
    'categorie', v_cat,
    'source_libelle', 'Jolene recommande le salariat lorsque les conditions concrètes de la mission pourraient caractériser un lien de subordination. Ce n’est pas une interdiction générale du libéral en clinique.',
    'source_force', 'CONFORMITE_JOLENE',
    'source_url', NULL,
    'source_url_complementaire', NULL
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant_v2(
  p_mission_id uuid,
  p_montant_verse numeric,
  p_montant_total_du numeric,
  p_methode text DEFAULT NULL,
  p_reference text DEFAULT NULL,
  p_date_paiement date DEFAULT CURRENT_DATE,
  p_attestation_sur_l_honneur boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_result jsonb;
  v_paiement_id uuid;
  v_plafond_brut numeric;
  v_source text;
  v_solde numeric;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('error', 'MISSION_INTROUVABLE', 'message', 'Mission introuvable.');
  END IF;

  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement('paiement', v_mission.etablissement_id) IS NOT TRUE
     )
  THEN
    RETURN jsonb_build_object('error', 'ACCES_REFUSE', 'message', 'Accès refusé.');
  END IF;

  IF p_montant_verse IS NULL OR p_montant_verse <= 0
     OR p_montant_total_du IS NULL OR p_montant_total_du <= 0
  THEN
    RETURN jsonb_build_object(
      'error', 'MONTANTS_REQUIS',
      'message', 'Renseignez le total net dû et le montant réellement versé.'
    );
  END IF;

  IF round(p_montant_verse, 2) > round(p_montant_total_du, 2) THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_VERSE_SUPERIEUR_AU_DU',
      'message', 'Le montant versé ne peut pas dépasser le total net dû.'
    );
  END IF;

  IF round(p_montant_verse, 2) < round(p_montant_total_du, 2) THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_INCOMPLET',
      'message', 'Le montant versé doit correspondre exactement au total net dû. Les paiements partiels ne sont pas acceptés.',
      'montant_verse', round(p_montant_verse, 2),
      'montant_total_du', round(p_montant_total_du, 2),
      'solde_manquant', round(p_montant_total_du - p_montant_verse, 2)
    );
  END IF;

  IF v_mission.type_contrat_applique = 'SALARIE' THEN
    v_plafond_brut := COALESCE(v_mission.total_brut, 0)
      + COALESCE(v_mission.montant_ifm, 0)
      + COALESCE(v_mission.montant_icp, 0)
      + COALESCE(v_mission.montant_majoration_nuit, 0)
      + COALESCE(v_mission.montant_majoration_dimanche, 0)
      + COALESCE(v_mission.montant_majoration_ferie, 0);
    IF v_plafond_brut <= 0 THEN
      RETURN jsonb_build_object(
        'error', 'BRUT_SALARIE_INDISPONIBLE',
        'message', 'La rémunération brute de référence est indisponible.'
      );
    END IF;
    IF round(p_montant_total_du, 2) > round(v_plafond_brut, 2) THEN
      RETURN jsonb_build_object(
        'error', 'MONTANT_NET_SALARIE_SUPERIEUR_AU_BRUT',
        'message', 'Le total net dû ne peut pas dépasser le brut de référence (' || round(v_plafond_brut, 2) || ' €).',
        'montant_maximum', round(v_plafond_brut, 2)
      );
    END IF;
    v_source := 'BULLETIN_OFFICIEL_ETABLISSEMENT';
  ELSE
    v_source := 'FACTURE_HONORAIRES';
  END IF;

  v_result := public.fn_declarer_paiement_soignant_internal_20260801(
    p_mission_id,
    round(p_montant_verse, 2),
    p_methode,
    p_reference,
    p_date_paiement,
    p_attestation_sur_l_honneur
  );
  IF v_result ? 'error' THEN
    RETURN v_result;
  END IF;

  v_paiement_id := (v_result->>'paiement_id')::uuid;
  v_solde := greatest(round(p_montant_total_du - p_montant_verse, 2), 0);

  UPDATE public.paiements_soignant
  SET montant_du_reference = round(p_montant_total_du, 2),
      solde_restant = v_solde,
      est_partiel = v_solde > 0,
      source_montant_du = v_source,
      modifie_le = now()
  WHERE id = v_paiement_id;

  RETURN v_result || jsonb_build_object(
    'montant_verse', round(p_montant_verse, 2),
    'montant_total_du', round(p_montant_total_du, 2),
    'solde_restant', v_solde,
    'est_partiel', v_solde > 0,
    'source_montant_du', v_source
  );
END;
$function$;

-- Le tableau principal utilise fn_obligations_financieres, pas seulement
-- fn_paiements_etablissement. On enrichit donc les deux journaux exposés par
-- ce RPC afin que les anciens versements incomplets ne disparaissent jamais.
CREATE OR REPLACE FUNCTION public.fn_obligations_financieres()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
  v_lignes jsonb := '[]'::jsonb;
  v_total_soignants numeric := 0;
  v_total_commissions numeric := 0;
  v_attente jsonb := '[]'::jsonb;
  v_confirmes jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS NULL
       OR public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_result := public.fn_obligations_financieres_internal_20260801();
  IF v_result ? 'error' THEN RETURN v_result; END IF;

  WITH lignes_corrigees AS (
    SELECT CASE
      WHEN ligne->>'type_contrat_applique' = 'SALARIE' THEN
        jsonb_set(
          ligne,
          '{net_a_payer}',
          to_jsonb(COALESCE(
            (SELECT NULLIF(m.net_estime, 0) FROM public.missions m WHERE m.id = (ligne->>'mission_id')::uuid),
            (SELECT round(NULLIF(m.net_a_payer, 0) * 0.78, 2) FROM public.missions m WHERE m.id = (ligne->>'mission_id')::uuid),
            0
          )),
          true
        )
      ELSE ligne
    END AS ligne
    FROM jsonb_array_elements(COALESCE(v_result->'missions_non_payees', '[]'::jsonb)) AS lignes(ligne)
  )
  SELECT COALESCE(jsonb_agg(ligne), '[]'::jsonb),
         COALESCE(sum((ligne->>'net_a_payer')::numeric), 0)
  INTO v_lignes, v_total_soignants
  FROM lignes_corrigees;

  SELECT COALESCE(jsonb_agg(
    paiement || jsonb_build_object(
      'montant_du_reference', ps.montant_du_reference,
      'solde_restant', ps.solde_restant,
      'est_partiel', ps.est_partiel,
      'source_montant_du', ps.source_montant_du
    )
  ), '[]'::jsonb)
  INTO v_attente
  FROM jsonb_array_elements(COALESCE(v_result->'paiements_soignants_en_attente', '[]'::jsonb)) AS paiements(paiement)
  LEFT JOIN public.paiements_soignant ps ON ps.id = (paiement->>'paiement_id')::uuid;

  SELECT COALESCE(jsonb_agg(
    paiement || jsonb_build_object(
      'montant_du_reference', ps.montant_du_reference,
      'solde_restant', ps.solde_restant,
      'est_partiel', ps.est_partiel,
      'source_montant_du', ps.source_montant_du
    )
  ), '[]'::jsonb)
  INTO v_confirmes
  FROM jsonb_array_elements(COALESCE(v_result->'paiements_soignants_confirmes', '[]'::jsonb)) AS paiements(paiement)
  LEFT JOIN public.paiements_soignant ps ON ps.id = (paiement->>'paiement_id')::uuid;

  v_total_commissions := COALESCE((v_result->>'total_commissions_du')::numeric, 0);
  v_result := jsonb_set(v_result, '{missions_non_payees}', v_lignes, true);
  v_result := jsonb_set(v_result, '{total_soignants_du}', to_jsonb(v_total_soignants), true);
  v_result := jsonb_set(v_result, '{total_du}', to_jsonb(v_total_soignants + v_total_commissions), true);
  v_result := jsonb_set(v_result, '{paiements_soignants_en_attente}', v_attente, true);
  RETURN jsonb_set(v_result, '{paiements_soignants_confirmes}', v_confirmes, true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant(
  p_mission_id uuid,
  p_montant numeric,
  p_methode text DEFAULT NULL,
  p_reference text DEFAULT NULL,
  p_date_paiement date DEFAULT CURRENT_DATE,
  p_attestation_sur_l_honneur boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_type_contrat text;
BEGIN
  SELECT type_contrat_applique INTO v_type_contrat
  FROM public.missions
  WHERE id = p_mission_id;

  IF v_type_contrat IS NULL THEN
    RETURN jsonb_build_object('error', 'MISSION_INTROUVABLE_OU_CONTRAT_NON_FIGE');
  END IF;

  IF v_type_contrat = 'SALARIE' THEN
    RETURN jsonb_build_object(
      'error', 'MONTANT_TOTAL_DU_REQUIS',
      'message', 'Pour un salarié, indiquez séparément le net total dû selon le bulletin officiel et le montant réellement versé.'
    );
  END IF;

  RETURN public.fn_declarer_paiement_soignant_v2(
    p_mission_id,
    p_montant,
    p_montant,
    p_methode,
    p_reference,
    p_date_paiement,
    p_attestation_sur_l_honneur
  );
END;
$function$;

-- Rend visibles le total dû, le versement et le reliquat dans le même journal.
CREATE OR REPLACE FUNCTION public.fn_paiements_etablissement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
  v_lignes jsonb;
  v_paiements jsonb;
BEGIN
  IF NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND (
       v_etab_id IS NULL
       OR public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_result := public.fn_paiements_etablissement_internal_20260801();
  IF v_result ? 'error' THEN RETURN v_result; END IF;

  SELECT COALESCE(jsonb_agg(
    CASE WHEN EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = (ligne->>'mission_id')::uuid AND m.type_contrat_applique = 'SALARIE'
    ) THEN jsonb_set(
      ligne, '{net_a_payer}',
      to_jsonb(COALESCE(
        (SELECT NULLIF(m.net_estime, 0) FROM public.missions m WHERE m.id = (ligne->>'mission_id')::uuid),
        (SELECT round(NULLIF(m.net_a_payer, 0) * 0.78, 2) FROM public.missions m WHERE m.id = (ligne->>'mission_id')::uuid),
        0
      )), true
    ) ELSE ligne END
  ), '[]'::jsonb)
  INTO v_lignes
  FROM jsonb_array_elements(COALESCE(v_result->'missions_a_payer', '[]'::jsonb)) AS lignes(ligne);

  SELECT COALESCE(jsonb_agg(
    paiement || jsonb_build_object(
      'montant_du_reference', ps.montant_du_reference,
      'solde_restant', ps.solde_restant,
      'est_partiel', ps.est_partiel,
      'source_montant_du', ps.source_montant_du
    )
  ), '[]'::jsonb)
  INTO v_paiements
  FROM jsonb_array_elements(COALESCE(v_result->'paiements_recents', '[]'::jsonb)) AS paiements(paiement)
  LEFT JOIN public.paiements_soignant ps ON ps.id = (paiement->>'id')::uuid;

  v_result := jsonb_set(v_result, '{missions_a_payer}', v_lignes, true);
  RETURN jsonb_set(v_result, '{paiements_recents}', v_paiements, true);
END;
$function$;

-- Les anciennes données de démonstration sont conservées mais leur paiement
-- partiel devient explicite et traçable, au lieu d'être présenté comme soldé.
UPDATE public.paiements_soignant ps
SET montant_du_reference = round(m.net_estime, 2),
    solde_restant = greatest(round(m.net_estime - ps.montant_net, 2), 0),
    est_partiel = round(ps.montant_net, 2) < round(m.net_estime, 2),
    source_montant_du = 'ESTIMATION_AVANT_PAS_A_CONFIRMER',
    modifie_le = now()
FROM public.missions m
JOIN public.etablissements e ON e.id = m.etablissement_id
WHERE ps.mission_id = m.id
  AND e.est_compte_test IS TRUE
  AND m.type_contrat_applique = 'SALARIE'
  AND ps.statut = 'DECLARE'
  AND ps.montant_du_reference IS NULL
  AND m.net_estime IS NOT NULL
  AND m.net_estime >= ps.montant_net;

CREATE OR REPLACE FUNCTION public.fn_diagnostic_coherence_financiere()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_missions jsonb;
  v_factures jsonb;
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

  WITH attendus AS (
    SELECT fh.id, fh.numero_facture, fh.mission_id, fh.montant_ht,
      CASE
        WHEN COALESCE(fh.est_facture_finale_mission, false) THEN m.net_a_payer
        ELSE (
          SELECT round(COALESCE(sum(
            extract(epoch FROM (mc.fin_le - mc.debut_le)) / 3600.0
            * COALESCE(m.taux_horaire_base_fige, m.taux_horaire_base)
          ), 0), 2)
          FROM public.mission_creneaux mc
          WHERE mc.mission_id = m.id
            AND COALESCE(mc.type_creneau, 'PREVISIONNEL') = 'PREVISIONNEL'
            AND mc.est_pause IS NOT TRUE
            AND mc.debut_le::date BETWEEN fh.periode_debut AND fh.periode_fin
        )
      END AS attendu
    FROM public.factures_honoraires fh
    JOIN public.missions m ON m.id = fh.mission_id
    WHERE COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
      AND fh.statut NOT IN ('BROUILLON', 'REMPLACEE', 'ANNULEE', 'ERREUR_GENERATION')
  ), ecarts AS (
    SELECT * FROM attendus
    WHERE attendu IS NOT NULL AND attendu > 0
      AND abs(montant_ht - attendu) > greatest(attendu * 0.01, 1.00)
  )
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', COALESCE(jsonb_agg(jsonb_build_object(
      'facture_id', id, 'numero_facture', numero_facture,
      'mission_id', mission_id, 'montant_ht', montant_ht,
      'mission_net', attendu, 'ecart', montant_ht - attendu
    ) ORDER BY numero_facture) FILTER (WHERE id IN (SELECT id FROM ecarts LIMIT 10)), '[]'::jsonb)
  ) INTO v_factures FROM ecarts;

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
    'genere_le', now(),
    'missions_incoherentes', v_missions,
    'factures_ecart_mission', v_factures,
    'stripe_transfers_orphelins', v_transfers
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_obligations_financieres() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_obligations_financieres() TO authenticated, service_role;

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
VALUES
  (
    'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)'::regprocedure)),
    'RPC établissement/admin : sépare total net dû et montant versé et refuse les paiements partiels ou les surpaiements.',
    now()
  ),
  (
    'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure)),
    'Compatibilité libéral uniquement ; les salaires exigent désormais le total dû explicite via v2.',
    now()
  ),
  (
    'fn_paiements_etablissement()',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_paiements_etablissement()'::regprocedure)),
    'Lecture financière bornée par permission, enrichie du total dû et du reliquat.',
    now()
  ),
  (
    'fn_obligations_financieres()',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_obligations_financieres()'::regprocedure)),
    'Lecture des obligations financières bornée au tenant et enrichie du total dû et du reliquat.',
    now()
  ),
  (
    'fn_diagnostic_coherence_financiere()',
    'ADMIN_EST_ADMIN_VALIDE',
    md5(pg_get_functiondef('public.fn_diagnostic_coherence_financiere()'::regprocedure)),
    'Diagnostic admin : compare le brut de base au taux x heures et les factures hebdomadaires à leur période exacte.',
    now()
  )
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;
