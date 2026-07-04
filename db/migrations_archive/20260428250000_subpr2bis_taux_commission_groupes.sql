-- Sub-PR 2bis — Gestion admin des taux commission multi-établissements
-- (cf. docs/tech-debt.md).
--
-- Contexte : taux fixé aujourd'hui par etablissements.taux_commission_negocie
-- (défaut 15%). Aucune cascade groupe ni audit des changements. Bloquant
-- avant clients multi-étabs sous contrat-cadre.
--
-- Infra existante :
--   - groupes_sante (table déjà présente, hierarchie via groupe_parent_id)
--   - etablissements.groupe_sante_id (FK déjà présente)
--   - etablissements.taux_commission_negocie (numeric)
--   - missions.taux_commission_fige (gel à l'assignation)
--   - fn_geler_mission_a_assignation (utilise actuellement uniquement
--     etab.taux_commission_negocie avec fallback 15)
--
-- Apports de cette migration :
--   1. Colonnes contrat groupe : taux_commission_negocie + contrat_debut + contrat_fin.
--   2. Modification fn_geler_mission_a_assignation : cascade
--      etab.taux_commission_negocie → groupe.taux_commission_negocie → 15.
--   3. RPC admin fn_admin_modifier_taux_commission (etab|groupe + raison + audit).
--   4. RPC fn_admin_lister_taux_commission pour la page UI.
--
-- Application : seul le gel à l'assignation lit le taux. Les missions
-- déjà gelées conservent leur taux_commission_fige. Le changement
-- impacte donc uniquement les futures assignations.

-- ───────────────────────────────────────────────────────────────────────
-- 1. Colonnes contrat sur groupes_sante

ALTER TABLE public.groupes_sante
  ADD COLUMN IF NOT EXISTS taux_commission_negocie numeric,
  ADD COLUMN IF NOT EXISTS contrat_debut date,
  ADD COLUMN IF NOT EXISTS contrat_fin date;

ALTER TABLE public.groupes_sante
  DROP CONSTRAINT IF EXISTS groupes_sante_taux_commission_range;
ALTER TABLE public.groupes_sante
  ADD CONSTRAINT groupes_sante_taux_commission_range
  CHECK (taux_commission_negocie IS NULL OR (taux_commission_negocie >= 0 AND taux_commission_negocie <= 100));

COMMENT ON COLUMN public.groupes_sante.taux_commission_negocie IS
  'Taux de commission Jolene appliqué par défaut aux établissements du groupe (cascade : etab.taux_commission_negocie > groupe.taux_commission_negocie > 15%).';
COMMENT ON COLUMN public.groupes_sante.contrat_debut IS
  'Date de début du contrat-cadre groupe (pour audit et reporting).';
COMMENT ON COLUMN public.groupes_sante.contrat_fin IS
  'Date de fin du contrat-cadre groupe (NULL = sans terme).';

-- ───────────────────────────────────────────────────────────────────────
-- 2. Mise à jour de la fonction de gel pour cascade groupe

CREATE OR REPLACE FUNCTION public.fn_geler_mission_a_assignation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_etab RECORD;
  v_groupe_taux numeric;
  v_taux_comm_resolved numeric;
  v_champ_modifie text;
  v_new_code text;
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
    -- IMPORTANT : on prend la cascade etab>groupe>15 directement, et on
    -- ignore NEW.taux_commission qui a un default 15.00 sur la table
    -- missions. Sans ce changement, la cascade groupe (par ex. 10%)
    -- était court-circuitée par le default mission (15%).
    NEW.taux_commission_fige := v_taux_comm_resolved;
    NEW.fige_le := now();

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
          ELSE 'defaut_15' END
      ),
      'code_pointage_genere', true,
      'soignant_assigne_id', NEW.soignant_assigne_id));
    RETURN NEW;
  END IF;

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
    RETURN NEW;
  END IF;

  -- Block des modifs post-gel (logique inchangée — copiée telle quelle)
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
      ELSIF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN v_champ_modifie := 'fige_le';
      END IF;
      IF v_champ_modifie IS NOT NULL THEN
        RAISE EXCEPTION 'Modification du champ "%" interdite après assignation (gel du %). Pour corriger une coquille, contactez le support Jolene pour un override admin tracé. Pour modifier le contenu substantiel, annuler la mission et en créer une nouvelle.',
          v_champ_modifie, OLD.fige_le USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────
-- 3. RPC admin de modification + listing

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_taux_commission(
  p_etablissement_id uuid DEFAULT NULL,
  p_groupe_id uuid DEFAULT NULL,
  p_nouveau_taux numeric DEFAULT NULL,
  p_raison text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old_taux numeric;
  v_target text;
  v_target_id uuid;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  IF (p_etablissement_id IS NULL AND p_groupe_id IS NULL)
     OR (p_etablissement_id IS NOT NULL AND p_groupe_id IS NOT NULL) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Exactement un de p_etablissement_id ou p_groupe_id doit être fourni');
  END IF;

  IF p_nouveau_taux IS NOT NULL AND (p_nouveau_taux < 0 OR p_nouveau_taux > 100) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Taux de commission hors bornes (attendu entre 0 et 100)');
  END IF;

  IF COALESCE(trim(p_raison), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Raison obligatoire (audit)');
  END IF;

  IF p_etablissement_id IS NOT NULL THEN
    SELECT taux_commission_negocie INTO v_old_taux
    FROM etablissements WHERE id = p_etablissement_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
    END IF;
    UPDATE etablissements SET taux_commission_negocie = p_nouveau_taux WHERE id = p_etablissement_id;
    v_target := 'etablissement';
    v_target_id := p_etablissement_id;
  ELSE
    SELECT taux_commission_negocie INTO v_old_taux
    FROM groupes_sante WHERE id = p_groupe_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Groupe introuvable');
    END IF;
    UPDATE groupes_sante SET taux_commission_negocie = p_nouveau_taux WHERE id = p_groupe_id;
    v_target := 'groupe';
    v_target_id := p_groupe_id;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'TAUX_COMMISSION_MODIFIE',
    p_type_ressource := v_target,
    p_id_ressource := v_target_id,
    p_details := jsonb_build_object(
      'old_taux', v_old_taux,
      'new_taux', p_nouveau_taux,
      'raison', p_raison,
      'note', 'Impacte uniquement les futures missions assignées (gel existant préservé)'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'cible', v_target,
    'cible_id', v_target_id,
    'ancien_taux', v_old_taux,
    'nouveau_taux', p_nouveau_taux
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_modifier_taux_commission(uuid, uuid, numeric, text) TO authenticated;

-- Listing pour la page UI (groupes + établissements + taux résolu cascade)
CREATE OR REPLACE FUNCTION public.fn_admin_lister_taux_commission()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'groupes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'nom', nom, 'siren', siren,
        'taux_commission_negocie', taux_commission_negocie,
        'contrat_debut', contrat_debut, 'contrat_fin', contrat_fin,
        'nb_etablissements', (SELECT count(*) FROM etablissements e WHERE e.groupe_sante_id = g.id)
      ) ORDER BY nom), '[]'::jsonb)
      FROM groupes_sante g WHERE supprime_le IS NULL
    ),
    'etablissements', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', e.id, 'nom', e.nom, 'siret', e.siret,
        'taux_commission_negocie', e.taux_commission_negocie,
        'groupe_id', e.groupe_sante_id, 'groupe_nom', g.nom,
        'taux_groupe', g.taux_commission_negocie,
        'taux_resolu', COALESCE(e.taux_commission_negocie, g.taux_commission_negocie, 15),
        'taux_resolu_source', CASE
          WHEN e.taux_commission_negocie IS NOT NULL THEN 'etablissement'
          WHEN g.taux_commission_negocie IS NOT NULL THEN 'groupe'
          ELSE 'defaut_15' END
      ) ORDER BY e.nom), '[]'::jsonb)
      FROM etablissements e
      LEFT JOIN groupes_sante g ON g.id = e.groupe_sante_id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_taux_commission() TO authenticated;

NOTIFY pgrst, 'reload schema';
