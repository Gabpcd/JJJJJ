-- ============================================================
-- CP-LITIGES-2 — Triggers et RPCs fondamentales
-- ============================================================
-- Sub-PR 2 quater — Extension système litiges (Option A+)
--
-- Dépend de CP-LITIGES-1 (20260417130000) : enums, colonnes,
-- parametres_litiges, index, backfill.
--
-- Livre :
--   1. fn_ajouter_jours_ouvres(ts, n) — jours ouvrés FR (exclut sam/dim/fériés)
--   2. trg_litige_mapping_categorie — auto-remplit categorie_litige
--   3. trg_litige_gel_degel_facture — gel sur OUVERT, dégel sur RESOLU
--   4. fn_fenetre_contestation_ouverte(type, mission, facture) — 3 fenêtres
--   5. fn_admin_creer_litige_force — bypass fenêtre, admin only, audit RGPD
--   6. Nouvelle signature fn_ouvrir_litige_rate_limited(uuid, type_litige, text)
--   7. Wrapper rétrocompat fn_ouvrir_litige_rate_limited(uuid, text) DEPRECATED
--
-- CHOIX PRODUIT — trg_presence_auto_litige NON créé en CP2 :
--   Option retenue : le cron CP-LITIGES-4 requête directement les présences
--   remplissant les conditions (statut ABSENT + validée > 48h + sans litige)
--   plutôt que de poser un flag via trigger. Cela évite :
--     - une colonne supplémentaire sur presences
--     - un état intermédiaire à synchroniser
--     - un cas limite si UPDATE transitoire puis re-UPDATE
--   Le cron CP4 fera : SELECT p.* FROM presences p WHERE p.statut_detecte = 'ABSENT'
--   AND p.valide_le < NOW() - INTERVAL '48 hours' AND NOT EXISTS (litige associé).
--
-- PRECISION 14 — Gel par période :
--   Les colonnes periode_debut/periode_fin sur factures_honoraires arrivent
--   avec Partie 2 (facturation hebdo libérale). À ce stade, le gel se fait
--   par mission_id entière. Le trigger sera étendu quand Partie 2 intégrera
--   la dimension période.
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. fn_ajouter_jours_ouvres — calendrier FR (exclut WE + fériés)
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_ajouter_jours_ouvres(
  p_date TIMESTAMPTZ,
  p_nb_jours INTEGER
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_date TIMESTAMPTZ := p_date;
  v_count INTEGER := 0;
  v_step INTEGER := CASE WHEN p_nb_jours >= 0 THEN 1 ELSE -1 END;
  v_target INTEGER := abs(p_nb_jours);
  v_dow INTEGER;
  v_is_feried BOOLEAN;
BEGIN
  IF v_target = 0 THEN
    RETURN v_date;
  END IF;

  WHILE v_count < v_target LOOP
    v_date := v_date + (v_step || ' day')::INTERVAL;
    v_dow := EXTRACT(DOW FROM v_date)::INTEGER;   -- 0=Dim, 6=Sam
    IF v_dow IN (0, 6) THEN
      CONTINUE;
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM public.jours_feries_fr
      WHERE date_ferie = v_date::DATE
    ) INTO v_is_feried;
    IF v_is_feried THEN
      CONTINUE;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_date;
END;
$$;

COMMENT ON FUNCTION public.fn_ajouter_jours_ouvres(TIMESTAMPTZ, INTEGER) IS
  'Ajoute N jours ouvrés (FR) en excluant samedi, dimanche et jours_feries_fr. N négatif autorisé.';

GRANT EXECUTE ON FUNCTION public.fn_ajouter_jours_ouvres(TIMESTAMPTZ, INTEGER) TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────
-- 2. trg_litige_mapping_categorie — sync categorie_litige depuis type_litige
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_trg_litige_mapping_categorie()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.categorie_litige := CASE NEW.type_litige
    WHEN 'ABSENCE_SOIGNANT'                   THEN 'PRESENCE'::public.categorie_litige
    WHEN 'DEPART_ANTICIPE'                    THEN 'PRESENCE'::public.categorie_litige
    WHEN 'RETARD_IMPORTANT'                   THEN 'PRESENCE'::public.categorie_litige
    WHEN 'DESACCORD_HEURES_POINTAGE'          THEN 'PRESENCE'::public.categorie_litige
    WHEN 'DESACCORD_MONTANT_FACTURE'          THEN 'FINANCIER'::public.categorie_litige
    WHEN 'NON_PAIEMENT'                       THEN 'FINANCIER'::public.categorie_litige
    WHEN 'FRAIS_COMPLEMENTAIRES'              THEN 'FINANCIER'::public.categorie_litige
    WHEN 'CONDITIONS_MISSION_NON_RESPECTEES'  THEN 'CONDITIONS'::public.categorie_litige
    WHEN 'SECURITE_DANGER'                    THEN 'CONDITIONS'::public.categorie_litige
    WHEN 'COMPORTEMENT_SOIGNANT'              THEN 'COMPORTEMENT'::public.categorie_litige
    WHEN 'COMPORTEMENT_ETABLISSEMENT'         THEN 'COMPORTEMENT'::public.categorie_litige
    ELSE 'AUTRE'::public.categorie_litige
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_litige_mapping_categorie ON public.litiges;
CREATE TRIGGER trg_litige_mapping_categorie
  BEFORE INSERT OR UPDATE OF type_litige ON public.litiges
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_litige_mapping_categorie();

COMMENT ON TRIGGER trg_litige_mapping_categorie ON public.litiges IS
  'Auto-remplit categorie_litige depuis type_litige selon mapping fixé.';

-- ──────────────────────────────────────────────────────────────
-- 3. trg_litige_gel_degel_facture — gel/dégel automatique sur statut
-- ──────────────────────────────────────────────────────────────
-- Gel :
--   - INSERT avec statut OUVERT OU UPDATE vers OUVERT
--   - Si est_informatif → aucun gel (litige hors fenêtre)
--   - Si categorie=FINANCIER ET facture_id NOT NULL → gèle UNIQUEMENT cette facture
--   - Sinon (PRESENCE, CONDITIONS, COMPORTEMENT) → gèle toutes les factures
--     NORMAL de la mission (pas PAYEE, pas déjà EN_ATTENTE_LITIGE)
--   - Garde-fou : jamais sur statut='PAYEE' (avoirs gèreront ça en CP3)
--
-- Dégel :
--   - UPDATE vers RESOLU/RESOLU_*/FERME/CLOTURE
--   - UPDATE factures_honoraires SET statut_litige = 'LITIGE_RESOLU_CONFIRME'
--     pour toutes les factures liées à ce litige (via litige_id).
--   - CP3 (fn_admin_resoudre_litige) surchargera à 'LITIGE_RESOLU_AJUSTE'
--     si un ajustement financier a été appliqué.

CREATE OR REPLACE FUNCTION public.fn_trg_litige_gel_degel_facture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_statuts_ouverts TEXT[] := ARRAY['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE'];
  v_statuts_resolus TEXT[] := ARRAY['RESOLU', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME', 'CLOTURE'];
  v_became_open BOOLEAN;
  v_became_resolved BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_became_open := NEW.statut = ANY(v_statuts_ouverts);
    v_became_resolved := FALSE;
  ELSE  -- UPDATE
    v_became_open := NEW.statut = ANY(v_statuts_ouverts) AND (OLD.statut IS NULL OR OLD.statut <> NEW.statut);
    v_became_resolved := NEW.statut = ANY(v_statuts_resolus) AND (OLD.statut IS NULL OR OLD.statut <> NEW.statut);
  END IF;

  -- GEL
  IF v_became_open AND NOT NEW.est_informatif THEN
    IF NEW.categorie_litige = 'FINANCIER' AND NEW.facture_id IS NOT NULL THEN
      UPDATE public.factures_honoraires
         SET statut_litige = 'EN_ATTENTE_LITIGE',
             litige_id = NEW.id
       WHERE id = NEW.facture_id
         AND statut_litige = 'NORMAL'
         AND statut <> 'PAYEE';
    ELSIF NEW.categorie_litige IN ('PRESENCE', 'CONDITIONS', 'COMPORTEMENT') THEN
      UPDATE public.factures_honoraires
         SET statut_litige = 'EN_ATTENTE_LITIGE',
             litige_id = NEW.id
       WHERE mission_id = NEW.mission_id
         AND statut_litige = 'NORMAL'
         AND statut <> 'PAYEE';
    END IF;
  END IF;

  -- DÉGEL
  IF v_became_resolved THEN
    UPDATE public.factures_honoraires
       SET statut_litige = 'LITIGE_RESOLU_CONFIRME'
     WHERE litige_id = NEW.id
       AND statut_litige = 'EN_ATTENTE_LITIGE';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_litige_gel_degel_facture ON public.litiges;
CREATE TRIGGER trg_litige_gel_degel_facture
  AFTER INSERT OR UPDATE OF statut ON public.litiges
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_litige_gel_degel_facture();

COMMENT ON TRIGGER trg_litige_gel_degel_facture ON public.litiges IS
  'Gèle les factures impactées lors de l''ouverture du litige, dégèle à la résolution.';

-- ──────────────────────────────────────────────────────────────
-- 4. fn_fenetre_contestation_ouverte — 3 fenêtres différenciées
-- ──────────────────────────────────────────────────────────────
-- Retourne TRUE si la fenêtre est ouverte pour ce type/mission/facture.
-- Fenêtres (paramétrées via parametres_litiges) :
--   F1 — Pointage (48h post-validation présence)  : ABSENCE, DEPART_ANTICIPE,
--        RETARD_IMPORTANT, DESACCORD_HEURES_POINTAGE
--   F2 — Facture libéral (48h post-émission)       : DESACCORD_MONTANT_FACTURE,
--        FRAIS_COMPLEMENTAIRES (si soignant libéral)
--   F3 — Paiement salarié (60j post-paiement)      : mêmes types si salarié
--   Sans limite                                    : SECURITE_DANGER
--   6 mois post-mission                            : COMPORTEMENT_*, CONDITIONS_*
--   Toujours ouvert                                : NON_PAIEMENT, AUTRE

CREATE OR REPLACE FUNCTION public.fn_fenetre_contestation_ouverte(
  p_type_litige public.type_litige,
  p_mission_id UUID,
  p_facture_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_presence_validee TIMESTAMPTZ;
  v_facture_emise    TIMESTAMPTZ;
  v_facture_payee    TIMESTAMPTZ;
  v_mission_fin      TIMESTAMPTZ;
  v_est_salarie      BOOLEAN;
  v_soignant_id      UUID;
  v_delai_pointage   INTEGER;
  v_delai_liberal    INTEGER;
  v_delai_salarie    INTEGER;
  v_delai_compo_mois INTEGER;
BEGIN
  -- Types toujours ouverts
  IF p_type_litige IN ('SECURITE_DANGER', 'NON_PAIEMENT', 'AUTRE') THEN
    RETURN TRUE;
  END IF;

  -- Lecture paramètres
  SELECT valeur::INTEGER INTO v_delai_pointage   FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';
  SELECT valeur::INTEGER INTO v_delai_liberal    FROM public.parametres_litiges WHERE cle = 'delai_contestation_facture_liberal_h';
  SELECT valeur::INTEGER INTO v_delai_salarie    FROM public.parametres_litiges WHERE cle = 'delai_contestation_paiement_salarie_j';
  SELECT valeur::INTEGER INTO v_delai_compo_mois FROM public.parametres_litiges WHERE cle = 'delai_comportement_mois';

  -- F1 — Pointage
  IF p_type_litige IN ('ABSENCE_SOIGNANT', 'DEPART_ANTICIPE', 'RETARD_IMPORTANT', 'DESACCORD_HEURES_POINTAGE') THEN
    SELECT valide_le INTO v_presence_validee
      FROM public.presences
     WHERE mission_id = p_mission_id
       AND valide_le IS NOT NULL
     ORDER BY valide_le DESC
     LIMIT 1;
    IF v_presence_validee IS NULL THEN
      -- Pas encore validée : fenêtre ouverte (pointage en cours)
      RETURN TRUE;
    END IF;
    RETURN v_presence_validee + make_interval(hours => v_delai_pointage) > NOW();
  END IF;

  -- F2/F3 — Facture (libéral 48h / salarié 60j)
  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'FRAIS_COMPLEMENTAIRES') THEN
    IF p_facture_id IS NULL THEN
      -- Pas de facture référencée : on considère ouvert par défaut
      RETURN TRUE;
    END IF;

    SELECT f.date_emission, f.date_paiement
      INTO v_facture_emise, v_facture_payee
      FROM public.factures_honoraires f
     WHERE f.id = p_facture_id;

    IF v_facture_emise IS NULL THEN
      RETURN FALSE;
    END IF;

    -- Détection statut soignant (via mission → soignant assigné)
    SELECT m.soignant_assigne_id INTO v_soignant_id
      FROM public.missions m WHERE m.id = p_mission_id;
    SELECT COALESCE(s.est_salarie_etablissement, FALSE) INTO v_est_salarie
      FROM public.soignants s WHERE s.id = v_soignant_id;

    IF v_est_salarie AND v_facture_payee IS NOT NULL THEN
      RETURN v_facture_payee + make_interval(days => v_delai_salarie) > NOW();
    ELSE
      RETURN v_facture_emise + make_interval(hours => v_delai_liberal) > NOW();
    END IF;
  END IF;

  -- 6 mois post-mission pour COMPORTEMENT_* et CONDITIONS_*
  IF p_type_litige IN ('COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT', 'CONDITIONS_MISSION_NON_RESPECTEES') THEN
    SELECT m.fin_le INTO v_mission_fin FROM public.missions m WHERE m.id = p_mission_id;
    IF v_mission_fin IS NULL THEN
      RETURN TRUE;
    END IF;
    RETURN v_mission_fin + make_interval(months => v_delai_compo_mois) > NOW();
  END IF;

  -- Fallback défensif (ne devrait pas être atteint)
  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.fn_fenetre_contestation_ouverte(public.type_litige, UUID, UUID) IS
  'Vérifie si la fenêtre de contestation est ouverte pour ce type de litige (F1 pointage 48h / F2 facture 48h / F3 paiement salarié 60j / 6 mois COMPORTEMENT).';

GRANT EXECUTE ON FUNCTION public.fn_fenetre_contestation_ouverte(public.type_litige, UUID, UUID)
  TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────
-- 5. fn_admin_creer_litige_force — admin bypass fenêtre + audit
-- ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_admin_creer_litige_force(
  p_mission_id UUID,
  p_type_litige public.type_litige,
  p_motif TEXT,
  p_raison_bypass TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mission RECORD;
  v_litige_id UUID;
  v_est_informatif BOOLEAN;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis pour cette opération.');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;
  IF length(trim(COALESCE(p_raison_bypass, ''))) < 10 THEN
    RETURN jsonb_build_object('error', 'La raison du bypass doit contenir au moins 10 caractères (traçabilité).');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id
    INTO v_mission
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  -- Si fenêtre fermée → litige informatif (pas de gel facture, juste traçabilité)
  v_est_informatif := NOT public.fn_fenetre_contestation_ouverte(
    p_type_litige, p_mission_id, NULL
  );

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, est_informatif
  )
  VALUES (
    p_mission_id, v_mission.soignant_assigne_id, v_mission.etablissement_id, 'ADMIN',
    trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif
  )
  RETURNING id INTO v_litige_id;

  -- Audit RGPD obligatoire avec motif bypass
  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_FORCE_CREATION',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'est_informatif', v_est_informatif,
      'raison_bypass', trim(p_raison_bypass)
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif
  );
END;
$$;

COMMENT ON FUNCTION public.fn_admin_creer_litige_force(UUID, public.type_litige, TEXT, TEXT) IS
  'Admin-only : crée un litige en bypassant la fenêtre de contestation. Flag est_informatif=TRUE si hors fenêtre. Audit RGPD obligatoire avec raison.';

GRANT EXECUTE ON FUNCTION public.fn_admin_creer_litige_force(UUID, public.type_litige, TEXT, TEXT)
  TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────
-- 6. Nouvelle signature fn_ouvrir_litige_rate_limited (3 args)
-- ──────────────────────────────────────────────────────────────
-- Signature canonique à utiliser côté frontend.

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id UUID,
  p_type_litige public.type_litige,
  p_motif TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_mission    RECORD;
  v_existing   INT;
  v_recent     INT;
  v_initie_par TEXT;
  v_etab_id    UUID;
  v_soignant_id UUID;
  v_presence_id UUID;
  v_facture_id UUID;
  v_rate_limit INT;
  v_litige_id  UUID;
  v_est_informatif BOOLEAN;
  v_fenetre_ouverte BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut
    INTO v_mission
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.soignant_assigne_id = v_user_id THEN
    v_initie_par  := 'SOIGNANT';
    v_etab_id     := v_mission.etablissement_id;
    v_soignant_id := v_user_id;
  ELSIF v_mission.etablissement_id = public.mon_etablissement_id() THEN
    v_initie_par  := 'ETABLISSEMENT';
    v_etab_id     := v_mission.etablissement_id;
    v_soignant_id := v_mission.soignant_assigne_id;
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante de cette mission.');
  END IF;

  -- Unicité par (mission, type) garantie par index unique partiel créé en CP1.
  -- On fait le check applicatif pour retourner une erreur explicite plutôt que
  -- une violation d'index.
  SELECT COUNT(*) INTO v_existing
    FROM public.litiges
   WHERE mission_id = p_mission_id
     AND type_litige = p_type_litige
     AND statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION');
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('error', 'Un litige de ce type est déjà ouvert pour cette mission.');
  END IF;

  -- Rate limit paramétrable (défaut 3, fenêtre 1h, inchangé depuis l'existant)
  v_rate_limit := COALESCE(
    (SELECT valeur::INT FROM public.parametres_litiges WHERE cle = 'rate_limit_litiges_par_24h'),
    3
  );
  SELECT COUNT(*) INTO v_recent
    FROM public.litiges
   WHERE (soignant_id = v_user_id OR etablissement_id = public.mon_etablissement_id())
     AND cree_le > NOW() - INTERVAL '1 hour';
  IF v_recent >= v_rate_limit THEN
    RETURN jsonb_build_object('error', 'Trop de litiges ouverts récemment. Réessayez plus tard.');
  END IF;

  -- Vérification fenêtre
  v_fenetre_ouverte := public.fn_fenetre_contestation_ouverte(p_type_litige, p_mission_id, NULL);
  v_est_informatif := NOT v_fenetre_ouverte;

  -- Si fenêtre fermée ET type pas éligible informatif → refus
  IF v_est_informatif
     AND p_type_litige NOT IN ('COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT', 'CONDITIONS_MISSION_NON_RESPECTEES')
  THEN
    RETURN jsonb_build_object(
      'error', 'Fenêtre de contestation fermée pour ce type de litige. Contactez le support.'
    );
  END IF;

  SELECT id INTO v_presence_id
    FROM public.presences WHERE mission_id = p_mission_id
   ORDER BY cree_le DESC LIMIT 1;

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, presence_id,
    initie_par, motif, statut, type_litige, est_informatif
  )
  VALUES (
    p_mission_id, v_soignant_id, v_etab_id, v_presence_id,
    v_initie_par, trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif
  )
  RETURNING id INTO v_litige_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif
  );
END;
$$;

COMMENT ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, public.type_litige, TEXT) IS
  'Ouvre un litige typé avec rate limit et vérification de fenêtre. Signature canonique (3 args).';

GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, public.type_litige, TEXT)
  TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────
-- 7. Wrapper rétrocompat fn_ouvrir_litige_rate_limited (2 args, DEPRECATED)
-- ──────────────────────────────────────────────────────────────
-- Conserve l'appel frontend existant (jusqu'à migration UI). Force type=AUTRE.
-- Sera supprimé en Sub-PR 3 (consolidation) après migration du frontend.

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id UUID,
  p_motif TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RAISE WARNING 'fn_ouvrir_litige_rate_limited(UUID, TEXT) is DEPRECATED since CP-LITIGES-2. Use 3-arg signature with type_litige.';
  RETURN public.fn_ouvrir_litige_rate_limited(
    p_mission_id,
    'AUTRE'::public.type_litige,
    p_motif
  );
END;
$$;

COMMENT ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT) IS
  'DEPRECATED. Wrapper rétrocompat vers la nouvelle signature 3-arg. Force type=AUTRE. À supprimer en Sub-PR 3.';

GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT)
  TO authenticated, service_role;

COMMIT;

-- ============================================================
-- Vérifications post-migration :
--
--   SELECT proname, pg_get_function_identity_arguments(oid)
--   FROM pg_proc WHERE proname IN (
--     'fn_ajouter_jours_ouvres',
--     'fn_fenetre_contestation_ouverte',
--     'fn_admin_creer_litige_force',
--     'fn_ouvrir_litige_rate_limited',
--     'fn_trg_litige_mapping_categorie',
--     'fn_trg_litige_gel_degel_facture'
--   );
--   -- attendu : 2 versions de fn_ouvrir_litige_rate_limited (overload)
--
--   SELECT tgname FROM pg_trigger
--   WHERE tgrelid = 'public.litiges'::regclass AND NOT tgisinternal;
--   -- attendu inclut : trg_litige_mapping_categorie, trg_litige_gel_degel_facture
-- ============================================================
