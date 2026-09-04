-- Sépare la résolution financière salariée du circuit des factures
-- d'honoraires libérales. Une correction de pointage salariée doit produire
-- une nouvelle simulation de paie traçable, sans réécrire l'ancien document.

ALTER TABLE public.bulletins_paie
  ADD COLUMN IF NOT EXISTS bulletin_precedent_id uuid,
  ADD COLUMN IF NOT EXISTS litige_id uuid,
  ADD COLUMN IF NOT EXISTS nature_document text NOT NULL DEFAULT 'SIMULATION',
  ADD COLUMN IF NOT EXISTS motif_rectification text;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'bulletins_paie_bulletin_precedent_id_fkey'
      AND conrelid = 'public.bulletins_paie'::regclass
  ) THEN
    ALTER TABLE public.bulletins_paie
      ADD CONSTRAINT bulletins_paie_bulletin_precedent_id_fkey
      FOREIGN KEY (bulletin_precedent_id)
      REFERENCES public.bulletins_paie(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'bulletins_paie_litige_id_fkey'
      AND conrelid = 'public.bulletins_paie'::regclass
  ) THEN
    ALTER TABLE public.bulletins_paie
      ADD CONSTRAINT bulletins_paie_litige_id_fkey
      FOREIGN KEY (litige_id)
      REFERENCES public.litiges(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'bulletins_paie_nature_document_check'
      AND conrelid = 'public.bulletins_paie'::regclass
  ) THEN
    ALTER TABLE public.bulletins_paie
      ADD CONSTRAINT bulletins_paie_nature_document_check
      CHECK (nature_document IN ('SIMULATION', 'RECTIFICATIF'));
  END IF;
END;
$constraints$;

ALTER TABLE public.bulletins_paie
  DROP CONSTRAINT IF EXISTS bulletins_paie_unique_mission;

CREATE UNIQUE INDEX IF NOT EXISTS bulletins_paie_unique_actif_mission
  ON public.bulletins_paie (mission_id)
  WHERE statut <> 'ANNULE';

CREATE INDEX IF NOT EXISTS idx_bulletins_paie_litige
  ON public.bulletins_paie (litige_id)
  WHERE litige_id IS NOT NULL;

-- Le calcul financier historique privilégie toujours le planning au pointage.
-- Pendant une résolution admin uniquement, cette valeur transactionnelle
-- bornée permet au trigger de reprendre les heures arbitrées. Les créneaux et
-- pointages bruts restent intacts comme preuves.
CREATE OR REPLACE FUNCTION public.fn_calculer_financier_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_duree numeric;
  v_taux_effectif numeric;
  v_brut_base numeric;
  v_total_majorations numeric;
  v_total_brut numeric;
  v_etab record;
  v_commission_taux numeric;
  v_commission_ht numeric;
  v_commission_tva numeric;
  v_commission_ttc numeric;
  v_has_creneaux boolean;
  v_est_liberal boolean;
  v_taux_ifm numeric;
  v_taux_icp numeric;
  v_override_mission text := current_setting('jolene.heures_litige_mission_id', true);
  v_override_heures text := current_setting('jolene.heures_litige_override', true);
BEGIN
  v_est_liberal := COALESCE(NEW.type_contrat_applique::text, '') = 'LIBERAL'
                OR COALESCE(NEW.type_paiement_soignant::text, '') = 'NOTE_HONORAIRES'
                OR COALESCE(NEW.choix_contrat_soignant, '') = 'LIBERAL';

  IF v_override_mission = NEW.id::text AND NULLIF(v_override_heures, '') IS NOT NULL THEN
    BEGIN
      v_duree := v_override_heures::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'Heures de résolution de litige invalides';
    END;
    IF v_duree::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_duree <= 0 OR v_duree > 168 THEN
      RAISE EXCEPTION 'Heures de résolution de litige hors limites';
    END IF;
  ELSE
    SELECT GREATEST(
      COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
        FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause), 0),
      COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
        FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause), 0)
    )
    INTO v_duree
    FROM public.mission_creneaux WHERE mission_id = NEW.id;

    SELECT EXISTS (
      SELECT 1 FROM public.mission_creneaux WHERE mission_id = NEW.id
    ) INTO v_has_creneaux;

    IF NOT v_has_creneaux THEN
      v_duree := COALESCE(
        NEW.duree_heures,
        EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0
      );
    END IF;
  END IF;

  NEW.duree_heures := v_duree;

  SELECT taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
         taux_majoration_ferie_pourcent, taux_commission_negocie,
         rist_plafond_actif, rist_taux_base_horaire
  INTO v_etab
  FROM public.etablissements WHERE id = NEW.etablissement_id;

  v_taux_effectif := NEW.taux_horaire_base;
  IF COALESCE(v_etab.rist_plafond_actif, true)
     AND NEW.taux_horaire_base > COALESCE(v_etab.rist_taux_base_horaire, 25) THEN
    NEW.rist_plafond_applique := true;
    NEW.taux_rist_plafonne := COALESCE(v_etab.rist_taux_base_horaire, 25);
    v_taux_effectif := NEW.taux_rist_plafonne;
  ELSE
    NEW.rist_plafond_applique := false;
    NEW.taux_rist_plafonne := NULL;
  END IF;

  v_brut_base := v_taux_effectif * v_duree;
  NEW.montant_majoration_nuit := ROUND(
    COALESCE(NEW.heures_nuit, 0) * v_taux_effectif
      * COALESCE(v_etab.taux_majoration_nuit_pourcent, 25) / 100.0,
    2
  );
  NEW.montant_majoration_dimanche := ROUND(
    COALESCE(NEW.heures_dimanche, 0) * v_taux_effectif
      * COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50) / 100.0,
    2
  );
  NEW.montant_majoration_ferie := ROUND(
    COALESCE(NEW.heures_ferie, 0) * v_taux_effectif
      * COALESCE(v_etab.taux_majoration_ferie_pourcent, 100) / 100.0,
    2
  );

  v_total_majorations := COALESCE(NEW.montant_majoration_nuit, 0)
    + COALESCE(NEW.montant_majoration_dimanche, 0)
    + COALESCE(NEW.montant_majoration_ferie, 0);
  v_total_brut := ROUND(v_brut_base + v_total_majorations, 2);
  NEW.total_brut := v_total_brut;

  v_taux_ifm := CASE WHEN v_est_liberal THEN 0 ELSE COALESCE(NEW.taux_ifm, 0.10) END;
  v_taux_icp := CASE WHEN v_est_liberal THEN 0 ELSE COALESCE(NEW.taux_icp, 0.10) END;
  NEW.taux_ifm := v_taux_ifm;
  NEW.taux_icp := v_taux_icp;
  NEW.montant_ifm := ROUND(v_total_brut * v_taux_ifm, 2);
  -- Les congés payés d'un CDD incluent l'IFM dans leur assiette. Conserver
  -- cette assiette canonique évite de sous-estimer à la fois le dû soignant
  -- et la commission calculée ensuite sur ce dû.
  NEW.montant_icp := ROUND((v_total_brut + NEW.montant_ifm) * v_taux_icp, 2);
  NEW.net_a_payer := ROUND(v_total_brut + NEW.montant_ifm + NEW.montant_icp, 2);
  NEW.net_estime := ROUND(NEW.net_a_payer * 0.78, 2);

  v_commission_taux := COALESCE(
    NEW.taux_commission_fige,
    NEW.taux_commission,
    v_etab.taux_commission_negocie,
    public.fn_param_num('commission_defaut_pct', 15)
  );
  NEW.taux_commission := v_commission_taux;
  v_commission_ht := ROUND(NEW.net_a_payer * v_commission_taux / 100.0, 2);
  v_commission_tva := ROUND(v_commission_ht * 0.20, 2);
  v_commission_ttc := ROUND(v_commission_ht + v_commission_tva, 2);
  NEW.montant_commission_ht := v_commission_ht;
  NEW.montant_commission_tva := v_commission_tva;
  NEW.montant_commission_ttc := v_commission_ttc;

  RETURN NEW;
END;
$function$;

-- Les triggers financiers historiques `dec_*` recalculent encore la mission
-- depuis le planning. Le calcul canonique doit donc être exécuté en dernier,
-- après ces compatibilités et après les garde-fous. PostgreSQL ordonne les
-- triggers de même nature par nom.
DROP TRIGGER IF EXISTS trg_calculer_financier ON public.missions;
DROP TRIGGER IF EXISTS zzzz_calculer_financier ON public.missions;
CREATE TRIGGER zzzz_calculer_financier
BEFORE INSERT OR UPDATE OF
  taux_horaire_base,
  duree_heures,
  debut_le,
  fin_le,
  heures_nuit,
  heures_dimanche,
  heures_ferie,
  taux_ifm,
  taux_icp
ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.fn_calculer_financier_mission();

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_salarie(
  p_litige_id uuid,
  p_resolution text,
  p_en_faveur_de text DEFAULT NULL,
  p_ajuster_heures numeric DEFAULT NULL,
  p_ajuster_taux numeric DEFAULT NULL,
  p_action_financiere text DEFAULT 'AUTO'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_action text := upper(btrim(COALESCE(p_action_financiere, 'AUTO')));
  v_faveur text := upper(btrim(COALESCE(p_en_faveur_de, 'NEUTRE')));
  v_nouveau_statut text;
  v_litige public.litiges%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_mission_apres public.missions%ROWTYPE;
  v_presence public.presences%ROWTYPE;
  v_presence_trouvee boolean := false;
  v_payload jsonb;
  v_type_payload text;
  v_modifications jsonb;
  v_arrivee_payload timestamptz;
  v_depart_payload timestamptz;
  v_heures_payload numeric;
  v_heures_avant numeric;
  v_heures_final numeric;
  v_taux_avant numeric;
  v_taux_final numeric;
  v_ajustement_demande boolean := false;
  v_accord_remplace boolean := false;
  v_helper_result jsonb;
  v_calcul_result jsonb;
  v_cot public.cotisations_sociales%ROWTYPE;
  v_bulletin_precedent public.bulletins_paie%ROWTYPE;
  v_bulletin_precedent_trouve boolean := false;
  v_bulletin_id uuid;
  v_numero_bulletin text;
  v_statut_bulletin text := 'EMIS';
  v_date_paiement date;
  v_total_confirme numeric := 0;
  v_nb_paiements integer := 0;
  v_regularisation_paiement boolean := false;
  v_ecart_paiement numeric := 0;
  v_commission_delta_ht numeric := 0;
  v_commission_delta_tva numeric := 0;
  v_commission_delta_ttc numeric := 0;
  v_document_commission_id uuid;
  v_document_commission_numero text;
  v_document_commission_type text;
  v_rows integer;
  v_audit_result jsonb;
BEGIN
  IF v_uid IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Administrateur requis.');
  END IF;
  IF length(btrim(COALESCE(p_resolution, ''))) < 10
     OR length(btrim(COALESCE(p_resolution, ''))) > 5000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La résolution doit contenir entre 10 et 5 000 caractères.'
    );
  END IF;
  IF v_faveur NOT IN ('SOIGNANT', 'ETABLISSEMENT', 'NEUTRE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'p_en_faveur_de doit être SOIGNANT, ETABLISSEMENT ou NEUTRE.'
    );
  END IF;
  IF v_action NOT IN ('AUTO', 'AUCUNE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Une mission salariée utilise la rectification de paie automatique, pas une action de facture d’honoraires.'
    );
  END IF;
  IF p_ajuster_heures IS NOT NULL
     AND (p_ajuster_heures::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_ajuster_heures <= 0 OR p_ajuster_heures > 168) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Les heures ajustées doivent être strictement positives et au plus égales à 168.'
    );
  END IF;
  IF p_ajuster_taux IS NOT NULL
     AND (p_ajuster_taux::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_ajuster_taux < 0.01 OR p_ajuster_taux > 1000) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Le taux ajusté doit être strictement positif et au plus égal à 1 000 €.'
    );
  END IF;

  SELECT l.* INTO v_litige
  FROM public.litiges l
  WHERE l.id = p_litige_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable.');
  END IF;
  IF v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Ce litige est déjà résolu ou non modifiable.'
    );
  END IF;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = v_litige.mission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission du litige introuvable.');
  END IF;
  IF COALESCE(v_mission.type_contrat_applique::text, '') <> 'SALARIE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cette mission ne relève pas du circuit de paie salariée.'
    );
  END IF;
  IF COALESCE(v_mission.commission_facturee, false) AND v_mission.facture_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Commission marquée facturée sans facture d’origine : intervention comptable requise.'
    );
  END IF;
  IF v_mission.facture_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.factures f WHERE f.id = v_mission.facture_id
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La facture de commission d’origine est introuvable.'
    );
  END IF;

  IF v_litige.presence_id IS NOT NULL THEN
    SELECT p.* INTO v_presence
    FROM public.presences p
    WHERE p.id = v_litige.presence_id
      AND p.mission_id = v_litige.mission_id
    FOR UPDATE;
    v_presence_trouvee := FOUND;
  ELSE
    SELECT p.* INTO v_presence
    FROM public.presences p
    WHERE p.mission_id = v_litige.mission_id
    ORDER BY p.valide_le DESC NULLS LAST, p.cree_le DESC
    LIMIT 1
    FOR UPDATE;
    v_presence_trouvee := FOUND;
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NOT NULL THEN
    IF v_litige.modifications_executees IS TRUE THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Les modifications de cet accord ont déjà été exécutées.'
      );
    END IF;
    IF v_litige.statut <> 'REVUE_ADMIN'
       OR v_litige.accord_soignant IS NOT TRUE
       OR v_litige.accord_etablissement IS NOT TRUE
       OR v_litige.accord_soignant_le IS NULL
       OR v_litige.accord_etablissement_le IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Un accord financier exige le double accord horodaté des parties.'
      );
    END IF;
    v_type_payload := v_payload->>'type';
    v_modifications := v_payload->'modifications';
    IF v_type_payload NOT IN ('MODIFICATION_HORAIRES', 'MIXTE') THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Pour une mission salariée, renseignez les heures ou le taux : un montant TTC isolé ne définit pas une paie.'
      );
    END IF;
    BEGIN
      v_arrivee_payload := (v_modifications->>'pointage_arrivee_le')::timestamptz;
      v_depart_payload := (v_modifications->>'pointage_depart_le')::timestamptz;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      RETURN jsonb_build_object('success', false, 'error', 'Format des horaires convenus invalide.');
    END;
    IF v_arrivee_payload IS NULL OR v_depart_payload IS NULL
       OR v_depart_payload <= v_arrivee_payload
       OR v_depart_payload - v_arrivee_payload > interval '7 days' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Plage horaire convenue invalide.');
    END IF;
    IF NOT v_presence_trouvee THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Aucune présence verrouillable pour appliquer les heures.'
      );
    END IF;
    v_heures_payload := round(
      GREATEST(
        0,
        EXTRACT(epoch FROM (v_depart_payload - v_arrivee_payload)) / 3600
          - COALESCE(v_presence.duree_pause_min, 0) / 60
      )::numeric,
      2
    );
    IF v_heures_payload <= 0 OR v_heures_payload > 168 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Durée nette convenue hors limites.');
    END IF;
  END IF;

  v_ajustement_demande := p_ajuster_heures IS NOT NULL
    OR p_ajuster_taux IS NOT NULL
    OR v_payload IS NOT NULL;
  IF v_action = 'AUCUNE' AND v_ajustement_demande THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'AUCUNE est interdite lorsqu’un ajustement de paie existe.'
    );
  END IF;
  IF v_ajustement_demande AND v_mission.statut <> 'TERMINEE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La mission doit être terminée avant de rectifier sa paie.'
    );
  END IF;
  IF (p_ajuster_heures IS NOT NULL OR v_heures_payload IS NOT NULL)
     AND NOT v_presence_trouvee THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Aucune présence verrouillable pour appliquer les heures.'
    );
  END IF;

  v_heures_avant := COALESCE(
    CASE WHEN v_presence_trouvee THEN v_presence.heures_ajustees_litige END,
    CASE WHEN v_presence_trouvee THEN v_presence.heures_reelles END,
    v_mission.duree_heures
  );
  v_taux_avant := COALESCE(
    v_mission.taux_horaire_base_fige,
    v_mission.taux_horaire_base
  );
  v_heures_final := COALESCE(p_ajuster_heures, v_heures_payload, v_heures_avant);
  v_taux_final := COALESCE(p_ajuster_taux, v_taux_avant);

  IF v_ajustement_demande AND (
    v_heures_final IS NULL OR v_heures_final <= 0 OR v_heures_final > 168
    OR v_taux_final IS NULL OR v_taux_final < 0.01 OR v_taux_final > 1000
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Heures ou taux de référence absents ou hors limites.'
    );
  END IF;

  IF v_payload IS NOT NULL THEN
    v_accord_remplace := p_ajuster_taux IS NOT NULL
      OR (
        p_ajuster_heures IS NOT NULL
        AND abs(p_ajuster_heures - v_heures_payload) > 0.005
      );
  END IF;

  IF v_ajustement_demande THEN
    IF v_payload IS NOT NULL AND p_ajuster_heures IS NULL THEN
      v_helper_result := public.fn_modifier_horaires_presence(
        v_presence.id,
        v_arrivee_payload,
        v_depart_payload,
        v_payload->>'justification'
      );
      IF COALESCE(v_helper_result @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Échec atomique de la correction des horaires: %',
          COALESCE(v_helper_result->>'error', 'résultat interne invalide');
      END IF;
      UPDATE public.presences
      SET heures_ajustees_litige = NULL,
          ajustement_litige_id = p_litige_id,
          motif_litige = left('Accord litige : ' || (v_payload->>'justification'), 2000),
          modifie_le = now()
      WHERE id = v_presence.id;
    ELSIF p_ajuster_heures IS NOT NULL THEN
      UPDATE public.presences
      SET heures_ajustees_litige = p_ajuster_heures,
          ajustement_litige_id = p_litige_id,
          motif_litige = left('Décision admin litige : ' || btrim(p_resolution), 2000),
          modifie_le = now()
      WHERE id = v_presence.id;
    END IF;

    PERFORM set_config('jolene.admin_override_gel', v_mission.id::text, true);
    PERFORM set_config(
      'jolene.admin_override_reason',
      'Résolution litige paie salariée ' || p_litige_id::text,
      true
    );
    PERFORM set_config('jolene.heures_litige_mission_id', v_mission.id::text, true);
    PERFORM set_config('jolene.heures_litige_override', v_heures_final::text, true);

    UPDATE public.missions
    SET duree_heures = v_heures_final,
        taux_horaire_base = v_taux_final,
        taux_horaire_base_fige = v_taux_final,
        commission_a_recalculer = false,
        modifie_le = now()
    WHERE id = v_mission.id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Recalcul de la mission non appliqué';
    END IF;

    PERFORM set_config('jolene.heures_litige_mission_id', '', true);
    PERFORM set_config('jolene.heures_litige_override', '', true);

    SELECT m.* INTO v_mission_apres
    FROM public.missions m WHERE m.id = v_mission.id;

    v_calcul_result := public.fn_calculer_cotisations(v_mission.id);
    IF COALESCE((v_calcul_result->>'success')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Calcul des cotisations échoué: %',
        COALESCE(v_calcul_result->>'error', 'résultat interne invalide');
    END IF;
    SELECT c.* INTO v_cot
    FROM public.cotisations_sociales c
    WHERE c.mission_id = v_mission.id;
    IF NOT FOUND OR v_cot.type_contrat <> 'CDD' THEN
      RAISE EXCEPTION 'Cotisations salariées rectificatives introuvables';
    END IF;

    SELECT bp.* INTO v_bulletin_precedent
    FROM public.bulletins_paie bp
    WHERE bp.mission_id = v_mission.id
      AND bp.statut <> 'ANNULE'
    ORDER BY bp.cree_le DESC
    LIMIT 1
    FOR UPDATE;
    v_bulletin_precedent_trouve := FOUND;

    IF v_bulletin_precedent_trouve THEN
      UPDATE public.bulletins_paie
      SET statut = 'ANNULE', modifie_le = now()
      WHERE id = v_bulletin_precedent.id
        AND statut <> 'ANNULE';
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Annulation concurrente de la simulation de paie refusée';
      END IF;
    END IF;

    SELECT
      COALESCE(sum(ps.montant_net) FILTER (WHERE ps.statut IN ('CONFIRME', 'RESOLU')), 0),
      max(ps.date_paiement) FILTER (WHERE ps.statut IN ('CONFIRME', 'RESOLU')),
      count(*) FILTER (WHERE ps.statut IN ('DECLARE', 'CONFIRME', 'RESOLU'))
    INTO v_total_confirme, v_date_paiement, v_nb_paiements
    FROM public.paiements_soignant ps
    WHERE ps.mission_id = v_mission.id;

    v_ecart_paiement := round(v_cot.net_avant_impot - v_total_confirme, 2);
    v_regularisation_paiement := v_nb_paiements > 0 AND abs(v_ecart_paiement) > 0.01;
    IF v_nb_paiements > 0 AND abs(v_ecart_paiement) <= 0.01 THEN
      v_statut_bulletin := 'PAYE';
    END IF;

    v_numero_bulletin := public.fn_next_bulletin_paie_number(
      v_mission.soignant_assigne_id
    );
    INSERT INTO public.bulletins_paie (
      numero_bulletin, soignant_id, mission_id, etablissement_id,
      periode_debut, periode_fin, salaire_brut,
      total_cotisations_salariales, total_cotisations_patronales,
      net_avant_impot, ifm, icp, statut, date_emission, date_paiement,
      bulletin_precedent_id, litige_id, nature_document, motif_rectification
    ) VALUES (
      v_numero_bulletin, v_mission.soignant_assigne_id, v_mission.id,
      v_mission.etablissement_id, v_mission.debut_le::date, v_mission.fin_le::date,
      v_cot.salaire_brut, v_cot.total_cotisations_salariales,
      v_cot.total_cotisations_patronales, v_cot.net_avant_impot,
      COALESCE(v_cot.ifm, 0), COALESCE(v_cot.icp, 0),
      v_statut_bulletin, current_date,
      CASE WHEN v_statut_bulletin = 'PAYE' THEN v_date_paiement ELSE NULL END,
      CASE WHEN v_bulletin_precedent_trouve THEN v_bulletin_precedent.id ELSE NULL END,
      p_litige_id,
      CASE WHEN v_bulletin_precedent_trouve THEN 'RECTIFICATIF' ELSE 'SIMULATION' END,
      left(btrim(p_resolution), 2000)
    ) RETURNING id INTO v_bulletin_id;

    v_commission_delta_ht := round(
      COALESCE(v_mission_apres.montant_commission_ht, 0)
        - COALESCE(v_mission.montant_commission_ht, 0),
      2
    );
    IF COALESCE(v_mission.commission_facturee, false)
       AND abs(v_commission_delta_ht) > 0.01 THEN
      v_commission_delta_tva := round(abs(v_commission_delta_ht) * 0.20, 2);
      v_commission_delta_ttc := abs(v_commission_delta_ht) + v_commission_delta_tva;
      IF v_commission_delta_ht < 0 THEN
        v_document_commission_type := 'AVOIR';
        v_document_commission_numero := public.next_avoir_commission_number(
          v_mission.etablissement_id
        );
      ELSE
        v_document_commission_type := 'FACTURE_COMPLEMENTAIRE';
        v_document_commission_numero := public.next_facture_complementaire_number(
          v_mission.etablissement_id
        );
      END IF;
      INSERT INTO public.factures (
        etablissement_id, numero_facture, mission_id, type_document,
        facture_precedente_id, montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, statut, date_emission, date_echeance,
        periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_document_commission_numero, v_mission.id,
        v_document_commission_type, v_mission.facture_id,
        abs(v_commission_delta_ht), 20, v_commission_delta_tva,
        v_commission_delta_ttc, 1, 'EMISE', now(), current_date + 30,
        v_mission.debut_le::date, v_mission.fin_le::date
      ) RETURNING id INTO v_document_commission_id;
    END IF;
  ELSE
    v_mission_apres := v_mission;
    v_action := 'AUCUNE';
  END IF;

  v_nouveau_statut := CASE v_faveur
    WHEN 'SOIGNANT' THEN 'RESOLU_SOIGNANT'
    WHEN 'ETABLISSEMENT' THEN 'RESOLU_ETABLISSEMENT'
    ELSE 'RESOLU_ADMIN'
  END;
  UPDATE public.litiges
  SET statut = v_nouveau_statut,
      resolution = btrim(p_resolution),
      resolu_par = v_uid,
      resolu_le = now(),
      modifications_executees = CASE
        WHEN v_payload IS NOT NULL THEN true ELSE modifications_executees
      END,
      modifications_executees_a = CASE
        WHEN v_payload IS NOT NULL THEN now() ELSE modifications_executees_a
      END,
      modifications_executees_par = CASE
        WHEN v_payload IS NOT NULL THEN v_uid ELSE modifications_executees_par
      END
  WHERE id = p_litige_id
    AND statut IN (
      'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN'
    );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Résolution concurrente refusée';
  END IF;

  v_audit_result := public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_RESOLUTION',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'LITIGE_RESOLUTION_PAIE_SALARIEE',
      'en_faveur_de', v_faveur,
      'heures_avant', v_heures_avant,
      'heures_apres', v_heures_final,
      'taux_avant', v_taux_avant,
      'taux_apres', v_taux_final,
      'brut_mission_avant', v_mission.total_brut,
      'brut_mission_apres', v_mission_apres.total_brut,
      'net_simule_apres', CASE WHEN v_ajustement_demande THEN v_cot.net_avant_impot ELSE NULL END,
      'commission_ht_avant', v_mission.montant_commission_ht,
      'commission_ht_apres', v_mission_apres.montant_commission_ht,
      'bulletin_precedent_id', CASE
        WHEN v_bulletin_precedent_trouve THEN v_bulletin_precedent.id ELSE NULL
      END,
      'bulletin_rectificatif_id', v_bulletin_id,
      'document_commission_id', v_document_commission_id,
      'document_commission_type', v_document_commission_type,
      'regularisation_paiement_requise', v_regularisation_paiement,
      'ecart_paiement', v_ecart_paiement,
      'accord_remplace', v_accord_remplace
    )
  );
  IF COALESCE(v_audit_result @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit de résolution non écrit: %',
      COALESCE(v_audit_result->>'error', 'résultat interne invalide');
  END IF;

  IF v_ajustement_demande THEN
    PERFORM public.fn_litige_push_notification(
      v_litige.soignant_id,
      'SOIGNANT',
      'LITIGE_RESOLU_AJUSTE',
      'Litige résolu — simulation de paie rectifiée',
      CASE WHEN v_regularisation_paiement
        THEN 'Les heures et la simulation de paie ont été rectifiées. Une régularisation du paiement reste à traiter.'
        ELSE 'Les heures, la simulation de paie et la commission ont été recalculées.'
      END,
      p_litige_id,
      jsonb_build_object(
        'bulletin_rectificatif_id', v_bulletin_id,
        'net_simule', v_cot.net_avant_impot,
        'regularisation_paiement_requise', v_regularisation_paiement
      )
    );
    PERFORM public.fn_litige_push_notification(
      v_litige.etablissement_id,
      'ETABLISSEMENT',
      'LITIGE_RESOLU_AJUSTE',
      'Litige résolu — paie salariée rectifiée',
      CASE WHEN v_regularisation_paiement
        THEN 'La paie simulée a été rectifiée. Traitez maintenant la régularisation du paiement.'
        ELSE 'La paie simulée et la commission de la mission ont été recalculées.'
      END,
      p_litige_id,
      jsonb_build_object(
        'bulletin_rectificatif_id', v_bulletin_id,
        'net_simule', v_cot.net_avant_impot,
        'regularisation_paiement_requise', v_regularisation_paiement
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_financiere', CASE
      WHEN v_ajustement_demande THEN 'RECTIFICATION_PAIE_SALARIEE'
      ELSE 'AUCUNE'
    END,
    'statut', v_nouveau_statut,
    'heures_final', v_heures_final,
    'taux_final', v_taux_final,
    'salaire_brut', CASE WHEN v_ajustement_demande THEN v_cot.salaire_brut ELSE NULL END,
    'net_avant_impot', CASE WHEN v_ajustement_demande THEN v_cot.net_avant_impot ELSE NULL END,
    'bulletin_annule_id', CASE
      WHEN v_bulletin_precedent_trouve THEN v_bulletin_precedent.id ELSE NULL
    END,
    'bulletin_rectificatif_id', v_bulletin_id,
    'document_commission_id', v_document_commission_id,
    'document_commission_type', v_document_commission_type,
    'regularisation_paiement_requise', v_regularisation_paiement,
    'ecart_paiement', v_ecart_paiement,
    'accord_remplace', v_accord_remplace
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_resoudre_litige_salarie(
  uuid, text, text, numeric, numeric, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_resoudre_litige_salarie(
  uuid, text, text, numeric, numeric, text
) TO authenticated, service_role;

-- Route les missions salariées avant toute tentative de résolution via une
-- facture d'honoraires. Le reste du résolveur intelligent reste inchangé.
DO $route_salariee$
DECLARE
  v_definition text;
  v_marqueur text := $marker$  IF v_action IN ('AUTO', 'COMPLEMENT') THEN$marker$;
  v_injection text := $injection$  IF EXISTS (
    SELECT 1
    FROM public.litiges l
    JOIN public.missions m ON m.id = l.mission_id
    WHERE l.id = p_litige_id
      AND COALESCE(m.type_contrat_applique::text, '') = 'SALARIE'
  ) THEN
    RETURN public.fn_admin_resoudre_litige_salarie(
      p_litige_id, p_resolution, p_en_faveur_de,
      p_ajuster_heures, p_ajuster_taux, v_action
    );
  END IF;

  IF v_action IN ('AUTO', 'COMPLEMENT') THEN$injection$;
BEGIN
  SELECT pg_get_functiondef(
    'public.fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)'::regprocedure
  ) INTO v_definition;

  IF strpos(v_definition, v_marqueur) = 0 THEN
    RAISE EXCEPTION 'Point d insertion du routeur de paie salariée introuvable';
  END IF;

  EXECUTE replace(v_definition, v_marqueur, v_injection);
END;
$route_salariee$;

COMMENT ON FUNCTION public.fn_admin_resoudre_litige_salarie(
  uuid, text, text, numeric, numeric, text
) IS
  'Résolution admin sans MFA des litiges salariés : conserve les preuves de pointage, recalcule paie et commission, annule la simulation précédente et émet un rectificatif audité.';
