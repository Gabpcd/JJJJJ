-- B9 (lot 5 B5b) — visibilité établissement par permission. NE PAS MERGER sans
-- le go explicite de Gabrielle (SECURITY DEFINER).
--
-- Sources : pg_get_functiondef PROD relu en lecture seule le 02/11/2026 ; les
-- md5(prosrc) LIVE sont identiques à supabase/schema/public.sql (re-baseline du
-- 01/11/2026). Chaque corps ci-dessous est le corps LIVE avec des ajouts
-- minimaux marqués « B5b ». Aucune table, aucune donnée, aucun GRANT/REVOKE :
-- CREATE OR REPLACE conserve propriétaire, ACL et commentaires.
--
-- 1. fn_etat_pointage_mission : code_pointage_actif seulement si la permission
--    « pointage » est accordée (LECTURE_SEULE garde l'état) ; un NULL dans la
--    garde d'accès vaut désormais refus.
-- 2. fn_stats_dashboard_etablissement : commissions_cumulees et
--    commissions_impayees à null sans lecture_paiement ni paiement ;
--    candidatures_recentes à null sans lecture_candidatures.
-- 3. fn_mon_etablissement_complet : stripe_customer_id, stripe_account_id et
--    iban_last4 à null sans lecture_paiement ni paiement.
-- Les rôles habilités reçoivent exactement les mêmes réponses qu'avant.

DO $preflight_b5b$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      (1, 'fn_etat_pointage_mission(uuid)', '3fe46580ddb6d871b4331e41a31a9e05', 's', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN'),
      (2, 'fn_stats_dashboard_etablissement()', '3b6e1d770f15c3d788236f2b57b77a9a', 'v', ARRAY['search_path=public']::text[], 'RPC_UTILISATEUR_AUTH_INTERNE'),
      (3, 'fn_mon_etablissement_complet()', 'adec3cf8c4d9bc8c317500222ed2675d', 'v', ARRAY['search_path=pg_catalog, public']::text[], 'RPC_UTILISATEUR_AUTH_INTERNE'),
      -- Matrice des permissions et résolution du tenant dont dépend la garde.
      (4, 'fn_a_permission_etablissement(text,uuid)', '1ee98c0e7094db4e98277b85ce71c6ec', 's', ARRAY['search_path=pg_catalog, public, auth']::text[], NULL),
      (5, 'fn_role_etablissement_courant(uuid)', 'ceb4e333f4b7f69a3be422b9753b559a', 's', ARRAY['search_path=pg_catalog, public, auth']::text[], NULL),
      (6, 'mon_etablissement_id()', 'dc3ef839d2920fb33cf6d7b320842c10', 's', ARRAY['search_path=pg_catalog, public, auth']::text[], NULL)
    ) AS t(ordre, signature, ancien_md5, volatilite, config, categorie)
    ORDER BY ordre
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile, p.proconfig, p.proacl,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure('public.' || v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.ancien_md5
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.provolatile::text IS DISTINCT FROM v_attendu.volatilite
      OR v_proc.proconfig IS DISTINCT FROM v_attendu.config
    THEN
      RAISE EXCEPTION 'VISIBILITE_ETAB_PREFLIGHT_SOURCE_DRIFT: %', v_attendu.signature;
    END IF;
    IF v_attendu.categorie IS NOT NULL THEN
      IF pg_catalog.has_function_privilege('anon', v_proc.oid, 'EXECUTE')
        OR NOT pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')
        OR NOT pg_catalog.has_function_privilege('service_role', v_proc.oid, 'EXECUTE')
      THEN
        RAISE EXCEPTION 'VISIBILITE_ETAB_PREFLIGHT_ACL_DRIFT: %', v_attendu.signature;
      END IF;
      IF (SELECT pg_catalog.count(*) FROM private.security_definer_inventory i
           WHERE i.signature IN (v_attendu.signature, 'public.' || v_attendu.signature)) <> 1
        OR NOT EXISTS (
          SELECT 1 FROM private.security_definer_inventory i
           WHERE i.signature = v_attendu.signature
             AND i.categorie = v_attendu.categorie
             AND i.definition_md5 = v_attendu.ancien_md5)
      THEN
        RAISE EXCEPTION 'VISIBILITE_ETAB_PREFLIGHT_INVENTORY_DRIFT: %', v_attendu.signature;
      END IF;
    END IF;
  END LOOP;

  -- ACL exactes avant redéfinition, comparées après (même transaction).
  CREATE TEMP TABLE _visibilite_etab_acl_avant ON COMMIT DROP AS
    SELECT p.oid, p.proacl::text AS acl
      FROM pg_catalog.pg_proc p
     WHERE p.oid IN (
       pg_catalog.to_regprocedure('public.fn_etat_pointage_mission(uuid)'),
       pg_catalog.to_regprocedure('public.fn_stats_dashboard_etablissement()'),
       pg_catalog.to_regprocedure('public.fn_mon_etablissement_complet()'));
END
$preflight_b5b$;

CREATE OR REPLACE FUNCTION public.fn_etat_pointage_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $etat_pointage$
DECLARE
  v_mission RECORD;
  v_is_etab boolean;
  v_is_soignant boolean;
  v_peut_voir_code boolean := false;
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

  -- B5b : un NULL (compte sans établissement, mission non affectée, session
  -- sans identité) vaut refus ; il laissait lire l'état de toute mission.
  IF NOT COALESCE(v_is_etab, false) AND NOT COALESCE(v_is_soignant, false) THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  -- B5b : le code n'est servi qu'aux membres habilités au pointage
  -- (permission « pointage » ; LECTURE_SEULE garde l'état sans le code).
  IF v_is_etab IS TRUE THEN
    v_peut_voir_code := public.fn_a_permission_etablissement('pointage', v_mission.etablissement_id) IS TRUE;
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
    -- Visible uniquement par l'établissement habilité au pointage (l'affiche au soignant à pointer).
    'code_pointage_actif', CASE WHEN v_peut_voir_code THEN v_mission.code_pointage_actif ELSE NULL END,
    'est_etab', v_is_etab
  );
END;
$etat_pointage$;

CREATE OR REPLACE FUNCTION public.fn_stats_dashboard_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $stats_dashboard$
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
    v_lecture_finances BOOLEAN;
    v_lecture_candidatures BOOLEAN;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;

    -- B5b : montants réservés à la lecture financière (lecture_paiement ou
    -- paiement, comme canReadFinance du web) ; noms des candidats réservés à
    -- lecture_candidatures. Les clés restent présentes et valent null.
    v_lecture_finances := public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS TRUE
        OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS TRUE;
    v_lecture_candidatures := public.fn_a_permission_etablissement('lecture_candidatures', v_etab_id) IS TRUE;
    
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
        'commissions_cumulees', CASE WHEN v_lecture_finances THEN COALESCE((SELECT SUM(montant_ht) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0) END,
        'commissions_impayees', CASE WHEN v_lecture_finances THEN v_commissions_impayees END,
        'nb_factures_impayees', v_nb_factures_impayees,
        'pool_urgence_count', v_pool_urgence_count,
        'messages_non_lus', v_messages_non_lus,
        'missions_a_payer', v_missions_a_payer,
        'litiges_ouverts', v_litiges_ouverts,
        'candidatures_en_attente', (
            SELECT COUNT(*) FROM candidatures c JOIN missions m ON m.id = c.mission_id
            WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
        ),
        'candidatures_recentes', CASE WHEN v_lecture_candidatures THEN COALESCE((
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
        ), '[]'::JSONB) END,
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
$stats_dashboard$;

CREATE OR REPLACE FUNCTION public.fn_mon_etablissement_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $etablissement_complet$
DECLARE
  v_etab_id uuid := public.mon_etablissement_id();
  v_result jsonb;
  v_lecture_finances boolean;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  -- B5b : identifiants Stripe et suffixe IBAN réservés à la lecture financière
  -- (lecture_paiement ou paiement, comme canReadFinance du web). Les clés
  -- restent présentes et valent null ; rib_s3_key est inchangé (voir PR).
  v_lecture_finances := public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS TRUE
    OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS TRUE;

  SELECT row_to_json(e)::jsonb
  INTO v_result
  FROM (
    SELECT
      et.id, et.nom, et.siret, et.finess, et.type::text, et.groupe_sante_id,
      et.adresse_rue, et.adresse_ville, et.adresse_code_postal, et.adresse_departement,
      et.adresse_lat, et.adresse_lng, et.email_contact, et.telephone_contact,
      CASE WHEN v_lecture_finances THEN et.stripe_customer_id END AS stripe_customer_id,
      CASE WHEN v_lecture_finances THEN et.stripe_account_id END AS stripe_account_id,
      et.taux_commission_negocie,
      COALESCE(et.taux_commission_negocie, gs.taux_commission_negocie, 15) AS taux_commission_effectif,
      et.mode_facturation, et.mode_paiement_commission,
      et.palier_commission_id, et.missions_mois_precedent, et.palier_recalcule_le,
      et.chorus_pro_actif, et.chorus_pro_identifiant, et.delai_paiement_jours,
      et.formule_abonnement, et.convention_collective, et.couleur_theme, et.logo_url,
      et.contrat_url, et.contrat_uploade_le, et.contrat_valide,
      et.contrat_service_signe, et.contrat_service_signe_le,
      et.rib_s3_key, et.rib_ia_coherent,
      CASE WHEN v_lecture_finances THEN et.iban_last4 END AS iban_last4, et.sms_actif,
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
$etablissement_complet$;

-- Aucun GRANT ni REVOKE : seules les empreintes des trois entrées déjà
-- recensées sont mises à jour, catégorie et justification inchangées.
DO $postflight_b5b$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      (1, 'fn_etat_pointage_mission(uuid)', '3fe46580ddb6d871b4331e41a31a9e05', '1188abb6a94766bbc7f7a8dc6d48c1ff', 's', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN'),
      (2, 'fn_stats_dashboard_etablissement()', '3b6e1d770f15c3d788236f2b57b77a9a', '1d66498685ed0ee237625b8e1975c0a3', 'v', ARRAY['search_path=public']::text[], 'RPC_UTILISATEUR_AUTH_INTERNE'),
      (3, 'fn_mon_etablissement_complet()', 'adec3cf8c4d9bc8c317500222ed2675d', '3aebe891df768a48ac72145b2c9db9a5', 'v', ARRAY['search_path=pg_catalog, public']::text[], 'RPC_UTILISATEUR_AUTH_INTERNE')
    ) AS t(ordre, signature, ancien_md5, nouveau_md5, volatilite, config, categorie)
    ORDER BY ordre
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile, p.proconfig, p.proacl,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure('public.' || v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.nouveau_md5
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.provolatile::text IS DISTINCT FROM v_attendu.volatilite
      OR v_proc.proconfig IS DISTINCT FROM v_attendu.config
      OR v_proc.proacl::text IS DISTINCT FROM (
        SELECT a.acl FROM pg_temp._visibilite_etab_acl_avant a WHERE a.oid = v_proc.oid)
      OR pg_catalog.has_function_privilege('anon', v_proc.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('service_role', v_proc.oid, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'VISIBILITE_ETAB_POSTFLIGHT_DRIFT: %', v_attendu.signature;
    END IF;
    UPDATE private.security_definer_inventory i
       SET definition_md5 = v_attendu.nouveau_md5, recense_le = pg_catalog.now()
     WHERE i.signature = v_attendu.signature
       AND i.categorie = v_attendu.categorie
       AND i.definition_md5 = v_attendu.ancien_md5;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'VISIBILITE_ETAB_INVENTORY_NOT_UPDATED: %', v_attendu.signature;
    END IF;
  END LOOP;
END
$postflight_b5b$;

NOTIFY pgrst, 'reload schema';
