-- Fixture du seul banc visibilite-etablissement-permission-isolated.test.sql.
-- Corps LIVE (production, md5(prosrc) relus en lecture seule le 02/11/2026,
-- identiques à supabase/schema/public.sql) des gardes d'identité et des trois
-- RPC AVANT la migration B5b, propriétaire et ACL compris. Aucune donnée.
-- Regénération : extraire les mêmes blocs de public.sql ; le test Node
-- tests/node/visibilite-etablissement-permission.node.mjs compare chaque corps.

-- fn_compte_auth_actif — supabase/schema/public.sql l.23877-23896, md5(prosrc) 8246c4c1f1b0a8053adb176a06c96766
CREATE OR REPLACE FUNCTION "public"."fn_compte_auth_actif"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
    AS $$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = auth.uid()
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND NOT EXISTS (
        SELECT 1 FROM public.soignants s
        WHERE s.id = u.id AND s.supprime_le IS NOT NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.etablissements e
        WHERE e.id = u.id AND e.supprime_le IS NOT NULL
      )
  ), false);
$$;
ALTER FUNCTION "public"."fn_compte_auth_actif"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."fn_compte_auth_actif"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_compte_auth_actif"() TO "service_role";
GRANT ALL ON FUNCTION "public"."fn_compte_auth_actif"() TO "authenticated";

-- est_admin_valide — supabase/schema/public.sql l.4852-4881, md5(prosrc) 7954bb4e079865c63c4ba1096bd1fc76
CREATE OR REPLACE FUNCTION "public"."est_admin_valide"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
    AS $$
  SELECT COALESCE(EXISTS (
    SELECT 1
      FROM auth.users u
     WHERE u.id = auth.uid()
       AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
       AND u.deleted_at IS NULL
       AND (u.banned_until IS NULL OR u.banned_until <= now())
       AND u.email_confirmed_at IS NOT NULL
       AND EXISTS (
         SELECT 1
           FROM public.equipe_admin ea
          WHERE ea.user_id = u.id
            AND ea.actif IS TRUE
            AND ARRAY[
              'Dashboard',
              'Utilisateurs',
              'Missions',
              'Litiges & contrats',
              'Finances',
              'Messagerie',
              'Conformité & Technique',
              'Fondateur'
            ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])
       )
  ), false);
$$;
ALTER FUNCTION "public"."est_admin_valide"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."est_admin_valide"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."est_admin_valide"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."est_admin_valide"() TO "service_role";
COMMENT ON FUNCTION "public"."est_admin_valide"() IS 'Garde admin Jolene : compte Auth actif et confirmé, rôle ADMIN_PLATEFORME et registre equipe_admin actif avec les 8 groupes. Aucun MFA/AAL2 requis.';

-- est_admin — supabase/schema/public.sql l.4830-4835, md5(prosrc) ef86d65809c3f76a1ac08eb737796fad
CREATE OR REPLACE FUNCTION "public"."est_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
    AS $$
  SELECT public.est_admin_valide();
$$;
ALTER FUNCTION "public"."est_admin"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."est_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."est_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."est_admin"() TO "service_role";

-- fn_role_etablissement_courant — supabase/schema/public.sql l.55433-55473, md5(prosrc) ceb4e333f4b7f69a3be422b9753b559a
CREATE OR REPLACE FUNCTION "public"."fn_role_etablissement_courant"("p_etablissement_id" "uuid" DEFAULT NULL::"uuid") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN NULL;
  END IF;

  SELECT m.role INTO v_role
  FROM public.membres_etablissement m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.user_id = v_uid
    AND m.actif = true
    AND e.supprime_le IS NULL
    AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id)
  ORDER BY CASE m.role WHEN 'PROPRIETAIRE' THEN 1 WHEN 'ADMIN_GROUPE' THEN 2 ELSE 3 END
  LIMIT 1;

  IF v_role IS NOT NULL THEN
    RETURN v_role;
  END IF;

  -- Compatibilite des comptes historiques : le compte Auth et la ligne
  -- etablissement partagent le meme UUID. Un simple etablissement_id stale
  -- dans app_metadata ne suffit jamais a recreer une appartenance revoquee.
  SELECT 'PROPRIETAIRE' INTO v_role
  FROM auth.users u
  JOIN public.etablissements e ON e.id = u.id
  WHERE u.id = v_uid
    AND u.raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT')
    AND e.supprime_le IS NULL
    AND (p_etablissement_id IS NULL OR e.id = p_etablissement_id)
  LIMIT 1;

  RETURN v_role;
END;
$$;
ALTER FUNCTION "public"."fn_role_etablissement_courant"("p_etablissement_id" "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."fn_role_etablissement_courant"("p_etablissement_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_role_etablissement_courant"("p_etablissement_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."fn_role_etablissement_courant"("p_etablissement_id" "uuid") TO "authenticated";

-- fn_a_permission_etablissement — supabase/schema/public.sql l.4905-4936, md5(prosrc) 1ee98c0e7094db4e98277b85ce71c6ec
CREATE OR REPLACE FUNCTION "public"."fn_a_permission_etablissement"("p_permission" "text", "p_etablissement_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
    AS $$
DECLARE
  v_role text;
BEGIN
  IF public.est_admin() THEN RETURN true; END IF;
  v_role := public.fn_role_etablissement_courant(p_etablissement_id);
  IF v_role IS NULL THEN RETURN false; END IF;

  RETURN CASE lower(COALESCE(p_permission, ''))
    WHEN 'gerer_equipe' THEN v_role = 'PROPRIETAIRE'
    WHEN 'supprimer_compte' THEN v_role = 'PROPRIETAIRE'
    WHEN 'profil_etab' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    WHEN 'paiement' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    WHEN 'missions' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'candidatures' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'contrats' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'pointage' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY')
    WHEN 'rh' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')
    WHEN 'api' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
    WHEN 'lecture_missions' THEN true
    WHEN 'lecture_candidatures' THEN v_role <> 'POINTAGE_ONLY'
    WHEN 'lecture_contrats' THEN v_role <> 'POINTAGE_ONLY'
    WHEN 'lecture_paiement' THEN v_role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'LECTURE_SEULE')
    WHEN 'lecture_pointage' THEN true
    WHEN 'lecture' THEN true
    ELSE false
  END;
END;
$$;
ALTER FUNCTION "public"."fn_a_permission_etablissement"("p_permission" "text", "p_etablissement_id" "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."fn_a_permission_etablissement"("p_permission" "text", "p_etablissement_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_a_permission_etablissement"("p_permission" "text", "p_etablissement_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."fn_a_permission_etablissement"("p_permission" "text", "p_etablissement_id" "uuid") TO "authenticated";

-- mon_etablissement_id — supabase/schema/public.sql l.67092-67119, md5(prosrc) dc3ef839d2920fb33cf6d7b320842c10
CREATE OR REPLACE FUNCTION "public"."mon_etablissement_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'auth'
    AS $$
  SELECT COALESCE(
    (
      SELECT m.etablissement_id
      FROM public.membres_etablissement m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.user_id = auth.uid()
        AND m.actif = true
        AND e.supprime_le IS NULL
      ORDER BY CASE m.role WHEN 'PROPRIETAIRE' THEN 1 WHEN 'ADMIN_GROUPE' THEN 2 ELSE 3 END
      LIMIT 1
    ),
    (
      SELECT e.id
      FROM auth.users u
      JOIN public.etablissements e ON e.id = u.id
      WHERE u.id = auth.uid()
        AND u.deleted_at IS NULL
        AND (u.banned_until IS NULL OR u.banned_until <= now())
        AND u.raw_app_meta_data ->> 'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT')
        AND e.supprime_le IS NULL
      LIMIT 1
    )
  );
$$;
ALTER FUNCTION "public"."mon_etablissement_id"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."mon_etablissement_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mon_etablissement_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mon_etablissement_id"() TO "service_role";

-- fn_etat_pointage_mission — supabase/schema/public.sql l.35145-35192, md5(prosrc) 3fe46580ddb6d871b4331e41a31a9e05
CREATE OR REPLACE FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_mission RECORD;
  v_is_etab boolean;
  v_is_soignant boolean;
  v_segments jsonb;
  v_segment_ouvert boolean;
BEGIN
  SELECT id, etablissement_id, soignant_assigne_id, statut,
         code_pointage_actif, prochain_type_scan, nb_scans, intitule
    INTO v_mission
    FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id();
  v_is_soignant := v_mission.soignant_assigne_id = auth.uid();

  IF NOT v_is_etab AND NOT v_is_soignant THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  -- Segments effectifs (les vrais créneaux travaillés, base de la paie)
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object('id', id, 'debut', debut, 'fin', fin) ORDER BY debut), '[]'::jsonb),
    bool_or(fin IS NULL)
    INTO v_segments, v_segment_ouvert
    FROM mission_creneaux
    WHERE mission_id = p_mission_id AND type_creneau = 'EFFECTIF';

  RETURN jsonb_build_object(
    'statut', v_mission.statut,
    'intitule', v_mission.intitule,
    'prochain_type_scan', v_mission.prochain_type_scan,
    'nb_scans', v_mission.nb_scans,
    'segment_ouvert', COALESCE(v_segment_ouvert, false),
    'segments', v_segments,
    -- Visible uniquement par l'établissement (l'affiche au soignant à pointer).
    'code_pointage_actif', CASE WHEN v_is_etab THEN v_mission.code_pointage_actif ELSE NULL END,
    'est_etab', v_is_etab
  );
END;
$$;
ALTER FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."fn_etat_pointage_mission"("p_mission_id" "uuid") TO "authenticated";

-- fn_stats_dashboard_etablissement — supabase/schema/public.sql l.57610-57706, md5(prosrc) 3b6e1d770f15c3d788236f2b57b77a9a
CREATE OR REPLACE FUNCTION "public"."fn_stats_dashboard_etablissement"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
    
    SELECT COALESCE(SUM(montant_a_payer), 0), COUNT(*)
    INTO v_commissions_impayees, v_nb_factures_impayees
    FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
      AND type_document IN ('FACTURE', 'FACTURE_COMPLEMENTAIRE')
      AND montant_a_payer > 0 AND NOT rapprochement_paiement_requis;
    
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
$$;
ALTER FUNCTION "public"."fn_stats_dashboard_etablissement"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."fn_stats_dashboard_etablissement"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_stats_dashboard_etablissement"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_stats_dashboard_etablissement"() TO "service_role";

-- fn_mon_etablissement_complet — supabase/schema/public.sql l.44594-44649, md5(prosrc) adec3cf8c4d9bc8c317500222ed2675d
CREATE OR REPLACE FUNCTION "public"."fn_mon_etablissement_complet"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  SELECT row_to_json(e)::jsonb
  INTO v_result
  FROM (
    SELECT
      et.id, et.nom, et.siret, et.finess, et.type::text, et.groupe_sante_id,
      et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
      et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
      et.stripe_customer_id, et.stripe_account_id,
      et.taux_commission_negocie,
      COALESCE(et.taux_commission_negocie, gs.taux_commission_negocie, 15) AS taux_commission_effectif,
      et.mode_facturation, et.mode_paiement_commission,
      et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
      et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
      et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
      et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
      et.contrat_service_signe, et.contrat_service_signe_le,
      et.rib_s3_key, et.rib_ia_coherent, et.iban_last4, et.sms_actif,
      et.taux_majoration_nuit_pourcent, et.taux_majoration_dimanche_pourcent,
      et.taux_majoration_ferie_pourcent,
      et.est_secteur_public, et.peut_publier_missions, et.statut_verification,
      et.note_moyenne, et.nb_evaluations, et.description, et.horaires_ouverture,
      et.rist_plafond_actif, et.rist_taux_base_horaire,
      et.bloque_auto_le, et.bloque_auto_raisons,
      et.cree_le, et.modifie_le,
      CASE WHEN pc.id IS NOT NULL THEN jsonb_build_object(
        'id', pc.id,
        'nom', pc.nom,
        'taux_commission', pc.taux_commission,
        'missions_min', pc.missions_min
      ) ELSE NULL END AS paliers_commission,
      CASE WHEN gs.id IS NOT NULL THEN jsonb_build_object(
        'id', gs.id,
        'nom', gs.nom,
        'taux_commission_negocie', gs.taux_commission_negocie
      ) ELSE NULL END AS groupes_sante
    FROM public.etablissements et
    LEFT JOIN public.paliers_commission pc ON pc.id = et.palier_commission_id
    LEFT JOIN public.groupes_sante gs ON gs.id = et.groupe_sante_id
    WHERE et.id = v_etab_id
  ) e;

  RETURN COALESCE(v_result, jsonb_build_object('error', 'Etablissement introuvable'));
END;
$$;
ALTER FUNCTION "public"."fn_mon_etablissement_complet"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."fn_mon_etablissement_complet"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_mon_etablissement_complet"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_mon_etablissement_complet"() TO "service_role";
COMMENT ON FUNCTION "public"."fn_mon_etablissement_complet"() IS 'Retourne le profil de l établissement courant, dont contrat_service_signe, source canonique du verrou de publication.';
