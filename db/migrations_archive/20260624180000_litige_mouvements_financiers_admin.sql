-- Règle : tout MOUVEMENT FINANCIER issu d'un litige doit être AUTORISÉ par l'admin.
--
-- Avant : fn_cloturer_litige_avec_payload exécutait automatiquement les modifications
-- financières (avoir, montant corrigé, compensation, annulation/remboursement) dès que
-- les DEUX parties (soignant + établissement) étaient d'accord — sans aucun admin.
--
-- Décision produit : les parties peuvent toujours PROPOSER et s'accorder sur un montant,
-- mais l'exécution d'un mouvement financier passe désormais par la validation admin.
-- Les accords NON financiers (clôture simple sans impact paie) restent auto entre parties.

-- 1. fn_cloturer_litige_avec_payload : si l'accord double porte sur un mouvement
--    financier → REVUE_ADMIN (proposition en attente de validation admin), sans exécuter.
--    Sinon (ACCORD_SANS_MODIFICATION) → clôture auto + exécution no-op comme avant.
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_avec_payload(p_litige_id uuid, p_payload jsonb)
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
  v_type text;
  v_financier boolean;
  v_admin_ids uuid[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  IF v_litige.soignant_id = v_uid THEN
    v_role := 'soignant'; v_other_role := 'etablissement';
  ELSIF v_litige.etablissement_id = v_uid OR mon_etablissement_id() = v_litige.etablissement_id THEN
    v_role := 'etablissement'; v_other_role := 'soignant';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.litiges SET
    payload_modifications = p_payload,
    accord_soignant = CASE WHEN v_role = 'soignant' THEN true ELSE accord_soignant END,
    accord_soignant_le = CASE WHEN v_role = 'soignant' THEN NOW() ELSE accord_soignant_le END,
    accord_etablissement = CASE WHEN v_role = 'etablissement' THEN true ELSE accord_etablissement END,
    accord_etablissement_le = CASE WHEN v_role = 'etablissement' THEN NOW() ELSE accord_etablissement_le END
  WHERE id = p_litige_id;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF COALESCE(v_litige.accord_soignant, false) AND COALESCE(v_litige.accord_etablissement, false) THEN
    v_type := v_litige.payload_modifications->>'type';
    v_financier := (v_litige.payload_modifications IS NOT NULL
                    AND COALESCE(v_type, 'ACCORD_SANS_MODIFICATION') <> 'ACCORD_SANS_MODIFICATION');

    IF v_financier THEN
      -- Mouvement financier : accord des parties enregistré, mais EN ATTENTE de validation admin.
      UPDATE public.litiges SET
        statut = 'REVUE_ADMIN',
        resolution = COALESCE(p_payload->>'justification', 'Accord des parties — validation admin requise')
      WHERE id = p_litige_id;

      -- Notifier les admins qu'un accord financier attend leur validation.
      v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());
      IF array_length(v_admin_ids, 1) > 0 THEN
        INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
        SELECT 'PUSH_NOTIF', jsonb_build_object(
          'destinataire_id', uid, 'type_evenement', 'ALERTE_ADMIN',
          'titre', '⚖️ Accord financier à valider',
          'corps', 'Les parties se sont accordées sur un ajustement financier (' || COALESCE(v_type, '?') || '). Validation admin requise.',
          'lien', '/admin/litiges'
        ), 'LITIGE_ACCORD_FINANCIER', p_litige_id FROM unnest(v_admin_ids) AS uid;
      END IF;

      RETURN jsonb_build_object('success', true, 'statut', 'EN_ATTENTE_VALIDATION_ADMIN',
                                'type', v_type, 'payload_propose', v_litige.payload_modifications);
    ELSE
      -- Accord sans impact financier : clôture auto + exécution no-op.
      UPDATE public.litiges SET
        statut = 'RESOLU',
        resolu_le = COALESCE(resolu_le, NOW()),
        resolu_par = v_uid,
        resolution = COALESCE(p_payload->>'justification', 'Accord mutuel sans modification')
      WHERE id = p_litige_id;

      PERFORM set_config('jolene.litige_exec_ok', 'true', true);
      v_exec_result := public.fn_executer_modifications_litige(p_litige_id);
      RETURN jsonb_build_object('success', true, 'statut', 'RESOLU', 'execution', v_exec_result);
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'statut', 'EN_ATTENTE_ACCORD_AUTRE_PARTIE',
                            'role_en_attente', v_other_role, 'payload_propose', p_payload);
END;
$function$;

-- 2. fn_executer_modifications_litige : gate. Exécution réservée à l'admin OU au contexte
--    interne autorisé (flag jolene.litige_exec_ok posé par cloture non-financière / validation admin).
--    + REVOKE EXECUTE aux authenticated (empêche un appel direct d'une partie pour contourner).
CREATE OR REPLACE FUNCTION public.fn_executer_modifications_litige(p_litige_id uuid)
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
  -- GATE : admin OU contexte interne explicitement autorisé.
  IF NOT (public.est_admin() OR COALESCE(current_setting('jolene.litige_exec_ok', true), '') = 'true') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Exécution réservée à l''administrateur (autorisation des mouvements financiers).');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  IF v_litige.modifications_executees THEN
    RETURN jsonb_build_object('success', true, 'already_executed', true,
                                'executees_a', v_litige.modifications_executees_a);
  END IF;

  IF NOT (COALESCE(v_litige.accord_soignant, false) AND COALESCE(v_litige.accord_etablissement, false)) THEN
    IF v_litige.statut NOT IN ('RESOLU', 'RESOLU_ADMIN', 'CLOTURE') THEN
      RETURN jsonb_build_object('success', false, 'error', 'Litige sans double accord ni résolution admin');
    END IF;
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NULL THEN
    UPDATE public.litiges SET
      modifications_executees = true, modifications_executees_a = NOW(), modifications_executees_par = v_uid
    WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'type', 'ACCORD_SANS_MODIFICATION');
  END IF;

  v_type := v_payload->>'type';
  v_mods := COALESCE(v_payload->'modifications', '{}'::jsonb);
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = v_litige.mission_id LIMIT 1;

  IF v_type = 'ACCORD_SANS_MODIFICATION' THEN
    v_results := v_results || jsonb_build_object('type', v_type, 'success', true);
  ELSIF v_type = 'MODIFICATION_HORAIRES' AND v_presence_id IS NOT NULL THEN
    v_h_arrivee := (v_mods->>'pointage_arrivee_le')::timestamptz;
    v_h_depart := (v_mods->>'pointage_depart_le')::timestamptz;
    IF v_h_arrivee IS NULL OR v_h_depart IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'pointage_arrivee_le et pointage_depart_le requis pour MODIFICATION_HORAIRES');
    END IF;
    v_result := public.fn_modifier_horaires_presence(v_presence_id, v_h_arrivee, v_h_depart, v_payload->>'justification');
    v_results := v_results || v_result;
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'AJUSTEMENT_HORAIRES', 'motif_avoir', 'MODIFICATION_HORAIRES'), 'LITIGE_EXEC', p_litige_id);
  ELSIF v_type = 'ANNULATION_TOTALE' THEN
    v_result := public.fn_annuler_mission_complete(v_litige.mission_id, v_payload->>'justification', p_litige_id);
    v_results := v_results || v_result;
  ELSIF v_type = 'COMPENSATION_PARTIELLE' THEN
    v_result := public.fn_appliquer_compensation_partielle(v_litige.mission_id, (v_mods->>'pourcentage_compensation')::numeric, v_payload->>'justification', p_litige_id);
    v_results := v_results || v_result;
  ELSIF v_type = 'MODIFICATION_MONTANT' THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'MODIFICATION_MONTANT', 'nouveau_montant', v_mods->>'montant_total_corrige', 'motif_avoir', 'MODIFICATION_HORAIRES'), 'LITIGE_EXEC', p_litige_id);
    v_results := v_results || jsonb_build_object('type', v_type, 'success', true, 'nouveau_montant', v_mods->>'montant_total_corrige');
  ELSIF v_type = 'MIXTE' THEN
    IF v_presence_id IS NOT NULL AND v_mods ? 'pointage_arrivee_le' AND v_mods ? 'pointage_depart_le' THEN
      v_h_arrivee := (v_mods->>'pointage_arrivee_le')::timestamptz;
      v_h_depart := (v_mods->>'pointage_depart_le')::timestamptz;
      v_result := public.fn_modifier_horaires_presence(v_presence_id, v_h_arrivee, v_h_depart, v_payload->>'justification');
      v_results := v_results || v_result;
    END IF;
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'MIXTE', 'motif_avoir', 'LITIGE_ACCORD_MUTUEL'), 'LITIGE_EXEC', p_litige_id);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Type de modification non supporté : ' || COALESCE(v_type, 'NULL'));
  END IF;

  UPDATE public.litiges SET
    modifications_executees = true, modifications_executees_a = NOW(), modifications_executees_par = v_uid
  WHERE id = p_litige_id;

  INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (COALESCE(v_uid, '00000000-0000-0000-0000-000000000000'),
    CASE WHEN v_uid IS NULL THEN 'SYSTEME' ELSE 'SYSTEM' END,
    'SYSTEM', 'litige', p_litige_id,
    jsonb_build_object('evenement', 'LITIGE_MODIFICATIONS_EXECUTEES', 'type', v_type, 'mission_id', v_litige.mission_id, 'results', v_results));

  RETURN jsonb_build_object('success', true, 'type', v_type, 'results', v_results);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_executer_modifications_litige(uuid) FROM authenticated;

-- 3. fn_admin_valider_accord_litige : l'admin valide l'accord financier proposé par les
--    parties (exécute le payload tel quel). Pour AJUSTER différemment, l'admin utilise
--    fn_admin_resoudre_litige (déjà en place, modale AdminLitiges).
CREATE OR REPLACE FUNCTION public.fn_admin_valider_accord_litige(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige RECORD;
  v_exec jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;
  IF v_litige.payload_modifications IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun accord à valider sur ce litige');
  END IF;

  UPDATE public.litiges SET
    statut = 'RESOLU_ADMIN',
    resolu_le = COALESCE(resolu_le, NOW()),
    resolu_par = v_uid
  WHERE id = p_litige_id;

  PERFORM set_config('jolene.litige_exec_ok', 'true', true);
  v_exec := public.fn_executer_modifications_litige(p_litige_id);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_ACCORD_VALIDE_ADMIN', p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('execution', v_exec));

  RETURN jsonb_build_object('success', true, 'statut', 'RESOLU_ADMIN', 'execution', v_exec);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_valider_accord_litige(uuid) TO authenticated;
