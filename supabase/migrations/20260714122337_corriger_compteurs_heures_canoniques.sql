-- Compteurs d'experience : une seule source de verite, exacte et fail-closed.
--
-- Trois anciens triggers mutaient les memes colonnes de facon concurrente :
-- une mission terminee pouvait etre comptee deux fois, un UPDATE cosmetique
-- effacait les heures externes et un retour LITIGE -> TERMINEE reincrementait
-- les heures. Cette migration remplace ces increments par un recalcul
-- idempotent, synchronise les surfaces denormalisees et ne supprime ni ne
-- masque aucune donnee utilisateur.

-- ---------------------------------------------------------------------------
-- 1. Provenance technique explicite pour les seules fixtures E2E ephemeres
-- ---------------------------------------------------------------------------

ALTER TABLE public.heures_externes_soignants
  DROP CONSTRAINT IF EXISTS heures_externes_source_validation_serveur_check,
  ADD CONSTRAINT heures_externes_source_validation_serveur_check CHECK (
    source_validation_serveur IS NULL
    OR source_validation_serveur IN (
      'ADMIN_LEGACY_AUDITE', 'ADMIN_AAL2', 'IA_REVUE',
      'IA_REJET_CONCLUSIF', 'TEST_FIXTURE_SERVICE_ROLE'
    )
  ) NOT VALID,
  DROP CONSTRAINT IF EXISTS heures_externes_valide_provenance_check,
  ADD CONSTRAINT heures_externes_valide_provenance_check CHECK (
    statut_validation <> 'VALIDE'
    OR (
      source_validation_serveur IN (
        'ADMIN_LEGACY_AUDITE', 'ADMIN_AAL2', 'TEST_FIXTURE_SERVICE_ROLE'
      )
      AND empreinte_snapshot_source IS NOT NULL
      AND (
        source_validation_serveur = 'ADMIN_LEGACY_AUDITE'
        OR empreinte_preuve_sha256 IS NOT NULL
      )
    )
  ) NOT VALID;

COMMENT ON COLUMN public.heures_externes_soignants.source_validation_serveur IS
  'Provenance serveur du verdict. ADMIN_AAL2 et ADMIN_LEGACY_AUDITE alimentent les comptes reels ; TEST_FIXTURE_SERVICE_ROLE est limite aux profils Playwright ephemeres par le compteur et sa RPC service_role.';

-- ---------------------------------------------------------------------------
-- 2. Compteur canonique exact (aucun arrondi entier avant les seuils)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.fn_heures_exercice_verifiees(
  p_soignant_id uuid
)
RETURNS TABLE(
  heures_jolene numeric,
  heures_externes_validees numeric,
  heures_externes_en_attente numeric,
  heures_totales numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
  WITH profil AS (
    SELECT s.id, COALESCE(s.est_compte_test, false) AS est_compte_test, s.email
    FROM public.soignants s
    WHERE s.id = p_soignant_id
  ),
  jolene AS (
    SELECT COALESCE(
      round(sum(
        COALESCE(
          (
            SELECT sum(COALESCE(pr.heures_ajustees_litige, pr.heures_reelles))
            FROM public.presences pr
            WHERE pr.mission_id = m.id
              AND COALESCE(pr.heures_ajustees_litige, pr.heures_reelles)
                  IS NOT NULL
          ),
          m.duree_heures_effective,
          m.duree_heures
        )
      ), 2),
      0::numeric
    ) AS heures
    FROM public.missions m
    WHERE m.soignant_assigne_id = p_soignant_id
      AND m.statut = 'TERMINEE'
  ),
  externes AS (
    SELECT
      COALESCE(sum(h.heures_declarees) FILTER (
        WHERE h.statut_validation = 'VALIDE'
          AND h.empreinte_snapshot_source =
              private.fn_empreinte_snapshot_heures_externes(h)
          AND (
            (
              h.source_validation_serveur IN (
                'ADMIN_AAL2', 'ADMIN_LEGACY_AUDITE'
              )
              AND (
                h.source_validation_serveur = 'ADMIN_LEGACY_AUDITE'
                OR h.empreinte_preuve_sha256 IS NOT NULL
              )
            )
            OR (
              h.source_validation_serveur = 'TEST_FIXTURE_SERVICE_ROLE'
              AND h.empreinte_preuve_sha256 IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM profil p
                WHERE p.est_compte_test IS TRUE
                  AND lower(p.email) LIKE 'playwright-test-caregiver-%@jolene.app'
              )
            )
          )
      ), 0::numeric) AS validees,
      COALESCE(sum(h.heures_declarees) FILTER (
        WHERE h.statut_validation = 'EN_ATTENTE'
      ), 0::numeric) AS en_attente
    FROM public.heures_externes_soignants h
    WHERE h.soignant_id = p_soignant_id
  )
  SELECT
    j.heures,
    e.validees,
    e.en_attente,
    round(j.heures + e.validees, 2)
  FROM jolene j
  CROSS JOIN externes e;
$function$;

REVOKE ALL ON FUNCTION private.fn_heures_exercice_verifiees(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- Le seuil d'installation n'est pas universel : il suit la profession de la
-- mission (regle Lot 21), jamais le seul diplome du profil. Les professions
-- infirmieres utilisent 3 200 h ; le parcours kine utilise 2 240 h ou la voie
-- zone sous-dotee ; les autres professions autorisees n'ont pas de seuil
-- horaire dans le parcours Jolene. NULL signifie qu'un choix kine manque et
-- doit etre bloque, jamais interprete comme zero.
CREATE OR REPLACE FUNCTION private.fn_seuil_heures_liberal(
  p_soignant_id uuid,
  p_profession_mission text
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
  SELECT CASE upper(COALESCE(p_profession_mission, ''))
    WHEN 'IDE' THEN 3200::numeric
    WHEN 'IADE' THEN 3200::numeric
    WHEN 'IBODE' THEN 3200::numeric
    WHEN 'KINE' THEN CASE p.parcours_kine
      WHEN 'HEURES_2240' THEN 2240::numeric
      WHEN 'ZONE_SOUS_DOTEE' THEN 0::numeric
      ELSE NULL::numeric
    END
    ELSE 0::numeric
  END
  FROM (SELECT 1) AS singleton
  LEFT JOIN public.parcours_liberal_soignants p
    ON p.soignant_id = p_soignant_id;
$function$;

REVOKE ALL ON FUNCTION private.fn_seuil_heures_liberal(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Une seule fonction proprietaire des colonnes denormalisees
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
  WHERE s.id = p_soignant_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT *
  INTO v_compteur
  FROM private.fn_heures_exercice_verifiees(p_soignant_id);

  SELECT
    count(*) FILTER (WHERE m.statut = 'TERMINEE')::integer,
    count(*) FILTER (WHERE m.statut = 'ANNULEE_PAR_SOIGNANT')::integer,
    count(*) FILTER (WHERE m.statut = 'ABSENCE')::integer
  INTO v_total_terminees, v_total_annulees, v_total_absences
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id;

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

  -- Le suivi n'est cree que pour une profession proposee en liberal. Une ligne
  -- historique deja presente reste toutefois synchronisee sans etre effacee.
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

CREATE OR REPLACE FUNCTION public.dec_maj_compteurs_soignant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_old_soignant_id uuid;
  v_new_soignant_id uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_old_soignant_id := OLD.soignant_assigne_id;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    v_new_soignant_id := NEW.soignant_assigne_id;
  END IF;

  IF v_old_soignant_id IS NOT NULL THEN
    PERFORM private.fn_resynchroniser_compteurs_soignant(v_old_soignant_id);
  END IF;
  IF v_new_soignant_id IS NOT NULL
     AND v_new_soignant_id IS DISTINCT FROM v_old_soignant_id THEN
    PERFORM private.fn_resynchroniser_compteurs_soignant(v_new_soignant_id);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_maj_compteurs_soignant()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_maj_compteurs_soignant()
  TO service_role;

DROP TRIGGER IF EXISTS dec_maj_compteurs ON public.missions;
CREATE TRIGGER dec_maj_compteurs
AFTER INSERT OR DELETE OR UPDATE OF
  statut, soignant_assigne_id, duree_heures, duree_heures_effective,
  debut_le, fin_le
ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_maj_compteurs_soignant();

-- L'ancien increment est dangereux meme s'il parait idempotent sur le premier
-- passage : LITIGE -> TERMINEE le rejouait. Le recalcul ci-dessus le remplace.
DROP TRIGGER IF EXISTS dec_heures_plateforme ON public.missions;
REVOKE ALL ON FUNCTION public.dec_incrementer_heures_plateforme()
  FROM PUBLIC, anon, authenticated, service_role;

-- Cette fonction conserve uniquement les effets non comptables historiques :
-- activite et badge de parrainage. Les compteurs sont exclusivement possedes
-- par private.fn_resynchroniser_compteurs_soignant.
CREATE OR REPLACE FUNCTION public.dec_mettre_a_jour_fiabilite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_parrain_id uuid;
  v_nb_filleuls_valides integer;
  v_parrain_avait_badge boolean;
  v_filleul_prenom text;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true), ''
  );
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.statut = 'TERMINEE'
     AND (
       OLD.statut IS DISTINCT FROM NEW.statut
       OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
     ) THEN
    PERFORM set_config('jolene.system_update', 'true', true);
    UPDATE public.soignants
    SET premiere_mission_le = COALESCE(premiere_mission_le, now()),
        derniere_activite_le = now(),
        modifie_le = now()
    WHERE id = NEW.soignant_assigne_id;

    SELECT s.parraine_par, s.prenom
    INTO v_parrain_id, v_filleul_prenom
    FROM public.soignants s
    WHERE s.id = NEW.soignant_assigne_id;

    IF v_parrain_id IS NOT NULL THEN
      SELECT count(*)::integer
      INTO v_nb_filleuls_valides
      FROM public.soignants s
      WHERE s.parraine_par = v_parrain_id
        AND COALESCE(s.total_missions_terminees, 0) > 0
        AND s.supprime_le IS NULL;

      IF v_nb_filleuls_valides >= 3 THEN
        SELECT s.badge_ambassadeur
        INTO v_parrain_avait_badge
        FROM public.soignants s
        WHERE s.id = v_parrain_id;

        IF NOT COALESCE(v_parrain_avait_badge, false) THEN
          UPDATE public.soignants
          SET badge_ambassadeur = true,
              modifie_le = now()
          WHERE id = v_parrain_id;

          INSERT INTO public.notifications (
            destinataire_id, type_destinataire, type, titre, corps, lien
          ) VALUES (
            v_parrain_id,
            'SOIGNANT',
            'PARRAINAGE',
            'Badge Ambassadeur debloque !',
            'Bravo ! ' || COALESCE(v_filleul_prenom, 'Votre filleul')
              || ' vient de terminer sa 1re mission. Vous avez 3 filleuls valides et obtenez le badge Ambassadeur, visible sur votre profil.',
            '/soignant/parrainage'
          );
        END IF;
      END IF;
    END IF;

    PERFORM set_config(
      'jolene.system_update', v_previous_system_update, true
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config(
    'jolene.system_update', v_previous_system_update, true
  );
  RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_mettre_a_jour_fiabilite()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_mettre_a_jour_fiabilite()
  TO service_role;

-- Une correction de pointage ou d'heures reelles doit etre visible partout
-- sans attendre une nouvelle mutation de mission.
CREATE OR REPLACE FUNCTION public.dec_resynchroniser_compteurs_presence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_old_mission_id uuid;
  v_new_mission_id uuid;
  v_soignant_id uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_old_mission_id := OLD.mission_id;
    SELECT m.soignant_assigne_id
    INTO v_soignant_id
    FROM public.missions m
    WHERE m.id = v_old_mission_id;
    PERFORM private.fn_resynchroniser_compteurs_soignant(
      COALESCE(v_soignant_id, OLD.soignant_id)
    );
  END IF;

  IF TG_OP <> 'DELETE' THEN
    v_new_mission_id := NEW.mission_id;
    IF v_new_mission_id IS DISTINCT FROM v_old_mission_id
       OR NEW.soignant_id IS DISTINCT FROM (
         CASE
           WHEN TG_OP = 'INSERT' THEN NULL::uuid
           ELSE OLD.soignant_id
         END
       )
       OR TG_OP = 'INSERT' THEN
      SELECT m.soignant_assigne_id
      INTO v_soignant_id
      FROM public.missions m
      WHERE m.id = v_new_mission_id;
      PERFORM private.fn_resynchroniser_compteurs_soignant(
        COALESCE(v_soignant_id, NEW.soignant_id)
      );
    ELSIF v_soignant_id IS NOT NULL THEN
      -- Meme mission : la premiere branche a deja recalcule avec NEW visible.
      NULL;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_resynchroniser_compteurs_presence()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_resynchroniser_compteurs_presence()
  TO service_role;

DROP TRIGGER IF EXISTS trg_resynchroniser_compteurs_presence
  ON public.presences;
CREATE TRIGGER trg_resynchroniser_compteurs_presence
AFTER INSERT OR DELETE OR UPDATE OF
  mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le,
  pause_debut_le, pause_fin_le, duree_pause_min, duree_nette_min,
  heures_reelles, heures_ajustees_litige
ON public.presences
FOR EACH ROW
EXECUTE FUNCTION public.dec_resynchroniser_compteurs_presence();

CREATE OR REPLACE FUNCTION public.dec_resynchroniser_compteurs_heures_externes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_old_soignant_id uuid;
  v_new_soignant_id uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_old_soignant_id := OLD.soignant_id;
    PERFORM private.fn_resynchroniser_compteurs_soignant(v_old_soignant_id);
  END IF;
  IF TG_OP <> 'DELETE' THEN
    v_new_soignant_id := NEW.soignant_id;
    IF v_new_soignant_id IS DISTINCT FROM v_old_soignant_id THEN
      PERFORM private.fn_resynchroniser_compteurs_soignant(v_new_soignant_id);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_resynchroniser_compteurs_heures_externes()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_resynchroniser_compteurs_heures_externes()
  TO service_role;

DROP TRIGGER IF EXISTS trg_resynchroniser_compteurs_heures_externes
  ON public.heures_externes_soignants;
CREATE TRIGGER trg_resynchroniser_compteurs_heures_externes
AFTER INSERT OR UPDATE OR DELETE ON public.heures_externes_soignants
FOR EACH ROW
EXECUTE FUNCTION public.dec_resynchroniser_compteurs_heures_externes();

-- ---------------------------------------------------------------------------
-- 4. Toutes les lectures et gates reutilisent le meme calcul
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.fn_compteur_heures_soignant(uuid);
CREATE FUNCTION public.fn_compteur_heures_soignant(p_soignant_id uuid)
RETURNS TABLE(
  heures_jolene numeric,
  heures_externes_validees numeric,
  heures_externes_en_attente numeric,
  heures_totales numeric,
  eligible_free_transition boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_compteur record;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Compte authentifie actif requis'
      USING ERRCODE = '42501';
  END IF;
  IF auth.uid() <> p_soignant_id AND NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Acces non autorise' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_compteur
  FROM private.fn_heures_exercice_verifiees(p_soignant_id);

  RETURN QUERY SELECT
    v_compteur.heures_jolene,
    v_compteur.heures_externes_validees,
    v_compteur.heures_externes_en_attente,
    v_compteur.heures_totales,
    v_compteur.heures_jolene >= 3200;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_compteur_heures_soignant(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_compteur_heures_soignant(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_calculer_heures_totales(
  p_soignant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_compteur record;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Fonction reservee au service_role'
      USING ERRCODE = '42501';
  END IF;
  PERFORM private.fn_resynchroniser_compteurs_soignant(p_soignant_id);
  SELECT *
  INTO v_compteur
  FROM private.fn_heures_exercice_verifiees(p_soignant_id);
  RETURN jsonb_build_object(
    'heures_plateforme', v_compteur.heures_jolene,
    'heures_externes_validees', v_compteur.heures_externes_validees,
    'heures_totales', v_compteur.heures_totales,
    'eligible_3200h', v_compteur.heures_totales >= 3200
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_calculer_heures_totales(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_calculer_heures_totales(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_verifier_eligibilite_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_heures_cumulees numeric;
  v_seuil_heures numeric;
  v_etablissement record;
  v_mode jsonb;
  v_verifier boolean := false;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut = 'ASSIGNEE'
     AND NEW.type_contrat_applique::text = 'LIBERAL' THEN
    IF TG_OP = 'INSERT' THEN
      v_verifier := true;
    ELSE
      v_verifier := OLD.statut IS DISTINCT FROM NEW.statut
        OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
        OR OLD.type_contrat_applique IS DISTINCT FROM NEW.type_contrat_applique;
    END IF;
  END IF;

  IF NOT v_verifier THEN
    RETURN NEW;
  END IF;

  IF upper(COALESCE(NEW.type_contrat_recherche::text, 'SALARIE'))
       NOT IN ('LIBERAL', 'TOUS') THEN
    RAISE EXCEPTION 'La mission n''est pas ouverte a un contrat liberal.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT e.type::text AS type_etablissement,
         COALESCE(e.est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements e
  WHERE e.id = NEW.etablissement_id
    AND e.supprime_le IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Etablissement introuvable pour la mission.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_etablissement.type_etablissement,
    CASE WHEN v_etablissement.est_public THEN 'PUBLIC' ELSE NULL END
  );
  IF COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE' THEN
    RAISE EXCEPTION '%', COALESCE(
      v_mode->>'source_libelle',
      'Cette profession est proposee en salarie pour cet etablissement.'
    ) USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_soignant_liberal_actif_verifie(
    NEW.soignant_assigne_id
  ) THEN
    RAISE EXCEPTION 'Le profil liberal doit etre actif, avec SIRET et identite verifies.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_documents_ok_pour_mission(
    NEW.soignant_assigne_id, 'LIBERAL'
  ) THEN
    RAISE EXCEPTION 'Les documents requis pour la mission liberale ne sont pas tous verifies.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.soignants s
    WHERE s.id = NEW.soignant_assigne_id
      AND s.supprime_le IS NULL
  ) THEN
    RAISE EXCEPTION 'Profil soignant introuvable.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT h.heures_totales
  INTO v_heures_cumulees
  FROM private.fn_heures_exercice_verifiees(
    NEW.soignant_assigne_id
  ) h;

  SELECT private.fn_seuil_heures_liberal(
    NEW.soignant_assigne_id,
    NEW.profession_requise::text
  )
  INTO v_seuil_heures;
  IF v_seuil_heures IS NULL THEN
    RAISE EXCEPTION 'Le parcours kine (2 240 heures ou zone sous-dotee) doit etre choisi avant une mission liberale.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(v_heures_cumulees, 0) < v_seuil_heures THEN
    RAISE EXCEPTION 'Vous devez cumuler % heures d''exercice pour accepter cette mission liberale. Vous avez actuellement % heures.',
      v_seuil_heures,
      round(COALESCE(v_heures_cumulees, 0), 2)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS dec_eligibilite_liberal ON public.missions;
CREATE TRIGGER dec_eligibilite_liberal
BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_verifier_eligibilite_liberal();

REVOKE ALL ON FUNCTION public.dec_verifier_eligibilite_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_eligibilite_liberal()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_activer_liberal()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant record;
  v_compteur record;
  v_seuil_heures numeric;
  v_taux jsonb;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true), ''
  );
  v_previous_liberal_transition text := COALESCE(
    current_setting('jolene.liberal_transition', true), ''
  );
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'NON_AUTHENTIFIE',
      'error', 'Non authentifie'
    );
  END IF;

  SELECT *
  INTO v_soignant
  FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SOIGNANT_INTROUVABLE',
      'error', 'Soignant introuvable'
    );
  END IF;
  IF v_soignant.siret_liberal !~ '^[0-9]{14}$'
     OR v_soignant.siret_liberal_verifie IS NOT TRUE
     OR v_soignant.siret_liberal_verifie_le IS NULL
     OR v_soignant.siret_liberal_coherence_identite IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SIRET_LIBERAL_NON_VERIFIE',
      'error', 'Le SIRET doit etre verifie et correspondre a votre identite avant activation.'
    );
  END IF;
  IF v_soignant.siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'
     AND NOT private.fn_preuve_identite_siret_manuelle_courante(v_uid) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SIRET_LIBERAL_PREUVE_IDENTITE_OBSOLETE',
      'error', 'La piece d identite ayant fonde la revue SIRET a expire, ete remplacee ou revoquee.'
    );
  END IF;
  IF v_soignant.profession NOT IN (
    SELECT p.profession
    FROM public.professions_liberal_eligible p
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PROFESSION_NON_ELIGIBLE',
      'error', 'Votre profession n est pas eligible au liberal'
    );
  END IF;

  SELECT *
  INTO v_compteur
  FROM private.fn_heures_exercice_verifiees(v_uid);

  SELECT private.fn_seuil_heures_liberal(v_uid, v_soignant.profession::text)
  INTO v_seuil_heures;
  IF v_seuil_heures IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PARCOURS_KINE_REQUIS',
      'error', 'Choisissez le parcours kine 2 240 heures ou zone sous-dotee avant l activation.'
    );
  END IF;
  IF v_compteur.heures_totales < v_seuil_heures THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'HEURES_EXERCICE_INSUFFISANTES',
      'error', 'Le seuil d heures d exercice requis pour votre profession n est pas atteint.',
      'heures_requises', v_seuil_heures,
      'heures_totales', v_compteur.heures_totales
    );
  END IF;

  -- Free Transition reste volontairement fonde sur les seules heures Jolene.
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_uid);
  v_taux := public.fn_calculer_taux_free_transition(v_uid);
  PERFORM set_config('jolene.liberal_transition', 'true', true);
  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET type_exercice = 'LIBERAL',
      type_contrat = 'LIBERAL',
      statut_liberal = 'ACTIF',
      date_passage_liberal = current_date,
      code_ape = (
        SELECT p.code_ape
        FROM public.professions_liberal_eligible p
        WHERE p.profession = v_soignant.profession
      ),
      modifie_le = now()
  WHERE id = v_uid;

  PERFORM public.fn_calculer_tous_documents_valides(v_uid);
  PERFORM set_config(
    'jolene.system_update', v_previous_system_update, true
  );
  PERFORM set_config(
    'jolene.liberal_transition', v_previous_liberal_transition, true
  );

  INSERT INTO public.conversions_liberal (
    soignant_id,
    heures_plateforme_au_demarrage,
    heures_externes_validees,
    heures_totales,
    statut,
    free_transition_eligible,
    taux_prise_en_charge,
    montant_pris_en_charge,
    complete_le
  ) VALUES (
    v_uid,
    v_compteur.heures_jolene,
    v_compteur.heures_externes_validees,
    v_compteur.heures_totales,
    'COMPLET',
    (v_taux ->> 'eligible')::boolean,
    (v_taux ->> 'taux_prise_en_charge')::integer,
    (v_taux ->> 'montant_pris_en_charge')::numeric,
    now()
  ) ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'taux', v_taux,
    'heures_totales', v_compteur.heures_totales
  );
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config(
    'jolene.system_update', v_previous_system_update, true
  );
  PERFORM set_config(
    'jolene.liberal_transition', v_previous_liberal_transition, true
  );
  RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_activer_liberal()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_activer_liberal()
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Seed E2E canonique, ferme aux comptes reels et aux JWT utilisateurs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_test_seed_heures_externes_validees(
  p_soignant_id uuid,
  p_heures numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $function$
DECLARE
  v_soignant record;
  v_id uuid;
  v_previous_server_update text := COALESCE(
    current_setting('jolene.heures_externes_server_update', true), ''
  );
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Seed heures externes reserve au service_role'
      USING ERRCODE = '42501';
  END IF;
  IF p_heures IS NULL OR p_heures <= 0 OR p_heures > 10000
     OR p_heures <> trunc(p_heures) THEN
    RAISE EXCEPTION 'Les heures de fixture doivent etre un entier entre 1 et 10000'
      USING ERRCODE = '22023';
  END IF;

  SELECT s.id, s.email, s.est_compte_test, s.type_exercice
  INTO v_soignant
  FROM public.soignants s
  WHERE s.id = p_soignant_id
  FOR UPDATE;
  IF NOT FOUND
     OR COALESCE(v_soignant.est_compte_test, false) IS NOT TRUE
     OR lower(v_soignant.email) NOT LIKE 'playwright-test-caregiver-%@jolene.app'
     OR COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
    RAISE EXCEPTION 'Seed refuse : profil Playwright liberal ephemere requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT h.id
  INTO v_id
  FROM public.heures_externes_soignants h
  WHERE h.soignant_id = p_soignant_id
    AND h.source_validation_serveur = 'TEST_FIXTURE_SERVICE_ROLE'
    AND h.statut_validation = 'VALIDE'
    AND h.heures_declarees = p_heures::integer
    AND h.empreinte_snapshot_source =
        private.fn_empreinte_snapshot_heures_externes(h)
  LIMIT 1;
  IF FOUND THEN
    PERFORM private.fn_resynchroniser_compteurs_soignant(p_soignant_id);
    RETURN v_id;
  END IF;

  -- Les lignes de fixtures sont liees au profil ephemere (ON DELETE CASCADE).
  -- Remplacer une ancienne valeur technique ne touche donc jamais les donnees
  -- de demo ni une preuve reelle.
  DELETE FROM public.heures_externes_soignants h
  WHERE h.soignant_id = p_soignant_id
    AND h.source_validation_serveur = 'TEST_FIXTURE_SERVICE_ROLE';

  PERFORM set_config(
    'jolene.heures_externes_server_update', 'true', true
  );
  INSERT INTO public.heures_externes_soignants (
    soignant_id,
    etablissement_nom,
    etablissement_type,
    date_debut,
    date_fin,
    heures_declarees,
    attestation_url,
    attestation_nom_fichier,
    statut_validation,
    source_validation_serveur
  ) VALUES (
    p_soignant_id,
    'Fixture Playwright ephemere',
    'HOPITAL_PUBLIC',
    date '2018-01-01',
    date '2021-12-31',
    p_heures::integer,
    p_soignant_id::text || '/heures-externes/fixture-playwright.pdf',
    'fixture-playwright.pdf',
    'EN_ATTENTE',
    'TEST_FIXTURE_SERVICE_ROLE'
  )
  RETURNING id INTO v_id;

  UPDATE public.heures_externes_soignants h
  SET statut_validation = 'VALIDE',
      valide_le = now(),
      commentaire_validation = 'Fixture E2E service_role ephemere',
      empreinte_preuve_sha256 = encode(
        extensions.digest(
          convert_to('playwright:' || p_soignant_id::text, 'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      empreinte_snapshot_source =
        private.fn_empreinte_snapshot_heures_externes(h),
      mis_a_jour_le = now()
  WHERE h.id = v_id;

  PERFORM set_config(
    'jolene.heures_externes_server_update', v_previous_server_update, true
  );
  PERFORM private.fn_resynchroniser_compteurs_soignant(p_soignant_id);
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config(
    'jolene.heures_externes_server_update', v_previous_server_update, true
  );
  RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_test_seed_heures_externes_validees(
  uuid, numeric
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_test_seed_heures_externes_validees(
  uuid, numeric
) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. Backfill conservateur : recalcul, aucune suppression ni masquage
-- ---------------------------------------------------------------------------

DO $backfill$
DECLARE
  v_soignant_id uuid;
BEGIN
  FOR v_soignant_id IN
    SELECT s.id
    FROM public.soignants s
    ORDER BY s.id
  LOOP
    PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant_id);
  END LOOP;
END;
$backfill$;
