-- Bug détecté par démarrage monitoring iter5 : 2 bugs prod fixés
--
-- Bug #1 : cron auto-transitions-missions échoue à chaque run
--   Erreur : "Transition de statut invalide : OUVERTE → EXPIREE"
--   Le statut EXPIREE existe dans l'enum statut_mission mais n'est pas dans
--   les transitions valides du trigger fn_valider_transition_statut_mission.
--   Fix : ajouter ('OUVERTE', 'EXPIREE') et ('ASSIGNEE', 'EXPIREE').
--
-- Bug #2 : trigger parrainage soignant crashe avec
--   "invalid input value for enum statut_mission: \"\""
--   COALESCE(OLD.statut, '') tente de cast '' en enum.
--   Fix : OLD.statut::text avant COALESCE.

-- Fix #1 : transitions OUVERTE/ASSIGNEE → EXPIREE
CREATE OR REPLACE FUNCTION public.fn_valider_transition_statut_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    v_transitions_valides text[][];
    v_valide boolean := false;
    v_pair text[];
BEGIN
    IF NEW.statut IS NOT DISTINCT FROM OLD.statut THEN
        RETURN NEW;
    END IF;

    v_transitions_valides := ARRAY[
        ARRAY['OUVERTE', 'ASSIGNEE'],
        ARRAY['OUVERTE', 'ANNULEE_PAR_ETABLISSEMENT'],
        ARRAY['OUVERTE', 'EXPIREE'],
        ARRAY['ASSIGNEE', 'EN_COURS'],
        ARRAY['ASSIGNEE', 'OUVERTE'],
        ARRAY['ASSIGNEE', 'ANNULEE_PAR_ETABLISSEMENT'],
        ARRAY['ASSIGNEE', 'ANNULEE_PAR_SOIGNANT'],
        ARRAY['ASSIGNEE', 'ABSENCE'],
        ARRAY['ASSIGNEE', 'EXPIREE'],
        ARRAY['EN_COURS', 'TERMINEE'],
        ARRAY['EN_COURS', 'ABSENCE'],
        ARRAY['EN_COURS', 'LITIGE'],
        ARRAY['EN_COURS', 'ANNULEE_PAR_ETABLISSEMENT'],
        ARRAY['LITIGE', 'TERMINEE'],
        ARRAY['LITIGE', 'ANNULEE_PAR_ETABLISSEMENT']
    ];

    FOREACH v_pair SLICE 1 IN ARRAY v_transitions_valides LOOP
        IF OLD.statut::text = v_pair[1] AND NEW.statut::text = v_pair[2] THEN
            v_valide := true;
            EXIT;
        END IF;
    END LOOP;

    IF NOT v_valide AND NOT est_admin() THEN
        RAISE EXCEPTION 'Transition de statut invalide : % → %', OLD.statut, NEW.statut;
    END IF;

    RETURN NEW;
END;
$function$;

-- Fix #2 : COALESCE(OLD.statut::text, '') au lieu de COALESCE(OLD.statut, '')
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_soignant_premiere_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_parrainage RECORD;
  v_nb_filleuls_valides INT;
BEGIN
  IF NEW.statut::text <> 'TERMINEE' OR COALESCE(OLD.statut::text, '') = 'TERMINEE' THEN RETURN NEW; END IF;
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages
  WHERE filleul_id = NEW.soignant_assigne_id AND statut = 'EN_ATTENTE'
  LIMIT 1;

  IF v_parrainage IS NOT NULL THEN
    SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages
    WHERE parrain_id = v_parrainage.parrain_id AND statut = 'VALIDE';

    IF v_nb_filleuls_valides < 20 THEN
      UPDATE parrainages SET statut = 'VALIDE', valide_le = NOW()
      WHERE id = v_parrainage.id;

      UPDATE soignants SET heures_cumulees = COALESCE(heures_cumulees, 0) + 50
      WHERE id IN (v_parrainage.parrain_id, v_parrainage.filleul_id);

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        v_parrainage.parrain_id, 'SOIGNANT', 'PARRAINAGE',
        '🎉 Filleul validé !',
        'Votre filleul a terminé sa 1ère mission. Vous gagnez +50h cumulées !',
        '/soignant/parrainage'
      );

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_parrainage.parrain_id, p_type_acteur := 'SYSTEME',
        p_action := 'PARRAINAGE_ETAB_VALIDE',
        p_type_ressource := 'parrainage', p_id_ressource := v_parrainage.id,
        p_details := jsonb_build_object('filleul_id', v_parrainage.filleul_id, 'mission_declencheur', NEW.id)
      );
    ELSE
      UPDATE parrainages SET statut = 'EXPIRED' WHERE id = v_parrainage.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
