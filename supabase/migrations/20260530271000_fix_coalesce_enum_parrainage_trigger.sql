-- P0 : fn_trg_valider_parrainage_soignant_premiere_mission faisait COALESCE(OLD.statut, '')
-- où '' est casté vers l'enum statut_mission (invalide) → TOUT changement de statut de
-- mission plantait (assignation, terminaison, transitions auto). Fix : OLD.statut::text.
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parrainage RECORD; v_parrain_a_mission BOOLEAN; v_nb_filleuls_actifs INT; v_filleul_parrainage RECORD;
BEGIN
  IF NEW.statut <> 'TERMINEE' OR COALESCE(OLD.statut::text, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_parrainage FROM parrainages WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE' LIMIT 1;
  IF v_parrainage IS NOT NULL THEN
    SELECT EXISTS(SELECT 1 FROM missions WHERE soignant_assigne_id = v_parrainage.parrain_id AND statut = 'TERMINEE' LIMIT 1) INTO v_parrain_a_mission;
    IF v_parrain_a_mission THEN
      SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages WHERE parrain_id = v_parrainage.parrain_id AND statut IN ('VALIDE','FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL','PRIME_VERSEE');
      IF v_nb_filleuls_actifs < 20 THEN
        UPDATE parrainages SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW() WHERE id = v_parrainage.id;
        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien) VALUES (v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE', 'Filleul activé !', 'Votre filleul a terminé sa 1ère mission. La prime de 50€ sera versée après 100€ de commission encaissée.', '/soignant/parrainage');
        PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME', p_action := 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF', p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id, p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'mission_id', NEW.id));
      ELSE
        UPDATE parrainages SET statut = 'EXPIRED' WHERE id = v_parrainage.id;
      END IF;
    END IF;
  END IF;
  FOR v_filleul_parrainage IN SELECT p.*, s.premiere_mission_le FROM parrainages p JOIN soignants s ON s.id = p.filleul_id WHERE p.parrain_id = NEW.soignant_assigne_id AND p.statut = 'EN_ATTENTE' AND s.premiere_mission_le IS NOT NULL
  LOOP
    SELECT COUNT(*) INTO v_nb_filleuls_actifs FROM parrainages WHERE parrain_id = NEW.soignant_assigne_id AND statut IN ('VALIDE','FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL','PRIME_VERSEE');
    IF v_nb_filleuls_actifs < 20 THEN
      UPDATE parrainages SET statut = 'FILLEUL_ACTIF', filleul_active_le = NOW(), valide_le = NOW() WHERE id = v_filleul_parrainage.id;
      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien) VALUES (NEW.soignant_assigne_id, 'SOIGNANT', 'PARRAINAGE', 'Filleul activé !', 'Votre filleul a terminé sa 1ère mission.', '/soignant/parrainage');
    END IF;
  END LOOP;
  RETURN NEW;
END;
$function$;
NOTIFY pgrst, 'reload schema';
