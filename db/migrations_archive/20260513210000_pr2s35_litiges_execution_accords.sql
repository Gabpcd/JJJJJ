-- PR 2 Sprint 3.5 — Litiges exécution automatique des accords
--
-- Refactor fn_cloturer_litige pour accepter un PAYLOAD STRUCTURÉ et
-- exécuter automatiquement les modifications convenues (heures, montants,
-- annulation, compensation).
--
-- Structure payload :
-- {
--   "type": "MODIFICATION_HORAIRES" | "MODIFICATION_MONTANT" |
--           "ANNULATION_TOTALE" | "COMPENSATION_PARTIELLE" |
--           "MIXTE" | "ACCORD_SANS_MODIFICATION",
--   "modifications": {
--     "heure_arrivee_corrigee": "08:00",
--     "heure_depart_corrigee": "14:00",
--     "taux_horaire_corrige": 28.50,
--     "montant_total_corrige": 240,
--     "pourcentage_compensation": 30,
--     "motif_annulation": "soignant parti plus tôt"
--   },
--   "justification": "texte libre"
-- }
--
-- Atomique : toute l'exécution dans la transaction PG. Les side-effects
-- externes (Stripe refund, Chorus recyclerFacture, DPAE annulation) sont
-- enqueués dans la table externalisation_actions traités par cron edge
-- function (pour éviter de bloquer la résolution sur des appels HTTP).

-- ============================================================
-- 1. Table externalisation_actions (side-effects asynchrones)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.externalisation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type_action text NOT NULL CHECK (type_action IN (
    'STRIPE_REFUND_PARTIEL', 'STRIPE_REFUND_TOTAL',
    'CHORUS_RECYCLER_FACTURE', 'DPAE_ANNULATION',
    'EMAIL_NOTIF', 'PUSH_NOTIF', 'AVOIR_PDF_GENERATION'
  )),
  payload jsonb NOT NULL,
  source text NOT NULL CHECK (source IN ('LITIGE_EXEC', 'ANNULATION_MISSION', 'AUTRE')),
  source_id uuid,
  statut text NOT NULL DEFAULT 'PENDING' CHECK (statut IN ('PENDING', 'PROCESSING', 'DONE', 'ERROR')),
  tentatives int NOT NULL DEFAULT 0,
  derniere_tentative_le timestamptz,
  derniere_erreur text,
  resultat jsonb,
  cree_le timestamptz NOT NULL DEFAULT NOW(),
  traite_le timestamptz
);

CREATE INDEX IF NOT EXISTS idx_ext_actions_pending
  ON public.externalisation_actions(statut, cree_le) WHERE statut IN ('PENDING','ERROR');

ALTER TABLE public.externalisation_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_ext_actions_admin ON public.externalisation_actions;
CREATE POLICY pol_ext_actions_admin ON public.externalisation_actions
  FOR SELECT TO authenticated USING (est_admin());
DROP POLICY IF EXISTS pol_ext_actions_deny_write ON public.externalisation_actions;
CREATE POLICY pol_ext_actions_deny_write ON public.externalisation_actions
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- 2. Sub-routine : modifier horaires d'une presence
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_modifier_horaires_presence(
  p_presence_id uuid,
  p_pointage_arrivee_le timestamptz,
  p_pointage_depart_le timestamptz,
  p_motif text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_presence RECORD;
  v_duree_min int;
BEGIN
  SELECT * INTO v_presence FROM public.presences WHERE id = p_presence_id;
  IF v_presence IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Presence introuvable');
  END IF;

  IF p_pointage_depart_le <= p_pointage_arrivee_le THEN
    RETURN jsonb_build_object('success', false, 'error', 'Heure départ doit être après arrivée');
  END IF;

  v_duree_min := EXTRACT(EPOCH FROM (p_pointage_depart_le - p_pointage_arrivee_le)) / 60;

  UPDATE public.presences SET
    pointage_arrivee_le = p_pointage_arrivee_le,
    pointage_depart_le = p_pointage_depart_le,
    duree_brute_min = v_duree_min,
    duree_nette_min = v_duree_min - COALESCE(duree_pause_min, 0),
    modifie_le = NOW()
  WHERE id = p_presence_id;

  RETURN jsonb_build_object(
    'success', true,
    'presence_id', p_presence_id,
    'nouvelle_duree_min', v_duree_min,
    'duree_h', ROUND(v_duree_min::numeric / 60, 2)
  );
END;
$function$;

-- ============================================================
-- 3. Sub-routine : annuler une mission complètement (post-pointage)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_annuler_mission_complete(
  p_mission_id uuid,
  p_motif text,
  p_source_litige_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_presence_id uuid;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  -- Marquer la mission comme annulée par litige
  UPDATE public.missions SET
    statut = 'ANNULEE_LITIGE',
    modifie_le = NOW()
  WHERE id = p_mission_id;

  -- Invalider la presence si elle existe
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = p_mission_id LIMIT 1;
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.presences SET
      heures_ajustees_litige = 0,
      ajustement_litige_id = p_source_litige_id,
      motif_litige = p_motif,
      modifie_le = NOW()
    WHERE id = v_presence_id;
  END IF;

  -- Enqueue side-effects (avoir total + Stripe refund + Chorus + DPAE si CDD)
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('STRIPE_REFUND_TOTAL', jsonb_build_object('mission_id', p_mission_id, 'motif', p_motif),
     'LITIGE_EXEC', p_source_litige_id),
    ('CHORUS_RECYCLER_FACTURE', jsonb_build_object('mission_id', p_mission_id, 'motif', 'ANNULATION'),
     'LITIGE_EXEC', p_source_litige_id),
    ('DPAE_ANNULATION', jsonb_build_object('mission_id', p_mission_id, 'motif', p_motif),
     'LITIGE_EXEC', p_source_litige_id),
    ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', p_mission_id, 'type', 'TOTAL', 'motif_avoir', 'ANNULATION_MISSION_SOIGNANT'),
     'LITIGE_EXEC', p_source_litige_id);

  RETURN jsonb_build_object('success', true, 'mission_id', p_mission_id, 'presence_id', v_presence_id);
END;
$function$;

-- ============================================================
-- 4. Sub-routine : compensation partielle (% de réduction)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_appliquer_compensation_partielle(
  p_mission_id uuid,
  p_pourcentage numeric,
  p_motif text,
  p_source_litige_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_presence_id uuid;
  v_taux numeric;
BEGIN
  IF p_pourcentage <= 0 OR p_pourcentage > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pourcentage doit être entre 0 et 100');
  END IF;

  v_taux := (100 - p_pourcentage) / 100.0;

  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = p_mission_id LIMIT 1;
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.presences SET
      heures_ajustees_litige = ROUND(duree_brute_min::numeric / 60 * v_taux, 2),
      ajustement_litige_id = p_source_litige_id,
      motif_litige = p_motif,
      modifie_le = NOW()
    WHERE id = v_presence_id;
  END IF;

  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('STRIPE_REFUND_PARTIEL', jsonb_build_object('mission_id', p_mission_id, 'pourcentage', p_pourcentage),
     'LITIGE_EXEC', p_source_litige_id),
    ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', p_mission_id, 'type', 'PARTIEL',
                                                  'pourcentage', p_pourcentage, 'motif_avoir', 'COMPENSATION_PARTIELLE'),
     'LITIGE_EXEC', p_source_litige_id);

  RETURN jsonb_build_object('success', true, 'mission_id', p_mission_id,
    'pourcentage_compensation', p_pourcentage, 'presence_id', v_presence_id);
END;
$function$;

-- ============================================================
-- 5. Orchestrateur principal : fn_executer_modifications_litige
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_executer_modifications_litige(
  p_litige_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_litige RECORD;
  v_payload jsonb;
  v_type text;
  v_mods jsonb;
  v_presence_id uuid;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_h_arrivee timestamptz;
  v_h_depart timestamptz;
  v_uid uuid := auth.uid();
BEGIN
  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  -- Idempotence : si déjà exécuté, retourner OK sans rejouer
  IF v_litige.modifications_executees THEN
    RETURN jsonb_build_object('success', true, 'already_executed', true,
                                'executees_a', v_litige.modifications_executees_a);
  END IF;

  -- Vérifier qu'on a un accord double + payload
  IF NOT (COALESCE(v_litige.accord_soignant, false) AND COALESCE(v_litige.accord_etablissement, false)) THEN
    -- OK si médiation admin (resolu_par admin) ou statut RESOLU_ADMIN
    IF v_litige.statut NOT IN ('RESOLU', 'RESOLU_ADMIN', 'CLOTURE') THEN
      RETURN jsonb_build_object('success', false, 'error', 'Litige sans double accord ni résolution admin');
    END IF;
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NULL THEN
    -- Pas de payload structuré = ACCORD_SANS_MODIFICATION
    UPDATE public.litiges SET
      modifications_executees = true,
      modifications_executees_a = NOW(),
      modifications_executees_par = v_uid
    WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'type', 'ACCORD_SANS_MODIFICATION');
  END IF;

  v_type := v_payload->>'type';
  v_mods := COALESCE(v_payload->'modifications', '{}'::jsonb);

  -- Récupérer presence_id si applicable
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = v_litige.mission_id LIMIT 1;

  IF v_type = 'ACCORD_SANS_MODIFICATION' THEN
    v_results := v_results || jsonb_build_object('type', v_type, 'success', true);

  ELSIF v_type = 'MODIFICATION_HORAIRES' AND v_presence_id IS NOT NULL THEN
    v_h_arrivee := (v_mods->>'pointage_arrivee_le')::timestamptz;
    v_h_depart := (v_mods->>'pointage_depart_le')::timestamptz;
    IF v_h_arrivee IS NULL OR v_h_depart IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'pointage_arrivee_le et pointage_depart_le requis pour MODIFICATION_HORAIRES');
    END IF;
    v_result := public.fn_modifier_horaires_presence(v_presence_id, v_h_arrivee, v_h_depart,
                                                       v_payload->>'justification');
    v_results := v_results || v_result;
    -- Enqueue avoir/regen facture
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION',
            jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'AJUSTEMENT_HORAIRES',
                                'motif_avoir', 'MODIFICATION_HORAIRES'),
            'LITIGE_EXEC', p_litige_id);

  ELSIF v_type = 'ANNULATION_TOTALE' THEN
    v_result := public.fn_annuler_mission_complete(v_litige.mission_id,
                                                     v_payload->>'justification', p_litige_id);
    v_results := v_results || v_result;

  ELSIF v_type = 'COMPENSATION_PARTIELLE' THEN
    v_result := public.fn_appliquer_compensation_partielle(v_litige.mission_id,
                                                             (v_mods->>'pourcentage_compensation')::numeric,
                                                             v_payload->>'justification', p_litige_id);
    v_results := v_results || v_result;

  ELSIF v_type = 'MODIFICATION_MONTANT' THEN
    -- Recalcul indirect : on traite comme un avoir + nouvelle facture, pas de modif presences
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION',
            jsonb_build_object('mission_id', v_litige.mission_id,
                                'type', 'MODIFICATION_MONTANT',
                                'nouveau_montant', v_mods->>'montant_total_corrige',
                                'motif_avoir', 'MODIFICATION_HORAIRES'),
            'LITIGE_EXEC', p_litige_id);
    v_results := v_results || jsonb_build_object('type', v_type, 'success', true,
                                                    'nouveau_montant', v_mods->>'montant_total_corrige');

  ELSIF v_type = 'MIXTE' THEN
    -- Combine MODIFICATION_HORAIRES + MODIFICATION_MONTANT
    IF v_presence_id IS NOT NULL AND v_mods ? 'pointage_arrivee_le' AND v_mods ? 'pointage_depart_le' THEN
      v_h_arrivee := (v_mods->>'pointage_arrivee_le')::timestamptz;
      v_h_depart := (v_mods->>'pointage_depart_le')::timestamptz;
      v_result := public.fn_modifier_horaires_presence(v_presence_id, v_h_arrivee, v_h_depart,
                                                         v_payload->>'justification');
      v_results := v_results || v_result;
    END IF;
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION',
            jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'MIXTE',
                                'motif_avoir', 'LITIGE_ACCORD_MUTUEL'),
            'LITIGE_EXEC', p_litige_id);

  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Type de modification non supporté : ' || COALESCE(v_type, 'NULL'));
  END IF;

  -- Marquer comme exécuté
  UPDATE public.litiges SET
    modifications_executees = true,
    modifications_executees_a = NOW(),
    modifications_executees_par = v_uid
  WHERE id = p_litige_id;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    COALESCE(v_uid, '00000000-0000-0000-0000-000000000000'),
    CASE WHEN v_uid IS NULL THEN 'SYSTEME' ELSE 'SYSTEM' END,
    'SYSTEM', 'litige', p_litige_id,
    jsonb_build_object(
      'evenement', 'LITIGE_MODIFICATIONS_EXECUTEES',
      'type', v_type,
      'mission_id', v_litige.mission_id,
      'results', v_results
    )
  );

  RETURN jsonb_build_object('success', true, 'type', v_type, 'results', v_results);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_executer_modifications_litige(uuid) TO authenticated;

-- ============================================================
-- 6. Wrapper fn_cloturer_litige_avec_payload (UI-facing)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_avec_payload(
  p_litige_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige RECORD;
  v_role text;
  v_other_role text;
  v_exec_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  -- Identifier le rôle de l'appelant
  IF v_litige.soignant_id = v_uid THEN
    v_role := 'soignant'; v_other_role := 'etablissement';
  ELSIF v_litige.etablissement_id = v_uid OR mon_etablissement_id() = v_litige.etablissement_id THEN
    v_role := 'etablissement'; v_other_role := 'soignant';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  -- Stocker le payload sur le litige (pour que l'autre partie le voie)
  UPDATE public.litiges SET
    payload_modifications = p_payload,
    -- L'appelant donne son accord auto
    accord_soignant = CASE WHEN v_role = 'soignant' THEN true ELSE accord_soignant END,
    accord_soignant_le = CASE WHEN v_role = 'soignant' THEN NOW() ELSE accord_soignant_le END,
    accord_etablissement = CASE WHEN v_role = 'etablissement' THEN true ELSE accord_etablissement END,
    accord_etablissement_le = CASE WHEN v_role = 'etablissement' THEN NOW() ELSE accord_etablissement_le END
  WHERE id = p_litige_id;

  -- Si les 2 parties sont d'accord, clôturer + exécuter
  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF COALESCE(v_litige.accord_soignant, false) AND COALESCE(v_litige.accord_etablissement, false) THEN
    UPDATE public.litiges SET
      statut = 'RESOLU',
      resolu_le = COALESCE(resolu_le, NOW()),
      resolu_par = v_uid,
      resolution = COALESCE(p_payload->>'justification', 'Accord mutuel sur modifications')
    WHERE id = p_litige_id;

    v_exec_result := public.fn_executer_modifications_litige(p_litige_id);

    RETURN jsonb_build_object('success', true, 'statut', 'RESOLU',
                                'execution', v_exec_result);
  END IF;

  -- Sinon, en attente de l'autre partie
  RETURN jsonb_build_object('success', true, 'statut', 'EN_ATTENTE_ACCORD_AUTRE_PARTIE',
                              'role_en_attente', v_other_role,
                              'payload_propose', p_payload);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_cloturer_litige_avec_payload(uuid, jsonb) TO authenticated;

-- ============================================================
-- 7. Audit
-- ============================================================
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR2_LITIGES_EXECUTION_INSTALLED',
    'pr', 'PR 2 Sprint 3.5',
    'rpcs', ARRAY['fn_modifier_horaires_presence', 'fn_annuler_mission_complete',
                   'fn_appliquer_compensation_partielle', 'fn_executer_modifications_litige',
                   'fn_cloturer_litige_avec_payload'],
    'tables', ARRAY['externalisation_actions'],
    'note', 'Side-effects Stripe/Chorus/DPAE enqueués dans externalisation_actions, traités par cron edge function (Sprint 4 pour le cron worker).'
  )
);
