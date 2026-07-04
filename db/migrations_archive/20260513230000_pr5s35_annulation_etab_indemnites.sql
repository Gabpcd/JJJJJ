-- PR 5 Sprint 3.5 — Annulation mission côté établissement + indemnités légales
--
-- Logique annulation étab avec calcul automatique des indemnités selon
-- Code travail (CDD) + Code civil (libéral). AUCUNE clause pénale auto
-- côté soignant. Indemnités versées via Stripe Connect.
--
-- Grille validée Gabrielle :
--   - Mission OUVERTE (pas encore acceptée) : libre, 0 pt
--   - ACCEPTEE et < 30 min après acceptation : fenêtre étab aussi, libre
--   - ACCEPTEE, contrat non signé : -3 pts, notif soignant
--   - CDD signé avant pointage : indemnité = heures × taux × 1.10 (salaire
--     + précarité 10%) + -10 pts
--   - LIBERAL signé avant pointage : clause pénale selon délai :
--       < 24h → 50% du montant total, 24-48h → 30%, > 48h → 10%
--     + -10 pts
--   - Après pointage : salaires/honoraires COMPLETS dus + -20 pts

-- ============================================================
-- 1. Helper : calcul indemnité étab
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_calculer_indemnite_annulation_etab(
  p_type_contrat text,
  p_montant_total numeric,
  p_duree_heures numeric,
  p_taux_horaire numeric,
  p_delta_mission interval
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_montant numeric := 0;
  v_motif text := 'aucune_indemnite';
  v_base text;
BEGIN
  IF p_type_contrat IN ('CDD', 'CDDU', 'SALARIE') THEN
    -- Code travail : salaire brut + indemnité précarité 10%
    v_montant := COALESCE(p_duree_heures, 0) * COALESCE(p_taux_horaire, 0) * 1.10;
    v_motif := 'INDEMNITE_CDD_SIGNE_L1243_8';
    v_base := 'duree × taux × 1.10 (salaire + précarité 10%)';
  ELSIF p_type_contrat IN ('REMPLACEMENT_LIBERAL', 'LIBERAL') THEN
    -- Code civil 1231-5 : clause pénale dégressive
    IF p_delta_mission < INTERVAL '24 hours' THEN
      v_montant := COALESCE(p_montant_total, 0) * 0.50;
      v_motif := 'CLAUSE_PENALE_LIBERAL_24H';
      v_base := 'montant × 50% (annulation < 24h)';
    ELSIF p_delta_mission < INTERVAL '48 hours' THEN
      v_montant := COALESCE(p_montant_total, 0) * 0.30;
      v_motif := 'CLAUSE_PENALE_LIBERAL_24_48H';
      v_base := 'montant × 30% (annulation 24-48h)';
    ELSE
      v_montant := COALESCE(p_montant_total, 0) * 0.10;
      v_motif := 'CLAUSE_PENALE_LIBERAL_48H_PLUS';
      v_base := 'montant × 10% (annulation > 48h)';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'montant', ROUND(v_montant, 2),
    'motif', v_motif,
    'base_calcul', v_base,
    'type_contrat', p_type_contrat
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_indemnite_annulation_etab(text, numeric, numeric, numeric, interval) TO authenticated;

-- ============================================================
-- 2. RPC principale : annulation mission par étab
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_annuler_mission_etab(
  p_mission_id uuid,
  p_motif_categorie text,
  p_texte_libre text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_contrat RECORD;
  v_presence_id uuid;
  v_indemnite jsonb;
  v_delta_mission interval;
  v_points int := 0;
  v_type_evt text;
  v_event_id uuid;
  v_montant_indem numeric := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  IF p_motif_categorie IS NULL OR p_motif_categorie NOT IN (
    'BESOIN_DISPARU', 'BUDGET_REVU', 'REMPLACEMENT_INTERNE',
    'CHANGEMENT_PLANNING', 'CAS_FORCE_MAJEURE', 'AUTRE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif requis');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 10 caractères)');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE', 'error', 'Mission introuvable');
  END IF;

  -- Auth : l'étab admin doit posséder la mission
  IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Non autorisé à annuler cette mission');
  END IF;

  IF v_mission.statut IN ('ANNULEE_LITIGE', 'ANNULEE_ETAB', 'TERMINEE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'STATUT_INVALIDE',
                                'error', 'Mission déjà annulée ou terminée');
  END IF;

  v_delta_mission := v_mission.debut_le - NOW();

  -- CAS 1 : Mission OUVERTE = annulation libre, 0 pt
  IF v_mission.statut = 'OUVERTE' THEN
    UPDATE public.missions SET
      statut = 'ANNULEE_ETAB',
      modifie_le = NOW()
    WHERE id = p_mission_id;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      v_uid, 'ADMIN_ETABLISSEMENT', 'ANNULATION_MISSION', 'mission', p_mission_id,
      jsonb_build_object('evenement', 'MISSION_ANNULEE_ETAB',
                          'motif_categorie', p_motif_categorie, 'texte_libre', p_texte_libre,
                          'libre', true, 'statut_initial', 'OUVERTE')
    );

    RETURN jsonb_build_object('success', true, 'libre', true, 'points', 0,
                                'indemnite_montant', 0, 'message', 'Mission OUVERTE annulée sans impact');
  END IF;

  -- Récupérer contrat + presence si applicables
  SELECT * INTO v_contrat FROM public.contrats_mission WHERE mission_id = p_mission_id LIMIT 1;
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = p_mission_id LIMIT 1;

  -- CAS 2 : Pointage déjà commencé → salaires/honoraires COMPLETS
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.missions SET statut = 'ANNULEE_ETAB', modifie_le = NOW()
    WHERE id = p_mission_id;
    -- Marquer la presence comme "annulee par étab post-pointage"
    UPDATE public.presences SET
      motif_litige = COALESCE(motif_litige, '') || ' ANNULEE_ETAB_APRES_POINTAGE',
      modifie_le = NOW()
    WHERE id = v_presence_id;

    v_points := -20;
    v_type_evt := 'ANNULATION_APRES_POINTAGE';

    -- Indemnité = montant total dû (mission considérée comme effectuée)
    v_indemnite := public.fn_calculer_indemnite_annulation_etab(
      COALESCE(v_contrat.type_contrat, v_mission.type_contrat::text),
      COALESCE(v_mission.duree_heures, 0) * COALESCE(v_mission.taux_horaire_base, 0),
      v_mission.duree_heures, v_mission.taux_horaire_base, INTERVAL '0'
    );
    v_montant_indem := (v_indemnite->>'montant')::numeric;

  -- CAS 3 : Contrat SIGNE_COMPLET avant pointage → indemnité légale
  ELSIF v_contrat IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET' THEN
    UPDATE public.missions SET statut = 'ANNULEE_ETAB', modifie_le = NOW()
    WHERE id = p_mission_id;
    UPDATE public.contrats_mission SET statut = 'RUPTURE_ETAB', modifie_le = NOW()
    WHERE id = v_contrat.id;

    v_indemnite := public.fn_calculer_indemnite_annulation_etab(
      v_contrat.type_contrat,
      COALESCE(v_mission.duree_heures, 0) * COALESCE(v_mission.taux_horaire_base, 0),
      v_mission.duree_heures, v_mission.taux_horaire_base, v_delta_mission
    );
    v_montant_indem := (v_indemnite->>'montant')::numeric;

    v_points := -10;
    v_type_evt := CASE WHEN v_contrat.type_contrat IN ('CDD', 'CDDU', 'SALARIE')
                       THEN 'ANNULATION_CDD_SIGNE'
                       ELSE 'ANNULATION_LIBERAL_SIGNE' END;

    -- Si CDD : enqueue DPAE annulation
    IF v_contrat.type_contrat IN ('CDD', 'CDDU', 'SALARIE') THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      VALUES ('DPAE_ANNULATION',
              jsonb_build_object('contrat_id', v_contrat.id, 'mission_id', p_mission_id,
                                  'motif', 'ANNULATION_ETAB', 'echeance_legale_h', 48),
              'ANNULATION_MISSION', p_mission_id);
    END IF;

  -- CAS 4 : Mission ACCEPTEE sans contrat signé
  ELSE
    UPDATE public.missions SET statut = 'ANNULEE_ETAB', modifie_le = NOW()
    WHERE id = p_mission_id;
    v_points := -3;
    v_type_evt := 'ANNULATION_AVANT_CONTRAT';
    v_indemnite := jsonb_build_object('montant', 0, 'motif', 'AUCUNE_INDEMNITE_AVANT_CONTRAT');
  END IF;

  -- Créer event score étab (toujours sauf cas OUVERTE déjà traité)
  IF v_points < 0 THEN
    INSERT INTO public.evenements_score_etab (
      etablissement_id, type_evenement, points, motif, contestable,
      mission_id, details
    ) VALUES (
      v_mission.etablissement_id, v_type_evt, v_points,
      p_motif_categorie || ' : ' || left(p_texte_libre, 200),
      true,
      p_mission_id,
      jsonb_build_object(
        'motif_categorie', p_motif_categorie,
        'texte_libre', p_texte_libre,
        'delta_mission_h', EXTRACT(EPOCH FROM v_delta_mission) / 3600,
        'indemnite', v_indemnite,
        'pointage_existant', v_presence_id IS NOT NULL,
        'contrat_signe', v_contrat IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET'
      )
    ) RETURNING id INTO v_event_id;
  END IF;

  -- Enqueue versement indemnité au soignant si applicable
  IF v_montant_indem > 0 AND v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('STRIPE_REFUND_PARTIEL',
            jsonb_build_object('mission_id', p_mission_id,
                                'beneficiaire_id', v_mission.soignant_assigne_id,
                                'montant', v_montant_indem,
                                'motif', v_indemnite->>'motif',
                                'base_calcul', v_indemnite->>'base_calcul'),
            'ANNULATION_MISSION', p_mission_id);
  END IF;

  -- Enqueue avoir PDF
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('AVOIR_PDF_GENERATION',
          jsonb_build_object('mission_id', p_mission_id, 'type', 'ANNULATION_ETAB',
                              'motif_avoir', 'ANNULATION_MISSION_ETAB',
                              'montant_indemnite', v_montant_indem),
          'ANNULATION_MISSION', p_mission_id);

  -- Notification soignant email + push
  IF v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES
      ('EMAIL_NOTIF', jsonb_build_object(
        'destinataire_id', v_mission.soignant_assigne_id,
        'type', 'MISSION_ANNULEE_ETAB',
        'data', jsonb_build_object('mission_id', p_mission_id,
                                    'motif_categorie', p_motif_categorie,
                                    'indemnite_montant', v_montant_indem,
                                    'indemnite_motif', v_indemnite->>'motif')
      ), 'ANNULATION_MISSION', p_mission_id),
      ('PUSH_NOTIF', jsonb_build_object(
        'destinataire_id', v_mission.soignant_assigne_id,
        'type_evenement', 'MISSION_ANNULEE_ETAB',
        'titre', 'Mission annulée par l''établissement',
        'corps', CASE WHEN v_montant_indem > 0
                       THEN 'Indemnité de ' || v_montant_indem || '€ versée selon Code du travail.'
                       ELSE 'Aucun contrat signé, pas d''indemnité.' END
      ), 'ANNULATION_MISSION', p_mission_id);
  END IF;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'ANNULATION_MISSION', 'mission', p_mission_id,
    jsonb_build_object(
      'evenement', 'MISSION_ANNULEE_ETAB',
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'points', v_points, 'type_evenement', v_type_evt,
      'indemnite', v_indemnite,
      'pointage_existant', v_presence_id IS NOT NULL,
      'contrat_signe', v_contrat IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET',
      'event_score_id', v_event_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'libre', v_points = 0,
    'points', v_points,
    'type_evenement', v_type_evt,
    'event_score_id', v_event_id,
    'indemnite', v_indemnite,
    'message', CASE
      WHEN v_montant_indem > 0 THEN 'Indemnité de ' || v_montant_indem || '€ versée au soignant'
      WHEN v_points = -3 THEN 'Annulation enregistrée, pas d''indemnité (contrat non signé)'
      ELSE 'Annulation enregistrée'
    END
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_annuler_mission_etab(uuid, text, text) TO authenticated;

-- Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR5_ANNULATION_ETAB_INSTALLED',
    'pr', 'PR 5 Sprint 3.5',
    'rpcs', ARRAY['fn_calculer_indemnite_annulation_etab',
                   'fn_annuler_mission_etab'],
    'grille_indemnites', jsonb_build_object(
      'CDD_signe', 'duree × taux × 1.10 (art. L1243-8 + précarité)',
      'LIBERAL_<24h', '50% montant total',
      'LIBERAL_24_48h', '30%',
      'LIBERAL_>48h', '10%',
      'apres_pointage', 'montant complet (mission considérée effectuée)'
    )
  )
);
