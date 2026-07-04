-- J2.3.B.2 — RPC fn_verifier_skip_serie_onboarding
-- Retourne {skip:bool, raison:text} selon les conditions métier
-- au moment de l'envoi (état utilisateur courant, pas au moment de la planif).

CREATE OR REPLACE FUNCTION public.fn_verifier_skip_serie_onboarding(
  p_envoi_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
STABLE
AS $$
DECLARE
  v_envoi RECORD;
  v_etab RECORD;
  v_soignant RECORD;
  v_count integer;
  v_j1_skipped boolean;
BEGIN
  SELECT * INTO v_envoi FROM serie_email_envois WHERE id = p_envoi_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('skip', true, 'raison', 'ENVOI_INTROUVABLE');
  END IF;

  -- ════════ SOIGNANT ════════
  IF v_envoi.serie = 'SOIGNANT_ONBOARDING' THEN
    SELECT prenom, nom, profession,
           rpps_verifie, mandat_facturation_signe,
           tous_documents_valides, type_exercice
    INTO v_soignant FROM soignants WHERE id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J0' THEN RETURN jsonb_build_object('skip', false); END IF;

    IF v_envoi.etape = 'J1' THEN
      -- Skip si profil "complet" (RPPS vérifié + documents valides + mandat
      -- signé pour libéraux)
      IF v_soignant.tous_documents_valides = true
         AND COALESCE(v_soignant.rpps_verifie, true) = true
         AND (v_soignant.type_exercice = 'SALARIE'
              OR v_soignant.mandat_facturation_signe = true) THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'PROFIL_DEJA_COMPLET');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J3' THEN
      -- Skip si déjà candidaté
      SELECT count(*) INTO v_count FROM candidatures WHERE soignant_id = v_envoi.utilisateur_id;
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'CANDIDATURE_DEJA_EFFECTUEE');
      END IF;
      -- Skip si J1 a été SKIPPED avec raison PROFIL_DEJA_COMPLET → c'est OK
      -- mais surtout skip si J1 SKIPPED pour profil incomplet (= on a pas
      -- réussi à le faire compléter, on insiste pas davantage)
      SELECT EXISTS(
        SELECT 1 FROM serie_email_envois
        WHERE utilisateur_id = v_envoi.utilisateur_id
          AND serie = 'SOIGNANT_ONBOARDING' AND etape = 'J1'
          AND statut = 'SKIPPED'
          AND skip_raison = 'NOTIFICATION_DESACTIVEE'
      ) INTO v_j1_skipped;
      IF v_j1_skipped THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'NOTIFICATIONS_DESACTIVEES_J1');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J7' THEN
      -- Skip si mission déjà assignée/en cours/terminée
      SELECT count(*) INTO v_count FROM missions
      WHERE soignant_assigne_id = v_envoi.utilisateur_id
        AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE');
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'MISSION_DEJA_ASSIGNEE');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;
  END IF;

  -- ════════ ÉTABLISSEMENT ════════
  IF v_envoi.serie = 'ETAB_ONBOARDING' THEN
    SELECT nom, type, contrat_service_signe, rib_s3_key
    INTO v_etab FROM etablissements WHERE id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J0' THEN RETURN jsonb_build_object('skip', false); END IF;

    IF v_envoi.etape = 'J1' THEN
      -- Skip si onboarding complet (contrat signé ET RIB uploadé non-legacy)
      IF v_etab.contrat_service_signe = true
         AND v_etab.rib_s3_key IS NOT NULL
         AND v_etab.rib_s3_key <> 'legacy/auto-backfill' THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'ONBOARDING_DEJA_COMPLET');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J3' THEN
      SELECT count(*) INTO v_count FROM missions WHERE etablissement_id = v_envoi.utilisateur_id;
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'MISSION_DEJA_PUBLIEE');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;

    IF v_envoi.etape = 'J7' THEN
      -- Skip si l'étab a reçu au moins 1 candidature
      SELECT count(*) INTO v_count FROM candidatures c
      JOIN missions m ON m.id = c.mission_id
      WHERE m.etablissement_id = v_envoi.utilisateur_id;
      IF v_count > 0 THEN
        RETURN jsonb_build_object('skip', true, 'raison', 'CANDIDATURE_DEJA_RECUE');
      END IF;
      RETURN jsonb_build_object('skip', false);
    END IF;
  END IF;

  RETURN jsonb_build_object('skip', false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_verifier_skip_serie_onboarding(uuid) TO service_role;

-- RPC fn_obtenir_donnees_template_serie : récupère les variables dynamiques
-- pour personnaliser l'email selon l'utilisateur (variables data passées
-- à send-email).
CREATE OR REPLACE FUNCTION public.fn_obtenir_donnees_template_serie(
  p_envoi_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
STABLE
AS $$
DECLARE
  v_envoi RECORD;
  v_data jsonb := '{}'::jsonb;
  v_count integer;
BEGIN
  SELECT * INTO v_envoi FROM serie_email_envois WHERE id = p_envoi_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;

  IF v_envoi.serie = 'SOIGNANT_ONBOARDING' THEN
    SELECT jsonb_build_object(
      'prenom', s.prenom, 'nom', s.nom, 'profession', s.profession,
      'lien_dashboard', 'https://jolene.app/soignant'
    ) INTO v_data FROM soignants s WHERE s.id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J3' THEN
      SELECT count(*) INTO v_count FROM missions WHERE statut = 'OUVERTE';
      v_data := v_data || jsonb_build_object('nb_missions_actives', v_count);
    END IF;
    IF v_envoi.etape = 'J7' THEN
      SELECT count(*) INTO v_count FROM candidatures WHERE soignant_id = v_envoi.utilisateur_id;
      v_data := v_data || jsonb_build_object('nb_candidatures', v_count);
    END IF;
  ELSIF v_envoi.serie = 'ETAB_ONBOARDING' THEN
    SELECT jsonb_build_object(
      'nom_etablissement', e.nom, 'type_etablissement', e.type::text,
      'contrat_signe', e.contrat_service_signe,
      'lien_dashboard', 'https://jolene.app/etablissement'
    ) INTO v_data FROM etablissements e WHERE e.id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J3' OR v_envoi.etape = 'J7' THEN
      SELECT count(*) INTO v_count FROM missions WHERE etablissement_id = v_envoi.utilisateur_id;
      v_data := v_data || jsonb_build_object('nb_missions_publiees', v_count);
    END IF;
    IF v_envoi.etape = 'J7' THEN
      SELECT count(*) INTO v_count FROM candidatures c
      JOIN missions m ON m.id = c.mission_id
      WHERE m.etablissement_id = v_envoi.utilisateur_id;
      v_data := v_data || jsonb_build_object('nb_candidatures_recues', v_count);
    END IF;
  END IF;

  RETURN v_data;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_donnees_template_serie(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
