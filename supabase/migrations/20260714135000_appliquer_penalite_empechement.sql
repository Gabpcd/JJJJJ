-- Correctifs post-déploiement de l'attestation d'empêchement impérieux :
--   1. la protection d'identité soignant neutralisait la pénalité -8 ;
--   2. le compteur canonique effaçait les annulations dont la mission rouvrait ;
--   3. deux déclarations simultanées pouvaient contourner le quota ;
--   4. la garantie retournait pool_alerte=0 alors que le trigger urgent avait
--      diffusé la mission ; un second fan-out aurait créé des doublons ;
--   5. un recalcul v2 ultérieur pouvait effacer la pénalité.
--
-- Les mutations internes réutilisent un contexte transactionnel restauré même
-- en cas d'exception. Les annulations et malus sont dérivés du journal d'audit
-- immuable, qui devient donc obligatoire (échec fermé si l'écriture échoue).

-- ---------------------------------------------------------------------------
-- Diffusion pool : coeur privé non exécutable par les rôles API
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.fn_diffuser_pool_urgence_interne(
  p_mission_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_mission record;
  v_nb integer := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
         e.adresse_ville AS etab_ville,
         COALESCE(e.est_compte_test, false) AS etab_est_compte_test
  INTO v_mission
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.id = p_mission_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  INSERT INTO public.notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire,
    type_ressource, id_ressource
  )
  SELECT s.id,
    'POOL_URGENCE',
    '🚨 Mission urgente à pourvoir — premier arrivé, premier servi',
    public.fn_html_escape(v_mission.intitule) || ' — '
      || COALESCE(v_mission.etab_ville, '') || ', le '
      || to_char(
        v_mission.debut_le AT TIME ZONE 'Europe/Paris',
        'DD/MM à HH24:MI'
      ) || ' à ' || COALESCE(v_mission.taux_horaire_base::text, '?')
      || ' €/h.',
    '/soignant/missions/' || v_mission.id,
    'SOIGNANT',
    'mission',
    v_mission.id
  FROM public.soignants s
  WHERE public.fn_soignant_eligible_mission(s.id, v_mission.id, true)
    -- Cloisonnement strict : une mission de démonstration ne cible jamais un
    -- compte réel, et une mission réelle ne pollue jamais les comptes stores.
    AND COALESCE(s.est_compte_test, false) = v_mission.etab_est_compte_test
    AND COALESCE(s.disponible_urgence, false)
    AND NOT public.fn_est_exclu(s.id, v_mission.etablissement_id)
    AND (
      v_mission.soignant_assigne_id IS NULL
      OR s.id <> v_mission.soignant_assigne_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.destinataire_id = s.id
        AND n.type = 'POOL_URGENCE'
        AND n.type_ressource = 'mission'
        AND n.id_ressource = v_mission.id
        AND n.cree_le > now() - interval '12 hours'
    )
    AND (
      s.adresse_lat IS NULL
      OR v_mission.etab_lat IS NULL
      OR public.fn_haversine_distance_m(
        s.adresse_lat, s.adresse_lng,
        v_mission.etab_lat, v_mission.etab_lng
      ) <= COALESCE(
        s.urgence_rayon_km, s.rayon_deplacement_km, 50
      ) * 1000
    )
  ORDER BY COALESCE(s.score_fiabilite, 0) DESC, s.id
  LIMIT 50;

  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb;
END;
$function$;


-- ---------------------------------------------------------------------------
-- Garantie remplacement : contexte interne borné + isolation réel/démo
-- ---------------------------------------------------------------------------

-- Le filtre canonique doit être symétrique. Sans cette égalité, un compte de
-- démonstration pouvait recevoir les alertes d'une mission réelle, alors que
-- l'inverse était déjà bloqué par fn_resoudre_contrat_mission.
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
  SELECT m.profession_requise, m.specialite_medicale_requise,
         COALESCE(m.accepte_non_specialises, true) AS accepte_non_specialises,
         COALESCE(m.type_contrat_recherche::text, 'SALARIE') AS type_contrat_recherche,
         m.remplacement_de_mission_id,
         COALESCE(e.est_compte_test, false) AS est_compte_test
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id AND m.statut = 'OUVERTE';
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT profession, specialite_medicale,
         COALESCE(type_exercice, 'SALARIE') AS type_exercice,
         COALESCE(est_compte_test, false) AS est_compte_test
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id
     AND supprime_le IS NULL
     AND COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF';
  IF NOT FOUND THEN RETURN false; END IF;

  IF v_soignant.est_compte_test IS DISTINCT FROM v_mission.est_compte_test THEN
    RETURN false;
  END IF;

  -- Aucun assigné remplacé, ni auteur d'une attestation EPI, ne peut revenir
  -- par un descendant de la chaîne. L'ascendance récursive couvre aussi
  -- EPI(A) -> remplacement B -> no-show(B) -> remplacement C.
  IF v_mission.remplacement_de_mission_id IS NOT NULL
     AND EXISTS (
       WITH RECURSIVE ascendance AS (
         SELECT m.id, m.soignant_assigne_id, m.remplacement_de_mission_id
         FROM public.missions m
         WHERE m.id = v_mission.remplacement_de_mission_id
         UNION
         SELECT parent.id, parent.soignant_assigne_id,
                parent.remplacement_de_mission_id
         FROM public.missions parent
         JOIN ascendance enfant
           ON parent.id = enfant.remplacement_de_mission_id
       )
       SELECT 1
       FROM ascendance a
       WHERE a.soignant_assigne_id = p_soignant_id
          OR EXISTS (
            SELECT 1
            FROM public.journaux_audit ja
            WHERE ja.acteur_id = p_soignant_id
              AND ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
              AND ja.type_ressource = 'mission'
              AND ja.id_ressource = a.id
          )
     ) THEN
    RETURN false;
  END IF;

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

REVOKE ALL ON FUNCTION public.fn_soignant_eligible_mission(uuid, uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_soignant_eligible_mission(uuid, uuid, boolean)
  TO service_role;

-- Une mission originale ne peut ouvrir qu'un seul remplacement direct. Les
-- remplacements en chaîne restent possibles (un enfant peut devenir l'original
-- du suivant), mais deux workers concurrents ne peuvent plus publier deux
-- missions pour le même créneau.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_missions_remplacement_direct
  ON public.missions (remplacement_de_mission_id)
  WHERE remplacement_de_mission_id IS NOT NULL;

-- Un client PostgreSQL peut définir un custom GUC. Le marqueur brut n'est donc
-- jamais, seul, une autorisation. Ce trigger est alphabétiquement le premier
-- BEFORE trigger de missions : il valide les mutations brutes, efface toute
-- pseudo-validation fournie par le client, puis pose un sceau transactionnel
-- consommé par les gardes historiques plus tard dans la chaîne.
CREATE OR REPLACE FUNCTION private.fn_guard_contexte_empechement_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, auth
AS $function$
DECLARE
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
  v_expected text;
  v_original public.missions%ROWTYPE;
BEGIN
  PERFORM set_config('jolene.empechement_mission_validated', '', true);
  IF v_context = '' OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    v_expected := 'FLAG:' || OLD.id::text || ':' || auth.uid()::text;
    IF v_context = v_expected
       AND OLD.id = NEW.id
       AND OLD.soignant_assigne_id = auth.uid()
       AND OLD.statut IN ('ASSIGNEE', 'EN_COURS')
       AND COALESCE(OLD.est_arret_maladie, false) IS FALSE
       AND NEW.est_arret_maladie IS TRUE
       AND NEW.arret_maladie_declare_le IS NOT NULL
       AND (
         to_jsonb(NEW) - ARRAY[
           'est_arret_maladie', 'arret_maladie_declare_le', 'modifie_le'
         ]::text[]
       ) = (
         to_jsonb(OLD) - ARRAY[
           'est_arret_maladie', 'arret_maladie_declare_le', 'modifie_le'
         ]::text[]
       ) THEN
      PERFORM set_config(
        'jolene.empechement_mission_validated', v_context, true
      );
      RETURN NEW;
    END IF;

    v_expected := 'CLOSE:' || OLD.id::text || ':' || auth.uid()::text;
    IF v_context = v_expected
       AND OLD.id = NEW.id
       AND OLD.soignant_assigne_id = auth.uid()
       AND OLD.statut = 'ASSIGNEE'
       AND OLD.debut_le > now()
       AND OLD.est_arret_maladie IS TRUE
       AND NEW.statut = 'ANNULEE_PAR_SOIGNANT'
       AND (
         to_jsonb(NEW) - ARRAY[
           'statut', 'modifie_le'
         ]::text[]
       ) = (
         to_jsonb(OLD) - ARRAY[
           'statut', 'modifie_le'
         ]::text[]
       ) THEN
      PERFORM set_config(
        'jolene.empechement_mission_validated', v_context, true
      );
      RETURN NEW;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.remplacement_de_mission_id IS NOT NULL THEN
    SELECT *
      INTO v_original
      FROM public.missions
     WHERE id = NEW.remplacement_de_mission_id;

    IF FOUND THEN
      v_expected := 'REPLACEMENT:' || v_original.id::text || ':' || auth.uid()::text;
      IF v_context = v_expected
         AND v_original.soignant_assigne_id = auth.uid()
         AND (
           v_original.statut = 'EN_COURS'
           OR (
             v_original.statut = 'ASSIGNEE'
             AND v_original.debut_le <= now()
           )
           OR (
             v_original.statut = 'ANNULEE_PAR_SOIGNANT'
             AND v_original.debut_le > now()
           )
         )
         AND v_original.fin_le > now() + interval '1 hour'
         AND v_original.garantie_remplacement IS TRUE
         AND v_original.est_arret_maladie IS TRUE
         AND NEW.etablissement_id = v_original.etablissement_id
         AND NEW.intitule = 'REMPLACEMENT URGENT — ' || v_original.intitule
         AND NEW.description = COALESCE(v_original.description, '')
           || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]'
         AND NEW.service IS NOT DISTINCT FROM v_original.service
         AND NEW.profession_requise = v_original.profession_requise
         AND NEW.specialite_medicale_requise
               IS NOT DISTINCT FROM v_original.specialite_medicale_requise
         AND NEW.accepte_non_specialises
               IS NOT DISTINCT FROM v_original.accepte_non_specialises
         AND NEW.debut_le = GREATEST(
           v_original.debut_le, now() + interval '15 minutes'
         )
         AND NEW.fin_le = v_original.fin_le
         AND NEW.duree_heures = round(extract(epoch FROM (
           v_original.fin_le - GREATEST(
             v_original.debut_le, now() + interval '15 minutes'
           )
         )) / 3600.0, 2)
         AND NEW.taux_horaire_base = v_original.taux_horaire_base
         AND NEW.type_contrat_recherche = v_original.type_contrat_recherche
         AND NEW.mode_remuneration = v_original.mode_remuneration
         AND NEW.retrocession_pct IS NOT DISTINCT FROM v_original.retrocession_pct
         AND NEW.mission_source = 'REMPLACEMENT'
         AND NEW.statut = 'OUVERTE'
         AND NEW.soignant_assigne_id IS NULL
         AND NEW.mode_attribution = 'PREMIER_ARRIVE'
         AND NEW.est_urgente IS TRUE
         AND NEW.niveau_urgence = 3
         AND NEW.garantie_remplacement IS TRUE
         AND NEW.remplacement_de_mission_id = v_original.id THEN
        PERFORM set_config(
          'jolene.empechement_mission_validated', v_context, true
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_guard_contexte_empechement_mission()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS dec_00_guard_empechement ON public.missions;
CREATE TRIGGER dec_00_guard_empechement
  BEFORE INSERT OR UPDATE ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION private.fn_guard_contexte_empechement_mission();

-- La protection métier laisse passer uniquement une CLOSE déjà validée par
-- dec_00_guard_empechement. Toutes les autres mutations conservent exactement
-- les protections Lot 21 existantes.
CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
BEGIN
  -- Conserver le bypass étroit du helper de seed E2E installé le 10/07/2026.
  -- Sans cet early-return, la présente redéfinition rendrait de nouveau
  -- fn_test_update_mission silencieusement inopérant pour service_role.
  IF current_setting('app.test_bypass_protections', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF current_setting('jolene.assignment_rpc_soignant_id', true) = COALESCE(NEW.soignant_assigne_id::text, '')
     AND OLD.statut = 'OUVERTE'
     AND NEW.statut = 'ASSIGNEE'
     AND OLD.soignant_assigne_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_context = COALESCE(
       current_setting('jolene.empechement_mission_validated', true), ''
     )
     AND v_context = 'CLOSE:' || OLD.id::text || ':' || auth.uid()::text THEN
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

-- Une annulation justifiée est bien historisée comme telle, mais elle ne doit
-- jamais emprunter le chemin de désistement ordinaire qui retire jusqu'à 25
-- points et rouvre la même ligne. Le garde dec_00 a déjà validé l'unique
-- mutation CLOSE autorisée ; hors de ce sceau, le comportement historique est
-- conservé à l'identique.
CREATE OR REPLACE FUNCTION public.dec_penalite_annulation_tardive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_heures_avant numeric;
  v_penalite integer;
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
BEGIN
  IF v_context = COALESCE(
       current_setting('jolene.empechement_mission_validated', true), ''
     )
     AND v_context = 'CLOSE:' || OLD.id::text || ':' || auth.uid()::text
     AND OLD.statut = 'ASSIGNEE'
     AND NEW.statut = 'ANNULEE_PAR_SOIGNANT'
     AND OLD.est_arret_maladie IS TRUE THEN
    RETURN NEW;
  END IF;

  IF NEW.statut = 'ANNULEE_PAR_SOIGNANT' AND OLD.statut = 'ASSIGNEE' THEN
    v_heures_avant := extract(epoch FROM (OLD.debut_le - now())) / 3600;
    IF v_heures_avant < 4 THEN
      v_penalite := 25;
    ELSIF v_heures_avant < 24 THEN
      v_penalite := 15;
    ELSE
      v_penalite := 8;
    END IF;

    UPDATE public.soignants
       SET score_fiabilite = greatest(0, score_fiabilite - v_penalite),
           total_missions_annulees = total_missions_annulees + 1,
           modifie_le = now()
     WHERE id = OLD.soignant_assigne_id;

    NEW.soignant_assigne_id := NULL;
    NEW.statut := 'OUVERTE';
  END IF;
  RETURN NEW;
END;
$function$;

-- Les notifications spécialisées de l'attestation sont écrites par la RPC.
-- Ne pas les doubler par le message d'annulation générique du vieux trigger.
CREATE OR REPLACE FUNCTION public.dec_notifier_changement_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_nom text;
  v_soignant_nom text;
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
BEGIN
  IF v_context = COALESCE(
       current_setting('jolene.empechement_mission_validated', true), ''
     )
     AND v_context = 'CLOSE:' || OLD.id::text || ':' || auth.uid()::text THEN
    RETURN NEW;
  END IF;

  SELECT nom INTO v_etab_nom
  FROM public.etablissements WHERE id = NEW.etablissement_id;

  IF NEW.statut = 'ASSIGNEE'
     AND (OLD.statut IS NULL OR OLD.statut = 'OUVERTE') THEN
    SELECT COALESCE(prenom, '') || ' ' || COALESCE(nom, '')
      INTO v_soignant_nom
      FROM public.soignants WHERE id = NEW.soignant_assigne_id;
    PERFORM public.fn_creer_notification(
      NEW.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_ACCEPTEE',
      'Mission acceptée',
      COALESCE(v_soignant_nom, 'Un soignant') || ' a accepté la mission "'
        || COALESCE(NEW.intitule, 'Mission') || '".',
      '/etablissement/missions/' || NEW.id::text, 'mission', NEW.id
    );
  END IF;

  IF NEW.statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')
     AND OLD.statut NOT IN (
       'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT'
     ) THEN
    IF NEW.soignant_assigne_id IS NOT NULL THEN
      PERFORM public.fn_creer_notification(
        NEW.soignant_assigne_id, 'SOIGNANT', 'MISSION_ANNULEE',
        'Mission annulée',
        'La mission "' || COALESCE(NEW.intitule, 'Mission') || '" chez '
          || COALESCE(v_etab_nom, 'un établissement') || ' a été annulée.',
        '/soignant/missions', 'mission', NEW.id
      );
    END IF;
    PERFORM public.fn_creer_notification(
      NEW.etablissement_id, 'ETABLISSEMENT', 'MISSION_ANNULEE',
      'Mission annulée',
      'La mission "' || COALESCE(NEW.intitule, 'Mission')
        || '" a été annulée.',
      '/etablissement/missions/' || NEW.id::text, 'mission', NEW.id
    );
  END IF;

  IF NEW.statut = 'TERMINEE' AND OLD.statut <> 'TERMINEE'
     AND NEW.soignant_assigne_id IS NOT NULL THEN
    PERFORM public.fn_creer_notification(
      NEW.soignant_assigne_id, 'SOIGNANT', 'MISSION_TERMINEE',
      'Mission terminée',
      'Votre mission "' || COALESCE(NEW.intitule, 'Mission') || '" chez '
        || COALESCE(v_etab_nom, 'un établissement') || ' est terminée.',
      '/soignant/missions', 'mission', NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$;

-- Le RBAC établissement protège aussi les rares profils ayant simultanément
-- un compte soignant et une appartenance établissement. Il ne doit accepter le
-- parcours empêchement que si le premier trigger a validé la phase exacte.
CREATE OR REPLACE FUNCTION public.fn_enforce_etablissement_rbac_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_row jsonb;
  v_old_row jsonb;
  v_new_row jsonb;
  v_etab_id uuid;
  v_mission_id uuid;
  v_permission text := TG_ARGV[0];
  v_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_TABLE_NAME = 'missions'
     AND v_context <> ''
     AND v_context = COALESCE(
       current_setting('jolene.empechement_mission_validated', true), ''
     )
     AND (
       (
         TG_OP = 'UPDATE'
         AND v_context IN (
           'FLAG:' || (to_jsonb(OLD)->>'id') || ':' || auth.uid()::text,
           'CLOSE:' || (to_jsonb(OLD)->>'id') || ':' || auth.uid()::text
         )
       )
       OR (
         TG_OP = 'INSERT'
         AND to_jsonb(NEW)->>'remplacement_de_mission_id' IS NOT NULL
         AND v_context = 'REPLACEMENT:'
           || (to_jsonb(NEW)->>'remplacement_de_mission_id')
           || ':' || auth.uid()::text
       )
     ) THEN
    RETURN NEW;
  END IF;

  -- Conserver les transitions Lot 21 protégées par
  -- fn_protect_candidature_statut. Un soignant peut répondre à sa propre
  -- proposition, y compris pour un profil aussi membre d'un établissement.
  IF TG_TABLE_NAME = 'candidatures' THEN
    v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    IF v_row ->> 'soignant_id' = auth.uid()::text
       OR current_setting('jolene.candidature_rpc_mission_id', true)
            = v_row ->> 'mission_id' THEN
      IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
  END IF;

  IF public.fn_role_etablissement_courant(NULL) IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  IF TG_OP = 'UPDATE' THEN
    v_old_row := to_jsonb(OLD);
    v_new_row := to_jsonb(NEW);
  END IF;
  IF COALESCE(v_row ->> 'etablissement_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_etab_id := (v_row ->> 'etablissement_id')::uuid;
  END IF;
  IF v_etab_id IS NULL
     AND COALESCE(v_row ->> 'mission_id', '') ~ '^[0-9a-fA-F-]{36}$' THEN
    v_mission_id := (v_row ->> 'mission_id')::uuid;
    SELECT m.etablissement_id INTO v_etab_id
    FROM public.missions m WHERE m.id = v_mission_id;
  END IF;

  IF v_etab_id IS NOT NULL
     AND v_permission = 'missions'
     AND TG_TABLE_NAME = 'missions'
     AND TG_OP = 'UPDATE'
     AND public.fn_a_permission_etablissement('pointage', v_etab_id)
     AND (
       v_new_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) = (
       v_old_row - ARRAY[
         'code_arrivee', 'code_depart', 'code_pointage_actif',
         'code_pointage_hmac', 'prochain_type_scan', 'nb_scans',
         'presence_confirmee_le', 'modifie_le'
       ]::text[]
     ) THEN
    RETURN NEW;
  END IF;

  IF v_etab_id IS NULL
     OR NOT public.fn_a_permission_etablissement(v_permission, v_etab_id) THEN
    RAISE EXCEPTION 'Permission etablissement % requise', v_permission
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_enforce_etablissement_rbac_trigger()
  FROM PUBLIC, anon, authenticated;

-- Une garantie ne peut pas contourner les gates légales d'onboarding. La RPC
-- prévérifie le blocage et bascule en revue admin plutôt que de publier une
-- mission pour un établissement suspendu ou non vérifié.
CREATE OR REPLACE FUNCTION public.fn_trg_verifier_onboarding_etab()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_blocage jsonb;
BEGIN
  IF public.est_admin() OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  v_blocage := public.fn_blocage_publication_etab(NEW.etablissement_id);
  IF v_blocage IS NOT NULL THEN
    RAISE EXCEPTION '%', COALESCE(
      v_blocage->>'message', v_blocage->>'error',
      'Publication de mission interdite'
    ) USING ERRCODE = 'check_violation', DETAIL = v_blocage::text;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_verifier_onboarding_etab()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_verifier_onboarding_etab()
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_bloquer_si_facture_impayee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_nb_impayees integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT count(*) INTO v_nb_impayees
    FROM public.factures
    WHERE etablissement_id = NEW.etablissement_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND date_echeance < current_date;

    IF v_nb_impayees > 0 AND NOT public.est_admin() THEN
      RAISE EXCEPTION
        'Vous avez % facture(s) échue(s) impayée(s) : les nouvelles publications sont suspendues (vos missions en cours ne sont pas affectées). Régularisez depuis Facturation pour republier.',
        v_nb_impayees;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Une mission de remplacement est déjà diffusée par le trigger urgent : le
-- trigger favoris ne doit pas envoyer une seconde campagne. Pour les nouvelles
-- missions ordinaires, il réutilise désormais l'éligibilité canonique (dont le
-- cloisonnement réel/démo) et neutralise les appels réseau en mode test.
CREATE OR REPLACE FUNCTION public.fn_trg_favori_nouvelle_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab record;
  v_soignant_id uuid;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
BEGIN
  IF TG_OP <> 'INSERT'
     OR NEW.statut <> 'OUVERTE'
     OR NEW.remplacement_de_mission_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id, nom, adresse_ville
  INTO v_etab
  FROM public.etablissements
  WHERE id = NEW.etablissement_id;

  BEGIN
    v_token := (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'service_role_key'
      LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN
    v_token := NULL;
  END;
  IF COALESCE(current_setting('app.test_mode', true), '') = 'true' THEN
    v_token := NULL;
  END IF;

  FOR v_soignant_id IN
    SELECT f.soignant_id
    FROM public.favoris_soignant_etab f
    JOIN public.soignants s
      ON s.id = f.soignant_id
     AND s.supprime_le IS NULL
    WHERE f.etablissement_id = NEW.etablissement_id
      AND public.fn_soignant_eligible_mission(s.id, NEW.id, false)
  LOOP
    IF public.fn_doit_notifier(
      v_soignant_id,
      'FAVORI_NOUVELLE_MISSION'::type_evenement_notification,
      'IN_APP'::canal_notification
    ) THEN
      INSERT INTO public.notifications (
        destinataire_id, type_destinataire, type, titre, corps, lien,
        type_ressource, id_ressource
      ) VALUES (
        v_soignant_id,
        'SOIGNANT',
        'FAVORI_NOUVELLE_MISSION',
        '⭐ Nouvelle mission chez ' || v_etab.nom,
        v_etab.nom || ' a publié "'
          || COALESCE(NEW.intitule, NEW.profession_requise::text)
          || '" à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
          || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h.',
        '/soignant/missions/' || NEW.id::text,
        'mission',
        NEW.id
      );
    END IF;

    IF v_token IS NOT NULL
       AND public.fn_doit_notifier(
         v_soignant_id,
         'FAVORI_NOUVELLE_MISSION'::type_evenement_notification,
         'EMAIL'::canal_notification
       ) THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_token
          ),
          body := jsonb_build_object(
            'type', 'FAVORI_NOUVELLE_MISSION',
            'destinataire_id', v_soignant_id,
            'data', jsonb_build_object(
              'mission_id', NEW.id,
              'mission_intitule', NEW.intitule,
              'etab_nom', v_etab.nom,
              'etab_ville', v_etab.adresse_ville,
              'taux_horaire', NEW.taux_horaire_base,
              'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_diffuser_pool_urgence_interne(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- La surface publique conserve exactement son autorisation établissement/admin.
CREATE OR REPLACE FUNCTION public.fn_diffuser_pool_urgence(p_mission_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_etablissement_id uuid;
BEGIN
  SELECT m.etablissement_id
  INTO v_etablissement_id
  FROM public.missions m
  WHERE m.id = p_mission_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF NOT (
    public.est_admin()
    OR v_etablissement_id = public.mon_etablissement_id()
  ) THEN
    RETURN 0;
  END IF;

  RETURN private.fn_diffuser_pool_urgence_interne(p_mission_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_diffuser_pool_urgence(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_diffuser_pool_urgence(uuid)
  TO authenticated, service_role;

-- Le trigger urgent est l'unique propriétaire du fan-out lors de la transition
-- ASSIGNEE -> OUVERTE. Ce trigger ajoute seulement l'information établissement
-- afin d'éviter deux notifications différentes envoyées aux mêmes soignants.
CREATE OR REPLACE FUNCTION public.fn_trg_desistement_garanti()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
BEGIN
  IF OLD.statut = 'ASSIGNEE'
     AND NEW.statut = 'OUVERTE'
     AND NEW.garantie_remplacement IS TRUE
     AND NEW.est_arret_maladie IS NOT TRUE
     AND NEW.debut_le < now() + interval '48 hours'
     AND NEW.debut_le > now() - interval '4 hours' THEN
    -- Une mission déjà urgente est diffusée par trg_auto_notify_mission_urgente.
    -- Pour un désistement garanti non urgent, ce helper assure le fan-out qui
    -- manquerait autrement. Les deux chemins restent mutuellement exclusifs.
    IF COALESCE(NEW.est_urgente, false) IS NOT TRUE THEN
      PERFORM private.fn_diffuser_pool_urgence_interne(NEW.id);
    END IF;
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      NEW.etablissement_id,
      'SYSTEM',
      'Désistement — pool urgence alerté 🚨',
      'Le soignant s''est désisté de "'
        || public.fn_html_escape(NEW.intitule)
        || '" à moins de 48h du début. Garantie remplacement : le pool '
        || 'd''urgence vient d''être alerté automatiquement.',
      '/etablissement/missions/' || NEW.id,
      'ETABLISSEMENT'
    );
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_desistement_garanti()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_desistement_garanti()
  TO service_role;

-- ---------------------------------------------------------------------------
-- Finance : aucun débit/release/facture sur une mission interrompue
-- ---------------------------------------------------------------------------

-- La sélection seule ne suffit pas : la mission peut changer entre le cron et
-- Stripe. Elle est néanmoins le premier filtre, strictement lié à l'assigné.
CREATE OR REPLACE FUNCTION public.fn_escrow_debits_a_echeance(
  p_limit integer DEFAULT 50
)
RETURNS SETOF public.paiements_escrow
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT pe.*
  FROM public.paiements_escrow pe
  JOIN public.missions m
    ON m.id = pe.mission_id
   AND m.etablissement_id = pe.etablissement_id
   AND m.soignant_assigne_id = pe.soignant_id
  WHERE pe.statut = 'INITIE'
    AND pe.debit_prevu_le <= now()
    AND pe.tentatives_debit < 3
    AND m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND COALESCE(m.est_arret_maladie, false) IS FALSE
    AND NOT EXISTS (
      SELECT 1 FROM public.missions r
      WHERE r.remplacement_de_mission_id = m.id
    )
  ORDER BY pe.debit_prevu_le, pe.id
  LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_debits_a_echeance(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_debits_a_echeance(integer)
  TO service_role;

-- Claim atomique juste avant la création d'un PaymentIntent. Le verrou de la
-- mission sérialise ce claim avec fn_declarer_empechement_imperieux : soit le
-- débit est réservé et la déclaration s'arrête, soit l'attestation gagne et le
-- worker ne peut plus débiter.
CREATE OR REPLACE FUNCTION public.fn_escrow_reserver_tentative_debit(
  p_paiement_escrow_id uuid,
  p_tentatives_attendues integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_rows integer;
  v_autorise boolean;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  SELECT (
      pe.statut = 'INITIE'
      AND pe.tentatives_debit = COALESCE(p_tentatives_attendues, 0)
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND m.soignant_assigne_id = pe.soignant_id
      AND m.etablissement_id = pe.etablissement_id
      AND COALESCE(m.est_arret_maladie, false) IS FALSE
      AND NOT EXISTS (
        SELECT 1 FROM public.missions r
        WHERE r.remplacement_de_mission_id = m.id
      )
    )
    INTO v_autorise
  FROM public.paiements_escrow pe
  JOIN public.missions m ON m.id = pe.mission_id
  WHERE pe.id = p_paiement_escrow_id
  FOR UPDATE OF m, pe;

  IF COALESCE(v_autorise, false) IS NOT TRUE THEN
    RETURN false;
  END IF;

  UPDATE public.paiements_escrow
     SET tentatives_debit = tentatives_debit + 1,
         derniere_tentative_le = now(),
         modifie_le = now()
   WHERE id = p_paiement_escrow_id
     AND statut = 'INITIE'
     AND tentatives_debit = COALESCE(p_tentatives_attendues, 0);
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_reserver_tentative_debit(uuid, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_reserver_tentative_debit(uuid, integer)
  TO service_role;

-- Un RELEASE_PLANIFIE reste toujours récupérable : Stripe a peut-être déjà
-- reçu l'appel. En revanche un nouveau payout DEBITE n'est sélectionné que
-- pour une mission terminée, le même soignant et des présences validées.
CREATE OR REPLACE FUNCTION public.fn_escrow_releases_a_traiter(
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  queue_id uuid,
  paiement_escrow_id uuid,
  mission_id uuid,
  soignant_id uuid,
  etablissement_id uuid,
  honoraires_cents integer,
  escrow_statut text,
  tentatives integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT q.id, q.paiement_escrow_id, q.mission_id,
         pe.soignant_id, pe.etablissement_id, pe.honoraires_cents,
         pe.statut, q.tentatives
  FROM public.escrow_release_queue q
  JOIN public.paiements_escrow pe
    ON pe.id = q.paiement_escrow_id
   AND pe.mission_id = q.mission_id
  LEFT JOIN public.missions m ON m.id = pe.mission_id
  WHERE q.statut IN ('EN_ATTENTE', 'EN_COURS')
    AND q.prochaine_tentative_le <= now()
    AND (
      pe.statut = 'RELEASE_PLANIFIE'
      OR (
        pe.statut = 'DEBITE'
        AND q.tentatives < 5
        AND m.statut = 'TERMINEE'
        AND m.soignant_assigne_id = pe.soignant_id
        AND m.etablissement_id = pe.etablissement_id
        AND COALESCE(m.est_arret_maladie, false) IS FALSE
        AND NOT EXISTS (
          SELECT 1 FROM public.missions r
          WHERE r.remplacement_de_mission_id = m.id
        )
        AND EXISTS (
          SELECT 1 FROM public.presences p
          WHERE p.mission_id = m.id
            AND COALESCE(p.valide_par_etablissement, false) IS TRUE
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.presences p
          WHERE p.mission_id = m.id
            AND COALESCE(p.valide_par_etablissement, false) IS FALSE
            AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
        )
      )
    )
  ORDER BY q.prochaine_tentative_le, q.id
  LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_releases_a_traiter(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_releases_a_traiter(integer)
  TO service_role;

-- Réservation atomique juste avant payouts.create. Une fois RELEASE_PLANIFIE,
-- le worker suit obligatoirement son chemin de réconciliation ; il ne rétrograde
-- jamais une ambiguïté Stripe.
CREATE OR REPLACE FUNCTION public.fn_escrow_reserver_release(
  p_queue_id uuid,
  p_paiement_escrow_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_autorise boolean;
  v_rows integer;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  SELECT (
      q.statut IN ('EN_ATTENTE', 'EN_COURS')
      AND pe.statut = 'DEBITE'
      AND q.mission_id = pe.mission_id
      AND m.statut = 'TERMINEE'
      AND m.soignant_assigne_id = pe.soignant_id
      AND m.etablissement_id = pe.etablissement_id
      AND COALESCE(m.est_arret_maladie, false) IS FALSE
      AND NOT EXISTS (
        SELECT 1 FROM public.missions r
        WHERE r.remplacement_de_mission_id = m.id
      )
      AND EXISTS (
        SELECT 1 FROM public.presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) IS TRUE
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) IS FALSE
          AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
      )
    )
    INTO v_autorise
  FROM public.escrow_release_queue q
  JOIN public.paiements_escrow pe ON pe.id = q.paiement_escrow_id
  JOIN public.missions m ON m.id = pe.mission_id
  WHERE q.id = p_queue_id
    AND pe.id = p_paiement_escrow_id
  FOR UPDATE OF q, pe, m;

  IF COALESCE(v_autorise, false) IS NOT TRUE THEN
    RETURN false;
  END IF;

  UPDATE public.paiements_escrow
     SET statut = 'RELEASE_PLANIFIE',
         available_on = now(),
         disponible_le = now(),
         release_planifie_le = now(),
         modifie_le = now()
   WHERE id = p_paiement_escrow_id
     AND statut = 'DEBITE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_reserver_release(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_reserver_release(uuid, uuid)
  TO service_role;

-- Les trois ordres possibles (validation, débit, TERMINEE) convergent vers la
-- même file idempotente, mais uniquement lorsque les trois gates sont vrais.
CREATE OR REPLACE FUNCTION public.fn_trg_escrow_release_check()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_escrow_id uuid;
BEGIN
  SELECT pe.id INTO v_escrow_id
  FROM public.paiements_escrow pe
  JOIN public.missions m
    ON m.id = pe.mission_id
   AND m.soignant_assigne_id = pe.soignant_id
   AND m.etablissement_id = pe.etablissement_id
  WHERE pe.mission_id = NEW.mission_id
    AND pe.statut = 'DEBITE'
    AND m.statut = 'TERMINEE'
    AND COALESCE(m.est_arret_maladie, false) IS FALSE
    AND NOT EXISTS (
      SELECT 1 FROM public.missions r
      WHERE r.remplacement_de_mission_id = m.id
    );
  IF v_escrow_id IS NULL THEN RETURN NEW; END IF;

  IF EXISTS (
    SELECT 1 FROM public.presences p
    WHERE p.mission_id = NEW.mission_id
      AND COALESCE(p.valide_par_etablissement, false) IS FALSE
      AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
  ) THEN RETURN NEW; END IF;

  INSERT INTO public.escrow_release_queue (paiement_escrow_id, mission_id)
  VALUES (v_escrow_id, NEW.mission_id)
  ON CONFLICT (paiement_escrow_id) DO NOTHING;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_escrow_enqueue_on_debite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.statut <> 'DEBITE' OR NEW.statut = OLD.statut THEN RETURN NEW; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.id = NEW.mission_id
      AND m.statut = 'TERMINEE'
      AND m.soignant_assigne_id = NEW.soignant_id
      AND m.etablissement_id = NEW.etablissement_id
      AND COALESCE(m.est_arret_maladie, false) IS FALSE
      AND NOT EXISTS (
        SELECT 1 FROM public.missions r
        WHERE r.remplacement_de_mission_id = m.id
      )
  ) THEN RETURN NEW; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.presences p
    WHERE p.mission_id = NEW.mission_id
      AND COALESCE(p.valide_par_etablissement, false) IS TRUE
  ) OR EXISTS (
    SELECT 1 FROM public.presences p
    WHERE p.mission_id = NEW.mission_id
      AND COALESCE(p.valide_par_etablissement, false) IS FALSE
      AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
  ) THEN RETURN NEW; END IF;

  INSERT INTO public.escrow_release_queue (paiement_escrow_id, mission_id)
  VALUES (NEW.id, NEW.mission_id)
  ON CONFLICT (paiement_escrow_id) DO NOTHING;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_escrow_enqueue_on_terminee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_escrow_id uuid;
BEGIN
  IF NEW.statut <> 'TERMINEE' OR OLD.statut = 'TERMINEE'
     OR NEW.soignant_assigne_id IS NULL
     OR COALESCE(NEW.est_arret_maladie, false) IS TRUE
     OR EXISTS (
       SELECT 1 FROM public.missions r
       WHERE r.remplacement_de_mission_id = NEW.id
     ) THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.presences p
    WHERE p.mission_id = NEW.id
      AND COALESCE(p.valide_par_etablissement, false) IS TRUE
  ) OR EXISTS (
    SELECT 1 FROM public.presences p
    WHERE p.mission_id = NEW.id
      AND COALESCE(p.valide_par_etablissement, false) IS FALSE
      AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
  ) THEN RETURN NEW; END IF;

  SELECT pe.id INTO v_escrow_id
  FROM public.paiements_escrow pe
  WHERE pe.mission_id = NEW.id
    AND pe.soignant_id = NEW.soignant_assigne_id
    AND pe.etablissement_id = NEW.etablissement_id
    AND pe.statut = 'DEBITE';
  IF v_escrow_id IS NOT NULL THEN
    INSERT INTO public.escrow_release_queue (paiement_escrow_id, mission_id)
    VALUES (v_escrow_id, NEW.id)
    ON CONFLICT (paiement_escrow_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_escrow_release_on_terminee ON public.missions;
CREATE TRIGGER trg_escrow_release_on_terminee
  AFTER UPDATE OF statut ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_escrow_enqueue_on_terminee();

-- Aucun chemin (cron, admin, service_role ou client) ne peut transformer une
-- interruption en TERMINEE avant qu'un futur flux dédié ait réconcilié les
-- heures effectives. Lever une exception ici évite bulletin, cotisations,
-- facture, transfer et payout calculés sur la durée planifiée complète.
CREATE OR REPLACE FUNCTION private.fn_bloquer_cloture_empechement_non_reconcilie()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF OLD.est_arret_maladie IS TRUE
     AND OLD.statut IS DISTINCT FROM 'TERMINEE'
     AND NEW.statut = 'TERMINEE' THEN
    RAISE EXCEPTION
      'Mission interrompue : validation admin des heures effectives requise avant clôture.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_bloquer_cloture_empechement_non_reconcilie()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_00_bloquer_cloture_empechement ON public.missions;
CREATE TRIGGER trg_00_bloquer_cloture_empechement
  BEFORE UPDATE OF statut ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION private.fn_bloquer_cloture_empechement_non_reconcilie();

CREATE OR REPLACE FUNCTION public.fn_auto_terminer_missions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.missions
     SET statut = 'TERMINEE', modifie_le = now()
   WHERE statut = 'EN_COURS'
     AND fin_le < now() - interval '15 minutes'
     AND COALESCE(est_arret_maladie, false) IS FALSE;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'missions_terminees', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_auto_transitions_missions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_assignee_to_en_cours integer := 0;
  v_assignee_to_terminee integer := 0;
  v_en_cours_to_terminee integer := 0;
  v_ouverte_to_expiree integer := 0;
  v_candidatures_refusees integer := 0;
  v_rows integer;
  v_mission record;
BEGIN
  UPDATE public.missions
     SET statut = 'EN_COURS', modifie_le = now()
   WHERE statut = 'ASSIGNEE'
     AND debut_le <= now()
     AND fin_le > now()
     AND COALESCE(est_arret_maladie, false) IS FALSE;
  GET DIAGNOSTICS v_assignee_to_en_cours = ROW_COUNT;

  UPDATE public.missions
     SET statut = 'TERMINEE', modifie_le = now()
   WHERE statut = 'ASSIGNEE'
     AND fin_le < now() - interval '15 minutes'
     AND COALESCE(est_arret_maladie, false) IS FALSE;
  GET DIAGNOSTICS v_assignee_to_terminee = ROW_COUNT;

  UPDATE public.missions
     SET statut = 'TERMINEE', modifie_le = now()
   WHERE statut = 'EN_COURS'
     AND fin_le < now() - interval '15 minutes'
     AND COALESCE(est_arret_maladie, false) IS FALSE;
  GET DIAGNOSTICS v_en_cours_to_terminee = ROW_COUNT;

  FOR v_mission IN
    SELECT id, intitule, etablissement_id, debut_le
    FROM public.missions
    WHERE statut = 'OUVERTE'
      AND debut_le < now() - interval '1 hour'
  LOOP
    UPDATE public.missions
       SET statut = 'EXPIREE', modifie_le = now()
     WHERE id = v_mission.id;
    v_ouverte_to_expiree := v_ouverte_to_expiree + 1;

    UPDATE public.candidatures
       SET statut = 'REFUSEE',
           motif_refus = 'Mission expiree (non pourvue)',
           traite_le = now()
     WHERE mission_id = v_mission.id
       AND statut IN ('EN_ATTENTE', 'PROPOSEE');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_candidatures_refusees := v_candidatures_refusees + v_rows;

    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      v_mission.etablissement_id, 'ETABLISSEMENT',
      'MISSION_NON_POURVUE', 'Mission expiree (non pourvue)',
      'Votre mission "' || v_mission.intitule
        || '" n''a trouve aucun soignant et est passee en expiree. '
        || 'Vous pouvez la republier depuis votre espace.',
      '/etablissement/missions/' || v_mission.id,
      'mission', v_mission.id
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'assignee_to_en_cours', v_assignee_to_en_cours,
    'assignee_to_terminee', v_assignee_to_terminee,
    'en_cours_to_terminee', v_en_cours_to_terminee,
    'ouverte_to_expiree', v_ouverte_to_expiree,
    'candidatures_refusees', v_candidatures_refusees
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_terminer_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_nb_presences integer;
BEGIN
  SELECT * INTO v_mission
  FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF NOT public.est_admin()
     AND v_mission.etablissement_id <> public.mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_mission.statut <> 'EN_COURS' THEN
    RETURN jsonb_build_object(
      'error', 'La mission doit être EN_COURS pour être terminée. Statut actuel : '
        || v_mission.statut
    );
  END IF;
  IF v_mission.est_arret_maladie IS TRUE THEN
    RETURN jsonb_build_object(
      'error_code', 'RECONCILIATION_HEURES_REQUISE',
      'error', 'Mission interrompue : validation admin des heures effectives requise avant clôture.'
    );
  END IF;
  SELECT count(*) INTO v_nb_presences
  FROM public.presences WHERE mission_id = p_mission_id;
  IF v_nb_presences = 0 AND NOT public.est_admin() THEN
    RETURN jsonb_build_object(
      'error', 'Impossible de terminer : aucune présence enregistrée. Le soignant doit pointer son arrivée et son départ.'
    );
  END IF;
  UPDATE public.missions
     SET statut = 'TERMINEE', terminee_le = now(), modifie_le = now()
   WHERE id = p_mission_id;
  IF v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_mission.soignant_assigne_id, 'SYSTEM', 'Mission terminée ✅',
      'La mission "' || v_mission.intitule
        || '" est terminée. Consultez vos gains.',
      '/soignant/mes-gains', 'SOIGNANT'
    );
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- Défense en profondeur sur le rail manuel, y compris hors escrow.
CREATE OR REPLACE FUNCTION public.fn_trg_bloquer_paiement_manuel_escrow()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.mission_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.id = NEW.mission_id
      AND m.est_arret_maladie IS TRUE
  ) THEN
    RAISE EXCEPTION
      'Mission interrompue : paiement bloqué jusqu''à validation admin des heures effectives.';
  END IF;
  IF NEW.mission_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.paiements_escrow pe
    WHERE pe.mission_id = NEW.mission_id
      AND pe.statut <> 'REMBOURSE'
  ) THEN
    RAISE EXCEPTION
      'Le paiement de cette mission passe par le circuit sécurisé (paiement rapide) : la déclaration manuelle est indisponible.';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_facturer(
  p_today date DEFAULT current_date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_finales jsonb;
  v_hebdo jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'FINALE',
    'mission_id', m.id,
    'soignant_id', m.soignant_assigne_id,
    'etablissement_id', m.etablissement_id,
    'periode_debut', m.debut_le::date,
    'periode_fin', m.fin_le::date,
    'numero_semaine_iso', NULL,
    'annee_iso', NULL,
    'strategie_facturation', m.strategie_facturation::text,
    'est_facture_finale_mission', true
  )), '[]'::jsonb)
  INTO v_finales
  FROM public.missions m
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  WHERE m.statut = 'TERMINEE'
    AND COALESCE(m.est_arret_maladie, false) IS FALSE
    AND m.fin_le::date < p_today
    AND m.type_contrat_applique = 'LIBERAL'
    AND COALESCE(s.mandat_facturation_signe, false) IS TRUE
    AND NOT EXISTS (
      SELECT 1 FROM public.missions r
      WHERE r.remplacement_de_mission_id = m.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.factures_honoraires fh
      WHERE fh.mission_id = m.id
        AND fh.est_facture_finale_mission IS TRUE
        AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    )
    AND EXISTS (
      SELECT 1 FROM public.mission_creneaux mc
      WHERE mc.mission_id = m.id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.presences p
      WHERE p.mission_id = m.id
        AND COALESCE(p.valide_par_etablissement, false) IS FALSE
        AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
    );

  WITH semaines AS (
    SELECT m.id AS mission_id,
           m.soignant_assigne_id,
           m.etablissement_id,
           m.debut_le,
           m.fin_le,
           m.strategie_facturation,
           gs.lundi_semaine
    FROM public.missions m
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    CROSS JOIN LATERAL generate_series(
      date_trunc('week', m.debut_le)::date,
      least(m.fin_le::date, p_today - interval '1 day')::date,
      '7 days'::interval
    ) AS gs(lundi_semaine)
    WHERE m.statut IN ('EN_COURS', 'TERMINEE')
      AND COALESCE(m.est_arret_maladie, false) IS FALSE
      AND m.strategie_facturation = 'HEBDO_ET_FINALE'
      AND m.type_contrat_applique = 'LIBERAL'
      AND COALESCE(s.mandat_facturation_signe, false) IS TRUE
      AND NOT EXISTS (
        SELECT 1 FROM public.missions r
        WHERE r.remplacement_de_mission_id = m.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) IS FALSE
          AND p.motif_litige IS NOT NULL
      )
  ),
  semaines_closes AS (
    SELECT sm.*,
           (sm.lundi_semaine + interval '6 days')::date AS dimanche_semaine,
           extract(week FROM sm.lundi_semaine)::smallint AS num_sem,
           extract(isoyear FROM sm.lundi_semaine)::smallint AS ann_iso,
           greatest(sm.lundi_semaine::date, sm.debut_le::date) AS periode_d,
           least(
             (sm.lundi_semaine + interval '6 days')::date,
             sm.fin_le::date
           ) AS periode_f
    FROM semaines sm
    WHERE (sm.lundi_semaine + interval '6 days')::date < p_today
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'HEBDO',
    'mission_id', sa.mission_id,
    'soignant_id', sa.soignant_assigne_id,
    'etablissement_id', sa.etablissement_id,
    'periode_debut', sa.periode_d,
    'periode_fin', sa.periode_f,
    'numero_semaine_iso', sa.num_sem,
    'annee_iso', sa.ann_iso,
    'strategie_facturation', sa.strategie_facturation::text,
    'est_facture_finale_mission', false
  )), '[]'::jsonb)
  INTO v_hebdo
  FROM semaines_closes sa
  WHERE NOT EXISTS (
    SELECT 1 FROM public.factures_honoraires fh
    WHERE fh.mission_id = sa.mission_id
      AND fh.annee_iso = sa.ann_iso
      AND fh.numero_semaine_iso = sa.num_sem
      AND fh.est_facture_finale_mission IS FALSE
      AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  )
    AND EXISTS (
      SELECT 1 FROM public.mission_creneaux mc
      WHERE mc.mission_id = sa.mission_id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
        AND mc.debut::date <= sa.periode_f
        AND COALESCE(mc.fin::date, mc.debut::date) >= sa.periode_d
    );

  RETURN jsonb_build_object(
    'today', p_today,
    'finales', v_finales,
    'hebdo', v_hebdo,
    'total', jsonb_array_length(v_finales) + jsonb_array_length(v_hebdo)
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Compteurs : inclure durablement les empêchements réellement pénalisés
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.fn_resynchroniser_compteurs_soignant(
  p_soignant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_compteur record;
  v_total_terminees integer := 0;
  v_total_annulees integer := 0;
  v_total_absences integer := 0;
  v_profession text;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true), ''
  );
BEGIN
  IF p_soignant_id IS NULL THEN
    RETURN;
  END IF;

  SELECT s.profession::text
  INTO v_profession
  FROM public.soignants s
  WHERE s.id = p_soignant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT *
  INTO v_compteur
  FROM private.fn_heures_exercice_verifiees(p_soignant_id);

  SELECT
    count(*) FILTER (WHERE m.statut = 'TERMINEE')::integer,
    count(*) FILTER (WHERE m.statut = 'ABSENCE')::integer
  INTO v_total_terminees, v_total_absences
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id;

  -- UNION déduplique une mission qui serait à la fois marquée annulée et
  -- journalisée comme empêchement. Le journal immuable conserve la source
  -- lorsque la garantie remet ensuite la mission en OUVERTE/non assignée.
  SELECT count(*)::integer
  INTO v_total_annulees
  FROM (
    SELECT m.id AS mission_id
    FROM public.missions m
    WHERE m.soignant_assigne_id = p_soignant_id
      AND m.statut = 'ANNULEE_PAR_SOIGNANT'
      AND NOT EXISTS (
        SELECT 1
        FROM public.journaux_audit ja_epi
        WHERE ja_epi.acteur_id = p_soignant_id
          AND ja_epi.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
          AND ja_epi.type_ressource = 'mission'
          AND ja_epi.id_ressource = m.id
      )
    UNION
    SELECT ja.id_ressource AS mission_id
    FROM public.journaux_audit ja
    WHERE ja.acteur_id = p_soignant_id
      AND ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
      AND ja.type_ressource = 'mission'
      AND ja.id_ressource IS NOT NULL
      AND ja.details @> '{"depassement": true}'::jsonb
  ) annulations;

  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET total_missions_terminees = v_total_terminees,
      total_missions_annulees = v_total_annulees,
      total_absences = v_total_absences,
      heures_plateforme = v_compteur.heures_jolene,
      heures_cumulees = v_compteur.heures_totales,
      eligible_conversion_3200h = v_compteur.heures_totales >= 3200,
      modifie_le = now()
  WHERE id = p_soignant_id;

  IF EXISTS (
       SELECT 1
       FROM public.professions_liberal_eligible p
       WHERE p.profession::text = v_profession
     )
     OR EXISTS (
       SELECT 1
       FROM public.suivi_conversion_3200h sc
       WHERE sc.soignant_id = p_soignant_id
     ) THEN
    INSERT INTO public.suivi_conversion_3200h (
      soignant_id,
      profession_cible_liberal,
      heures_actuelles,
      jalon_800h_atteint,
      jalon_1600h_atteint,
      jalon_2400h_atteint,
      jalon_3200h_atteint,
      modifie_le
    ) VALUES (
      p_soignant_id,
      v_profession,
      v_compteur.heures_totales,
      v_compteur.heures_totales >= 800,
      v_compteur.heures_totales >= 1600,
      v_compteur.heures_totales >= 2400,
      v_compteur.heures_totales >= 3200,
      now()
    )
    ON CONFLICT (soignant_id) DO UPDATE
    SET heures_actuelles = EXCLUDED.heures_actuelles,
        jalon_800h_atteint = EXCLUDED.jalon_800h_atteint,
        jalon_1600h_atteint = EXCLUDED.jalon_1600h_atteint,
        jalon_2400h_atteint = EXCLUDED.jalon_2400h_atteint,
        jalon_3200h_atteint = EXCLUDED.jalon_3200h_atteint,
        modifie_le = EXCLUDED.modifie_le;
  END IF;

  PERFORM set_config(
    'jolene.system_update', v_previous_system_update, true
  );
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config(
    'jolene.system_update', v_previous_system_update, true
  );
  RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_resynchroniser_compteurs_soignant(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Score : réappliquer durablement -8 par dépassement sur les 12 derniers mois
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_calculer_score_fiabilite_v2(p_soignant_id uuid, p_raison text DEFAULT 'recalcul'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_soignant RECORD;
  v_since TIMESTAMPTZ;
  v_total_missions_terminees INT;
  v_notation_etab NUMERIC;
  v_presentisme NUMERIC;
  v_ponctualite NUMERIC;
  v_reactivite NUMERIC;
  v_anciennete_volume NUMERIC;
  v_notation_par_soignant NUMERIC;
  v_p_notation_etab NUMERIC := 35;
  v_p_presentisme NUMERIC := 20;
  v_p_ponctualite NUMERIC := 15;
  v_p_reactivite NUMERIC := 10;
  v_p_anciennete_volume NUMERIC := 10;
  v_p_notation_par_soignant NUMERIC := 10;
  v_pe_notation_etab NUMERIC;
  v_pe_presentisme NUMERIC;
  v_pe_ponctualite NUMERIC;
  v_pe_reactivite NUMERIC;
  v_pe_anciennete_volume NUMERIC;
  v_pe_notation_par_soignant NUMERIC;
  v_total_poids_actifs NUMERIC := 0;
  v_facteur_redistribution NUMERIC := 1;
  v_litiges_malus NUMERIC := 0;
  v_absence_malus NUMERIC := 0;
  v_fraude_gps_malus NUMERIC := 0;
  v_empechement_malus NUMERIC := 0;
  v_bonus_super_actif NUMERIC := 0;
  v_bonus_urgence NUMERIC := 0;
  v_score NUMERIC := 0;
  v_niveau public.niveau_qualitatif;
  v_probatoire BOOLEAN;
  v_actives_count INT := 0;
  v_inactives_json JSONB := '[]'::jsonb;
  v_breakdown_id UUID;
  v_nb_terminees_12m INT;
  v_nb_litiges INT;
  v_nb_absences INT;
  v_nb_decisions_cand INT;
  v_delai_moyen_h NUMERIC;
  v_nb_notations INT;
  v_nb_notations_par_soignant INT;
  v_pct_notations_donnees NUMERIC;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true), ''
  );
BEGIN
  v_since := NOW() - INTERVAL '12 months';

  SELECT id, prevoyance_inscrit INTO v_soignant
  FROM soignants
  WHERE id = p_soignant_id
  FOR UPDATE;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  SELECT COUNT(*) INTO v_total_missions_terminees FROM missions
  WHERE soignant_assigne_id = p_soignant_id AND statut = 'TERMINEE';

  v_probatoire := v_total_missions_terminees < 3;

  SELECT COUNT(*) INTO v_nb_terminees_12m FROM missions
  WHERE soignant_assigne_id = p_soignant_id AND statut = 'TERMINEE' AND fin_le >= v_since;

  -- FIX Finding #3 : double-aveugle — n'agréger que les notes PUBLIÉES
  -- (publie_le IS NOT NULL), comme les 3 autres surfaces. Une note non publiée
  -- ne doit JAMAIS déplacer le score public du soignant avant réciprocité.
  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_etab
  FROM notations_missions
  WHERE note_id = p_soignant_id AND sens = 'ETAB_VERS_SOIGNANT'
    AND cree_le >= v_since AND masque = false AND publie_le IS NOT NULL;

  IF v_nb_notations < 3 OR v_notation_etab IS NULL THEN
    v_notation_etab := NULL;
  ELSE
    v_notation_etab := GREATEST(0, LEAST(100, (v_notation_etab - 1) * 25));
  END IF;

  IF v_nb_terminees_12m < 3 THEN
    v_presentisme := NULL;
  ELSE
    DECLARE v_total_engagements INT;
    BEGIN
      SELECT count(*) INTO v_total_engagements
      FROM missions m_engagement
      WHERE m_engagement.soignant_assigne_id = p_soignant_id
        AND m_engagement.statut IN (
          'TERMINEE', 'ANNULEE_PAR_SOIGNANT', 'ABSENCE'
        )
        AND COALESCE(m_engagement.fin_le, m_engagement.debut_le) >= v_since
        AND NOT (
          m_engagement.statut = 'ANNULEE_PAR_SOIGNANT'
          AND EXISTS (
            SELECT 1
            FROM public.journaux_audit ja_epi
            WHERE ja_epi.acteur_id = p_soignant_id
              AND ja_epi.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
              AND ja_epi.type_ressource = 'mission'
              AND ja_epi.id_ressource = m_engagement.id
          )
        );
      IF v_total_engagements > 0 THEN
        v_presentisme := (v_nb_terminees_12m::NUMERIC / v_total_engagements) * 100;
      ELSE v_presentisme := NULL; END IF;
    END;
  END IF;

  DECLARE v_nb_pointages INT; v_total_score NUMERIC := 0;
  BEGIN
    SELECT COUNT(*),
      SUM(CASE
        WHEN COALESCE(retard_min, 0) <= 0 THEN 100
        WHEN retard_min < 5 THEN 90
        WHEN retard_min < 10 THEN 75
        WHEN retard_min < 30 THEN 50
        ELSE 25
      END)
    INTO v_nb_pointages, v_total_score
    FROM presences p JOIN missions m ON m.id = p.mission_id
    WHERE p.soignant_id = p_soignant_id AND p.pointage_arrivee_le >= v_since AND p.pointage_arrivee_le IS NOT NULL;
    IF v_nb_pointages < 3 THEN v_ponctualite := NULL;
    ELSE v_ponctualite := v_total_score / v_nb_pointages; END IF;
  END;

  SELECT COUNT(*), AVG(EXTRACT(EPOCH FROM (traite_le - cree_le)) / 3600.0)
  INTO v_nb_decisions_cand, v_delai_moyen_h
  FROM candidatures
  WHERE soignant_id = p_soignant_id AND statut IN ('ACCEPTEE','REFUSEE')
    AND traite_le IS NOT NULL AND cree_le >= v_since;

  IF v_nb_decisions_cand < 3 OR v_delai_moyen_h IS NULL THEN
    v_reactivite := NULL;
  ELSE
    v_reactivite := CASE
      WHEN v_delai_moyen_h < 1 THEN 100
      WHEN v_delai_moyen_h < 3 THEN 90
      WHEN v_delai_moyen_h < 12 THEN 80
      WHEN v_delai_moyen_h < 24 THEN 70
      WHEN v_delai_moyen_h < 48 THEN 60
      ELSE 50
    END;
  END IF;

  v_anciennete_volume := CASE
    WHEN v_nb_terminees_12m = 0 THEN 0
    WHEN v_nb_terminees_12m <= 2 THEN 30
    WHEN v_nb_terminees_12m <= 9 THEN 50
    WHEN v_nb_terminees_12m <= 29 THEN 75
    WHEN v_nb_terminees_12m <= 49 THEN 90
    ELSE 100
  END;

  IF v_nb_terminees_12m = 0 THEN
    v_notation_par_soignant := NULL;
  ELSE
    SELECT COUNT(*) INTO v_nb_notations_par_soignant
    FROM notations_missions
    WHERE notateur_id = p_soignant_id AND sens = 'SOIGNANT_VERS_ETAB' AND cree_le >= v_since;
    v_pct_notations_donnees := (v_nb_notations_par_soignant::NUMERIC / v_nb_terminees_12m) * 100;
    v_notation_par_soignant := CASE
      WHEN v_pct_notations_donnees >= 50 THEN 100
      WHEN v_pct_notations_donnees >= 25 THEN 75
      WHEN v_pct_notations_donnees >= 10 THEN 50
      ELSE 0
    END;
  END IF;

  v_total_poids_actifs := 0;
  IF v_notation_etab IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_notation_etab; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','notation_etab_soignant','poids_initial',v_p_notation_etab); END IF;
  IF v_presentisme IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_presentisme; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','presentisme','poids_initial',v_p_presentisme); END IF;
  IF v_ponctualite IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_ponctualite; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','ponctualite','poids_initial',v_p_ponctualite); END IF;
  IF v_reactivite IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_reactivite; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','reactivite','poids_initial',v_p_reactivite); END IF;
  IF v_anciennete_volume IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_anciennete_volume; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','anciennete_volume','poids_initial',v_p_anciennete_volume); END IF;
  IF v_notation_par_soignant IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_notation_par_soignant; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','notation_soignant_etab','poids_initial',v_p_notation_par_soignant); END IF;

  IF v_total_poids_actifs > 0 THEN
    v_facteur_redistribution := 100.0 / v_total_poids_actifs;
  ELSE v_facteur_redistribution := 0; END IF;

  v_pe_notation_etab := CASE WHEN v_notation_etab IS NOT NULL THEN v_p_notation_etab * v_facteur_redistribution ELSE 0 END;
  v_pe_presentisme := CASE WHEN v_presentisme IS NOT NULL THEN v_p_presentisme * v_facteur_redistribution ELSE 0 END;
  v_pe_ponctualite := CASE WHEN v_ponctualite IS NOT NULL THEN v_p_ponctualite * v_facteur_redistribution ELSE 0 END;
  v_pe_reactivite := CASE WHEN v_reactivite IS NOT NULL THEN v_p_reactivite * v_facteur_redistribution ELSE 0 END;
  v_pe_anciennete_volume := CASE WHEN v_anciennete_volume IS NOT NULL THEN v_p_anciennete_volume * v_facteur_redistribution ELSE 0 END;
  v_pe_notation_par_soignant := CASE WHEN v_notation_par_soignant IS NOT NULL THEN v_p_notation_par_soignant * v_facteur_redistribution ELSE 0 END;

  v_score := COALESCE(v_notation_etab, 0) * v_pe_notation_etab / 100
           + COALESCE(v_presentisme, 0) * v_pe_presentisme / 100
           + COALESCE(v_ponctualite, 0) * v_pe_ponctualite / 100
           + COALESCE(v_reactivite, 0) * v_pe_reactivite / 100
           + COALESCE(v_anciennete_volume, 0) * v_pe_anciennete_volume / 100
           + COALESCE(v_notation_par_soignant, 0) * v_pe_notation_par_soignant / 100;

  SELECT LEAST(2, COUNT(*)) * 10 INTO v_nb_litiges
  FROM litiges
  WHERE soignant_id = p_soignant_id
    AND statut IN ('RESOLU_ETABLISSEMENT', 'RESOLU_FAVEUR_ETAB')
    AND COALESCE(resolu_le, NOW()) >= v_since;
  v_litiges_malus := -COALESCE(v_nb_litiges, 0);

  SELECT LEAST(1, COUNT(*)) * 30 INTO v_nb_absences
  FROM missions
  WHERE soignant_assigne_id = p_soignant_id AND statut = 'ABSENCE'
    AND COALESCE(fin_le, debut_le) >= v_since;
  v_absence_malus := -COALESCE(v_nb_absences, 0);

  -- ★ Malus anti-triche GPS : piloté par les événements FRAUDE_GPS non annulés
  --   (points_corriges prime si l'admin a tranché une réclamation). Cap -30.
  SELECT GREATEST(-30, COALESCE(SUM(COALESCE(points_corriges, points)), 0))
  INTO v_fraude_gps_malus
  FROM evenements_score_soignant
  WHERE soignant_id = p_soignant_id AND type_evenement = 'FRAUDE_GPS' AND cree_le >= v_since;
  v_fraude_gps_malus := COALESCE(v_fraude_gps_malus, 0);

  -- Le journal immuable est le registre canonique des dépassements. DISTINCT
  -- protège le score contre une éventuelle répétition historique sur une même
  -- mission ; le prédicat JSON tolère les anciennes lignes sans ce champ.
  SELECT (-8 * count(DISTINCT ja.id_ressource))::numeric
  INTO v_empechement_malus
  FROM public.journaux_audit ja
  WHERE ja.acteur_id = p_soignant_id
    AND ja.action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
    AND ja.type_ressource = 'mission'
    AND ja.id_ressource IS NOT NULL
    AND ja.cree_le >= v_since
    AND ja.details @> '{"depassement": true}'::jsonb;
  v_empechement_malus := COALESCE(v_empechement_malus, 0);

  IF v_nb_terminees_12m > 50 THEN v_bonus_super_actif := 5; END IF;

  IF EXISTS (
    SELECT 1 FROM missions m
    WHERE m.soignant_assigne_id = p_soignant_id
      AND COALESCE(m.est_urgente, false) = true
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
  ) OR EXISTS (
    SELECT 1 FROM candidatures c JOIN missions m ON m.id = c.mission_id
    WHERE c.soignant_id = p_soignant_id
      AND COALESCE(m.est_urgente, false) = true
      AND c.statut = 'EN_ATTENTE_VALIDATION_ETAB'
      AND m.statut = 'OUVERTE'
  ) THEN
    v_bonus_urgence := 5;
  END IF;

  v_score := v_score + v_litiges_malus + v_absence_malus
           + v_fraude_gps_malus + v_empechement_malus
           + v_bonus_super_actif + v_bonus_urgence;
  v_score := GREATEST(0, LEAST(100, v_score));

  v_score := ROUND(v_score, 2);

  v_niveau := CASE
    WHEN v_score >= 90 THEN 'PLATINE'
    WHEN v_score >= 70 THEN 'OR'
    WHEN v_score >= 50 THEN 'ARGENT'
    ELSE 'BRONZE'
  END::public.niveau_qualitatif;

  INSERT INTO scoring_breakdown (
    soignant_id, score_total, niveau, en_periode_probatoire,
    notation_etab_soignant_pct, notation_etab_soignant_poids,
    presentisme_pct, presentisme_poids,
    ponctualite_pct, ponctualite_poids,
    reactivite_pct, reactivite_poids,
    anciennete_volume_pct, anciennete_volume_poids,
    notation_soignant_etab_pct, notation_soignant_etab_poids,
    litiges_malus, absence_sans_prevenir_malus, bonus_super_actif,
    composantes_inactives_json, composantes_actives_count, redistribution_json,
    raison_recalcul
  ) VALUES (
    p_soignant_id, v_score, v_niveau, v_probatoire,
    v_notation_etab, v_pe_notation_etab,
    v_presentisme, v_pe_presentisme,
    v_ponctualite, v_pe_ponctualite,
    v_reactivite, v_pe_reactivite,
    v_anciennete_volume, v_pe_anciennete_volume,
    v_notation_par_soignant, v_pe_notation_par_soignant,
    v_litiges_malus, v_absence_malus, v_bonus_super_actif,
    v_inactives_json, v_actives_count,
    jsonb_build_object('facteur', v_facteur_redistribution, 'total_poids_actifs', v_total_poids_actifs, 'bonus_urgence', v_bonus_urgence, 'fraude_gps_malus', v_fraude_gps_malus, 'empechement_malus', v_empechement_malus),
    p_raison
  ) RETURNING id INTO v_breakdown_id;

  BEGIN
    PERFORM set_config('jolene.system_update', 'true', true);
    UPDATE soignants SET
      score_fiabilite = CASE WHEN v_total_missions_terminees = 0 THEN NULL ELSE v_score END, niveau = v_niveau,
      en_periode_probatoire = v_probatoire,
      score_breakdown_id = v_breakdown_id, modifie_le = NOW()
    WHERE id = p_soignant_id;
    PERFORM set_config(
      'jolene.system_update', v_previous_system_update, true
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config(
      'jolene.system_update', v_previous_system_update, true
    );
    RAISE;
  END;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_soignant_id, p_type_acteur := 'SYSTEME',
    p_action := 'SCORE_RECALCULE_V2', p_type_ressource := 'soignant', p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object('score', v_score, 'niveau', v_niveau::text, 'breakdown_id', v_breakdown_id, 'raison', p_raison, 'bonus_urgence', v_bonus_urgence, 'fraude_gps_malus', v_fraude_gps_malus, 'empechement_malus', v_empechement_malus)
  );

  RETURN jsonb_build_object('success', true, 'score', CASE WHEN v_total_missions_terminees = 0 THEN NULL ELSE v_score END, 'niveau', v_niveau,
    'breakdown_id', v_breakdown_id, 'en_periode_probatoire', v_probatoire,
    'composantes_actives', v_actives_count, 'bonus_urgence', v_bonus_urgence, 'fraude_gps_malus', v_fraude_gps_malus, 'empechement_malus', v_empechement_malus);
END;
$function$;

-- Le worker no-show peut être lancé en parallèle par plusieurs invocations du
-- cron. Verrouiller chaque mission originale, revérifier son état sous le
-- verrou et publier le remplacement après un CAS évite les doubles diffusions.
CREATE OR REPLACE FUNCTION public.fn_detecter_noshow_et_remplacer()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m record;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_remplacement_id uuid;
  v_traites integer := 0;
  v_remplacements integer := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_s uuid;
  v_corps text;
  v_rows integer;
  v_constraint text;
  v_admin uuid;
  v_blocage_publication jsonb;
  v_refund_result jsonb;
  v_finance_en_revue boolean;
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
       AND COALESCE(m.est_arret_maladie, false) = false
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
     ORDER BY m.id
     FOR UPDATE OF m SKIP LOCKED
  LOOP
    v_remplacement_id := NULL;
    v_escrow := NULL;
    v_blocage_publication := NULL;
    v_refund_result := NULL;
    v_finance_en_revue := false;

    -- Ces contrôles utilisent un nouveau snapshot après l'acquisition du
    -- verrou et couvrent les écritures concurrentes de présence/EPI/remplacement.
    IF COALESCE(v_m.est_arret_maladie, false)
       OR v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS')
       OR EXISTS (
         SELECT 1 FROM public.presences p
          WHERE p.mission_id = v_m.id
            AND p.soignant_id = v_m.soignant_assigne_id
       )
       OR EXISTS (
         SELECT 1 FROM public.missions r
          WHERE r.remplacement_de_mission_id = v_m.id
       ) THEN
      CONTINUE;
    END IF;

    IF COALESCE(v_m.garantie_remplacement, false) THEN
      BEGIN
      -- Le verrou mission est déjà détenu. Verrouiller ensuite l'escrow dans
      -- le même ordre que les RPC de débit empêche un nouveau claim concurrent.
      -- Un débit certain est remboursé avec reverse_transfer ; un appel Stripe
      -- déjà ambigu reste gelé pour rapprochement humain, jamais silencieux.
      SELECT pe.*
        INTO v_escrow
        FROM public.paiements_escrow pe
       WHERE pe.mission_id = v_m.id
       ORDER BY pe.cree_le DESC
       LIMIT 1
       FOR UPDATE;

      IF FOUND THEN
        IF v_escrow.statut = 'INITIE'
           AND v_escrow.stripe_payment_intent_id IS NULL
           AND v_escrow.stripe_charge_id IS NULL
           AND v_escrow.stripe_payout_id IS NULL
           AND COALESCE(v_escrow.tentatives_debit, 0) = 0 THEN
          UPDATE public.paiements_escrow
             SET statut = 'REMBOURSE',
                 erreur = 'No-show avant débit Stripe',
                 modifie_le = now()
           WHERE id = v_escrow.id
             AND statut = 'INITIE'
             AND stripe_payment_intent_id IS NULL
             AND stripe_charge_id IS NULL
             AND stripe_payout_id IS NULL
             AND COALESCE(tentatives_debit, 0) = 0;
          GET DIAGNOSTICS v_rows = ROW_COUNT;
          IF v_rows <> 1 THEN
            RAISE EXCEPTION 'Neutralisation escrow no-show concurrente refusée.'
              USING ERRCODE = 'P0001';
          END IF;
          UPDATE public.escrow_exposition_releases
             SET statut = 'REGLE'
           WHERE paiement_escrow_id = v_escrow.id AND statut = 'ACTIF';
          UPDATE public.escrow_release_queue
             SET statut = 'ECHEC',
                 erreur = 'Mission classée no-show avant débit',
                 traite_le = now()
           WHERE paiement_escrow_id = v_escrow.id
             AND statut IN ('EN_ATTENTE', 'EN_COURS');
          INSERT INTO public.journaux_audit (
            acteur_id, type_acteur, action, type_ressource, id_ressource,
            details, navigateur_acteur
          ) VALUES (
            '00000000-0000-0000-0000-000000000000'::uuid,
            'SYSTEME', 'ADMIN_ACTION', 'paiement_escrow', v_escrow.id,
            jsonb_build_object(
              'evenement', 'ESCROW_ANNULE_NO_SHOW_AVANT_DEBIT',
              'mission_id', v_m.id
            ),
            'fn_detecter_noshow_et_remplacer'
          );
        ELSIF v_escrow.statut IN ('DEBITE', 'DISPONIBLE') THEN
          v_refund_result := public.fn_escrow_rembourser(
            v_escrow.id,
            v_escrow.honoraires_cents,
            true,
            'No-show constaté avant remplacement garanti'
          );
          IF COALESCE((v_refund_result->>'success')::boolean, false) IS NOT TRUE THEN
            RAISE EXCEPTION 'Remboursement escrow no-show impossible: %',
              v_refund_result USING ERRCODE = 'P0001';
          END IF;
        ELSIF v_escrow.statut NOT IN (
          'REMBOURSE_EN_COURS', 'REMBOURSE', 'ECHOUE'
        ) THEN
          v_finance_en_revue := true;
        END IF;
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.stripe_transfers st
        WHERE st.mission_id = v_m.id
          AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
      ) OR EXISTS (
        SELECT 1 FROM public.paiements_soignant ps
        WHERE ps.mission_id = v_m.id
      ) OR EXISTS (
        SELECT 1 FROM public.factures_honoraires fh
        WHERE fh.mission_id = v_m.id
          AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
      ) THEN
        v_finance_en_revue := true;
      END IF;

      IF v_finance_en_revue THEN
        INSERT INTO public.journaux_audit (
          acteur_id, type_acteur, action, type_ressource, id_ressource,
          details, navigateur_acteur
        ) VALUES (
          '00000000-0000-0000-0000-000000000000'::uuid,
          'SYSTEME', 'ADMIN_ACTION', 'mission', v_m.id,
          jsonb_build_object(
            'evenement', 'NO_SHOW_RAPPROCHEMENT_FINANCIER_REQUIS',
            'paiement_escrow_id', v_escrow.id,
            'escrow_statut', v_escrow.statut
          ),
          'fn_detecter_noshow_et_remplacer'
        );
      END IF;

      -- Le cron est exécuté avec service_role, que le trigger onboarding laisse
      -- volontairement passer. La vérification explicite est donc obligatoire.
      v_blocage_publication := public.fn_blocage_publication_etab(
        v_m.etablissement_id
      );

      IF v_blocage_publication IS NOT NULL OR v_finance_en_revue THEN
        UPDATE public.missions m
           SET statut = 'ABSENCE',
               absence_sans_prevenir = true,
               modifie_le = now()
         WHERE m.id = v_m.id
           AND m.statut = v_m.statut
           AND m.soignant_assigne_id = v_m.soignant_assigne_id
           AND COALESCE(m.est_arret_maladie, false) = false
           AND m.debut_le < now() - interval '30 minutes'
           AND m.debut_le > now() - interval '4 hours'
           AND m.fin_le > now() + interval '1 hour'
           AND NOT EXISTS (
             SELECT 1 FROM public.presences p
              WHERE p.mission_id = m.id
                AND p.soignant_id = m.soignant_assigne_id
           )
           AND NOT EXISTS (
             SELECT 1 FROM public.missions r
              WHERE r.remplacement_de_mission_id = m.id
           );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'Classification no-show concurrente refusée.'
            USING ERRCODE = 'P0004';
        END IF;

        v_traites := v_traites + 1;
        IF v_blocage_publication IS NOT NULL THEN
          FOR v_admin IN
            SELECT ea.user_id FROM public.equipe_admin ea
            WHERE ea.actif AND ea.user_id IS NOT NULL
          LOOP
            INSERT INTO public.notifications (
              destinataire_id, type_destinataire, type, titre, corps, lien,
              type_ressource, id_ressource
            ) VALUES (
              v_admin, 'ADMIN', 'SYSTEM',
              'No-show — remplacement à traiter manuellement ⚠️',
              'Le no-show est enregistré mais la publication automatique est bloquée : '
                || COALESCE(
                  v_blocage_publication->>'message',
                  v_blocage_publication->>'error', 'gate établissement'
                ) || '.',
              '/admin/missions', 'mission', v_m.id
            );
          END LOOP;
        END IF;
        IF v_finance_en_revue THEN
          FOR v_admin IN
            SELECT ea.user_id FROM public.equipe_admin ea
            WHERE ea.actif AND ea.user_id IS NOT NULL
          LOOP
            INSERT INTO public.notifications (
              destinataire_id, type_destinataire, type, titre, corps, lien,
              type_ressource, id_ressource
            ) VALUES (
              v_admin, 'ADMIN', 'SYSTEM',
              'No-show — rapprochement financier requis ⚠️',
              'Le no-show est enregistré, mais le rail financier de la mission originale doit être rapproché avant tout remplacement. Escrow : '
                || COALESCE(v_escrow.statut, 'artefact financier externe') || '.',
              '/admin/finances', 'mission', v_m.id
            );
          END LOOP;
        END IF;
        INSERT INTO public.notifications (
          destinataire_id, type, titre, corps, lien, type_destinataire
        ) VALUES (
          v_m.etablissement_id, 'SYSTEM',
          'Aucun pointage — remplacement en revue ⚠️',
          'Aucun pointage détecté 30 min après le début de « '
            || public.fn_html_escape(v_m.intitule)
            || ' ». Le no-show est enregistré ; la publication automatique du remplacement est suspendue '
            || CASE
                 WHEN v_blocage_publication IS NOT NULL AND v_finance_en_revue
                   THEN 'par un contrôle de conformité et un rapprochement financier.'
                 WHEN v_blocage_publication IS NOT NULL
                   THEN 'par un contrôle de conformité.'
                 ELSE 'dans l’attente du rapprochement financier.'
               END
            || ' L’équipe admin est alertée.',
          '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT'
        );
      ELSE
      -- Le sous-bloc est un sous-transaction : si l'index unique arbitre une
      -- course, le passage temporaire à ABSENCE est lui aussi annulé.
      BEGIN
        UPDATE public.missions m
           SET statut = 'ABSENCE',
               absence_sans_prevenir = true,
               modifie_le = now()
         WHERE m.id = v_m.id
           AND m.statut = v_m.statut
           AND m.soignant_assigne_id = v_m.soignant_assigne_id
           AND COALESCE(m.est_arret_maladie, false) = false
           AND m.debut_le < now() - interval '30 minutes'
           AND m.debut_le > now() - interval '4 hours'
           AND m.fin_le > now() + interval '1 hour'
           AND NOT EXISTS (
             SELECT 1 FROM public.presences p
              WHERE p.mission_id = m.id
                AND p.soignant_id = m.soignant_assigne_id
           )
           AND NOT EXISTS (
             SELECT 1 FROM public.missions r
              WHERE r.remplacement_de_mission_id = m.id
           );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'Classification no-show concurrente refusée.'
            USING ERRCODE = 'P0004';
        END IF;

        INSERT INTO public.missions(
          etablissement_id, intitule, description, service,
          profession_requise, specialite_medicale_requise, accepte_non_specialises,
          debut_le, fin_le, duree_heures, taux_horaire_base,
          type_contrat_recherche, mode_remuneration, retrocession_pct,
          mission_source, statut, mode_attribution,
          est_urgente, niveau_urgence, garantie_remplacement,
          remplacement_de_mission_id
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
          v_m.mode_remuneration, v_m.retrocession_pct,
          'REMPLACEMENT', 'OUVERTE', 'PREMIER_ARRIVE',
          true, 3, true, v_m.id
        ) RETURNING id INTO v_remplacement_id;
      EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'uniq_missions_remplacement_direct'
           AND EXISTS (
             SELECT 1 FROM public.missions r
              WHERE r.remplacement_de_mission_id = v_m.id
           ) THEN
          RAISE EXCEPTION 'Remplacement no-show concurrent déjà publié.'
            USING ERRCODE = 'P0004';
        END IF;
        RAISE;
      END;

      v_traites := v_traites + 1;
      v_remplacements := v_remplacements + 1;
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
      END IF;
      EXCEPTION WHEN SQLSTATE 'P0004' THEN
        -- Le sous-bloc annule aussi toute neutralisation/refund préparé avant
        -- que le CAS ne découvre une présence ou une mutation concurrente.
        CONTINUE;
      END;
    ELSE
      v_traites := v_traites + 1;
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


CREATE OR REPLACE FUNCTION public.fn_declarer_empechement_imperieux(
  p_mission_id uuid, p_indispo_debut date, p_indispo_fin date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_m public.missions%ROWTYPE;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_nb integer := 0;
  v_max integer := greatest(
    0, fn_param_num('annulations_justifiees_max_12m', 2)::integer
  );
  v_n12 integer;
  v_depasse boolean;
  v_admin uuid;
  v_soignant_id uuid := auth.uid();
  v_audit_result jsonb;
  v_refund_result jsonb;
  v_blocage_publication jsonb;
  v_notifications_avant integer := 0;
  v_rows integer := 0;
  v_context text;
  v_est_future boolean;
  v_originale_cloturee boolean := false;
  v_remplacement_en_revue boolean := false;
  v_finance_resolution text := 'AUCUNE';
  v_previous_empechement_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
  v_previous_empechement_validated text := COALESCE(
    current_setting('jolene.empechement_mission_validated', true), ''
  );
  v_mission_diffusee_id uuid := p_mission_id;
  v_remplacement_id uuid;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true), ''
  );
BEGIN
  -- Un verrou par soignant sérialise le quota même si deux missions distinctes
  -- sont déclarées en parallèle. Le verrou de ligne empêche en plus une double
  -- déclaration de la même mission.
  IF v_soignant_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'jolene.empechement.' || v_soignant_id::text,
        0
      )
    );
  END IF;

  SELECT * INTO v_m
  FROM public.missions
  WHERE id = p_mission_id AND soignant_assigne_id = v_soignant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_m.est_arret_maladie THEN
    RETURN jsonb_build_object('error', 'Un empêchement est déjà déclaré sur cette mission.');
  END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  IF p_indispo_debut IS NULL OR p_indispo_fin IS NULL OR p_indispo_fin < p_indispo_debut THEN
    RETURN jsonb_build_object('error', 'Dates d''indisponibilité invalides.');
  END IF;
  IF p_indispo_fin - p_indispo_debut > 90 THEN
    RETURN jsonb_build_object('error', 'Période d''indisponibilité trop longue (90 jours max).');
  END IF;
  IF p_indispo_fin < (v_m.debut_le AT TIME ZONE 'Europe/Paris')::date
     OR p_indispo_debut > (v_m.fin_le AT TIME ZONE 'Europe/Paris')::date THEN
    RETURN jsonb_build_object(
      'error_code', 'INDISPONIBILITE_HORS_MISSION',
      'error', 'La période d''indisponibilité doit chevaucher la mission.'
    );
  END IF;

  v_est_future := v_m.statut = 'ASSIGNEE' AND v_m.debut_le > now();

  -- Une mission future doit pouvoir être annulée sans jamais payer l'ancien
  -- soignant. Les situations déjà externalisées ou ambiguës sont arrêtées
  -- avant le moindre flag/audit : aucune demi-transaction n'est possible.
  IF v_est_future THEN
    IF EXISTS (
      SELECT 1 FROM public.stripe_transfers st
      WHERE st.mission_id = p_mission_id
        AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
    ) OR EXISTS (
      SELECT 1 FROM public.paiements_soignant ps
      WHERE ps.mission_id = p_mission_id
    ) OR EXISTS (
      SELECT 1 FROM public.factures_honoraires fh
      WHERE fh.mission_id = p_mission_id
        AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    ) THEN
      RETURN jsonb_build_object(
        'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
        'error', 'Une opération financière existe déjà pour cette mission. Le support doit la rapprocher avant l''annulation.'
      );
    END IF;

    SELECT pe.* INTO v_escrow
    FROM public.paiements_escrow pe
    WHERE pe.mission_id = p_mission_id
    ORDER BY pe.cree_le DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      IF v_escrow.statut IN ('RELEASE_PLANIFIE', 'PAYE', 'DISPUTE')
         OR (
           v_escrow.statut = 'INITIE'
           AND (
             v_escrow.stripe_payment_intent_id IS NOT NULL
             OR v_escrow.stripe_charge_id IS NOT NULL
             OR v_escrow.stripe_payout_id IS NOT NULL
             OR COALESCE(v_escrow.tentatives_debit, 0) > 0
           )
         ) THEN
        RETURN jsonb_build_object(
          'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
          'error', 'Le paiement rapide est déjà en cours d''externalisation. Le support doit le rapprocher avant l''annulation.',
          'escrow_statut', v_escrow.statut
        );
      END IF;
    END IF;
  END IF;

  SELECT count(*) INTO v_n12
  FROM public.journaux_audit
  WHERE acteur_id = v_soignant_id
    AND action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
    AND cree_le > NOW() - INTERVAL '12 months';
  v_depasse := (v_n12 + 1) > v_max;

  -- Phase FLAG : le garde alphabétiquement premier vérifie que ces trois
  -- colonnes sont les seules mutées. La phase est nécessaire aussi pour un
  -- profil soignant qui possède parallèlement un rôle établissement faible.
  v_context := 'FLAG:' || p_mission_id::text || ':' || v_soignant_id::text;
  BEGIN
    PERFORM set_config(
      'jolene.empechement_mission_context', v_context, true
    );
    PERFORM set_config('jolene.empechement_mission_validated', '', true);
    UPDATE missions
    SET est_arret_maladie = TRUE,
        arret_maladie_declare_le = NOW(),
        modifie_le = NOW()
    WHERE id = p_mission_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1
       OR NOT EXISTS (
         SELECT 1
         FROM public.missions m_flag
         WHERE m_flag.id = p_mission_id
           AND m_flag.est_arret_maladie IS TRUE
           AND m_flag.arret_maladie_declare_le IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Phase interne FLAG incomplète.'
        USING ERRCODE = 'P0001';
    END IF;
    PERFORM set_config(
      'jolene.empechement_mission_validated',
      v_previous_empechement_validated,
      true
    );
    PERFORM set_config(
      'jolene.empechement_mission_context',
      v_previous_empechement_context,
      true
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config(
      'jolene.empechement_mission_validated',
      v_previous_empechement_validated,
      true
    );
    PERFORM set_config(
      'jolene.empechement_mission_context',
      v_previous_empechement_context,
      true
    );
    RAISE;
  END;

  v_audit_result := fn_ecrire_audit_safe(
    v_soignant_id, 'SOIGNANT', 'ANNULATION_EMPECHEMENT_IMPERIEUX',
    'mission', p_mission_id, NULL,
    jsonb_build_object(
      'sur_honneur', true,
      'indispo_debut', p_indispo_debut,
      'indispo_fin', p_indispo_fin,
      'n_12_mois', v_n12 + 1,
      'max_12_mois', v_max,
      'depassement', v_depasse
    )
  );
  IF COALESCE((v_audit_result->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'La déclaration ne peut pas être journalisée.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Le compteur est intégralement dérivé de ses sources canoniques.
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant_id);

  IF v_depasse THEN
    BEGIN
      PERFORM set_config('jolene.system_update', 'true', true);
      UPDATE soignants
      SET score_fiabilite = GREATEST(
            0, COALESCE(score_fiabilite, 50) - 8
          ),
          modifie_le = NOW()
      WHERE id = v_soignant_id;
      PERFORM set_config(
        'jolene.system_update', v_previous_system_update, true
      );
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config(
        'jolene.system_update', v_previous_system_update, true
      );
      RAISE;
    END;

    FOR v_admin IN
      SELECT user_id FROM equipe_admin WHERE actif AND user_id IS NOT NULL
    LOOP
      INSERT INTO notifications (
        destinataire_id, type, titre, corps, lien, type_destinataire
      ) VALUES (
        v_admin,
        'SYSTEM',
        'Empêchements répétés — revue soignant ⚠️',
        'Un soignant vient de déclarer son ' || (v_n12 + 1) ||
          'e empêchement impérieux sur 12 mois (max toléré : ' || v_max ||
          '). Pénalité de score appliquée. Détails dans le journal d''audit ' ||
          '(action ANNULATION_EMPECHEMENT_IMPERIEUX).',
        '/admin/audit',
        'ADMIN'
      );
    END LOOP;
  END IF;

  -- Neutraliser l'ancien rail financier puis clôturer toute mission future,
  -- garantie ou non. L'originale conserve l'assigné pour la preuve et les
  -- compteurs ; le remplacement aura toujours un nouvel id.
  IF v_est_future THEN
    IF v_escrow.id IS NOT NULL THEN
      IF v_escrow.statut = 'INITIE' THEN
        UPDATE public.paiements_escrow
           SET statut = 'REMBOURSE',
               erreur = 'Annulé avant tout débit : empêchement impérieux',
               modifie_le = now()
         WHERE id = v_escrow.id
           AND statut = 'INITIE'
           AND stripe_payment_intent_id IS NULL
           AND stripe_charge_id IS NULL
           AND stripe_payout_id IS NULL
           AND tentatives_debit = 0;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'Neutralisation escrow concurrente refusée.'
            USING ERRCODE = 'P0001';
        END IF;
        UPDATE public.escrow_exposition_releases
           SET statut = 'REGLE'
         WHERE paiement_escrow_id = v_escrow.id AND statut = 'ACTIF';
        UPDATE public.escrow_release_queue
           SET statut = 'ECHEC',
               erreur = 'Mission annulée avant débit',
               traite_le = now()
         WHERE paiement_escrow_id = v_escrow.id
           AND statut IN ('EN_ATTENTE', 'EN_COURS');
        INSERT INTO public.journaux_audit (
          acteur_id, type_acteur, action, type_ressource, id_ressource,
          details, navigateur_acteur
        ) VALUES (
          '00000000-0000-0000-0000-000000000000'::uuid,
          'SYSTEME', 'ADMIN_ACTION', 'paiement_escrow', v_escrow.id,
          jsonb_build_object(
            'evenement', 'ESCROW_ANNULE_AVANT_DEBIT',
            'mission_id', p_mission_id,
            'motif', 'EMPECHEMENT_IMPERIEUX'
          ),
          'fn_declarer_empechement_imperieux'
        );
        v_finance_resolution := 'ESCROW_ANNULE_AVANT_DEBIT';
      ELSIF v_escrow.statut IN ('DEBITE', 'DISPONIBLE') THEN
        v_refund_result := public.fn_escrow_rembourser(
          v_escrow.id,
          v_escrow.honoraires_cents,
          true,
          'Empêchement impérieux avant mission'
        );
        IF COALESCE((v_refund_result->>'success')::boolean, false) IS NOT TRUE THEN
          RAISE EXCEPTION 'Remboursement escrow impossible: %', v_refund_result
            USING ERRCODE = 'P0001';
        END IF;
        v_finance_resolution := 'ESCROW_REMBOURSEMENT_ENFILE';
      ELSIF v_escrow.statut = 'REMBOURSE_EN_COURS' THEN
        v_finance_resolution := 'ESCROW_REMBOURSEMENT_DEJA_EN_COURS';
      ELSIF v_escrow.statut IN ('REMBOURSE', 'ECHOUE') THEN
        v_finance_resolution := 'ESCROW_TERMINAL';
      ELSE
        RAISE EXCEPTION 'Etat escrow non annulable: %', v_escrow.statut
          USING ERRCODE = 'P0001';
      END IF;
    END IF;

    v_context := 'CLOSE:' || p_mission_id::text || ':' || v_soignant_id::text;
    BEGIN
      PERFORM set_config('jolene.empechement_mission_context', v_context, true);
      PERFORM set_config('jolene.empechement_mission_validated', '', true);
      UPDATE public.missions
         SET statut = 'ANNULEE_PAR_SOIGNANT', modifie_le = now()
       WHERE id = p_mission_id;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 OR NOT EXISTS (
        SELECT 1 FROM public.missions m_close
        WHERE m_close.id = p_mission_id
          AND m_close.statut = 'ANNULEE_PAR_SOIGNANT'
          AND m_close.soignant_assigne_id = v_soignant_id
          AND m_close.est_arret_maladie IS TRUE
      ) THEN
        RAISE EXCEPTION 'Phase interne CLOSE incomplète.'
          USING ERRCODE = 'P0001';
      END IF;
      PERFORM set_config(
        'jolene.empechement_mission_validated',
        v_previous_empechement_validated, true
      );
      PERFORM set_config(
        'jolene.empechement_mission_context',
        v_previous_empechement_context, true
      );
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config(
        'jolene.empechement_mission_validated',
        v_previous_empechement_validated, true
      );
      PERFORM set_config(
        'jolene.empechement_mission_context',
        v_previous_empechement_context, true
      );
      RAISE;
    END;
    v_originale_cloturee := true;

    -- Le contrat signé reste une preuve immuable. Si une DPAE a été faite,
    -- on enfile explicitement son annulation au lieu de falsifier le contrat.
    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    )
    SELECT 'DPAE_ANNULATION',
           jsonb_build_object(
             'contrat_id', cm.id,
             'mission_id', p_mission_id,
             'motif', 'EMPECHEMENT_IMPERIEUX',
             'echeance_legale_h', 48
           ),
           'ANNULATION_MISSION', p_mission_id
    FROM public.contrats_mission cm
    WHERE cm.mission_id = p_mission_id
      AND cm.statut = 'SIGNE_COMPLET'
      AND cm.type_contrat IN ('CDD', 'CDDU', 'VACATION')
      AND (
        COALESCE(cm.dpae_effectuee, false) IS TRUE
        OR NULLIF(btrim(COALESCE(cm.dpae_numero, '')), '') IS NOT NULL
      );
  END IF;

  INSERT INTO public.notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_m.etablissement_id,
    'SYSTEM',
    'Empêchement impérieux déclaré ⚠️',
    'Le soignant assigné à "' || fn_html_escape(v_m.intitule) ||
      '" atteste sur l''honneur d''un empêchement impérieux et sera indisponible du ' ||
      TO_CHAR(p_indispo_debut, 'DD/MM') || ' au ' || TO_CHAR(p_indispo_fin, 'DD/MM') || '.' ||
      CASE
        WHEN v_m.garantie_remplacement AND v_m.fin_le > now() + interval '1 hour'
          THEN ' Garantie remplacement : Jolene traite la demande. Vous serez informé dès sa diffusion.'
        WHEN v_est_future
          THEN ' La mission originale est clôturée. Publiez un remplacement depuis vos missions.'
        ELSE ' La mission est suspendue jusqu''à validation des heures réellement effectuées.'
      END,
    '/etablissement/missions/' || v_m.id,
    'ETABLISSEMENT'
  );

  INSERT INTO notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_soignant_id,
    'SYSTEM',
    'Empêchement enregistré',
    'Votre attestation sur l''honneur est enregistrée — aucun justificatif à fournir.' ||
      CASE
        WHEN v_depasse
          THEN ' Attention : au-delà de ' || v_max ||
            ' empêchements sur 12 mois, la pénalité de score s''applique (c''est le cas ici).'
        ELSE ' Aucune pénalité de score.'
      END ||
      ' Une fausse déclaration engage votre responsabilité (CGU).',
    '/soignant/missions/' || v_m.id,
    'SOIGNANT'
  );

  IF v_m.garantie_remplacement AND v_m.fin_le > now() + interval '1 hour' THEN
    v_blocage_publication := public.fn_blocage_publication_etab(
      v_m.etablissement_id
    );
    IF v_blocage_publication IS NOT NULL THEN
      v_remplacement_en_revue := true;
      FOR v_admin IN
        SELECT user_id FROM public.equipe_admin
        WHERE actif AND user_id IS NOT NULL
      LOOP
        INSERT INTO public.notifications (
          destinataire_id, type_destinataire, type, titre, corps, lien,
          type_ressource, id_ressource
        ) VALUES (
          v_admin, 'ADMIN', 'SYSTEM',
          'Garantie remplacement à traiter manuellement ⚠️',
          'L''empêchement est enregistré mais la publication automatique est bloquée : '
            || COALESCE(
              v_blocage_publication->>'message',
              v_blocage_publication->>'error', 'gate établissement'
            ) || '.',
          '/admin/missions', 'mission', p_mission_id
        );
      END LOOP;
    ELSE
      v_context := 'REPLACEMENT:' || p_mission_id::text || ':'
        || v_soignant_id::text;
      BEGIN
        PERFORM set_config(
          'jolene.empechement_mission_context', v_context, true
        );
        PERFORM set_config('jolene.empechement_mission_validated', '', true);
        INSERT INTO public.missions (
          etablissement_id, intitule, description, service,
          profession_requise, specialite_medicale_requise,
          accepte_non_specialises, debut_le, fin_le, duree_heures,
          taux_horaire_base, type_contrat_recherche,
          mode_remuneration, retrocession_pct, mission_source, statut,
          mode_attribution, est_urgente, niveau_urgence,
          garantie_remplacement, remplacement_de_mission_id
        ) VALUES (
          v_m.etablissement_id,
          'REMPLACEMENT URGENT — ' || v_m.intitule,
          COALESCE(v_m.description, '')
            || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]',
          v_m.service,
          v_m.profession_requise,
          v_m.specialite_medicale_requise,
          v_m.accepte_non_specialises,
          GREATEST(v_m.debut_le, now() + interval '15 minutes'),
          v_m.fin_le,
          round(extract(epoch FROM (
            v_m.fin_le - GREATEST(
              v_m.debut_le, now() + interval '15 minutes'
            )
          )) / 3600.0, 2),
          v_m.taux_horaire_base,
          v_m.type_contrat_recherche,
          v_m.mode_remuneration,
          v_m.retrocession_pct,
          'REMPLACEMENT',
          'OUVERTE',
          'PREMIER_ARRIVE',
          true,
          3,
          true,
          v_m.id
        ) RETURNING id INTO v_remplacement_id;
        IF NOT EXISTS (
          SELECT 1
          FROM public.missions m_replacement
          WHERE m_replacement.id = v_remplacement_id
            AND m_replacement.remplacement_de_mission_id = p_mission_id
            AND m_replacement.statut = 'OUVERTE'
            AND m_replacement.soignant_assigne_id IS NULL
            AND m_replacement.est_urgente IS TRUE
            AND m_replacement.niveau_urgence = 3
            AND m_replacement.mode_attribution = 'PREMIER_ARRIVE'
            AND m_replacement.debut_le > now()
        ) THEN
          RAISE EXCEPTION 'Phase interne REPLACEMENT incomplète.'
            USING ERRCODE = 'P0001';
        END IF;
        PERFORM set_config(
          'jolene.empechement_mission_validated',
          v_previous_empechement_validated,
          true
        );
        PERFORM set_config(
          'jolene.empechement_mission_context',
          v_previous_empechement_context,
          true
        );
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config(
          'jolene.empechement_mission_validated',
          v_previous_empechement_validated,
          true
        );
        PERFORM set_config(
          'jolene.empechement_mission_context',
          v_previous_empechement_context,
          true
        );
        RAISE;
      END;
      v_mission_diffusee_id := v_remplacement_id;

      INSERT INTO notifications (
        destinataire_id, type, titre, corps, lien, type_destinataire,
        type_ressource, id_ressource
      ) VALUES (
        v_m.etablissement_id,
        'SYSTEM',
        'Mission de remplacement urgente créée 🚨',
        'La mission de remplacement pour « '
          || fn_html_escape(v_m.intitule)
          || ' » est publiée pour le temps restant et le pool vient d''être alerté.',
        '/etablissement/missions/' || v_remplacement_id,
        'ETABLISSEMENT',
        'mission',
        v_remplacement_id
      );

      -- Le trigger urgent est l'unique fan-out externe.
      SELECT greatest(0, count(*)::integer - v_notifications_avant)
      INTO v_nb
      FROM public.notifications n
      WHERE n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
        AND n.type_ressource = 'mission'
        AND n.id_ressource = v_mission_diffusee_id;
    END IF;
  END IF;

  -- Les AFTER triggers historiques peuvent avoir touché les compteurs pendant
  -- CLOSE ; le résultat final est toujours recalé sur les sources canoniques.
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant_id);

  RETURN jsonb_build_object(
    'success', true,
    'pool_alerte', v_nb,
    'mission_diffusee_id', v_mission_diffusee_id,
    'mission_remplacement_id', v_remplacement_id,
    'mission_originale_cloturee', v_originale_cloturee,
    'remplacement_en_revue', v_remplacement_en_revue,
    'finance_resolution', v_finance_resolution,
    'depassement', v_depasse,
    'n_12_mois', v_n12 + 1,
    'max_12_mois', v_max
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_declarer_empechement_imperieux(uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_empechement_imperieux(uuid, date, date)
  TO authenticated, service_role;
