-- Partie 2 — Step A : étendre fn_geler_mission_a_assignation pour figer
-- strategie_facturation au gel selon (fin_le::date - debut_le::date).
-- ≤ 7 j = FINALE_UNIQUE, > 7 j = HEBDO_ET_FINALE.
-- Une prolongation post-gel ne modifie pas la stratégie (D8).

CREATE OR REPLACE FUNCTION public.fn_geler_mission_a_assignation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab RECORD;
  v_groupe_taux numeric;
  v_taux_comm_resolved numeric;
  v_champ_modifie text;
  v_new_code text;
  v_duree_jours integer;
  v_strategie public.strategie_facturation;
BEGIN
  IF OLD.statut = 'OUVERTE' AND NEW.statut = 'ASSIGNEE' THEN
    SELECT
      COALESCE(e.taux_majoration_nuit_pourcent, 25) AS taux_nuit,
      COALESCE(e.taux_majoration_dimanche_pourcent, 25) AS taux_dim,
      COALESCE(e.taux_majoration_ferie_pourcent, 50) AS taux_fer,
      COALESCE(e.heure_debut_nuit, '21:00'::time) AS h_debut_nuit,
      COALESCE(e.heure_fin_nuit, '06:00'::time) AS h_fin_nuit,
      e.taux_commission_negocie AS taux_comm_etab,
      e.groupe_sante_id AS groupe_id
    INTO v_etab
    FROM etablissements e WHERE e.id = NEW.etablissement_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Établissement % introuvable', NEW.etablissement_id USING ERRCODE = 'foreign_key_violation'; END IF;

    -- Cascade taux commission : etab > groupe > 15
    IF v_etab.taux_comm_etab IS NOT NULL THEN
      v_taux_comm_resolved := v_etab.taux_comm_etab;
    ELSIF v_etab.groupe_id IS NOT NULL THEN
      SELECT taux_commission_negocie INTO v_groupe_taux
      FROM groupes_sante WHERE id = v_etab.groupe_id;
      v_taux_comm_resolved := COALESCE(v_groupe_taux, 15);
    ELSE
      v_taux_comm_resolved := 15;
    END IF;

    NEW.taux_horaire_base_fige := NEW.taux_horaire_base;
    NEW.taux_majoration_nuit_fige := v_etab.taux_nuit;
    NEW.taux_majoration_dimanche_fige := v_etab.taux_dim;
    NEW.taux_majoration_ferie_fige := v_etab.taux_fer;
    NEW.heure_debut_nuit_fige := v_etab.h_debut_nuit;
    NEW.heure_fin_nuit_fige := v_etab.h_fin_nuit;
    NEW.taux_commission_fige := v_taux_comm_resolved;
    NEW.fige_le := now();

    -- Step A : figer strategie_facturation selon durée
    -- (NEW.fin_le::date - NEW.debut_le::date) = nombre de jours civils.
    -- Mission lun→dim de la même semaine = 6 jours. Mission lun S1 → mar S2 = 8 jours.
    v_duree_jours := (NEW.fin_le::date - NEW.debut_le::date);
    v_strategie := CASE
      WHEN v_duree_jours > 7 THEN 'HEBDO_ET_FINALE'::public.strategie_facturation
      ELSE 'FINALE_UNIQUE'::public.strategie_facturation
    END;
    NEW.strategie_facturation := v_strategie;

    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
    WHILE EXISTS (SELECT 1 FROM missions WHERE code_pointage_actif = v_new_code AND id != NEW.id AND statut IN ('ASSIGNEE','EN_COURS')) LOOP
      v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
    END LOOP;
    NEW.code_pointage_actif := v_new_code;
    NEW.code_pointage_hmac := CASE WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL
      THEN encode(extensions.hmac(NEW.id::text || ':' || v_new_code, current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex') ELSE NULL END;
    NEW.prochain_type_scan := 'OUVERTURE';
    NEW.nb_scans := 0;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'SYSTEME', 'GEL_APPLIED', 'mission', NEW.id,
      jsonb_build_object('snapshot', jsonb_build_object(
        'taux_horaire_base_fige', NEW.taux_horaire_base_fige,
        'taux_majoration_nuit_fige', NEW.taux_majoration_nuit_fige,
        'taux_majoration_dimanche_fige', NEW.taux_majoration_dimanche_fige,
        'taux_majoration_ferie_fige', NEW.taux_majoration_ferie_fige,
        'heure_debut_nuit_fige', NEW.heure_debut_nuit_fige,
        'heure_fin_nuit_fige', NEW.heure_fin_nuit_fige,
        'taux_commission_fige', NEW.taux_commission_fige,
        'taux_commission_source', CASE
          WHEN v_etab.taux_comm_etab IS NOT NULL THEN 'etablissement'
          WHEN v_groupe_taux IS NOT NULL THEN 'groupe'
          ELSE 'defaut_15' END,
        'strategie_facturation', NEW.strategie_facturation,
        'duree_jours', v_duree_jours
      ),
      'code_pointage_genere', true,
      'soignant_assigne_id', NEW.soignant_assigne_id));
    RETURN NEW;
  END IF;

  -- Dégel : remet strategie_facturation au défaut FINALE_UNIQUE
  -- (sera re-figée au prochain gel).
  IF NEW.statut = 'OUVERTE' AND OLD.statut != 'OUVERTE' AND OLD.fige_le IS NOT NULL THEN
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'SYSTEME', 'DEGEL_APPLIED', 'mission', OLD.id,
      jsonb_build_object('old_snapshot', jsonb_build_object(
        'taux_horaire_base_fige', OLD.taux_horaire_base_fige,
        'taux_majoration_nuit_fige', OLD.taux_majoration_nuit_fige,
        'taux_majoration_dimanche_fige', OLD.taux_majoration_dimanche_fige,
        'taux_majoration_ferie_fige', OLD.taux_majoration_ferie_fige,
        'heure_debut_nuit_fige', OLD.heure_debut_nuit_fige,
        'heure_fin_nuit_fige', OLD.heure_fin_nuit_fige,
        'taux_commission_fige', OLD.taux_commission_fige,
        'strategie_facturation', OLD.strategie_facturation,
        'fige_le', OLD.fige_le),
      'old_statut', OLD.statut, 'new_statut', 'OUVERTE',
      'nb_scans_before_degel', OLD.nb_scans));
    PERFORM set_config('jolene.sync_in_progress', 'true', true);
    DELETE FROM mission_creneaux WHERE mission_id = OLD.id AND type_creneau = 'EFFECTIF';
    PERFORM set_config('jolene.sync_in_progress', 'false', true);
    NEW.taux_horaire_base_fige := NULL; NEW.taux_majoration_nuit_fige := NULL;
    NEW.taux_majoration_dimanche_fige := NULL; NEW.taux_majoration_ferie_fige := NULL;
    NEW.heure_debut_nuit_fige := NULL; NEW.heure_fin_nuit_fige := NULL;
    NEW.taux_commission_fige := NULL; NEW.fige_le := NULL;
    NEW.code_pointage_actif := NULL; NEW.code_pointage_hmac := NULL;
    NEW.prochain_type_scan := NULL; NEW.nb_scans := 0;
    NEW.debut_effectif := NULL; NEW.fin_effective := NULL; NEW.duree_heures_effective := NULL;
    NEW.strategie_facturation := 'FINALE_UNIQUE'::public.strategie_facturation;
    RETURN NEW;
  END IF;

  -- Block des modifs post-gel (logique inchangée) — strategie_facturation
  -- ajoutée à la liste des champs protégés (D8 figée à l'assignation).
  IF OLD.fige_le IS NOT NULL THEN
    IF current_setting('jolene.admin_override_gel', true) = OLD.id::text
       AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN
      DECLARE v_fm jsonb := '{}'::jsonb; v_or text := current_setting('jolene.admin_override_reason', true);
      BEGIN
        IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN v_fm := v_fm || jsonb_build_object('taux_horaire_base', jsonb_build_object('old', OLD.taux_horaire_base, 'new', NEW.taux_horaire_base)); END IF;
        IF NEW.intitule IS DISTINCT FROM OLD.intitule THEN v_fm := v_fm || jsonb_build_object('intitule', jsonb_build_object('old', OLD.intitule, 'new', NEW.intitule)); END IF;
        IF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN v_fm := v_fm || jsonb_build_object('profession_requise', jsonb_build_object('old', OLD.profession_requise, 'new', NEW.profession_requise)); END IF;
        IF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN v_fm := v_fm || jsonb_build_object('taux_horaire_base_fige', jsonb_build_object('old', OLD.taux_horaire_base_fige, 'new', NEW.taux_horaire_base_fige)); END IF;
        IF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN v_fm := v_fm || jsonb_build_object('taux_majoration_nuit_fige', jsonb_build_object('old', OLD.taux_majoration_nuit_fige, 'new', NEW.taux_majoration_nuit_fige)); END IF;
        IF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN v_fm := v_fm || jsonb_build_object('taux_majoration_dimanche_fige', jsonb_build_object('old', OLD.taux_majoration_dimanche_fige, 'new', NEW.taux_majoration_dimanche_fige)); END IF;
        IF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN v_fm := v_fm || jsonb_build_object('taux_majoration_ferie_fige', jsonb_build_object('old', OLD.taux_majoration_ferie_fige, 'new', NEW.taux_majoration_ferie_fige)); END IF;
        IF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN v_fm := v_fm || jsonb_build_object('heure_debut_nuit_fige', jsonb_build_object('old', OLD.heure_debut_nuit_fige, 'new', NEW.heure_debut_nuit_fige)); END IF;
        IF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN v_fm := v_fm || jsonb_build_object('heure_fin_nuit_fige', jsonb_build_object('old', OLD.heure_fin_nuit_fige, 'new', NEW.heure_fin_nuit_fige)); END IF;
        IF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN v_fm := v_fm || jsonb_build_object('taux_commission_fige', jsonb_build_object('old', OLD.taux_commission_fige, 'new', NEW.taux_commission_fige)); END IF;
        IF NEW.strategie_facturation IS DISTINCT FROM OLD.strategie_facturation THEN v_fm := v_fm || jsonb_build_object('strategie_facturation', jsonb_build_object('old', OLD.strategie_facturation, 'new', NEW.strategie_facturation)); END IF;
        IF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN v_fm := v_fm || jsonb_build_object('fige_le', jsonb_build_object('old', OLD.fige_le, 'new', NEW.fige_le)); END IF;
        IF v_fm != '{}'::jsonb THEN INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
          VALUES (auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_CHAMP_POST_GEL', 'mission', OLD.id, jsonb_build_object('reason', v_or, 'fields_modified', v_fm)); END IF;
      END;
      RETURN NEW;
    ELSE
      IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN v_champ_modifie := 'taux_horaire_base';
      ELSIF NEW.intitule IS DISTINCT FROM OLD.intitule THEN v_champ_modifie := 'intitule';
      ELSIF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN v_champ_modifie := 'profession_requise';
      ELSIF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN v_champ_modifie := 'taux_horaire_base_fige';
      ELSIF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN v_champ_modifie := 'taux_majoration_nuit_fige';
      ELSIF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN v_champ_modifie := 'taux_majoration_dimanche_fige';
      ELSIF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN v_champ_modifie := 'taux_majoration_ferie_fige';
      ELSIF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN v_champ_modifie := 'heure_debut_nuit_fige';
      ELSIF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN v_champ_modifie := 'heure_fin_nuit_fige';
      ELSIF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN v_champ_modifie := 'taux_commission_fige';
      ELSIF NEW.strategie_facturation IS DISTINCT FROM OLD.strategie_facturation THEN v_champ_modifie := 'strategie_facturation';
      ELSIF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN v_champ_modifie := 'fige_le';
      END IF;
      IF v_champ_modifie IS NOT NULL THEN
        RAISE EXCEPTION 'Modification du champ "%" interdite après assignation (gel du %). Pour corriger, override admin tracé requis.',
          v_champ_modifie, OLD.fige_le USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
