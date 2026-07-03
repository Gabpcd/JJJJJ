CREATE OR REPLACE FUNCTION public.fn_repondre_litige(p_litige_id uuid, p_reponse text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_uid UUID := auth.uid();
    v_litige RECORD;
    v_auteur TEXT;
    v_type_acteur TEXT;
    v_reponse_safe TEXT;
    v_date_str TEXT;
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    IF v_litige.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME') THEN
        RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé');
    END IF;
    IF v_uid = v_litige.soignant_id THEN
      v_auteur := 'Soignant'; v_type_acteur := 'SOIGNANT';
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
      v_auteur := 'Établissement'; v_type_acteur := 'ADMIN_ETABLISSEMENT';
    ELSIF est_admin() THEN
      v_auteur := 'Admin'; v_type_acteur := 'ADMIN_PLATEFORME';
    ELSE
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    v_reponse_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_reponse), ''), ''), '<[^>]*>', '', 'g'), 2000);
    IF LENGTH(v_reponse_safe) < 10 THEN
      RETURN jsonb_build_object('error', 'La réponse doit contenir au moins 10 caractères');
    END IF;
    v_date_str := TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI');

    UPDATE litiges SET
        reponse = CASE WHEN reponse IS NOT NULL AND reponse != ''
            THEN reponse || E'\n---\n[' || v_date_str || '] ' || v_auteur || ': ' || v_reponse_safe
            ELSE '[' || v_date_str || '] ' || v_auteur || ': ' || v_reponse_safe END,
        statut = 'EN_DISCUSSION'
    WHERE id = p_litige_id;

    -- Audit RGPD (Art. 32 — traçabilité des modifications de litige)
    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    PERFORM fn_ecrire_audit(
      v_uid, v_type_acteur, 'LITIGE_REPONSE',
      'litige', p_litige_id, NULL,
      jsonb_build_object(
        'mission_id', v_litige.mission_id,
        'motif_original', v_litige.motif,
        'auteur_reponse', v_auteur,
        'reponse_length', LENGTH(v_reponse_safe),
        'nouveau_statut', 'EN_DISCUSSION'
      ),
      v_ip, v_user_agent
    );

    RETURN jsonb_build_object('success', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_resoudre_litige(p_litige_id uuid, p_statut text, p_resolution text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_litige RECORD;
    v_mission RECORD;
    v_score_avant NUMERIC;
    v_score_apres NUMERIC;
BEGIN
    IF NOT est_admin() THEN
        RETURN '{"error":"Seul l''administrateur peut résoudre un litige"}'::JSONB;
    END IF;
    IF p_statut NOT IN ('RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME') THEN
        RETURN '{"error":"Statut invalide"}'::JSONB;
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN '{"error":"Litige introuvable"}'::JSONB; END IF;

    SELECT * INTO v_mission FROM missions WHERE id = v_litige.mission_id;

    UPDATE litiges SET
        statut = p_statut,
        resolution = p_resolution,
        resolu_par = auth.uid(),
        resolu_le = NOW()
    WHERE id = p_litige_id;

    IF p_statut = 'RESOLU_SOIGNANT' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'TERMINEE', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = TRUE, valide_le = NOW(), motif_litige = NULL
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;
        UPDATE soignants SET score_fiabilite = LEAST(100, COALESCE(score_fiabilite, 50) + 3), modifie_le = NOW()
        WHERE id = v_litige.soignant_id;

    ELSIF p_statut = 'RESOLU_ETABLISSEMENT' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = FALSE, motif_litige = p_resolution
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;

        SELECT score_fiabilite INTO v_score_avant FROM soignants WHERE id = v_litige.soignant_id;

        UPDATE soignants SET total_litiges_perdus = COALESCE(total_litiges_perdus, 0) + 1, modifie_le = NOW()
        WHERE id = v_litige.soignant_id;

        v_score_apres := public.fn_recalculer_score_fiabilite_soignant(v_litige.soignant_id);

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_litige.soignant_id,
          p_type_acteur := 'SYSTEME',
          p_action := 'SCORE_FIABILITE_PENALITE_LITIGE',
          p_type_ressource := 'litige',
          p_id_ressource := p_litige_id,
          p_details := jsonb_build_object(
            'mission_id', v_litige.mission_id,
            'score_avant', v_score_avant,
            'score_apres', v_score_apres,
            'delta', COALESCE(v_score_apres, 0) - COALESCE(v_score_avant, 0)
          )
        );

    ELSIF p_statut = 'RESOLU_ADMIN' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'TERMINEE', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = TRUE, valide_le = NOW()
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;

    ELSIF p_statut = 'FERME' THEN
        IF v_mission.statut = 'LITIGE' THEN
            UPDATE missions SET statut = 'TERMINEE', modifie_le = NOW() WHERE id = v_litige.mission_id;
        END IF;
        UPDATE presences SET valide_par_etablissement = TRUE, valide_le = NOW()
        WHERE mission_id = v_litige.mission_id AND soignant_id = v_litige.soignant_id;
    END IF;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire) VALUES
    (v_litige.soignant_id, 'SYSTEM',
        CASE p_statut
            WHEN 'RESOLU_SOIGNANT' THEN 'Litige résolu en votre faveur ✅'
            WHEN 'RESOLU_ETABLISSEMENT' THEN 'Litige résolu en faveur de l''établissement'
            WHEN 'RESOLU_ADMIN' THEN 'Litige résolu par l''administrateur'
            WHEN 'FERME' THEN 'Litige clôturé ✅'
        END,
        COALESCE(p_resolution, 'Le litige a été résolu.'),
        '/soignant/missions', 'SOIGNANT'),
    (v_litige.etablissement_id, 'SYSTEM',
        CASE p_statut
            WHEN 'RESOLU_SOIGNANT' THEN 'Litige résolu en faveur du soignant'
            WHEN 'RESOLU_ETABLISSEMENT' THEN 'Litige résolu en votre faveur ✅'
            WHEN 'RESOLU_ADMIN' THEN 'Litige résolu par l''administrateur'
            WHEN 'FERME' THEN 'Litige clôturé ✅'
        END,
        COALESCE(p_resolution, 'Le litige a été résolu.'),
        '/etablissement/missions', 'ETABLISSEMENT');

    PERFORM fn_ecrire_audit_safe(
        auth.uid(), 'ADMIN_PLATEFORME', 'MISSION_LITIGE',
        'litige', p_litige_id, NULL,
        jsonb_build_object('resolution', p_statut, 'mission_id', v_litige.mission_id,
            'soignant_id', v_litige.soignant_id, 'details', p_resolution),
        NULL, 'rpc'
    );

    RETURN jsonb_build_object('success', true, 'statut', p_statut,
        'mission_statut', CASE
            WHEN p_statut = 'RESOLU_ETABLISSEMENT' THEN 'ANNULEE_PAR_ETABLISSEMENT'
            ELSE 'TERMINEE' END);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_retirer_exclusion(p_exclu_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid := auth.uid();
  v_exclusion_id uuid;
  v_type text;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT id, type_exclu_par INTO v_exclusion_id, v_type
  FROM exclusions
  WHERE exclu_par = v_caller_id AND exclu_id = p_exclu_id
  LIMIT 1;

  IF v_exclusion_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Exclusion introuvable');
  END IF;

  DELETE FROM exclusions WHERE id = v_exclusion_id;

  PERFORM fn_ecrire_audit_safe(
    v_caller_id,
    CASE WHEN v_type = 'ETABLISSEMENT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    'EXCLUSION_SUPPRIMEE',
    'exclusion', p_exclu_id, NULL,
    jsonb_build_object('exclusion_id', v_exclusion_id),
    NULL, 'rpc'
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_repondre_proposition(p_candidature_id uuid, p_accepter boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_cand RECORD;
    v_mission RECORD;
    v_soignant RECORD;
    v_user_id UUID := auth.uid();
    v_result JSONB;
BEGIN
    SELECT c.*, m.statut AS mission_statut, m.id AS mid,
           m.type_contrat_recherche AS mission_type_contrat_recherche
    INTO v_cand
    FROM candidatures c
    JOIN missions m ON m.id = c.mission_id
    WHERE c.id = p_candidature_id;

    IF v_cand IS NULL THEN
        RETURN jsonb_build_object('error', 'Candidature introuvable');
    END IF;

    IF v_cand.soignant_id != v_user_id THEN
        RETURN jsonb_build_object('error', 'Acces refuse');
    END IF;

    IF v_cand.statut != 'PROPOSEE' THEN
        RETURN jsonb_build_object('error', 'Cette proposition n est plus en attente');
    END IF;

    IF p_accepter THEN
        SELECT * INTO v_soignant FROM soignants WHERE id = v_cand.soignant_id;

        IF v_soignant.type_exercice = 'MIXTE' AND v_cand.mission_type_contrat_recherche = 'TOUS' THEN
            IF v_cand.type_contrat_choisi IS NULL OR v_cand.type_contrat_choisi NOT IN ('SALARIE', 'LIBERAL') THEN
                RETURN jsonb_build_object(
                    'error', 'E16_CANDIDATURE_ORPHELINE',
                    'message', 'Cette proposition a ete creee avant correctif E16. Le soignant doit re-candidater avec son choix de contrat (salarie ou liberal).',
                    'candidature_id', p_candidature_id
                );
            END IF;
        END IF;

        UPDATE candidatures SET statut = 'ACCEPTEE', traite_le = NOW() WHERE id = p_candidature_id;

        v_result := fn_accepter_mission(v_cand.mid, v_cand.type_contrat_choisi);

        IF v_result ? 'error' THEN
            UPDATE candidatures SET statut = 'PROPOSEE', traite_le = NULL WHERE id = p_candidature_id;
            RETURN v_result;
        END IF;

        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'Proposition acceptee',
            'choix_applique', v_cand.type_contrat_choisi,
            'contrat_id', v_result->>'contrat_id',
            'contrat_numero', v_result->>'contrat_numero'
        );
    ELSE
        UPDATE candidatures SET statut = 'REFUSEE', traite_le = NOW() WHERE id = p_candidature_id;
        RETURN jsonb_build_object('success', TRUE, 'message', 'Proposition refusee');
    END IF;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_repartition_heures_soignant(p_periode_jours integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_periode INTEGER;
  v_since TIMESTAMPTZ;
  v_total NUMERIC;
  v_nuit NUMERIC;
  v_dimanche NUMERIC;
  v_ferie NUMERIC;
  v_jour NUMERIC;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_periode := GREATEST(COALESCE(p_periode_jours, 30), 1);
  v_since := NOW() - (v_periode || ' days')::interval;

  SELECT
    COALESCE(SUM(duree_heures), 0),
    COALESCE(SUM(heures_nuit), 0),
    COALESCE(SUM(heures_dimanche), 0),
    COALESCE(SUM(heures_ferie), 0)
  INTO v_total, v_nuit, v_dimanche, v_ferie
  FROM missions
  WHERE soignant_assigne_id = v_uid
    AND statut = 'TERMINEE'
    AND fin_le >= v_since;

  v_jour := GREATEST(v_total - (v_nuit + v_dimanche + v_ferie), 0);

  RETURN jsonb_build_object(
    'total_heures', ROUND(v_total::numeric, 1),
    'periode_jours', v_periode,
    'jour', ROUND(v_jour::numeric, 1),
    'nuit', ROUND(v_nuit::numeric, 1),
    'dimanche', ROUND(v_dimanche::numeric, 1),
    'ferie', ROUND(v_ferie::numeric, 1)
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_resolve_template_contrat(p_type_contrat text, p_profession text, p_type_etab text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slug text;
  v_template RECORD;
  v_profession_court text;
BEGIN
  -- Tentative de matching spécifique : LIBERAL_<PROFESSION>_<TYPE_ETAB>
  IF p_type_contrat IN ('REMPLACEMENT_LIBERAL', 'LIBERAL') AND p_profession IS NOT NULL AND p_type_etab IS NOT NULL THEN
    -- Normalisation profession : enlever "_LIBERAL" / "IDE_LIBERAL" → "IDE", garder MEDECIN, DENTISTE, etc.
    v_profession_court := regexp_replace(upper(p_profession), '_LIBERAL$', '');
    v_slug := 'LIBERAL_' || v_profession_court || '_' || upper(p_type_etab);
    SELECT type_contrat, nom, version INTO v_template
    FROM public.templates_contrat
    WHERE type_contrat = v_slug AND est_actif = true
    ORDER BY version DESC LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'slug', v_template.type_contrat,
        'nom', v_template.nom, 'version', v_template.version,
        'match', 'specifique'
      );
    END IF;
  END IF;

  -- Fallback : master
  IF p_type_contrat IN ('REMPLACEMENT_LIBERAL', 'LIBERAL') THEN
    v_slug := 'REMPLACEMENT_LIBERAL';
  ELSE
    v_slug := p_type_contrat; -- CDD, etc.
  END IF;

  SELECT type_contrat, nom, version INTO v_template
  FROM public.templates_contrat
  WHERE type_contrat = v_slug AND est_actif = true
  ORDER BY version DESC LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Aucun template actif pour ' || v_slug);
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'slug', v_template.type_contrat,
    'nom', v_template.nom, 'version', v_template.version,
    'match', 'master_fallback'
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_reset_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    UPDATE public.soignants
    SET onboarding_etapes_completees = '[]'::jsonb,
        onboarding_termine_le = NULL
    WHERE id = v_uid;
    RETURN jsonb_build_object('success', true, 'role', 'SOIGNANT');
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    UPDATE public.etablissements
    SET onboarding_etapes_completees = '[]'::jsonb,
        onboarding_termine_le = NULL
    WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', true, 'role', 'ETAB');
  END IF;

  RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_retirer_candidature(p_candidature_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_statut text;
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT statut, soignant_id INTO v_statut, v_owner
  FROM public.candidatures WHERE id = p_candidature_id;

  IF v_statut IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Candidature introuvable');
  END IF;
  IF v_owner <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;
  IF v_statut <> 'EN_ATTENTE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'La candidature a déjà été traitée et ne peut plus être retirée ici.');
  END IF;

  DELETE FROM public.candidatures WHERE id = p_candidature_id;
  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rgpd_purge_automatique_inactifs()
 RETURNS TABLE(soignant_purge_id uuid, derniere_activite timestamp with time zone, action_effectuee text)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_date_limite TIMESTAMPTZ := NOW() - INTERVAL '2 years';
    v_sg RECORD;
BEGIN
    FOR v_sg IN
        SELECT s.id, s.email, s.derniere_activite_le
        FROM soignants s
        WHERE s.derniere_activite_le < v_date_limite
          AND s.supprime_le IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM missions m
              WHERE m.soignant_assigne_id = s.id
                AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'LITIGE')
          )
    LOOP
        -- Anonymiser les données personnelles
        UPDATE soignants SET
            prenom = 'ANONYMISE', nom = 'ANONYMISE',
            email = 'purge_' || v_sg.id || '@anonymise.local',
            telephone = NULL, date_naissance = NULL,
            adresse_lat = NULL, adresse_lng = NULL,
            supprime_le = NOW(), modifie_le = NOW()
        WHERE id = v_sg.id;

        -- Anonymiser les documents
        UPDATE documents_soignants SET
            s3_cle = 'PURGE', nom_fichier = 'PURGE',
            supprime_le = NOW(), modifie_le = NOW()
        WHERE soignant_id = v_sg.id;

        -- Anonymiser les données de terminaux dans les présences
        UPDATE presences SET
            arrivee_id_terminal = NULL, depart_id_terminal = NULL,
            arrivee_ip = NULL, depart_ip = NULL
        WHERE soignant_id = v_sg.id;

        -- Écrire dans le journal d'audit
        PERFORM fn_ecrire_audit(
            NULL, 'SYSTEME', 'RGPD_SUPPRESSION_DONNEES',
            'soignant', v_sg.id, NULL,
            jsonb_build_object(
                'motif', 'Purge automatique : inactivité > 2 ans',
                'derniere_activite', v_sg.derniere_activite_le
            )
        );

        INSERT INTO demandes_rgpd (demandeur_id, type_demandeur, type_demande, statut, motif, termine_le)
        VALUES (v_sg.id, 'SOIGNANT', 'PURGE_AUTOMATIQUE', 'TERMINEE',
                'Purge auto inactivité > 2 ans (Art. 17 RGPD)', NOW());

        soignant_purge_id := v_sg.id;
        derniere_activite := v_sg.derniere_activite_le;
        action_effectuee := 'ANONYMISE_ET_SUPPRIME';
        RETURN NEXT;
    END LOOP;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rgpd_exporter_rate_limited()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_allowed BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifié');
    END IF;

    -- Garde-fou léger anti-abus : 30 exports / heure (au lieu de 2 / 24h).
    v_allowed := fn_verifier_rate_limit(v_user_id::TEXT, 'rgpd_export', 30, 3600);
    IF NOT v_allowed THEN
        RETURN jsonb_build_object('error', 'Trop d''exports en peu de temps. Réessayez dans quelques minutes.');
    END IF;

    RETURN fn_rgpd_exporter_donnees_soignant(v_user_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_revoquer_mandat_facturation(p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_signature_id uuid;
  v_version text;
  v_signed_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM soignants
    WHERE id = v_uid AND mandat_facturation_signe = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun mandat actif à révoquer');
  END IF;

  UPDATE mandats_facturation_signatures
  SET revoked_at = now()
  WHERE soignant_id = v_uid AND revoked_at IS NULL
  RETURNING id, version, signed_at INTO v_signature_id, v_version, v_signed_at;

  UPDATE soignants
  SET mandat_facturation_signe = false,
      mandat_facturation_signe_le = NULL,
      mandat_facturation_version = NULL
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'MANDAT_FACTURATION_REVOQUE',
    p_type_ressource := 'mandat_facturation',
    p_id_ressource := v_signature_id,
    p_details := jsonb_build_object(
      'version', v_version,
      'signed_at', v_signed_at,
      'revoked_at', now(),
      'motif', p_motif
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'signature_id', v_signature_id,
    'version', v_version,
    'revoked_at', now()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_revoquer_contrat_service(p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_sig_id uuid;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  SELECT id INTO v_sig_id FROM contrats_service_signatures
   WHERE etablissement_id = v_etab_id AND revoked_at IS NULL;
  IF v_sig_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun contrat actif à révoquer');
  END IF;

  UPDATE contrats_service_signatures
  SET revoked_at = now(), motif_revocation = p_motif
  WHERE id = v_sig_id;

  PERFORM set_config('app.internal_operation', 'true', true);
  UPDATE etablissements
  SET contrat_service_signe = false, contrat_service_signe_le = NULL
  WHERE id = v_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_etab_id,
    p_details := jsonb_build_object('type', 'contrat_service_jolene_revoque', 'motif', p_motif)
  );

  RETURN jsonb_build_object('success', true, 'message', 'Contrat de service révoqué. Vous ne pouvez plus publier de nouvelles missions.');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_revoquer_api_key(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := est_admin();
  v_etab_id uuid := mon_etablissement_id();
  v_target_etab uuid;
BEGIN
  SELECT etablissement_id INTO v_target_etab FROM public.api_keys WHERE id = p_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Clé introuvable');
  END IF;

  IF NOT v_is_admin AND v_target_etab IS DISTINCT FROM v_etab_id THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.api_keys SET actif = false WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor, CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'API_KEY_REVOQUEE', 'api_key', p_id,
    NULL, jsonb_build_object('id', p_id), NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_revoquer_membre(p_membre_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_membre RECORD;
  v_perms jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_membre FROM public.membres_etablissement WHERE id = p_membre_id;
  IF v_membre IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MEMBRE_INTROUVABLE');
  END IF;

  SELECT public.fn_mes_permissions_etab(v_membre.etablissement_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Empêcher la révocation du dernier PROPRIETAIRE
  IF v_membre.role = 'PROPRIETAIRE' AND NOT EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = v_membre.etablissement_id
      AND role = 'PROPRIETAIRE'
      AND actif = true
      AND id != p_membre_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DERNIER_PROPRIETAIRE');
  END IF;

  UPDATE public.membres_etablissement
  SET actif = false, maj_le = now()
  WHERE id = p_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', p_membre_id,
    jsonb_build_object(
      'evenement', 'MEMBRE_REVOQUE',
      'role', v_membre.role,
      'etablissement_id', v_membre.etablissement_id
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_reverifier_blocage_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id uuid := mon_etablissement_id();
    v_paiements_retard_nb int;
    v_factures_retard_nb int;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM etablissements WHERE id = v_etab_id AND bloque_auto_le IS NOT NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE, 'message', 'Votre compte n''est pas bloqué.');
    END IF;

    -- Mêmes critères que fn_gerer_blocage_etabs (seuil 45 jours)
    SELECT COUNT(*) INTO v_paiements_retard_nb
    FROM missions m
    WHERE m.etablissement_id = v_etab_id
      AND m.type_contrat_applique = 'SALARIE'
      AND m.statut = 'TERMINEE'
      AND m.fin_le < NOW() - INTERVAL '45 days'
      AND NOT EXISTS (
          SELECT 1 FROM paiements_soignant ps
          WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME'));

    SELECT COUNT(*) INTO v_factures_retard_nb
    FROM factures f
    WHERE f.etablissement_id = v_etab_id
      AND f.statut IN ('EMISE', 'EN_RETARD')
      AND f.date_emission < NOW() - INTERVAL '45 days';

    IF v_paiements_retard_nb = 0 AND v_factures_retard_nb = 0 THEN
        UPDATE etablissements SET bloque_auto_le = NULL, bloque_auto_raisons = NULL WHERE id = v_etab_id;
        INSERT INTO historique_blocages_etablissements (etablissement_id, action)
        VALUES (v_etab_id, 'DEBLOCAGE');
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_etab_id, 'SYSTEM', 'Publication de missions reactivee',
            'Vos obligations sont régularisées : votre compte est à nouveau autorisé à publier des missions.',
            '/etablissement/tableau-de-bord', 'ETABLISSEMENT');
        RETURN jsonb_build_object('success', TRUE, 'debloque', TRUE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE,
        'paiements_retard_nb', v_paiements_retard_nb,
        'factures_retard_nb', v_factures_retard_nb,
        'message', 'Des obligations restent en retard — régularisez-les puis réessayez.');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rgpd_exporter_donnees_soignant(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := p_soignant_id;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Identifiant soignant manquant');
  END IF;

  -- Anti-IDOR : un utilisateur authentifié ne peut exporter que ses propres
  -- données. auth.uid() NULL (service_role / contexte admin) : pas de restriction.
  IF auth.uid() IS NOT NULL AND auth.uid() <> v_uid THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT jsonb_build_object(
    'export_date', NOW(),
    'utilisateur_id', v_uid,
    'profil', (SELECT to_jsonb(s.*) - 'numero_secu' - 'numero_securite_sociale' FROM soignants s WHERE id = v_uid),
    'missions', (SELECT COALESCE(jsonb_agg(to_jsonb(m.*) - 'taux_commission' - 'montant_commission_ht' - 'montant_commission_tva' - 'montant_commission_ttc' ORDER BY m.cree_le DESC), '[]'::jsonb) FROM missions m WHERE m.soignant_assigne_id = v_uid),
    'candidatures', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.cree_le DESC), '[]'::jsonb) FROM candidatures c WHERE c.soignant_id = v_uid),
    'presences', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM presences p WHERE p.soignant_id = v_uid),
    'factures_honoraires', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',f.id,'numero_facture',f.numero_facture,'mission_id',f.mission_id,'etablissement_id',f.etablissement_id,'montant_ht',f.montant_ht,'montant_ttc',f.montant_ttc,'taux_tva',f.taux_tva,'exoneration_tva',f.exoneration_tva,'date_emission',f.date_emission,'date_echeance',f.date_echeance,'date_paiement',f.date_paiement,'statut',f.statut,'type_document',f.type_document,'pdf_s3_key',f.pdf_s3_key) ORDER BY f.date_emission DESC), '[]'::jsonb) FROM factures_honoraires f WHERE f.soignant_id = v_uid),
    'bulletins_paie', (SELECT COALESCE(jsonb_agg(to_jsonb(b.*) ORDER BY b.periode_debut DESC), '[]'::jsonb) FROM bulletins_paie b WHERE b.soignant_id = v_uid),
    'cotisations_sociales', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.calcule_le DESC), '[]'::jsonb) FROM cotisations_sociales c WHERE c.soignant_id = v_uid),
    'mandats_facturation', (SELECT COALESCE(jsonb_agg(jsonb_build_object('version',version,'signed_at',signed_at,'revoked_at',revoked_at,'ip_address',ip_address,'contenu_hash',contenu_hash) ORDER BY signed_at DESC), '[]'::jsonb) FROM mandats_facturation_signatures WHERE soignant_id = v_uid),
    'cessions_creance', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.signed_at DESC), '[]'::jsonb) FROM cessions_creance c WHERE c.soignant_id = v_uid),
    'factor_advances', (SELECT COALESCE(jsonb_agg(to_jsonb(fa.*) ORDER BY fa.cree_le DESC), '[]'::jsonb) FROM factor_advances fa WHERE fa.soignant_id = v_uid),
    'paiements_soignant', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM paiements_soignant p WHERE p.soignant_id = v_uid),
    'contrats_mission', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'mission_id',mission_id,'type_contrat',type_contrat,'numero_contrat',numero_contrat,'statut',statut,'signature_soignant_le',signature_soignant_le,'signature_etablissement_le',signature_etablissement_le,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM contrats_mission WHERE soignant_id = v_uid),
    'documents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type_document,'libelle',libelle,'statut_verification',statut_verification,'valide_jusqua',valide_jusqua,'televerse_le',televerse_le) ORDER BY televerse_le DESC), '[]'::jsonb) FROM documents_soignants WHERE soignant_id = v_uid AND supprime_le IS NULL),
    'evaluations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evalue_id = v_uid),
    'evaluations_donnees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evaluateur_id = v_uid),
    'messages_chat', (SELECT COALESCE(jsonb_agg(jsonb_build_object('conversation_id',conversation_id,'contenu',contenu,'cree_le',cree_le,'lu',lu) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_chat WHERE auteur_id = v_uid),
    'messages_litige', (SELECT COALESCE(jsonb_agg(jsonb_build_object('litige_id',litige_id,'type_auteur',type_auteur,'contenu',contenu,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_litige WHERE auteur_id = v_uid),
    'messages_mission', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'type_auteur',type_auteur,'contenu',contenu,'lu',lu,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_mission WHERE auteur_id = v_uid),
    'notifications', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type,'titre',titre,'corps',corps,'lue',lue,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notifications WHERE destinataire_id = v_uid),
    'partages_rib', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id',etablissement_id,'mission_id',mission_id,'partage_le',partage_le,'consulte_le',consulte_le,'expire_le',expire_le,'actif',actif)), '[]'::jsonb) FROM partages_rib WHERE soignant_id = v_uid),
    'parrainages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('role', CASE WHEN parrain_id = v_uid THEN 'parrain' ELSE 'filleul' END,'code_parrainage',code_parrainage,'statut',statut,'valide_le',valide_le,'cree_le',cree_le)), '[]'::jsonb) FROM parrainages WHERE parrain_id = v_uid OR filleul_id = v_uid),
    'preferences_notifications', (SELECT to_jsonb(p) - 'utilisateur_id' FROM preferences_notifications p WHERE utilisateur_id = v_uid),
    'preferences_notifications_par_evenement', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type_evenement',type_evenement,'canal',canal,'actif',actif)), '[]'::jsonb) FROM preferences_notifications_par_evenement WHERE utilisateur_id = v_uid),
    'serie_email_envois', (SELECT COALESCE(jsonb_agg(jsonb_build_object('serie',serie,'etape',etape,'planifie_le',planifie_le,'envoye_le',envoye_le,'statut',statut,'skip_raison',skip_raison) ORDER BY planifie_le DESC), '[]'::jsonb) FROM serie_email_envois WHERE utilisateur_id = v_uid),
    'filtres_sauvegardes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('nom',nom,'audience',audience,'filtres',filtres,'alerte_active',alerte_active,'frequence_alerte',frequence_alerte,'dernier_check_le',dernier_check_le,'nb_resultats_dernier_check',nb_resultats_dernier_check,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM filtres_sauvegardes WHERE utilisateur_id = v_uid),
    'favoris_etablissements', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id', etablissement_id, 'cree_le', cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM favoris_soignant_etab WHERE soignant_id = v_uid),
    'prevoyance_liste_attente', (SELECT COALESCE(jsonb_agg(jsonb_build_object('email', email, 'niveau_souhaite', niveau_souhaite, 'cree_le', cree_le, 'mis_a_jour_le', mis_a_jour_le)), '[]'::jsonb) FROM prevoyance_liste_attente WHERE soignant_id = v_uid),
    'notations_donnees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'sens',sens,'critere_1',critere_1,'critere_2',critere_2,'critere_3',critere_3,'critere_4',critere_4,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notations_missions WHERE notateur_id = v_uid),
    'notations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'sens',sens,'critere_1',critere_1,'critere_2',critere_2,'critere_3',critere_3,'critere_4',critere_4,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notations_missions WHERE note_id = v_uid AND masque = false),
    'scoring_breakdown_historique', (SELECT COALESCE(jsonb_agg(jsonb_build_object('score_total',score_total,'niveau',niveau,'en_periode_probatoire',en_periode_probatoire,'composantes_actives_count',composantes_actives_count,'litiges_malus',litiges_malus,'absence_sans_prevenir_malus',absence_sans_prevenir_malus,'bonus_super_actif',bonus_super_actif,'raison_recalcul',raison_recalcul,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM scoring_breakdown WHERE soignant_id = v_uid)
  ) INTO v_result;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'RGPD_EXPORT_DONNEES',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('version', 'v10_restaure_couverture_v9_30_cles')
  );

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_sanitiser_html(p_html text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    IF p_html IS NULL THEN RETURN NULL; END IF;
    -- Supprimer les balises script
    p_html := regexp_replace(p_html, '<script[^>]*>.*?</script>', '', 'gi');
    -- Supprimer les événements JavaScript inline
    p_html := regexp_replace(p_html, '\son\w+\s*=\s*"[^"]*"', '', 'gi');
    p_html := regexp_replace(p_html, '\son\w+\s*=\s*''[^'']*''', '', 'gi');
    -- Supprimer les iframes
    p_html := regexp_replace(p_html, '<iframe[^>]*>.*?</iframe>', '', 'gi');
    -- Supprimer les liens javascript:
    p_html := regexp_replace(p_html, 'javascript\s*:', '', 'gi');
    -- Supprimer les data: URLs dans les attributs
    p_html := regexp_replace(p_html, 'data\s*:[^"''>\s]+', '', 'gi');
    RETURN p_html;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_set_user_role(p_user_id uuid, p_role text, p_etablissement_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Vérification : cette fonction ne doit être appelée que par service_role
    -- En contexte authenticated, auth.uid() est défini
    -- En contexte service_role, auth.uid() est NULL
    IF auth.uid() IS NOT NULL THEN
        -- C'est un utilisateur authentifié qui essaie d'appeler → REFUS
        RAISE EXCEPTION 'INTERDIT : seul le serveur peut attribuer des rôles.';
    END IF;

    IF p_role NOT IN ('SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME') THEN
        RAISE EXCEPTION 'Rôle invalide.';
    END IF;

    UPDATE auth.users SET raw_app_meta_data =
        COALESCE(raw_app_meta_data, '{}'::jsonb)
        || jsonb_build_object('role', p_role)
        || CASE WHEN p_etablissement_id IS NOT NULL
            THEN jsonb_build_object('etablissement_id', p_etablissement_id::TEXT)
            ELSE '{}'::jsonb END
    WHERE id = p_user_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_sauvegarder_profil(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
    
    PERFORM set_config('jolene.rpc_update', 'true', true);
    
    UPDATE soignants SET
        telephone = COALESCE((p_data->>'telephone'), telephone),
        date_naissance = COALESCE((p_data->>'date_naissance')::DATE, date_naissance),
        adresse_rue = COALESCE((p_data->>'adresse_rue'), adresse_rue),
        adresse_ville = COALESCE((p_data->>'adresse_ville'), adresse_ville),
        adresse_code_postal = COALESCE((p_data->>'adresse_code_postal'), adresse_code_postal),
        adresse_lat = COALESCE((p_data->>'adresse_lat')::NUMERIC, adresse_lat),
        adresse_lng = COALESCE((p_data->>'adresse_lng')::NUMERIC, adresse_lng),
        rayon_deplacement_km = COALESCE((p_data->>'rayon_deplacement_km')::INT, rayon_deplacement_km),
        numero_adeli = COALESCE((p_data->>'numero_adeli'), numero_adeli),
        avatar_url = COALESCE((p_data->>'avatar_url'), avatar_url),
        bio = COALESCE((p_data->>'bio'), bio),
        annees_experience = COALESCE((p_data->>'annees_experience')::INT, annees_experience),
        taux_horaire_minimum = COALESCE((p_data->>'taux_horaire_minimum')::NUMERIC, taux_horaire_minimum),
        type_exercice = COALESCE((p_data->>'type_exercice'), type_exercice),
        ville_recherche = COALESCE((p_data->>'ville_recherche'), ville_recherche),
        ville_urgence = COALESCE((p_data->>'ville_urgence'), ville_urgence),
        disponible_urgence = COALESCE((p_data->>'disponible_urgence')::BOOLEAN, disponible_urgence),
        urgence_rayon_km = COALESCE((p_data->>'urgence_rayon_km')::INT, urgence_rayon_km),
        attestation_cumul_activite = COALESCE((p_data->>'attestation_cumul_activite')::BOOLEAN, attestation_cumul_activite),
        est_cumul_activite = COALESCE((p_data->>'est_cumul_activite')::BOOLEAN, est_cumul_activite),
        est_salarie_etablissement = COALESCE((p_data->>'est_salarie_etablissement')::BOOLEAN, est_salarie_etablissement),
        consentement_gps = COALESCE((p_data->>'consentement_gps')::BOOLEAN, consentement_gps),
        types_contrat_acceptes = COALESCE((p_data->>'types_contrat_acceptes'), types_contrat_acceptes),
        specialites = CASE WHEN p_data ? 'specialites' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'specialites')) ELSE specialites END,
        attestation_cumul_le = CASE WHEN (p_data->>'attestation_cumul_activite')::BOOLEAN = TRUE THEN NOW() ELSE attestation_cumul_le END,
        consentement_gps_le = CASE WHEN p_data ? 'consentement_gps' THEN NOW() ELSE consentement_gps_le END,
        modifie_le = NOW()
    WHERE id = v_uid;
    
    RETURN jsonb_build_object('success', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage(p_code text, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD; v_now timestamptz := now(); v_arrondi timestamptz;
  v_dernier_scan timestamptz; v_premier_prevu timestamptz; v_dernier_prevu timestamptz;
  v_est_en_avance boolean := false; v_validation_requise boolean := false;
  v_creneau_id uuid; v_creneau_debut timestamptz;
  v_new_code text; v_new_hmac text; v_scan_numero smallint;
BEGIN
  SELECT id, soignant_assigne_id, code_pointage_actif, prochain_type_scan, nb_scans, statut
  INTO v_mission FROM missions WHERE code_pointage_actif = p_code AND statut IN ('ASSIGNEE','EN_COURS') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Code de pointage invalide ou expiré.' USING ERRCODE = 'no_data_found'; END IF;
  IF auth.uid() != v_mission.soignant_assigne_id THEN RAISE EXCEPTION 'Vous n''êtes pas assigné(e) à cette mission.' USING ERRCODE = 'insufficient_privilege'; END IF;

  SELECT scanne_le INTO v_dernier_scan FROM scans_pointage WHERE mission_id = v_mission.id ORDER BY numero_scan DESC LIMIT 1;
  IF v_dernier_scan IS NOT NULL AND v_now - v_dernier_scan < INTERVAL '2 minutes' THEN
    RAISE EXCEPTION 'Scan déjà pris en compte. Prochain scan possible dans % secondes.',
      CEIL(EXTRACT(EPOCH FROM (v_dernier_scan + INTERVAL '2 minutes' - v_now))) USING ERRCODE = 'check_violation';
  END IF;

  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  v_arrondi := fn_arrondir_quart_heure(v_now);

  IF v_mission.prochain_type_scan = 'OUVERTURE' THEN
    -- GATE LÉGAL : aucun pointage d'arrivée/reprise sans contrat signé complet.
    IF NOT EXISTS (SELECT 1 FROM contrats_mission WHERE mission_id = v_mission.id AND statut = 'SIGNE_COMPLET') THEN
      RAISE EXCEPTION 'Le contrat doit être signé avant le pointage.' USING ERRCODE = 'check_violation';
    END IF;

    SELECT MIN(debut) INTO v_premier_prevu FROM mission_creneaux WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';
    IF v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'Pointage trop tôt. Mission commence à %. Possible à partir de %.',
        TO_CHAR(v_premier_prevu AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
        TO_CHAR((v_premier_prevu - INTERVAL '15 minutes') AT TIME ZONE 'Europe/Paris', 'HH24:MI') USING ERRCODE = 'check_violation';
    END IF;
    v_est_en_avance := (v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu);
    SELECT MAX(fin) INTO v_dernier_prevu FROM mission_creneaux WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';
    v_validation_requise := v_est_en_avance OR (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre, type_creneau)
    VALUES (v_mission.id, v_arrondi, NULL, false,
      COALESCE((SELECT MAX(ordre)+1 FROM mission_creneaux WHERE mission_id = v_mission.id), 1), 'EFFECTIF')
    RETURNING id INTO v_creneau_id;

    INSERT INTO scans_pointage (mission_id, soignant_id, code_saisi, numero_scan, type_scan, scanne_le, horodatage_arrondi, creneau_effectif_id, est_en_avance, validation_etab_requise, latitude, longitude, precision_gps_m, id_terminal, ip_address)
    VALUES (v_mission.id, auth.uid(), p_code, v_scan_numero, 'OUVERTURE', v_now, v_arrondi, v_creneau_id, v_est_en_avance, v_validation_requise,
      (p_metadata->>'latitude')::numeric, (p_metadata->>'longitude')::numeric, (p_metadata->>'precision_gps_m')::numeric, p_metadata->>'id_terminal', (p_metadata->>'ip_address')::inet);

    IF NOT EXISTS (SELECT 1 FROM presences WHERE mission_id = v_mission.id AND soignant_id = auth.uid()) THEN
      INSERT INTO presences (mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m, arrivee_id_terminal, methode_pointage_arrivee)
      VALUES (v_mission.id, auth.uid(), v_arrondi,
        (p_metadata->>'latitude')::numeric, (p_metadata->>'longitude')::numeric,
        (p_metadata->>'precision_gps_m')::numeric, p_metadata->>'id_terminal', 'CODE');
      UPDATE missions SET statut = 'EN_COURS', modifie_le = now()
        WHERE id = v_mission.id AND statut = 'ASSIGNEE';
    ELSE
      UPDATE presences SET pointage_depart_le = NULL, modifie_le = now()
        WHERE mission_id = v_mission.id AND soignant_id = auth.uid();
    END IF;

  ELSE -- FERMETURE
    SELECT id, debut INTO v_creneau_id, v_creneau_debut FROM mission_creneaux
    WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF' AND fin IS NULL ORDER BY debut DESC LIMIT 1;
    IF v_creneau_id IS NULL THEN RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer.' USING ERRCODE = 'no_data_found'; END IF;

    IF v_arrondi <= v_creneau_debut THEN
      v_arrondi := v_creneau_debut + INTERVAL '15 minutes';
    END IF;

    UPDATE mission_creneaux SET fin = v_arrondi WHERE id = v_creneau_id;

    SELECT MAX(fin) INTO v_dernier_prevu FROM mission_creneaux WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';
    v_validation_requise := (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    INSERT INTO scans_pointage (mission_id, soignant_id, code_saisi, numero_scan, type_scan, scanne_le, horodatage_arrondi, creneau_effectif_id, est_en_avance, validation_etab_requise, latitude, longitude, precision_gps_m, id_terminal, ip_address)
    VALUES (v_mission.id, auth.uid(), p_code, v_scan_numero, 'FERMETURE', v_now, v_arrondi, v_creneau_id, false, v_validation_requise,
      (p_metadata->>'latitude')::numeric, (p_metadata->>'longitude')::numeric, (p_metadata->>'precision_gps_m')::numeric, p_metadata->>'id_terminal', (p_metadata->>'ip_address')::inet);

    UPDATE presences SET
      pointage_depart_le = v_arrondi,
      depart_lat = (p_metadata->>'latitude')::numeric,
      depart_lng = (p_metadata->>'longitude')::numeric,
      methode_pointage_depart = 'CODE',
      heures_reelles = (
        SELECT COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)::numeric, 2), 0)
        FROM mission_creneaux
        WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF'
          AND fin IS NOT NULL AND NOT est_pause
      ),
      modifie_le = now()
    WHERE mission_id = v_mission.id AND soignant_id = auth.uid();
  END IF;

  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  WHILE EXISTS (SELECT 1 FROM missions WHERE code_pointage_actif = v_new_code AND id != v_mission.id AND statut IN ('ASSIGNEE','EN_COURS')) LOOP
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  END LOOP;
  v_new_hmac := CASE WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL
    THEN encode(extensions.hmac(v_mission.id::text || ':' || v_new_code, current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex') ELSE NULL END;

  UPDATE missions SET code_pointage_actif = v_new_code, code_pointage_hmac = v_new_hmac,
    prochain_type_scan = CASE WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE' ELSE 'OUVERTURE' END,
    nb_scans = v_scan_numero WHERE id = v_mission.id;

  RETURN jsonb_build_object('nouveau_code', v_new_code, 'nouveau_hmac', v_new_hmac,
    'type_scan_effectue', v_mission.prochain_type_scan,
    'prochain_type_scan', CASE WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE' ELSE 'OUVERTURE' END,
    'creneau_effectif_id', v_creneau_id, 'horodatage_arrondi', v_arrondi,
    'numero_scan', v_scan_numero, 'validation_etab_requise', v_validation_requise);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_set_mis_a_jour_le()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  NEW.mis_a_jour_le = now();
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_score_etab_public(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_a_eu_mission BOOLEAN := false;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT EXISTS (SELECT 1 FROM missions WHERE etablissement_id = p_etab_id AND soignant_assigne_id = v_uid)
  INTO v_a_eu_mission;
  IF NOT v_a_eu_mission AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  SELECT jsonb_build_object(
    'etablissement_id', e.id, 'nom', e.nom,
    'score_qualite', e.score_qualite, 'niveau', e.niveau
  ) INTO v_result FROM etablissements e WHERE e.id = p_etab_id;
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signaler_notation(p_notation_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_notation RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_notation FROM notations_missions WHERE id = p_notation_id;
  IF v_notation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation introuvable');
  END IF;

  -- Seule la cible (note_id) peut signaler — soit soignant, soit étab via mon_etablissement_id()
  IF v_notation.note_id <> v_uid AND v_notation.note_id <> COALESCE(v_etab_id, '00000000-0000-0000-0000-000000000000'::uuid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez signaler que les notations vous concernant');
  END IF;

  IF v_notation.signale = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation déjà signalée');
  END IF;

  UPDATE notations_missions SET signale = true, mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_SIGNALE',
    p_type_ressource := 'notation',
    p_id_ressource := p_notation_id,
    p_details := jsonb_build_object('motif', p_motif, 'mission_id', v_notation.mission_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signaler_utilisateur(p_cible_id uuid, p_cible_type text, p_categorie text, p_motif text, p_mission_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_signaleur_type text;
  v_id uuid;
  v_admin RECORD;
BEGIN
  IF v_me IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;
  IF p_cible_type NOT IN ('SOIGNANT','ETABLISSEMENT') THEN RETURN jsonb_build_object('success', false, 'error', 'Cible invalide'); END IF;
  IF p_categorie IS NULL OR p_categorie NOT IN ('COMPORTEMENT_INAPPROPRIE','FRAUDE_SUSPECTEE','FAUX_DOCUMENT','NON_PROFESSIONNALISME','SECURITE_DANGER','USURPATION_IDENTITE','AUTRE') THEN RETURN jsonb_build_object('success', false, 'error', 'Catégorie invalide'); END IF;
  IF p_motif IS NULL OR length(trim(p_motif)) < 10 THEN RETURN jsonb_build_object('success', false, 'error', 'Motif obligatoire (10 caractères minimum).'); END IF;
  IF p_cible_id = v_me THEN RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez pas vous signaler vous-même.'); END IF;
  IF EXISTS (SELECT 1 FROM soignants WHERE id = v_me) THEN v_signaleur_type := 'SOIGNANT';
  ELSIF EXISTS (SELECT 1 FROM etablissements WHERE id = v_me) THEN v_signaleur_type := 'ETABLISSEMENT';
  ELSE RETURN jsonb_build_object('success', false, 'error', 'Profil signaleur inconnu'); END IF;
  INSERT INTO public.signalements (signaleur_id, signaleur_type, cible_id, cible_type, categorie, motif, mission_id)
  VALUES (v_me, v_signaleur_type, p_cible_id, p_cible_type, p_categorie, trim(p_motif), p_mission_id) RETURNING id INTO v_id;
  FOR v_admin IN SELECT id FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME' LOOP
    INSERT INTO public.notifications (destinataire_id, type_destinataire, type, titre, corps, type_ressource, id_ressource)
    VALUES (v_admin.id, 'ADMIN', 'SYSTEM', '🚩 Nouveau signalement utilisateur',
      'Un ' || lower(v_signaleur_type) || ' a signalé un ' || lower(p_cible_type) || ' (' || p_categorie || ').',
      'signalement', v_id);
  END LOOP;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_me, p_type_acteur := v_signaleur_type,
    p_action := 'SIGNALEMENT_UTILISATEUR', p_type_ressource := 'signalement', p_id_ressource := v_id,
    p_details := jsonb_build_object('cible_id', p_cible_id, 'cible_type', p_cible_type, 'categorie', p_categorie));
  RETURN jsonb_build_object('success', true, 'signalement_id', v_id);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_soignant(p_contrat_id uuid, p_signature_image text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_contrat RECORD;
BEGIN
    SELECT * INTO v_contrat FROM contrats_mission WHERE id = p_contrat_id;
    IF v_contrat IS NULL THEN RETURN '{"error":"Contrat introuvable"}'::JSONB; END IF;
    IF v_contrat.soignant_id != auth.uid() THEN RETURN '{"error":"Ce contrat ne vous concerne pas"}'::JSONB; END IF;
    IF v_contrat.signature_soignant = TRUE THEN RETURN '{"error":"Déjà signé"}'::JSONB; END IF;

    -- Autorise la transition de statut de signature dans le trigger de protection
    PERFORM set_config('jolene.signature_soignant_en_cours', '1', true);

    UPDATE contrats_mission SET
        signature_soignant = TRUE,
        signature_soignant_le = NOW(),
        signature_image_soignant = p_signature_image,
        signature_navigateur_soignant = current_setting('request.headers', true)::JSON->>'user-agent',
        statut = CASE
            WHEN signature_etablissement = TRUE THEN 'SIGNE_COMPLET'
            ELSE 'SIGNE_SOIGNANT'
        END,
        modifie_le = NOW()
    WHERE id = p_contrat_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_etablissement(p_contrat_id uuid, p_signature_image text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_contrat RECORD;
BEGIN
    SELECT * INTO v_contrat FROM contrats_mission WHERE id = p_contrat_id;
    IF v_contrat IS NULL THEN RETURN '{"error":"Contrat introuvable"}'::JSONB; END IF;
    IF v_contrat.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Ce contrat ne vous concerne pas"}'::JSONB;
    END IF;
    IF v_contrat.signature_etablissement = TRUE THEN RETURN '{"error":"Déjà signé"}'::JSONB; END IF;

    UPDATE contrats_mission SET
        signature_etablissement = TRUE,
        signature_etablissement_le = NOW(),
        signature_image_etablissement = p_signature_image,
        signature_navigateur_etablissement = current_setting('request.headers', true)::JSON->>'user-agent',
        statut = CASE
            WHEN signature_soignant = TRUE THEN 'SIGNE_COMPLET'
            ELSE 'SIGNE_ETABLISSEMENT'
        END,
        modifie_le = NOW()
    WHERE id = p_contrat_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_attestation_sante()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_user_id) THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  UPDATE soignants
  SET attestation_sante_signee_le = now(),
      modifie_le = now()
  WHERE id = v_user_id;

  -- Capture IP + User-Agent pour non-répudiation (signature médicale)
  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    v_user_id, 'SOIGNANT', 'ATTESTATION_SANTE_SIGNEE',
    'soignant', v_user_id, NULL,
    jsonb_build_object(
      'vaccinations', true,
      'medecine_travail', true,
      'horodatage', now()
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true, 'signe_le', now());
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_mandat_facturation(p_version text, p_ip text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text, p_contenu_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_signature_id UUID;
    v_mission_id UUID;
    v_backfill INT := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN '{"error":"Non authentifié"}'::JSONB;
    END IF;

    -- Vérifier que c'est bien un soignant
    IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_user_id AND supprime_le IS NULL) THEN
        RETURN '{"error":"Seuls les soignants peuvent signer ce mandat"}'::JSONB;
    END IF;

    -- Enregistrer la signature (audit)
    INSERT INTO mandats_facturation_signatures (soignant_id, version, ip_address, user_agent, contenu_hash)
    VALUES (v_user_id, p_version, p_ip, p_user_agent, p_contenu_hash)
    RETURNING id INTO v_signature_id;

    -- Mettre à jour le soignant
    UPDATE soignants SET
        mandat_facturation_signe = TRUE,
        mandat_facturation_signe_le = now(),
        mandat_facturation_version = p_version
    WHERE id = v_user_id;

    -- BACKFILL : rattraper les factures d'honoraires non générées faute de mandat.
    -- On reproduit les prédicats des deux générateurs existants :
    --   (A) honoraires "classiques" (non rétrocession) → généré par le trigger TERMINEE
    --       si mandat signé. Gardé sur type_contrat_applique = 'LIBERAL' pour ne PAS
    --       facturer en honoraires les missions SALARIÉES d'un soignant MIXTE.
    --   (B) rétrocession confirmée (honoraires_confirmes_le NOT NULL) → généré par
    --       confirm/cron si mandat signé. RETROCESSION est par nature libéral.
    -- fn_generer_facture_honoraires_mission est idempotente (no-op si facture existe).
    FOR v_mission_id IN
        SELECT m.id
        FROM missions m
        WHERE m.soignant_assigne_id = v_user_id
          AND m.statut = 'TERMINEE'
          AND COALESCE(m.net_a_payer, m.total_brut, 0) > 0
          AND NOT EXISTS (SELECT 1 FROM factures_honoraires fh WHERE fh.mission_id = m.id)
          AND (
                (m.mode_remuneration IS DISTINCT FROM 'RETROCESSION' AND m.type_contrat_applique = 'LIBERAL')
             OR (m.mode_remuneration = 'RETROCESSION' AND m.honoraires_confirmes_le IS NOT NULL)
          )
    LOOP
        PERFORM fn_generer_facture_honoraires_mission(v_mission_id);
        v_backfill := v_backfill + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'signature_id', v_signature_id,
        'version', p_version,
        'signed_at', now(),
        'factures_regenerees', v_backfill
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_cession_creance(p_facture_honoraire_id uuid, p_version text, p_ip text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text, p_contenu_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_facture RECORD;
    v_existing_id UUID;
    v_cession_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN '{"error":"Non authentifié"}'::JSONB;
    END IF;

    -- Vérifier que la facture appartient bien au soignant
    SELECT * INTO v_facture
    FROM factures_honoraires
    WHERE id = p_facture_honoraire_id AND soignant_id = v_user_id;

    IF v_facture IS NULL THEN
        RETURN '{"error":"Facture introuvable ou non autorisée"}'::JSONB;
    END IF;

    -- Une seule cession par facture
    SELECT id INTO v_existing_id FROM cessions_creance WHERE facture_honoraire_id = p_facture_honoraire_id;
    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'cession_id', v_existing_id, 'message', 'Cession déjà existante');
    END IF;

    INSERT INTO cessions_creance (
        soignant_id, facture_honoraire_id, montant,
        version_texte, contenu_hash, ip_address, user_agent
    ) VALUES (
        v_user_id, p_facture_honoraire_id, v_facture.montant_ttc,
        p_version, p_contenu_hash, p_ip, p_user_agent
    ) RETURNING id INTO v_cession_id;

    RETURN jsonb_build_object('success', true, 'cession_id', v_cession_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_sms_doit_envoyer(p_destinataire_id uuid, p_type text, p_fenetre_minutes integer DEFAULT 5)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_existe BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM sms_envoyes
    WHERE destinataire_id = p_destinataire_id
      AND type = p_type
      AND statut IN ('SENT','DELIVERED','PENDING')
      AND cree_le > NOW() - (p_fenetre_minutes || ' minutes')::INTERVAL
  ) INTO v_existe;
  RETURN NOT v_existe;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_service(p_version text, p_ip text, p_user_agent text, p_contenu_hash text, p_signature_s3_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_existing uuid;
  v_headers jsonb;
  v_real_ip text;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  SELECT id INTO v_existing FROM contrats_service_signatures
   WHERE etablissement_id = v_etab_id AND revoked_at IS NULL;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat déjà signé et actif');
  END IF;

  -- Capture IP réelle depuis les headers
  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_real_ip := COALESCE(
      v_headers->>'cf-connecting-ip',
      split_part(v_headers->>'x-forwarded-for', ',', 1),
      v_headers->>'x-real-ip',
      NULLIF(p_ip, ''),
      'unknown'
    );
  EXCEPTION WHEN OTHERS THEN
    v_real_ip := COALESCE(NULLIF(p_ip, ''), 'unknown');
  END;

  INSERT INTO contrats_service_signatures (etablissement_id, version, ip_address, user_agent, contenu_hash, signature_s3_key)
  VALUES (v_etab_id, p_version, v_real_ip, p_user_agent, p_contenu_hash, p_signature_s3_key);

  PERFORM set_config('app.internal_operation', 'true', true);
  UPDATE etablissements
  SET contrat_service_signe = true, contrat_service_signe_le = now()
  WHERE id = v_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_etab_id,
    p_details := jsonb_build_object(
      'type', 'contrat_service_jolene',
      'version', p_version,
      'ip', v_real_ip,
      'has_signature_image', p_signature_s3_key IS NOT NULL
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_otp(p_contrat_id uuid, p_otp_code text, p_hash_document text DEFAULT NULL::text, p_signature_image text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_sig RECORD;
  v_contrat RECORD;
  v_expected_hash text;
  v_role text;
  v_ip inet;
  v_ua text;
  v_other_signed boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  SELECT cm.signature_soignant, cm.signature_etablissement, cm.statut
  INTO v_contrat
  FROM public.contrats_mission cm WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE', 'error', 'Contrat introuvable');
  END IF;

  SELECT * INTO v_sig FROM public.signatures_contrats
  WHERE contrat_id = p_contrat_id AND signataire_user_id = v_uid
  ORDER BY cree_le DESC LIMIT 1;

  IF v_sig IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_NON_DEMANDE',
      'error', 'Aucune demande OTP en cours. Cliquez d''abord sur "Recevoir un code SMS".');
  END IF;

  IF v_sig.statut_signature = 'signe' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE',
      'error', 'Vous avez déjà signé ce contrat le ' ||
        COALESCE(to_char(v_sig.signe_a, 'DD/MM/YYYY HH24:MI'), '—') || '.',
      'signe_a', v_sig.signe_a);
  END IF;

  -- Ordre obligatoire (vérif redondante avec fn_envoyer_otp_signature)
  IF v_sig.signataire_role = 'etablissement' AND v_contrat.signature_soignant IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAB_AVANT_SOIGNANT',
      'error', 'Le soignant doit signer en premier.');
  END IF;

  IF v_sig.otp_tentatives >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_TENTATIVES',
      'error', 'Trop de tentatives. Renvoyez un nouveau code SMS.');
  END IF;

  IF v_sig.otp_envoye_a IS NULL OR v_sig.otp_envoye_a < NOW() - INTERVAL '10 minutes' THEN
    UPDATE public.signatures_contrats
    SET statut_signature = 'expire', modifie_le = NOW()
    WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_EXPIRE',
      'error', 'Code expiré. Renvoyez un nouveau code SMS.');
  END IF;

  v_expected_hash := encode(digest(p_otp_code || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');
  IF v_expected_hash != v_sig.otp_code_hash THEN
    UPDATE public.signatures_contrats
    SET otp_tentatives = otp_tentatives + 1, modifie_le = NOW()
    WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_INCORRECT',
      'error', 'Code incorrect.',
      'tentatives_restantes', 5 - (v_sig.otp_tentatives + 1));
  END IF;

  v_role := v_sig.signataire_role;
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_ua := current_setting('request.headers', true)::jsonb->>'user-agent';

  UPDATE public.signatures_contrats
  SET statut_signature = 'signe',
      otp_valide_a = NOW(),
      signe_a = NOW(),
      ip_signature = v_ip,
      user_agent = v_ua,
      hash_document = p_hash_document,
      signature_image_base64 = p_signature_image,
      modifie_le = NOW(),
      audit_trail = COALESCE(audit_trail, '{}'::jsonb)
        || jsonb_build_object('signe_le', NOW()::text, 'tentatives', v_sig.otp_tentatives + 1)
  WHERE id = v_sig.id;

  IF v_role = 'soignant' THEN
    UPDATE public.contrats_mission
    SET signature_soignant = true,
        signature_soignant_le = NOW(),
        signature_ip_soignant = COALESCE(v_ip, signature_ip_soignant),
        signature_navigateur_soignant = COALESCE(v_ua, signature_navigateur_soignant),
        signature_image_soignant = COALESCE(p_signature_image, signature_image_soignant),
        mode_signature = 'JOLENE_OTP'
    WHERE id = p_contrat_id;
  ELSE
    UPDATE public.contrats_mission
    SET signature_etablissement = true,
        signature_etablissement_le = NOW(),
        signature_ip_etablissement = COALESCE(v_ip, signature_ip_etablissement),
        signature_navigateur_etablissement = COALESCE(v_ua, signature_navigateur_etablissement),
        signature_image_etablissement = COALESCE(p_signature_image, signature_image_etablissement),
        mode_signature = 'JOLENE_OTP'
    WHERE id = p_contrat_id;
  END IF;

  SELECT (signature_soignant = true AND signature_etablissement = true) INTO v_other_signed
  FROM public.contrats_mission WHERE id = p_contrat_id;

  IF v_other_signed THEN
    UPDATE public.contrats_mission
    SET statut = 'SIGNE_COMPLET', modifie_le = NOW()
    WHERE id = p_contrat_id AND statut != 'SIGNE_COMPLET';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'contrat_complet', v_other_signed
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignant_pour_etablissement(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_a_mission_aujourdhui BOOLEAN;
    v_a_relation_contractuelle BOOLEAN;
BEGIN
    IF NOT est_admin() AND v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM missions
        WHERE soignant_assigne_id = p_soignant_id
          AND etablissement_id = v_etab_id
          AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE','ABSENCE','LITIGE')
    ) INTO v_a_relation_contractuelle;

    SELECT EXISTS (
        SELECT 1 FROM missions
        WHERE soignant_assigne_id = p_soignant_id
          AND etablissement_id = v_etab_id
          AND statut IN ('ASSIGNEE','EN_COURS')
          AND debut_le::DATE <= CURRENT_DATE + 1
    ) INTO v_a_mission_aujourdhui;

    RETURN (
        SELECT jsonb_build_object(
            'id', id,
            'prenom', prenom,
            'nom', CASE
                WHEN est_admin() OR v_a_relation_contractuelle THEN nom
                ELSE LEFT(COALESCE(nom, ''), 1) || '.'
            END,
            'nom_anonymise', NOT (est_admin() OR v_a_relation_contractuelle),
            'profession', profession::TEXT,
            'specialite_medicale', specialite_medicale,
            'telephone', CASE WHEN v_a_mission_aujourdhui OR est_admin() THEN telephone ELSE NULL END,
            'numero_rpps', numero_rpps,
            'score_fiabilite', score_fiabilite,
            'note_moyenne', note_moyenne,
            'nb_evaluations', nb_evaluations,
            'total_missions_terminees', total_missions_terminees,
            'rpps_verifie', rpps_verifie,
            'tous_documents_valides', tous_documents_valides,
            'avatar_url', avatar_url,
            'type_exercice', COALESCE(type_exercice, 'SALARIE'),
            'bio', bio,
            'annees_experience', annees_experience,
            'specialites', specialites,
            'disponible_urgence', disponible_urgence,
            'est_etudiant', est_etudiant,
            'etudiant_details', etudiant_details
        )
        FROM soignants WHERE id = p_soignant_id AND supprime_le IS NULL
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignant_stripe_connect_actif(p_soignant_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Seul le soignant lui-même, l'étab de sa mission, ou admin/service_role
    IF p_soignant_id != auth.uid() 
       AND NOT est_admin()
       AND COALESCE(current_setting('request.jwt.claim.role', true), '') != 'service_role'
       AND NOT EXISTS(SELECT 1 FROM missions m WHERE m.soignant_assigne_id = p_soignant_id AND m.etablissement_id = mon_etablissement_id() AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE'))
    THEN
        RETURN FALSE; -- Ne pas exposer l'info
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM stripe_connect_onboarding 
        WHERE soignant_id = p_soignant_id 
        AND onboarding_complete = TRUE 
        AND charges_enabled = TRUE 
        AND payouts_enabled = TRUE
        AND statut = 'COMPLET'
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
 RETURNS TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
BEGIN
    SELECT m.id, m.profession_requise, m.type_contrat_recherche, e.id AS etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission FROM missions m JOIN etablissements e ON e.id = m.etablissement_id WHERE m.id = p_mission_id;
    IF NOT FOUND THEN RETURN; END IF;
    IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT s.id AS soignant_id, s.id, s.prenom::TEXT, s.nom::TEXT,
        COALESCE(s.score_fiabilite, 0)::INTEGER,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
                SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER, s.telephone::TEXT
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE AND s.supprime_le IS NULL
      AND fn_documents_ok_pour_mission(s.id, v_mission.type_contrat_recherche::text) AND s.profession = v_mission.profession_requise
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le)
      AND (s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
              COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
              SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
          )))) <= COALESCE(s.urgence_rayon_km, 15))
    ORDER BY s.score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soumettre_reclamation(p_categorie text, p_sujet text, p_details text, p_mission_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE v_user_id UUID := auth.uid(); v_role TEXT; v_type TEXT; v_reclamation_id UUID; BEGIN IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF; SELECT raw_app_meta_data ->> 'role' INTO v_role FROM auth.users WHERE id = v_user_id; IF v_role IN ('SOIGNANT') THEN v_type := 'SOIGNANT'; ELSIF v_role IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT') THEN v_type := 'ETABLISSEMENT'; ELSE RETURN jsonb_build_object('error', 'Rôle non autorisé'); END IF; INSERT INTO reclamations (utilisateur_id, type_utilisateur, categorie, sujet, details, mission_id) VALUES (v_user_id, v_type, p_categorie, p_sujet, p_details, p_mission_id) RETURNING id INTO v_reclamation_id; PERFORM fn_ecrire_audit_safe(v_user_id, v_type, 'RECLAMATION_CREEE', 'reclamation', v_reclamation_id, NULL, jsonb_build_object('categorie', p_categorie, 'sujet', p_sujet), NULL, NULL); RETURN jsonb_build_object('id', v_reclamation_id, 'statut', 'EN_ATTENTE'); END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignant_compatible_mission(p_soignant_profession type_profession, p_soignant_specialite text, p_mission_profession type_profession, p_mission_specialite text, p_accepte_non_specialises boolean)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    -- Cas 1 : match exact profession
    WHEN p_soignant_profession = p_mission_profession THEN
      CASE
        -- Pour MEDECIN avec spécialité requise, filtrer selon le flag
        WHEN p_mission_profession = 'MEDECIN'
             AND p_mission_specialite IS NOT NULL
             AND p_mission_specialite <> '' THEN
          COALESCE(p_accepte_non_specialises, true)
          OR COALESCE(p_soignant_specialite, '') = p_mission_specialite
        ELSE TRUE
      END
    -- Cas 2 : hiérarchie IDE — IBODE et IADE sont diplômés IDE de base,
    -- ils peuvent toujours candidater à une mission IDE (pas besoin du
    -- flag accepte_non_specialises côté IDE)
    WHEN p_mission_profession = 'IDE'
         AND p_soignant_profession IN ('IBODE', 'IADE') THEN TRUE
    -- Cas 3 : IDE peut candidater à mission IBODE/IADE uniquement si
    -- l'étab accepte les non-spécialisés
    WHEN p_soignant_profession = 'IDE'
         AND p_mission_profession IN ('IBODE', 'IADE') THEN
      COALESCE(p_accepte_non_specialises, true)
    ELSE FALSE
  END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignant_dpae_complet(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_s RECORD;
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  IF NOT (p_soignant_id = auth.uid() OR est_admin()) THEN
    RETURN jsonb_build_object('complet', false, 'manquants', ARRAY['non_autorise']);
  END IF;
  SELECT sexe, lieu_naissance_commune, lieu_naissance_departement, pays_naissance, nationalite,
         COALESCE(numero_securite_sociale, numero_secu) AS nir, date_naissance, adresse_rue, adresse_ville
  INTO v_s FROM public.soignants WHERE id = p_soignant_id;
  IF v_s IS NULL THEN
    RETURN jsonb_build_object('complet', false, 'manquants', ARRAY['profil_introuvable']);
  END IF;
  IF v_s.sexe IS NULL THEN v_manquants := array_append(v_manquants, 'sexe'); END IF;
  IF v_s.date_naissance IS NULL THEN v_manquants := array_append(v_manquants, 'date_naissance'); END IF;
  IF v_s.pays_naissance IS NULL THEN v_manquants := array_append(v_manquants, 'pays_naissance'); END IF;
  IF v_s.nationalite IS NULL THEN v_manquants := array_append(v_manquants, 'nationalite'); END IF;
  IF COALESCE(v_s.pays_naissance, 'France') = 'France' THEN
    IF v_s.lieu_naissance_commune IS NULL THEN v_manquants := array_append(v_manquants, 'lieu_naissance_commune'); END IF;
    IF v_s.lieu_naissance_departement IS NULL THEN v_manquants := array_append(v_manquants, 'lieu_naissance_departement'); END IF;
  END IF;
  IF v_s.nir IS NULL OR v_s.nir = '' THEN v_manquants := array_append(v_manquants, 'numero_securite_sociale'); END IF;
  IF v_s.adresse_rue IS NULL OR v_s.adresse_rue = '' THEN v_manquants := array_append(v_manquants, 'adresse'); END IF;
  RETURN jsonb_build_object('complet', array_length(v_manquants, 1) IS NULL, 'manquants', v_manquants);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignants_inactifs_a_relancer(p_limit integer DEFAULT 150)
 RETURNS TABLE(id uuid, prenom text, email text, profession text, nb_missions_ouvertes bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT s.id, s.prenom, s.email, s.profession::text,
    (SELECT count(*) FROM missions m
      WHERE m.statut = 'OUVERTE' AND m.profession_requise = s.profession) AS nb_missions_ouvertes
  FROM soignants s
  WHERE s.cree_le < now() - interval '3 days'
    AND s.email IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.soignant_id = s.id)
    AND NOT EXISTS (
      SELECT 1 FROM relances_soignants r
      WHERE r.soignant_id = s.id AND r.envoye_le > now() - interval '14 days'
    )
  ORDER BY s.cree_le DESC
  LIMIT greatest(p_limit, 1);
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_soignant_score_breakdown(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b public.scoring_breakdown;
BEGIN
  SELECT * INTO v_b FROM public.scoring_breakdown
   WHERE soignant_id = p_soignant_id
   ORDER BY cree_le DESC LIMIT 1;

  IF v_b.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'composantes', '[]'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'score_total', v_b.score_total,
    'niveau', v_b.niveau,
    'composantes', jsonb_build_array(
      jsonb_build_object('cle','notation_etab','label','Notations reçues','poids',35,'valeur', v_b.notation_etab_soignant_pct),
      jsonb_build_object('cle','presentisme','label','Présentéisme','poids',20,'valeur', v_b.presentisme_pct),
      jsonb_build_object('cle','ponctualite','label','Ponctualité','poids',15,'valeur', v_b.ponctualite_pct),
      jsonb_build_object('cle','reactivite','label','Réactivité','poids',10,'valeur', v_b.reactivite_pct),
      jsonb_build_object('cle','anciennete','label','Ancienneté / volume','poids',10,'valeur', v_b.anciennete_volume_pct),
      jsonb_build_object('cle','notation_soignant_etab','label','Notes données aux établissements','poids',10,'valeur', v_b.notation_soignant_etab_pct)
    )
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_souscrire_prevoyance(p_plan_id uuid, p_numero_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_plan RECORD;
BEGIN
    SELECT * INTO v_plan FROM plans_prevoyance WHERE id = p_plan_id AND est_actif = TRUE;
    IF v_plan IS NULL THEN RETURN '{"error":"Plan introuvable"}'::JSONB; END IF;

    INSERT INTO souscriptions_prevoyance (soignant_id, plan_id, numero_contrat_externe, statut)
    VALUES (auth.uid(), p_plan_id, p_numero_contrat, 'ACTIVE')
    ON CONFLICT DO NOTHING;

    UPDATE soignants SET
        prevoyance_inscrit = TRUE,
        prevoyance_fournisseur = v_plan.fournisseur,
        prevoyance_numero_contrat = p_numero_contrat,
        modifie_le = NOW()
    WHERE id = auth.uid();

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_stats_dashboard_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_stats JSONB;
    v_pool_urgence_count INT;
    v_messages_non_lus INT;
    v_missions_a_payer INT;
    v_debut_mois TIMESTAMPTZ;
    v_terminees_ce_mois INT;
    v_soignants_ce_mois INT;
    v_commissions_impayees NUMERIC;
    v_nb_factures_impayees INT;
    v_litiges_ouverts INT;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    
    v_debut_mois := DATE_TRUNC('month', NOW());
    
    SELECT COUNT(*) INTO v_pool_urgence_count FROM fn_pool_urgence_etablissement(v_etab_id);
    
    SELECT COUNT(*) INTO v_messages_non_lus
    FROM messages_chat mc JOIN conversations c ON c.id = mc.conversation_id
    WHERE (c.participant_1_id = v_etab_id OR c.participant_2_id = v_etab_id)
    AND mc.auteur_id != v_etab_id AND mc.lu = FALSE;
    
    SELECT COUNT(*) INTO v_missions_a_payer
    FROM missions m WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME'));
    
    SELECT COUNT(*) INTO v_terminees_ce_mois
    FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois;
    
    SELECT COUNT(DISTINCT soignant_assigne_id) INTO v_soignants_ce_mois
    FROM missions WHERE etablissement_id = v_etab_id AND soignant_assigne_id IS NOT NULL
    AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE') AND debut_le >= v_debut_mois;
    
    SELECT COALESCE(SUM(montant_ttc), 0), COUNT(*)
    INTO v_commissions_impayees, v_nb_factures_impayees
    FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD');
    
    -- Litiges ouverts
    SELECT COUNT(*) INTO v_litiges_ouverts
    FROM litiges WHERE etablissement_id = v_etab_id 
    AND statut IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE');
    
    SELECT jsonb_build_object(
        'a_deja_publie', (SELECT COUNT(*) > 0 FROM missions WHERE etablissement_id = v_etab_id),
        'total_missions', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id),
        'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'OUVERTE'),
        'missions_assignees', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'),
        'missions_en_cours', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'EN_COURS'),
        'missions_terminees', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'),
        'missions_terminees_ce_mois', v_terminees_ce_mois,
        'soignants_ce_mois', v_soignants_ce_mois,
        'commissions_cumulees', COALESCE((SELECT SUM(montant_ht) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0),
        'commissions_impayees', v_commissions_impayees,
        'nb_factures_impayees', v_nb_factures_impayees,
        'pool_urgence_count', v_pool_urgence_count,
        'messages_non_lus', v_messages_non_lus,
        'missions_a_payer', v_missions_a_payer,
        'litiges_ouverts', v_litiges_ouverts,
        'candidatures_en_attente', (
            SELECT COUNT(*) FROM candidatures c JOIN missions m ON m.id = c.mission_id
            WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
        ),
        'candidatures_recentes', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT c.id::TEXT AS candidature_id, m.intitule AS mission_intitule,
                    m.id::TEXT AS mission_id,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession,
                    s.score_fiabilite AS soignant_score, c.cree_le
                FROM candidatures c JOIN missions m ON m.id = c.mission_id JOIN soignants s ON s.id = c.soignant_id
                WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
                ORDER BY c.cree_le DESC LIMIT 5
            ) x
        ), '[]'::JSONB),
        'missions_assignees_detail', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession, s.score_fiabilite AS soignant_score
                FROM missions m JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'ASSIGNEE'
                ORDER BY m.debut_le ASC
            ) x
        ), '[]'::JSONB)
    ) INTO v_stats;
    
    RETURN v_stats;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_stats_rh_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
    v_debut_mois TIMESTAMPTZ;
    v_debut_mois_prec TIMESTAMPTZ;
    v_mois_fr TEXT[];
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    
    v_debut_mois := DATE_TRUNC('month', NOW());
    v_debut_mois_prec := DATE_TRUNC('month', NOW() - INTERVAL '1 month');
    v_mois_fr := ARRAY['Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    
    SELECT jsonb_build_object(
        'terminees_total', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'),
        'terminees_mois_prec', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois_prec AND fin_le < v_debut_mois),
        'terminees_ce_mois', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois),
        
        'cout_total_termine', COALESCE((SELECT SUM(total_brut) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'), 0),
        'cout_mois_prec', COALESCE((SELECT SUM(total_brut) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois_prec AND fin_le < v_debut_mois), 0),
        'cout_ce_mois', COALESCE((SELECT SUM(total_brut) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois), 0),
        'commission_mois_prec', COALESCE((SELECT SUM(montant_commission_ttc) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois_prec AND fin_le < v_debut_mois), 0),
        'commission_ce_mois', COALESCE((SELECT SUM(montant_commission_ttc) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois), 0),
        'heures_terminees', COALESCE((SELECT SUM(EXTRACT(EPOCH FROM (fin_le - debut_le))/3600) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'), 0),
        
        'cout_moyen_heure', COALESCE((
            SELECT ROUND((SUM(total_brut) / NULLIF(SUM(EXTRACT(EPOCH FROM (fin_le - debut_le))/3600), 0))::NUMERIC, 2)
            FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'
        ), 0),
        
        'assignees_total', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'),
        'cout_previsionnel_brut', COALESCE((SELECT SUM(total_brut) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'), 0),
        'commission_previsionnelle', COALESCE((SELECT SUM(montant_commission_ttc) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'), 0),
        'cout_previsionnel_total', COALESCE((SELECT SUM(total_brut + COALESCE(montant_commission_ttc, 0)) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'), 0),
        'heures_prevues', COALESCE((SELECT SUM(EXTRACT(EPOCH FROM (fin_le - debut_le))/3600) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'), 0),
        
        'ouvertes_total', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'OUVERTE'),
        
        'taux_remplissage', COALESCE((
            SELECT ROUND(
                (COUNT(*) FILTER (WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE'))::NUMERIC /
                 NULLIF(COUNT(*) FILTER (WHERE statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')), 0)
                ) * 100, 0)
            FROM missions WHERE etablissement_id = v_etab_id
        ), 0),
        
        'soignants_total', (SELECT COUNT(DISTINCT soignant_assigne_id) FROM missions WHERE etablissement_id = v_etab_id AND soignant_assigne_id IS NOT NULL AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')),
        'soignants_ce_mois', (SELECT COUNT(DISTINCT soignant_assigne_id) FROM missions WHERE etablissement_id = v_etab_id AND soignant_assigne_id IS NOT NULL AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE') AND debut_le >= v_debut_mois),
        
        'top_soignants', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT s.id::TEXT AS soignant_id, COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS nom,
                    s.profession::TEXT, s.score_fiabilite, s.note_moyenne,
                    COUNT(*) AS nb_missions, SUM(m.total_brut) AS total_facture
                FROM missions m JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE'
                GROUP BY s.id ORDER BY nb_missions DESC LIMIT 5
            ) x
        ), '[]'::JSONB),
        
        -- ★ NOUVEAU : Détail missions mois précédent
        'missions_mois_prec', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le, m.total_brut,
                    m.montant_commission_ttc, EXTRACT(EPOCH FROM (m.fin_le - m.debut_le))/3600 AS heures,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession
                FROM missions m LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE'
                AND m.fin_le >= v_debut_mois_prec AND m.fin_le < v_debut_mois
                ORDER BY m.fin_le DESC
            ) x
        ), '[]'::JSONB),
        
        -- ★ NOUVEAU : Détail missions ce mois
        'missions_ce_mois', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le, m.total_brut,
                    m.montant_commission_ttc, EXTRACT(EPOCH FROM (m.fin_le - m.debut_le))/3600 AS heures,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession
                FROM missions m LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE'
                AND m.fin_le >= v_debut_mois
                ORDER BY m.fin_le DESC
            ) x
        ), '[]'::JSONB),
        
        'prochaines_missions', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le, m.total_brut,
                    m.montant_commission_ttc, m.statut::TEXT,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom
                FROM missions m LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS')
                AND m.debut_le >= NOW()
                ORDER BY m.debut_le ASC LIMIT 10
            ) x
        ), '[]'::JSONB),
        
        'mois_en_cours', v_mois_fr[EXTRACT(MONTH FROM NOW())::INT] || ' ' || EXTRACT(YEAR FROM NOW())::TEXT,
        'mois_precedent', v_mois_fr[EXTRACT(MONTH FROM NOW() - INTERVAL '1 month')::INT] || ' ' || EXTRACT(YEAR FROM NOW() - INTERVAL '1 month')::TEXT
    ) INTO v_result;
    
    RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_suggestions_missions_pour_soignant(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_result JSONB;
  v_limit INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 5), 1), 10);

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;

  WITH candidates AS (
    SELECT m.id, m.intitule, m.profession_requise, m.specialite_medicale_requise,
      m.taux_horaire_base, m.debut_le, m.fin_le, m.est_urgente, m.cree_le,
      m.etablissement_id,
      e.nom AS etab_nom, e.adresse_ville AS etab_ville,
      e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
      (SELECT ROUND(AVG(note)::NUMERIC, 2) FROM evaluations ev
       JOIN missions m2 ON m2.id = ev.mission_id
       WHERE m2.etablissement_id = m.etablissement_id AND ev.note IS NOT NULL) AS etab_note_moyenne,
      CASE
        WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
          ROUND((6371 * 2 * asin(sqrt(
            power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
            cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
            power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
          )))::NUMERIC, 1)
        ELSE NULL
      END AS distance_km
    FROM missions m
    LEFT JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > NOW()
      AND public.fn_soignant_compatible_mission(
        v_soignant.profession, v_soignant.specialite_medicale,
        m.profession_requise, m.specialite_medicale_requise,
        COALESCE(m.accepte_non_specialises, true)
      ) = true
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = m.id AND c.soignant_id = v_uid
      )
      AND (
        v_soignant.rayon_deplacement_km IS NULL
        OR e.adresse_lat IS NULL OR v_soignant.adresse_lat IS NULL OR
        (6371 * 2 * asin(sqrt(
          power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
          cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
          power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
        ))) <= v_soignant.rayon_deplacement_km
      )
      AND COALESCE(m.taux_horaire_base, 0) >= COALESCE(v_soignant.taux_horaire_minimum, 0)
  ),
  ranked AS (
    SELECT *,
      ROW_NUMBER() OVER (ORDER BY
        est_urgente DESC,
        distance_km ASC NULLS LAST,
        etab_note_moyenne DESC NULLS LAST,
        cree_le DESC
      ) AS rn
    FROM candidates
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'intitule', r.intitule,
    'profession_requise', r.profession_requise::text,
    'specialite_medicale_requise', r.specialite_medicale_requise,
    'taux_horaire_base', r.taux_horaire_base,
    'debut_le', r.debut_le,
    'fin_le', r.fin_le,
    'est_urgente', r.est_urgente,
    'etablissement_id', r.etablissement_id,
    'etab_nom', r.etab_nom,
    'etab_ville', r.etab_ville,
    'etab_note_moyenne', r.etab_note_moyenne,
    'distance_km', r.distance_km
  ) ORDER BY r.rn), '[]'::jsonb)
  INTO v_result
  FROM (SELECT * FROM ranked WHERE rn <= v_limit) r;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_stats_etab_complements()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID;
  v_debut_mois TIMESTAMPTZ;
  v_debut_mois_precedent TIMESTAMPTZ;
  v_fin_mois_precedent TIMESTAMPTZ;
  v_soignants_mois_precedent INT;
  v_cout_brut_ce_mois NUMERIC;
  v_heures_ce_mois NUMERIC;
  v_missions_pourvues_ce_mois INT;
  v_missions_publiees_ce_mois INT;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  END IF;

  v_debut_mois := DATE_TRUNC('month', NOW());
  v_debut_mois_precedent := DATE_TRUNC('month', NOW() - INTERVAL '1 month');
  v_fin_mois_precedent := v_debut_mois;

  SELECT COUNT(DISTINCT soignant_assigne_id) INTO v_soignants_mois_precedent
  FROM missions
  WHERE (v_etab_id IS NULL OR etablissement_id = v_etab_id)
    AND soignant_assigne_id IS NOT NULL
    AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE')
    AND debut_le >= v_debut_mois_precedent AND debut_le < v_fin_mois_precedent;

  SELECT COALESCE(SUM(total_brut), 0), COALESCE(SUM(duree_heures), 0)
  INTO v_cout_brut_ce_mois, v_heures_ce_mois
  FROM missions
  WHERE (v_etab_id IS NULL OR etablissement_id = v_etab_id)
    AND statut = 'TERMINEE' AND fin_le >= v_debut_mois;

  SELECT
    COUNT(*) FILTER (WHERE statut IN ('ASSIGNEE','EN_COURS','TERMINEE')),
    COUNT(*)
  INTO v_missions_pourvues_ce_mois, v_missions_publiees_ce_mois
  FROM missions
  WHERE (v_etab_id IS NULL OR etablissement_id = v_etab_id)
    AND cree_le >= v_debut_mois;

  RETURN jsonb_build_object(
    'soignants_mois_precedent', v_soignants_mois_precedent,
    'cout_brut_ce_mois', v_cout_brut_ce_mois,
    'heures_ce_mois', v_heures_ce_mois,
    'missions_pourvues_ce_mois', v_missions_pourvues_ce_mois,
    'missions_publiees_ce_mois', v_missions_publiees_ce_mois
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_stripe_webhook_event_is_new(p_event_id text, p_event_type text, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.stripe_webhook_events (event_id, event_type, payload)
  VALUES (p_event_id, p_event_type, p_payload)
  ON CONFLICT (event_id) DO NOTHING;

  -- TRUE tant que l'event n'a PAS été traité avec succès (traite_le IS NULL) :
  -- couvre le nouvel event ET le retry Stripe d'un event qui avait échoué.
  -- FALSE seulement si déjà traité avec succès → idempotence.
  -- (Avant : « AND recu_le > NOW() - INTERVAL '1 minute' » faisait que tout retry
  -- Stripe arrivant >1 min après l'échec initial était faussement considéré
  -- « déjà traité » → l'edge renvoyait 200, Stripe arrêtait de réessayer, et le
  -- webhook en échec était définitivement perdu.)
  RETURN EXISTS (
    SELECT 1 FROM public.stripe_webhook_events
    WHERE event_id = p_event_id AND traite_le IS NULL
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_api_key(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := est_admin();
  v_etab_id uuid := mon_etablissement_id();
  v_target_etab uuid;
  v_nom text;
BEGIN
  SELECT etablissement_id, nom INTO v_target_etab, v_nom FROM public.api_keys WHERE id = p_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Clé introuvable');
  END IF;

  IF NOT v_is_admin AND v_target_etab IS DISTINCT FROM v_etab_id THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  DELETE FROM public.api_keys WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor, CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'API_KEY_SUPPRIMEE', 'api_key', p_id,
    NULL, jsonb_build_object('id', p_id, 'nom', v_nom), NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_suis_soignant_reel()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM soignants s WHERE s.id = auth.uid() AND s.est_compte_test = false);
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_missions_futures INTEGER;
    v_hash TEXT;
    v_uid UUID := auth.uid();
BEGIN
    SELECT COUNT(*) INTO v_missions_futures FROM missions
    WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE','EN_COURS') AND fin_le > NOW();
    IF v_missions_futures > 0 THEN
        RETURN jsonb_build_object('error', 'Vous avez ' || v_missions_futures || ' mission(s) en cours.');
    END IF;
    v_hash := encode(digest(v_uid::TEXT || NOW()::TEXT, 'sha256'), 'hex');
    UPDATE soignants SET
        prenom = 'Soignant', nom = 'Supprimé',
        email = v_hash || '@supprime.jolene.app',
        telephone = NULL, adresse_rue = NULL, adresse_ville = NULL,
        adresse_code_postal = NULL, numero_secu = NULL,
        numero_securite_sociale = NULL,
        lieu_naissance_commune = NULL, lieu_naissance_departement = NULL,
        pays_naissance = NULL, nationalite = NULL, sexe = NULL,
        date_naissance = NULL, siret_liberal = NULL,
        numero_tva = NULL, bio = NULL, specialites = NULL,
        avatar_url = NULL, adresse_lat = NULL, adresse_lng = NULL,
        numero_rpps = NULL, numero_adeli = NULL,
        iban_last4 = NULL, stripe_account_id = NULL,
        psc_sub = NULL, psc_linked_le = NULL, psc_last_login = NULL,
        mandat_facturation_signe = FALSE, mandat_facturation_signe_le = NULL,
        sms_actif = FALSE, sms_consent_le = NULL,
        supprime_le = NOW()
    WHERE id = v_uid;
    UPDATE evaluations SET commentaire = NULL WHERE evaluateur_id = v_uid OR evalue_id = v_uid;
    DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
    DELETE FROM tokens_calendrier WHERE soignant_id = v_uid;
    UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    DELETE FROM attestations_heures_externes WHERE soignant_id = v_uid;
    DELETE FROM favoris_soignant_etab WHERE soignant_id = v_uid;
    DELETE FROM reclamations_scoring WHERE soignant_id = v_uid;
    DELETE FROM notifications WHERE destinataire_id = v_uid;
    UPDATE parrainages SET parrain_id = NULL WHERE parrain_id = v_uid;
    UPDATE parrainages SET filleul_id = NULL WHERE filleul_id = v_uid;
    UPDATE presences SET
        arrivee_lat = NULL, arrivee_lng = NULL, depart_lat = NULL, depart_lng = NULL,
        arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
        arrivee_id_terminal = NULL, depart_id_terminal = NULL,
        arrivee_modele_terminal = NULL, depart_modele_terminal = NULL
    WHERE soignant_id = v_uid;
    DELETE FROM pings_gps_mission WHERE soignant_id = v_uid;
    DELETE FROM consentements_ping_gps WHERE soignant_id = v_uid;
    UPDATE scans_pointage SET
        latitude = NULL, longitude = NULL, precision_gps_m = NULL,
        id_terminal = NULL, ip_address = NULL, distance_etablissement_m = NULL
    WHERE soignant_id = v_uid;
    UPDATE documents_soignants SET supprime_le = NOW() WHERE soignant_id = v_uid;
    UPDATE partages_rib SET actif = FALSE WHERE soignant_id = v_uid;
    UPDATE stripe_connect_onboarding SET
        stripe_account_id = 'SUPPRIME_' || LEFT(v_hash, 20), iban_last4 = NULL, erreur_onboarding = NULL
    WHERE soignant_id = v_uid;
    UPDATE candidatures SET message = NULL WHERE soignant_id = v_uid;
    UPDATE contrats_mission SET
        signature_ip_soignant = NULL, signature_navigateur_soignant = NULL, signature_image_soignant = NULL
    WHERE soignant_id = v_uid;
    DELETE FROM conversions_liberal WHERE soignant_id = v_uid;
    DELETE FROM heures_externes WHERE soignant_id = v_uid;
    DELETE FROM pauses_presence WHERE soignant_id = v_uid;
    DELETE FROM souscriptions_prevoyance WHERE soignant_id = v_uid;
    DELETE FROM suivi_conversion_3200h WHERE soignant_id = v_uid;
    DELETE FROM mandats_facturation_signatures WHERE soignant_id = v_uid;
    DELETE FROM cessions_creance WHERE soignant_id = v_uid;
    UPDATE factures_honoraires SET soignant_id = v_uid WHERE soignant_id = v_uid;
    DELETE FROM factor_advances WHERE soignant_id = v_uid;
    DELETE FROM psc_auth_sessions WHERE cree_le < NOW();
    DELETE FROM email_queue WHERE destinataire_id = v_uid;
    UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL WHERE destinataire_id = v_uid;
    DELETE FROM cotisations_sociales WHERE soignant_id = v_uid;
    DELETE FROM conformite_travail WHERE soignant_id = v_uid;
    UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    UPDATE stripe_transfers SET soignant_id = NULL WHERE soignant_id = v_uid;
    UPDATE paiements_soignant SET soignant_id = NULL WHERE soignant_id = v_uid;
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (v_uid, 'SOIGNANT', 'RGPD_SUPPRESSION_COMPTE', 'soignant', v_uid,
        jsonb_build_object('anonymise', true, 'tables_nettoyees', ARRAY[
            'soignants','evaluations','tokens_push','tokens_calendrier','messages_mission','messages_chat',
            'attestations_heures_externes','favoris','reclamations_scoring','parrainages','notifications',
            'presences','pings_gps_mission','consentements_ping_gps','scans_pointage',
            'documents_soignants','partages_rib','stripe_connect_onboarding','candidatures',
            'contrats_mission','conversions_liberal','heures_externes','pauses_presence',
            'souscriptions_prevoyance','suivi_conversion_3200h',
            'mandats_facturation_signatures','cessions_creance','factures_honoraires','factor_advances',
            'email_queue','sms_envoyes','cotisations_sociales','conformite_travail',
            'messages_litige','stripe_transfers','paiements_soignant']));
    RETURN jsonb_build_object('success', true, 'message', 'Votre compte a été supprimé et vos données anonymisées.');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_terminer_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_nb_presences INTEGER;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;

    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    IF v_mission.statut != 'EN_COURS' THEN
        RETURN jsonb_build_object('error', 'La mission doit être EN_COURS pour être terminée. Statut actuel : ' || v_mission.statut);
    END IF;

    -- ★ Vérifier qu'il y a au moins une présence enregistrée
    SELECT COUNT(*) INTO v_nb_presences FROM presences WHERE mission_id = p_mission_id;
    IF v_nb_presences = 0 AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Impossible de terminer : aucune présence enregistrée. Le soignant doit pointer son arrivée et son départ.');
    END IF;

    UPDATE missions SET
        statut = 'TERMINEE',
        terminee_le = NOW(),
        modifie_le = NOW()
    WHERE id = p_mission_id;

    -- Notifier le soignant (colonne = corps, pas message)
    IF v_mission.soignant_assigne_id IS NOT NULL THEN
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.soignant_assigne_id, 'SYSTEM',
            'Mission terminée ✅',
            'La mission "' || v_mission.intitule || '" est terminée. Consultez vos gains.',
            '/soignant/mes-gains', 'SOIGNANT');
    END IF;

    -- ★ Les cotisations sont calculées automatiquement via trg_auto_cotisations

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_compte_rate_limited()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_allowed BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifié');
    END IF;
    
    v_allowed := fn_verifier_rate_limit(v_user_id::TEXT, 'supprimer_compte', 1, 86400);
    IF NOT v_allowed THEN
        RETURN jsonb_build_object('error', 'Demande de suppression déjà en cours.');
    END IF;
    
    RETURN fn_supprimer_mon_compte();
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_sync_mission_creneaux()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission_id uuid; v_old_mission_id uuid; v_debut timestamptz; v_fin timestamptz;
  v_duree numeric; v_nb integer; v_debut_eff timestamptz; v_fin_eff timestamptz;
  v_duree_eff numeric; v_duree_phase2 numeric;
BEGIN
  IF current_setting('jolene.sync_in_progress', true) = 'true' THEN RETURN NULL; END IF;
  IF TG_OP = 'DELETE' THEN v_mission_id := OLD.mission_id; v_old_mission_id := NULL;
  ELSIF TG_OP = 'UPDATE' AND OLD.mission_id IS DISTINCT FROM NEW.mission_id THEN
    v_mission_id := NEW.mission_id; v_old_mission_id := OLD.mission_id;
  ELSE v_mission_id := NEW.mission_id; v_old_mission_id := NULL; END IF;

  SELECT MIN(debut), MAX(fin),
    COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0), COUNT(*)
  INTO v_debut, v_fin, v_duree, v_nb
  FROM mission_creneaux WHERE mission_id = v_mission_id AND type_creneau = 'PREVISIONNEL';
  SELECT MIN(debut), MAX(fin),
    COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
  INTO v_debut_eff, v_fin_eff, v_duree_eff
  FROM mission_creneaux WHERE mission_id = v_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;
  IF v_duree_eff = 0 AND v_debut_eff IS NULL THEN v_duree_eff := NULL; END IF;
  v_duree_phase2 := GREATEST(COALESCE(v_duree_eff, 0), COALESCE(v_duree, 0));

  PERFORM set_config('jolene.sync_in_progress', 'true', true);
  IF v_nb > 0 THEN UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb WHERE id = v_mission_id;
  ELSE UPDATE missions SET nb_creneaux = 0 WHERE id = v_mission_id; END IF;
  PERFORM set_config('jolene.sync_in_progress', 'false', true);

  IF v_nb > 0 OR v_duree_eff IS NOT NULL THEN
    UPDATE missions SET duree_heures = ROUND(v_duree_phase2::numeric, 2),
      debut_effectif = v_debut_eff, fin_effective = v_fin_eff,
      duree_heures_effective = CASE WHEN v_duree_eff IS NOT NULL THEN ROUND(v_duree_eff::numeric, 2) ELSE NULL END
    WHERE id = v_mission_id;
  ELSE UPDATE missions SET duree_heures = NULL, debut_effectif = NULL, fin_effective = NULL, duree_heures_effective = NULL WHERE id = v_mission_id; END IF;

  IF v_old_mission_id IS NOT NULL THEN
    SELECT MIN(debut), MAX(fin),
      COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0), COUNT(*)
    INTO v_debut, v_fin, v_duree, v_nb
    FROM mission_creneaux WHERE mission_id = v_old_mission_id AND type_creneau = 'PREVISIONNEL';
    SELECT MIN(debut), MAX(fin),
      COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
    INTO v_debut_eff, v_fin_eff, v_duree_eff
    FROM mission_creneaux WHERE mission_id = v_old_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;
    IF v_duree_eff = 0 AND v_debut_eff IS NULL THEN v_duree_eff := NULL; END IF;
    v_duree_phase2 := GREATEST(COALESCE(v_duree_eff, 0), COALESCE(v_duree, 0));
    PERFORM set_config('jolene.sync_in_progress', 'true', true);
    IF v_nb > 0 THEN UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb WHERE id = v_old_mission_id;
    ELSE UPDATE missions SET nb_creneaux = 0 WHERE id = v_old_mission_id; END IF;
    PERFORM set_config('jolene.sync_in_progress', 'false', true);
    IF v_nb > 0 OR v_duree_eff IS NOT NULL THEN
      UPDATE missions SET duree_heures = ROUND(v_duree_phase2::numeric, 2),
        debut_effectif = v_debut_eff, fin_effective = v_fin_eff,
        duree_heures_effective = CASE WHEN v_duree_eff IS NOT NULL THEN ROUND(v_duree_eff::numeric, 2) ELSE NULL END
      WHERE id = v_old_mission_id;
    ELSE UPDATE missions SET duree_heures = NULL, debut_effectif = NULL, fin_effective = NULL, duree_heures_effective = NULL WHERE id = v_old_mission_id; END IF;
  END IF;
  RETURN NULL;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions_actives int;
  v_factures_impayees int;
  v_hash text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT id INTO v_etab_id FROM etablissements WHERE id = v_uid;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun établissement lié à ce compte');
  END IF;

  -- Garde-fou : missions actives
  SELECT count(*) INTO v_missions_actives FROM missions
   WHERE etablissement_id = v_etab_id
     AND statut IN ('OUVERTE','ASSIGNEE','EN_COURS','LITIGE')
     AND fin_le > NOW();
  IF v_missions_actives > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('Vous avez %s mission(s) ouverte(s) ou en cours.', v_missions_actives));
  END IF;

  -- Garde-fou : factures impayées (la suppression n'efface pas une dette)
  SELECT count(*) INTO v_factures_impayees FROM factures
   WHERE etablissement_id = v_etab_id AND statut IN ('EN_ATTENTE','EN_RETARD');
  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('%s facture(s) impayée(s). Réglez-les avant suppression.', v_factures_impayees));
  END IF;

  -- Bypass trigger fn_protect_etablissement_commercial pour anonymisation
  PERFORM set_config('app.internal_operation', 'true', true);
  v_hash := encode(extensions.digest(v_etab_id::text || NOW()::text, 'sha256'), 'hex');

  -- Anonymisation établissement
  UPDATE etablissements SET
    nom = 'Établissement supprimé',
    siret = '99' || LPAD(LEFT(REGEXP_REPLACE(v_hash, '[^0-9]', '', 'g'), 12), 12, '0'),
    finess = NULL,
    email_contact = v_hash || '@supprime.jolene.app',
    telephone_contact = NULL,
    adresse_rue = '[SUPPRIMÉ]',
    adresse_ville = '[SUPPRIMÉ]',
    adresse_code_postal = '00000',
    adresse_departement = NULL, adresse_lat = NULL, adresse_lng = NULL,
    description = NULL, logo_url = NULL, horaires_ouverture = NULL,
    contrat_url = NULL,
    siret_raison_sociale = NULL, siret_categorie_juridique = NULL,
    siret_code_naf = NULL, siret_est_actif = false,
    chorus_pro_actif = false, chorus_pro_identifiant = NULL,
    sms_actif = false, sms_consent_le = NULL,
    peut_publier_missions = false,
    bloque_auto_le = NOW(),
    bloque_auto_raisons = jsonb_build_array('COMPTE_SUPPRIME_RGPD'),
    supprime_le = NOW(),
    stripe_sepa_payment_method_id = NULL
  WHERE id = v_etab_id;

  -- Tables liées
  DELETE FROM admins_groupe_sante WHERE utilisateur_id = v_uid;
  DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
  DELETE FROM notifications WHERE destinataire_id = v_uid;

  UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

  UPDATE evaluations SET commentaire = NULL
   WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

  DELETE FROM exclusions WHERE exclu_par = v_uid OR exclu_id = v_uid;

  UPDATE partages_rib SET actif = false, expire_le = NOW()
   WHERE etablissement_id = v_etab_id;

  -- Contrats : on conserve (preuves légales) mais anonymise IP/UA
  UPDATE contrats_mission SET
    signature_ip_etablissement = NULL,
    signature_navigateur_etablissement = NULL,
    signature_image_etablissement = NULL
   WHERE etablissement_id = v_etab_id;

  DELETE FROM email_queue WHERE destinataire_id = v_uid;
  UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL
   WHERE destinataire_id = v_uid;

  DELETE FROM calendar_events_sync WHERE connection_id IN
    (SELECT id FROM calendar_connections WHERE utilisateur_id = v_uid);
  DELETE FROM calendar_connections WHERE utilisateur_id = v_uid;
  DELETE FROM api_keys WHERE etablissement_id = v_etab_id;

  -- Audit (type_acteur ADMIN_ETABLISSEMENT, action RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT)
  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (v_uid, 'ADMIN_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT', 'etablissement', v_etab_id,
    jsonb_build_object('anonymise', true));

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Établissement anonymisé. Factures conservées 10 ans (LPF L102 B).',
    'etablissement_id', v_etab_id
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_compte_etablissement_rate_limited()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_allowed boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_allowed := public.fn_verifier_rate_limit(v_uid::text, 'supprimer_compte_etablissement', 1, 86400);
  IF NOT v_allowed THEN
    RETURN jsonb_build_object('error', 'Demande de suppression déjà en cours.');
  END IF;

  RETURN public.fn_supprimer_mon_compte_etablissement();
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_filtre_sauvegarde(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_old RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;

  SELECT * INTO v_old FROM filtres_sauvegardes WHERE id = p_id AND utilisateur_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Filtre introuvable'); END IF;

  DELETE FROM filtres_sauvegardes WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_SUPPRIME', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := p_id,
    p_details := jsonb_build_object('nom', v_old.nom, 'audience', v_old.audience::text)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_supprimer_mes_tokens_push()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_count int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;
  DELETE FROM public.tokens_push WHERE utilisateur_id = v_uid;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'tokens_supprimes', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_toggle_pool_urgence(p_actif boolean, p_rayon_km integer DEFAULT 15, p_creneaux jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
    v_rcp_ok BOOLEAN;
BEGIN
    SELECT tous_documents_valides, supprime_le, type_exercice, statut_liberal
      INTO v_soignant FROM soignants WHERE id = auth.uid();

    IF p_actif THEN
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Vos documents obligatoires ne sont pas tous validés. Complétez votre dossier pour rejoindre le pool urgence.');
        END IF;

        IF v_soignant.type_exercice = 'LIBERAL' THEN
            SELECT EXISTS(
                SELECT 1 FROM documents_soignants
                WHERE soignant_id = auth.uid() AND type_document = 'RCP_ASSURANCE'
                AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
                AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
            ) INTO v_rcp_ok;
            IF NOT v_rcp_ok THEN
                RETURN jsonb_build_object('error', 'Votre assurance RCP est manquante ou expirée. Elle est obligatoire pour le pool urgence (exercice libéral).');
            END IF;
        END IF;
    END IF;

    UPDATE soignants SET
        disponible_urgence = p_actif,
        urgence_rayon_km = p_rayon_km,
        urgence_creneaux = p_creneaux,
        modifie_le = NOW()
    WHERE id = auth.uid();

    RETURN jsonb_build_object('success', true, 'disponible_urgence', p_actif);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_top_soignants(p_profession text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, prenom text, nom text, profession text, note_moyenne numeric, nb_evaluations integer, score_fiabilite integer, total_missions_terminees integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.id, s.prenom, s.nom, s.profession::TEXT, s.note_moyenne, s.nb_evaluations,
           ROUND(COALESCE(s.score_fiabilite, 0))::integer AS score_fiabilite,
           s.total_missions_terminees
    FROM soignants s
    WHERE s.supprime_le IS NULL
    AND s.est_compte_test = false
    AND fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND (p_profession IS NULL OR s.profession::TEXT = p_profession)
    ORDER BY s.note_moyenne DESC NULLS LAST, s.score_fiabilite DESC, s.total_missions_terminees DESC
    LIMIT p_limit;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_toggle_pool_urgence_sms(p_actif boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  UPDATE soignants
  SET pool_urgence_sms_opt_in = COALESCE(p_actif, false)
  WHERE id = v_uid AND supprime_le IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'POOL_URGENCE_SMS_TOGGLE',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('actif', p_actif)
  );

  RETURN jsonb_build_object('success', true, 'pool_urgence_sms_opt_in', COALESCE(p_actif, false));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_top_etablissements_soignant(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
  v_limit INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 3), 1), 10);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'etablissement_id', etablissement_id,
    'nom', nom,
    'ville', ville,
    'logo_url', logo_url,
    'nb_missions', nb_missions,
    'derniere_mission_le', derniere_mission_le
  ) ORDER BY nb_missions DESC, derniere_mission_le DESC NULLS LAST), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      m.etablissement_id,
      e.nom,
      e.adresse_ville AS ville,
      e.logo_url,
      count(*) AS nb_missions,
      max(m.fin_le) AS derniere_mission_le
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.soignant_assigne_id = v_uid AND m.statut = 'TERMINEE'
    GROUP BY m.etablissement_id, e.nom, e.adresse_ville, e.logo_url
    ORDER BY count(*) DESC, max(m.fin_le) DESC NULLS LAST
    LIMIT v_limit
  ) t;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_toggle_favori_etablissement(p_etablissement_id uuid, p_actif boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_existe BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT EXISTS (SELECT 1 FROM etablissements WHERE id = p_etablissement_id) INTO v_etab_existe;
  IF NOT v_etab_existe THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  IF p_actif THEN
    INSERT INTO favoris_soignant_etab (soignant_id, etablissement_id)
    VALUES (v_uid, p_etablissement_id)
    ON CONFLICT (soignant_id, etablissement_id) DO NOTHING;
    PERFORM public.fn_ecrire_audit_safe(v_uid, 'SOIGNANT', 'FAVORI_AJOUTE', 'etablissement', p_etablissement_id, NULL, jsonb_build_object('sens', 'soignant_etab'));
  ELSE
    DELETE FROM favoris_soignant_etab
    WHERE soignant_id = v_uid AND etablissement_id = p_etablissement_id;
    PERFORM public.fn_ecrire_audit_safe(v_uid, 'SOIGNANT', 'FAVORI_RETIRE', 'etablissement', p_etablissement_id, NULL, jsonb_build_object('sens', 'soignant_etab'));
  END IF;

  RETURN jsonb_build_object('success', true, 'actif', p_actif);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_test_seed_mission(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_cols text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'fn_test_seed_mission réservé au service_role (seed E2E uniquement)';
  END IF;
  PERFORM set_config('app.internal_operation', 'true', true);
  PERFORM set_config('jolene.creer_mission_context', 'true', true);
  v_cols := (SELECT string_agg(quote_ident(key), ',') FROM jsonb_object_keys(p_data) AS key);
  EXECUTE format(
    'INSERT INTO public.missions (%s) SELECT %s FROM jsonb_populate_record(NULL::public.missions, $1) RETURNING id',
    v_cols, v_cols
  ) USING p_data INTO v_id;
  RETURN v_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_test_update_mission(p_mission_id uuid, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_set text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'fn_test_update_mission réservé au service_role (seed E2E uniquement)';
  END IF;
  PERFORM set_config('app.internal_operation', 'true', true);
  PERFORM set_config('jolene.creer_mission_context', 'true', true);
  v_set := (SELECT string_agg(format('%I = r.%I', key, key), ',') FROM jsonb_object_keys(p_data) AS key);
  EXECUTE format(
    'UPDATE public.missions m SET %s FROM jsonb_populate_record(NULL::public.missions, $1) r WHERE m.id = $2',
    v_set
  ) USING p_data, p_mission_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_test_purge_mission(p_mission_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  v_intitule text;
BEGIN
  SELECT intitule INTO v_intitule FROM missions WHERE id = p_mission_id;
  IF v_intitule IS NULL THEN RETURN; END IF;
  -- Garde-fou : réservé STRICTEMENT aux missions de test (jamais de données réelles).
  IF v_intitule NOT LIKE '[pw-test%' AND v_intitule NOT LIKE '[playwright-test]%' THEN
    RAISE EXCEPTION 'fn_test_purge_mission reserve aux missions de test (intitule=%)', v_intitule;
  END IF;

  -- messages_chat : enfant de conversations (FK conversation_id, pas mission_id).
  DELETE FROM messages_chat WHERE conversation_id IN (SELECT id FROM conversations WHERE mission_id = p_mission_id);

  -- Toutes les tables ayant une FK directe vers missions.id (hors auto-référence missions).
  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND c.confrelid = 'public.missions'::regclass
      AND c.conrelid <> 'public.missions'::regclass
  LOOP
    EXECUTE format('DELETE FROM %s WHERE %I = $1', r.tbl, r.col) USING p_mission_id;
  END LOOP;

  DELETE FROM missions WHERE id = p_mission_id;
END;
$function$
