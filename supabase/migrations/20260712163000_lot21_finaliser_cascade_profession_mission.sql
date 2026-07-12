-- Lot 21 / D4 — cascade métier déterminée par la mission.
--
-- Une spécialisation portée par le profil (par exemple IADE) sert uniquement à
-- vérifier la compatibilité de compétences. Le régime juridique et contractuel
-- est résolu depuis missions.profession_requise + la catégorie d'établissement.
-- Un profil libéral reste valide et peut accepter une mission salariée : ce
-- sont alors les documents SALARIE_ONLY et un CDD qui s'appliquent.

-- C7 : aligne le libellé réellement affiché sur le wording expressément
-- validé, sans réécrire les migrations déjà appliquées.
UPDATE public.matrice_modes_exercice
   SET source_libelle = 'L''exercice libéral n''est pas prévu pour cette profession — lettre interministérielle du 30 décembre 2021 (n° D21-031940), validée par le Conseil d''État (11/02/2025, n°491128). Mission proposée en salarié.'
 WHERE profession IN ('AUXILIAIRE_PUERICULTURE', 'IBODE', 'IADE')
   AND source_force = 'DOCTRINE';

-- Résolution centralisée du contrat effectif. La matrice est relue en défense
-- en profondeur lorsqu'un contrat libéral est demandé.
CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_etablissement record;
  v_recherche text;
  v_choix text;
  v_mode jsonb;
BEGIN
  SELECT id, profession_requise, type_contrat_recherche, etablissement_id
    INTO v_mission
    FROM public.missions
   WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission introuvable');
  END IF;

  SELECT id, COALESCE(type_exercice, 'SALARIE') AS type_exercice,
         preference_contrat_mixte, COALESCE(est_compte_test, false) AS est_compte_test
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Profil soignant introuvable');
  END IF;

  SELECT type::text AS type_etablissement,
         COALESCE(est_secteur_public, false) AS est_public,
         COALESCE(est_compte_test, false) AS est_compte_test
    INTO v_etablissement
    FROM public.etablissements
   WHERE id = v_mission.etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Établissement introuvable');
  END IF;
  -- Les comptes de démonstration conservent toutes leurs données pour les
  -- captures stores, sans les exposer aux comptes réels.
  IF v_etablissement.est_compte_test AND NOT v_soignant.est_compte_test THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission de démonstration non disponible');
  END IF;

  IF p_choix_contrat IS NOT NULL AND upper(p_choix_contrat) NOT IN ('SALARIE', 'LIBERAL') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Choix de contrat invalide');
  END IF;

  v_recherche := CASE
    WHEN upper(COALESCE(v_mission.type_contrat_recherche::text, 'SALARIE')) IN ('SALARIE', 'LIBERAL', 'TOUS')
      THEN upper(COALESCE(v_mission.type_contrat_recherche::text, 'SALARIE'))
    ELSE 'SALARIE'
  END;

  IF v_recherche = 'SALARIE' THEN
    -- Important : le type_exercice du PROFIL ne bloque jamais un CDD.
    v_choix := 'SALARIE';
  ELSIF v_recherche = 'LIBERAL' THEN
    IF v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est proposée en libéral ; activez un profil libéral valide ou choisissez une mission salariée.');
    END IF;
    v_choix := 'LIBERAL';
  ELSE
    v_choix := upper(p_choix_contrat);
    IF v_choix IS NULL THEN
      IF v_soignant.type_exercice = 'MIXTE' THEN
        v_choix := CASE
          WHEN upper(COALESCE(v_soignant.preference_contrat_mixte, '')) IN ('SALARIE', 'LIBERAL')
            THEN upper(v_soignant.preference_contrat_mixte)
          ELSE NULL
        END;
        IF v_choix IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Choisissez votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD / bulletin de paie)'),
              jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')
            )
          );
        END IF;
      ELSIF v_soignant.type_exercice = 'LIBERAL' THEN
        v_choix := 'LIBERAL';
      ELSE
        v_choix := 'SALARIE';
      END IF;
    END IF;

    IF v_choix = 'LIBERAL' AND v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Votre profil n''est pas activé pour un contrat libéral.');
    END IF;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_mode := public.fn_mode_exercice(
      v_mission.profession_requise::text,
      v_etablissement.type_etablissement,
      CASE WHEN v_etablissement.est_public THEN 'PUBLIC' ELSE NULL END
    );
    IF COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE' THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', COALESCE(v_mode->>'source_libelle', 'Cette mission est proposée en salarié.'),
        'niveau', COALESCE(v_mode->>'niveau', 'NON_PROPOSE')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_contrat_recherche', v_recherche
  );
END;
$function$;

-- Éligibilité canonique créée avant tous ses consommateurs (y compris les
-- fonctions LANGUAGE sql, dont les dépendances sont résolues à la création).
CREATE OR REPLACE FUNCTION public.fn_soignant_eligible_mission(
  p_soignant_id uuid,
  p_mission_id uuid,
  p_exiger_documents boolean DEFAULT false
) RETURNS boolean
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_type text;
  v_resolution jsonb;
BEGIN
  SELECT profession_requise, specialite_medicale_requise,
         COALESCE(accepte_non_specialises, true) AS accepte_non_specialises,
         COALESCE(type_contrat_recherche::text, 'SALARIE') AS type_contrat_recherche
    INTO v_mission
    FROM public.missions
   WHERE id = p_mission_id AND statut = 'OUVERTE';
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT profession, specialite_medicale,
         COALESCE(type_exercice, 'SALARIE') AS type_exercice
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id
     AND supprime_le IS NULL
     AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
  IF NOT FOUND THEN RETURN false; END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    v_mission.accepte_non_specialises
  ) THEN
    RETURN false;
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id, p_soignant_id, NULL
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE
     AND COALESCE((v_resolution->>'choix_requis')::boolean, false) IS NOT TRUE THEN
    RETURN false;
  END IF;
  IF NOT p_exiger_documents THEN RETURN true; END IF;

  IF COALESCE((v_resolution->>'choix_requis')::boolean, false) THEN
    RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'SALARIE')
      OR (v_soignant.type_exercice IN ('LIBERAL', 'MIXTE')
          AND public.fn_documents_ok_pour_mission(p_soignant_id, 'LIBERAL'));
  END IF;
  v_type := v_resolution->>'contrat';
  IF v_type = 'LIBERAL' THEN
    RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'LIBERAL');
  END IF;
  RETURN public.fn_documents_ok_pour_mission(p_soignant_id, 'SALARIE');
END;
$function$;

-- Les plafonds de temps de travail suivent les missions salariées, pas le
-- statut global du profil. Un profil IADE libéral reste donc soumis aux 48 h
-- lorsqu'il accepte une mission IDE salariée ; ses missions libérales ne sont
-- pas additionnées au décompte du code du travail.
CREATE OR REPLACE FUNCTION public.dec_verifier_plafond_48h()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_heures_mission numeric;
  v_heures_jolene numeric;
  v_heures_externes numeric;
  v_heures_total numeric;
  v_semaine_debut date;
  v_use_effectif boolean;
  v_regime text;
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

  v_semaine_debut := date_trunc('week', NEW.debut_le)::date;
  v_use_effectif := EXISTS (
    SELECT 1 FROM public.mission_creneaux
     WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL
  );
  IF v_use_effectif THEN
    SELECT COALESCE(sum(extract(epoch FROM (fin - debut)) / 3600.0), 0)
      INTO v_heures_mission
      FROM public.mission_creneaux
     WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF'
       AND fin IS NOT NULL AND NOT est_pause;
  ELSE
    SELECT COALESCE(sum(extract(epoch FROM (fin - debut)) / 3600.0), 0)
      INTO v_heures_mission
      FROM public.mission_creneaux
     WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND NOT est_pause;
  END IF;
  IF v_heures_mission = 0
     AND NOT EXISTS (SELECT 1 FROM public.mission_creneaux WHERE mission_id = NEW.id) THEN
    v_heures_mission := COALESCE(
      NEW.duree_heures,
      extract(epoch FROM (NEW.fin_le - NEW.debut_le)) / 3600.0,
      0
    );
  END IF;

  SELECT COALESCE(sum(
    CASE WHEN EXISTS (
      SELECT 1 FROM public.mission_creneaux mc2
       WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL
    ) THEN (
      SELECT COALESCE(sum(extract(epoch FROM (mc3.fin - mc3.debut)) / 3600.0), 0)
        FROM public.mission_creneaux mc3
       WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF'
         AND mc3.fin IS NOT NULL AND NOT mc3.est_pause
    ) ELSE (
      SELECT COALESCE(sum(extract(epoch FROM (mc4.fin - mc4.debut)) / 3600.0), 0)
        FROM public.mission_creneaux mc4
       WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause
    ) END
  ), 0)
    INTO v_heures_jolene
    FROM public.missions m
   WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
     AND m.id <> NEW.id
     AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
     AND m.debut_le >= v_semaine_debut::timestamptz
     AND m.debut_le < (v_semaine_debut + 7)::timestamptz
     AND COALESCE(
       m.type_contrat_applique::text,
       NULLIF(upper(m.choix_contrat_soignant), ''),
       CASE WHEN m.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
     ) = 'SALARIE';

  SELECT COALESCE(heures_salarie, 0)
    INTO v_heures_externes
    FROM public.attestations_heures_externes
   WHERE soignant_id = NEW.soignant_assigne_id AND semaine_du = v_semaine_debut;
  IF NOT FOUND THEN v_heures_externes := 0; END IF;

  v_heures_total := v_heures_jolene + v_heures_externes + v_heures_mission;
  IF v_heures_total > 48 THEN
    INSERT INTO public.conformite_travail(
      soignant_id, mission_id, type_controle, resultat, details_violation
    ) VALUES (
      NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'VIOLATION_BLOQUEE',
      jsonb_build_object(
        'heures_jolene', round(v_heures_jolene + v_heures_mission, 2),
        'heures_externes', round(v_heures_externes, 2),
        'total', round(v_heures_total, 2), 'plafond', 48, 'article', 'L3121-20'
      )
    );
    RAISE EXCEPTION '[CODE DU TRAVAIL] Plafond hebdomadaire dépassé : %h Jolene + %h ailleurs = %h total (max 48h, Art. L3121-20)',
      round(v_heures_jolene + v_heures_mission, 1),
      round(v_heures_externes, 1), round(v_heures_total, 1);
  END IF;

  INSERT INTO public.conformite_travail(
    soignant_id, mission_id, type_controle, resultat, details_violation
  ) VALUES (
    NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'CONFORME',
    jsonb_build_object('total_heures', round(v_heures_total, 2))
  );
  RETURN NEW;
END;
$function$;

-- L'activation du pool accepte un dossier valide pour au moins un des deux
-- régimes. Chaque mission sera ensuite filtrée par fn_soignant_eligible_mission.
CREATE OR REPLACE FUNCTION public.fn_toggle_pool_urgence(
  p_actif boolean,
  p_rayon_km integer DEFAULT 15,
  p_creneaux jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant record;
  v_salarie_ok boolean;
  v_liberal_ok boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT id, COALESCE(type_exercice, 'SALARIE') AS type_exercice INTO v_soignant
    FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;
  IF p_rayon_km IS NULL OR p_rayon_km < 1 OR p_rayon_km > 200 THEN
    RETURN jsonb_build_object('error', 'Le rayon doit être compris entre 1 et 200 km.');
  END IF;

  IF p_actif THEN
    v_salarie_ok := public.fn_documents_ok_pour_mission(v_uid, 'SALARIE');
    v_liberal_ok := v_soignant.type_exercice IN ('LIBERAL', 'MIXTE')
      AND public.fn_documents_ok_pour_mission(v_uid, 'LIBERAL');
    IF NOT v_salarie_ok AND NOT v_liberal_ok THEN
      RETURN jsonb_build_object(
        'error', 'Validez les documents d’au moins un type de mission (salariée ou libérale) pour rejoindre le pool urgence.',
        'documents_salarie_ok', false,
        'documents_liberal_ok', false
      );
    END IF;
  END IF;

  UPDATE public.soignants
     SET disponible_urgence = COALESCE(p_actif, false),
         urgence_rayon_km = p_rayon_km,
         urgence_creneaux = p_creneaux,
         modifie_le = now()
   WHERE id = v_uid;

  RETURN jsonb_build_object(
    'success', true,
    'disponible_urgence', COALESCE(p_actif, false),
    'documents_salarie_ok', COALESCE(v_salarie_ok, false),
    'documents_liberal_ok', COALESCE(v_liberal_ok, false)
  );
END;
$function$;

-- Rebooking : une spécialisation IADE/IBODE est compatible avec une mission
-- IDE et ne doit pas être rejetée par une ancienne égalité stricte.
CREATE OR REPLACE FUNCTION public.fn_rebooker_soignant(
  p_soignant_id uuid,
  p_mission_modele_id uuid,
  p_debut timestamptz,
  p_fin timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_s record;
  v_new_id uuid;
  v_resolution jsonb;
BEGIN
  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_modele_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission modèle introuvable'); END IF;
  IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_debut IS NULL OR p_fin IS NULL OR p_fin <= p_debut OR p_debut < now() THEN
    RETURN jsonb_build_object('error', 'Dates invalides (le début doit être dans le futur).');
  END IF;
  SELECT * INTO v_s FROM public.soignants WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_s.profession, v_s.specialite_medicale,
    v_m.profession_requise, v_m.specialite_medicale_requise,
    COALESCE(v_m.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('error', 'Le soignant n’est pas compatible avec la profession requise par la mission modèle.');
  END IF;
  IF public.fn_est_exclu(p_soignant_id, v_m.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d’exclusions.');
  END IF;
  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_modele_id, p_soignant_id, NULL
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE
     AND COALESCE((v_resolution->>'choix_requis')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;

  INSERT INTO public.missions(
    etablissement_id, intitule, description, service,
    profession_requise, specialite_medicale_requise, accepte_non_specialises,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    type_contrat_recherche, statut, mode_attribution, est_urgente,
    garantie_remplacement, mission_source
  ) VALUES (
    v_m.etablissement_id, v_m.intitule, v_m.description, v_m.service,
    v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_non_specialises,
    p_debut, p_fin, round(extract(epoch FROM (p_fin - p_debut)) / 3600.0, 2),
    v_m.taux_horaire_base, v_m.type_contrat_recherche, 'OUVERTE', 'CANDIDATURE',
    false, COALESCE(v_m.garantie_remplacement, false), 'REBOOK'
  ) RETURNING id INTO v_new_id;

  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Un établissement veut retravailler avec vous ⭐',
    public.fn_html_escape(v_m.intitule) || ' du ' ||
      to_char(p_debut AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || ' au ' ||
      to_char(p_fin AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || ' à ' ||
      COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h — vous êtes leur premier choix, postulez en 1 clic.',
    '/soignant/missions/' || v_new_id, 'SOIGNANT'
  );
  RETURN jsonb_build_object('success', true, 'mission_id', v_new_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_suggestions_missions_pour_soignant(p_limit integer DEFAULT 5)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant record;
  v_result jsonb;
  v_limit integer;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  v_limit := least(greatest(COALESCE(p_limit, 5), 1), 10);
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

  WITH candidates AS (
    SELECT m.id, m.intitule, m.profession_requise, m.specialite_medicale_requise,
      m.type_contrat_recherche, m.taux_horaire_base, m.debut_le, m.fin_le,
      m.est_urgente, m.cree_le, m.etablissement_id,
      e.nom AS etab_nom, e.adresse_ville AS etab_ville,
      e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
      (SELECT round(avg(note)::numeric, 2) FROM public.evaluations ev
       JOIN public.missions m2 ON m2.id = ev.mission_id
       WHERE m2.etablissement_id = m.etablissement_id AND ev.note IS NOT NULL) AS etab_note_moyenne,
      CASE WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
        round((6371 * 2 * asin(sqrt(
          power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
          cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
          power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
        )))::numeric, 1)
      ELSE NULL END AS distance_km
    FROM public.missions m
    LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND public.fn_soignant_eligible_mission(v_uid, m.id, false)
      AND NOT public.fn_est_exclu(v_uid, m.etablissement_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.candidatures c
         WHERE c.mission_id = m.id AND c.soignant_id = v_uid
      )
      AND (
        v_soignant.rayon_deplacement_km IS NULL OR e.adresse_lat IS NULL
        OR v_soignant.adresse_lat IS NULL OR
        (6371 * 2 * asin(sqrt(
          power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
          cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
          power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
        ))) <= v_soignant.rayon_deplacement_km
      )
      AND COALESCE(m.taux_horaire_base, 0) >= COALESCE(v_soignant.taux_horaire_minimum, 0)
  ), ranked AS (
    SELECT *, row_number() OVER (
      ORDER BY est_urgente DESC, distance_km ASC NULLS LAST,
               etab_note_moyenne DESC NULLS LAST, cree_le DESC
    ) AS rn
    FROM candidates
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id, 'intitule', r.intitule,
    'profession_requise', r.profession_requise::text,
    'specialite_medicale_requise', r.specialite_medicale_requise,
    'type_contrat_recherche', r.type_contrat_recherche,
    'taux_horaire_base', r.taux_horaire_base,
    'debut_le', r.debut_le, 'fin_le', r.fin_le,
    'est_urgente', r.est_urgente, 'etablissement_id', r.etablissement_id,
    'etab_nom', r.etab_nom, 'etab_ville', r.etab_ville,
    'etab_note_moyenne', r.etab_note_moyenne, 'distance_km', r.distance_km
  ) ORDER BY r.rn), '[]'::jsonb)
    INTO v_result
    FROM (SELECT * FROM ranked WHERE rn <= v_limit) r;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_booster_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_prix numeric;
  v_nb integer := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
         e.adresse_ville AS etab_ville
    INTO v_m
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Seule une mission ouverte peut être boostée.');
  END IF;
  IF v_m.boostee_le IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Cette mission est déjà boostée.');
  END IF;

  v_prix := public.fn_param_num('mission_boost_prix_ht', 0);
  UPDATE public.missions
     SET boostee_le = now(), montant_boost_ht = COALESCE(v_prix, 0), modifie_le = now()
   WHERE id = p_mission_id;

  WITH cibles AS (
    SELECT s.id
      FROM public.soignants s
     WHERE public.fn_soignant_eligible_mission(s.id, p_mission_id, true)
       AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
       AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.candidatures c
          WHERE c.mission_id = v_m.id AND c.soignant_id = s.id
       )
       AND (
         s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
         OR public.fn_haversine_distance_m(
           s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng
         ) <= COALESCE(s.rayon_deplacement_km, 50) * 1000
       )
     LIMIT 50
  )
  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  SELECT id, 'MISSION_A_POURVOIR', '🚀 Mission mise en avant près de chez vous',
    public.fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
    to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
    COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L’établissement recherche activement.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT'
  FROM cibles;
  GET DIAGNOSTICS v_nb = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true, 'soignants_notifies', v_nb, 'prix_ht', COALESCE(v_prix, 0)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_relancer_missions_sans_candidat()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_missions_relancees integer := 0;
  v_soignants_notifies integer := 0;
  v_nb integer;
BEGIN
  FOR v_m IN
    SELECT m.id, m.intitule, m.profession_requise, m.type_contrat_recherche,
           m.taux_horaire_base, m.debut_le, m.etablissement_id,
           e.nom AS etab_nom, e.adresse_ville AS etab_ville,
           e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
     WHERE m.statut = 'OUVERTE'
       AND m.mode_attribution = 'CANDIDATURE'
       AND m.debut_le > now()
       AND m.cree_le < now() - interval '24 hours'
       AND COALESCE(m.relances_sans_candidat, 0) < 2
       AND (m.derniere_relance_sans_candidat_le IS NULL
            OR m.derniere_relance_sans_candidat_le < now() - interval '48 hours')
       AND NOT EXISTS (
         SELECT 1 FROM public.candidatures c
          WHERE c.mission_id = m.id AND c.statut = 'EN_ATTENTE'
       )
     LIMIT 200
  LOOP
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (
      v_m.etablissement_id, 'MISSION_NON_POURVUE',
      'Aucun candidat pour « ' || public.fn_html_escape(v_m.intitule) || ' »',
      'Votre mission du ' || to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') ||
      ' n’a pas encore de candidat. Les soignants compatibles viennent d’être notifiés. Vérifiez le taux horaire ou alertez le pool d’urgence.',
      '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT'
    );

    WITH cibles AS (
      SELECT s.id
        FROM public.soignants s
       WHERE public.fn_soignant_eligible_mission(s.id, v_m.id, true)
         AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
         AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
         AND NOT EXISTS (
           SELECT 1 FROM public.candidatures c
            WHERE c.mission_id = v_m.id AND c.soignant_id = s.id
         )
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
            WHERE n.destinataire_id = s.id AND n.type = 'MISSION_A_POURVOIR'
              AND n.lien = '/soignant/missions/' || v_m.id
         )
         AND (
           s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
           OR public.fn_haversine_distance_m(
             s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng
           ) <= COALESCE(s.rayon_deplacement_km, 50) * 1000
         )
       LIMIT 25
    )
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    SELECT id, 'MISSION_A_POURVOIR',
      'Mission ' || v_m.profession_requise::text || ' à pourvoir près de chez vous',
      public.fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
      to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
      COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L’établissement cherche encore — postulez vite.',
      '/soignant/missions/' || v_m.id, 'SOIGNANT'
    FROM cibles;
    GET DIAGNOSTICS v_nb = ROW_COUNT;
    v_soignants_notifies := v_soignants_notifies + v_nb;

    UPDATE public.missions
       SET relances_sans_candidat = COALESCE(relances_sans_candidat, 0) + 1,
           derniere_relance_sans_candidat_le = now()
     WHERE id = v_m.id;
    v_missions_relancees := v_missions_relancees + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'missions_relancees', v_missions_relancees,
    'soignants_notifies', v_soignants_notifies
  );
END;
$function$;

-- Notification immédiate à la publication : même filtre canonique que le
-- feed. Cela évite que les anciens champs globaux `tous_documents_valides`,
-- `type_exercice` ou `mandat_facturation_signe` masquent une mission salariée.
CREATE OR REPLACE FUNCTION public.fn_trg_auto_notify_mission_urgente()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab record;
  v_count integer := 0;
  v_soignant record;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_should_fire boolean := false;
  v_corps text;
BEGIN
  IF TG_OP = 'INSERT'
     AND COALESCE(NEW.est_urgente, false)
     AND NEW.statut = 'OUVERTE' THEN
    v_should_fire := true;
  ELSIF TG_OP = 'UPDATE'
        AND COALESCE(NEW.est_urgente, false)
        AND NEW.statut = 'OUVERTE'
        AND (
          COALESCE(OLD.est_urgente, false) IS DISTINCT FROM COALESCE(NEW.est_urgente, false)
          OR (OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE')
        ) THEN
    v_should_fire := true;
  END IF;
  IF NOT v_should_fire THEN RETURN NEW; END IF;

  SELECT id, nom, adresse_lat, adresse_lng, adresse_ville
    INTO v_etab
    FROM public.etablissements WHERE id = NEW.etablissement_id;
  BEGIN
    v_token := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
       WHERE name = 'service_role_key' LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN v_token := NULL;
  END;
  IF COALESCE(current_setting('app.test_mode', true), '') = 'true' THEN
    v_token := NULL;
  END IF;

  FOR v_soignant IN
    SELECT s.id, s.email, s.prenom, s.telephone,
      COALESCE(s.pool_urgence_sms_opt_in, false) AS sms_opt_in,
      CASE WHEN v_etab.adresse_lat IS NOT NULL AND s.adresse_lat IS NOT NULL THEN
        6371 * 2 * asin(sqrt(
          power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
          cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
          power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
        ))
      ELSE NULL END AS distance_km
    FROM public.soignants s
    WHERE COALESCE(s.disponible_urgence, false)
      AND public.fn_soignant_eligible_mission(s.id, NEW.id, true)
      AND NOT public.fn_est_exclu(s.id, NEW.etablissement_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.candidatures c
         WHERE c.mission_id = NEW.id AND c.soignant_id = s.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.missions m2
         WHERE m2.soignant_assigne_id = s.id AND m2.id <> NEW.id
           AND m2.statut IN ('ASSIGNEE', 'EN_COURS')
           AND m2.debut_le < NEW.fin_le AND m2.fin_le > NEW.debut_le
      )
      AND (
        v_etab.adresse_lat IS NULL OR s.adresse_lat IS NULL
        OR 6371 * 2 * asin(sqrt(
          power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
          cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
          power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
        )) <= COALESCE(s.urgence_rayon_km, 30)
      )
    ORDER BY distance_km ASC NULLS LAST, COALESCE(s.score_fiabilite, 0) DESC
  LOOP
    v_corps := 'Mission ' || COALESCE(NEW.intitule, NEW.profession_requise::text) ||
      ' à ' || COALESCE(v_etab.adresse_ville, 'votre zone') ||
      CASE WHEN v_soignant.distance_km IS NOT NULL
        THEN ' (' || round(v_soignant.distance_km::numeric, 1) || ' km)' ELSE '' END ||
      ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h. Acceptez en 1 clic.';

    INSERT INTO public.notifications(
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      v_soignant.id, 'SOIGNANT', 'MISSION_URGENTE',
      '🚨 Mission urgente près de chez vous', v_corps,
      '/soignant/pool-urgence', 'mission', NEW.id
    );

    IF v_token IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-push',
          headers := jsonb_build_object(
            'Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token
          ),
          body := jsonb_build_object(
            'destinataire_id', v_soignant.id,
            'type_evenement', 'MISSION_URGENTE',
            'titre', '🚨 Mission urgente près de chez vous',
            'corps', v_corps,
            'data', jsonb_build_object(
              'mission_id', NEW.id, 'lien', '/soignant/pool-urgence'
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object(
            'Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token
          ),
          body := jsonb_build_object(
            'type', 'MISSION_URGENTE_POOL',
            'destinataire_id', v_soignant.id,
            'data', jsonb_build_object(
              'prenom', v_soignant.prenom,
              'mission_id', NEW.id,
              'mission_intitule', NEW.intitule,
              'profession', NEW.profession_requise::text,
              'ville', v_etab.adresse_ville,
              'distance_km', v_soignant.distance_km,
              'taux_horaire', NEW.taux_horaire_base,
              'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      IF v_soignant.sms_opt_in AND COALESCE(v_soignant.telephone, '') <> '' THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-sms',
            headers := jsonb_build_object(
              'Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token
            ),
            body := jsonb_build_object(
              'destinataire_id', v_soignant.id,
              'telephone', v_soignant.telephone,
              'message', 'URGENT - Mission ' || COALESCE(NEW.profession_requise::text, '') ||
                ' ' || COALESCE(v_etab.adresse_ville, '') || ' ' ||
                to_char(NEW.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24h') ||
                ' - ' || COALESCE(NEW.taux_horaire_base::text, '?') ||
                '€/h - Acceptez sur jolene.app/pool-urgence'
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := NEW.etablissement_id,
      p_type_acteur := 'SYSTEME',
      p_action := 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES',
      p_type_ressource := 'mission',
      p_id_ressource := NEW.id,
      p_details := jsonb_build_object(
        'count', v_count, 'mission_intitule', NEW.intitule,
        'event', TG_OP, 'filtre', 'fn_soignant_eligible_mission',
        'canaux', jsonb_build_array('in_app', 'push', 'email', 'sms_opt_in')
      )
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_detecter_noshow_et_remplacer()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_remplacement_id uuid;
  v_traites integer := 0;
  v_remplacements integer := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_s uuid;
  v_corps text;
BEGIN
  BEGIN
    v_token := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
       WHERE name = 'service_role_key' LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN v_token := NULL;
  END;

  FOR v_m IN
    SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
           e.adresse_ville AS etab_ville
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
     WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
       AND m.soignant_assigne_id IS NOT NULL
       AND m.debut_le < now() - interval '30 minutes'
       AND m.debut_le > now() - interval '4 hours'
       AND m.fin_le > now() + interval '1 hour'
       AND NOT EXISTS (
         SELECT 1 FROM public.presences p
          WHERE p.mission_id = m.id AND p.soignant_id = m.soignant_assigne_id
       )
       AND NOT EXISTS (
         SELECT 1 FROM public.missions r WHERE r.remplacement_de_mission_id = m.id
       )
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
          WHERE n.destinataire_id = m.etablissement_id AND n.type = 'SYSTEM'
            AND n.lien = '/etablissement/missions/' || m.id
            AND n.titre LIKE 'Aucun pointage%'
            AND n.cree_le > now() - interval '6 hours'
       )
  LOOP
    v_traites := v_traites + 1;
    IF v_m.garantie_remplacement THEN
      INSERT INTO public.missions(
        etablissement_id, intitule, description, service,
        profession_requise, specialite_medicale_requise, accepte_non_specialises,
        debut_le, fin_le, duree_heures, taux_horaire_base,
        type_contrat_recherche, statut, mode_attribution,
        est_urgente, niveau_urgence, remplacement_de_mission_id
      ) VALUES (
        v_m.etablissement_id,
        'REMPLACEMENT URGENT — ' || v_m.intitule,
        COALESCE(v_m.description, '') || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]',
        v_m.service,
        v_m.profession_requise, v_m.specialite_medicale_requise,
        v_m.accepte_non_specialises,
        greatest(v_m.debut_le, now() + interval '15 minutes'), v_m.fin_le,
        round(extract(epoch FROM (
          v_m.fin_le - greatest(v_m.debut_le, now() + interval '15 minutes')
        )) / 3600.0, 2),
        v_m.taux_horaire_base, v_m.type_contrat_recherche,
        'OUVERTE', 'PREMIER_ARRIVE', true, 3, v_m.id
      ) RETURNING id INTO v_remplacement_id;

      v_corps := public.fn_html_escape(v_m.intitule) || ' — ' ||
        COALESCE(v_m.etab_ville, '') || ', MAINTENANT à ' ||
        COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Acceptez en 1 clic.';

      -- Les anciens candidats restent prioritaires, mais sont revalidés sur
      -- la profession et le contrat de la nouvelle mission.
      FOR v_s IN
        SELECT c.soignant_id
          FROM public.candidatures c
         WHERE c.mission_id = v_m.id
           AND c.soignant_id IS NOT NULL
           AND c.soignant_id <> v_m.soignant_assigne_id
           AND c.statut::text NOT IN ('ACCEPTEE', 'RETIREE', 'ANNULEE')
           AND public.fn_soignant_eligible_mission(c.soignant_id, v_remplacement_id, true)
           AND NOT public.fn_est_exclu(c.soignant_id, v_m.etablissement_id)
      LOOP
        INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (
          v_s, 'POOL_URGENCE',
          '🎯 Une mission où tu avais postulé se libère — priorité à toi',
          v_corps, '/soignant/missions/' || v_remplacement_id, 'SOIGNANT'
        );
        IF v_token IS NOT NULL THEN
          BEGIN
            PERFORM net.http_post(
              url := v_url || '/functions/v1/send-push',
              headers := jsonb_build_object(
                'Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token
              ),
              body := jsonb_build_object(
                'destinataire_id', v_s, 'type_evenement', 'MISSION_URGENTE',
                'titre', '🎯 Une mission où tu avais postulé se libère',
                'corps', v_corps,
                'data', jsonb_build_object(
                  'mission_id', v_remplacement_id,
                  'lien', '/soignant/missions/' || v_remplacement_id
                )
              )
            );
          EXCEPTION WHEN OTHERS THEN NULL;
          END;
        END IF;
      END LOOP;

      -- Élargissement aux profils hors pool : la compatibilité hiérarchique et
      -- les documents sont ceux de la mission de remplacement.
      FOR v_s IN
        SELECT s.id
          FROM public.soignants s
         WHERE public.fn_soignant_eligible_mission(s.id, v_remplacement_id, true)
           AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
           AND COALESCE(s.disponible_urgence, false) = false
           AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
           AND s.id <> v_m.soignant_assigne_id
           AND NOT EXISTS (
             SELECT 1 FROM public.candidatures cb
              WHERE cb.mission_id = v_m.id AND cb.soignant_id = s.id
                AND cb.statut::text NOT IN ('ACCEPTEE', 'RETIREE', 'ANNULEE')
           )
           AND (
             s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR public.fn_haversine_distance_m(
               s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng
             ) <= COALESCE(s.rayon_deplacement_km, 50) * 1000
           )
         LIMIT 200
      LOOP
        INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (
          v_s, 'POOL_URGENCE',
          '🚨 Remplacement immédiat — premier arrivé, premier servi',
          v_corps, '/soignant/missions/' || v_remplacement_id, 'SOIGNANT'
        );
        IF v_token IS NOT NULL THEN
          BEGIN
            PERFORM net.http_post(
              url := v_url || '/functions/v1/send-push',
              headers := jsonb_build_object(
                'Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token
              ),
              body := jsonb_build_object(
                'destinataire_id', v_s, 'type_evenement', 'MISSION_URGENTE',
                'titre', '🚨 Remplacement immédiat près de chez vous',
                'corps', v_corps,
                'data', jsonb_build_object(
                  'mission_id', v_remplacement_id, 'lien', '/soignant/pool-urgence'
                )
              )
            );
          EXCEPTION WHEN OTHERS THEN NULL;
          END;
        END IF;
      END LOOP;

      INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (
        v_m.etablissement_id, 'SYSTEM', 'Aucun pointage — remplacement lancé 🚨',
        'Aucun pointage détecté 30 min après le début de « ' ||
          public.fn_html_escape(v_m.intitule) ||
          ' ». Garantie remplacement activée : une mission urgente vient d’être diffusée.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT'
      );
      UPDATE public.missions
         SET statut = 'ABSENCE', absence_sans_prevenir = true, modifie_le = now()
       WHERE id = v_m.id;
      v_remplacements := v_remplacements + 1;
    ELSE
      INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (
        v_m.etablissement_id, 'SYSTEM', 'Aucun pointage détecté ⚠️',
        'Aucun pointage 30 min après le début de « ' ||
          public.fn_html_escape(v_m.intitule) ||
          ' ». Contactez le soignant ou alertez le pool d’urgence depuis la mission.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT'
      );
    END IF;

    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (
      v_m.soignant_assigne_id, 'SYSTEM', 'Aucun pointage détecté sur votre mission',
      'Votre mission « ' || public.fn_html_escape(v_m.intitule) ||
        ' » a démarré il y a 30 min sans pointage. Pointez immédiatement ou contactez l’établissement.',
      '/soignant/presences', 'SOIGNANT'
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true, 'detectes', v_traites, 'remplacements', v_remplacements
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_escalade_remplacement_non_pourvu()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_s uuid;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  v_escalades integer := 0;
  v_notifies integer := 0;
  v_notifies_mission integer;
BEGIN
  BEGIN
    v_token := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
       WHERE name = 'service_role_key' LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN v_token := NULL;
  END;

  FOR v_m IN
    SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
           e.adresse_ville AS etab_ville
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
     WHERE m.remplacement_de_mission_id IS NOT NULL
       AND m.est_urgente = true
       AND m.statut = 'OUVERTE'
       AND m.cree_le < now() - interval '20 minutes'
       AND m.cree_le > now() - interval '4 hours'
       AND m.debut_le > now() - interval '15 minutes'
       AND NOT EXISTS (
         SELECT 1 FROM public.candidatures c WHERE c.mission_id = m.id
       )
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
          WHERE n.type_destinataire = 'ADMIN' AND n.type = 'SYSTEM'
            AND n.titre LIKE 'Remplacement non pourvu%'
            AND n.id_ressource = m.id
            AND n.cree_le > now() - interval '4 hours'
       )
  LOOP
    v_escalades := v_escalades + 1;
    v_notifies_mission := 0;
    v_corps := public.fn_html_escape(v_m.intitule) || ' — ' ||
      COALESCE(v_m.etab_ville, '') || ', URGENT à ' ||
      COALESCE(v_m.taux_horaire_base::text, '?') ||
      ' €/h. Toujours disponible, acceptez en 1 clic !';

    FOR v_s IN
      SELECT s.id
        FROM public.soignants s
       WHERE public.fn_soignant_eligible_mission(s.id, v_m.id, true)
         AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
         AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
         AND (
           s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
           OR public.fn_haversine_distance_m(
             s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng
           ) <= 80000
         )
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n2
            WHERE n2.destinataire_id = s.id
              AND n2.type_ressource = 'mission' AND n2.id_ressource = v_m.id
         )
       LIMIT 300
    LOOP
      INSERT INTO public.notifications(
        destinataire_id, type, titre, corps, lien, type_destinataire,
        type_ressource, id_ressource
      ) VALUES (
        v_s, 'POOL_URGENCE', '🚨 Remplacement urgent — toujours à pourvoir',
        v_corps, '/soignant/missions/' || v_m.id,
        'SOIGNANT', 'mission', v_m.id
      );
      v_notifies_mission := v_notifies_mission + 1;
      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object(
              'Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token
            ),
            body := jsonb_build_object(
              'destinataire_id', v_s, 'type_evenement', 'MISSION_URGENTE',
              'titre', '🚨 Remplacement urgent à pourvoir', 'corps', v_corps,
              'data', jsonb_build_object(
                'mission_id', v_m.id, 'lien', '/soignant/pool-urgence'
              )
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
    END LOOP;
    v_notifies := v_notifies + v_notifies_mission;

    BEGIN
      INSERT INTO public.notifications(
        destinataire_id, type_destinataire, type, titre, corps, lien,
        type_ressource, id_ressource
      )
      SELECT uid, 'ADMIN', 'SYSTEM',
        'Remplacement non pourvu — action requise 🚨',
        'La mission de remplacement « ' || public.fn_html_escape(v_m.intitule) ||
        ' » (' || COALESCE(v_m.etab_ville, '') ||
        ') reste sans candidat 20 min après diffusion. Rayon élargi à 80 km ; une intervention manuelle est conseillée.',
        '/admin/missions', 'mission', v_m.id
      FROM unnest(ARRAY(SELECT id FROM public.fn_list_admin_user_ids())) AS uid;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_m.etablissement_id,
      p_type_acteur := 'SYSTEME',
      p_action := 'REMPLACEMENT_ESCALADE',
      p_type_ressource := 'mission',
      p_id_ressource := v_m.id,
      p_details := jsonb_build_object(
        'notifies_elargis', v_notifies_mission,
        'rayon_km', 80,
        'filtre', 'fn_soignant_eligible_mission'
      )
    );
  END LOOP;
  RETURN jsonb_build_object(
    'success', true, 'escalades', v_escalades, 'notifies', v_notifies
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_email_recap_hebdo()
RETURNS TABLE(
  email text, prenom text, soignant_id uuid, missions_terminees bigint,
  heures_semaine numeric, gains_semaine numeric, score numeric,
  heures_totales numeric, missions_dispo bigint
)
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT s.email, s.prenom, s.id,
    count(m.id) FILTER (
      WHERE m.statut = 'TERMINEE' AND m.fin_le > now() - interval '7 days'
    ),
    COALESCE(sum(m.duree_heures) FILTER (
      WHERE m.statut = 'TERMINEE' AND m.fin_le > now() - interval '7 days'
    ), 0),
    COALESCE(sum(m.net_a_payer) FILTER (
      WHERE m.statut = 'TERMINEE' AND m.fin_le > now() - interval '7 days'
    ), 0),
    s.score_fiabilite, s.heures_cumulees,
    (SELECT count(*) FROM public.missions mo
      WHERE mo.statut = 'OUVERTE'
        AND public.fn_soignant_eligible_mission(s.id, mo.id, false))
  FROM public.soignants s
  LEFT JOIN public.missions m ON m.soignant_assigne_id = s.id
  WHERE s.supprime_le IS NULL AND s.email IS NOT NULL
    AND s.derniere_activite_le > now() - interval '30 days'
  GROUP BY s.id, s.email, s.prenom, s.score_fiabilite, s.heures_cumulees;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_soignants_inactifs_a_relancer(p_limit integer DEFAULT 150)
RETURNS TABLE(id uuid, prenom text, email text, profession text, nb_missions_ouvertes bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT s.id, s.prenom, s.email, s.profession::text,
    (SELECT count(*) FROM public.missions m
      WHERE m.statut = 'OUVERTE'
        AND public.fn_soignant_eligible_mission(s.id, m.id, false))
  FROM public.soignants s
  WHERE s.cree_le < now() - interval '3 days'
    AND s.email IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.candidatures c WHERE c.soignant_id = s.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.relances_soignants r
       WHERE r.soignant_id = s.id AND r.envoye_le > now() - interval '14 days'
    )
  ORDER BY s.cree_le DESC
  LIMIT greatest(COALESCE(p_limit, 150), 1);
$function$;

-- Recommandations établissement : même hiérarchie et même régime documentaire.
CREATE OR REPLACE FUNCTION "public"."fn_recommander_soignants"("p_mission_id" "uuid", "p_limit" integer DEFAULT 20) RETURNS TABLE("id" "uuid", "prenom" "text", "nom" "text", "profession" "public"."type_profession", "score_fiabilite" integer, "distance_km" numeric, "missions_etab" integer, "missions_etablissement" integer, "score_matching" numeric, "est_favori" boolean, "type_exercice" "text", "note_moyenne" numeric, "nb_evaluations" integer, "tous_documents_valides" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_mission RECORD;
    v_etab RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE missions.id = p_mission_id;
    IF v_mission IS NULL THEN RETURN; END IF;
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM v_mission.etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : mission non détenue par votre établissement' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_etab FROM etablissements WHERE etablissements.id = v_mission.etablissement_id;
    RETURN QUERY
    SELECT
        s.id, s.prenom, s.nom, s.profession,
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END,
        ROUND((CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
            )))
        ELSE 999 END)::NUMERIC, 1),
        (SELECT COUNT(*)::INTEGER FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = v_mission.etablissement_id AND m2.statut = 'TERMINEE'),
        (SELECT COUNT(*)::INTEGER FROM missions m2b WHERE m2b.soignant_assigne_id = s.id AND m2b.etablissement_id = v_mission.etablissement_id AND m2b.statut = 'TERMINEE') AS missions_etablissement,
        ROUND((COALESCE(s.score_fiabilite, 0) * 0.3
            + COALESCE(s.note_moyenne, 3) * 20 * 0.2
            + LEAST(100, (SELECT COUNT(*) FROM missions m3 WHERE m3.soignant_assigne_id = s.id AND m3.etablissement_id = v_mission.etablissement_id AND m3.statut = 'TERMINEE') * 10) * 0.2
            + CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
                GREATEST(0, 100 - (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                    COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                    COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                    SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
                )))))
              ELSE 0 END * 0.2
            + CASE WHEN EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id) THEN 20 ELSE 0 END
        )::NUMERIC, 1),
        EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id),
        COALESCE(s.type_exercice, 'SALARIE'),
        CASE WHEN COALESCE(s.nb_evaluations, 0) >= 3 THEN s.note_moyenne ELSE NULL END,
        COALESCE(s.nb_evaluations, 0),
        s.tous_documents_valides
    FROM soignants s
    WHERE public.fn_soignant_eligible_mission(s.id, p_mission_id, true)
      AND (s.adresse_lat IS NULL OR v_etab.adresse_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
              COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
              SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
          )))) <= COALESCE(s.rayon_deplacement_km, 50))
      AND s.id NOT IN (
          SELECT m4.soignant_assigne_id FROM missions m4
          WHERE m4.soignant_assigne_id IS NOT NULL AND m4.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m4.debut_le < v_mission.fin_le AND m4.fin_le > v_mission.debut_le
      )
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
    ORDER BY est_favori DESC, score_matching DESC
    LIMIT p_limit;
END;
$$;


-- Éligibilité commune aux feeds, pools et notifications. La compatibilité de
-- diplôme est distincte de la décision contractuelle. En particulier :
-- IADE × mission IDE = compatible, puis les règles IDE de la mission s'appliquent.
REVOKE ALL ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_soignant_eligible_mission(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_soignant_eligible_mission(uuid, uuid, boolean) TO service_role;

COMMENT ON FUNCTION public.fn_resoudre_contrat_mission(uuid, uuid, text) IS
  'Lot 21 D4 — résout le contrat depuis la profession requise par la mission et sa matrice, jamais depuis le diplôme du profil.';

-- API historique : conserver les codes pour compatibilité, mais ne plus
-- annoncer IADE ni PHARMACIEN comme libéraux. Les profils déjà valides ne sont
-- ni réécrits ni invalidés par cette migration.
CREATE OR REPLACE FUNCTION public.fn_professions_liberales()
RETURNS jsonb
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT '[
    {"code":"IDE","label":"Infirmier(ère) Diplômé(e) d''État","liberal":true},
    {"code":"IADE","label":"Infirmier(ère) Anesthésiste","liberal":false},
    {"code":"SAGE_FEMME","label":"Sage-Femme","liberal":true},
    {"code":"KINE","label":"Kinésithérapeute","liberal":true},
    {"code":"MEDECIN","label":"Médecin","liberal":true},
    {"code":"PHARMACIEN","label":"Pharmacien(ne)","liberal":false},
    {"code":"ORTHOPHONISTE","label":"Orthophoniste","liberal":true},
    {"code":"DIETETICIEN","label":"Diététicien(ne)","liberal":true},
    {"code":"ERGOTHERAPEUTE","label":"Ergothérapeute","liberal":true},
    {"code":"PSYCHOMOTRICIEN","label":"Psychomotricien(ne)","liberal":true},
    {"code":"AS","label":"Aide-Soignant(e)","liberal":false},
    {"code":"AES","label":"Accompagnant Éducatif et Social","liberal":false},
    {"code":"IBODE","label":"Infirmier(ère) de Bloc Opératoire","liberal":false},
    {"code":"MANIPULATEUR_RADIO","label":"Manipulateur Radio","liberal":false},
    {"code":"PREPARATEUR_PHARMA","label":"Préparateur en Pharmacie","liberal":false}
  ]'::jsonb;
$function$;

-- Les triggers historiques déduisaient le paiement depuis le PROFIL et
-- interdisaient donc « profil libéral × mission salariée ». Ils suivent
-- désormais le contrat appliqué à la mission.
CREATE OR REPLACE FUNCTION public.dec_definir_type_paiement()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_choix text;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL THEN
    v_choix := COALESCE(
      NEW.type_contrat_applique::text,
      NULLIF(upper(NEW.choix_contrat_soignant), ''),
      CASE WHEN NEW.type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
    );
    IF v_choix = 'LIBERAL' THEN
      NEW.type_paiement_soignant := 'NOTE_HONORAIRES';
      NEW.mode_paiement_soignant := 'STRIPE_CONNECT';
    ELSE
      NEW.type_paiement_soignant := 'BULLETIN_PAIE';
      NEW.mode_paiement_soignant := 'DIRECT';
    END IF;
    IF NEW.type_paiement_soignant = 'NOTE_HONORAIRES'
       AND NEW.statut = 'TERMINEE' AND NEW.numero_note_honoraires IS NULL THEN
      NEW.numero_note_honoraires := public.fn_generer_numero_note_honoraires();
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_verifier_type_contrat_mission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut = 'ASSIGNEE'
     AND OLD.statut = 'OUVERTE' THEN
    IF NEW.type_contrat_applique = 'SALARIE'
       AND NEW.type_paiement_soignant IS DISTINCT FROM 'BULLETIN_PAIE' THEN
      RAISE EXCEPTION 'Incohérence : une mission salariée doit produire un bulletin de paie.';
    ELSIF NEW.type_contrat_applique = 'LIBERAL'
       AND NEW.type_paiement_soignant IS DISTINCT FROM 'NOTE_HONORAIRES' THEN
      RAISE EXCEPTION 'Incohérence : une mission libérale doit produire une note d''honoraires.';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_verifier_eligibilite_liberal()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant record;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut = 'ASSIGNEE'
     AND OLD.statut = 'OUVERTE'
     AND NEW.type_contrat_applique = 'LIBERAL' THEN
    SELECT type_exercice, COALESCE(heures_cumulees, 0) AS heures_cumulees
      INTO v_soignant
      FROM public.soignants
     WHERE id = NEW.soignant_assigne_id;
    IF COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
      RAISE EXCEPTION 'Le profil doit être activé pour exercer en libéral.';
    END IF;
    IF v_soignant.heures_cumulees < 3200 THEN
      RAISE EXCEPTION 'Vous devez cumuler 3 200 heures d''exercice pour accepter une mission libérale. Vous avez actuellement % heures.',
        round(v_soignant.heures_cumulees);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_verifier_profession_etablissement()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type public.type_etablissement;
BEGIN
  SELECT type INTO v_type FROM public.etablissements WHERE id = NEW.etablissement_id;
  IF v_type = 'PHARMACIE_OFFICINE' THEN
    RAISE EXCEPTION 'Jolene ne propose pas le remplacement du titulaire d''une officine. Les missions pharmacien proposées par la plateforme sont des missions salariées d''établissement, notamment en PUI.';
  END IF;
  RETURN NEW;
END;
$function$;

-- Le recalcul financier historique passait le PROFIL à
-- fn_calculer_remuneration_mission : un profil libéral affecté à un CDD perdait
-- alors ses IFM/ICP à chaque UPDATE de la mission. Le régime financier suit
-- exclusivement le contrat de la mission, y compris lors de sa clôture.
CREATE OR REPLACE FUNCTION public.dec_calculer_finance_mission()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_taux_effectif numeric;
  v_calcul jsonb;
  v_c record;
  v_sum_prev numeric := 0;
  v_sum_eff numeric := 0;
  v_use_effectif boolean;
  v_est_liberal boolean;
  v_h_nuit numeric := 0;
  v_h_dim numeric := 0;
  v_h_fer numeric := 0;
  v_m_nuit numeric := 0;
  v_m_dim numeric := 0;
  v_m_fer numeric := 0;
  v_brut numeric := 0;
  v_ifm numeric := 0;
  v_icp numeric := 0;
  v_taux_ifm numeric := 0;
  v_taux_icp numeric := 0;
BEGIN
  v_est_liberal := COALESCE(
    NEW.type_contrat_applique::text,
    CASE WHEN NEW.type_contrat_recherche = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
  ) = 'LIBERAL';
  v_taux_effectif := COALESCE(NEW.taux_rist_plafonne, NEW.taux_horaire_base);

  SELECT COALESCE(sum(CASE WHEN NOT est_pause THEN extract(epoch FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
    INTO v_sum_prev
    FROM public.mission_creneaux
   WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND fin IS NOT NULL;
  SELECT COALESCE(sum(CASE WHEN NOT est_pause THEN extract(epoch FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
    INTO v_sum_eff
    FROM public.mission_creneaux
   WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;
  v_use_effectif := v_sum_eff > v_sum_prev;

  IF v_sum_prev > 0 OR v_sum_eff > 0 THEN
    FOR v_c IN
      SELECT debut, fin
        FROM public.mission_creneaux
       WHERE mission_id = NEW.id
         AND NOT est_pause
         AND fin IS NOT NULL
         AND type_creneau = CASE WHEN v_use_effectif THEN 'EFFECTIF' ELSE 'PREVISIONNEL' END
       ORDER BY debut
    LOOP
      -- NULL évite toute déduction depuis le profil ; le régime est appliqué
      -- ci-dessous depuis NEW.type_contrat_applique.
      v_calcul := public.fn_calculer_remuneration_mission(
        v_c.debut, v_c.fin, v_taux_effectif, NEW.etablissement_id, NULL
      );
      v_h_nuit := v_h_nuit + (v_calcul->>'heures_nuit')::numeric;
      v_h_dim := v_h_dim + (v_calcul->>'heures_dimanche')::numeric;
      v_h_fer := v_h_fer + (v_calcul->>'heures_ferie')::numeric;
      v_m_nuit := v_m_nuit + (v_calcul->>'montant_majoration_nuit')::numeric;
      v_m_dim := v_m_dim + (v_calcul->>'montant_majoration_dimanche')::numeric;
      v_m_fer := v_m_fer + (v_calcul->>'montant_majoration_ferie')::numeric;
      v_brut := v_brut + (v_calcul->>'total_brut')::numeric;
    END LOOP;
  ELSE
    v_calcul := public.fn_calculer_remuneration_mission(
      NEW.debut_le, NEW.fin_le, v_taux_effectif, NEW.etablissement_id, NULL
    );
    v_h_nuit := (v_calcul->>'heures_nuit')::numeric;
    v_h_dim := (v_calcul->>'heures_dimanche')::numeric;
    v_h_fer := (v_calcul->>'heures_ferie')::numeric;
    v_m_nuit := (v_calcul->>'montant_majoration_nuit')::numeric;
    v_m_dim := (v_calcul->>'montant_majoration_dimanche')::numeric;
    v_m_fer := (v_calcul->>'montant_majoration_ferie')::numeric;
    v_brut := (v_calcul->>'total_brut')::numeric;
  END IF;

  IF NOT v_est_liberal THEN
    v_taux_ifm := 0.10;
    v_taux_icp := 0.10;
    v_ifm := round(v_brut * v_taux_ifm, 2);
    v_icp := round((v_brut + v_ifm) * v_taux_icp, 2);
  END IF;

  NEW.heures_nuit := round(v_h_nuit, 2);
  NEW.heures_dimanche := round(v_h_dim, 2);
  NEW.heures_ferie := round(v_h_fer, 2);
  NEW.montant_majoration_nuit := round(v_m_nuit, 2);
  NEW.montant_majoration_dimanche := round(v_m_dim, 2);
  NEW.montant_majoration_ferie := round(v_m_fer, 2);
  NEW.total_brut := round(v_brut, 2);
  NEW.taux_ifm := v_taux_ifm;
  NEW.montant_ifm := v_ifm;
  NEW.taux_icp := v_taux_icp;
  NEW.montant_icp := v_icp;
  NEW.net_a_payer := round(v_brut + v_ifm + v_icp, 2);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_calculer_cotisations(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_brut numeric;
  v_type text;
  v_pmss constant numeric := 3864;
  v_csg_base numeric;
  v_csg_ded numeric;
  v_csg_non_ded numeric;
  v_crds numeric;
  v_ss_maladie numeric;
  v_ss_vieillesse_p numeric;
  v_ss_vieillesse_d numeric;
  v_retraite_t1 numeric;
  v_retraite_t2 numeric;
  v_chomage numeric;
  v_ceg numeric;
  v_ifm numeric;
  v_icp numeric;
  v_total_sal numeric;
  v_total_pat numeric;
  v_net numeric;
  v_pat_ss numeric;
  v_pat_af numeric;
  v_pat_at numeric;
  v_pat_ret numeric;
  v_pat_chom numeric;
  v_pat_fnal numeric;
  v_pat_form numeric;
  v_pat_transport numeric;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_mission.soignant_assigne_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun soignant assigné');
  END IF;

  -- Source unique : contrat appliqué à la mission. Le type_exercice du profil
  -- n'intervient jamais dans un calcul de paie ou d'honoraires.
  v_type := CASE
    WHEN COALESCE(
      v_mission.type_contrat_applique::text,
      CASE WHEN v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
    ) = 'LIBERAL' THEN 'REMPLACEMENT_LIBERAL'
    ELSE 'CDD'
  END;

  -- total_brut est le snapshot financier serveur déjà plafonné Rist et majoré.
  -- Le recalcul depuis taux_horaire_base ignorait taux_rist_plafonne.
  v_brut := COALESCE(
    v_mission.total_brut,
    COALESCE(v_mission.taux_rist_plafonne, v_mission.taux_horaire_base)
      * COALESCE(v_mission.duree_heures, 0)
      + COALESCE(v_mission.montant_majoration_nuit, 0)
      + COALESCE(v_mission.montant_majoration_dimanche, 0)
      + COALESCE(v_mission.montant_majoration_ferie, 0)
  );

  IF v_type = 'CDD' THEN
    v_ifm := COALESCE(v_mission.montant_ifm, round(v_brut * 0.10, 2));
    v_icp := COALESCE(v_mission.montant_icp, round((v_brut + v_ifm) * 0.10, 2));
  ELSE
    v_ifm := 0;
    v_icp := 0;
  END IF;

  v_brut := v_brut + v_ifm + v_icp;
  v_csg_base := round(v_brut * 0.9825, 2);

  IF v_type = 'REMPLACEMENT_LIBERAL' THEN
    v_csg_ded := 0; v_csg_non_ded := 0; v_crds := 0;
    v_ss_maladie := 0; v_ss_vieillesse_p := 0; v_ss_vieillesse_d := 0;
    v_retraite_t1 := 0; v_retraite_t2 := 0; v_chomage := 0; v_ceg := 0;
    v_total_sal := 0; v_pat_ss := 0; v_pat_af := 0; v_pat_at := 0;
    v_pat_ret := 0; v_pat_chom := 0; v_pat_fnal := 0; v_pat_form := 0;
    v_pat_transport := 0; v_total_pat := 0; v_net := v_brut;
  ELSE
    v_csg_ded := round(v_csg_base * 0.0680, 2);
    v_csg_non_ded := round(v_csg_base * 0.0240, 2);
    v_crds := round(v_csg_base * 0.0050, 2);
    v_ss_maladie := 0;
    v_ss_vieillesse_p := round(least(v_brut, v_pmss) * 0.0690, 2);
    v_ss_vieillesse_d := round(v_brut * 0.0040, 2);
    v_retraite_t1 := round(least(v_brut, v_pmss) * 0.0386, 2);
    v_retraite_t2 := round(greatest(0, v_brut - v_pmss) * 0.1021, 2);
    v_chomage := 0;
    v_ceg := round(least(v_brut, v_pmss) * 0.0086, 2);
    v_total_sal := v_csg_ded + v_csg_non_ded + v_crds + v_ss_maladie
      + v_ss_vieillesse_p + v_ss_vieillesse_d + v_retraite_t1
      + v_retraite_t2 + v_chomage + v_ceg;
    v_pat_ss := round(v_brut * 0.1305, 2);
    v_pat_af := round(v_brut * 0.0525, 2);
    v_pat_at := round(v_brut * 0.0100, 2);
    v_pat_ret := round(least(v_brut, v_pmss) * 0.0601, 2);
    v_pat_chom := round(v_brut * 0.0405, 2);
    v_pat_fnal := round(v_brut * 0.0050, 2);
    v_pat_form := round(v_brut * 0.0055, 2);
    v_pat_transport := round(v_brut * 0.0175, 2);
    v_total_pat := v_pat_ss + v_pat_af + v_pat_at + v_pat_ret
      + v_pat_chom + v_pat_fnal + v_pat_form + v_pat_transport;
    v_net := v_brut - v_total_sal;
  END IF;

  DELETE FROM public.cotisations_sociales WHERE mission_id = p_mission_id;
  INSERT INTO public.cotisations_sociales(
    mission_id, soignant_id, type_contrat, salaire_brut,
    csg_deductible, csg_non_deductible, crds,
    securite_sociale_maladie, securite_sociale_vieillesse_plafonnee,
    securite_sociale_vieillesse_deplafonnee,
    retraite_complementaire_t1, retraite_complementaire_t2,
    assurance_chomage, contribution_equilibre_general,
    patronal_securite_sociale, patronal_allocations_familiales,
    patronal_accident_travail, patronal_retraite_complementaire,
    patronal_chomage, patronal_fnal, patronal_formation, patronal_transport,
    total_cotisations_salariales, total_cotisations_patronales,
    net_avant_impot, cout_total_employeur, ifm, icp
  ) VALUES (
    p_mission_id, v_mission.soignant_assigne_id, v_type, v_brut,
    v_csg_ded, v_csg_non_ded, v_crds,
    v_ss_maladie, v_ss_vieillesse_p, v_ss_vieillesse_d,
    v_retraite_t1, v_retraite_t2, v_chomage, v_ceg,
    v_pat_ss, v_pat_af, v_pat_at, v_pat_ret,
    v_pat_chom, v_pat_fnal, v_pat_form, v_pat_transport,
    v_total_sal, v_total_pat, v_net, v_brut + v_total_pat, v_ifm, v_icp
  );

  RETURN jsonb_build_object(
    'success', true, 'type_contrat', v_type, 'brut', v_brut,
    'ifm', v_ifm, 'icp', v_icp,
    'cotisations_salariales', v_total_sal,
    'cotisations_patronales', v_total_pat,
    'net_avant_impot', v_net,
    'cout_total_employeur', v_brut + v_total_pat
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_creer_bulletin_paie(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_mission record;
  v_cot record;
  v_bulletin_id uuid;
  v_numero text;
  v_existing uuid;
  v_regime text;
BEGIN
  SELECT m.id, m.soignant_assigne_id, m.etablissement_id, m.statut,
         m.debut_le, m.fin_le, m.duree_heures, m.taux_horaire_base,
         m.type_contrat_applique, m.type_paiement_soignant
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable'); END IF;
  IF v_mission.soignant_assigne_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun soignant assigné');
  END IF;
  IF v_mission.statut <> 'TERMINEE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non terminée');
  END IF;

  v_regime := COALESCE(
    v_mission.type_contrat_applique::text,
    CASE WHEN v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  IF v_regime <> 'SALARIE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Bulletin de paie non applicable : cette mission est libérale.'
    );
  END IF;

  SELECT id INTO v_existing
    FROM public.bulletins_paie WHERE mission_id = p_mission_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'bulletin_id', v_existing, 'already_existed', true);
  END IF;

  SELECT * INTO v_cot
    FROM public.cotisations_sociales WHERE mission_id = p_mission_id;
  IF NOT FOUND OR v_cot.type_contrat <> 'CDD' THEN
    PERFORM public.fn_calculer_cotisations(p_mission_id);
    SELECT * INTO v_cot
      FROM public.cotisations_sociales WHERE mission_id = p_mission_id;
  END IF;
  IF v_cot IS NULL OR v_cot.type_contrat <> 'CDD' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Calcul des cotisations salariées échoué');
  END IF;

  v_numero := public.fn_next_bulletin_paie_number(v_mission.soignant_assigne_id);
  INSERT INTO public.bulletins_paie(
    numero_bulletin, soignant_id, mission_id, etablissement_id,
    periode_debut, periode_fin, salaire_brut,
    total_cotisations_salariales, total_cotisations_patronales,
    net_avant_impot, ifm, icp, statut, date_emission
  ) VALUES (
    v_numero, v_mission.soignant_assigne_id, p_mission_id, v_mission.etablissement_id,
    v_mission.debut_le::date, v_mission.fin_le::date, v_cot.salaire_brut,
    v_cot.total_cotisations_salariales, v_cot.total_cotisations_patronales,
    v_cot.net_avant_impot, COALESCE(v_cot.ifm, 0), COALESCE(v_cot.icp, 0),
    'EMIS', current_date
  ) RETURNING id INTO v_bulletin_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_mission.soignant_assigne_id,
    p_type_acteur := 'SOIGNANT',
    p_action := 'BULLETIN_PAIE_EMIS',
    p_type_ressource := 'bulletin_paie',
    p_id_ressource := v_bulletin_id,
    p_details := jsonb_build_object(
      'numero_bulletin', v_numero,
      'mission_id', p_mission_id,
      'profession_requise', (
        SELECT profession_requise::text FROM public.missions WHERE id = p_mission_id
      ),
      'salaire_brut', v_cot.salaire_brut,
      'net_avant_impot', v_cot.net_avant_impot
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'bulletin_id', v_bulletin_id,
    'numero_bulletin', v_numero,
    'salaire_brut', v_cot.salaire_brut,
    'net_avant_impot', v_cot.net_avant_impot
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_auto_calculer_cotisations()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.statut = 'TERMINEE'
     AND OLD.statut IS DISTINCT FROM 'TERMINEE'
     AND NEW.soignant_assigne_id IS NOT NULL
     AND COALESCE(
       NEW.type_contrat_applique::text,
       CASE WHEN NEW.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
     ) = 'SALARIE' THEN
    PERFORM public.fn_calculer_cotisations(NEW.id);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_auto_creer_bulletin_paie_trg()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.statut = 'TERMINEE'
     AND OLD.statut IS DISTINCT FROM 'TERMINEE'
     AND NEW.soignant_assigne_id IS NOT NULL
     AND COALESCE(
       NEW.type_contrat_applique::text,
       CASE WHEN NEW.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
     ) = 'SALARIE' THEN
    BEGIN
      PERFORM public.fn_creer_bulletin_paie(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_auto_creer_bulletin_paie_trg: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_auto_facture_honoraires()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mandat_signe boolean;
  v_existing_id uuid;
  v_regime text;
BEGIN
  IF NEW.statut <> 'TERMINEE' OR OLD.statut IS NOT DISTINCT FROM 'TERMINEE' THEN
    RETURN NEW;
  END IF;

  v_regime := COALESCE(
    NEW.type_contrat_applique::text,
    CASE WHEN NEW.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  IF v_regime <> 'LIBERAL' OR NEW.soignant_assigne_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.mode_remuneration = 'RETROCESSION' AND NEW.montant_honoraires_bruts IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(mandat_facturation_signe, false)
    INTO v_mandat_signe
    FROM public.soignants
   WHERE id = NEW.soignant_assigne_id;
  IF NOT COALESCE(v_mandat_signe, false) THEN RETURN NEW; END IF;

  SELECT id INTO v_existing_id
    FROM public.factures_honoraires WHERE mission_id = NEW.id LIMIT 1;
  IF v_existing_id IS NULL THEN
    PERFORM public.fn_generer_facture_honoraires_mission(NEW.id);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_mode_paiement_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_connect_actif boolean;
  v_rib_partage boolean;
  v_regime text;
BEGIN
  SELECT m.*, s.type_exercice AS profil_type_exercice,
         s.iban_last4 AS soignant_iban_last4
    INTO v_mission
    FROM public.missions m
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;

  IF v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
     AND v_mission.soignant_assigne_id IS DISTINCT FROM auth.uid()
     AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_regime := COALESCE(
    v_mission.type_contrat_applique::text,
    CASE WHEN v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  v_connect_actif := v_regime = 'LIBERAL'
    AND public.fn_soignant_stripe_connect_actif(v_mission.soignant_assigne_id);
  v_rib_partage := EXISTS (
    SELECT 1 FROM public.partages_rib
     WHERE mission_id = p_mission_id
       AND actif
       AND (expire_le IS NULL OR expire_le > now())
  );

  RETURN jsonb_build_object(
    'mode_recommande', CASE
      WHEN v_regime = 'LIBERAL' AND v_connect_actif THEN 'STRIPE_CONNECT'
      WHEN v_regime = 'LIBERAL' THEN 'VIREMENT_NOTE_HONORAIRES'
      ELSE 'VIREMENT_PAIE'
    END,
    'type_contrat_applique', v_regime,
    'type_exercice', v_mission.profil_type_exercice,
    'stripe_connect_actif', v_connect_actif,
    'rib_partage', v_rib_partage,
    'iban_last4', v_mission.soignant_iban_last4,
    'montant_soignant', v_mission.net_a_payer,
    'total_brut', v_mission.total_brut,
    'net_estime', v_mission.net_estime,
    'commission_ht', v_mission.montant_commission_ht,
    'commission_ttc', v_mission.montant_commission_ttc,
    'total', COALESCE(v_mission.net_a_payer, 0) + COALESCE(v_mission.montant_commission_ttc, 0)
  );
END;
$function$;

-- Défense en profondeur : même un appel manuel à l'ancien générateur ne peut
-- créer une facture d'honoraires pour une mission salariée.
CREATE OR REPLACE FUNCTION public.dec_facture_honoraires_regime_mission()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_regime text;
BEGIN
  IF NEW.mission_id IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(
           m.type_contrat_applique::text,
           CASE WHEN m.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
         )
    INTO v_regime
    FROM public.missions m
   WHERE m.id = NEW.mission_id;
  IF v_regime IS DISTINCT FROM 'LIBERAL' THEN
    RAISE EXCEPTION 'Une facture d''honoraires ne peut être créée que pour une mission libérale.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_facture_honoraires_regime_mission ON public.factures_honoraires;
CREATE TRIGGER trg_facture_honoraires_regime_mission
BEFORE INSERT OR UPDATE OF mission_id ON public.factures_honoraires
FOR EACH ROW EXECUTE FUNCTION public.dec_facture_honoraires_regime_mission();

REVOKE ALL ON FUNCTION public.dec_facture_honoraires_regime_mission()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_facture_honoraires_regime_mission()
  TO service_role;

-- Le garde-fou historique inspectait tous les documents critiques du profil,
-- sans tenir compte du régime de la mission. Une RCP libérale expirée pouvait
-- donc bloquer un CDD parfaitement conforme. On ne contrôle ici que les
-- documents critiques applicables au contrat effectivement attribué.
CREATE OR REPLACE FUNCTION public.dec_verifier_docs_jusqua_fin()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_doc_expire record;
  v_regime text;
BEGIN
  IF NEW.statut = 'ASSIGNEE'
     AND OLD.statut = 'OUVERTE'
     AND NEW.soignant_assigne_id IS NOT NULL THEN
    v_regime := COALESCE(NEW.type_contrat_applique::text, 'SALARIE');

    SELECT ds.type_document, ds.valide_jusqua
      INTO v_doc_expire
      FROM public.documents_soignants ds
      JOIN public.documents_requis_par_profession drp
        ON drp.profession = (
          SELECT s.profession FROM public.soignants s
          WHERE s.id = NEW.soignant_assigne_id
        )
       AND drp.type_document = ds.type_document
       AND COALESCE(drp.est_critique, true)
       AND (
         drp.type_exercice_requis = 'TOUS'
         OR (v_regime = 'LIBERAL' AND drp.type_exercice_requis = 'LIBERAL_ONLY')
         OR (v_regime = 'SALARIE' AND drp.type_exercice_requis = 'SALARIE_ONLY')
       )
     WHERE ds.soignant_id = NEW.soignant_assigne_id
       AND ds.supprime_le IS NULL
       AND ds.valide_jusqua IS NOT NULL
       AND ds.valide_jusqua < NEW.fin_le::date
     LIMIT 1;

    IF v_doc_expire.type_document IS NOT NULL THEN
      RAISE EXCEPTION 'Votre document "%" expire le % — avant la fin de cette mission (%). Veuillez le renouveler.',
        v_doc_expire.type_document,
        to_char(v_doc_expire.valide_jusqua, 'DD/MM/YYYY'),
        to_char(NEW.fin_le, 'DD/MM/YYYY');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Les mutations directes de missions restent protégées. L'unique exception
-- est l'affectation atomique marquée par fn_finaliser_attribution_mission,
-- inaccessible aux rôles applicatifs. Sans cette marque, l'ancien trigger
-- remettait soignant_assigne_id à NULL lors d'une acceptation par le soignant.
CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('jolene.assignment_rpc_soignant_id', true) = COALESCE(NEW.soignant_assigne_id::text, '')
     AND OLD.statut = 'OUVERTE'
     AND NEW.statut = 'ASSIGNEE'
     AND OLD.soignant_assigne_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
    NEW.soignant_assigne_id := OLD.soignant_assigne_id;
    NEW.taux_horaire_base := OLD.taux_horaire_base;
    NEW.total_brut := OLD.total_brut;
    NEW.net_a_payer := OLD.net_a_payer;
    NEW.net_estime := OLD.net_estime;
    NEW.montant_ifm := OLD.montant_ifm;
    NEW.montant_icp := OLD.montant_icp;
    NEW.taux_ifm := OLD.taux_ifm;
    NEW.taux_icp := OLD.taux_icp;
    NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
    NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
    NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
    NEW.heures_nuit := OLD.heures_nuit;
    NEW.heures_dimanche := OLD.heures_dimanche;
    NEW.heures_ferie := OLD.heures_ferie;
    NEW.taux_commission := OLD.taux_commission;
    NEW.montant_commission_ht := OLD.montant_commission_ht;
    NEW.montant_commission_tva := OLD.montant_commission_tva;
    NEW.montant_commission_ttc := OLD.montant_commission_ttc;
    NEW.taux_rist_plafonne := OLD.taux_rist_plafonne;
    NEW.rist_plafond_applique := OLD.rist_plafond_applique;
    NEW.commission_facturee := OLD.commission_facturee;
    NEW.etablissement_id := OLD.etablissement_id;
    NEW.intitule := OLD.intitule;
    NEW.description := OLD.description;
    NEW.profession_requise := OLD.profession_requise;
    NEW.service := OLD.service;
    NEW.est_urgente := OLD.est_urgente;
    NEW.niveau_urgence := OLD.niveau_urgence;
    NEW.mode_attribution := OLD.mode_attribution;
    NEW.type_contrat_recherche := OLD.type_contrat_recherche;
    NEW.statut := OLD.statut;
    NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
    NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
    NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
    NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
    NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
    NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
    NEW.taux_commission_fige := OLD.taux_commission_fige;
    NEW.fige_le := OLD.fige_le;
    RETURN NEW;
  END IF;

  IF NOT public.est_admin() AND NOT public.est_admin_etablissement() THEN
    NEW.soignant_assigne_id := OLD.soignant_assigne_id;
    NEW.taux_horaire_base := OLD.taux_horaire_base;
    NEW.total_brut := OLD.total_brut;
    NEW.net_a_payer := OLD.net_a_payer;
    NEW.montant_ifm := OLD.montant_ifm;
    NEW.montant_icp := OLD.montant_icp;
    NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
    NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
    NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
    NEW.taux_commission := OLD.taux_commission;
    NEW.montant_commission_ht := OLD.montant_commission_ht;
    NEW.montant_commission_tva := OLD.montant_commission_tva;
    NEW.montant_commission_ttc := OLD.montant_commission_ttc;
    NEW.duree_heures := OLD.duree_heures;
    NEW.heures_nuit := OLD.heures_nuit;
    NEW.heures_dimanche := OLD.heures_dimanche;
    NEW.heures_ferie := OLD.heures_ferie;
    NEW.etablissement_id := OLD.etablissement_id;
    NEW.intitule := OLD.intitule;
    NEW.description := OLD.description;
    NEW.profession_requise := OLD.profession_requise;
    NEW.service := OLD.service;
    NEW.debut_le := OLD.debut_le;
    NEW.fin_le := OLD.fin_le;
    NEW.est_urgente := OLD.est_urgente;
    NEW.niveau_urgence := OLD.niveau_urgence;
    NEW.net_estime := OLD.net_estime;
    NEW.mode_attribution := OLD.mode_attribution;
    NEW.type_contrat_recherche := OLD.type_contrat_recherche;
    NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
    NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
    NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
    NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
    NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
    NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
    NEW.taux_commission_fige := OLD.taux_commission_fige;
    NEW.fige_le := OLD.fige_le;
  END IF;
  RETURN NEW;
END;
$function$;

-- Le soignant ne peut pas modifier librement sa candidature. Le seul passage
-- PROPOSEE → réponse est autorisé pendant fn_repondre_proposition, avec un
-- marqueur local lié à la mission ; il permet aussi de refuser atomiquement
-- les candidatures concurrentes après attribution.
CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;

  IF current_setting('jolene.candidature_rpc_mission_id', true) = OLD.mission_id::text THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF OLD.statut = 'PROPOSEE'
       AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE') THEN
      NEW.message := OLD.message;
      RETURN NEW;
    END IF;
    IF OLD.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE')
       AND NEW.statut = 'REFUSEE' THEN
      NEW.message := OLD.message;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
  END IF;

  IF auth.uid() = OLD.soignant_id THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF NEW.statut IS DISTINCT FROM OLD.statut THEN
      IF OLD.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB')
         AND NEW.statut = 'ANNULEE' THEN
        RETURN NEW;
      ELSIF OLD.statut = 'ACCEPTEE'
            AND NEW.statut = 'ANNULEE'
            AND COALESCE(current_setting('jolene.annulation_soignant_ctx', true), '') = 'true' THEN
        RETURN NEW;
      ELSE
        RAISE EXCEPTION 'Vous ne pouvez pas modifier le statut de votre candidature (% → %)',
          OLD.statut, NEW.statut;
      END IF;
    END IF;
    IF NEW.message IS DISTINCT FROM OLD.message AND OLD.statut <> 'EN_ATTENTE' THEN
      RAISE EXCEPTION 'Vous ne pouvez plus modifier votre message';
    END IF;
    NEW.motif_refus := OLD.motif_refus;
    NEW.traite_le := OLD.traite_le;
    RETURN NEW;
  END IF;

  IF public.mon_etablissement_id() IS NOT NULL THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF NEW.statut IS DISTINCT FROM OLD.statut
       AND NOT (
         (OLD.statut = 'EN_ATTENTE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
         OR (OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
         OR (OLD.statut = 'PROPOSEE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
       ) THEN
      RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Accès refusé à cette candidature';
END;
$function$;


-- Attribution atomique commune aux trois portes d'entrée : premier arrivé,
-- décision sur candidature et affectation manuelle. Les wrappers gardent la
-- responsabilité de l'autorisation ; cette fonction garde une mécanique unique.
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
  v_heures_semaine numeric;
  v_debut_semaine timestamptz;
  v_fin_semaine timestamptz;
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

  IF v_choix = 'SALARIE' THEN
    v_debut_semaine := date_trunc('week', v_mission.debut_le);
    v_fin_semaine := v_debut_semaine + interval '7 days';
    SELECT COALESCE(sum(duree_heures), 0)
      INTO v_heures_semaine
      FROM public.missions
     WHERE soignant_assigne_id = p_soignant_id
       AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
       AND debut_le >= v_debut_semaine AND debut_le < v_fin_semaine
       AND COALESCE(
         type_contrat_applique::text,
         NULLIF(upper(choix_contrat_soignant), ''),
         CASE WHEN type_contrat_recherche::text = 'LIBERAL' THEN 'LIBERAL' ELSE 'SALARIE' END
       ) = 'SALARIE';
    IF v_heures_semaine + COALESCE(v_mission.duree_heures, 0) > 48 THEN
      RETURN jsonb_build_object(
        'error', 'Dépassement du plafond de 48 h par semaine (' ||
          round(v_heures_semaine, 1) || ' h déjà planifiées).'
      );
    END IF;
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
    -- La profession affichée dans le contrat est celle REQUISE par la mission.
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

CREATE OR REPLACE FUNCTION public.fn_accepter_mission(
  p_mission_id uuid,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT statut, mode_attribution INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
  IF v_mission.mode_attribution <> 'PREMIER_ARRIVE' THEN
    RETURN jsonb_build_object('error', 'Cette mission nécessite une candidature');
  END IF;

  v_result := public.fn_finaliser_attribution_mission(p_mission_id, auth.uid(), p_choix_contrat);
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_etablissement_id uuid;
BEGIN
  IF NOT (public.est_admin() OR public.est_admin_etablissement()) THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  SELECT etablissement_id INTO v_etablissement_id
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT public.est_admin()
     AND v_etablissement_id IS DISTINCT FROM public.mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Cette mission n''appartient pas à votre établissement');
  END IF;

  RETURN public.fn_finaliser_attribution_mission(p_mission_id, p_soignant_id, p_choix_contrat);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_postuler_mission(
  p_mission_id uuid,
  p_message text DEFAULT NULL,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
  v_docs_ok boolean;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
  IF v_mission.mode_attribution <> 'CANDIDATURE' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures');
  END IF;

  SELECT * INTO v_soignant FROM public.soignants
   WHERE id = auth.uid() AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;
  IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
    RETURN jsonb_build_object('error', 'Votre compte ne permet pas de candidater. Contactez bonjour@jolene.app.');
  END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Votre profession ne correspond pas à la mission requise (' ||
        v_mission.profession_requise::text || ').'
    );
  END IF;
  IF public.fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Accès refusé.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, auth.uid(), p_choix_contrat);
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';

  IF EXISTS (
    SELECT 1 FROM public.candidatures
     WHERE mission_id = p_mission_id AND soignant_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission');
  END IF;

  -- La candidature salariée reste ouverte même si les documents SALARIE_ONLY
  -- doivent être complétés ; l'attribution, elle, reste bloquée jusqu'à validation.
  v_docs_ok := public.fn_documents_ok_pour_mission(auth.uid(), v_choix);
  IF v_choix = 'LIBERAL' AND NOT v_docs_ok THEN
    RETURN jsonb_build_object(
      'error', 'Les documents requis pour candidater en libéral sont manquants ou expirés.',
      'documents_requis_pour', 'LIBERAL',
      'lien_documents', '/soignant/mes-documents'
    );
  END IF;

  INSERT INTO public.candidatures(
    mission_id, soignant_id, message, statut, type_contrat_choisi
  ) VALUES (
    p_mission_id, auth.uid(), public.fn_html_escape(p_message), 'EN_ATTENTE', v_choix
  ) RETURNING id INTO v_candidature_id;

  INSERT INTO public.notifications(destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
    '📋 Nouvelle candidature reçue',
    COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' ||
      public.fn_html_escape(v_mission.intitule) || ' ».',
    '/etablissement/missions/' || p_mission_id
  );

  IF NOT v_docs_ok THEN
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    SELECT auth.uid(), 'RAPPEL_DOCUMENTS', 'Complétez vos documents salariés',
      'Votre candidature est envoyée. Les documents requis pour le CDD doivent être validés avant que l''établissement puisse vous accepter.',
      '/soignant/mes-documents', 'SOIGNANT'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notifications
       WHERE destinataire_id = auth.uid()
         AND type = 'RAPPEL_DOCUMENTS'
         AND cree_le > now() - interval '24 hours'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', NOT v_docs_ok,
    'documents_requis_pour', v_choix
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_traiter_candidature(
  p_candidature_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_candidature record;
  v_mission record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_candidature FROM public.candidatures WHERE id = p_candidature_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Candidature introuvable'); END IF;
  SELECT * INTO v_mission FROM public.missions WHERE id = v_candidature.mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
     AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_candidature.statut::text NOT IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB') THEN
    RETURN jsonb_build_object('error', 'Cette candidature a déjà été traitée.');
  END IF;

  IF p_decision = 'REFUSEE' THEN
    UPDATE public.candidatures
       SET statut = 'REFUSEE', motif_refus = p_motif, traite_le = now()
     WHERE id = p_candidature_id;
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (
      v_candidature.soignant_id, 'CANDIDATURE_REFUSEE', 'Candidature non retenue',
      'Votre candidature pour « ' || public.fn_html_escape(v_mission.intitule) || ' » n''a pas été retenue.' ||
        CASE WHEN p_motif IS NOT NULL THEN ' Motif : ' || public.fn_html_escape(p_motif) ELSE '' END,
      '/soignant/missions', 'SOIGNANT'
    );
    RETURN jsonb_build_object('success', true);
  ELSIF p_decision <> 'ACCEPTEE' THEN
    RETURN jsonb_build_object('error', 'Décision invalide');
  END IF;

  v_result := public.fn_finaliser_attribution_mission(
    v_candidature.mission_id,
    v_candidature.soignant_id,
    v_candidature.type_contrat_choisi
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    IF v_result->>'documents_requis_pour' IS NOT NULL THEN
      INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
      SELECT v_candidature.soignant_id, 'RAPPEL_DOCUMENTS',
        'Un établissement veut accepter votre candidature',
        'Complétez les documents requis pour la mission ' || lower(v_result->>'documents_requis_pour') ||
          ' afin de finaliser votre contrat.',
        '/soignant/mes-documents', 'SOIGNANT'
      WHERE NOT EXISTS (
        SELECT 1 FROM public.notifications
         WHERE destinataire_id = v_candidature.soignant_id
           AND type = 'RAPPEL_DOCUMENTS'
           AND cree_le > now() - interval '6 hours'
      );
    END IF;
    RETURN v_result;
  END IF;

  UPDATE public.candidatures SET statut = 'ACCEPTEE', traite_le = now()
   WHERE id = p_candidature_id;
  UPDATE public.candidatures
     SET statut = 'REFUSEE', motif_refus = 'Un autre candidat a été sélectionné', traite_le = now()
   WHERE mission_id = v_candidature.mission_id
     AND id <> p_candidature_id
     AND statut::text IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB');

  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    v_candidature.soignant_id, 'CANDIDATURE_ACCEPTEE', 'Candidature acceptée',
    'Votre candidature pour « ' || public.fn_html_escape(v_mission.intitule) ||
      ' » a été acceptée. Signez votre contrat.',
    '/soignant/missions', 'SOIGNANT'
  );

  IF v_result->>'choix_applique' = 'LIBERAL'
     AND NOT COALESCE((SELECT mandat_facturation_signe FROM public.soignants WHERE id = v_candidature.soignant_id), false) THEN
    INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (
      v_candidature.soignant_id, 'CONTRAT_A_SIGNER', '✍️ Signez votre mandat de facturation',
      'Votre mission « ' || public.fn_html_escape(v_mission.intitule) ||
        ' » est confirmée en libéral. Signez le mandat avant son démarrage.',
      '/soignant/mandat-facturation', 'SOIGNANT'
    );
  END IF;

  RETURN v_result;
END;
$function$;

-- Proposition directe établissement → soignant : mêmes compatibilité,
-- matrice et documents que les autres portes d'entrée.
CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(
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
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT public.est_admin()
     AND v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'La mission n’est plus ouverte');
  END IF;

  SELECT * INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant n’est pas compatible avec la profession requise par la mission (' ||
        v_mission.profession_requise::text || ').'
    );
  END IF;
  IF public.fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d’exclusions.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id, p_soignant_id, p_choix_contrat
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';
  IF NOT public.fn_documents_ok_pour_mission(p_soignant_id, v_choix) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant n’a pas encore les documents validés pour une mission ' || lower(v_choix) || '.',
      'documents_requis_pour', v_choix
    );
  END IF;

  -- La carte affiche une fenêtre de réponse de 2 h : la même règle est
  -- appliquée en base avant de rechercher un doublon actif.
  UPDATE public.candidatures
     SET statut = 'EXPIREE', traite_le = now()
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
     AND statut = 'PROPOSEE'
     AND cree_le < now() - interval '2 hours';

  IF EXISTS (
    SELECT 1 FROM public.candidatures
     WHERE mission_id = p_mission_id
       AND soignant_id = p_soignant_id
       AND statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE', 'ACCEPTEE')
  ) THEN
    RETURN jsonb_build_object('error', 'Cette mission a déjà été proposée à ce soignant.');
  END IF;

  INSERT INTO public.candidatures(
    mission_id, soignant_id, statut, type_contrat_choisi
  ) VALUES (
    p_mission_id, p_soignant_id, 'PROPOSEE', v_choix
  ) RETURNING id INTO v_candidature_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := CASE WHEN public.est_admin() THEN 'ADMIN' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'MISSION_PROPOSEE_SOIGNANT',
    p_type_ressource := 'candidature',
    p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object(
      'mission_id', p_mission_id,
      'soignant_id', p_soignant_id,
      'profession_requise', v_mission.profession_requise::text,
      'type_contrat_choisi', v_choix
    )
  );

  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Mission proposée',
    'Un établissement vous propose la mission « ' || public.fn_html_escape(v_mission.intitule) ||
      ' » en ' || lower(v_choix) || '.',
    '/soignant/missions/' || p_mission_id, 'SOIGNANT'
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_persiste', v_choix,
    'profession_requise', v_mission.profession_requise::text
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_repondre_proposition(
  p_candidature_id uuid,
  p_accepter boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_candidature record;
  v_result jsonb;
BEGIN
  SELECT c.* INTO v_candidature
    FROM public.candidatures c
   WHERE c.id = p_candidature_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Candidature introuvable'); END IF;
  IF v_candidature.soignant_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_candidature.statut <> 'PROPOSEE' THEN
    RETURN jsonb_build_object('error', 'Cette proposition n’est plus en attente');
  END IF;

  PERFORM set_config(
    'jolene.candidature_rpc_mission_id',
    v_candidature.mission_id::text,
    true
  );
  IF v_candidature.cree_le < now() - interval '2 hours' THEN
    UPDATE public.candidatures
       SET statut = 'EXPIREE', traite_le = now()
     WHERE id = p_candidature_id;
    RETURN jsonb_build_object('error', 'Cette proposition a expiré');
  END IF;

  IF NOT p_accepter THEN
    UPDATE public.candidatures
       SET statut = 'REFUSEE', traite_le = now()
     WHERE id = p_candidature_id;
    RETURN jsonb_build_object('success', true, 'message', 'Proposition refusée');
  END IF;

  v_result := public.fn_finaliser_attribution_mission(
    v_candidature.mission_id,
    v_candidature.soignant_id,
    v_candidature.type_contrat_choisi
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_result;
  END IF;

  UPDATE public.candidatures
     SET statut = 'ACCEPTEE', traite_le = now()
   WHERE id = p_candidature_id;
  UPDATE public.candidatures
     SET statut = 'REFUSEE', motif_refus = 'Mission attribuée', traite_le = now()
   WHERE mission_id = v_candidature.mission_id
     AND id <> p_candidature_id
     AND statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');

  RETURN v_result || jsonb_build_object('message', 'Proposition acceptée');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_accepter_mission_urgence(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_candidature_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable'); END IF;
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' OR NOT COALESCE(v_mission.est_urgente, false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission urgente non disponible');
  END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profession ou spécialité incompatible');
  END IF;
  IF public.fn_est_exclu(v_uid, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, v_uid, NULL);
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false) || (v_resolution - 'ok');
  END IF;
  IF NOT public.fn_documents_ok_pour_mission(v_uid, v_resolution->>'contrat') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Vos documents ne sont pas validés pour cette mission ' || lower(v_resolution->>'contrat'),
      'documents_requis_pour', v_resolution->>'contrat'
    );
  END IF;
  IF EXISTS (SELECT 1 FROM public.candidatures WHERE mission_id = p_mission_id AND soignant_id = v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà candidaté à cette mission');
  END IF;

  INSERT INTO public.candidatures(
    mission_id, soignant_id, statut, message, type_contrat_choisi, cree_le
  ) VALUES (
    p_mission_id, v_uid, 'EN_ATTENTE_VALIDATION_ETAB',
    'Acceptation rapide via pool urgence', v_resolution->>'contrat', now()
  ) RETURNING id INTO v_candidature_id;

  INSERT INTO public.notifications(destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'POOL_URGENCE_ACCEPTATION',
    '🚨 Acceptation rapide du pool urgence',
    COALESCE(v_soignant.prenom, 'Un soignant') || ' (' || v_soignant.profession::text ||
      ') a accepté votre mission urgente. Validez ou refusez sous 1 h.',
    '/etablissement/missions/' || p_mission_id, 'candidature', v_candidature_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_resolution->>'contrat',
    'profession_requise', v_mission.profession_requise::text,
    'message', 'Acceptation enregistrée. En attente de validation par l''établissement.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(
  p_mission_id uuid,
  p_direction text,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_direction public.swipe_direction;
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_swipe_id uuid;
  v_candidature_id uuid;
  v_planning jsonb;
  v_warning text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF p_direction = 'SUPER_LIKE' THEN p_direction := 'FAVORI'; END IF;
  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'FAVORI') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;
  v_direction := p_direction::public.swipe_direction;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND OR v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_indisponible');
  END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'profil_introuvable'); END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profession_incompatible');
  END IF;
  IF public.fn_est_exclu(v_uid, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'acces_refuse');
  END IF;

  IF v_direction = 'LIKE' THEN
    IF EXISTS (SELECT 1 FROM public.candidatures WHERE mission_id = p_mission_id AND soignant_id = v_uid) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Vous avez déjà candidaté à cette mission');
    END IF;
    v_planning := public.fn_conflit_planning_soignant(v_uid, p_mission_id);
    IF COALESCE((v_planning->>'conflit')::boolean, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', v_planning->>'message', 'conflit_planning', true);
    END IF;
    v_warning := v_planning->>'warning';

    v_resolution := public.fn_resoudre_contrat_mission(p_mission_id, v_uid, p_choix_contrat);
    IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
      RETURN jsonb_build_object('ok', false) || (v_resolution - 'ok');
    END IF;
    v_choix := v_resolution->>'contrat';
    IF v_choix = 'LIBERAL' AND NOT public.fn_documents_ok_pour_mission(v_uid, 'LIBERAL') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Les documents requis pour candidater en libéral sont manquants ou expirés.',
        'documents_requis_pour', 'LIBERAL'
      );
    END IF;
  END IF;

  INSERT INTO public.swipes(soignant_id, mission_id, direction)
  VALUES (v_uid, p_mission_id, v_direction)
  ON CONFLICT (soignant_id, mission_id) DO NOTHING
  RETURNING id INTO v_swipe_id;
  IF v_swipe_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  IF v_direction = 'FAVORI' THEN
    INSERT INTO public.missions_sauvegardees(soignant_id, mission_id)
    VALUES (v_uid, p_mission_id)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING;
    RETURN jsonb_build_object('ok', true, 'swipe_id', v_swipe_id, 'direction', 'FAVORI', 'sauvegardee', true);
  ELSIF v_direction = 'LIKE' THEN
    INSERT INTO public.candidatures(mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, v_uid, NULL, 'EN_ATTENTE', v_choix)
    RETURNING id INTO v_candidature_id;
    INSERT INTO public.notifications(destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (
      v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
      '📋 Nouvelle candidature reçue',
      COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' ||
        public.fn_html_escape(v_mission.intitule) || ' ».',
      '/etablissement/missions/' || p_mission_id
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'swipe_id', v_swipe_id, 'direction', p_direction,
    'candidature_id', v_candidature_id, 'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', v_direction = 'LIKE' AND NOT public.fn_documents_ok_pour_mission(v_uid, v_choix),
    'warning', v_warning
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant public.soignants%ROWTYPE;
  v_missions jsonb;
  v_flag_pr boolean := (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid;

  SELECT COALESCE(jsonb_agg(payload ORDER BY tri DESC), '[]'::jsonb)
    INTO v_missions
    FROM (
      SELECT (COALESCE(ms.score_global, 0) + floor(random() * 13))::int AS tri,
        jsonb_build_object(
          'mission_id', m.id,
          'intitule', m.intitule,
          'profession_requise', m.profession_requise,
          'etablissement_id', m.etablissement_id,
          'etablissement_nom', e.nom,
          'etablissement_ville', e.adresse_ville,
          'etablissement_code_postal', e.adresse_code_postal,
          'etablissement_logo_url', e.logo_url,
          'etablissement_score', e.score_qualite,
          'taux_horaire_base', m.taux_horaire_base,
          'duree_heures', m.duree_heures,
          'debut_le', m.debut_le,
          'fin_le', m.fin_le,
          'est_urgente', m.est_urgente,
          'service', m.service,
          'type_contrat_applique', m.type_contrat_applique,
          'type_contrat_recherche', m.type_contrat_recherche,
          'nb_creneaux', m.nb_creneaux,
          'total_brut', m.total_brut,
          'net_a_payer', m.net_a_payer,
          'net_estime', m.net_estime,
          'montant_ifm', COALESCE(m.montant_ifm, 0),
          'montant_icp', COALESCE(m.montant_icp, 0),
          'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
          'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
          'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
          'score', COALESCE(ms.score_global, 0),
          'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),
          'paiement_rapide', (
            v_flag_pr AND m.type_contrat_recherche = 'LIBERAL'
            AND e.mode_paiement_commission = 'SEPA_DEBIT'
            AND e.stripe_sepa_payment_method_id IS NOT NULL
            AND public.fn_escrow_etab_eligible(m.etablissement_id)
          ),
          'distance_km', CASE
            WHEN v_soignant.adresse_lat IS NOT NULL AND v_soignant.adresse_lng IS NOT NULL
             AND e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
            THEN round((public.fn_haversine_distance_m(
              v_soignant.adresse_lat, v_soignant.adresse_lng,
              e.adresse_lat, e.adresse_lng
            ) / 1000.0)::numeric, 1)
            ELSE NULL
          END
        ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_uid
      WHERE m.statut = 'OUVERTE'
        AND m.debut_le > now()
        AND (COALESCE(e.est_compte_test, false) = false OR COALESCE(v_soignant.est_compte_test, false))
        AND (m.intitule NOT LIKE '[%' OR v_soignant.email LIKE 'playwright-%')
        AND public.fn_soignant_eligible_mission(v_uid, m.id, false)
        AND (v_soignant.taux_horaire_minimum IS NULL OR m.taux_horaire_base IS NULL
             OR m.taux_horaire_base >= v_soignant.taux_horaire_minimum)
        AND NOT EXISTS (
          SELECT 1 FROM public.swipes sw WHERE sw.soignant_id = v_uid AND sw.mission_id = m.id
        )
      ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100))
    ) q;

  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

-- Dashboard : mêmes missions que le feed et mêmes montants serveur. La durée
-- contractuelle (duree_heures) remplace toute différence calendaire début/fin.
CREATE OR REPLACE FUNCTION public.fn_dashboard_soignant_complet()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_lundi date := date_trunc('week', now())::date;
  v_dimanche date := date_trunc('week', now())::date + 7;
  v_debut_mois date := date_trunc('month', now())::date;
  v_fin_mois date := (date_trunc('month', now()) + interval '1 month' - interval '1 second')::date;
  v_six_mois_ago date := date_trunc('month', now() - interval '5 months')::date;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT jsonb_build_object(
    'profil', (
      SELECT row_to_json(s)::jsonb FROM (
        SELECT prenom, nom, telephone, date_naissance, profession, type_contrat,
          numero_rpps, numero_adeli, rpps_verifie, adresse_lat, adresse_lng,
          tous_documents_valides, identite_verifiee, score_fiabilite,
          total_missions_terminees, heures_cumulees, eligible_conversion_3200h,
          type_exercice, mandat_facturation_signe
        FROM public.soignants WHERE id = v_uid
      ) s
    ),
    'missions_ouvertes', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb)
      FROM (
        SELECT m.id, m.intitule, m.service, m.debut_le, m.fin_le,
          m.duree_heures, m.nb_creneaux, m.taux_horaire_base,
          m.total_brut, m.net_a_payer, m.net_estime,
          m.est_urgente, m.etablissement_id, m.profession_requise,
          m.type_contrat_recherche, m.accepte_non_specialises,
          m.specialite_medicale_requise, e.nom AS etab_nom
        FROM public.missions m
        LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
        WHERE m.statut = 'OUVERTE'
          AND m.debut_le > v_now
          AND public.fn_soignant_eligible_mission(v_uid, m.id, false)
        ORDER BY m.debut_le
        LIMIT 3
      ) m
    ),
    'mes_missions', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb)
      FROM (
        SELECT m.id, m.intitule, m.debut_le, m.fin_le, m.duree_heures,
          m.statut, m.etablissement_id, e.nom AS etab_nom
        FROM public.missions m
        LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
        WHERE m.soignant_assigne_id = v_uid AND m.statut IN ('ASSIGNEE', 'EN_COURS')
        ORDER BY m.debut_le LIMIT 3
      ) m
    ),
    'documents', (
      SELECT COALESCE(jsonb_agg(row_to_json(d)::jsonb), '[]'::jsonb)
      FROM (
        SELECT id, type_document, valide_jusqua, statut_verification
        FROM public.documents_soignants
        WHERE soignant_id = v_uid AND supprime_le IS NULL
      ) d
    ),
    'heures_semaine', (
      SELECT COALESCE(sum(duree_heures), 0) FROM public.missions
      WHERE soignant_assigne_id = v_uid
        AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        AND debut_le >= v_lundi AND debut_le < v_dimanche
    ),
    'gains_mois', (
      SELECT jsonb_build_object(
        'net_total', COALESCE(sum(COALESCE(net_a_payer, net_estime, total_brut)), 0),
        'brut_total', COALESCE(sum(total_brut), 0),
        'nb_missions', count(*)
      ) FROM public.missions
      WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
        AND debut_le >= v_debut_mois AND debut_le <= v_fin_mois
    ),
    'gains_6mois', (
      SELECT COALESCE(jsonb_agg(row_to_json(g)::jsonb ORDER BY g.mois), '[]'::jsonb)
      FROM (
        SELECT to_char(debut_le, 'YYYY-MM') AS mois,
          round(COALESCE(sum(COALESCE(net_a_payer, net_estime)), 0)::numeric, 2) AS net
        FROM public.missions
        WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
          AND debut_le >= v_six_mois_ago
        GROUP BY to_char(debut_le, 'YYYY-MM')
      ) g
    ),
    'missions_semaine_cal', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb)
      FROM (
        SELECT debut_le, statut FROM public.missions
        WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE', 'EN_COURS')
          AND debut_le >= v_lundi AND debut_le < v_dimanche
      ) m
    ),
    'propositions', (
      SELECT COALESCE(jsonb_agg(row_to_json(p)::jsonb), '[]'::jsonb)
      FROM (
        SELECT c.id, c.mission_id, c.cree_le, c.type_contrat_choisi,
          jsonb_build_object(
            'id', m.id,
            'intitule', m.intitule,
            'debut_le', m.debut_le,
            'fin_le', m.fin_le,
            'duree_heures', m.duree_heures,
            'taux_horaire_base', m.taux_horaire_base,
            'net_estime', m.net_estime,
            'type_contrat_recherche', m.type_contrat_recherche,
            'etablissement_id', m.etablissement_id,
            'est_urgente', m.est_urgente,
            'etab_nom', e.nom
          ) AS missions
        FROM public.candidatures c
        JOIN public.missions m ON m.id = c.mission_id
        LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
        WHERE c.soignant_id = v_uid
          AND c.statut = 'PROPOSEE'
          AND c.cree_le >= v_now - interval '2 hours'
        ORDER BY c.cree_le DESC LIMIT 5
      ) p
    ),
    'heures_totales_terminees', (
      SELECT COALESCE(sum(duree_heures), 0) FROM public.missions
      WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
    ),
    'missions_oubliees_count', (
      SELECT count(*) FROM public.missions m
      WHERE m.soignant_assigne_id = v_uid AND m.statut = 'EN_COURS'
        AND m.fin_le < v_now - interval '30 minutes'
        AND NOT EXISTS (
          SELECT 1 FROM public.presences p
          WHERE p.mission_id = m.id AND p.pointage_arrivee_le IS NOT NULL
        )
    ),
    'notifs_non_lues', (
      SELECT count(*) FROM public.notifications WHERE destinataire_id = v_uid AND lue = false
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_diffuser_pool_urgence(p_mission_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_nb integer := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
         e.adresse_ville AS etab_ville
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN 0; END IF;
  IF NOT (public.est_admin() OR v_mission.etablissement_id = public.mon_etablissement_id()) THEN
    RETURN 0;
  END IF;

  INSERT INTO public.notifications(
    destinataire_id, type, titre, corps, lien, type_destinataire,
    type_ressource, id_ressource
  )
  SELECT s.id, 'POOL_URGENCE',
    '🚨 Mission urgente à pourvoir — premier arrivé, premier servi',
    public.fn_html_escape(v_mission.intitule) || ' — ' || COALESCE(v_mission.etab_ville, '') ||
      ', le ' || to_char(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
      ' à ' || COALESCE(v_mission.taux_horaire_base::text, '?') || ' €/h.',
    '/soignant/missions/' || v_mission.id, 'SOIGNANT', 'mission', v_mission.id
  FROM public.soignants s
  WHERE public.fn_soignant_eligible_mission(s.id, v_mission.id, true)
    AND COALESCE(s.disponible_urgence, false)
    AND NOT public.fn_est_exclu(s.id, v_mission.etablissement_id)
    AND (v_mission.soignant_assigne_id IS NULL OR s.id <> v_mission.soignant_assigne_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.destinataire_id = s.id
        AND n.type = 'POOL_URGENCE'
        AND n.type_ressource = 'mission'
        AND n.id_ressource = v_mission.id
        AND n.cree_le > now() - interval '12 hours'
    )
    AND (
      s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
      OR public.fn_haversine_distance_m(
        s.adresse_lat, s.adresse_lng, v_mission.etab_lat, v_mission.etab_lng
      ) <= COALESCE(s.urgence_rayon_km, s.rayon_deplacement_km, 50) * 1000
    )
  LIMIT 50;
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_pool_urgence_missions_pour_soignant()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant record;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'intitule', m.intitule,
    'profession_requise', m.profession_requise::text,
    'specialite_medicale_requise', m.specialite_medicale_requise,
    'type_contrat_recherche', m.type_contrat_recherche,
    'taux_horaire_base', m.taux_horaire_base,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'service', m.service,
    'etablissement_nom', e.nom,
    'etablissement_ville', e.adresse_ville,
    'distance_km', CASE
      WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL
      THEN round((public.fn_haversine_distance_m(
        v_soignant.adresse_lat, v_soignant.adresse_lng,
        e.adresse_lat, e.adresse_lng
      ) / 1000.0)::numeric, 1)
      ELSE NULL
    END,
    'deja_candidate', EXISTS (
      SELECT 1 FROM public.candidatures c WHERE c.mission_id = m.id AND c.soignant_id = v_uid
    ),
    'statut_candidature', (
      SELECT statut FROM public.candidatures c
      WHERE c.mission_id = m.id AND c.soignant_id = v_uid LIMIT 1
    )
  ) ORDER BY m.debut_le), '[]'::jsonb)
  INTO v_result
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND COALESCE(m.est_urgente, false)
    AND m.debut_le > now()
    AND public.fn_soignant_eligible_mission(v_uid, m.id, false)
    AND NOT public.fn_est_exclu(v_uid, m.etablissement_id)
    AND (
      e.adresse_lat IS NULL OR v_soignant.adresse_lat IS NULL
      OR public.fn_haversine_distance_m(
        v_soignant.adresse_lat, v_soignant.adresse_lng,
        e.adresse_lat, e.adresse_lng
      ) <= COALESCE(v_soignant.urgence_rayon_km, 30) * 1000
    );

  RETURN jsonb_build_object(
    'missions', v_result,
    'pool_actif', COALESCE(v_soignant.disponible_urgence, false),
    'rayon_km', COALESCE(v_soignant.urgence_rayon_km, 30),
    'sms_opt_in', COALESCE(v_soignant.pool_urgence_sms_opt_in, false)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
RETURNS TABLE(
  soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer,
  distance_km numeric, urgence_rayon_km integer, telephone text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
BEGIN
  SELECT m.id, m.etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT (public.est_admin() OR v_mission.etablissement_id = public.mon_etablissement_id()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT s.id, s.id, s.prenom::text, s.nom::text,
    COALESCE(s.score_fiabilite, 0)::integer,
    CASE WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL
      THEN round((public.fn_haversine_distance_m(
        s.adresse_lat, s.adresse_lng, v_mission.etab_lat, v_mission.etab_lng
      ) / 1000.0)::numeric, 1)
      ELSE NULL
    END,
    COALESCE(s.urgence_rayon_km, 15)::integer,
    s.telephone::text
  FROM public.soignants s
  WHERE COALESCE(s.disponible_urgence, false)
    AND public.fn_soignant_eligible_mission(s.id, p_mission_id, true)
    AND NOT public.fn_est_exclu(s.id, v_mission.etablissement_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.missions ma
      WHERE ma.soignant_assigne_id = s.id AND ma.statut = 'EN_COURS'
        AND now() BETWEEN ma.debut_le AND ma.fin_le
    )
    AND (
      s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
      OR public.fn_haversine_distance_m(
        s.adresse_lat, s.adresse_lng, v_mission.etab_lat, v_mission.etab_lng
      ) <= COALESCE(s.urgence_rayon_km, 15) * 1000
    )
  ORDER BY s.score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;

-- Les deux vagues (urgente et non urgente) utilisent la même éligibilité que
-- le feed. Cela inclut donc une IADE sur une mission IDE salariée.
CREATE OR REPLACE FUNCTION public.fn_vagues_notification_urgentes()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_s record;
  v_taille integer;
  v_envoyes integer := 0;
  v_missions integer := 0;
  v_nu_missions integer := 0;
  v_nu_envoyes integer := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  v_t1 integer := GREATEST(1, public.fn_param_num('vague_taille_1', 10)::integer);
  v_t2 integer := GREATEST(1, public.fn_param_num('vague_taille_2', 30)::integer);
  v_t3 integer := GREATEST(1, public.fn_param_num('vague_taille_3', 60)::integer);
  v_d2 integer := GREATEST(1, public.fn_param_num('vague_delai_2_min', 15)::integer);
  v_d3 integer := GREATEST(1, public.fn_param_num('vague_delai_3_min', 30)::integer);
  v_cap integer := GREATEST(1, public.fn_param_num('vague_cap_push_24h', 3)::integer);
  v_fenetre_h integer := GREATEST(1, public.fn_param_num('vague_fenetre_urgente_h', 48)::integer);
  v_nu_delai_h integer := GREATEST(1, public.fn_param_num('vague_non_urgente_delai_h', 4)::integer);
  v_nu_taille integer := GREATEST(1, public.fn_param_num('vague_non_urgente_taille', 20)::integer);
  v_nu_cap integer := GREATEST(1, public.fn_param_num('vague_non_urgente_cap_24h', 2)::integer);
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL;
  END;

  FOR v_m IN
    SELECT m.id, m.intitule, m.taux_horaire_base, m.debut_le, m.cree_le,
           m.etablissement_id, e.adresse_ville AS etab_ville,
           e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.est_urgente
      AND m.remplacement_de_mission_id IS NULL
      AND m.debut_le BETWEEN now() AND now() + make_interval(hours => v_fenetre_h)
      AND m.intitule NOT LIKE '[%'
      AND NOT EXISTS (SELECT 1 FROM public.candidatures c WHERE c.mission_id = m.id)
  LOOP
    v_missions := v_missions + 1;
    v_taille := CASE
      WHEN v_m.cree_le > now() - make_interval(mins => v_d2) THEN v_t1
      WHEN v_m.cree_le > now() - make_interval(mins => v_d3) THEN v_t2
      ELSE v_t3
    END;
    v_corps := public.fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') ||
      ', débute le ' || to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
      ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h.';

    FOR v_s IN
      SELECT s.id AS soignant_id
      FROM public.soignants s
      LEFT JOIN public.matching_scores ms ON ms.soignant_id = s.id AND ms.mission_id = v_m.id
      WHERE public.fn_soignant_eligible_mission(s.id, v_m.id, true)
        AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
        AND NOT EXISTS (SELECT 1 FROM public.swipes sw WHERE sw.mission_id = v_m.id AND sw.soignant_id = s.id)
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR public.fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
        AND NOT EXISTS (
          SELECT 1 FROM public.notifications n
          WHERE n.destinataire_id = s.id AND n.type = 'MISSION_URGENTE'
            AND n.lien = '/soignant/missions/' || v_m.id
        )
        AND (
          SELECT count(*) FROM public.notifications n2
          WHERE n2.destinataire_id = s.id AND n2.type = 'MISSION_URGENTE'
            AND n2.cree_le > now() - interval '24 hours'
        ) < v_cap
      ORDER BY COALESCE(ms.score_global, 0) DESC,
        public.fn_haversine_distance_m(
          COALESCE(s.adresse_lat, 0), COALESCE(s.adresse_lng, 0),
          COALESCE(v_m.etab_lat, 0), COALESCE(v_m.etab_lng, 0)
        ) ASC
      LIMIT v_taille
    LOOP
      INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (
        v_s.soignant_id, 'MISSION_URGENTE', '⚡ Mission urgente sélectionnée pour vous',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT'
      );
      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s.soignant_id,
              'type_evenement', 'MISSION_URGENTE',
              'titre', '⚡ Mission urgente sélectionnée pour vous',
              'corps', v_corps,
              'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
      v_envoyes := v_envoyes + 1;
    END LOOP;
  END LOOP;

  FOR v_m IN
    SELECT m.id, m.intitule, m.taux_horaire_base, m.debut_le, m.etablissement_id,
           e.adresse_ville AS etab_ville, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND NOT m.est_urgente
      AND m.remplacement_de_mission_id IS NULL
      AND m.cree_le < now() - make_interval(hours => v_nu_delai_h)
      AND m.debut_le > now()
      AND m.intitule NOT LIKE '[%'
      AND NOT EXISTS (SELECT 1 FROM public.candidatures c WHERE c.mission_id = m.id)
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.type = 'MISSION_A_POURVOIR' AND n.lien = '/soignant/missions/' || m.id
      )
  LOOP
    v_nu_missions := v_nu_missions + 1;
    v_corps := public.fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') ||
      ', débute le ' || to_char(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
      ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Personne n''a encore postulé.';

    FOR v_s IN
      SELECT s.id AS soignant_id
      FROM public.soignants s
      LEFT JOIN public.matching_scores ms ON ms.soignant_id = s.id AND ms.mission_id = v_m.id
      WHERE public.fn_soignant_eligible_mission(s.id, v_m.id, true)
        AND NOT public.fn_est_exclu(s.id, v_m.etablissement_id)
        AND NOT EXISTS (SELECT 1 FROM public.swipes sw WHERE sw.mission_id = v_m.id AND sw.soignant_id = s.id)
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR public.fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
        AND (
          SELECT count(*) FROM public.notifications n2
          WHERE n2.destinataire_id = s.id AND n2.type = 'MISSION_A_POURVOIR'
            AND n2.cree_le > now() - interval '24 hours'
        ) < v_nu_cap
      ORDER BY COALESCE(ms.score_global, 0) DESC
      LIMIT v_nu_taille
    LOOP
      INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (
        v_s.soignant_id, 'MISSION_A_POURVOIR', '✨ Une mission sélectionnée pour vous',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT'
      );
      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s.soignant_id,
              'type_evenement', 'MISSION_A_POURVOIR',
              'titre', '✨ Une mission sélectionnée pour vous',
              'corps', v_corps,
              'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
      v_nu_envoyes := v_nu_envoyes + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'missions', v_missions,
    'notifications', v_envoyes,
    'missions_non_urgentes', v_nu_missions,
    'notifications_non_urgentes', v_nu_envoyes
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_matching_inverse_dispos()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant record;
  v_count integer;
  v_notifies integer := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  v_cap_h integer := GREATEST(1, public.fn_param_num('alerte_filtre_cap_h', 20)::integer);
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL;
  END;

  FOR v_soignant IN
    SELECT DISTINCT s.id, s.adresse_lat, s.adresse_lng, s.rayon_deplacement_km
    FROM public.soignants s
    JOIN public.disponibilites_soignant d ON d.soignant_id = s.id
    WHERE d.jour BETWEEN current_date AND current_date + 14
      AND s.supprime_le IS NULL
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.destinataire_id = s.id AND n.type = 'MISSION_A_POURVOIR'
          AND n.cree_le > now() - make_interval(hours => v_cap_h)
      )
  LOOP
    SELECT count(*) INTO v_count
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND m.intitule NOT LIKE '[%'
      AND public.fn_soignant_eligible_mission(v_soignant.id, m.id, true)
      AND NOT public.fn_est_exclu(v_soignant.id, m.etablissement_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.swipes sw
        WHERE sw.mission_id = m.id AND sw.soignant_id = v_soignant.id
      )
      AND (
        v_soignant.adresse_lat IS NULL OR e.adresse_lat IS NULL
        OR public.fn_haversine_distance_m(
          v_soignant.adresse_lat, v_soignant.adresse_lng,
          e.adresse_lat, e.adresse_lng
        ) <= COALESCE(v_soignant.rayon_deplacement_km, 50) * 1000
      )
      AND EXISTS (
        SELECT 1 FROM public.disponibilites_soignant d
        WHERE d.soignant_id = v_soignant.id
          AND d.jour = (m.debut_le AT TIME ZONE 'Europe/Paris')::date
          AND (
            d.creneau = 'JOURNEE'
            OR (d.creneau = 'NUIT' AND (
              extract(hour FROM m.debut_le AT TIME ZONE 'Europe/Paris') >= 20
              OR extract(hour FROM m.debut_le AT TIME ZONE 'Europe/Paris') < 7
            ))
            OR (d.creneau IN ('MATIN', 'APRES_MIDI')
                AND extract(hour FROM m.debut_le AT TIME ZONE 'Europe/Paris') BETWEEN 7 AND 19)
          )
      );

    IF v_count > 0 THEN
      v_corps := v_count || ' mission' || CASE WHEN v_count > 1 THEN 's correspondent' ELSE ' correspond' END ||
        ' à vos disponibilités des deux prochaines semaines.';
      INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (
        v_soignant.id, 'MISSION_A_POURVOIR', '📅 Des missions correspondent à votre planning',
        v_corps, '/soignant/recherche-missions?vue=swipe', 'SOIGNANT'
      );
      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_soignant.id,
              'type_evenement', 'MISSION_A_POURVOIR',
              'titre', '📅 Des missions correspondent à votre planning',
              'corps', v_corps,
              'data', jsonb_build_object('lien', '/soignant/recherche-missions?vue=swipe')
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
      v_notifies := v_notifies + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'notifies', v_notifies);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_digest_hebdo_cibles(p_limit integer DEFAULT 500)
RETURNS TABLE(id uuid, prenom text, email text, profession text, nb_missions bigint, taux_max numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT s.id, s.prenom::text, s.email::text, s.profession::text,
    (SELECT count(*) FROM public.missions m
      WHERE m.statut = 'OUVERTE' AND public.fn_soignant_eligible_mission(s.id, m.id, false)),
    (SELECT max(m.taux_horaire_base) FROM public.missions m
      WHERE m.statut = 'OUVERTE' AND public.fn_soignant_eligible_mission(s.id, m.id, false))
  FROM public.soignants s
  WHERE s.email IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.statut = 'OUVERTE' AND public.fn_soignant_eligible_mission(s.id, m.id, false)
    )
  LIMIT greatest(COALESCE(p_limit, 500), 1);
$function$;

-- Édition complète : tous les champs affichés comme modifiables sont persistés
-- par une seule transaction et le trigger de matrice revalide le contrat.
CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement_v2(
  p_mission_id uuid,
  p_intitule text,
  p_description text DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_profession_requise public.type_profession DEFAULT NULL,
  p_debut_le timestamptz DEFAULT NULL,
  p_fin_le timestamptz DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE',
  p_type_contrat_recherche text DEFAULT 'SALARIE',
  p_specialite_medicale_requise text DEFAULT NULL,
  p_accepte_non_specialises boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_etablissement_id uuid := public.mon_etablissement_id();
BEGIN
  SELECT * INTO v_mission
    FROM public.missions
   WHERE id = p_mission_id
     AND (etablissement_id = v_etablissement_id OR public.est_admin());
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable ou accès refusé.');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions ouvertes peuvent être modifiées.');
  END IF;
  IF p_intitule IS NULL OR length(btrim(p_intitule)) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'L''intitulé doit contenir au moins 3 caractères.');
  END IF;
  IF p_profession_requise IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'La profession requise est obligatoire.');
  END IF;
  IF p_debut_le IS NULL OR p_fin_le IS NULL OR p_fin_le <= p_debut_le THEN
    RETURN jsonb_build_object('success', false, 'error', 'La date de fin doit être postérieure à la date de début.');
  END IF;
  IF p_debut_le < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Une mission ouverte ne peut pas être déplacée dans le passé.');
  END IF;
  IF p_taux_horaire_base IS NULL OR p_taux_horaire_base <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Le taux horaire doit être supérieur à zéro.');
  END IF;
  IF p_mode_attribution NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mode d''attribution invalide.');
  END IF;
  IF p_type_contrat_recherche NOT IN ('SALARIE', 'LIBERAL', 'TOUS') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Type de contrat invalide.');
  END IF;
  IF v_mission.nb_creneaux > 1
     AND (p_debut_le IS DISTINCT FROM v_mission.debut_le OR p_fin_le IS DISTINCT FROM v_mission.fin_le) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Les dates d''une mission multi-jours se modifient depuis ses créneaux, pas depuis l''enveloppe globale.'
    );
  END IF;

  UPDATE public.missions
     SET intitule = btrim(p_intitule),
         description = p_description,
         service = NULLIF(btrim(p_service), ''),
         profession_requise = p_profession_requise,
         debut_le = p_debut_le,
         fin_le = p_fin_le,
         taux_horaire_base = p_taux_horaire_base,
         est_urgente = COALESCE(p_est_urgente, false),
         niveau_urgence = CASE WHEN COALESCE(p_est_urgente, false)
           THEN GREATEST(1, LEAST(COALESCE(p_niveau_urgence, 1), 3)) ELSE 0 END,
         mode_attribution = p_mode_attribution,
         type_contrat_recherche = p_type_contrat_recherche,
         specialite_medicale_requise = CASE
           WHEN p_profession_requise = 'MEDECIN' THEN NULLIF(btrim(p_specialite_medicale_requise), '')
           ELSE NULL
         END,
         accepte_non_specialises = CASE
           WHEN p_profession_requise IN ('IBODE', 'IADE') THEN COALESCE(p_accepte_non_specialises, true)
           ELSE true
         END,
         modifie_le = now()
   WHERE id = p_mission_id;

  -- Relire la ligne après les triggers de matrice et de calcul : le contrat
  -- retourné/audité est celui réellement appliqué, pas la préférence envoyée.
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    auth.uid(),
    CASE WHEN public.est_admin() THEN 'ADMIN' ELSE 'ADMIN_ETABLISSEMENT' END,
    'MISSION_MODIFICATION', 'mission', p_mission_id, NULL,
    jsonb_build_object(
      'profession_requise', v_mission.profession_requise,
      'debut_le', v_mission.debut_le,
      'fin_le', v_mission.fin_le,
      'taux_horaire_base', v_mission.taux_horaire_base,
      'type_contrat_recherche', v_mission.type_contrat_recherche,
      'mode_attribution', v_mission.mode_attribution,
      'est_urgente', v_mission.est_urgente
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'mission_id', p_mission_id,
    'profession_requise', v_mission.profession_requise,
    'type_contrat_recherche', v_mission.type_contrat_recherche
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'sqlstate', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(
  p_profession text DEFAULT NULL,
  p_ville text DEFAULT NULL
) RETURNS TABLE(
  id uuid, intitule text, profession_requise text, ville text, code_postal text,
  debut_le timestamptz, fin_le timestamptz, taux_horaire_base numeric,
  est_urgente boolean, type_contrat_recherche text, total_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_est_soignant boolean := EXISTS (
    SELECT 1 FROM public.soignants s WHERE s.id = auth.uid() AND s.supprime_le IS NULL
  );
BEGIN
  RETURN QUERY
  WITH filtered AS (
    SELECT m.id AS mid, m.intitule AS mintitule, m.profession_requise::text AS mprof,
      e.adresse_ville::text AS mville, e.adresse_code_postal::text AS mcp,
      m.debut_le AS mdebut, m.fin_le AS mfin, m.taux_horaire_base AS mtaux,
      COALESCE(m.est_urgente, false) AS murgente,
      m.type_contrat_recherche::text AS mcontrat, m.cree_le AS mcree
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND e.supprime_le IS NULL
      AND COALESCE(e.est_compte_test, false) = false
      AND e.statut_verification = 'VERIFIE'
      AND COALESCE(e.peut_publier_missions, false) = true
      AND e.type <> 'PHARMACIE_OFFICINE'
      AND m.intitule NOT LIKE '[%'
      AND (p_profession IS NULL OR btrim(p_profession) = '' OR m.profession_requise::text = btrim(p_profession))
      AND (p_ville IS NULL OR btrim(p_ville) = ''
           OR e.adresse_ville ILIKE '%' || btrim(p_ville) || '%'
           OR e.adresse_code_postal LIKE btrim(p_ville) || '%')
      AND (NOT v_est_soignant OR public.fn_soignant_eligible_mission(v_uid, m.id, false))
      AND (v_uid IS NULL OR NOT public.fn_est_exclu(v_uid, m.etablissement_id))
  ), counted AS (
    SELECT count(*)::bigint AS cnt FROM filtered
  )
  SELECT f.mid, f.mintitule, f.mprof, f.mville, f.mcp, f.mdebut, f.mfin,
         f.mtaux, f.murgente, f.mcontrat, c.cnt
  FROM filtered f CROSS JOIN counted c
  ORDER BY f.murgente DESC, f.mcree DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_missions_publiques_recherche(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_recherche(text, text) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_mission_publique(p_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT to_jsonb(t) FROM (
    SELECT m.id, m.intitule, left(COALESCE(m.description, ''), 1500) AS description,
           m.profession_requise::text, m.debut_le, m.fin_le,
           m.taux_horaire_base, m.est_urgente, m.service,
           m.type_contrat_recherche::text,
           m.cree_le, m.modifie_le,
           e.nom AS etablissement_nom, e.type::text AS etablissement_type,
           e.adresse_ville::text AS ville,
           e.adresse_code_postal::text AS code_postal
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
     WHERE m.id = p_id
       AND m.statut = 'OUVERTE'
       AND m.debut_le > now()
       AND e.supprime_le IS NULL
       AND COALESCE(e.est_compte_test, false) = false
       AND e.statut_verification = 'VERIFIE'
       AND COALESCE(e.peut_publier_missions, false) = true
       AND e.type <> 'PHARMACIE_OFFICINE'
       AND m.intitule NOT LIKE '[%'
  ) t;
$function$;

CREATE OR REPLACE FUNCTION public.fn_missions_ouvertes_sitemap()
RETURNS TABLE(id uuid, maj timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT m.id, greatest(m.cree_le, COALESCE(m.modifie_le, m.cree_le)) AS maj
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.statut = 'OUVERTE'
     AND m.debut_le > now()
     AND e.supprime_le IS NULL
     AND COALESCE(e.est_compte_test, false) = false
     AND e.statut_verification = 'VERIFIE'
     AND COALESCE(e.peut_publier_missions, false) = true
     AND e.type <> 'PHARMACIE_OFFICINE'
     AND m.intitule NOT LIKE '[%'
   ORDER BY m.cree_le DESC
   LIMIT 2000;
$function$;

REVOKE ALL ON FUNCTION public.fn_mission_publique(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mission_publique(uuid) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_missions_ouvertes_sitemap() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_missions_ouvertes_sitemap() TO service_role;

-- Centre d'aide live : retirer les articles dont la règle dépend encore du
-- profil ou qui promettent des remplacements d'officine. Leur contenu n'est
-- pas supprimé et reste disponible en admin pour révision.
UPDATE public.articles_aide
   SET publie = false,
       mis_a_jour_le = now()
 WHERE slug <> 'modes-exercice-missions'
   AND publie = true
   AND (
     contenu ILIKE '%n°488367%'
     OR contenu ILIKE '%488367%'
     OR contenu ~* 'IADE.{0,80}(libéral|honoraire)'
     OR contenu ~* 'pharmacien.{0,100}(officine|libéral|honoraire)'
     OR contenu ~* '(type_exercice|type d.exercice).{0,160}(mission|candid)'
     OR contenu ~* '(profil|diplôme).{0,120}(détermine|impose).{0,120}(contrat|libéral|salari)'
   );

INSERT INTO public.articles_aide(
  slug, titre, contenu, audience, categorie, ordre_affichage, publie
) VALUES (
  'modes-exercice-missions',
  'Comment le contrat d’une mission est-il déterminé ?',
  E'Le régime se lit sur la **profession requise par la mission** et sur le type d’établissement, jamais sur les diplômes supplémentaires du soignant.\n\n- Un profil IADE peut candidater à une mission IDE : les règles IDE de cette mission s’appliquent.\n- Une mission qui requiert IADE ou IBODE est proposée en contrat salarié, sans exception.\n- Les missions de pharmacien proposées par Jolene concernent les besoins salariés d’établissement, notamment en PUI. Le remplacement d’un titulaire d’officine n’est pas proposé.\n- Les missions de manipulateur en électroradiologie sont proposées en contrat salarié.\n- Toute combinaison absente de la matrice est proposée en contrat salarié. Un contrat libéral n’existe que lorsqu’une cellule explicite et sourcée l’autorise.\n\nPour les professions visées par la lettre : lettre interministérielle du 30 décembre 2021 (n° D21-031940), validée par le Conseil d’État (11/02/2025, n°491128). Le cas aide-soignant a été jugé par le Conseil d’État (n°491128). Centre de santé : art. L.6323-1-5 du code de la santé publique.',
  'COMMUN', 'CONFORMITE', 5, true
)
ON CONFLICT (slug) DO UPDATE SET
  titre = EXCLUDED.titre,
  contenu = EXCLUDED.contenu,
  audience = EXCLUDED.audience,
  categorie = EXCLUDED.categorie,
  ordre_affichage = EXCLUDED.ordre_affichage,
  publie = true,
  mis_a_jour_le = now();

REVOKE ALL ON FUNCTION public.fn_modifier_mission_etablissement_v2(
  uuid, text, text, text, public.type_profession, timestamptz, timestamptz,
  numeric, boolean, integer, text, text, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_modifier_mission_etablissement_v2(
  uuid, text, text, text, public.type_profession, timestamptz, timestamptz,
  numeric, boolean, integer, text, text, text, boolean
) TO authenticated, service_role;

-- Permissions des RPCs remplacées : aucune réouverture à anon/PUBLIC.
REVOKE ALL ON FUNCTION public.fn_professions_liberales() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_accepter_mission(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_assigner_mission_admin(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_postuler_mission(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_traiter_candidature(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_accepter_mission_urgence(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_enregistrer_swipe(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_obtenir_missions_swipe(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_dashboard_soignant_complet() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_diffuser_pool_urgence(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_pool_urgence_missions_pour_soignant() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_soignants_urgence(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_vagues_notification_urgentes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_matching_inverse_dispos() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_digest_hebdo_cibles(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dec_verifier_plafond_48h() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_toggle_pool_urgence(boolean, integer, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_rebooker_soignant(uuid, uuid, timestamptz, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_suggestions_missions_pour_soignant(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_booster_mission(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_relancer_missions_sans_candidat() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_trg_auto_notify_mission_urgente() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_detecter_noshow_et_remplacer() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_escalade_remplacement_non_pourvu() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_email_recap_hebdo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_soignants_inactifs_a_relancer(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_recommander_soignants(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_proposer_mission_soignant(uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_repondre_proposition(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_mode_paiement_mission(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_protect_candidature_statut() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_professions_liberales() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_accepter_mission(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_assigner_mission_admin(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_postuler_mission(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_traiter_candidature(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_accepter_mission_urgence(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_enregistrer_swipe(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_obtenir_missions_swipe(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_dashboard_soignant_complet() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_diffuser_pool_urgence(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_pool_urgence_missions_pour_soignant() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_soignants_urgence(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_vagues_notification_urgentes() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_matching_inverse_dispos() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_digest_hebdo_cibles(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.dec_verifier_plafond_48h() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_toggle_pool_urgence(boolean, integer, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_rebooker_soignant(uuid, uuid, timestamptz, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_suggestions_missions_pour_soignant(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_booster_mission(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_relancer_missions_sans_candidat() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_trg_auto_notify_mission_urgente() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_detecter_noshow_et_remplacer() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_escalade_remplacement_non_pourvu() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_email_recap_hebdo() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_soignants_inactifs_a_relancer(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_recommander_soignants(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_proposer_mission_soignant(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_repondre_proposition(uuid, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mode_paiement_mission(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_protect_candidature_statut() TO service_role;

-- Scoring : le filtre dur de profession utilise la hiérarchie commune ; une
-- IADE reçoit donc un score réel sur une mission IDE au lieu d'un faux zéro.
CREATE OR REPLACE FUNCTION public.fn_calculer_score_matching(p_soignant_id uuid, p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant record;
  v_mission record;
  v_etab record;
  v_prefs record;
  v_taux_median numeric;
  v_distance_km numeric;
  v_ratio numeric;
  v_est_nuit boolean;
  v_est_we boolean;
  v_score_tarif integer := 0;
  v_score_distance integer := 0;
  v_score_horaire integer := 0;
  v_score_etab integer := 0;
  v_score_urgence integer := 0;
  v_score_soignant_fiabilite integer := 0;
  v_bonus_fraicheur integer := 0;
  v_bonus_connaissance integer := 0;
  v_bonus_paiement_rapide integer := 0;
  v_bonus_boost integer := 0;
  v_bonus_service integer := 0;
  v_score_global integer := 0;
  v_breakdown jsonb;
BEGIN
  SELECT id, profession, adresse_lat, adresse_lng, score_fiabilite, type_contrat
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id;

  IF v_soignant.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'soignant_introuvable'));
  END IF;

  SELECT m.id, m.profession_requise, m.etablissement_id, m.taux_horaire_base,
         m.statut, m.est_urgente, m.debut_le, m.fin_le, m.duree_heures,
         m.cree_le, m.boostee_le, m.type_contrat_recherche, m.service
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id;

  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'mission_introuvable'));
  END IF;

  IF NOT public.fn_soignant_eligible_mission(p_soignant_id, p_mission_id, false) THEN
    RETURN jsonb_build_object(
      'score', 0,
      'breakdown', jsonb_build_object('filtre_dur_ko', 'profession_incompatible')
    );
  END IF;

  SELECT id, adresse_lat, adresse_lng, score_qualite,
         mode_paiement_commission, stripe_sepa_payment_method_id
    INTO v_etab
    FROM public.etablissements
   WHERE id = v_mission.etablissement_id;

  IF v_soignant.adresse_lat IS NOT NULL
     AND v_soignant.adresse_lng IS NOT NULL
     AND v_etab.adresse_lat IS NOT NULL
     AND v_etab.adresse_lng IS NOT NULL THEN
    v_distance_km := 6371 * acos(
      cos(radians(v_soignant.adresse_lat)) * cos(radians(v_etab.adresse_lat))
      * cos(radians(v_etab.adresse_lng) - radians(v_soignant.adresse_lng))
      + sin(radians(v_soignant.adresse_lat)) * sin(radians(v_etab.adresse_lat))
    );

    IF v_distance_km > 50 THEN
      RETURN jsonb_build_object(
        'score', 0,
        'breakdown', jsonb_build_object(
          'filtre_dur_ko', 'distance_excessive',
          'distance_km', round(v_distance_km, 1)
        )
      );
    END IF;
  ELSE
    v_distance_km := NULL;
  END IF;

  -- v3 : tarif RELATIF à la médiane de marché de la profession (90 j).
  -- ratio 0,7× → 2 pts, 1,0× → ~13 pts, ≥1,2× → 20 pts. Fallback ancien
  -- barème (seuil 30 €) si pas assez de données de marché.
  SELECT taux_median INTO v_taux_median
    FROM public.marche_taux_medians
   WHERE profession = v_mission.profession_requise::text;

  IF v_mission.taux_horaire_base IS NULL THEN
    v_score_tarif := 10;
  ELSIF v_taux_median IS NOT NULL AND v_taux_median > 0 THEN
    v_ratio := v_mission.taux_horaire_base / v_taux_median;
    v_score_tarif := LEAST(20, GREATEST(2, round(2 + (v_ratio - 0.7) / 0.5 * 18)::integer));
  ELSE
    v_score_tarif := LEAST(20, GREATEST(0,
      CASE WHEN v_mission.taux_horaire_base >= 30 THEN 20
           ELSE round(v_mission.taux_horaire_base / 30.0 * 20)::integer END));
  END IF;

  v_score_distance := CASE
    WHEN v_distance_km IS NULL THEN 10
    WHEN v_distance_km < 5 THEN 20
    WHEN v_distance_km >= 50 THEN 0
    ELSE round(20 * (1 - (v_distance_km - 5) / 45.0))::integer
  END;

  -- v3 : pattern horaire appris — 15 × moyenne(pref tranche-heure, pref
  -- tranche-semaine). Neutre (7-8 pts) sans historique de swipe.
  v_est_nuit := v_mission.debut_le IS NOT NULL AND (
    EXTRACT(HOUR FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') >= 20
    OR EXTRACT(HOUR FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') < 7);
  v_est_we := v_mission.debut_le IS NOT NULL
    AND EXTRACT(DOW FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') IN (0, 6);

  SELECT * INTO v_prefs
    FROM public.matching_preferences_soignant
   WHERE soignant_id = p_soignant_id;

  v_score_horaire := round(15 * (
    (CASE WHEN v_est_nuit THEN COALESCE(v_prefs.pref_nuit, 0.5) ELSE COALESCE(v_prefs.pref_jour, 0.5) END
     + CASE WHEN v_est_we THEN COALESCE(v_prefs.pref_weekend, 0.5) ELSE COALESCE(v_prefs.pref_semaine, 0.5) END
    ) / 2.0))::integer;

  v_score_etab := LEAST(15, GREATEST(0,
    CASE
      WHEN v_etab.score_qualite IS NULL THEN 7
      ELSE round(v_etab.score_qualite / 100.0 * 15)::integer
    END
  ));

  v_score_urgence := CASE WHEN v_mission.est_urgente THEN 10 ELSE 0 END;

  v_score_soignant_fiabilite := LEAST(10, GREATEST(0,
    CASE
      WHEN v_soignant.score_fiabilite IS NULL THEN 5
      ELSE round(COALESCE(v_soignant.score_fiabilite, 50) / 100.0 * 10)::integer
    END
  ));

  v_bonus_fraicheur := LEAST(5, GREATEST(0,
    5 - FLOOR(EXTRACT(EPOCH FROM (NOW() - COALESCE(v_mission.cree_le, NOW()))) / 86400)::integer
  ));

  -- v3 : bonus fort « tu connais cet établissement » (mission déjà réalisée).
  v_bonus_connaissance := CASE WHEN EXISTS (
    SELECT 1 FROM public.missions mh
     WHERE mh.soignant_assigne_id = p_soignant_id
       AND mh.etablissement_id = v_mission.etablissement_id
       AND mh.statut = 'TERMINEE'
  ) THEN 8 ELSE 0 END;

  -- Lot 17 (A1) : bonus « tu connais ce service » — mission TERMINEE dans le
  -- même service (libellé normalisé Lot 12), quel que soit l'établissement.
  v_bonus_service := CASE WHEN
    v_mission.service IS NOT NULL
    AND btrim(v_mission.service) <> ''
    AND EXISTS (
      SELECT 1 FROM public.missions mh
       WHERE mh.soignant_assigne_id = p_soignant_id
         AND mh.statut = 'TERMINEE'
         AND mh.service IS NOT NULL
         AND lower(btrim(mh.service)) = lower(btrim(v_mission.service))
    )
  THEN GREATEST(0, public.fn_param_num('matching_bonus_service', 4)::integer) ELSE 0 END;

  -- v3 : bonus ⚡ paiement rapide (même gating serveur que le badge 7c).
  v_bonus_paiement_rapide := CASE WHEN
    public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
    AND v_mission.type_contrat_recherche = 'LIBERAL'
    AND v_etab.mode_paiement_commission = 'SEPA_DEBIT'
    AND v_etab.stripe_sepa_payment_method_id IS NOT NULL
  THEN 5 ELSE 0 END;

  v_bonus_boost := CASE
    WHEN v_mission.boostee_le IS NOT NULL AND v_mission.boostee_le > NOW() - INTERVAL '7 days' THEN 10
    ELSE 0
  END;

  v_score_global := v_score_tarif + v_score_distance + v_score_horaire + v_score_etab
                  + v_score_urgence + v_score_soignant_fiabilite
                  + v_bonus_fraicheur + v_bonus_connaissance + v_bonus_service
                  + v_bonus_paiement_rapide + v_bonus_boost;

  v_breakdown := jsonb_build_object(
    'tarif', v_score_tarif,
    'distance', v_score_distance,
    'horaire', v_score_horaire,
    'etablissement', v_score_etab,
    'urgence', v_score_urgence,
    'soignant_fiabilite', v_score_soignant_fiabilite,
    'fraicheur', v_bonus_fraicheur,
    'connaissance_etab', v_bonus_connaissance,
    'service', v_bonus_service,
    'paiement_rapide', v_bonus_paiement_rapide,
    'boost', v_bonus_boost,
    'distance_km', CASE WHEN v_distance_km IS NULL THEN NULL ELSE round(v_distance_km, 1) END,
    'taux_median', v_taux_median
  );

  RETURN jsonb_build_object(
    'score', LEAST(100, GREATEST(0, v_score_global)),
    'breakdown', v_breakdown
  );
END;
$function$;
