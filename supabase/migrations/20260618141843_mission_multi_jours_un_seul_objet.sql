-- Missions multi-jours = UNE seule mission avec N créneaux PREVISIONNEL (un par
-- jour travaillé), au lieu de N missions séparées (ancien fn_creer_serie).
-- Le pointage QR (scans_pointage + créneaux EFFECTIF), la paie et la facturation
-- gèrent déjà le multi-créneaux. Mécanisme vérifié en transaction annulée.

-- 1) Relever le plafond de créneaux : jusqu'à 1 an (366 jours).
ALTER TABLE public.missions DROP CONSTRAINT IF EXISTS ck_max_6_creneaux;
ALTER TABLE public.missions ADD CONSTRAINT ck_max_366_creneaux
  CHECK (nb_creneaux >= 0 AND nb_creneaux <= 366);

-- 2) Création d'UNE mission multi-jours (parité salarié + libéral : le type de
--    contrat / la rétrocession sont appliqués après coup par mission_id via
--    fn_modifier_type_contrat_mission / fn_definir_retrocession_mission, donc
--    cette fonction n'a qu'à renvoyer un mission_id unique).
CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE',
  p_specialite_medicale_requise text DEFAULT NULL,
  p_accepte_non_specialises boolean DEFAULT true,
  p_creneaux jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_blocage jsonb;
  v_mission_id uuid;
  v_mode text;
  v_nb int;
  v_min timestamptz;
  v_max timestamptz;
  v_c jsonb;
  v_ordre int := 0;
  v_cd timestamptz;
  v_cf timestamptz;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN '{"error":"Acces refuse"}'::jsonb;
  END IF;

  v_blocage := fn_blocage_publication_etab(v_etab_id);
  IF v_blocage IS NOT NULL THEN RETURN v_blocage; END IF;

  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN '{"error":"Champs obligatoires manquants."}'::jsonb;
  END IF;

  v_nb := COALESCE(jsonb_array_length(p_creneaux), 0);
  IF v_nb = 0 THEN RETURN '{"error":"Aucun jour fourni."}'::jsonb; END IF;
  IF v_nb > 366 THEN RETURN '{"error":"Maximum 366 jours par mission."}'::jsonb; END IF;

  -- Validation de chaque jour (fin > début) + enveloppe globale
  FOR v_c IN SELECT * FROM jsonb_array_elements(p_creneaux) LOOP
    v_cd := (v_c->>'debut')::timestamptz;
    v_cf := (v_c->>'fin')::timestamptz;
    IF v_cd IS NULL OR v_cf IS NULL OR v_cf <= v_cd THEN
      RETURN '{"error":"Chaque jour doit avoir une fin après le début."}'::jsonb;
    END IF;
  END LOOP;

  SELECT MIN((c->>'debut')::timestamptz), MAX((c->>'fin')::timestamptz)
  INTO v_min, v_max
  FROM jsonb_array_elements(p_creneaux) c;

  IF v_min < NOW() AND NOT est_admin() THEN
    RETURN '{"error":"La mission ne peut pas commencer dans le passe."}'::jsonb;
  END IF;

  v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
  IF v_mode NOT IN ('PREMIER_ARRIVE','CANDIDATURE') THEN v_mode := 'PREMIER_ARRIVE'; END IF;

  PERFORM set_config('jolene.creer_mission_context','true', true);

  -- (a) UNE mission, span = enveloppe (1er jour → dernier jour)
  INSERT INTO missions (
    etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, mode_attribution,
    specialite_medicale_requise, accepte_non_specialises
  ) VALUES (
    v_etab_id, p_intitule, p_description, p_profession_requise, p_service,
    v_min, v_max, p_taux_horaire_base, p_est_urgente,
    CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END, v_mode,
    p_specialite_medicale_requise, p_accepte_non_specialises
  ) RETURNING id INTO v_mission_id;

  -- (b) N créneaux PREVISIONNEL (sync suspendue → un seul re-sync ensuite, perf)
  PERFORM set_config('jolene.sync_in_progress','true', true);
  v_ordre := 0;
  FOR v_c IN SELECT * FROM jsonb_array_elements(p_creneaux) LOOP
    v_ordre := v_ordre + 1;
    INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre, type_creneau)
    VALUES (v_mission_id, (v_c->>'debut')::timestamptz, (v_c->>'fin')::timestamptz, false, v_ordre, 'PREVISIONNEL');
  END LOOP;
  PERFORM set_config('jolene.sync_in_progress','false', true);

  -- (c) Re-sync unique : enveloppe + nb_creneaux ; le trigger financier recalcule
  --     duree_heures depuis les créneaux (somme des jours).
  UPDATE missions SET debut_le = v_min, fin_le = v_max, nb_creneaux = v_nb
  WHERE id = v_mission_id;

  RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id, 'nb_creneaux', v_nb);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_creer_mission_multi_jours(text, text, type_profession, text, numeric, boolean, integer, text, text, boolean, jsonb) TO authenticated;
