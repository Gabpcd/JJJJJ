-- Câblage prime_parrainage_eur sur fn_param_num.
-- Le système de parrainage est entièrement automatisé (triggers + worker payout).
-- Le montant 50 € était codé en dur dans 3 fonctions — désormais lu dynamiquement.

UPDATE public.parametres_systeme SET valeur = 50, cablee = true WHERE cle = 'prime_parrainage_eur';

-- 1) fn_appliquer_parrainage : le message mentionne le montant.
CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parrain RECORD;
  v_filleul_id UUID := auth.uid();
  v_nb_filleuls_valides INT;
  v_parrainage_id UUID;
  v_ip TEXT;
  v_user_agent TEXT;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 50))::integer;
BEGIN
  IF v_filleul_id IS NULL THEN RETURN '{"error":"Non authentifié"}'::JSONB; END IF;
  SELECT * INTO v_parrain FROM soignants WHERE code_parrainage = UPPER(TRIM(p_code)) AND supprime_le IS NULL;
  IF v_parrain IS NULL THEN RETURN '{"error":"Code de parrainage invalide"}'::JSONB; END IF;
  IF v_parrain.id = v_filleul_id THEN RETURN '{"error":"Vous ne pouvez pas vous parrainer vous-même"}'::JSONB; END IF;
  SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages WHERE parrain_id = v_parrain.id AND statut IN ('VALIDE','FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL','PRIME_VERSEE');
  IF v_nb_filleuls_valides >= 20 THEN RETURN '{"error":"Le parrain a atteint la limite de 20 filleuls validés"}'::JSONB; END IF;
  IF EXISTS (SELECT 1 FROM parrainages WHERE filleul_id = v_filleul_id) THEN RETURN '{"error":"Vous avez déjà appliqué un code de parrainage"}'::JSONB; END IF;
  INSERT INTO parrainages (parrain_id, filleul_id, code_parrainage, statut) VALUES (v_parrain.id, v_filleul_id, UPPER(TRIM(p_code)), 'EN_ATTENTE') RETURNING id INTO v_parrainage_id;
  UPDATE soignants SET parraine_par = v_parrain.id WHERE id = v_filleul_id AND parraine_par IS NULL;
  BEGIN
    v_ip := COALESCE(current_setting('request.headers', true)::json->>'x-forwarded-for', current_setting('request.headers', true)::json->>'x-real-ip', 'unknown');
    v_user_agent := COALESCE(current_setting('request.headers', true)::json->>'user-agent', 'unknown');
  EXCEPTION WHEN OTHERS THEN v_ip := 'unknown'; v_user_agent := 'unknown';
  END;
  IF v_ip <> 'unknown' THEN
    DECLARE v_parrain_last_ip TEXT;
    BEGIN
      SELECT (details->>'ip')::text INTO v_parrain_last_ip FROM journaux_audit WHERE acteur_id = v_parrain.id AND action = 'CONNEXION' ORDER BY cree_le DESC LIMIT 1;
      IF v_parrain_last_ip IS NOT NULL AND v_parrain_last_ip = v_ip THEN
        INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail) VALUES (v_parrainage_id, 'MEME_IP', jsonb_build_object('ip', v_ip, 'parrain_id', v_parrain.id, 'filleul_id', v_filleul_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail) VALUES (v_parrainage_id, 'MEME_DEVICE', jsonb_build_object('ip_filleul', v_ip, 'user_agent_filleul', v_user_agent, 'filleul_id', v_filleul_id, 'parrain_id', v_parrain.id));
  RETURN jsonb_build_object('success', true, 'message', 'Code accepté ! Votre prime de ' || v_prime || '€ sera versée après votre 1ère mission terminée et 100€ de commission encaissée par Jolene.');
END;
$function$;

-- 2) fn_trg_parrainage_commission_encaissee : payload + notifications.
CREATE OR REPLACE FUNCTION public.fn_trg_parrainage_commission_encaissee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mission RECORD; v_parrainage RECORD; v_commission NUMERIC; v_new_cumul NUMERIC; v_nb_fraude_signals INT;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 50))::integer;
BEGIN
  IF NEW.statut <> 'PAYEE' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.statut, '') = 'PAYEE' THEN RETURN NEW; END IF;
  IF NEW.mission_id IS NULL THEN RETURN NEW; END IF;
  SELECT id, soignant_assigne_id INTO v_mission FROM missions WHERE id = NEW.mission_id;
  IF v_mission IS NULL OR v_mission.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = v_mission.soignant_assigne_id AND statut IN ('FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL') LIMIT 1;
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;
  v_commission := COALESCE(NEW.montant_ht, 0);
  IF v_commission <= 0 THEN RETURN NEW; END IF;
  v_new_cumul := COALESCE(v_parrainage.commission_cumulee_filleul, 0) + v_commission;
  UPDATE parrainages SET commission_cumulee_filleul = v_new_cumul WHERE id = v_parrainage.id;
  IF v_new_cumul >= 100 AND v_parrainage.statut = 'FILLEUL_ACTIF' THEN
    SELECT COUNT(*) INTO v_nb_fraude_signals FROM parrainage_fraude_signals WHERE parrainage_id = v_parrainage.id AND type = 'MEME_IP';
    IF v_nb_fraude_signals > 0 THEN
      UPDATE parrainages SET statut = 'FRAUDE' WHERE id = v_parrainage.id;
      PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME', p_action := 'PARRAINAGE_SOIGNANT_FRAUDE', p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id, p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'commission_cumulee', v_new_cumul, 'raison', 'MEME_IP détectée à inscription'));
      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien) SELECT id, 'ADMIN_PLATEFORME', 'SYSTEM', 'Parrainage fraude détectée', 'Parrainage ' || v_parrainage.id::text || ' : même IP parrain/filleul. Versement bloqué.', '/admin/utilisateurs' FROM soignants WHERE role = 'ADMIN_PLATEFORME' LIMIT 3;
      RETURN NEW;
    END IF;
    UPDATE parrainages SET statut = 'VALIDE_EN_ATTENTE_SEUIL' WHERE id = v_parrainage.id;
    PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME', p_action := 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT', p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id, p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'commission_cumulee', v_new_cumul));
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id) VALUES ('RECOMPENSE_PARRAINAGE_SOIGNANT', jsonb_build_object('parrainage_id', v_parrainage.id, 'parrain_id', v_parrainage.parrain_id, 'filleul_id', v_parrainage.filleul_id, 'montant_parrain', v_prime, 'montant_filleul', v_prime, 'commission_cumulee', v_new_cumul), 'parrainage_soignant', v_parrainage.id);
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien) VALUES (v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE', 'Prime de parrainage de ' || v_prime || '€ !', 'Votre filleul a généré suffisamment de commission. ' || v_prime || '€ vont être versés sur votre compte.', '/soignant/parrainage'), (v_parrainage.filleul_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE', 'Prime de parrainage de ' || v_prime || '€ !', 'Félicitations ! ' || v_prime || '€ de prime de parrainage vont être versés sur votre compte.', '/soignant/parrainage');
  END IF;
  RETURN NEW;
END;
$function$;
