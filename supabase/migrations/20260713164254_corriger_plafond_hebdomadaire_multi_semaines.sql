-- Le plafond de l'art. L3121-20 s'applique à chaque semaine civile. Une
-- mission multi-jours doit donc être ventilée depuis mission_creneaux, jamais
-- imputée en totalité à sa seule semaine de début.

CREATE OR REPLACE FUNCTION public.fn_heures_mission_semaine(
  p_mission_id uuid,
  p_semaine_debut date
) RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  WITH bornes AS (
    SELECT
      p_semaine_debut::timestamp AT TIME ZONE 'Europe/Paris' AS debut_ts,
      (p_semaine_debut + 7)::timestamp AT TIME ZONE 'Europe/Paris' AS fin_ts
  ), mission AS (
    SELECT m.* FROM public.missions m WHERE m.id = p_mission_id
  ), type_reference AS (
    SELECT CASE
      WHEN m.statut = 'TERMINEE' AND EXISTS (
        SELECT 1 FROM public.mission_creneaux mc
         WHERE mc.mission_id = m.id AND mc.type_creneau = 'EFFECTIF'
           AND mc.fin IS NOT NULL AND NOT mc.est_pause
      ) THEN 'EFFECTIF'
      WHEN EXISTS (
        SELECT 1 FROM public.mission_creneaux mc
         WHERE mc.mission_id = m.id AND mc.type_creneau = 'PREVISIONNEL'
           AND mc.fin IS NOT NULL AND NOT mc.est_pause
      ) THEN 'PREVISIONNEL'
      WHEN EXISTS (
        SELECT 1 FROM public.mission_creneaux mc
         WHERE mc.mission_id = m.id AND mc.type_creneau = 'EFFECTIF'
           AND mc.fin IS NOT NULL AND NOT mc.est_pause
      ) THEN 'EFFECTIF'
      ELSE NULL
    END AS type_creneau
    FROM mission m
  ), heures_creneaux AS (
    SELECT sum(
      extract(epoch FROM (
        least(mc.fin, b.fin_ts) - greatest(mc.debut, b.debut_ts)
      )) / 3600.0
    ) AS heures
    FROM public.mission_creneaux mc
    CROSS JOIN bornes b
    CROSS JOIN type_reference tr
    WHERE tr.type_creneau IS NOT NULL
      AND mc.mission_id = p_mission_id
      AND mc.type_creneau = tr.type_creneau
      AND mc.fin IS NOT NULL
      AND NOT mc.est_pause
      AND mc.debut < b.fin_ts
      AND mc.fin > b.debut_ts
  ), heures_repli AS (
    -- Compatibilité avec les anciennes missions simples sans créneaux.
    SELECT CASE
      WHEN tr.type_creneau IS NULL
       AND COALESCE(m.nb_creneaux, 0) <= 1
       AND date_trunc('week', m.debut_le AT TIME ZONE 'Europe/Paris')::date = p_semaine_debut
      THEN COALESCE(
        m.duree_heures,
        extract(epoch FROM (m.fin_le - m.debut_le)) / 3600.0,
        0
      )
      ELSE 0
    END AS heures
    FROM mission m CROSS JOIN type_reference tr
  )
  SELECT round(COALESCE(hc.heures, hr.heures, 0)::numeric, 2)
  FROM heures_creneaux hc CROSS JOIN heures_repli hr;
$function$;

CREATE OR REPLACE FUNCTION public.fn_semaines_mission(p_mission_id uuid)
RETURNS TABLE(semaine_debut date, heures numeric)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  WITH bornes AS (
    SELECT
      date_trunc('week', m.debut_le AT TIME ZONE 'Europe/Paris')::date AS premiere,
      date_trunc(
        'week',
        (m.fin_le - interval '1 microsecond') AT TIME ZONE 'Europe/Paris'
      )::date AS derniere
    FROM public.missions m
    WHERE m.id = p_mission_id
  ), semaines AS (
    SELECT (b.premiere + (n * 7))::date AS semaine_debut
    FROM bornes b
    CROSS JOIN LATERAL generate_series(0, ((b.derniere - b.premiere) / 7)::integer) n
  )
  SELECT s.semaine_debut, h.heures
  FROM semaines s
  CROSS JOIN LATERAL (
    SELECT public.fn_heures_mission_semaine(p_mission_id, s.semaine_debut) AS heures
  ) h
  WHERE h.heures > 0
  ORDER BY s.semaine_debut;
$function$;

CREATE OR REPLACE FUNCTION public.fn_heures_soignant_semaine(
  p_soignant_id uuid,
  p_semaine_debut date,
  p_exclure_mission_id uuid DEFAULT NULL
) RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  SELECT round(COALESCE(sum(
    public.fn_heures_mission_semaine(m.id, p_semaine_debut)
  ), 0)::numeric, 2)
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.id IS DISTINCT FROM p_exclure_mission_id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND m.debut_le < ((p_semaine_debut + 7)::timestamp AT TIME ZONE 'Europe/Paris')
    AND m.fin_le > (p_semaine_debut::timestamp AT TIME ZONE 'Europe/Paris')
    AND COALESCE(
      m.type_contrat_applique::text,
      NULLIF(upper(m.choix_contrat_soignant), ''),
      CASE WHEN m.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
    ) = 'SALARIE';
$function$;

REVOKE ALL ON FUNCTION public.fn_heures_mission_semaine(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_semaines_mission(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_heures_soignant_semaine(uuid, date, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_heures_mission_semaine(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_semaines_mission(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_heures_soignant_semaine(uuid, date, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.dec_verifier_plafond_48h()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_semaine record;
  v_heures_jolene numeric;
  v_heures_externes numeric;
  v_heures_total numeric;
  v_regime text;
  v_nb_creneaux_valides integer;
  v_details_semaines jsonb := '[]'::jsonb;
BEGIN
  IF NEW.soignant_assigne_id IS NULL OR NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN NEW;
  END IF;

  v_regime := COALESCE(
    NEW.type_contrat_applique::text,
    NULLIF(upper(NEW.choix_contrat_soignant), ''),
    CASE WHEN NEW.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  IF v_regime = 'LIBERAL' THEN RETURN NEW; END IF;

  IF COALESCE(NEW.nb_creneaux, 0) > 1 THEN
    SELECT count(*)::integer INTO v_nb_creneaux_valides
      FROM public.mission_creneaux mc
     WHERE mc.mission_id = NEW.id
       AND mc.fin IS NOT NULL
       AND mc.type_creneau = CASE
         WHEN EXISTS (
           SELECT 1 FROM public.mission_creneaux p
            WHERE p.mission_id = NEW.id AND p.type_creneau = 'PREVISIONNEL'
              AND p.fin IS NOT NULL AND NOT p.est_pause
         ) THEN 'PREVISIONNEL'
         ELSE 'EFFECTIF'
       END;
    IF v_nb_creneaux_valides < NEW.nb_creneaux THEN
      RAISE EXCEPTION '[PLANNING_HEBDOMADAIRE_INDISPONIBLE] Mission % : % créneau(x) valide(s) sur % attendu(s)',
        NEW.id, v_nb_creneaux_valides, NEW.nb_creneaux;
    END IF;
  END IF;

  FOR v_semaine IN
    SELECT * FROM public.fn_semaines_mission(NEW.id)
  LOOP
    v_heures_jolene := public.fn_heures_soignant_semaine(
      NEW.soignant_assigne_id, v_semaine.semaine_debut, NEW.id
    );
    SELECT COALESCE(heures_salarie, 0)
      INTO v_heures_externes
      FROM public.attestations_heures_externes
     WHERE soignant_id = NEW.soignant_assigne_id
       AND semaine_du = v_semaine.semaine_debut;
    IF NOT FOUND THEN v_heures_externes := 0; END IF;

    v_heures_total := v_heures_jolene + v_heures_externes + v_semaine.heures;
    v_details_semaines := v_details_semaines || jsonb_build_array(jsonb_build_object(
      'semaine_du', v_semaine.semaine_debut,
      'heures_jolene_existantes', round(v_heures_jolene, 2),
      'heures_mission', round(v_semaine.heures, 2),
      'heures_externes', round(v_heures_externes, 2),
      'total', round(v_heures_total, 2),
      'plafond', 48
    ));

    IF v_heures_total > 48 THEN
      INSERT INTO public.conformite_travail(
        soignant_id, mission_id, type_controle, resultat, details_violation
      ) VALUES (
        NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'VIOLATION_BLOQUEE',
        jsonb_build_object(
          'semaine_du', v_semaine.semaine_debut,
          'heures_jolene', round(v_heures_jolene + v_semaine.heures, 2),
          'heures_externes', round(v_heures_externes, 2),
          'total', round(v_heures_total, 2),
          'plafond', 48,
          'article', 'L3121-20'
        )
      );
      RAISE EXCEPTION '[CODE DU TRAVAIL] Semaine du % : %h Jolene + %h ailleurs = %h total (max 48h, Art. L3121-20)',
        to_char(v_semaine.semaine_debut, 'DD/MM/YYYY'),
        round(v_heures_jolene + v_semaine.heures, 1),
        round(v_heures_externes, 1),
        round(v_heures_total, 1);
    END IF;
  END LOOP;

  INSERT INTO public.conformite_travail(
    soignant_id, mission_id, type_controle, resultat, details_violation
  ) VALUES (
    NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'CONFORME',
    jsonb_build_object('semaines', v_details_semaines)
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_verifier_plafond_48h() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_plafond_48h() TO service_role;

-- La pré-vérification atomique doit appliquer exactement la même ventilation
-- que le trigger, sinon une mission 40h + 40h serait rejetée avant l'UPDATE.
CREATE OR REPLACE FUNCTION public.fn_finaliser_attribution_mission(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_etab record;
  v_resolution jsonb;
  v_choix text;
  v_semaine record;
  v_heures_existantes numeric;
  v_heures_externes numeric;
  v_heures_total numeric;
  v_nb_creneaux_valides integer;
  v_type_contrat text;
  v_type_paiement text;
  v_mode_paiement text;
  v_numero text;
  v_html text;
  v_contrat_id uuid;
  v_rows integer;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible');
  END IF;

  SELECT * INTO v_soignant FROM public.soignants
   WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant (' || v_soignant.profession::text ||
        ') n''est pas compatible avec la profession requise par la mission (' ||
        v_mission.profession_requise::text || ').'
    );
  END IF;

  IF public.fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Accès refusé pour cette mission.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, p_soignant_id, p_choix_contrat);
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';

  IF NOT public.fn_documents_ok_pour_mission(p_soignant_id, v_choix) THEN
    RETURN jsonb_build_object(
      'error', 'Les documents requis pour une mission ' || lower(v_choix) ||
        ' ne sont pas encore validés.',
      'documents_requis_pour', v_choix,
      'lien_documents', '/soignant/mes-documents'
    );
  END IF;

  -- Sérialise toutes les attributions visant un même soignant dans la
  -- transaction courante. Deux missions acceptées en parallèle ne peuvent
  -- ainsi plus vérifier chacune un planning encore vide puis dépasser 48 h.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('jolene:attribution:' || p_soignant_id::text, 0)
  );

  IF v_choix = 'SALARIE' THEN
    IF COALESCE(v_mission.nb_creneaux, 0) > 1 THEN
      SELECT count(*)::integer INTO v_nb_creneaux_valides
        FROM public.mission_creneaux mc
       WHERE mc.mission_id = p_mission_id
         AND mc.fin IS NOT NULL
         AND mc.type_creneau = CASE
           WHEN EXISTS (
             SELECT 1 FROM public.mission_creneaux p
              WHERE p.mission_id = p_mission_id AND p.type_creneau = 'PREVISIONNEL'
                AND p.fin IS NOT NULL AND NOT p.est_pause
           ) THEN 'PREVISIONNEL'
           ELSE 'EFFECTIF'
         END;
      IF v_nb_creneaux_valides < v_mission.nb_creneaux THEN
        RETURN jsonb_build_object(
          'error', 'Planning hebdomadaire incomplet : impossible de vérifier le plafond de 48 h.',
          'code', 'PLANNING_HEBDOMADAIRE_INDISPONIBLE',
          'creneaux_valides', v_nb_creneaux_valides,
          'creneaux_attendus', v_mission.nb_creneaux
        );
      END IF;
    END IF;

    FOR v_semaine IN
      SELECT * FROM public.fn_semaines_mission(p_mission_id)
    LOOP
      v_heures_existantes := public.fn_heures_soignant_semaine(
        p_soignant_id, v_semaine.semaine_debut, p_mission_id
      );
      SELECT COALESCE(heures_salarie, 0)
        INTO v_heures_externes
        FROM public.attestations_heures_externes
       WHERE soignant_id = p_soignant_id
         AND semaine_du = v_semaine.semaine_debut;
      IF NOT FOUND THEN v_heures_externes := 0; END IF;
      v_heures_total := v_heures_existantes + v_heures_externes + v_semaine.heures;

      IF v_heures_total > 48 THEN
        RETURN jsonb_build_object(
          'error', 'Dépassement du plafond de 48 h pour la semaine du ' ||
            to_char(v_semaine.semaine_debut, 'DD/MM/YYYY') || ' (' ||
            round(v_heures_existantes, 1) || ' h déjà planifiées + ' ||
            round(v_semaine.heures, 1) || ' h pour cette mission + ' ||
            round(v_heures_externes, 1) || ' h ailleurs).',
          'code', 'PLAFOND_48H_HEBDO',
          'semaine_du', v_semaine.semaine_debut,
          'heures_existantes', round(v_heures_existantes, 2),
          'heures_mission', round(v_semaine.heures, 2),
          'heures_externes', round(v_heures_externes, 2),
          'total', round(v_heures_total, 2)
        );
      END IF;
    END LOOP;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_type_contrat := 'REMPLACEMENT_LIBERAL';
    v_type_paiement := 'NOTE_HONORAIRES';
    v_mode_paiement := 'STRIPE_CONNECT';
  ELSE
    v_type_contrat := 'CDD';
    v_type_paiement := 'BULLETIN_PAIE';
    v_mode_paiement := 'DIRECT';
  END IF;

  PERFORM set_config('jolene.assignment_rpc_soignant_id', p_soignant_id::text, true);
  UPDATE public.missions
     SET soignant_assigne_id = p_soignant_id,
         statut = 'ASSIGNEE',
         type_contrat_applique = v_choix::public.type_contrat_applique_enum,
         choix_contrat_soignant = v_choix,
         type_paiement_soignant = v_type_paiement,
         mode_paiement_soignant = v_mode_paiement,
         modifie_le = now()
   WHERE id = p_mission_id AND statut = 'OUVERTE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('error', 'Cette mission vient d''être attribuée.');
  END IF;

  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_mission.etablissement_id;
  v_numero := public.fn_generer_numero_contrat_safe(v_type_contrat);
  SELECT contenu_html INTO v_html
    FROM public.templates_contrat
   WHERE type_contrat = v_type_contrat AND est_actif = true
   LIMIT 1;

  IF v_html IS NOT NULL THEN
    v_html := replace(v_html, '{{etablissement_nom}}', public.fn_html_escape(COALESCE(v_etab.nom, '')));
    v_html := replace(v_html, '{{etablissement_siret}}', public.fn_html_escape(COALESCE(v_etab.siret, '')));
    v_html := replace(v_html, '{{etablissement_finess}}', public.fn_html_escape(COALESCE(v_etab.finess, 'N/A')));
    v_html := replace(v_html, '{{etablissement_adresse}}', public.fn_html_escape(COALESCE(v_etab.adresse_rue || ', ' || v_etab.adresse_code_postal || ' ' || v_etab.adresse_ville, '')));
    v_html := replace(v_html, '{{soignant_prenom}}', public.fn_html_escape(COALESCE(v_soignant.prenom, '')));
    v_html := replace(v_html, '{{soignant_nom}}', public.fn_html_escape(COALESCE(v_soignant.nom, '')));
    v_html := replace(v_html, '{{soignant_rpps}}', public.fn_html_escape(COALESCE(v_soignant.numero_rpps, '')));
    v_html := replace(v_html, '{{soignant_siret}}', public.fn_html_escape(COALESCE(v_soignant.siret_liberal, '')));
    v_html := replace(v_html, '{{profession}}', public.fn_html_escape(v_mission.profession_requise::text));
    v_html := replace(v_html, '{{service}}', public.fn_html_escape(COALESCE(v_mission.service, '')));
    v_html := replace(v_html, '{{debut_date}}', to_char(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
    v_html := replace(v_html, '{{debut_heure}}', to_char(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
    v_html := replace(v_html, '{{fin_date}}', to_char(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
    v_html := replace(v_html, '{{fin_heure}}', to_char(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
    v_html := replace(v_html, '{{duree_heures}}', COALESCE(v_mission.duree_heures::text, ''));
    v_html := replace(v_html, '{{taux_horaire}}', COALESCE(v_mission.taux_horaire_base::text, ''));
    v_html := replace(v_html, '{{retrocession_pct}}', COALESCE(v_mission.retrocession_pct::text, ''));
    v_html := replace(v_html, '{{numero_contrat}}', public.fn_html_escape(v_numero));
    v_html := replace(v_html, '{{date_signature}}', to_char(now() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
    v_html := replace(v_html, '{{lieu}}', public.fn_html_escape(COALESCE(v_etab.adresse_ville, '')));
  END IF;

  SELECT id INTO v_contrat_id
    FROM public.contrats_mission
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
     AND statut <> 'ANNULE'
   ORDER BY cree_le DESC
   LIMIT 1;

  IF v_contrat_id IS NULL THEN
    INSERT INTO public.contrats_mission(
      mission_id, etablissement_id, soignant_id,
      type_contrat, numero_contrat, contenu_html, statut
    ) VALUES (
      p_mission_id, v_mission.etablissement_id, p_soignant_id,
      v_type_contrat, v_numero, v_html, 'EN_ATTENTE_SIGNATURES'
    ) RETURNING id INTO v_contrat_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'contrat_id', v_contrat_id,
    'contrat_numero', v_numero,
    'choix_applique', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_paiement', v_type_paiement,
    'mode_paiement', v_mode_paiement
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_finaliser_attribution_mission(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_finaliser_attribution_mission(uuid, uuid, text) TO service_role;
