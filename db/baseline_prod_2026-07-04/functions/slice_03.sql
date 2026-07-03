CREATE OR REPLACE FUNCTION public.fn_admin_rejeter_etablissement(p_etablissement_id uuid, p_motif text DEFAULT 'Non conforme aux critères de la plateforme'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_nom TEXT; v_motif_safe TEXT;
BEGIN
    IF NOT est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement'); END IF;
    v_motif_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_motif), ''), 'Non conforme'), '<[^>]*>', '', 'g'), 500);
    UPDATE etablissements SET statut_verification = 'REJETE', peut_publier_missions = FALSE, motif_rejet = v_motif_safe
    WHERE id = p_etablissement_id;
    SELECT COALESCE(nom, 'Inconnu') INTO v_nom FROM etablissements WHERE id = p_etablissement_id;
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'ADMIN_ACTION', 'etablissement', p_etablissement_id,
        jsonb_build_object('sous_action', 'REJET_ETABLISSEMENT', 'nom', v_nom, 'motif', v_motif_safe));
    RETURN jsonb_build_object('success', TRUE, 'message', 'Établissement rejeté : ' || v_nom);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige(p_litige_id uuid, p_resolution text, p_ajuster_heures numeric DEFAULT NULL::numeric, p_ajuster_taux numeric DEFAULT NULL::numeric, p_en_faveur_de text DEFAULT 'NEUTRE'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_litige RECORD;
    v_presence RECORD;
    v_mission RECORD;
    v_nouveau_statut TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Réservé aux administrateurs');
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.statut IN ('RESOLU_ADMIN','FERME') THEN
        RETURN jsonb_build_object('error', 'Ce litige est déjà résolu');
    END IF;

    -- Déterminer le statut de résolution
    v_nouveau_statut := CASE p_en_faveur_de
        WHEN 'SOIGNANT' THEN 'RESOLU_SOIGNANT'
        WHEN 'ETABLISSEMENT' THEN 'RESOLU_ETABLISSEMENT'
        ELSE 'RESOLU_ADMIN'
    END;

    -- Ajuster les heures de présence si demandé
    IF p_ajuster_heures IS NOT NULL AND v_litige.presence_id IS NOT NULL THEN
        SELECT * INTO v_presence FROM presences WHERE id = v_litige.presence_id;
        IF v_presence.id IS NOT NULL THEN
            UPDATE presences SET 
                heures_reelles = p_ajuster_heures,
                duree_nette_min = p_ajuster_heures * 60,
                modifie_le = NOW()
            WHERE id = v_litige.presence_id;
        END IF;
    END IF;

    -- Ajuster le taux horaire de la mission si demandé
    IF p_ajuster_taux IS NOT NULL THEN
        SELECT * INTO v_mission FROM missions WHERE id = v_litige.mission_id;
        IF v_mission.id IS NOT NULL THEN
            UPDATE missions SET 
                taux_horaire_base = p_ajuster_taux,
                modifie_le = NOW()
            WHERE id = v_litige.mission_id;
            -- Le trigger dec_calculer_finance_mission recalculera automatiquement
        END IF;
    END IF;

    -- Résoudre le litige
    UPDATE litiges SET 
        statut = v_nouveau_statut,
        resolution = p_resolution,
        resolu_par = auth.uid(),
        resolu_le = NOW()
    WHERE id = p_litige_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'statut', v_nouveau_statut,
        'heures_ajustees', p_ajuster_heures IS NOT NULL,
        'taux_ajuste', p_ajuster_taux IS NOT NULL
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_recategoriser_litige_legacy(p_litige_id uuid, p_nouveau_type type_litige)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id       UUID := auth.uid();
  v_litige        public.litiges%ROWTYPE;
  v_ancien_type   public.type_litige;
  v_nouvelle_cat  public.categorie_litige;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis.');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable.');
  END IF;

  IF v_litige.type_legacy IS DISTINCT FROM TRUE THEN
    RETURN jsonb_build_object(
      'error', 'Ce litige n''est pas marqué legacy — recatégorisation interdite.'
    );
  END IF;

  IF v_litige.type_litige IS DISTINCT FROM 'AUTRE'::public.type_litige THEN
    RETURN jsonb_build_object(
      'error', 'Seuls les litiges legacy de type AUTRE peuvent être recatégorisés.'
    );
  END IF;

  IF p_nouveau_type IS NULL THEN
    RETURN jsonb_build_object('error', 'Nouveau type requis.');
  END IF;

  v_ancien_type := v_litige.type_litige;

  UPDATE public.litiges
     SET type_litige = p_nouveau_type,
         type_legacy = FALSE
   WHERE id = p_litige_id
  RETURNING categorie_litige INTO v_nouvelle_cat;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_RECATEGORISATION_LEGACY',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'ancien_type', v_ancien_type,
      'nouveau_type', p_nouveau_type,
      'nouvelle_categorie', v_nouvelle_cat,
      'motif_original', v_litige.motif
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', p_litige_id,
    'ancien_type', v_ancien_type,
    'nouveau_type', p_nouveau_type,
    'nouvelle_categorie', v_nouvelle_cat,
    'type_legacy', FALSE
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_alerte(p_alerte_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.alertes_systeme
  SET resolu_le = now(), resolu_par = auth.uid()
  WHERE id = p_alerte_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Alerte introuvable');
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_reset_test_account(p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email text;
  v_user_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_email := CASE p_role
    WHEN 'SOIGNANT' THEN 'playwright-soignant@jolene.app'
    WHEN 'ADMIN_ETABLISSEMENT' THEN 'playwright-etab@jolene.app'
    ELSE NULL
  END;

  IF v_email IS NULL THEN
    RETURN jsonb_build_object('error', 'Rôle invalide');
  END IF;

  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Compte test introuvable, exécuter le seed d''abord');
  END IF;

  IF p_role = 'SOIGNANT' THEN
    DELETE FROM public.candidatures WHERE soignant_id = v_user_id;
    DELETE FROM public.notations WHERE evaluateur_id = v_user_id OR evalue_id = v_user_id;
    DELETE FROM public.exclusions WHERE excluant_id = v_user_id;
    DELETE FROM public.notifications WHERE destinataire_id = v_user_id;
    DELETE FROM public.parrainages WHERE filleul_id = v_user_id;
    UPDATE public.soignants SET
      score_fiabilite = 50,
      total_missions_terminees = 0,
      total_missions_annulees = 0,
      heures_cumulees = 0,
      premiere_mission_le = NULL
    WHERE id = v_user_id;
  ELSIF p_role = 'ADMIN_ETABLISSEMENT' THEN
    DELETE FROM public.candidatures WHERE mission_id IN (
      SELECT id FROM public.missions WHERE etablissement_id = v_user_id
    );
    DELETE FROM public.missions WHERE etablissement_id = v_user_id AND statut IN ('OUVERTE', 'BROUILLON');
    DELETE FROM public.notifications WHERE destinataire_id = v_user_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'role', p_role);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_template_contrat(p_template_id uuid, p_contenu_html text, p_nom text DEFAULT NULL::text, p_variables jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ancien_version int;
  v_nouvelle_version int;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF p_contenu_html IS NULL OR length(p_contenu_html) < 50 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTENU_TROP_COURT',
                                'error', 'Le contenu HTML doit faire au moins 50 caractères');
  END IF;

  SELECT version INTO v_ancien_version FROM public.templates_contrat WHERE id = p_template_id;
  IF v_ancien_version IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEMPLATE_INTROUVABLE');
  END IF;

  v_nouvelle_version := v_ancien_version + 1;

  UPDATE public.templates_contrat
  SET contenu_html = p_contenu_html,
      nom = COALESCE(p_nom, nom),
      variables = COALESCE(p_variables, variables),
      version = v_nouvelle_version,
      modifie_le = now()
  WHERE id = p_template_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'template_contrat', p_template_id,
    jsonb_build_object(
      'evenement', 'TEMPLATE_CONTRAT_MODIFIE',
      'ancienne_version', v_ancien_version,
      'nouvelle_version', v_nouvelle_version,
      'taille_contenu', length(p_contenu_html)
    )
  );

  RETURN jsonb_build_object('success', true, 'version', v_nouvelle_version);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_planning_global(p_debut date, p_fin date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'debut', p_debut,
    'fin', p_fin,
    'missions', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id,
        'intitule', m.intitule,
        'statut', m.statut,
        'profession_requise', m.profession_requise,
        'service', m.service,
        'debut_le', m.debut_le,
        'fin_le', m.fin_le,
        'est_urgente', m.est_urgente,
        'etablissement_nom', e.nom,
        'etablissement_ville', e.adresse_ville,
        'soignant_nom', CASE WHEN s.id IS NOT NULL THEN s.prenom || ' ' || s.nom ELSE NULL END
      ) ORDER BY m.debut_le), '[]'::jsonb)
      FROM missions m
      LEFT JOIN etablissements e ON e.id = m.etablissement_id
      LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
      WHERE m.debut_le >= p_debut::timestamptz
        AND m.debut_le < (p_fin::timestamptz + interval '1 day')
    )
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_recherche_globale(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_q text := LOWER(TRIM(COALESCE(p_query, '')));
  v_vide jsonb := jsonb_build_object(
    'utilisateurs', '[]'::jsonb,
    'missions', '[]'::jsonb,
    'factures', '[]'::jsonb
  );
  v_utilisateurs jsonb;
  v_missions jsonb;
  v_factures jsonb;
BEGIN
  IF NOT est_admin() THEN RETURN v_vide; END IF;
  IF length(v_q) < 2 THEN RETURN v_vide; END IF;

  -- Utilisateurs : soignants (nom, prénom, email, téléphone) + établissements (nom)
  SELECT COALESCE(jsonb_agg(x.r), '[]'::jsonb) INTO v_utilisateurs FROM (
    SELECT jsonb_build_object(
      'id', u.id,
      'type', CASE
        WHEN s.id IS NOT NULL THEN 'soignant'
        WHEN e.id IS NOT NULL THEN 'etablissement'
        ELSE 'inconnu'
      END,
      'nom', COALESCE(s.nom, e.nom, ''),
      'prenom', COALESCE(s.prenom, ''),
      'email', u.email,
      'profession', s.profession,
      'ville', COALESCE(s.adresse_ville, e.adresse_ville)
    ) AS r
    FROM auth.users u
    LEFT JOIN soignants s ON s.id = u.id
    LEFT JOIN etablissements e ON e.id = u.id
    WHERE LOWER(u.email) LIKE v_q || '%'
       OR LOWER(COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(s.nom, '') || ' ' || COALESCE(s.prenom, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(e.nom, '')) LIKE '%' || v_q || '%'
       OR COALESCE(s.telephone, '') LIKE v_q || '%'
    LIMIT 5
  ) x;

  -- Missions : intitulé, service, n° de note d'honoraires, début d'UUID, nom d'établissement
  SELECT COALESCE(jsonb_agg(x.r), '[]'::jsonb) INTO v_missions FROM (
    SELECT jsonb_build_object(
      'id', m.id,
      'intitule', m.intitule,
      'statut', m.statut,
      'etablissement', e.nom,
      'debut_le', m.debut_le,
      'profession', m.profession_requise
    ) AS r
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE LOWER(COALESCE(m.intitule, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(m.service, '')) LIKE '%' || v_q || '%'
       OR LOWER(COALESCE(m.numero_note_honoraires, '')) LIKE v_q || '%'
       OR m.id::text LIKE v_q || '%'
       OR LOWER(e.nom) LIKE '%' || v_q || '%'
    ORDER BY m.debut_le DESC
    LIMIT 5
  ) x;

  -- Factures : numéro, début d'UUID, nom d'établissement
  SELECT COALESCE(jsonb_agg(x.r), '[]'::jsonb) INTO v_factures FROM (
    SELECT jsonb_build_object(
      'id', f.id,
      'numero', f.numero_facture,
      'statut', f.statut,
      'etablissement', e.nom,
      'montant_ttc', f.montant_ttc,
      'date_emission', f.date_emission,
      'type_document', f.type_document
    ) AS r
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE LOWER(COALESCE(f.numero_facture, '')) LIKE '%' || v_q || '%'
       OR f.id::text LIKE v_q || '%'
       OR LOWER(e.nom) LIKE '%' || v_q || '%'
    ORDER BY f.date_emission DESC NULLS LAST
    LIMIT 5
  ) x;

  RETURN jsonb_build_object(
    'utilisateurs', v_utilisateurs,
    'missions', v_missions,
    'factures', v_factures
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_stripe_connect_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE v_total_comptes integer := 0; v_complets integer := 0; v_en_cours integer := 0; v_total_verse_soignants numeric := 0; v_en_attente_soignants numeric := 0; v_total_commission_jolene numeric := 0; v_en_attente_commission numeric := 0; v_volume_total numeric := 0; v_volume_en_attente numeric := 0; BEGIN IF NOT est_admin() THEN RETURN '{"error":"Accès réservé aux administrateurs"}'::JSONB; END IF; SELECT COUNT(*) INTO v_total_comptes FROM stripe_connect_onboarding; SELECT COUNT(*) INTO v_complets FROM stripe_connect_onboarding WHERE statut = 'COMPLETE'; SELECT COUNT(*) INTO v_en_cours FROM stripe_connect_onboarding WHERE statut IN ('PENDING', 'EN_COURS'); SELECT COALESCE(SUM(montant_soignant), 0) INTO v_total_verse_soignants FROM stripe_transfers WHERE statut = 'COMPLETED'; SELECT COALESCE(SUM(montant_soignant), 0) INTO v_en_attente_soignants FROM stripe_transfers WHERE statut = 'PENDING'; SELECT COALESCE(SUM(montant_commission), 0) INTO v_total_commission_jolene FROM stripe_transfers WHERE statut = 'COMPLETED'; SELECT COALESCE(SUM(montant_commission), 0) INTO v_en_attente_commission FROM stripe_transfers WHERE statut = 'PENDING'; SELECT COALESCE(SUM(montant_total), 0) INTO v_volume_total FROM stripe_transfers WHERE statut = 'COMPLETED'; SELECT COALESCE(SUM(montant_total), 0) INTO v_volume_en_attente FROM stripe_transfers WHERE statut = 'PENDING'; RETURN jsonb_build_object('total_comptes', v_total_comptes, 'complets', v_complets, 'en_cours', v_en_cours, 'total_verse_soignants', v_total_verse_soignants, 'en_attente_soignants', v_en_attente_soignants, 'total_commission_jolene', v_total_commission_jolene, 'en_attente_commission', v_en_attente_commission, 'volume_total', v_volume_total, 'volume_en_attente', v_volume_en_attente); END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_suspendre_utilisateur(p_table text, p_id uuid, p_suspendre boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_nom TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    IF p_table NOT IN ('soignants', 'etablissements') THEN
        RETURN jsonb_build_object('error', 'Table invalide');
    END IF;

    IF p_table = 'soignants' THEN
        IF p_suspendre THEN
            UPDATE soignants SET supprime_le = NOW() WHERE id = p_id AND supprime_le IS NULL;
        ELSE
            UPDATE soignants SET supprime_le = NULL WHERE id = p_id AND supprime_le IS NOT NULL;
        END IF;
        SELECT COALESCE(prenom || ' ' || nom, 'Inconnu') INTO v_nom FROM soignants WHERE id = p_id;
    ELSIF p_table = 'etablissements' THEN
        IF p_suspendre THEN
            UPDATE etablissements SET supprime_le = NOW(), peut_publier_missions = FALSE WHERE id = p_id AND supprime_le IS NULL;
        ELSE
            UPDATE etablissements SET supprime_le = NULL WHERE id = p_id AND supprime_le IS NOT NULL;
        END IF;
        SELECT COALESCE(nom, 'Inconnu') INTO v_nom FROM etablissements WHERE id = p_id;
    END IF;

    -- Audit (fix: id_ressource au lieu de ressource_id)
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
        auth.uid(), 'ADMIN',
        CASE WHEN p_suspendre THEN 'SUSPENSION_COMPTE' ELSE 'REACTIVATION_COMPTE' END,
        p_table, p_id,
        jsonb_build_object('nom', v_nom, 'table', p_table, 'action', CASE WHEN p_suspendre THEN 'suspendre' ELSE 'réactiver' END)
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', CASE WHEN p_suspendre THEN 'Compte suspendu : ' ELSE 'Compte réactivé : ' END || v_nom
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige(p_litige_id uuid, p_resolution text, p_en_faveur_de text DEFAULT NULL::text, p_ajuster_heures numeric DEFAULT NULL::numeric, p_ajuster_taux numeric DEFAULT NULL::numeric, p_action_financiere text DEFAULT 'AUTO'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_litige RECORD;
  v_facture RECORD;
  v_action TEXT;
  v_nouveau_statut TEXT;
  v_nouveau_montant_ht NUMERIC;
  v_nouvelle_facture_id UUID;
  v_nouveau_numero_facture TEXT;
  v_avoir_id UUID;
  v_avoir_numero TEXT;
  v_diff NUMERIC;
  v_mode_remboursement public.mode_remboursement_avoir;
  v_delai_stripe_j INT;
  v_delai_urssaf_j INT;
  v_age_facture_j INT;
  v_regul_sociale BOOLEAN := FALSE;
  v_regen_request_ids BIGINT[] := ARRAY[]::BIGINT[];
  v_etab_user_id UUID;
  v_soignant_id UUID;
  v_email_data JSONB;
  v_taux_ref NUMERIC;
  v_heures_ref NUMERIC;
  v_taux_final NUMERIC;
  v_heures_final NUMERIC;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis pour cette opération.');
  END IF;
  IF length(trim(COALESCE(p_resolution, ''))) < 10 THEN
    RETURN jsonb_build_object('error', 'Le texte de résolution doit contenir au moins 10 caractères.');
  END IF;
  IF p_en_faveur_de IS NOT NULL AND p_en_faveur_de NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('error', 'p_en_faveur_de doit être SOIGNANT ou ETABLISSEMENT.');
  END IF;
  IF p_action_financiere NOT IN ('AUTO', 'AUCUNE', 'RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    RETURN jsonb_build_object('error', 'p_action_financiere invalide.');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable.');
  END IF;
  IF v_litige.statut IN ('RESOLU', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT',
                         'RESOLU_ADMIN', 'FERME', 'CLOTURE') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà résolu.');
  END IF;

  IF v_litige.facture_id IS NOT NULL THEN
    SELECT * INTO v_facture FROM public.factures_honoraires WHERE id = v_litige.facture_id;
  ELSE
    SELECT * INTO v_facture FROM public.factures_honoraires
     WHERE mission_id = v_litige.mission_id
       AND statut_litige = 'EN_ATTENTE_LITIGE'
     ORDER BY date_emission ASC NULLS LAST LIMIT 1;
  END IF;

  IF v_facture.id IS NOT NULL THEN
    SELECT m.taux_horaire_base INTO v_taux_ref
      FROM public.missions m
     WHERE m.id = v_facture.mission_id;

    SELECT p.heures_reelles INTO v_heures_ref
      FROM public.presences p
     WHERE p.mission_id = v_facture.mission_id
       AND p.valide_par_etablissement = TRUE
     ORDER BY p.valide_le DESC NULLS LAST
     LIMIT 1;

    v_taux_final   := COALESCE(p_ajuster_taux, v_taux_ref);
    v_heures_final := COALESCE(
      p_ajuster_heures,
      v_heures_ref,
      CASE WHEN v_taux_final IS NOT NULL AND v_taux_final <> 0
           THEN v_facture.montant_ht / v_taux_final
           ELSE NULL END
    );
  END IF;

  IF p_action_financiere = 'AUTO' THEN
    IF v_facture.id IS NULL OR (p_ajuster_heures IS NULL AND p_ajuster_taux IS NULL) THEN
      v_action := 'AUCUNE';
    ELSIF v_facture.statut = 'BROUILLON' THEN
      v_action := 'RECALCUL';
    ELSIF v_facture.statut = 'EMISE' THEN
      v_action := 'ANNULER_REEMETTRE';
    ELSIF v_facture.statut = 'PAYEE' THEN
      v_action := 'AVOIR';
    ELSE
      v_action := 'AUCUNE';
    END IF;
  ELSE
    v_action := p_action_financiere;
  END IF;

  IF v_action = 'RECALCUL' AND v_facture.id IS NOT NULL THEN
    IF v_heures_final IS NOT NULL AND v_taux_final IS NOT NULL THEN
      v_nouveau_montant_ht := v_heures_final * v_taux_final;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;

    UPDATE public.factures_honoraires
       SET montant_ht = v_nouveau_montant_ht,
           montant_ttc = v_nouveau_montant_ht * (1 + COALESCE(taux_tva, 0) / 100),
           montant_tva = v_nouveau_montant_ht * COALESCE(taux_tva, 0) / 100,
           statut_litige = 'LITIGE_RESOLU_AJUSTE',
           pdf_a_regenerer = TRUE
     WHERE id = v_facture.id;

    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_facture.id), 0);

  ELSIF v_action = 'ANNULER_REEMETTRE' AND v_facture.id IS NOT NULL THEN
    IF v_heures_final IS NOT NULL AND v_taux_final IS NOT NULL THEN
      v_nouveau_montant_ht := v_heures_final * v_taux_final;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;

    UPDATE public.factures_honoraires
       SET statut = 'ANNULEE',
           statut_litige = 'LITIGE_RESOLU_AJUSTE'
     WHERE id = v_facture.id;

    v_nouveau_numero_facture := public.next_invoice_number(v_facture.soignant_id);

    INSERT INTO public.factures_honoraires (
      soignant_id, etablissement_id, mission_id,
      numero_facture, montant_ht, montant_tva, montant_ttc,
      taux_tva, exoneration_tva, date_emission, date_echeance,
      statut, mandat_version, type_document, facture_precedente_id,
      statut_litige, litige_id, pdf_a_regenerer,
      periode_debut, periode_fin, numero_semaine_iso, annee_iso
    ) VALUES (
      v_facture.soignant_id, v_facture.etablissement_id, v_facture.mission_id,
      v_nouveau_numero_facture,
      v_nouveau_montant_ht,
      v_nouveau_montant_ht * COALESCE(v_facture.taux_tva, 0) / 100,
      v_nouveau_montant_ht * (1 + COALESCE(v_facture.taux_tva, 0) / 100),
      v_facture.taux_tva, v_facture.exoneration_tva,
      CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days',
      'BROUILLON', v_facture.mandat_version,
      'FACTURE', v_facture.id,
      'LITIGE_RESOLU_AJUSTE', p_litige_id, TRUE,
      COALESCE(v_facture.periode_debut, CURRENT_DATE),
      COALESCE(v_facture.periode_fin, v_facture.periode_debut, CURRENT_DATE),
      v_facture.numero_semaine_iso, v_facture.annee_iso
    )
    RETURNING id INTO v_nouvelle_facture_id;

    v_regen_request_ids := v_regen_request_ids
      || COALESCE(public.fn_trigger_regen_pdf_immediate(v_nouvelle_facture_id), 0);

  ELSIF v_action = 'AVOIR' AND v_facture.id IS NOT NULL THEN
    IF v_heures_final IS NOT NULL AND v_taux_final IS NOT NULL THEN
      v_nouveau_montant_ht := v_heures_final * v_taux_final;
    ELSE
      v_nouveau_montant_ht := v_facture.montant_ht;
    END IF;
    v_diff := v_facture.montant_ht - v_nouveau_montant_ht;

    IF v_diff = 0 THEN
      v_action := 'AUCUNE';
    ELSIF v_diff < 0 THEN
      RETURN jsonb_build_object(
        'error',
        'Le nouveau montant (' || v_nouveau_montant_ht || ' €) est supérieur à l''original (' ||
        v_facture.montant_ht || ' €). AVOIR non applicable. Utilisez p_action_financiere=ANNULER_REEMETTRE.'
      );
    ELSE
      SELECT valeur::INT INTO v_delai_stripe_j
        FROM public.parametres_litiges WHERE cle = 'delai_stripe_refund_auto_j';

      IF v_facture.stripe_payment_intent_id IS NOT NULL
         AND v_facture.date_paiement IS NOT NULL
         AND v_facture.date_paiement > CURRENT_DATE - make_interval(days => v_delai_stripe_j) THEN
        v_mode_remboursement := 'AUTO_STRIPE';
      ELSE
        v_mode_remboursement := 'VIREMENT_MANUEL';
      END IF;

      v_avoir_numero := public.next_avoir_number(v_facture.soignant_id);

      INSERT INTO public.factures_honoraires (
        soignant_id, etablissement_id, mission_id,
        numero_facture, montant_ht, montant_tva, montant_ttc,
        taux_tva, exoneration_tva, date_emission, date_echeance,
        statut, mandat_version, type_document, facture_precedente_id,
        statut_litige, litige_id, mode_remboursement, pdf_a_regenerer,
        periode_debut, periode_fin, numero_semaine_iso, annee_iso
      ) VALUES (
        v_facture.soignant_id, v_facture.etablissement_id, v_facture.mission_id,
        v_avoir_numero,
        v_diff,
        v_diff * COALESCE(v_facture.taux_tva, 0) / 100,
        v_diff * (1 + COALESCE(v_facture.taux_tva, 0) / 100),
        v_facture.taux_tva, v_facture.exoneration_tva,
        CURRENT_DATE, CURRENT_DATE,
        'EMISE', v_facture.mandat_version,
        'AVOIR', v_facture.id,
        'LITIGE_RESOLU_AJUSTE', p_litige_id, v_mode_remboursement, TRUE,
        COALESCE(v_facture.periode_debut, CURRENT_DATE),
        COALESCE(v_facture.periode_fin, v_facture.periode_debut, CURRENT_DATE),
        v_facture.numero_semaine_iso, v_facture.annee_iso
      )
      RETURNING id INTO v_avoir_id;

      UPDATE public.factures_honoraires
         SET statut_litige = 'LITIGE_RESOLU_AJUSTE'
       WHERE id = v_facture.id;

      IF v_mode_remboursement = 'AUTO_STRIPE' THEN
        INSERT INTO public.stripe_refunds_queue (
          avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts
        ) VALUES (
          v_avoir_id, v_facture.id, v_facture.stripe_payment_intent_id,
          (v_diff * 100)::INTEGER
        );
      END IF;

      v_regen_request_ids := v_regen_request_ids
        || COALESCE(public.fn_trigger_regen_pdf_immediate(v_avoir_id), 0);
    END IF;
  END IF;

  IF v_facture.id IS NOT NULL
     AND v_action IN ('ANNULER_REEMETTRE', 'AVOIR')
     AND p_ajuster_heures IS NOT NULL
  THEN
    SELECT valeur::INT INTO v_delai_urssaf_j
      FROM public.parametres_litiges WHERE cle = 'delai_notif_urssaf_mois';
    v_delai_urssaf_j := COALESCE(v_delai_urssaf_j, 3) * 30;

    v_age_facture_j := EXTRACT(DAY FROM NOW() - v_facture.date_emission)::INT;
    IF v_age_facture_j > v_delai_urssaf_j THEN
      UPDATE public.missions
         SET regularisation_sociale_requise = TRUE
       WHERE id = v_facture.mission_id;
      v_regul_sociale := TRUE;
    END IF;
  END IF;

  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') THEN
    UPDATE public.missions
       SET commission_a_recalculer = TRUE
     WHERE id = v_litige.mission_id;
  END IF;

  v_nouveau_statut := CASE
    WHEN p_en_faveur_de = 'SOIGNANT'       THEN 'RESOLU_SOIGNANT'
    WHEN p_en_faveur_de = 'ETABLISSEMENT'  THEN 'RESOLU_ETABLISSEMENT'
    ELSE 'RESOLU_ADMIN'
  END;

  UPDATE public.litiges
     SET statut = v_nouveau_statut,
         resolution = trim(p_resolution),
         resolu_par = v_user_id,
         resolu_le = NOW()
   WHERE id = p_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_RESOLUTION',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'action_financiere', v_action,
      'en_faveur_de', p_en_faveur_de,
      'ajuster_heures', p_ajuster_heures,
      'ajuster_taux', p_ajuster_taux,
      'heures_final', v_heures_final,
      'taux_final', v_taux_final,
      'facture_id', v_facture.id,
      'nouvelle_facture_id', v_nouvelle_facture_id,
      'avoir_id', v_avoir_id,
      'mode_remboursement', v_mode_remboursement,
      'regularisation_sociale_requise', v_regul_sociale,
      'regen_pdf_request_ids', to_jsonb(v_regen_request_ids)
    ),
    NULL, NULL
  );

  IF v_action IN ('RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR') AND v_litige.id IS NOT NULL THEN
    v_soignant_id := v_litige.soignant_id;

    v_etab_user_id := v_litige.etablissement_id;

    v_email_data := jsonb_build_object(
      'action_financiere', v_action,
      'en_faveur_de', p_en_faveur_de,
      'resolution', trim(p_resolution),
      'numero_facture', v_facture.numero_facture,
      'numero_ancienne', CASE WHEN v_action = 'ANNULER_REEMETTRE' THEN v_facture.numero_facture ELSE NULL END,
      'numero_nouvelle', v_nouveau_numero_facture,
      'numero_avoir', v_avoir_numero,
      'montant_avant', v_facture.montant_ht,
      'montant_apres', v_nouveau_montant_ht
    );

    IF v_soignant_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_soignant_id,
        'SOIGNANT',
        'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — ajustement appliqué',
        CASE v_action
          WHEN 'AVOIR'             THEN 'Un avoir ' || COALESCE(v_avoir_numero, '') || ' a été émis suite à la résolution du litige.'
          WHEN 'RECALCUL'          THEN 'Votre facture ' || COALESCE(v_facture.numero_facture, '') || ' a été recalculée.'
          WHEN 'ANNULER_REEMETTRE' THEN 'Une nouvelle facture ' || COALESCE(v_nouveau_numero_facture, '') || ' remplace ' || COALESCE(v_facture.numero_facture, '') || '.'
          ELSE                          'Le litige a été résolu avec impact financier.'
        END,
        p_litige_id,
        v_email_data
      );
    END IF;

    IF v_etab_user_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_etab_user_id,
        'ETABLISSEMENT',
        'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — ajustement appliqué',
        CASE v_action
          WHEN 'AVOIR'             THEN 'Un avoir ' || COALESCE(v_avoir_numero, '') || ' a été émis pour cette mission.'
          WHEN 'RECALCUL'          THEN 'La facture ' || COALESCE(v_facture.numero_facture, '') || ' a été recalculée.'
          WHEN 'ANNULER_REEMETTRE' THEN 'Une nouvelle facture ' || COALESCE(v_nouveau_numero_facture, '') || ' remplace ' || COALESCE(v_facture.numero_facture, '') || '.'
          ELSE                          'Le litige a été résolu avec impact financier.'
        END,
        p_litige_id,
        v_email_data
      );
    END IF;

    IF v_action = 'AVOIR' AND v_avoir_id IS NOT NULL AND v_soignant_id IS NOT NULL THEN
      PERFORM public.fn_litige_push_notification(
        v_soignant_id,
        'SOIGNANT',
        'AVOIR_EMIS',
        'Avoir ' || COALESCE(v_avoir_numero, '') || ' émis',
        'Un avoir a été émis suite à la résolution du litige. Le PDF est attaché à cet email.',
        p_litige_id,
        jsonb_build_object(
          'avoir_id', v_avoir_id,
          'numero_avoir', v_avoir_numero,
          'numero_facture_origine', v_facture.numero_facture,
          'montant_avoir', v_diff,
          'mode_remboursement_texte', CASE v_mode_remboursement::text
            WHEN 'AUTO_STRIPE'      THEN 'Remboursement Stripe automatique (2 à 5 jours ouvrés)'
            WHEN 'VIREMENT_MANUEL'  THEN 'Virement manuel sous 7 jours ouvrés'
            ELSE                         'Mode de remboursement à confirmer'
          END
        )
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'action_financiere', v_action,
    'statut', v_nouveau_statut,
    'facture_id', v_facture.id,
    'nouvelle_facture_id', v_nouvelle_facture_id,
    'avoir_id', v_avoir_id,
    'avoir_numero', v_avoir_numero,
    'mode_remboursement', v_mode_remboursement,
    'regularisation_sociale_requise', v_regul_sociale,
    'regen_pdf_request_ids', to_jsonb(v_regen_request_ids),
    'heures_final', v_heures_final,
    'taux_final', v_taux_final
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_traiter_reclamation(p_reclamation_id uuid, p_decision text, p_points_corriges integer, p_motif_admin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rec RECORD;
  v_event_id uuid;
  v_event_type text;
  v_proprio_id uuid;
  v_score jsonb;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_ADMIN');
  END IF;

  IF p_decision NOT IN ('MAINTENIR', 'REDUIRE', 'ANNULER') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DECISION_INVALIDE',
                                'error', 'Décision doit être MAINTENIR, REDUIRE ou ANNULER');
  END IF;

  IF p_motif_admin IS NULL OR length(trim(p_motif_admin)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_ADMIN_REQUIS',
                                'error', 'Motif admin obligatoire (min 10 caractères)');
  END IF;

  IF p_decision = 'REDUIRE' AND (p_points_corriges IS NULL OR p_points_corriges >= 0) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'POINTS_CORRIGES_INVALIDE',
                                'error', 'REDUIRE requiert points_corriges < 0 (ex: -5 au lieu de -10)');
  END IF;

  SELECT * INTO v_rec FROM public.reclamations_score WHERE id = p_reclamation_id;
  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RECLAMATION_INTROUVABLE');
  END IF;

  IF v_rec.statut != 'PENDING' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_TRAITEE',
                                'error', 'Réclamation déjà traitée (statut : ' || v_rec.statut || ')');
  END IF;

  v_event_type := v_rec.evenement_type;
  v_event_id := COALESCE(v_rec.evenement_soignant_id, v_rec.evenement_etab_id);

  -- Mettre à jour la réclamation
  UPDATE public.reclamations_score SET
    statut = 'TREATED',
    decision_admin = p_decision,
    motif_admin = trim(p_motif_admin),
    traitee_par_admin_id = v_uid,
    traitee_le = NOW(),
    modifiee_le = NOW()
  WHERE id = p_reclamation_id;

  -- Propager la décision sur l'événement
  IF v_event_type = 'SOIGNANT' THEN
    UPDATE public.evenements_score_soignant SET
      decision_admin = p_decision,
      points_corriges = CASE WHEN p_decision = 'REDUIRE' THEN p_points_corriges ELSE NULL END,
      motif_admin = trim(p_motif_admin),
      traite_par_admin_id = v_uid,
      traite_le = NOW()
    WHERE id = v_event_id
    RETURNING soignant_id INTO v_proprio_id;

    -- Recalcul score auto
    v_score := public.fn_calculer_score_soignant(v_proprio_id);
  ELSE
    UPDATE public.evenements_score_etab SET
      decision_admin = p_decision,
      points_corriges = CASE WHEN p_decision = 'REDUIRE' THEN p_points_corriges ELSE NULL END,
      motif_admin = trim(p_motif_admin),
      traite_par_admin_id = v_uid,
      traite_le = NOW()
    WHERE id = v_event_id
    RETURNING etablissement_id INTO v_proprio_id;

    v_score := public.fn_calculer_score_etab(v_proprio_id);
  END IF;

  -- Notification user (email + push) avec décision et motif
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('EMAIL_NOTIF', jsonb_build_object(
      'destinataire_id', v_rec.contesteur_id,
      'type', 'RECLAMATION_SCORE_DECISION',
      'data', jsonb_build_object(
        'reclamation_id', p_reclamation_id,
        'decision', p_decision,
        'motif_admin', p_motif_admin,
        'points_corriges', p_points_corriges,
        'nouveau_score', (v_score->>'score_total')::int
      )
    ), 'AUTRE', p_reclamation_id),
    ('PUSH_NOTIF', jsonb_build_object(
      'destinataire_id', v_rec.contesteur_id,
      'type_evenement', 'RECLAMATION_SCORE_DECISION',
      'titre', CASE p_decision
        WHEN 'ANNULER' THEN 'Réclamation acceptée ✅'
        WHEN 'REDUIRE' THEN 'Réclamation partiellement acceptée'
        ELSE 'Réclamation examinée'
      END,
      'corps', 'Votre score a été mis à jour. Consultez votre profil pour le détail.'
    ), 'AUTRE', p_reclamation_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'reclamation_score', p_reclamation_id,
    jsonb_build_object(
      'evenement', 'RECLAMATION_SCORE_TRAITEE',
      'decision', p_decision,
      'points_corriges', p_points_corriges,
      'motif_admin', p_motif_admin,
      'event_id', v_event_id, 'event_type', v_event_type,
      'nouveau_score', v_score
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'reclamation_id', p_reclamation_id,
    'decision', p_decision,
    'event_id', v_event_id,
    'nouveau_score', v_score
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_toggle_template_contrat(p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ancien_statut boolean;
  v_nouveau_statut boolean;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT est_actif INTO v_ancien_statut FROM public.templates_contrat WHERE id = p_template_id;
  IF v_ancien_statut IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEMPLATE_INTROUVABLE');
  END IF;

  v_nouveau_statut := NOT v_ancien_statut;

  UPDATE public.templates_contrat
  SET est_actif = v_nouveau_statut, modifie_le = now()
  WHERE id = p_template_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'template_contrat', p_template_id,
    jsonb_build_object(
      'evenement', CASE WHEN v_nouveau_statut THEN 'TEMPLATE_CONTRAT_ACTIVE' ELSE 'TEMPLATE_CONTRAT_DESACTIVE' END,
      'ancien_statut', v_ancien_statut,
      'nouveau_statut', v_nouveau_statut
    )
  );

  RETURN jsonb_build_object('success', true, 'est_actif', v_nouveau_statut);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_resume_alertes_pointage()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_kpi jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT jsonb_build_object(
    -- Périodes : 24h / 7j / 30j pour chaque type d'alerte
    'teleportations_24h', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '24 hours'),
    'teleportations_7j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '7 days'),
    'teleportations_30j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '30 days'),

    'mock_gps_24h', (SELECT COUNT(*) FROM public.presences
        WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
          AND modifie_le > NOW() - INTERVAL '24 hours'),
    'mock_gps_7j', (SELECT COUNT(*) FROM public.presences
        WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
          AND modifie_le > NOW() - INTERVAL '7 days'),
    'mock_gps_30j', (SELECT COUNT(*) FROM public.presences
        WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
          AND modifie_le > NOW() - INTERVAL '30 days'),

    'coherence_24h', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '24 hours'),
    'coherence_7j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '7 days'),
    'coherence_30j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '30 days'),

    'qr_gps_eloigne_24h', (SELECT COUNT(*) FROM public.journaux_audit
        WHERE action = 'POINTAGE' AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
          AND cree_le > NOW() - INTERVAL '24 hours'),
    'qr_gps_eloigne_7j', (SELECT COUNT(*) FROM public.journaux_audit
        WHERE action = 'POINTAGE' AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
          AND cree_le > NOW() - INTERVAL '7 days'),
    'qr_gps_eloigne_30j', (SELECT COUNT(*) FROM public.journaux_audit
        WHERE action = 'POINTAGE' AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
          AND cree_le > NOW() - INTERVAL '30 days'),

    'total_ouvertes', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE resolu_le IS NULL
          AND type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT'))
  ) INTO v_kpi;

  RETURN jsonb_build_object('success', true, 'kpis', v_kpi);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_traiter_alerte_pointage(p_alerte_id uuid, p_decision text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_alerte RECORD;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF p_decision NOT IN ('LEGITIME', 'FRAUDE_AVERTISSEMENT', 'FRAUDE_SUSPENSION_PROPOSEE', 'IGNORER') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DECISION_INVALIDE');
  END IF;

  SELECT * INTO v_alerte FROM public.alertes_systeme WHERE id = p_alerte_id;
  IF v_alerte IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ALERTE_INTROUVABLE');
  END IF;

  UPDATE public.alertes_systeme
  SET resolu_le = now(),
      details = COALESCE(details, '{}'::jsonb) || jsonb_build_object(
        'decision_admin', p_decision,
        'motif_admin', p_motif,
        'traite_par', v_uid,
        'traite_le', now()
      )
  WHERE id = p_alerte_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'alerte_systeme', p_alerte_id,
    jsonb_build_object(
      'evenement', 'ALERTE_POINTAGE_TRAITEE',
      'decision', p_decision,
      'motif', p_motif,
      'type_alerte', v_alerte.type_alerte
    )
  );

  RETURN jsonb_build_object('success', true, 'decision', p_decision);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_supprimer_compte_test(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := lower(trim(p_email));
  v_id uuid;
  v_rpps text;
  v_nb_soignant int := 0;
  v_nb_auth int := 0;
BEGIN
  -- Autorisé : admin authentifié OU contexte service_role / éditeur SQL (auth.uid() NULL).
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Réservé à l''administrateur.');
  END IF;

  SELECT id, numero_rpps INTO v_id, v_rpps FROM soignants WHERE lower(email) = v_email;

  -- Supprime la ligne soignant (libère le RPPS via l'unicité) puis le compte auth (libère l'email).
  DELETE FROM soignants WHERE lower(email) = v_email;
  GET DIAGNOSTICS v_nb_soignant = ROW_COUNT;

  DELETE FROM auth.users WHERE lower(email) = v_email;
  GET DIAGNOSTICS v_nb_auth = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'email', v_email,
    'soignant_id', v_id,
    'rpps_libere', v_rpps,
    'lignes_soignant_supprimees', v_nb_soignant,
    'comptes_auth_supprimes', v_nb_auth
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_valider_etablissement(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_etab RECORD;
BEGIN
    IF NOT est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement'); END IF;
    SELECT id, nom, statut_verification, siret_verifie, contrat_valide
    INTO v_etab FROM etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;
    IF v_etab IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    IF v_etab.statut_verification = 'VERIFIE' THEN RETURN jsonb_build_object('error', 'Cet établissement est déjà vérifié'); END IF;
    UPDATE etablissements SET
        statut_verification = 'VERIFIE', peut_publier_missions = TRUE,
        verifie_le = NOW(), verifie_par = auth.uid(),
        finess_verifie = TRUE, finess_verifie_le = COALESCE(finess_verifie_le, NOW()),
        rattachement_methode = 'ADMIN', rattachement_verifie = TRUE, rattachement_verifie_le = NOW()
    WHERE id = p_etablissement_id;
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'ADMIN_ACTION', 'etablissement', p_etablissement_id,
        jsonb_build_object('sous_action', 'VALIDATION_ETABLISSEMENT', 'nom', v_etab.nom, 'rattachement', 'ADMIN'));
    RETURN jsonb_build_object('success', true, 'nom', v_etab.nom);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_valider_contrat_etablissement(p_etablissement_id uuid, p_valider boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    UPDATE etablissements SET
        contrat_valide = p_valider
    WHERE id = p_etablissement_id;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, ressource_id, details)
    VALUES (auth.uid(), 'ADMIN', CASE WHEN p_valider THEN 'VALIDATION_CONTRAT' ELSE 'INVALIDATION_CONTRAT' END, 
        'ETABLISSEMENT', p_etablissement_id, jsonb_build_object('valide', p_valider));

    RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_ajouter_jours_ouvres(p_date timestamp with time zone, p_nb_jours integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_local  TIMESTAMP;
  v_count  INTEGER := 0;
  v_step   INTEGER := CASE WHEN p_nb_jours >= 0 THEN 1 ELSE -1 END;
  v_target INTEGER := abs(p_nb_jours);
  v_dow    INTEGER;
  v_is_feried BOOLEAN;
BEGIN
  v_local := p_date AT TIME ZONE 'Europe/Paris';

  IF v_target = 0 THEN
    RETURN v_local AT TIME ZONE 'Europe/Paris';
  END IF;

  WHILE v_count < v_target LOOP
    v_local := v_local + (v_step || ' day')::INTERVAL;
    v_dow := EXTRACT(DOW FROM v_local)::INTEGER;
    IF v_dow IN (0, 6) THEN
      CONTINUE;
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM public.jours_feries_fr
      WHERE date_ferie = v_local::DATE
    ) INTO v_is_feried;
    IF v_is_feried THEN
      CONTINUE;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_local AT TIME ZONE 'Europe/Paris';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_trancher_litige(p_litige_id uuid, p_decision text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_litige RECORD;
  v_decision_clean TEXT;
  v_statut_final TEXT;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seul l''administrateur peut trancher');
  END IF;

  v_decision_clean := UPPER(TRIM(p_decision));
  IF v_decision_clean NOT IN ('FAVEUR_SOIGNANT','FAVEUR_ETAB','PARTAGE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Décision invalide (FAVEUR_SOIGNANT/FAVEUR_ETAB/PARTAGE)');
  END IF;

  v_statut_final := 'RESOLU_' || v_decision_clean;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  UPDATE litiges SET statut = v_statut_final, resolution = p_motif, resolu_par = v_uid, resolu_le = NOW()
  WHERE id = p_litige_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES
    (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
     CASE v_decision_clean
       WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en votre faveur ✅'
       WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en faveur de l''établissement'
       ELSE 'Litige tranché : décision partagée'
     END,
     COALESCE(p_motif, 'L''administrateur a tranché.'),
     '/soignant/litiges'),
    (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
     CASE v_decision_clean
       WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en faveur du soignant'
       WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en votre faveur ✅'
       ELSE 'Litige tranché : décision partagée'
     END,
     COALESCE(p_motif, 'L''administrateur a tranché.'),
     '/etablissement/litiges');

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_ADMIN_TRANCHE',
    p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('decision', v_decision_clean, 'statut_final', v_statut_final, 'motif', p_motif)
  );

  RETURN jsonb_build_object('success', true, 'statut_final', v_statut_final);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_valider_heures_externes(p_id uuid, p_decision text, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ligne public.heures_externes_soignants%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  IF p_decision NOT IN ('VALIDE', 'REJETE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Décision invalide (VALIDE ou REJETE)');
  END IF;

  IF p_decision = 'REJETE' AND COALESCE(length(trim(p_commentaire)), 0) < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Motif requis pour un rejet (min 5 caractères)');
  END IF;

  SELECT * INTO v_ligne FROM public.heures_externes_soignants WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Déclaration introuvable');
  END IF;

  UPDATE public.heures_externes_soignants
     SET statut_validation = p_decision,
         commentaire_validation = COALESCE(NULLIF(trim(p_commentaire), ''), commentaire_validation),
         valide_par = v_uid,
         valide_le = NOW(),
         mis_a_jour_le = NOW()
   WHERE id = p_id;

  BEGIN
    PERFORM public.fn_ecrire_audit_safe(
      v_uid, 'ADMIN', 'HEURES_EXTERNES_VALIDATION_MANUELLE',
      'heures_externes_soignants', p_id, v_ligne.attestation_url,
      jsonb_build_object(
        'decision', p_decision,
        'soignant_id', v_ligne.soignant_id,
        'heures_declarees', v_ligne.heures_declarees,
        'heures_extraites_ia', v_ligne.heures_extraites_ia,
        'commentaire', p_commentaire
      ),
      NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'statut', p_decision);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_triage_scores()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
  END IF;

  SELECT jsonb_build_object('success', true, 'lignes', COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.score ASC), '[]'::jsonb))
  INTO v
  FROM (
    SELECT s.id AS user_id,
           'SOIGNANT' AS type,
           NULLIF(btrim(COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '')), '') AS nom,
           COALESCE(s.email, '') AS email,
           COALESCE(s.score_fiabilite, 0)::numeric AS score
    FROM public.soignants s
    WHERE s.supprime_le IS NULL
    UNION ALL
    SELECT e.id,
           'ETAB',
           NULLIF(btrim(COALESCE(e.nom, '')), '') AS nom,
           COALESCE(e.email_contact, '') AS email,
           COALESCE(e.score_qualite, 0)::numeric AS score
    FROM public.etablissements e
    WHERE e.supprime_le IS NULL
  ) x;

  RETURN v;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_traiter_signalement(p_id uuid, p_statut text, p_resolution text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Admin requis'); END IF;
  IF p_statut NOT IN ('OUVERT','EN_COURS','TRAITE','REJETE') THEN RETURN jsonb_build_object('success', false, 'error', 'Statut invalide'); END IF;
  UPDATE public.signalements SET statut = p_statut, resolution = p_resolution, traite_par = auth.uid(),
    traite_le = CASE WHEN p_statut IN ('TRAITE','REJETE') THEN now() ELSE traite_le END WHERE id = p_id;
  RETURN jsonb_build_object('success', true);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_valider_accord_litige(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige RECORD;
  v_exec jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;
  IF v_litige.payload_modifications IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun accord à valider sur ce litige');
  END IF;

  UPDATE public.litiges SET
    statut = 'RESOLU_ADMIN',
    resolu_le = COALESCE(resolu_le, NOW()),
    resolu_par = v_uid
  WHERE id = p_litige_id;

  PERFORM set_config('jolene.litige_exec_ok', 'true', true);
  v_exec := public.fn_executer_modifications_litige(p_litige_id);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_ACCORD_VALIDE_ADMIN', p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('execution', v_exec));

  RETURN jsonb_build_object('success', true, 'statut', 'RESOLU_ADMIN', 'execution', v_exec);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_alerte_cddu_repetitif(p_soignant_id uuid, p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_jours INTEGER;
BEGIN
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : alerte réservée à l''établissement' USING ERRCODE = '42501';
    END IF;

    SELECT COUNT(DISTINCT debut_le::DATE) INTO v_jours
    FROM missions
    WHERE soignant_assigne_id = p_soignant_id
      AND etablissement_id = p_etablissement_id
      AND statut = 'TERMINEE'
      AND debut_le > NOW() - INTERVAL '365 days';

    RETURN jsonb_build_object(
        'jours_12_mois', v_jours,
        'alerte', v_jours > 150,
        'message', CASE
            WHEN v_jours > 150 THEN 'Risque de requalification en CDI — ' || v_jours || ' jours travaillés sur 12 mois'
            ELSE NULL
        END
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_ajouter_message_litige(p_litige_id uuid, p_contenu text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_litige RECORD;
    v_type_auteur TEXT;
    v_destinataire_id UUID;
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.statut = 'CLOTURE' THEN
        RETURN jsonb_build_object('error', 'Ce litige est clôturé.');
    END IF;
    
    -- Déterminer qui écrit
    IF auth.uid() = v_litige.soignant_id THEN
        v_type_auteur := 'SOIGNANT';
        v_destinataire_id := v_litige.etablissement_id;
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
        v_type_auteur := 'ETABLISSEMENT';
        v_destinataire_id := v_litige.soignant_id;
    ELSIF est_admin() THEN
        v_type_auteur := 'ADMIN';
        v_destinataire_id := v_litige.soignant_id; -- notifier les 2
    ELSE
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    IF LENGTH(TRIM(p_contenu)) < 1 OR LENGTH(p_contenu) > 5000 THEN
        RETURN jsonb_build_object('error', 'Le message doit contenir entre 1 et 5000 caractères.');
    END IF;
    
    INSERT INTO messages_litige (litige_id, auteur_id, type_auteur, contenu)
    VALUES (p_litige_id, auth.uid(), v_type_auteur, fn_html_escape(p_contenu));
    
    -- Notifier l'autre partie
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_destinataire_id, 'SYSTEM', 'Nouveau message sur le litige',
        'Un message a été ajouté au litige concernant la mission.',
        CASE WHEN v_type_auteur = 'SOIGNANT' THEN '/etablissement/missions/' || v_litige.mission_id
             ELSE '/soignant/mes-missions/' || v_litige.mission_id END,
        CASE WHEN v_type_auteur = 'SOIGNANT' THEN 'ETABLISSEMENT' ELSE 'SOIGNANT' END);
    
    RETURN jsonb_build_object('success', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_analytics_etablissement(p_etablissement_id uuid, p_mois integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_debut DATE;
  v_result JSONB;
  v_taux_remplissage NUMERIC;
  v_cout_heure_moyen NUMERIC;
  v_turnover NUMERIC;
  v_missions_par_mois JSONB;
  v_top_professions JSONB;
  v_soignants_recurrents JSONB;
BEGIN
  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
    RETURN jsonb_build_object('error', 'Accès refusé : analytics réservées au propriétaire de l''établissement');
  END IF;

  v_debut := (CURRENT_DATE - (p_mois || ' months')::INTERVAL)::DATE;

  SELECT ROUND(COALESCE(
    COUNT(*) FILTER(WHERE soignant_assigne_id IS NOT NULL) * 100.0 / NULLIF(COUNT(*), 0)
  , 0), 1) INTO v_taux_remplissage
  FROM missions WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut;

  SELECT ROUND(COALESCE(AVG(CASE WHEN duree_heures > 0 THEN total_brut / duree_heures END), 0), 2) INTO v_cout_heure_moyen
  FROM missions WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND debut_le >= v_debut;

  SELECT ROUND(COALESCE(
    COUNT(DISTINCT soignant_assigne_id) FILTER(WHERE statut = 'TERMINEE') * 1.0 / NULLIF(COUNT(*) FILTER(WHERE statut = 'TERMINEE'), 0)
  , 0), 2) INTO v_turnover
  FROM missions WHERE etablissement_id = p_etablissement_id AND debut_le >= v_debut;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', mois, 'total', total, 'terminees', terminees, 'gmv', gmv
  ) ORDER BY mois), '[]'::jsonb) INTO v_missions_par_mois
  FROM (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS mois,
      COUNT(*) AS total,
      COUNT(*) FILTER(WHERE statut = 'TERMINEE') AS terminees,
      ROUND(COALESCE(SUM(total_brut) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS gmv
    FROM missions WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('profession', profession, 'nb', nb)), '[]'::jsonb) INTO v_top_professions
  FROM (
    SELECT profession_requise AS profession, COUNT(*) AS nb FROM missions
    WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut
    GROUP BY profession_requise ORDER BY nb DESC LIMIT 10
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('soignant_id', soignant_id, 'nb_missions', nb_missions)), '[]'::jsonb) INTO v_soignants_recurrents
  FROM (
    SELECT soignant_assigne_id AS soignant_id, COUNT(*) AS nb_missions FROM missions
    WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND debut_le >= v_debut
      AND soignant_assigne_id IS NOT NULL
    GROUP BY soignant_assigne_id HAVING COUNT(*) > 1 ORDER BY nb_missions DESC LIMIT 10
  ) sub;

  v_result := jsonb_build_object(
    'taux_remplissage', v_taux_remplissage, 'cout_heure_moyen', v_cout_heure_moyen,
    'turnover', v_turnover, 'missions_par_mois', v_missions_par_mois,
    'top_professions', v_top_professions, 'soignants_recurrents', v_soignants_recurrents
  );
  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_alerter_mediation_prioritaire()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_delai_j INT;
  v_nb_alertes INT := 0;
  v_litige RECORD;
  v_admin_id UUID;
BEGIN
  SELECT valeur::INT INTO v_delai_j
    FROM public.parametres_litiges WHERE cle = 'delai_mediation_alerte_prioritaire_j';

  FOR v_litige IN
    SELECT id, mission_id, type_litige, escalade_auto_le
      FROM public.litiges
     WHERE statut = 'EN_MEDIATION'
       AND escalade_auto_le IS NOT NULL
       AND escalade_auto_le < NOW() - make_interval(days => v_delai_j)
       AND NOT (derniers_rappels_envoyes ? 'MEDIATION_7J')
  LOOP
    FOR v_admin_id IN SELECT * FROM public.fn_list_admin_user_ids()
    LOOP
      PERFORM public.fn_litige_push_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_MEDIATION_PRIORITAIRE',
        'Litige en médiation depuis > ' || v_delai_j || ' jours',
        'Le litige ' || v_litige.type_litige || ' sur mission '
          || v_litige.mission_id::text
          || ' est en médiation sans action admin depuis plus de '
          || v_delai_j || ' jours.',
        v_litige.id,
        jsonb_build_object(
          'type_litige', v_litige.type_litige,
          'mission_id', v_litige.mission_id,
          'jours_depuis_escalade', v_delai_j,
          'prioritaire', TRUE
        )
      );
    END LOOP;

    UPDATE public.litiges
       SET derniers_rappels_envoyes = derniers_rappels_envoyes
         || jsonb_build_object('MEDIATION_7J', NOW())
     WHERE id = v_litige.id;

    v_nb_alertes := v_nb_alertes + 1;
  END LOOP;

  RETURN jsonb_build_object('alertes_mediation', v_nb_alertes);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_alerter_paiements_retard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_facture RECORD;
    v_montant_estime NUMERIC;
    v_count_emails INT := 0;
    v_count_missions_j7 INT := 0;
    v_count_missions_j21 INT := 0;
    v_count_factures_j7 INT := 0;
    v_count_factures_j21 INT := 0;
BEGIN
    FOR v_mission IN
        SELECT m.id, m.intitule, m.fin_le, m.net_a_payer, m.total_brut,
               m.relance_paiement_1_le, m.relance_paiement_2_le,
               m.soignant_assigne_id, m.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email,
               COALESCE(s.prenom, '') AS soignant_prenom,
               COALESCE(s.nom, '') AS soignant_nom
        FROM public.missions m
        JOIN public.etablissements e ON e.id = m.etablissement_id
        LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.statut = 'TERMINEE'
        AND m.type_contrat_applique = 'SALARIE'
        AND m.fin_le IS NOT NULL
        AND m.soignant_assigne_id IS NOT NULL
        AND (m.relance_paiement_1_le IS NULL OR m.relance_paiement_2_le IS NULL)
        AND NOT EXISTS (
            SELECT 1 FROM public.paiements_soignant ps
            WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME')
        )
    LOOP
        v_montant_estime := COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0);

        IF v_mission.fin_le + INTERVAL '7 days' <= NOW()
           AND v_mission.relance_paiement_1_le IS NULL THEN

            IF v_mission.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_mission.etablissement_id, v_mission.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'PAIEMENT_SOIGNANT',
                        'mission_id', v_mission.id,
                        'mission_intitule', v_mission.intitule,
                        'soignant_prenom', v_mission.soignant_prenom,
                        'soignant_nom', v_mission.soignant_nom,
                        'montant_estime', ROUND(v_montant_estime, 2),
                        'date_fin_mission', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_mission.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Rappel paiement soignant',
                'Rappel : paiement de ' || v_montant_estime || ' EUR a declarer pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || ').',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_1_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j7 := v_count_missions_j7 + 1;
        END IF;

        IF v_mission.fin_le + INTERVAL '21 days' <= NOW()
           AND v_mission.relance_paiement_2_le IS NULL THEN

            IF v_mission.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_mission.etablissement_id, v_mission.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'PAIEMENT_SOIGNANT',
                        'mission_id', v_mission.id,
                        'mission_intitule', v_mission.intitule,
                        'soignant_prenom', v_mission.soignant_prenom,
                        'soignant_nom', v_mission.soignant_nom,
                        'montant_estime', ROUND(v_montant_estime, 2),
                        'date_fin_mission', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_mission.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Paiement en retard (21 jours)',
                'Paiement de ' || v_montant_estime || ' EUR toujours non declare pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || '). Sans regularisation sous 24 jours la publication de nouvelles missions sera suspendue.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_2_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j21 := v_count_missions_j21 + 1;
        END IF;
    END LOOP;

    FOR v_facture IN
        SELECT f.id, f.numero_facture, f.montant_ttc, f.date_emission,
               f.relance_1_le, f.relance_2_le, f.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email
        FROM public.factures f
        JOIN public.etablissements e ON e.id = f.etablissement_id
        WHERE f.statut IN ('EMISE', 'EN_RETARD')
        AND f.date_emission IS NOT NULL
        AND (f.relance_1_le IS NULL OR f.relance_2_le IS NULL)
    LOOP
        IF v_facture.date_emission + INTERVAL '7 days' <= NOW()
           AND v_facture.relance_1_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Rappel facture commission',
                'Rappel : facture ' || COALESCE(v_facture.numero_facture, '-') || ' de ' || v_facture.montant_ttc || ' EUR en attente de reglement.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_1_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j7 := v_count_factures_j7 + 1;
        END IF;

        IF v_facture.date_emission + INTERVAL '21 days' <= NOW()
           AND v_facture.relance_2_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Facture en retard (21 jours)',
                'Facture ' || COALESCE(v_facture.numero_facture, '-') || ' de ' || v_facture.montant_ttc || ' EUR toujours impayee. Sans regularisation sous 24 jours la publication de nouvelles missions sera suspendue.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_2_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j21 := v_count_factures_j21 + 1;
        END IF;
    END LOOP;

    FOR v_mission IN
        SELECT p.id AS paiement_id, p.soignant_id, p.mission_id, p.montant_net,
               m.intitule, e.nom AS etab_nom
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.etablissements e ON e.id = p.etablissement_id
        WHERE p.statut = 'DECLARE'
        AND p.confirme_par_soignant = FALSE
        AND p.cree_le < NOW() - INTERVAL '15 days'
        AND p.relance_1_le IS NULL
    LOOP
        UPDATE public.paiements_soignant SET relance_1_le = NOW() WHERE id = v_mission.paiement_id;

        INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.soignant_id, 'SYSTEM',
            'Rappel : confirmez la reception du paiement',
            'L etablissement "' || COALESCE(v_mission.etab_nom, 'Etablissement') || '" a declare vous avoir paye ' || v_mission.montant_net || ' EUR pour "' || COALESCE(v_mission.intitule, 'Mission') || '". Merci de confirmer ou contester.',
            '/soignant/mes-gains', 'SOIGNANT');
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'emails_queued', v_count_emails,
        'missions_j7', v_count_missions_j7,
        'missions_j21', v_count_missions_j21,
        'factures_j7', v_count_factures_j7,
        'factures_j21', v_count_factures_j21
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_alertes_dashboard_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID;
  v_missions_orphelines JSONB;
  v_contrats_a_uploader JSONB;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
  END IF;

  -- Missions OUVERTE > 48h sans aucune candidature, début à venir
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'profession_requise', m.profession_requise::text,
    'debut_le', m.debut_le,
    'cree_le', m.cree_le,
    'taux_horaire_base', m.taux_horaire_base,
    'est_urgente', COALESCE(m.est_urgente, false),
    'jours_sans_candidature', EXTRACT(EPOCH FROM (NOW() - m.cree_le)) / 86400.0
  ) ORDER BY m.debut_le ASC), '[]'::jsonb)
  INTO v_missions_orphelines
  FROM missions m
  WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
    AND m.statut = 'OUVERTE'
    AND m.cree_le < NOW() - INTERVAL '48 hours'
    AND m.debut_le > NOW()
    AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id);

  -- Missions SALARIE J-1 sans contrat travail uploadé (étab-scope)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'debut_le', m.debut_le,
    'soignant_prenom', s.prenom,
    'soignant_nom_initiale', LEFT(s.nom, 1) || '.',
    'heures_avant_debut', ROUND((EXTRACT(EPOCH FROM (m.debut_le - NOW())) / 3600.0)::numeric, 1)
  ) ORDER BY m.debut_le ASC), '[]'::jsonb)
  INTO v_contrats_a_uploader
  FROM missions m
  JOIN soignants s ON s.id = m.soignant_assigne_id
  WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
    AND m.statut IN ('ASSIGNEE','EN_COURS')
    AND m.type_contrat_applique = 'SALARIE'
    AND m.debut_le >= NOW()
    AND m.debut_le < NOW() + INTERVAL '48 hours'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM contrats_travail_missions ct WHERE ct.mission_id = m.id);

  RETURN jsonb_build_object(
    'missions_sans_candidature_48h', v_missions_orphelines,
    'contrats_travail_a_uploader', v_contrats_a_uploader,
    'count_total',
      jsonb_array_length(v_missions_orphelines) + jsonb_array_length(v_contrats_a_uploader)
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_candidature_soignant(p_candidature_id uuid, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_candidature RECORD;
  v_mission RECORD;
  v_contrat RECORD;
  v_penalite jsonb;
  v_event_id uuid;
  v_points int;
  v_motif_event text;
  v_signalement boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  IF p_motif_categorie IS NULL OR p_motif_categorie NOT IN (
    'URGENCE_PERSONNELLE', 'URGENCE_MEDICALE', 'DEUIL',
    'PROBLEME_TRANSPORT', 'CHANGEMENT_AVIS', 'AUTRE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif requis (URGENCE_PERSONNELLE, URGENCE_MEDICALE, DEUIL, PROBLEME_TRANSPORT, CHANGEMENT_AVIS, AUTRE)');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 10 caractères)');
  END IF;

  SELECT * INTO v_candidature FROM public.candidatures WHERE id = p_candidature_id;
  IF v_candidature IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CANDIDATURE_INTROUVABLE', 'error', 'Candidature introuvable');
  END IF;

  IF v_candidature.soignant_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas le soignant de cette candidature');
  END IF;

  IF v_candidature.statut NOT IN ('ACCEPTEE', 'EN_ATTENTE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'STATUT_INVALIDE',
                                'error', 'Candidature pas dans un état annulable (statut : ' || v_candidature.statut || ')');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_candidature.mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE', 'error', 'Mission introuvable');
  END IF;

  PERFORM set_config('jolene.annulation_soignant_ctx', 'true', true);

  IF v_candidature.statut = 'EN_ATTENTE' THEN
    UPDATE public.candidatures SET
      statut = 'ANNULEE',
      traite_le = NOW(),
      motif_refus = p_texte_libre
    WHERE id = p_candidature_id;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      v_uid, 'SOIGNANT', 'SYSTEM', 'candidature', p_candidature_id,
      jsonb_build_object('evenement', 'CANDIDATURE_ANNULEE_PAR_SOIGNANT',
                          'motif_categorie', p_motif_categorie,
                          'texte_libre', p_texte_libre,
                          'libre', true,
                          'statut_initial', v_candidature.statut)
    );

    RETURN jsonb_build_object('success', true, 'libre', true, 'points', 0,
                                'message', 'Candidature retirée sans impact');
  END IF;

  v_penalite := public.fn_calculer_penalite_annulation_soignant(
    v_candidature.acceptee_a, v_mission.debut_le, v_mission.est_asap
  );

  v_points := (v_penalite->>'points')::int;
  v_motif_event := v_penalite->>'motif';
  v_signalement := COALESCE((v_penalite->>'signalement_admin')::boolean, false);

  UPDATE public.candidatures SET
    statut = 'ANNULEE',
    traite_le = NOW(),
    motif_refus = p_motif_categorie || ' : ' || p_texte_libre
  WHERE id = p_candidature_id;

  UPDATE public.missions SET
    statut = 'OUVERTE',
    soignant_assigne_id = NULL,
    modifie_le = NOW()
  WHERE id = v_candidature.mission_id AND statut IN ('ASSIGNEE', 'EN_COURS');

  SELECT * INTO v_contrat FROM public.contrats_mission
  WHERE mission_id = v_candidature.mission_id LIMIT 1;
  IF FOUND THEN
    UPDATE public.contrats_mission SET
      statut = 'RUPTURE_SOIGNANT',
      modifie_le = NOW()
    WHERE id = v_contrat.id;

    IF v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')
       AND v_contrat.statut = 'SIGNE_COMPLET' THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      VALUES ('DPAE_ANNULATION',
              jsonb_build_object('contrat_id', v_contrat.id, 'mission_id', v_candidature.mission_id,
                                  'motif', 'ANNULATION_SOIGNANT', 'echeance_legale_h', 48),
              'ANNULATION_MISSION', p_candidature_id);
    END IF;
  END IF;

  IF v_points < 0 THEN
    INSERT INTO public.evenements_score_soignant (
      soignant_id, type_evenement, points, motif, contestable,
      mission_id, candidature_id, justificatif_storage_path,
      details
    ) VALUES (
      v_uid, v_motif_event, v_points,
      p_motif_categorie || ' : ' || left(p_texte_libre, 200),
      true,
      v_candidature.mission_id, p_candidature_id, p_justificatif_storage_path,
      jsonb_build_object(
        'motif_categorie', p_motif_categorie,
        'texte_libre', p_texte_libre,
        'delta_mission_h', EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 3600,
        'delta_retract_min', EXTRACT(EPOCH FROM (NOW() - v_candidature.acceptee_a)) / 60,
        'est_asap', v_mission.est_asap,
        'signalement_admin', v_signalement
      )
    ) RETURNING id INTO v_event_id;

    IF v_signalement THEN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_uid, 'SOIGNANT', 'SYSTEM', 'soignant', v_uid,
        jsonb_build_object('evenement', 'ALERTE_ADMIN_NO_SHOW',
                            'mission_id', v_candidature.mission_id,
                            'event_score_id', v_event_id,
                            'motif_categorie', p_motif_categorie,
                            'action_requise', 'REVISION_MANUELLE_ADMIN')
      );
    END IF;
  END IF;

  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('EMAIL_NOTIF', jsonb_build_object(
      'destinataire_id', v_mission.etablissement_id,
      'type', 'CANDIDATURE_ANNULEE_SOIGNANT',
      'data', jsonb_build_object(
        'mission_id', v_mission.id,
        'motif_categorie', p_motif_categorie,
        'libre', v_points = 0
      )
    ), 'ANNULATION_MISSION', p_candidature_id),
    ('PUSH_NOTIF', jsonb_build_object(
      'destinataire_id', v_mission.etablissement_id,
      'type_evenement', 'CANDIDATURE_ANNULEE_SOIGNANT',
      'titre', 'Le soignant a annulé',
      'corps', 'La mission est de nouveau disponible. Notifications envoyées aux soignants matching.'
    ), 'ANNULATION_MISSION', p_candidature_id);

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'candidature', p_candidature_id,
    jsonb_build_object(
      'evenement', 'CANDIDATURE_ANNULEE_PAR_SOIGNANT',
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'points', v_points,
      'motif_score', v_motif_event,
      'event_score_id', v_event_id,
      'mission_id', v_mission.id,
      'signalement_admin', v_signalement
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'libre', v_points = 0,
    'points', v_points,
    'motif_score', v_motif_event,
    'event_score_id', v_event_id,
    'contestable', v_points < 0,
    'signalement_admin', v_signalement
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_alerte_reclamations_pending_old()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int; v_liste jsonb; v_admin_ids uuid[];
BEGIN
  SELECT COUNT(*), jsonb_agg(jsonb_build_object(
    'id', id, 'evenement_type', evenement_type, 'contesteur_id', contesteur_id,
    'motif_categorie', motif_categorie, 'texte_libre', LEFT(texte_libre, 100),
    'cree_le', cree_le, 'jours_attente', EXTRACT(EPOCH FROM (NOW() - cree_le)) / 86400
  ) ORDER BY cree_le ASC) INTO v_count, v_liste
  FROM public.reclamations_score
  WHERE statut = 'PENDING' AND cree_le < NOW() - INTERVAL '14 days';
  IF v_count = 0 THEN RETURN jsonb_build_object('success', true, 'count', 0); END IF;
  v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());
  IF array_length(v_admin_ids, 1) > 0 THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    SELECT 'EMAIL_NOTIF', jsonb_build_object('destinataire_id', uid, 'type', 'ALERTE_RECLAMATIONS_PENDING',
      'data', jsonb_build_object('count', v_count, 'liste', v_liste,
        'lien_admin', 'https://app.jolene.app/admin/reclamations-score')),
      'CRON_ALERTE_ADMIN', NULL FROM unnest(v_admin_ids) AS uid;
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    SELECT 'PUSH_NOTIF', jsonb_build_object('destinataire_id', uid, 'type_evenement', 'ALERTE_ADMIN',
      'titre', '⚠️ ' || v_count || ' réclamation' || CASE WHEN v_count > 1 THEN 's' ELSE '' END || ' en attente > 14j',
      'corps', 'Examen requis.', 'lien', '/admin/reclamations-score'),
      'CRON_ALERTE_ADMIN', NULL FROM unnest(v_admin_ids) AS uid;
  END IF;
  RETURN jsonb_build_object('success', true, 'count', v_count, 'admins_notifies', array_length(v_admin_ids, 1));
END; $function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_serie(p_serie_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    IF NOT est_admin_etablissement() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    UPDATE missions SET
        statut = 'ANNULEE_PAR_ETABLISSEMENT',
        modifie_le = NOW()
    WHERE serie_id = p_serie_id
      AND statut IN ('OUVERTE', 'ASSIGNEE')
      AND (etablissement_id = mon_etablissement_id() OR est_admin());

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN jsonb_build_object('success', true, 'missions_annulees', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_serie_etablissement(p_mission_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_count int := 0;
  v_mid uuid;
BEGIN
  -- Get caller's establishment
  SELECT mon_etablissement_id() INTO v_etab_id;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé');
  END IF;

  -- Cancel all missions in a single transaction
  FOREACH v_mid IN ARRAY p_mission_ids LOOP
    UPDATE missions 
    SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = now()
    WHERE id = v_mid 
      AND etablissement_id = v_etab_id 
      AND statut = 'OUVERTE';
    IF FOUND THEN v_count := v_count + 1; END IF;
  END LOOP;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    auth.uid(), 'ADMIN_ETABLISSEMENT', 'MISSION_ANNULATION_SERIE',
    'mission', v_etab_id, NULL,
    jsonb_build_object('nb_annulees', v_count, 'mission_ids', to_jsonb(p_mission_ids)),
    NULL, NULL
  );

  RETURN jsonb_build_object('success', true, 'nb_annulees', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_mission(p_mission_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_is_admin BOOLEAN := est_admin();
    v_etab_id UUID := mon_etablissement_id();
    v_nouveau_statut TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;

    IF NOT v_is_admin AND v_mission.etablissement_id != v_etab_id AND v_mission.soignant_assigne_id != auth.uid() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    IF v_mission.statut NOT IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS') THEN
        RETURN jsonb_build_object('error', 'Impossible d''annuler au statut ' || v_mission.statut);
    END IF;

    -- Déterminer le bon statut selon qui annule
    IF auth.uid() = v_mission.soignant_assigne_id THEN
        v_nouveau_statut := 'ANNULEE_PAR_SOIGNANT';
        UPDATE soignants SET
            score_fiabilite = GREATEST(0, score_fiabilite - 10),
            total_missions_annulees = total_missions_annulees + 1,
            modifie_le = NOW()
        WHERE id = v_mission.soignant_assigne_id;
    ELSE
        v_nouveau_statut := 'ANNULEE_PAR_ETABLISSEMENT';
    END IF;

    UPDATE missions SET
        statut = v_nouveau_statut,
        motif_annulation = COALESCE(p_motif, 'Annulée'),
        annulee_le = NOW(),
        annulee_par = auth.uid(),
        modifie_le = NOW()
    WHERE id = p_mission_id;

    UPDATE contrats_mission SET statut = 'ANNULE', modifie_le = NOW()
    WHERE mission_id = p_mission_id AND statut != 'SIGNE';

    IF v_mission.soignant_assigne_id IS NOT NULL AND auth.uid() != v_mission.soignant_assigne_id THEN
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.soignant_assigne_id, 'MISSION_ANNULEE', 'Mission annulée',
            'La mission "' || v_mission.intitule || '" a été annulée.', '/soignant/missions', 'SOIGNANT');
    END IF;

    IF auth.uid() != v_mission.etablissement_id THEN
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.etablissement_id, 'MISSION_ANNULEE', 'Mission annulée',
            'La mission "' || v_mission.intitule || '" a été annulée.', '/etablissement/missions', 'ETABLISSEMENT');
    END IF;

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_mission_soignant(p_mission_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_heures_avant NUMERIC;
    v_est_tardive BOOLEAN;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;

    IF v_mission.soignant_assigne_id != auth.uid() THEN
        RETURN '{"error":"Cette mission ne vous est pas assignée"}'::JSONB;
    END IF;
    IF v_mission.statut NOT IN ('ASSIGNEE') THEN
        RETURN '{"error":"Annulation impossible dans cet état. Si la mission est en cours, ouvrez un litige."}'::JSONB;
    END IF;

    v_heures_avant := EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 3600;
    v_est_tardive := v_heures_avant < 24;

    UPDATE missions SET
        statut = 'OUVERTE',
        soignant_assigne_id = NULL,
        annulee_par = auth.uid(),
        annulee_le = NOW(),
        motif_annulation = COALESCE(p_motif, 'Annulée par le soignant'),
        modifie_le = NOW()
    WHERE id = p_mission_id;

    IF v_est_tardive THEN
        UPDATE soignants SET
            total_missions_annulees = COALESCE(total_missions_annulees, 0) + 1,
            score_fiabilite = GREATEST(0, COALESCE(score_fiabilite, 50) - 8),
            modifie_le = NOW()
        WHERE id = auth.uid();
    ELSE
        UPDATE soignants SET
            total_missions_annulees = COALESCE(total_missions_annulees, 0) + 1,
            modifie_le = NOW()
        WHERE id = auth.uid();
    END IF;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_mission.etablissement_id, 'SYSTEM',
        CASE WHEN v_est_tardive THEN '⚠️ Annulation tardive' ELSE '❌ Mission annulée' END,
        'Le soignant a annulé la mission "' || v_mission.intitule || '"' ||
        CASE WHEN v_est_tardive THEN ' à moins de 24h du début.' ELSE '.' END ||
        CASE WHEN p_motif IS NOT NULL THEN ' Motif : ' || p_motif ELSE '' END ||
        ' La mission est remise en ligne.',
        '/etablissement/missions', 'ETABLISSEMENT');

    PERFORM fn_ecrire_audit_safe(
        auth.uid(), 'SOIGNANT', 'MISSION_ANNULEE_PAR_SOIGNANT', 'mission', p_mission_id, NULL,
        jsonb_build_object('tardive', v_est_tardive, 'heures_avant', ROUND(v_heures_avant, 1), 'motif', p_motif)
    );

    IF COALESCE(v_mission.est_urgente, false) = true THEN
        PERFORM public.fn_calculer_score_fiabilite_v2(auth.uid(), 'annulation_mission_urgente');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'annulation_tardive', v_est_tardive,
        'penalite_score', CASE WHEN v_est_tardive THEN -8 ELSE 0 END
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_mission_etablissement(p_mission_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Cette mission ne vous appartient pas"}'::JSONB;
    END IF;
    IF v_mission.statut NOT IN ('OUVERTE', 'ASSIGNEE') THEN
        RETURN '{"error":"Impossible d''annuler une mission en cours ou terminée. Ouvrez un litige si nécessaire."}'::JSONB;
    END IF;

    UPDATE missions SET
        statut = 'ANNULEE_PAR_ETABLISSEMENT',
        annulee_par = COALESCE(mon_etablissement_id(), auth.uid()),
        annulee_le = NOW(),
        motif_annulation = COALESCE(p_motif, 'Annulée par l''établissement'),
        modifie_le = NOW()
    WHERE id = p_mission_id;

    -- ★ Notifier le soignant assigné
    IF v_mission.soignant_assigne_id IS NOT NULL THEN
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.soignant_assigne_id, 'SYSTEM',
            '❌ Mission annulée par l''établissement',
            'La mission "' || v_mission.intitule || '" a été annulée.' ||
            CASE WHEN p_motif IS NOT NULL THEN ' Motif : ' || p_motif ELSE '' END,
            '/soignant/missions', 'SOIGNANT');
    END IF;

    -- ★ Audit
    PERFORM fn_ecrire_audit_safe(
        COALESCE(mon_etablissement_id(), auth.uid()), 'ETABLISSEMENT', 
        'MISSION_ANNULEE_PAR_ETABLISSEMENT', 'mission', p_mission_id, NULL,
        jsonb_build_object('motif', p_motif, 'soignant_assigne', v_mission.soignant_assigne_id)
    );

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_mission_complete(p_mission_id uuid, p_motif text, p_source_litige_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_presence_id uuid;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  -- Marquer la mission comme annulée par litige
  UPDATE public.missions SET
    statut = 'LITIGE',
    modifie_le = NOW()
  WHERE id = p_mission_id;

  -- Invalider la presence si elle existe
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = p_mission_id LIMIT 1;
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.presences SET
      heures_ajustees_litige = 0,
      ajustement_litige_id = p_source_litige_id,
      motif_litige = p_motif,
      modifie_le = NOW()
    WHERE id = v_presence_id;
  END IF;

  -- Enqueue side-effects (avoir total + Stripe refund + Chorus + DPAE si CDD)
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('STRIPE_REFUND_TOTAL', jsonb_build_object('mission_id', p_mission_id, 'motif', p_motif),
     'LITIGE_EXEC', p_source_litige_id),
    ('CHORUS_RECYCLER_FACTURE', jsonb_build_object('mission_id', p_mission_id, 'motif', 'ANNULATION'),
     'LITIGE_EXEC', p_source_litige_id),
    ('DPAE_ANNULATION', jsonb_build_object('mission_id', p_mission_id, 'motif', p_motif),
     'LITIGE_EXEC', p_source_litige_id),
    ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', p_mission_id, 'type', 'TOTAL', 'motif_avoir', 'ANNULATION_MISSION_SOIGNANT'),
     'LITIGE_EXEC', p_source_litige_id);

  RETURN jsonb_build_object('success', true, 'mission_id', p_mission_id, 'presence_id', v_presence_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_mission_etab(p_mission_id uuid, p_motif_categorie text, p_texte_libre text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_contrat RECORD;
  v_presence_id uuid;
  v_indemnite jsonb;
  v_delta_mission interval;
  v_points int := 0;
  v_type_evt text;
  v_event_id uuid;
  v_montant_indem numeric := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  IF p_motif_categorie IS NULL OR p_motif_categorie NOT IN (
    'BESOIN_DISPARU', 'BUDGET_REVU', 'REMPLACEMENT_INTERNE',
    'CHANGEMENT_PLANNING', 'CAS_FORCE_MAJEURE', 'AUTRE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif requis');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 10 caractères)');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE', 'error', 'Mission introuvable');
  END IF;

  -- Auth : l'étab admin doit posséder la mission
  IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Non autorisé à annuler cette mission');
  END IF;

  IF v_mission.statut IN ('LITIGE', 'ANNULEE_PAR_ETABLISSEMENT', 'TERMINEE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'STATUT_INVALIDE',
                                'error', 'Mission déjà annulée ou terminée');
  END IF;

  v_delta_mission := v_mission.debut_le - NOW();

  -- CAS 1 : Mission OUVERTE = annulation libre, 0 pt
  IF v_mission.statut = 'OUVERTE' THEN
    UPDATE public.missions SET
      statut = 'ANNULEE_PAR_ETABLISSEMENT',
      modifie_le = NOW()
    WHERE id = p_mission_id;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      v_uid, 'ADMIN_ETABLISSEMENT', 'ANNULATION_MISSION', 'mission', p_mission_id,
      jsonb_build_object('evenement', 'MISSION_ANNULEE_ETAB',
                          'motif_categorie', p_motif_categorie, 'texte_libre', p_texte_libre,
                          'libre', true, 'statut_initial', 'OUVERTE')
    );

    RETURN jsonb_build_object('success', true, 'libre', true, 'points', 0,
                                'indemnite_montant', 0, 'message', 'Mission OUVERTE annulée sans impact');
  END IF;

  -- Récupérer contrat + presence si applicables
  SELECT * INTO v_contrat FROM public.contrats_mission WHERE mission_id = p_mission_id LIMIT 1;
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = p_mission_id LIMIT 1;

  -- CAS 2 : Pointage déjà commencé → salaires/honoraires COMPLETS
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.missions SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = NOW()
    WHERE id = p_mission_id;
    -- Marquer la presence comme "annulee par étab post-pointage"
    UPDATE public.presences SET
      motif_litige = COALESCE(motif_litige, '') || ' ANNULEE_ETAB_APRES_POINTAGE',
      modifie_le = NOW()
    WHERE id = v_presence_id;

    v_points := -20;
    v_type_evt := 'ANNULATION_APRES_POINTAGE';

    -- Indemnité = montant total dû (mission considérée comme effectuée)
    v_indemnite := public.fn_calculer_indemnite_annulation_etab(
      COALESCE(v_contrat.type_contrat, v_mission.type_contrat::text),
      COALESCE(v_mission.duree_heures, 0) * COALESCE(v_mission.taux_horaire_base, 0),
      v_mission.duree_heures, v_mission.taux_horaire_base, INTERVAL '0'
    );
    v_montant_indem := (v_indemnite->>'montant')::numeric;

  -- CAS 3 : Contrat SIGNE_COMPLET avant pointage → indemnité légale
  ELSIF v_contrat.id IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET' THEN
    UPDATE public.missions SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = NOW()
    WHERE id = p_mission_id;
    UPDATE public.contrats_mission SET statut = 'RUPTURE_ETAB', modifie_le = NOW()
    WHERE id = v_contrat.id;

    v_indemnite := public.fn_calculer_indemnite_annulation_etab(
      v_contrat.type_contrat,
      COALESCE(v_mission.duree_heures, 0) * COALESCE(v_mission.taux_horaire_base, 0),
      v_mission.duree_heures, v_mission.taux_horaire_base, v_delta_mission
    );
    v_montant_indem := (v_indemnite->>'montant')::numeric;

    v_points := -10;
    v_type_evt := CASE WHEN v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')
                       THEN 'ANNULATION_CDD_SIGNE'
                       ELSE 'ANNULATION_LIBERAL_SIGNE' END;

    -- Si CDD : enqueue DPAE annulation
    IF v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE') THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      VALUES ('DPAE_ANNULATION',
              jsonb_build_object('contrat_id', v_contrat.id, 'mission_id', p_mission_id,
                                  'motif', 'ANNULATION_ETAB', 'echeance_legale_h', 48),
              'ANNULATION_MISSION', p_mission_id);
    END IF;

  -- CAS 4 : Mission ACCEPTEE sans contrat signé
  ELSE
    UPDATE public.missions SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = NOW()
    WHERE id = p_mission_id;
    v_points := -3;
    v_type_evt := 'ANNULATION_AVANT_CONTRAT';
    v_indemnite := jsonb_build_object('montant', 0, 'motif', 'AUCUNE_INDEMNITE_AVANT_CONTRAT');
  END IF;

  -- Créer event score étab (toujours sauf cas OUVERTE déjà traité)
  IF v_points < 0 THEN
    INSERT INTO public.evenements_score_etab (
      etablissement_id, type_evenement, points, motif, contestable,
      mission_id, details
    ) VALUES (
      v_mission.etablissement_id, v_type_evt, v_points,
      p_motif_categorie || ' : ' || left(p_texte_libre, 200),
      true,
      p_mission_id,
      jsonb_build_object(
        'motif_categorie', p_motif_categorie,
        'texte_libre', p_texte_libre,
        'delta_mission_h', EXTRACT(EPOCH FROM v_delta_mission) / 3600,
        'indemnite', v_indemnite,
        'pointage_existant', v_presence_id IS NOT NULL,
        'contrat_signe', v_contrat.id IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET'
      )
    ) RETURNING id INTO v_event_id;
  END IF;

  -- Enqueue versement indemnité au soignant si applicable
  IF v_montant_indem > 0 AND v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('STRIPE_REFUND_PARTIEL',
            jsonb_build_object('mission_id', p_mission_id,
                                'beneficiaire_id', v_mission.soignant_assigne_id,
                                'montant', v_montant_indem,
                                'motif', v_indemnite->>'motif',
                                'base_calcul', v_indemnite->>'base_calcul'),
            'ANNULATION_MISSION', p_mission_id);
  END IF;

  -- Enqueue avoir PDF
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('AVOIR_PDF_GENERATION',
          jsonb_build_object('mission_id', p_mission_id, 'type', 'ANNULATION_ETAB',
                              'motif_avoir', 'ANNULATION_MISSION_ETAB',
                              'montant_indemnite', v_montant_indem),
          'ANNULATION_MISSION', p_mission_id);

  -- Notification soignant email + push
  IF v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES
      ('EMAIL_NOTIF', jsonb_build_object(
        'destinataire_id', v_mission.soignant_assigne_id,
        'type', 'MISSION_ANNULEE_ETAB',
        'data', jsonb_build_object('mission_id', p_mission_id,
                                    'motif_categorie', p_motif_categorie,
                                    'indemnite_montant', v_montant_indem,
                                    'indemnite_motif', v_indemnite->>'motif')
      ), 'ANNULATION_MISSION', p_mission_id),
      ('PUSH_NOTIF', jsonb_build_object(
        'destinataire_id', v_mission.soignant_assigne_id,
        'type_evenement', 'MISSION_ANNULEE_ETAB',
        'titre', 'Mission annulée par l''établissement',
        'corps', CASE WHEN v_montant_indem > 0
                       THEN 'Indemnité de ' || v_montant_indem || '€ versée selon Code du travail.'
                       ELSE 'Aucun contrat signé, pas d''indemnité.' END
      ), 'ANNULATION_MISSION', p_mission_id);
  END IF;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'ANNULATION_MISSION', 'mission', p_mission_id,
    jsonb_build_object(
      'evenement', 'MISSION_ANNULEE_ETAB',
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'points', v_points, 'type_evenement', v_type_evt,
      'indemnite', v_indemnite,
      'pointage_existant', v_presence_id IS NOT NULL,
      'contrat_signe', v_contrat.id IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET',
      'event_score_id', v_event_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'libre', v_points = 0,
    'points', v_points,
    'type_evenement', v_type_evt,
    'event_score_id', v_event_id,
    'indemnite', v_indemnite,
    'message', CASE
      WHEN v_montant_indem > 0 THEN 'Indemnité de ' || v_montant_indem || '€ versée au soignant'
      WHEN v_points = -3 THEN 'Annulation enregistrée, pas d''indemnité (contrat non signé)'
      ELSE 'Annulation enregistrée'
    END
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_annuler_invitation_membre(p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_invitation RECORD;
  v_perms jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_invitation FROM public.invitations_etablissement WHERE id = p_invitation_id;
  IF v_invitation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_INTROUVABLE');
  END IF;

  SELECT public.fn_mes_permissions_etab(v_invitation.etablissement_id) INTO v_perms;
  IF NOT COALESCE((v_perms->'permissions'->>'gerer_equipe')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  UPDATE public.invitations_etablissement
  SET statut = 'ANNULEE'
  WHERE id = p_invitation_id AND statut = 'EN_ATTENTE';

  RETURN jsonb_build_object('success', true);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_anonymiser_gps_anciennes()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE presences
  SET arrivee_lat = NULL, arrivee_lng = NULL,
      depart_lat = NULL, depart_lng = NULL,
      arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
      arrivee_ip = NULL, depart_ip = NULL
  WHERE (pointage_arrivee_le < now() - interval '90 days')
    AND (arrivee_lat IS NOT NULL OR depart_lat IS NOT NULL);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parrain RECORD;
  v_filleul_id UUID := auth.uid();
  v_nb_filleuls_valides INT;
  v_parrainage_id UUID;
  v_ip TEXT;
  v_user_agent TEXT;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 50))::integer;
BEGIN
  IF v_filleul_id IS NULL THEN RETURN '{"error":"Non authentifié"}'::JSONB; END IF;
  SELECT * INTO v_parrain FROM soignants WHERE code_parrainage = UPPER(TRIM(p_code)) AND supprime_le IS NULL;
  IF v_parrain IS NULL THEN RETURN '{"error":"Code de parrainage invalide"}'::JSONB; END IF;
  IF v_parrain.id = v_filleul_id THEN RETURN '{"error":"Vous ne pouvez pas vous parrainer vous-même"}'::JSONB; END IF;
  SELECT COUNT(*) INTO v_nb_filleuls_valides FROM parrainages WHERE parrain_id = v_parrain.id AND statut IN ('VALIDE','FILLEUL_ACTIF','VALIDE_EN_ATTENTE_SEUIL','PRIME_VERSEE');
  IF v_nb_filleuls_valides >= 20 THEN RETURN '{"error":"Le parrain a atteint la limite de 20 filleuls validés"}'::JSONB; END IF;
  IF EXISTS (SELECT 1 FROM parrainages WHERE filleul_id = v_filleul_id) THEN RETURN '{"error":"Vous avez déjà appliqué un code de parrainage"}'::JSONB; END IF;
  INSERT INTO parrainages (parrain_id, filleul_id, code_parrainage, statut) VALUES (v_parrain.id, v_filleul_id, UPPER(TRIM(p_code)), 'EN_ATTENTE') RETURNING id INTO v_parrainage_id;
  UPDATE soignants SET parraine_par = v_parrain.id WHERE id = v_filleul_id AND parraine_par IS NULL;
  BEGIN
    v_ip := COALESCE(current_setting('request.headers', true)::json->>'x-forwarded-for', current_setting('request.headers', true)::json->>'x-real-ip', 'unknown');
    v_user_agent := COALESCE(current_setting('request.headers', true)::json->>'user-agent', 'unknown');
  EXCEPTION WHEN OTHERS THEN v_ip := 'unknown'; v_user_agent := 'unknown';
  END;
  IF v_ip <> 'unknown' THEN
    DECLARE v_parrain_last_ip TEXT;
    BEGIN
      SELECT (details->>'ip')::text INTO v_parrain_last_ip FROM journaux_audit WHERE acteur_id = v_parrain.id AND action = 'CONNEXION' ORDER BY cree_le DESC LIMIT 1;
      IF v_parrain_last_ip IS NOT NULL AND v_parrain_last_ip = v_ip THEN
        INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail) VALUES (v_parrainage_id, 'MEME_IP', jsonb_build_object('ip', v_ip, 'parrain_id', v_parrain.id, 'filleul_id', v_filleul_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  INSERT INTO parrainage_fraude_signals (parrainage_id, type, detail) VALUES (v_parrainage_id, 'MEME_DEVICE', jsonb_build_object('ip_filleul', v_ip, 'user_agent_filleul', v_user_agent, 'filleul_id', v_filleul_id, 'parrain_id', v_parrain.id));
  RETURN jsonb_build_object('success', true, 'message', 'Code accepté ! Votre prime de ' || v_prime || '€ sera versée après votre 1ère mission terminée et 100€ de commission encaissée par Jolene.');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_anti_seed_facture_honoraire()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission_net numeric;
  v_ecart numeric;
  v_ctx text;
  v_admin_reason text;
BEGIN
  v_ctx := NULLIF(current_setting('jolene.generate_invoice_context', true), '');
  IF v_ctx = 'true' THEN
    RETURN NEW;
  END IF;

  v_admin_reason := NULLIF(current_setting('jolene.admin_seed_override_reason', true), '');
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object('reason', v_admin_reason, 'mission_id', NEW.mission_id,
        'montant_ht', NEW.montant_ht, 'numero_facture', NEW.numero_facture)
    );
    RETURN NEW;
  END IF;

  IF public.est_admin() THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'factures_honoraires', NEW.id,
      jsonb_build_object('reason', 'admin_context (résolution litige / ajustement financier)',
        'mission_id', NEW.mission_id, 'montant_ht', NEW.montant_ht, 'numero_facture', NEW.numero_facture)
    );
    RETURN NEW;
  END IF;

  SELECT net_a_payer INTO v_mission_net FROM missions WHERE id = NEW.mission_id;

  IF v_mission_net IS NULL THEN
    RAISE EXCEPTION 'anti-seed facture: mission % sans snapshot financier (net_a_payer=NULL). Utilisez generate-invoice ou définissez jolene.admin_seed_override_reason.',
      NEW.mission_id USING ERRCODE = 'check_violation';
  END IF;

  v_ecart := ABS(COALESCE(NEW.montant_ht, 0) - v_mission_net);
  IF v_ecart > 0.50 THEN
    RAISE EXCEPTION 'anti-seed facture: montant_ht % incoherent avec mission.net_a_payer % (ecart=%€ > 0.50€). Utilisez generate-invoice ou jolene.admin_seed_override_reason.',
      NEW.montant_ht, v_mission_net, v_ecart USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_anti_seed_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ctx text;
  v_admin_reason text;
  v_expected_brut numeric;
  v_expected_net numeric;
  v_ecart_brut numeric;
  v_ecart_net numeric;
  v_taux_commission numeric;
BEGIN
  v_ctx := NULLIF(current_setting('jolene.creer_mission_context', true), '');
  IF v_ctx = 'true' THEN
    RETURN NEW;
  END IF;

  v_admin_reason := NULLIF(current_setting('jolene.admin_seed_override_reason', true), '');
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_ANTI_SEED',
      'missions', NEW.id,
      jsonb_build_object(
        'reason', v_admin_reason,
        'intitule', NEW.intitule,
        'etablissement_id', NEW.etablissement_id,
        'total_brut', NEW.total_brut,
        'net_a_payer', NEW.net_a_payer
      )
    );
    RETURN NEW;
  END IF;

  IF NEW.total_brut IS NULL AND NEW.net_a_payer IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.duree_heures IS NULL OR NEW.taux_horaire_base IS NULL THEN
    RAISE EXCEPTION 'anti-seed mission: total_brut/net_a_payer posés sans duree_heures ni taux_horaire_base. Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_expected_brut := NEW.taux_horaire_base * NEW.duree_heures;
  v_taux_commission := COALESCE(NEW.taux_commission, 0);
  v_expected_net := v_expected_brut * (1 - v_taux_commission);

  v_ecart_brut := ABS(COALESCE(NEW.total_brut, 0) - v_expected_brut);
  v_ecart_net  := ABS(COALESCE(NEW.net_a_payer, 0) - v_expected_net);

  IF v_ecart_brut > 1 THEN
    RAISE EXCEPTION 'anti-seed mission: total_brut % incoherent avec taux×duree=% (ecart=%€ > 1€). Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.',
      NEW.total_brut, v_expected_brut, v_ecart_brut
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_ecart_net > 1 THEN
    RAISE EXCEPTION 'anti-seed mission: net_a_payer % incoherent avec brut×(1-commission)=% (ecart=%€ > 1€). Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.',
      NEW.net_a_payer, v_expected_net, v_ecart_net
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage_etab(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filleul_id UUID;
  v_parrain_etab RECORD;
  v_filleul_siret TEXT;
  v_existing UUID;
  v_nb_valides INT;
BEGIN
  v_filleul_id := mon_etablissement_id();
  IF v_filleul_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous devez être connecté en tant qu''établissement');
  END IF;

  IF p_code IS NULL OR LENGTH(TRIM(p_code)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code invalide');
  END IF;

  SELECT id, nom, siret INTO v_parrain_etab FROM etablissements
  WHERE code_parrainage = UPPER(TRIM(p_code));

  IF v_parrain_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code parrainage introuvable');
  END IF;

  IF v_parrain_etab.id = v_filleul_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez pas vous parrainer vous-même');
  END IF;

  SELECT siret INTO v_filleul_siret FROM etablissements WHERE id = v_filleul_id;
  IF EXISTS (
    SELECT 1 FROM parrainages_etablissements pe
    JOIN etablissements ef ON ef.id = pe.filleul_etab_id
    WHERE ef.siret = v_filleul_siret AND pe.statut = 'VALIDATED'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cet établissement (SIRET) a déjà bénéficié d''un parrainage validé');
  END IF;

  SELECT id INTO v_existing FROM parrainages_etablissements WHERE filleul_etab_id = v_filleul_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà appliqué un code parrainage');
  END IF;

  SELECT COUNT(*) INTO v_nb_valides FROM parrainages_etablissements
  WHERE parrain_etab_id = v_parrain_etab.id AND statut = 'VALIDATED';
  IF v_nb_valides >= 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cet établissement parrain a atteint la limite de 10 parrainages validés');
  END IF;

  INSERT INTO parrainages_etablissements (parrain_etab_id, filleul_etab_id, code_parrainage, statut)
  VALUES (v_parrain_etab.id, v_filleul_id, UPPER(TRIM(p_code)), 'PENDING');

  UPDATE etablissements SET parraine_par_id = v_parrain_etab.id
  WHERE id = v_filleul_id AND parraine_par_id IS NULL;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_filleul_id,
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'PARRAINAGE_ETAB_APPLIQUE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_parrain_etab.id,
    p_details := jsonb_build_object('code_parrainage', UPPER(TRIM(p_code)), 'parrain_nom', v_parrain_etab.nom)
  );

  RETURN jsonb_build_object(
    'success', true,
    'parrain_nom', v_parrain_etab.nom,
    'message', 'Code parrainage appliqué. Dès que Jolene aura encaissé 100€ de commission sur vos missions, vous et votre parrain recevrez chacun 50€ de crédit commission.'
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_appliquer_credits_disponibles_etab(p_facture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_facture RECORD;
  v_etab_id UUID;
  v_credits_dispo NUMERIC;
  v_a_deduire NUMERIC;
  v_credit RECORD;
  v_reste_a_deduire NUMERIC;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  SELECT id, etablissement_id, montant_ht, montant_ttc, statut, type_document
  INTO v_facture FROM factures WHERE id = p_facture_id;
  IF v_facture IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facture introuvable');
  END IF;
  IF v_facture.statut <> 'BROUILLON' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facture non modifiable (statut: ' || v_facture.statut || ')');
  END IF;
  IF v_facture.type_document <> 'FACTURE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Crédits applicables uniquement sur FACTURE');
  END IF;

  v_etab_id := v_facture.etablissement_id;

  SELECT COALESCE(SUM(montant_eur), 0) INTO v_credits_dispo
  FROM credits_etablissement WHERE etablissement_id = v_etab_id AND applique_le IS NULL;

  IF v_credits_dispo <= 0 THEN
    RETURN jsonb_build_object('success', true, 'credit_applique_eur', 0, 'message', 'Aucun crédit disponible');
  END IF;

  v_a_deduire := LEAST(v_credits_dispo, v_facture.montant_ht);
  v_reste_a_deduire := v_a_deduire;

  FOR v_credit IN
    SELECT id, montant_eur FROM credits_etablissement
    WHERE etablissement_id = v_etab_id AND applique_le IS NULL
    ORDER BY cree_le ASC
  LOOP
    EXIT WHEN v_reste_a_deduire <= 0;
    UPDATE credits_etablissement SET applique_le = NOW(), facture_id = p_facture_id WHERE id = v_credit.id;
    v_reste_a_deduire := v_reste_a_deduire - v_credit.montant_eur;
  END LOOP;

  UPDATE factures
  SET montant_ht = GREATEST(0, montant_ht - v_a_deduire),
      montant_ttc = GREATEST(0, montant_ttc - v_a_deduire)
  WHERE id = p_facture_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_etab_id,
    p_type_acteur := 'SYSTEME',
    p_action := 'CREDIT_PARRAINAGE_APPLIQUE',
    p_type_ressource := 'facture',
    p_id_ressource := p_facture_id,
    p_details := jsonb_build_object('credit_eur', v_a_deduire, 'etablissement_id', v_etab_id)
  );

  RETURN jsonb_build_object('success', true, 'credit_applique_eur', v_a_deduire);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_appliquer_compensation_partielle(p_mission_id uuid, p_pourcentage numeric, p_motif text, p_source_litige_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_presence_id uuid;
  v_taux numeric;
BEGIN
  IF p_pourcentage <= 0 OR p_pourcentage > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pourcentage doit être entre 0 et 100');
  END IF;

  v_taux := (100 - p_pourcentage) / 100.0;

  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = p_mission_id LIMIT 1;
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.presences SET
      heures_ajustees_litige = ROUND(duree_brute_min::numeric / 60 * v_taux, 2),
      ajustement_litige_id = p_source_litige_id,
      motif_litige = p_motif,
      modifie_le = NOW()
    WHERE id = v_presence_id;
  END IF;

  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('STRIPE_REFUND_PARTIEL', jsonb_build_object('mission_id', p_mission_id, 'pourcentage', p_pourcentage),
     'LITIGE_EXEC', p_source_litige_id),
    ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', p_mission_id, 'type', 'PARTIEL',
                                                  'pourcentage', p_pourcentage, 'motif_avoir', 'COMPENSATION_PARTIELLE'),
     'LITIGE_EXEC', p_source_litige_id);

  RETURN jsonb_build_object('success', true, 'mission_id', p_mission_id,
    'pourcentage_compensation', p_pourcentage, 'presence_id', v_presence_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_apercu_marche_profession(p_profession text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_rayon_km integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_geo boolean := p_lat IS NOT NULL AND p_lng IS NOT NULL AND COALESCE(p_rayon_km, 0) > 0;
  v_nb_missions integer;
  v_taux_max numeric;
  v_taux_moyen numeric;
  v_nb_etabs integer;
BEGIN
  SELECT count(*)::integer, max(m.taux_horaire_base), round(avg(m.taux_horaire_base), 2)
  INTO v_nb_missions, v_taux_max, v_taux_moyen
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND m.debut_le > now()
    AND e.supprime_le IS NULL
    AND (p_profession IS NULL OR btrim(p_profession) = '' OR m.profession_requise::text = btrim(p_profession))
    AND (
      NOT v_geo
      OR (e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
          AND public.fn_haversine_distance_m(e.adresse_lat, e.adresse_lng, p_lat::numeric, p_lng::numeric) <= p_rayon_km * 1000)
    );

  -- Preuve sociale de repli quand le marché est vide : établissements inscrits.
  SELECT count(*)::integer
  INTO v_nb_etabs
  FROM etablissements e
  WHERE e.supprime_le IS NULL
    AND (
      NOT v_geo
      OR (e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
          AND public.fn_haversine_distance_m(e.adresse_lat, e.adresse_lng, p_lat::numeric, p_lng::numeric) <= p_rayon_km * 1000)
    );

  RETURN jsonb_build_object(
    'nb_missions', COALESCE(v_nb_missions, 0),
    'taux_max', v_taux_max,
    'taux_moyen', v_taux_moyen,
    'nb_etablissements', COALESCE(v_nb_etabs, 0),
    'zone', CASE WHEN v_geo THEN 'rayon' ELSE 'national' END
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_appliquer_remise_groupe()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_groupe RECORD;
    v_nb_updated INTEGER := 0;
    v_total INTEGER := 0;
BEGIN
    IF NOT est_admin() THEN RETURN jsonb_build_object('error', 'Non autorisé'); END IF;

    FOR v_groupe IN 
        SELECT g.id, g.nom, g.remise_groupe_pourcent
        FROM groupes_sante g
        WHERE g.supprime_le IS NULL
          AND g.remise_groupe_pourcent IS NOT NULL
          AND g.remise_groupe_pourcent > 0
    LOOP
        -- Appliquer: le taux effectif = taux palier - remise groupe
        -- (sans descendre en dessous de 5%)
        UPDATE etablissements SET
            taux_commission_negocie = GREATEST(5.00, 
                COALESCE(
                    (SELECT pc.taux_commission FROM paliers_commission pc WHERE pc.id = palier_commission_id),
                    15.00
                ) - v_groupe.remise_groupe_pourcent
            ),
            modifie_le = NOW()
        WHERE groupe_sante_id = v_groupe.id
          AND supprime_le IS NULL;
          
        GET DIAGNOSTICS v_nb_updated = ROW_COUNT;
        v_total := v_total + v_nb_updated;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'etablissements_mis_a_jour', v_total);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_audit_connexion(p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
BEGIN
    IF p_action NOT IN ('CONNEXION', 'DECONNEXION') THEN
        RETURN '{"error":"Action non autorisée"}'::JSONB;
    END IF;

    -- Capture automatique de l'IP et du User-Agent depuis les headers HTTP
    -- (PostgREST expose request.headers à PostgreSQL)
    BEGIN
        v_headers := current_setting('request.headers', true)::jsonb;
        -- X-Forwarded-For peut contenir une chaine "ip1, ip2, ip3" -> on prend la 1ere (client réel)
        v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
        v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
        v_ip := NULL;
        v_user_agent := NULL;
    END;

    INSERT INTO journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource,
        ip_acteur, navigateur_acteur, details
    )
    VALUES (
        COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID),
        COALESCE(mon_role(), 'SOIGNANT'),
        p_action,
        'session',
        COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID),
        v_ip,
        v_user_agent,
        jsonb_build_object(
            'horodatage', now(),
            'method', 'email_password'
        )
    );

    RETURN '{"success":true}'::JSONB;
EXCEPTION WHEN OTHERS THEN
    -- Silencieux — l'audit de connexion ne doit jamais bloquer l'utilisateur
    RETURN '{"success":false}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_code_parrainage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.code_parrainage IS NULL OR NEW.code_parrainage = '' THEN
        NEW.code_parrainage := fn_generer_code_parrainage();
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_arrondir_quart_heure(p_ts timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT date_trunc('hour', p_ts) +
    INTERVAL '15 minutes' * ROUND(EXTRACT(MINUTE FROM p_ts) / 15.0);
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_etab RECORD;
    v_type_contrat TEXT;
    v_numero TEXT;
    v_html TEXT;
    v_heures_semaine NUMERIC;
    v_debut_semaine TIMESTAMPTZ;
    v_fin_semaine TIMESTAMPTZ;
    v_choix_applique TEXT;
    v_type_paiement TEXT;
    v_mode_paiement TEXT;
BEGIN
    IF NOT (est_admin() OR est_admin_etablissement()) THEN
        RETURN '{"error":"Non autorise"}'::JSONB;
    END IF;

    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN '{"error":"Cette mission n est plus disponible"}'::JSONB; END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN '{"error":"Soignant introuvable"}'::JSONB; END IF;

    SELECT * INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Ce soignant est ' || v_soignant.profession::TEXT || ', la mission requiert un(e) ' || v_mission.profession_requise::TEXT || '.');
    END IF;

    IF fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
        RETURN jsonb_build_object('error', 'Ce soignant est dans la liste d exclusions de cet etablissement.');
    END IF;

    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') = 'LIBERAL' THEN
        RETURN jsonb_build_object('error', 'Cette mission est reservee aux salaries.');
    END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est reservee aux liberaux.');
    END IF;

    IF p_choix_contrat IS NOT NULL AND p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
        RETURN jsonb_build_object('error', 'p_choix_contrat invalide (attendu SALARIE ou LIBERAL).');
    END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL THEN
            RETURN jsonb_build_object(
                'error', 'E16_CHOIX_CONTRAT_REQUIS',
                'message', 'Mission MIXTE avec soignant MIXTE : specifiez p_choix_contrat SALARIE ou LIBERAL.',
                'mission_id', p_mission_id,
                'soignant_id', p_soignant_id
            );
        END IF;
        v_choix_applique := p_choix_contrat;
    ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN
        v_choix_applique := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
        v_choix_applique := 'LIBERAL';
    ELSE
        v_choix_applique := COALESCE(v_soignant.type_exercice, 'SALARIE');
    END IF;

    IF v_choix_applique = 'SALARIE' THEN
        v_debut_semaine := DATE_TRUNC('week', v_mission.debut_le);
        v_fin_semaine := v_debut_semaine + INTERVAL '7 days';
        SELECT COALESCE(SUM(duree_heures), 0) INTO v_heures_semaine
        FROM missions WHERE soignant_assigne_id = p_soignant_id
          AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
          AND debut_le >= v_debut_semaine AND debut_le < v_fin_semaine;
        IF v_heures_semaine + COALESCE(v_mission.duree_heures, 0) > 48 THEN
            RETURN jsonb_build_object('error', 'Depasse 48h/semaine (' || ROUND(v_heures_semaine, 1) || 'h planifiees).');
        END IF;
    END IF;

    IF v_choix_applique = 'LIBERAL' THEN
        v_type_contrat := 'REMPLACEMENT_LIBERAL';
        v_type_paiement := 'NOTE_HONORAIRES';
        v_mode_paiement := 'STRIPE_CONNECT';
    ELSE
        v_type_contrat := 'CDD';
        v_type_paiement := 'BULLETIN_PAIE';
        v_mode_paiement := 'DIRECT';
    END IF;

    UPDATE missions SET
        soignant_assigne_id = p_soignant_id,
        statut = 'ASSIGNEE',
        type_contrat_applique = v_choix_applique::type_contrat_applique_enum,
        choix_contrat_soignant = v_choix_applique,
        type_paiement_soignant = v_type_paiement,
        mode_paiement_soignant = v_mode_paiement,
        modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';

    IF NOT FOUND THEN RETURN '{"error":"Mission deja prise"}'::JSONB; END IF;

    v_numero := fn_generer_numero_contrat(v_type_contrat);

    SELECT contenu_html INTO v_html FROM templates_contrat
    WHERE type_contrat = v_type_contrat AND est_actif = TRUE LIMIT 1;

    IF v_html IS NOT NULL THEN
        v_html := REPLACE(v_html, '{{etablissement_nom}}', fn_html_escape(v_etab.nom));
        v_html := REPLACE(v_html, '{{etablissement_siret}}', fn_html_escape(v_etab.siret));
        v_html := REPLACE(v_html, '{{etablissement_finess}}', fn_html_escape(COALESCE(v_etab.finess, 'N/A')));
        v_html := REPLACE(v_html, '{{etablissement_adresse}}', fn_html_escape(COALESCE(v_etab.adresse_rue || ', ' || v_etab.adresse_code_postal || ' ' || v_etab.adresse_ville, '')));
        v_html := REPLACE(v_html, '{{soignant_prenom}}', fn_html_escape(v_soignant.prenom));
        v_html := REPLACE(v_html, '{{soignant_nom}}', fn_html_escape(v_soignant.nom));
        v_html := REPLACE(v_html, '{{soignant_rpps}}', fn_html_escape(COALESCE(v_soignant.numero_rpps, '')));
        v_html := REPLACE(v_html, '{{soignant_siret}}', fn_html_escape(COALESCE(v_soignant.siret_liberal, '')));
        v_html := REPLACE(v_html, '{{profession}}', fn_html_escape(COALESCE(v_soignant.profession::TEXT, '')));
        v_html := REPLACE(v_html, '{{service}}', fn_html_escape(COALESCE(v_mission.service, '')));
        v_html := REPLACE(v_html, '{{debut_date}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{debut_heure}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
        v_html := REPLACE(v_html, '{{fin_date}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{fin_heure}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
        v_html := REPLACE(v_html, '{{duree_heures}}', COALESCE(v_mission.duree_heures::TEXT, ''));
        v_html := REPLACE(v_html, '{{taux_horaire}}', COALESCE(v_mission.taux_horaire_base::TEXT, ''));
        v_html := REPLACE(v_html, '{{numero_contrat}}', fn_html_escape(v_numero));
        v_html := REPLACE(v_html, '{{date_signature}}', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{lieu}}', fn_html_escape(COALESCE(v_etab.adresse_ville, '')));
    END IF;

    INSERT INTO contrats_mission (
        mission_id, etablissement_id, soignant_id,
        type_contrat, numero_contrat, contenu_html, statut
    ) VALUES (
        p_mission_id, v_mission.etablissement_id, p_soignant_id,
        v_type_contrat, v_numero, v_html, 'EN_ATTENTE_SIGNATURES'
    );

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (p_soignant_id, 'MISSION_ACCEPTEE', 'Mission assignee',
        'Vous avez ete assigne(e) a la mission "' || fn_html_escape(v_mission.intitule) || '". Signez votre contrat.',
        '/soignant/missions/' || p_mission_id, 'SOIGNANT');

    RETURN jsonb_build_object(
        'success', true,
        'contrat_numero', v_numero,
        'choix_applique', v_choix_applique
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_audit_rls_strict()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_tables_sans_rls jsonb; v_tables_avec_rls_faible jsonb;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  SELECT jsonb_agg(c.relname) INTO v_tables_sans_rls
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = false
    AND c.relname NOT IN ('signature_rate_limit_ip', 'spatial_ref_sys');
  SELECT jsonb_agg(jsonb_build_object('table', c.relname, 'policies', cnt))
  INTO v_tables_avec_rls_faible
  FROM (
    SELECT c.relname, COUNT(p.polname) AS cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_policy p ON p.polrelid = c.oid
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = true
    GROUP BY c.relname HAVING COUNT(p.polname) = 0
  ) c;
  RETURN jsonb_build_object('success', true,
    'tables_sans_rls', COALESCE(v_tables_sans_rls, '[]'::jsonb),
    'tables_rls_active_sans_policy', COALESCE(v_tables_avec_rls_faible, '[]'::jsonb),
    'exec_le', NOW());
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_archiver_conversations_anciennes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_archivees int;
BEGIN
  WITH upd AS (
    UPDATE conversations c
    SET archived_at = NOW()
    FROM missions m
    WHERE c.mission_id = m.id
      AND c.archived_at IS NULL
      AND m.statut IN ('TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
      AND COALESCE(m.fin_le, m.cree_le) < NOW() - INTERVAL '30 days'
    RETURNING c.id
  )
  SELECT count(*) INTO v_archivees FROM upd;

  IF v_archivees > 0 THEN
    INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'conversations', NULL,
            jsonb_build_object(
              'evenement', 'MESSAGERIE_ARCHIVAGE_AUTO',
              'nombre_archivees', v_archivees,
              'date_iso', NOW()::text
            ));
  END IF;

  RETURN jsonb_build_object(
    'archivees', v_archivees,
    'execute_le', NOW()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auth_user_deleted_cleanup_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    DELETE FROM public.soignants WHERE id = OLD.id;
  EXCEPTION WHEN others THEN
    UPDATE public.soignants
      SET numero_rpps = NULL, rpps_verifie = false, rpps_verifie_le = NULL,
          rpps_nom_api = NULL, rpps_prenom_api = NULL, rpps_profession_api = NULL,
          numero_adeli = NULL,
          supprime_le = COALESCE(supprime_le, now())
      WHERE id = OLD.id;
  END;
  RETURN OLD;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_facture_id UUID;
    v_num TEXT;
    v_compteur INT := 0;
    v_mois TEXT;
    v_recalc_info JSONB;
    v_est_public BOOLEAN;
    v_delai_j INTEGER;
    v_echeance DATE;
BEGIN
    IF NOT fn_est_contexte_cron_ou_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    v_recalc_info := public.fn_recalculer_commissions_post_litige();
    v_mois := TO_CHAR(now(), 'YYYY-MM');

    FOR v_etab IN
        SELECT etablissement_id,
               COUNT(*) as nb,
               SUM(COALESCE(montant_commission_ht, 0)) as sum_ht,
               SUM(COALESCE(montant_commission_tva, 0)) as sum_tva,
               SUM(COALESCE(montant_commission_ttc, 0)) as sum_ttc
        FROM missions m
        WHERE m.statut = 'TERMINEE'
          AND m.commission_facturee = false
          AND NOT (m.mode_remuneration = 'RETROCESSION' AND m.honoraires_confirmes_le IS NULL)
          AND m.facture_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = m.id)
        GROUP BY etablissement_id
    LOOP
        IF v_etab.sum_ht <= 0 THEN CONTINUE; END IF;
        SELECT COALESCE(est_secteur_public, false) INTO v_est_public FROM etablissements WHERE id = v_etab.etablissement_id;
        v_delai_j := CASE WHEN v_est_public
                          THEN (public.fn_param_num('delai_paiement_public_j', 50))::integer
                          ELSE (public.fn_param_num('delai_paiement_prive_j', 30))::integer END;
        v_echeance := (now() + (v_delai_j::text || ' days')::interval)::date;
        v_compteur := v_compteur + 1;
        v_num := 'FACT-' || v_mois || '-' || LPAD(v_compteur::TEXT, 4, '0');
        INSERT INTO factures (etablissement_id, numero_facture, montant_ht, montant_tva, montant_ttc,
            nombre_missions, statut, date_emission, date_echeance, periode_debut, periode_fin)
        VALUES (v_etab.etablissement_id, v_num, v_etab.sum_ht, v_etab.sum_tva, v_etab.sum_ttc,
            v_etab.nb, 'EMISE', now(), v_echeance,
            date_trunc('month', now())::date,
            (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date)
        RETURNING id INTO v_facture_id;
        UPDATE missions SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id AND statut = 'TERMINEE'
          AND commission_facturee = false AND facture_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = missions.id);
    END LOOP;

    RETURN jsonb_build_object('success', true, 'factures_generees', v_compteur, 'recalc_post_litige', v_recalc_info);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_revoke_anon_execute()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE object_type = 'function'
    LOOP
        IF r.schema_name = 'public' THEN
            -- object_identity comes from system catalog, not user input — safe
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, public', r.object_identity);
        END IF;
    END LOOP;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_publier_evaluation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.note >= 4 AND (NEW.commentaire IS NULL OR trim(NEW.commentaire) = '') THEN
        NEW.visible := TRUE;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_terminer_missions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INT;
BEGIN
    UPDATE missions
    SET statut = 'TERMINEE',
        modifie_le = now()
    WHERE statut = 'EN_COURS'
    AND fin_le < now() - INTERVAL '15 minutes'; -- petite marge pour éviter les race conditions
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN jsonb_build_object('success', true, 'missions_terminees', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_creation_litiges_presence()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_delai_pointage_h INT;
  v_nb_abs INT := 0;
  v_nb_dep INT := 0;
  v_presence RECORD;
  v_litige_id UUID;
  v_type_litige public.type_litige;
  v_motif TEXT;
  v_notif_corps TEXT;
BEGIN
  SELECT valeur::INT INTO v_delai_pointage_h
    FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';

  FOR v_presence IN
    SELECT p.id AS presence_id,
           p.mission_id,
           p.soignant_id,
           p.heures_reelles,
           m.duree_heures,
           m.etablissement_id,
           m.soignant_assigne_id
      FROM public.presences p
      JOIN public.missions m ON m.id = p.mission_id
     WHERE p.valide_par_etablissement = TRUE
       AND p.valide_le IS NOT NULL
       AND p.valide_le < NOW() - make_interval(hours => v_delai_pointage_h)
       AND p.motif_litige IS NOT NULL
       AND p.litige_auto_cree_le IS NULL
  LOOP
    IF v_presence.heures_reelles IS NULL OR v_presence.heures_reelles = 0 THEN
      v_type_litige := 'ABSENCE_SOIGNANT';
      v_motif       := 'Auto-création : soignant marqué absent sans contestation dans les 48h';
      v_notif_corps := 'Votre établissement a signalé une absence. Répondez sous 72h pour éviter l''escalade automatique.';
    ELSIF v_presence.duree_heures IS NOT NULL
      AND v_presence.duree_heures > 0
      AND v_presence.heures_reelles < v_presence.duree_heures * 0.80
    THEN
      v_type_litige := 'DEPART_ANTICIPE';
      v_motif       := format(
        'Auto-création : départ anticipé (%sh effectuées sur %sh prévues, soit %s %%).',
        v_presence.heures_reelles,
        v_presence.duree_heures,
        round((v_presence.heures_reelles / v_presence.duree_heures) * 100)
      );
      v_notif_corps := 'Votre établissement a signalé un départ anticipé. Répondez sous 72h pour éviter l''escalade automatique.';
    ELSE
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.litiges l
       WHERE l.mission_id = v_presence.mission_id
         AND l.type_litige = v_type_litige
         AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION')
    ) THEN
      UPDATE public.presences
         SET litige_auto_cree_le = NOW()
       WHERE id = v_presence.presence_id;
      CONTINUE;
    END IF;

    INSERT INTO public.litiges (
      mission_id, soignant_id, etablissement_id, presence_id,
      initie_par, motif, statut, type_litige, est_informatif
    ) VALUES (
      v_presence.mission_id,
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      v_presence.etablissement_id,
      v_presence.presence_id,
      'SYSTEME',
      v_motif,
      'OUVERT',
      v_type_litige,
      FALSE
    )
    RETURNING id INTO v_litige_id;

    UPDATE public.presences
       SET litige_auto_cree_le = NOW()
     WHERE id = v_presence.presence_id;

    PERFORM public.fn_ecrire_audit(
      NULL, 'SYSTEM', 'LITIGE_AUTO_CREATION',
      'litige', v_litige_id, NULL,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'presence_id', v_presence.presence_id,
        'heures_reelles', v_presence.heures_reelles,
        'duree_heures_prevues', v_presence.duree_heures,
        'raison', CASE v_type_litige
          WHEN 'ABSENCE_SOIGNANT' THEN 'Absence non contestée dans les 48h post-validation présence'
          WHEN 'DEPART_ANTICIPE'  THEN 'Départ anticipé (< 80 % heures prévues) non contesté dans les 48h'
        END
      ),
      NULL, NULL
    );

    PERFORM public.fn_litige_push_notification(
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      'SOIGNANT',
      'LITIGE_OUVERTURE',
      'Litige ouvert sur votre mission',
      v_notif_corps,
      v_litige_id,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'auto_cree', TRUE
      )
    );

    IF v_type_litige = 'ABSENCE_SOIGNANT' THEN
      v_nb_abs := v_nb_abs + 1;
    ELSE
      v_nb_dep := v_nb_dep + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'litiges_crees', v_nb_abs + v_nb_dep,
    'absence_soignant', v_nb_abs,
    'depart_anticipe', v_nb_dep
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_creer_bulletin_paie_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_type text;
BEGIN
  IF NEW.statut = 'TERMINEE' AND (OLD.statut IS DISTINCT FROM 'TERMINEE') AND NEW.soignant_assigne_id IS NOT NULL THEN
    SELECT type_exercice INTO v_type FROM soignants WHERE id = NEW.soignant_assigne_id;
    IF COALESCE(v_type, 'SALARIE') <> 'LIBERAL' THEN
      -- Best-effort : on n'arrête pas le passage en TERMINEE si la création échoue.
      BEGIN
        PERFORM public.fn_creer_bulletin_paie(NEW.id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'fn_auto_creer_bulletin_paie_trg: %', SQLERRM;
      END;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_code_parrainage_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.code_parrainage IS NULL OR NEW.code_parrainage = '' THEN
    NEW.code_parrainage := public.fn_generer_code_parrainage_etab();
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_confirmer_honoraires()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD; v_mandat boolean; v_n int := 0;
BEGIN
  FOR v_m IN
    SELECT m.* FROM missions m
    WHERE m.mode_remuneration = 'RETROCESSION'
      AND m.montant_honoraires_bruts IS NOT NULL
      AND m.honoraires_confirmes_le IS NULL
      AND m.modifie_le < NOW() - INTERVAL '48 hours'
      AND NOT EXISTS (
        SELECT 1 FROM litiges l
        WHERE l.mission_id = m.id
          AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN'))
    LIMIT 50
  LOOP
    UPDATE missions SET honoraires_confirmes_le = NOW() WHERE id = v_m.id;
    SELECT COALESCE(mandat_facturation_signe, FALSE) INTO v_mandat FROM soignants WHERE id = v_m.soignant_assigne_id;
    IF v_mandat AND NOT EXISTS (SELECT 1 FROM factures_honoraires WHERE mission_id = v_m.id) THEN
      PERFORM fn_generer_facture_honoraires_mission(v_m.id);
    END IF;
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Relevé validé automatiquement',
      'Sans contestation sous 48h, le relevé de "' || fn_html_escape(v_m.intitule) ||
      '" est validé : rétrocession de ' || v_m.net_a_payer || ' €.',
      '/soignant/missions/' || v_m.id, 'SOIGNANT');
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('success', TRUE, 'confirmes', v_n);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_valider_presences_72h()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
  v_result := fn_valider_presences_72h_auto();
  RETURN COALESCE((v_result->>'count_validees')::int, 0);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_badge_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
BEGIN
    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN '{}'::JSONB; END IF;
    
    RETURN jsonb_build_object(
        'total_missions', v_soignant.total_missions_terminees,
        'heures_cumulees', v_soignant.heures_cumulees,
        'score_fiabilite', v_soignant.score_fiabilite,
        'missions_urgentes', (SELECT COUNT(*) FROM missions WHERE soignant_assigne_id = auth.uid() AND est_urgente = true AND statut = 'TERMINEE'),
        'evaluations_5_etoiles', (SELECT COUNT(*) FROM evaluations WHERE evalue_id = auth.uid() AND note = 5),
        'mois_consecutifs', GREATEST(1, EXTRACT(MONTH FROM AGE(NOW(), v_soignant.premiere_mission_le))::INTEGER),
        'parrainages', (SELECT COUNT(*) FROM parrainages WHERE parrain_id = auth.uid()),
        'badge_ambassadeur', v_soignant.badge_ambassadeur
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_bfa_info(p_annee integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID;
    v_groupe_id UUID;
    v_bfa_eligible BOOLEAN;
    v_bfa_contrat_signe TIMESTAMP WITH TIME ZONE;
    v_annee INTEGER;
    v_bfa RECORD;
    v_missions INTEGER;
    v_commissions NUMERIC;
    v_paliers JSONB;
    v_palier_actuel TEXT;
    v_prochain RECORD;
    v_missions_manquantes INTEGER;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN 
        RETURN jsonb_build_object('eligible', false, 'raison', 'Non autorise'); 
    END IF;
    
    v_annee := COALESCE(p_annee, EXTRACT(YEAR FROM NOW())::INTEGER);

    SELECT e.groupe_sante_id, g.bfa_eligible, g.bfa_contrat_signe_le
    INTO v_groupe_id, v_bfa_eligible, v_bfa_contrat_signe
    FROM etablissements e
    LEFT JOIN groupes_sante g ON g.id = e.groupe_sante_id
    WHERE e.id = v_etab_id;

    IF v_groupe_id IS NULL OR v_bfa_eligible IS NOT TRUE OR v_bfa_contrat_signe IS NULL THEN
        RETURN jsonb_build_object('eligible', false, 'raison', 
            CASE 
                WHEN v_groupe_id IS NULL THEN 'Reserve aux groupes de sante'
                WHEN v_bfa_eligible IS NOT TRUE THEN 'Votre groupe nest pas eligible au BFA'
                ELSE 'Contrat BFA non signe'
            END
        );
    END IF;

    SELECT COUNT(*), COALESCE(SUM(montant_commission_ht), 0)
    INTO v_missions, v_commissions
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
    WHERE e.groupe_sante_id = v_groupe_id AND m.statut = 'TERMINEE'
    AND EXTRACT(YEAR FROM m.fin_le) = v_annee;

    SELECT * INTO v_bfa FROM bfa_suivi WHERE groupe_id = v_groupe_id AND annee = v_annee;

    SELECT nom INTO v_palier_actuel FROM paliers_bfa
    WHERE est_actif = TRUE AND missions_min <= v_missions
    AND (missions_max IS NULL OR missions_max >= v_missions)
    ORDER BY ordre DESC LIMIT 1;

    SELECT * INTO v_prochain FROM paliers_bfa
    WHERE est_actif = TRUE AND missions_min > v_missions
    ORDER BY missions_min ASC LIMIT 1;

    v_missions_manquantes := CASE WHEN v_prochain.id IS NOT NULL THEN v_prochain.missions_min - v_missions ELSE 0 END;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'nom', nom, 'taux_bfa', taux_bfa, 'missions_min', missions_min, 'missions_max', missions_max,
        'atteint', (v_missions >= missions_min)
    ) ORDER BY ordre), '[]'::JSONB) INTO v_paliers FROM paliers_bfa WHERE est_actif = TRUE;

    RETURN jsonb_build_object(
        'eligible', true,
        'annee', v_annee,
        'est_groupe', true,
        'missions_annee', v_missions,
        'commissions_ht_annee', v_commissions,
        'palier_actuel', COALESCE(v_palier_actuel, 'Aucun'),
        'montant_bfa_estime', CASE 
            WHEN v_palier_actuel IS NOT NULL THEN ROUND(v_commissions * (
                SELECT taux_bfa FROM paliers_bfa WHERE nom = v_palier_actuel AND est_actif = TRUE LIMIT 1
            ) / 100, 2)
            ELSE 0 END,
        'prochain_palier', CASE WHEN v_prochain.id IS NOT NULL THEN v_prochain.nom ELSE NULL END,
        'missions_manquantes', v_missions_manquantes,
        'bfa_verse', COALESCE(v_bfa.bfa_verse, FALSE),
        'montant_verse', v_bfa.montant_bfa,
        'paliers', v_paliers,
        'explication', 'Le Bonus Fidelite Annuel (BFA) vous reverse un pourcentage des commissions payees dans lannee. Plus vous utilisez Jolene, plus le bonus est eleve. Il est calcule automatiquement en janvier et verse sous forme davoir.'
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_valider_etablissement_siret()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si le SIRET vient d'être vérifié (colonne siret_verifie passe à TRUE)
    -- ET que le contrat de service est signé
    -- → auto-valider l'établissement
    IF NEW.siret_verifie = TRUE 
       AND (OLD.siret_verifie IS NULL OR OLD.siret_verifie = FALSE)
       AND NEW.statut_verification = 'EN_ATTENTE' THEN
        
        -- Si le contrat est aussi validé → validation complète
        IF NEW.contrat_valide = TRUE THEN
            NEW.statut_verification := 'VERIFIE';
            NEW.peut_publier_missions := TRUE;
            NEW.verifie_le := NOW();
            
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (NEW.id, 'SYSTEM', 'Compte vérifié automatiquement ✅',
                'Votre SIRET a été vérifié et votre contrat est signé. Vous pouvez publier des missions.',
                '/etablissement/missions/creer', 'ETABLISSEMENT');
        ELSE
            -- SIRET OK mais contrat pas encore signé → statut EN_COURS
            NEW.statut_verification := 'EN_COURS';
            
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (NEW.id, 'SYSTEM', 'SIRET vérifié ✅ — Contrat en attente',
                'Votre SIRET a été vérifié. Signez votre contrat de service pour pouvoir publier des missions.',
                '/etablissement/profil', 'ETABLISSEMENT');
        END IF;
    END IF;

    -- Si le contrat vient d'être validé ET que le SIRET est déjà vérifié
    IF NEW.contrat_valide = TRUE 
       AND (OLD.contrat_valide IS NULL OR OLD.contrat_valide = FALSE)
       AND NEW.siret_verifie = TRUE
       AND NEW.statut_verification IN ('EN_ATTENTE', 'EN_COURS') THEN
        
        NEW.statut_verification := 'VERIFIE';
        NEW.peut_publier_missions := TRUE;
        NEW.verifie_le := NOW();
        
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (NEW.id, 'SYSTEM', 'Compte vérifié ✅',
            'Votre établissement est vérifié. Vous pouvez publier des missions !',
            '/etablissement/missions/creer', 'ETABLISSEMENT');
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_auto_transitions_missions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_assignee_to_en_cours INT := 0;
    v_assignee_to_terminee INT := 0;
    v_en_cours_to_terminee INT := 0;
    v_ouverte_to_expiree INT := 0;
    v_candidatures_refusees INT := 0;
    v_rows INT;
    v_mission RECORD;
BEGIN
    UPDATE missions
    SET statut = 'EN_COURS', modifie_le = now()
    WHERE statut = 'ASSIGNEE'
    AND debut_le <= now()
    AND fin_le > now();
    GET DIAGNOSTICS v_assignee_to_en_cours = ROW_COUNT;

    UPDATE missions
    SET statut = 'TERMINEE', modifie_le = now()
    WHERE statut = 'ASSIGNEE'
    AND fin_le < now() - INTERVAL '15 minutes';
    GET DIAGNOSTICS v_assignee_to_terminee = ROW_COUNT;

    UPDATE missions
    SET statut = 'TERMINEE', modifie_le = now()
    WHERE statut = 'EN_COURS'
    AND fin_le < now() - INTERVAL '15 minutes';
    GET DIAGNOSTICS v_en_cours_to_terminee = ROW_COUNT;

    FOR v_mission IN
        SELECT id, intitule, etablissement_id, debut_le
        FROM missions
        WHERE statut = 'OUVERTE'
        AND debut_le < now() - INTERVAL '1 hour'
    LOOP
        UPDATE missions
        SET statut = 'EXPIREE', modifie_le = now()
        WHERE id = v_mission.id;
        v_ouverte_to_expiree := v_ouverte_to_expiree + 1;

        UPDATE candidatures
        SET statut = 'REFUSEE',
            motif_refus = 'Mission expiree (non pourvue)',
            traite_le = NOW()
        WHERE mission_id = v_mission.id
        AND statut IN ('EN_ATTENTE', 'PROPOSEE');
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_candidatures_refusees := v_candidatures_refusees + v_rows;

        INSERT INTO notifications (
            destinataire_id, type_destinataire, type, titre, corps, lien,
            type_ressource, id_ressource
        ) VALUES (
            v_mission.etablissement_id,
            'ETABLISSEMENT',
            'MISSION_NON_POURVUE',
            'Mission expiree (non pourvue)',
            'Votre mission "' || v_mission.intitule || '" n''a trouve aucun soignant et est passee en expiree. Vous pouvez la republier depuis votre espace.',
            '/etablissement/missions/' || v_mission.id,
            'mission',
            v_mission.id
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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_basculer_litiges_revue_admin_timeout()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_litige RECORD;
  v_count INT := 0;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  FOR v_litige IN
    SELECT id, soignant_id, etablissement_id FROM litiges
    WHERE statut = 'MEDIATION_EN_COURS'
      AND cree_le < NOW() - INTERVAL '7 days'
      AND (accord_soignant_le IS NULL OR accord_etablissement_le IS NULL)
  LOOP
    UPDATE litiges SET statut = 'REVUE_ADMIN' WHERE id = v_litige.id;

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES
      (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_MEDIATION',
       '⚠️ Litige basculé en revue admin',
       'La période de médiation de 7 jours est écoulée sans accord mutuel. Un administrateur va trancher.',
       '/soignant/litiges'),
      (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_MEDIATION',
       '⚠️ Litige basculé en revue admin',
       'La période de médiation de 7 jours est écoulée sans accord mutuel. Un administrateur va trancher.',
       '/etablissement/litiges');

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_litige.id, p_type_acteur := 'SYSTEME',
      p_action := 'MEDIATION_REVUE_ADMIN_DEMANDEE',
      p_type_ressource := 'litige', p_id_ressource := v_litige.id,
      p_details := jsonb_build_object('raison', 'timeout_7_jours_sans_accord')
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_award_badges_swipe()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total_swipes integer;
BEGIN
  SELECT count(*) INTO v_total_swipes
    FROM public.swipes
   WHERE soignant_id = NEW.soignant_id;

  IF v_total_swipes = 1 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'PREMIER_SWIPE')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  IF v_total_swipes = 50 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'EXPLORATEUR')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  IF v_total_swipes = 200 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'TOP_SWIPER')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  IF NEW.direction = 'SUPER_LIKE' THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'PREMIER_SUPER_LIKE')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_award_badges_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_had_swipe boolean;
  v_total_matches_via_swipe integer;
BEGIN
  -- Match détecté uniquement quand la candidature passe à ACCEPTEE
  IF NEW.statut <> 'ACCEPTEE' OR OLD.statut = 'ACCEPTEE' THEN
    RETURN NEW;
  END IF;

  -- Vérifier qu'un swipe LIKE/SUPER_LIKE existe pour cette mission + soignant
  SELECT EXISTS (
    SELECT 1 FROM public.swipes
     WHERE soignant_id = NEW.soignant_id
       AND mission_id = NEW.mission_id
       AND direction IN ('LIKE', 'SUPER_LIKE')
  ) INTO v_had_swipe;

  IF NOT v_had_swipe THEN
    RETURN NEW;
  END IF;

  -- PREMIER_MATCH (idempotent via UNIQUE)
  INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
    VALUES (NEW.soignant_id, 'PREMIER_MATCH', jsonb_build_object('mission_id', NEW.mission_id))
    ON CONFLICT (soignant_id, badge_type) DO NOTHING;

  -- Compter total matches via swipe pour MATCH_KING_QUEEN
  SELECT count(*) INTO v_total_matches_via_swipe
    FROM public.candidatures c
   WHERE c.soignant_id = NEW.soignant_id
     AND c.statut = 'ACCEPTEE'
     AND EXISTS (
       SELECT 1 FROM public.swipes s
        WHERE s.soignant_id = c.soignant_id
          AND s.mission_id = c.mission_id
          AND s.direction IN ('LIKE', 'SUPER_LIKE')
     );

  IF v_total_matches_via_swipe >= 10 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
      VALUES (
        NEW.soignant_id,
        'MATCH_KING_QUEEN',
        jsonb_build_object('total_matches', v_total_matches_via_swipe)
      )
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_bfa(p_etablissement_id uuid DEFAULT NULL::uuid, p_groupe_id uuid DEFAULT NULL::uuid, p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_missions INTEGER;
    v_commissions NUMERIC;
    v_palier RECORD;
    v_taux NUMERIC := 0;
    v_montant NUMERIC := 0;
    v_palier_nom TEXT := 'AUCUN';
BEGIN
    IF p_groupe_id IS NOT NULL THEN
        -- Cumuler pour tout le groupe
        SELECT COUNT(*), COALESCE(SUM(montant_commission_ht), 0)
        INTO v_missions, v_commissions
        FROM missions m
        JOIN etablissements e ON e.id = m.etablissement_id
        WHERE e.groupe_sante_id = p_groupe_id
          AND m.statut = 'TERMINEE'
          AND EXTRACT(YEAR FROM m.fin_le) = p_annee;
    ELSIF p_etablissement_id IS NOT NULL THEN
        SELECT COUNT(*), COALESCE(SUM(montant_commission_ht), 0)
        INTO v_missions, v_commissions
        FROM missions
        WHERE etablissement_id = p_etablissement_id
          AND statut = 'TERMINEE'
          AND EXTRACT(YEAR FROM fin_le) = p_annee;
    END IF;

    -- Trouver le palier
    SELECT * INTO v_palier
    FROM paliers_bfa
    WHERE est_actif = TRUE
      AND missions_min <= v_missions
      AND (missions_max IS NULL OR missions_max >= v_missions)
    ORDER BY ordre DESC LIMIT 1;

    IF v_palier.id IS NOT NULL THEN
        v_taux := v_palier.taux_bfa;
        v_montant := ROUND(v_commissions * (v_taux / 100.0), 2);
        v_palier_nom := v_palier.nom;
    END IF;

    -- Upsert dans bfa_suivi
    IF p_groupe_id IS NOT NULL THEN
        INSERT INTO bfa_suivi (groupe_id, annee, missions_cumulees, commissions_cumulees,
            palier_bfa, taux_bfa, montant_bfa, calcule_le)
        VALUES (p_groupe_id, p_annee, v_missions, v_commissions,
            v_palier_nom, v_taux, v_montant, NOW())
        ON CONFLICT (groupe_id, annee) DO UPDATE SET
            missions_cumulees = v_missions,
            commissions_cumulees = v_commissions,
            palier_bfa = v_palier_nom,
            taux_bfa = v_taux,
            montant_bfa = v_montant,
            calcule_le = NOW();
    ELSIF p_etablissement_id IS NOT NULL THEN
        INSERT INTO bfa_suivi (etablissement_id, annee, missions_cumulees, commissions_cumulees,
            palier_bfa, taux_bfa, montant_bfa, calcule_le)
        VALUES (p_etablissement_id, p_annee, v_missions, v_commissions,
            v_palier_nom, v_taux, v_montant, NOW())
        ON CONFLICT (etablissement_id, annee) DO UPDATE SET
            missions_cumulees = v_missions,
            commissions_cumulees = v_commissions,
            palier_bfa = v_palier_nom,
            taux_bfa = v_taux,
            montant_bfa = v_montant,
            calcule_le = NOW();
    END IF;

    RETURN jsonb_build_object(
        'annee', p_annee,
        'missions', v_missions,
        'commissions_ht', v_commissions,
        'palier', v_palier_nom,
        'taux_bfa', v_taux,
        'montant_bfa', v_montant
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_bloquer_delete_doc_verifie()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Service role + admin passthrough
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN OLD; END IF;
    IF auth.uid() IS NULL THEN RETURN OLD; END IF;
    IF est_admin() THEN RETURN OLD; END IF;

    -- Bloquer suppression de documents vérifiés
    IF OLD.statut_verification = 'VERIFIE' THEN
        RAISE EXCEPTION 'Impossible de supprimer un document vérifié. Contactez le support.';
    END IF;

    RETURN OLD;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_block_audit_log_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$ BEGIN RAISE EXCEPTION 'DELETE interdit sur invoice_audit_log (traçabilité fiscale)'; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_block_audit_log_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$ BEGIN RAISE EXCEPTION 'UPDATE interdit sur invoice_audit_log (traçabilité fiscale)'; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_block_bulletin_paie_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_role text := current_setting('role', true);
  v_is_admin boolean := COALESCE((SELECT public.est_admin()), false);
BEGIN
  IF v_role = 'service_role' OR v_is_admin THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'Bulletin de paie % : suppression interdite (conservation 5 ans art. L3243-4 CTW)', OLD.numero_bulletin;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_bp_passage_paye_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  -- Quand un paiement passe à confirme_par_soignant=true (ou statut='CONFIRME'),
  -- on flippe le bulletin lié à la même mission en PAYE (best-effort).
  IF (NEW.confirme_par_soignant = true AND COALESCE(OLD.confirme_par_soignant, false) = false)
     OR (NEW.statut = 'CONFIRME' AND COALESCE(OLD.statut, '') <> 'CONFIRME') THEN
    BEGIN
      UPDATE public.bulletins_paie
      SET statut = 'PAYE',
          date_paiement = COALESCE(NEW.date_paiement, CURRENT_DATE)
      WHERE mission_id = NEW.mission_id
        AND statut = 'EMIS';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_bp_passage_paye_trg: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_blocage_publication_etab(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v RECORD;
BEGIN
  IF est_admin() THEN
    RETURN NULL;
  END IF;

  IF p_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Acces refuse');
  END IF;

  SELECT peut_publier_missions, statut_verification, contrat_valide,
         bloque_auto_le, bloque_auto_raisons,
         finess_verifie, rattachement_verifie
    INTO v
  FROM public.etablissements WHERE id = p_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  IF v.peut_publier_missions IS NOT TRUE THEN
    IF v.statut_verification = 'EN_ATTENTE' THEN
      RETURN jsonb_build_object('error', 'Votre etablissement est en attente de verification. Vous pourrez publier des missions une fois verifie.');
    ELSIF v.statut_verification = 'REJETE' THEN
      RETURN jsonb_build_object('error', 'Votre etablissement a ete rejete. Contactez support@jolene.app.');
    ELSIF v.statut_verification = 'SUSPENDU' THEN
      RETURN jsonb_build_object('error', 'Votre compte est suspendu.');
    ELSE
      RETURN jsonb_build_object('error', 'Votre etablissement doit etre verifie avant de publier des missions.');
    END IF;
  END IF;

  IF v.finess_verifie IS NOT TRUE OR v.rattachement_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'VERIFICATION_INCOMPLETE',
      'message', 'La verification de votre etablissement est incomplete : le numero FINESS et le rattachement de votre representant doivent etre verifies avant de publier des missions.',
      'finess_verifie', COALESCE(v.finess_verifie, false),
      'rattachement_verifie', COALESCE(v.rattachement_verifie, false)
    );
  END IF;

  IF v.bloque_auto_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'PUBLICATION_SUSPENDUE',
      'message', 'Publication de nouvelles missions suspendue en raison de retards de paiement. Regularisez vos obligations pour reactiver votre compte.',
      'bloque_auto_le', v.bloque_auto_le,
      'raisons', v.bloque_auto_raisons
    );
  END IF;

  IF v.contrat_valide IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Votre contrat de service Jolene doit etre valide avant de publier des missions.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.factures
    WHERE etablissement_id = p_etab_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND date_echeance < CURRENT_DATE
  ) THEN
    RETURN jsonb_build_object('error', 'Vous avez des factures impayees. Veuillez regulariser.');
  END IF;

  RETURN NULL;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_booster_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_prix numeric;
  v_nb int := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    INTO v_m
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Seule une mission ouverte peut être boostée.'); END IF;
  IF v_m.boostee_le IS NOT NULL THEN RETURN jsonb_build_object('error', 'Cette mission est déjà boostée.'); END IF;

  v_prix := public.fn_param_num('mission_boost_prix_ht', 0);

  UPDATE missions SET boostee_le = NOW(), montant_boost_ht = COALESCE(v_prix, 0), modifie_le = NOW()
   WHERE id = p_mission_id;

  WITH cibles AS (
    SELECT s.id
    FROM soignants s
    WHERE s.profession = v_m.profession_requise
      AND s.supprime_le IS NULL
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND (v_m.type_contrat_recherche = 'TOUS'
           OR (v_m.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice,'SALARIE') IN ('SALARIE','MIXTE'))
           OR (v_m.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice,'SALARIE') IN ('LIBERAL','MIXTE')))
      AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = v_m.id AND c.soignant_id = s.id)
      AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
           OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
              <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
    LIMIT 50
  )
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  SELECT id, 'MISSION_A_POURVOIR',
    '🚀 Mission mise en avant près de chez vous',
    fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
    TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
    COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L''établissement recherche activement.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT'
  FROM cibles;
  GET DIAGNOSTICS v_nb = ROW_COUNT;

  RETURN jsonb_build_object('success', TRUE, 'soignants_notifies', v_nb, 'prix_ht', COALESCE(v_prix, 0));
END;
$function$
