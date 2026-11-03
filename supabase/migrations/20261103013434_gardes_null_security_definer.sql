-- B9 (SECURITY DEFINER, autorisation) — gardes d'accès qui valaient NULL.
-- En attente du go explicite de Gabrielle : pas d'auto-merge (CLAUDE.md B9).
--
-- Motif. mon_etablissement_id() renvoie NULL pour un appelant sans
-- établissement actif (soignant, membre révoqué, service sans identité) et
-- est_admin_etablissement() renvoie NULL quand fn_role_etablissement_courant(NULL)
-- ne trouve aucun rôle. Dans une garde de refus écrite
--   IF x.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN refus
--   IF NOT (est_admin() OR x.etablissement_id = mon_etablissement_id()) THEN refus
-- la condition vaut NULL, PL/pgSQL ne prend pas la branche et la fonction
-- continue. Les 20 fonctions ci-dessous (SECURITY DEFINER, EXECUTE accordé à
-- authenticated) laissaient ainsi passer un soignant, ou un membre révoqué :
-- validation de sa propre présence (déclenche la file escrow), lecture des
-- codes de pointage statiques, code de secours et QR de pointage, téléphones
-- du pool urgence, données DPAE du contrat, numéro DPAE, rebooking, boost
-- facturé, garantie de remplacement, dépôt Chorus, facture de commission,
-- diffusion du pool, présences d'une mission d'un tiers, fiche établissement,
-- réclamation sur un événement de score d'établissement, honoraires et régime
-- de rétrocession.
--
-- Correctif. Une seule différence par fonction : la comparaison avec
-- mon_etablissement_id() (ou est_admin_etablissement(), ou auth.uid() quand
-- elle partage la garde) passe sous COALESCE(..., false). Un NULL vaut
-- désormais « pas d'accès » ; les appelants dont la comparaison valait déjà
-- true ou false (membre de l'établissement, membre d'un autre établissement,
-- soignant assigné là où il est attendu, administrateur plateforme) gardent
-- exactement le même résultat. Messages de refus, corps, propriétaire, ACL,
-- volatilité et search_path inchangés (CREATE OR REPLACE, aucun GRANT).
--
-- Contexte système. Quinze de ces fonctions n'ont pas de garde
-- auth.uid() IS NULL préalable : service_role et les crons, qui passaient par
-- le NULL, sont désormais refusés comme tout appelant sans établissement.
-- Aucun appelant système relu (cron.job LIVE, pg_proc hors
-- fn_regenerer_qr_mission et fn_creer_mission_multi_jours_v2 qui tournent sous
-- le JWT de l'utilisateur, edge functions, iOS, scripts) : pas de régression
-- attendue. Détail : docs/GARDES_NULL_SECURITY_DEFINER.md §2.
--
-- Sources : définitions LIVE production relues le 2026-11-03 en lecture seule
-- (md5(prosrc), pg_get_function_arguments, pg_get_function_result, proconfig,
-- has_function_privilege, private.security_definer_inventory). Les 20 corps
-- LIVE sont identiques à supabase/schema/public.sql (empreintes « avant »
-- ci-dessous). Toutes les gardes « avant » précèdent la première
-- redéfinition : une seule source divergente refuse la migration entière.
--
-- Hors périmètre, volontairement :
--   * fn_declarer_fin_retroactive : même défaut, corrigé par la PR B9
--     fix/scanner-code-sans-code-suivant (migration 20261102205212). La
--     redéfinir ici à partir du LIVE réintroduirait nouveau_code/nouveau_hmac
--     si cette migration passait après.
--   * fn_etat_pointage_mission : même défaut, corrigé par la PR B9 B5b
--     fix/visibilite-etablissement-par-permission (migration 20261102210943,
--     COALESCE à l'usage et code réservé à la permission « pointage »), partie
--     du même LIVE (md5 3fe46580…). La garder ici ferait échouer la seconde
--     PR mergée, quel que soit l'ordre.
--   * est_admin_etablissement() et les cinq triggers qui la nient
--     (dec_proteger_mission_soignant, dec_proteger_presence_soignant,
--     fn_protect_mission_financials, fn_protect_presence_integrity,
--     fn_protect_contrat_integrity) : corriger le helper réactiverait ces
--     triggers pour tous les soignants et pour le contexte système, avec des
--     régressions identifiées (désistement fn_annuler_mission_soignant :
--     soignant_assigne_id reverté). Volet séparé, instruit dans
--     docs/GARDES_NULL_SECURITY_DEFINER.md et verrouillé par
--     tests/node/gardes-null-security-definer.node.mjs.
--
-- Ordre de merge (docs/GARDES_NULL_SECURITY_DEFINER.md §7). Ce lot passe en
-- dernier des branches B9 du 02/11, dont les migrations le précèdent :
--   20261102204820 fix/score-matching-inconnu-null
--   20261102205212 fix/scanner-code-sans-code-suivant   (verrou : garde statique)
--   20261102205808 fix/contestation-paiement-soignant
--   20261102210943 fix/visibilite-etablissement-par-permission (B5b, verrou : garde statique)
-- Aucune ne redéfinit l'une des 20 fonctions ci-dessous. La garde statique
-- refuse ce lot tant que les correctifs scanner et B5b ne sont pas dans le
-- dépôt (entrées REVUES conditionnées à leur preuve). Si ce lot devait passer
-- avant l'une des quatre, la renommer après 20261103013434 (CLAUDE.md,
-- migrations règle 2) et repartir de son LIVE.
-- Garde statique : tests/node/gardes-null-security-definer.node.mjs.
-- Recette SQL sous ROLLBACK : tests/security/gardes-null-security-definer.test.sql.

DO $gardes_null_avant$
DECLARE
  r record;
  p record;
  n integer := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
    ('fn_valider_alerte_presence(uuid)', 'p_presence_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '05a6e15c497e28d6f94b9cd1c243c811', '1ff0c4c48ccd906f161e1a9174034505'),
    ('fn_codes_pointage_mission(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'ca8d9013f736db6d3dca03b595aecf48', '478bc3d59e15a1a1c844443863a86d49'),
    ('fn_generer_code_secours_mission(uuid,text)', 'p_mission_id uuid, p_type text DEFAULT ''UNIVERSEL''::text', 'jsonb', 'v', ARRAY['search_path=public, extensions']::text[], 'MIXTE_TENANT_ADMIN', '3fbae3ee7274f92165cccb0ab705bdcd', '76c8e19c6f16a642b968d91a7850752b'),
    ('fn_generer_qr_mission(uuid,text)', 'p_mission_id uuid, p_type text DEFAULT ''UNIVERSEL''::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '6196379d17503a467d24beeb038b8897', '75869cf50e34d68dd982a6714c010c0b'),
    ('fn_soignants_urgence(uuid)', 'p_mission_id uuid', 'TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '9dcc20b932437733fbbdf5474cd1b39e', '9b8f736b8f7fd19729e26cc56f28d2c4'),
    ('fn_generer_donnees_dpae(uuid)', 'p_contrat_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'fd81d58a2e18b98fe7f57d458b467079', '1070a34cb7025565225d732ed7ac3906'),
    ('fn_enregistrer_numero_dpae(uuid,text)', 'p_contrat_id uuid, p_dpae_numero text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '1f54235815e67141e4994cb9a604aa2b', '0d6fb5c6692759e3972746d8dbc196f9'),
    ('fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'p_soignant_id uuid, p_mission_modele_id uuid, p_debut timestamp with time zone, p_fin timestamp with time zone', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'd404ad86634519ac9a63b3202e52d2db', '53a208f0c1ee8c78a6faab262f47eaa4'),
    ('fn_booster_mission(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'c22963698c0cbfc4cd6de19bb474f520', 'e57ceb0273b02fab0215e2d33e251200'),
    ('fn_presences_detail_mission(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '5063c38138004b599a721412b029c5ff', '1f653d7d432a87a356f3f62910a7ee38'),
    ('fn_activer_garantie_mission(uuid,boolean)', 'p_mission_id uuid, p_actif boolean', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '4f170971145ed66ddad01805abebae6f', '00b0feecc9dfc4893a04bc94b584a013'),
    ('fn_deposer_chorus(uuid,text)', 'p_facture_id uuid, p_chorus_id text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '3a42d1cf3e8bb1aecedd28c4e0782cae', '8b310b8e4c6bbabd58b039a9e915c675'),
    ('fn_generer_facture(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '5314c8689cd382ad000be9e7a9df6b29', '078777ead10a6a4d500694551299622b'),
    ('fn_diffuser_pool_urgence(uuid)', 'p_mission_id uuid', 'integer', 'v', ARRAY['search_path=pg_catalog, public, private']::text[], 'MIXTE_TENANT_ADMIN', 'ba942f8cc9f7997930c5bdc9d32af9df', '07cd19c650da67e2b8128d32d0ffbfe6'),
    ('fn_etablissement_pour_mission(uuid)', 'p_etablissement_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '1f9bc93c9cf7e4b097ace3a78720c689', '55493a7014ae20761ebf86fdab938f1c'),
    ('fn_annuler_serie(uuid)', 'p_serie_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '71d57002916d856d6530d90f749676e1', '06255e7b0d58441d46ac69798276dfae'),
    ('fn_assigner_mission_admin(uuid,uuid,text)', 'p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '502101a70656f3b5e5eb01c14f23d5de', '3a3523b9ac79ebd8e34a5ef58e749de3'),
    ('fn_creer_reclamation_score(uuid,text,text,text,text)', 'p_evenement_id uuid, p_evenement_type text, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'RPC_UTILISATEUR_AUTH_INTERNE', '34855c0d2b9062792aa49dbafc32ae6b', '18be67db062364dadbd298fb90884947'),
    ('fn_declarer_honoraires_retrocession(uuid,numeric,text)', 'p_mission_id uuid, p_montant_honoraires numeric, p_justificatif_cle text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '093135e6e6086e183023c612aa7bfa92', '4223483a5500b8d865c4f529af6f1a99'),
    ('fn_definir_retrocession_mission(uuid,numeric)', 'p_mission_id uuid, p_pct numeric', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '89a25f4acaeed41f2850acea6d15530e', '52393260c791cbb5093278f303a93ebd')
    ) AS v(signature, arguments, resultat, volatilite, configuration, categorie, md5_avant, md5_apres)
  LOOP
    n := n + 1;
    SELECT * INTO p FROM pg_catalog.pg_proc
    WHERE oid = pg_catalog.to_regprocedure('public.' || r.signature);
    IF NOT FOUND OR pg_catalog.md5(p.prosrc) <> r.md5_avant
      OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> r.volatilite
      OR p.proconfig IS DISTINCT FROM r.configuration
      OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
      OR pg_catalog.pg_get_function_arguments(p.oid) <> r.arguments
      OR pg_catalog.pg_get_function_result(p.oid) <> r.resultat
      OR (SELECT count(*) FROM private.security_definer_inventory i
          WHERE i.signature = r.signature
            AND i.categorie = r.categorie
            AND i.definition_md5 = r.md5_avant) <> 1
      OR EXISTS (SELECT FROM private.security_definer_inventory i
                 WHERE i.signature = 'public.' || r.signature)
    THEN RAISE EXCEPTION 'GARDES_NULL_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT : %', r.signature; END IF;
    IF pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
      OR EXISTS (SELECT FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                 WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    THEN RAISE EXCEPTION 'GARDES_NULL_ACL_AVANT_DIVERGENTE : %', r.signature; END IF;
  END LOOP;
  IF n <> 20 THEN RAISE EXCEPTION 'GARDES_NULL_PERIMETRE_INCOMPLET : % fonctions', n; END IF;
END;
$gardes_null_avant$;

-- fn_valider_alerte_presence(uuid) : LIVE 05a6e15c497e28d6f94b9cd1c243c811 → 1ff0c4c48ccd906f161e1a9174034505
CREATE OR REPLACE FUNCTION public.fn_valider_alerte_presence(p_presence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
    v_presence RECORD;
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    SELECT p.*, m.etablissement_id FROM presences p 
    JOIN missions m ON m.id = p.mission_id 
    WHERE p.id = p_presence_id INTO v_presence;
    
    IF v_presence IS NULL THEN RETURN jsonb_build_object('error', 'Présence introuvable'); END IF;
    
    IF NOT COALESCE(v_presence.etablissement_id = v_etab_id, false) AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    UPDATE presences SET 
        valide_par_etablissement = TRUE, 
        valide_le = NOW()
    WHERE id = p_presence_id;
    
    RETURN jsonb_build_object('success', TRUE, 'message', 'Présence validée');
END;
$fonction$;

-- fn_codes_pointage_mission(uuid) : LIVE ca8d9013f736db6d3dca03b595aecf48 → 478bc3d59e15a1a1c844443863a86d49
CREATE OR REPLACE FUNCTION public.fn_codes_pointage_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_mission record;
BEGIN
  SELECT id, code_arrivee, code_depart, etablissement_id
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  IF v_mission.code_arrivee IS NULL THEN
    UPDATE missions SET
      code_arrivee = lpad(floor(random() * 1000000)::text, 6, '0'),
      code_depart = lpad(floor(random() * 1000000)::text, 6, '0')
    WHERE id = p_mission_id
    RETURNING code_arrivee, code_depart INTO v_mission.code_arrivee, v_mission.code_depart;
  END IF;

  RETURN jsonb_build_object(
    'code_arrivee', v_mission.code_arrivee,
    'code_depart', v_mission.code_depart
  );
END;
$fonction$;

-- fn_generer_code_secours_mission(uuid,text) : LIVE 3fbae3ee7274f92165cccb0ab705bdcd → 76c8e19c6f16a642b968d91a7850752b
CREATE OR REPLACE FUNCTION public.fn_generer_code_secours_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $fonction$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_code text;
  v_code_hash text;
  v_expire_le timestamptz;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, fin_le, statut INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;
  IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Invalider codes précédents non utilisés du même type
  UPDATE public.codes_secours_mission
  SET utilise = true, utilise_le = NOW()
  WHERE mission_id = p_mission_id AND type = p_type AND utilise = false;

  -- Générer 6 chiffres aléatoires (uniformément distribués 0-999999)
  v_code := lpad((floor(random() * 1000000))::text, 6, '0');
  v_code_hash := crypt(v_code, gen_salt('bf'));

  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.codes_secours_mission (mission_id, code_hash, type, expire_le, cree_par)
  VALUES (p_mission_id, v_code_hash, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_id;

  -- Audit (sans le code en clair !)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'code_secours_mission', v_id,
    jsonb_build_object('evenement', 'CODE_SECOURS_GENERE',
                        'mission_id', p_mission_id, 'type', p_type,
                        'expire_le', v_expire_le)
  );

  -- Retourne le code EN CLAIR (une seule fois — jamais re-affiché)
  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'code', v_code,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$fonction$;

-- fn_generer_qr_mission(uuid,text) : LIVE 6196379d17503a467d24beeb038b8897 → 75869cf50e34d68dd982a6714c010c0b
CREATE OR REPLACE FUNCTION public.fn_generer_qr_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_token text;
  v_expire_le timestamptz;
  v_qr_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, debut_le, fin_le, statut INTO v_mission
  FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;

  -- Auth : étab admin de la mission ou admin Jolene
  IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF v_mission.statut IN ('LITIGE', 'ANNULEE_PAR_ETABLISSEMENT', 'TERMINEE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INACTIVE');
  END IF;

  -- Désactiver les QR actifs précédents du même type
  UPDATE public.qr_codes_mission SET actif = false
  WHERE mission_id = p_mission_id AND type = p_type AND actif = true;

  -- Token = UUID v4 + suffix 16 chars random cryptographique
  v_token := gen_random_uuid()::text || '_' ||
             encode(extensions.gen_random_bytes(8), 'hex');

  -- Expiration : min(date_fin + 2h, NOW() + 7j)
  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.qr_codes_mission (mission_id, token, type, expire_le, cree_par)
  VALUES (p_mission_id, v_token, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_qr_id;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'qr_code_mission', v_qr_id,
    jsonb_build_object('evenement', 'QR_GENERE',
                        'mission_id', p_mission_id,
                        'type', p_type, 'expire_le', v_expire_le)
  );

  RETURN jsonb_build_object(
    'success', true,
    'qr_id', v_qr_id,
    'token', v_token,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$fonction$;

-- fn_soignants_urgence(uuid) : LIVE 9dcc20b932437733fbbdf5474cd1b39e → 9b8f736b8f7fd19729e26cc56f28d2c4
CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
 RETURNS TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_mission record;
BEGIN
  SELECT m.id, m.etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT (public.est_admin() OR COALESCE(v_mission.etablissement_id = public.mon_etablissement_id(), false)) THEN
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
$fonction$;

-- fn_generer_donnees_dpae(uuid) : LIVE fd81d58a2e18b98fe7f57d458b467079 → 1070a34cb7025565225d732ed7ac3906
CREATE OR REPLACE FUNCTION public.fn_generer_donnees_dpae(p_contrat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_uid uuid := auth.uid();
  v_payload jsonb;
  v_etab_id uuid;
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT cm.etablissement_id INTO v_etab_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR COALESCE(v_etab_id = mon_etablissement_id(), false)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'contrat_id', cm.id,
    'type_contrat', cm.type_contrat,
    'etablissement', jsonb_build_object(
      'nom', e.nom,
      'siret', e.siret,
      'naf', e.siret_code_naf,
      'adresse_rue', e.adresse_rue,
      'adresse_ville', e.adresse_ville,
      'adresse_code_postal', e.adresse_code_postal,
      'telephone', e.telephone_contact,
      'email', e.email_contact,
      'organisme_protection_sociale', 'URSSAF'
    ),
    'salarie', jsonb_build_object(
      'nom', s.nom,
      'prenom', s.prenom,
      'sexe', s.sexe,
      'date_naissance', s.date_naissance,
      'lieu_naissance_commune', s.lieu_naissance_commune,
      'lieu_naissance_departement', s.lieu_naissance_departement,
      'pays_naissance', COALESCE(s.pays_naissance, 'France'),
      'nationalite', COALESCE(s.nationalite, 'Française'),
      'numero_securite_sociale', COALESCE(s.numero_securite_sociale, s.numero_secu),
      'adresse_rue', s.adresse_rue,
      'adresse_code_postal', s.adresse_code_postal,
      'adresse_ville', s.adresse_ville,
      'profession', s.profession,
      'champs_a_completer_sur_net_entreprises', (
        SELECT COALESCE(jsonb_agg(m), '[]'::jsonb) FROM (
          SELECT 'sexe' AS m WHERE s.sexe IS NULL
          UNION ALL SELECT 'lieu_naissance_commune' WHERE s.lieu_naissance_commune IS NULL AND COALESCE(s.pays_naissance, 'France') = 'France'
          UNION ALL SELECT 'lieu_naissance_departement' WHERE s.lieu_naissance_departement IS NULL AND COALESCE(s.pays_naissance, 'France') = 'France'
          UNION ALL SELECT 'pays_naissance' WHERE s.pays_naissance IS NULL
          UNION ALL SELECT 'nationalite' WHERE s.nationalite IS NULL
          UNION ALL SELECT 'numero_securite_sociale' WHERE COALESCE(s.numero_securite_sociale, s.numero_secu) IS NULL
        ) t
      )
    ),
    'embauche', jsonb_build_object(
      'date_prevue', m.debut_le,
      'heure_prevue', to_char(m.debut_le, 'HH24:MI'),
      'date_fin', m.fin_le,
      'type_contrat', cm.type_contrat,
      'duree_heures_prevues', m.duree_heures
    ),
    'urssaf_url', 'https://www.net-entreprises.fr/declaration-prealable-embauche/',
    'note', 'Copiez ces données dans le formulaire DPAE Net-Entreprises. Les champs marqués dans champs_a_completer_sur_net_entreprises ne sont pas encore renseignés par le soignant — demandez-lui de compléter son profil ou saisissez-les manuellement.'
  )
  INTO v_payload
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = cm.etablissement_id
  JOIN public.soignants s ON s.id = cm.soignant_id
  WHERE cm.id = p_contrat_id;

  RETURN v_payload;
END;
$fonction$;

-- fn_enregistrer_numero_dpae(uuid,text) : LIVE 1f54235815e67141e4994cb9a604aa2b → 0d6fb5c6692759e3972746d8dbc196f9
CREATE OR REPLACE FUNCTION public.fn_enregistrer_numero_dpae(p_contrat_id uuid, p_dpae_numero text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_numero_trim text;
  v_soignant_id uuid;
  v_mission_id uuid;
  v_soignant_prenom text;
  v_etab_nom text;
  v_mission_intitule text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_dpae_numero IS NULL OR length(trim(p_dpae_numero)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Numéro DPAE requis');
  END IF;

  v_numero_trim := trim(p_dpae_numero);

  IF v_numero_trim !~ '^[A-Za-z0-9]{8,30}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : 8 à 30 caractères alphanumériques (lettres et chiffres) requis. Aucun espace ni ponctuation.'
    );
  END IF;

  IF v_numero_trim !~ '[0-9]' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : le numéro DPAE doit contenir au moins un chiffre.'
    );
  END IF;

  SELECT cm.etablissement_id, cm.soignant_id, cm.mission_id
    INTO v_etab_id, v_soignant_id, v_mission_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR COALESCE(v_etab_id = mon_etablissement_id(), false)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.contrats_mission
  SET dpae_numero = v_numero_trim,
      dpae_effectuee = true,
      dpae_effectuee_le = COALESCE(dpae_effectuee_le, NOW()),
      modifie_le = NOW()
  WHERE id = p_contrat_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'contrat_mission', p_contrat_id,
    jsonb_build_object(
      'evenement', 'DPAE_NUMERO_ENREGISTRE',
      'dpae_numero', v_numero_trim,
      'enregistre_le', NOW()::text
    )
  );

  IF v_soignant_id IS NOT NULL AND v_mission_id IS NOT NULL THEN
    SELECT prenom INTO v_soignant_prenom FROM public.soignants WHERE id = v_soignant_id;
    SELECT nom INTO v_etab_nom FROM public.etablissements WHERE id = v_etab_id;
    SELECT intitule INTO v_mission_intitule FROM public.missions WHERE id = v_mission_id;

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'type', 'DPAE_DECLAREE_SOIGNANT',
          'destinataire_id', v_soignant_id,
          'data', jsonb_build_object(
            'prenom', COALESCE(v_soignant_prenom, ''),
            'etablissement_nom', COALESCE(v_etab_nom, 'L''établissement'),
            'mission_intitule', COALESCE(v_mission_intitule, 'votre mission'),
            'dpae_numero', v_numero_trim,
            'contrat_id', p_contrat_id::text
          )
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'dpae_numero', v_numero_trim);
END;
$fonction$;

-- fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone) : LIVE d404ad86634519ac9a63b3202e52d2db → 53a208f0c1ee8c78a6faab262f47eaa4
CREATE OR REPLACE FUNCTION public.fn_rebooker_soignant(p_soignant_id uuid, p_mission_modele_id uuid, p_debut timestamp with time zone, p_fin timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_m record;
  v_s record;
  v_new_id uuid;
  v_resolution jsonb;
BEGIN
  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_modele_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission modèle introuvable'); END IF;
  IF NOT COALESCE(v_m.etablissement_id = public.mon_etablissement_id(), false) AND NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_debut IS NULL OR p_fin IS NULL OR p_fin <= p_debut OR p_debut < now() THEN
    RETURN jsonb_build_object('error', 'Dates invalides (le début doit être dans le futur).');
  END IF;
  SELECT * INTO v_s FROM public.soignants WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF NOT private.fn_compatibilite_profil_mission(
    p_soignant_id, v_m.profession_requise, v_m.specialite_medicale_requise,
    COALESCE(v_m.accepte_non_specialises, true), false, p_fin
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
$fonction$;

-- fn_booster_mission(uuid) : LIVE c22963698c0cbfc4cd6de19bb474f520 → e57ceb0273b02fab0215e2d33e251200
CREATE OR REPLACE FUNCTION public.fn_booster_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
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
  IF NOT COALESCE(v_m.etablissement_id = public.mon_etablissement_id(), false) AND NOT public.est_admin() THEN
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
$fonction$;

-- fn_presences_detail_mission(uuid) : LIVE 5063c38138004b599a721412b029c5ff → 1f653d7d432a87a356f3f62910a7ee38
CREATE OR REPLACE FUNCTION public.fn_presences_detail_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
    v_mission RECORD;
    v_presence RECORD;
    v_pauses JSONB;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;

    IF NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin()
       AND NOT COALESCE(v_mission.soignant_assigne_id = auth.uid(), false) THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT * INTO v_presence FROM presences WHERE mission_id = p_mission_id LIMIT 1;

    IF v_presence IS NULL THEN
        RETURN jsonb_build_object('pointage_effectue', false, 'heures_planifiees', v_mission.duree_heures);
    END IF;

    -- Récupérer les pauses détaillées
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', pp.id, 'debut', pp.debut_le, 'fin', pp.fin_le, 
        'duree_min', pp.duree_min, 'motif', pp.motif, 'en_cours', pp.fin_le IS NULL
    ) ORDER BY pp.debut_le), '[]'::JSONB) INTO v_pauses
    FROM pauses_presence pp WHERE pp.presence_id = v_presence.id;

    RETURN jsonb_build_object(
        'pointage_effectue', true,
        'heures_planifiees', v_mission.duree_heures,
        'heures_reelles', v_presence.heures_reelles,
        'pointage_arrivee', v_presence.pointage_arrivee_le,
        'pointage_depart', v_presence.pointage_depart_le,
        'methode_arrivee', v_presence.methode_pointage_arrivee,
        'methode_depart', v_presence.methode_pointage_depart,
        'retard_min', v_presence.retard_min,
        'depart_anticipe_min', v_presence.depart_anticipe_min,
        'duree_brute_min', v_presence.duree_brute_min,
        'duree_pause_min', v_presence.duree_pause_min,
        'duree_nette_min', v_presence.duree_nette_min,
        'nb_pauses', jsonb_array_length(v_pauses),
        'pauses', v_pauses,
        'distance_m', v_presence.distance_etablissement_m,
        'perimetre_valide', v_presence.perimetre_gps_valide,
        'alerte_teleportation', v_presence.alerte_teleportation,
        'alertes', v_presence.alertes_fraude,
        'valide', v_presence.valide_par_etablissement
    );
END;
$fonction$;

-- fn_activer_garantie_mission(uuid,boolean) : LIVE 4f170971145ed66ddad01805abebae6f → 00b0feecc9dfc4893a04bc94b584a013
CREATE OR REPLACE FUNCTION public.fn_activer_garantie_mission(p_mission_id uuid, p_actif boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT COALESCE(v_m.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut NOT IN ('OUVERTE', 'ASSIGNEE') THEN
    RETURN jsonb_build_object('error', 'La garantie ne peut être modifiée que sur une mission ouverte ou assignée.');
  END IF;
  UPDATE missions SET garantie_remplacement = p_actif, modifie_le = NOW() WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'garantie', p_actif);
END;
$fonction$;

-- fn_deposer_chorus(uuid,text) : LIVE 3a42d1cf3e8bb1aecedd28c4e0782cae → 8b310b8e4c6bbabd58b039a9e915c675
CREATE OR REPLACE FUNCTION public.fn_deposer_chorus(p_facture_id uuid, p_chorus_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
    v_facture RECORD;
BEGIN
    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN '{"error":"Facture introuvable"}'::JSONB; END IF;
    IF NOT COALESCE(v_facture.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    IF v_facture.rapprochement_paiement_requis OR v_facture.montant_a_payer<=0
      OR v_facture.statut NOT IN ('EMISE','EN_RETARD') THEN
      RETURN jsonb_build_object('error','Facture soldée ou paiement à rapprocher.'); END IF;
    UPDATE factures SET
        chorus_pro_statut = 'DEPOSEE',
        chorus_pro_deposee_le = NOW(),
        chorus_pro_id = p_chorus_id
    WHERE id = p_facture_id;

    RETURN '{"success":true}'::JSONB;
END;
$fonction$;

-- fn_generer_facture(uuid) : LIVE 5314c8689cd382ad000be9e7a9df6b29 → 078777ead10a6a4d500694551299622b
CREATE OR REPLACE FUNCTION public.fn_generer_facture(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
    v_mission RECORD;
    v_facture_id UUID;
    v_numero TEXT;
    v_annee TEXT := to_char(NOW(), 'YYYY');
    v_seq INTEGER;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF NOT est_admin() AND NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;
    IF v_mission.statut != 'TERMINEE' THEN
        RETURN '{"error":"La mission doit être TERMINEE"}'::JSONB;
    END IF;
    IF EXISTS (SELECT 1 FROM factures WHERE mission_id = p_mission_id) THEN
        RETURN '{"error":"Facture déjà existante"}'::JSONB;
    END IF;

    SELECT COALESCE(MAX(CAST(SUBSTRING(numero_facture FROM '\d+$') AS INTEGER)), 0) + 1
    INTO v_seq FROM factures WHERE numero_facture LIKE 'JOL-' || v_annee || '-%';
    v_numero := 'JOL-' || v_annee || '-' || LPAD(v_seq::TEXT, 5, '0');

    INSERT INTO factures (
        numero_facture, etablissement_id, mission_id,
        montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, statut, date_emission, date_echeance
    ) VALUES (
        v_numero, v_mission.etablissement_id, p_mission_id,
        COALESCE(v_mission.montant_commission_ht, 0),
        20,
        COALESCE(v_mission.montant_commission_tva, 0),
        COALESCE(v_mission.montant_commission_ttc, 0),
        1, 'EMISE', NOW(), (NOW() + INTERVAL '30 days')::DATE
    ) RETURNING id INTO v_facture_id;

    UPDATE missions SET commission_facturee = TRUE, modifie_le = NOW() WHERE id = p_mission_id;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_mission.etablissement_id, 'FACTURE_EMISE', 'Facture ' || v_numero,
        'Montant TTC : ' || COALESCE(v_mission.montant_commission_ttc, 0) || '€',
        '/etablissement/facturation', 'ETABLISSEMENT');

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$fonction$;

-- fn_diffuser_pool_urgence(uuid) : LIVE ba942f8cc9f7997930c5bdc9d32af9df → 07cd19c650da67e2b8128d32d0ffbfe6
CREATE OR REPLACE FUNCTION public.fn_diffuser_pool_urgence(p_mission_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $fonction$
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
    OR COALESCE(v_etablissement_id = public.mon_etablissement_id(), false)
  ) THEN
    RETURN 0;
  END IF;

  RETURN private.fn_diffuser_pool_urgence_interne(p_mission_id);
END;
$fonction$;

-- fn_etablissement_pour_mission(uuid) : LIVE 1f9bc93c9cf7e4b097ace3a78720c689 → 55493a7014ae20761ebf86fdab938f1c
CREATE OR REPLACE FUNCTION public.fn_etablissement_pour_mission(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT EXISTS(
        SELECT 1 FROM missions 
        WHERE etablissement_id = p_etablissement_id 
        AND (statut = 'OUVERTE' OR soignant_assigne_id = auth.uid())
    ) AND NOT COALESCE(mon_etablissement_id() = p_etablissement_id, false) AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT jsonb_build_object(
        'id', id, 'nom', nom, 'type', type::TEXT,
        'adresse_ville', adresse_ville, 'adresse_code_postal', adresse_code_postal,
        'adresse_departement', adresse_departement, 'adresse_rue', adresse_rue,
        'adresse_lat', adresse_lat, 'adresse_lng', adresse_lng,
        'note_moyenne', note_moyenne, 'convention_collective', convention_collective,
        'est_secteur_public', est_secteur_public, 'finess', finess
    ) INTO v_result
    FROM etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Établissement introuvable'));
END;
$fonction$;

-- fn_annuler_serie(uuid) : LIVE 71d57002916d856d6530d90f749676e1 → 06255e7b0d58441d46ac69798276dfae
CREATE OR REPLACE FUNCTION public.fn_annuler_serie(p_serie_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
    v_count INTEGER;
BEGIN
    IF NOT COALESCE(est_admin_etablissement(), false) AND NOT est_admin() THEN
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
$fonction$;

-- fn_assigner_mission_admin(uuid,uuid,text) : LIVE 502101a70656f3b5e5eb01c14f23d5de → 3a3523b9ac79ebd8e34a5ef58e749de3
CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_etablissement_id uuid;
BEGIN
  IF NOT (public.est_admin() OR COALESCE(public.est_admin_etablissement(), false)) THEN
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
$fonction$;

-- fn_creer_reclamation_score(uuid,text,text,text,text) : LIVE 34855c0d2b9062792aa49dbafc32ae6b → 18be67db062364dadbd298fb90884947
CREATE OR REPLACE FUNCTION public.fn_creer_reclamation_score(p_evenement_id uuid, p_evenement_type text, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_uid uuid := auth.uid();
  v_event RECORD;
  v_proprio_id uuid;
  v_reclamation_id uuid;
  v_existante RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_evenement_type NOT IN ('SOIGNANT', 'ETAB') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE',
                                'error', 'evenement_type doit être SOIGNANT ou ETAB');
  END IF;

  IF p_motif_categorie NOT IN ('URGENCE_MEDICALE','DEUIL','FORCE_MAJEURE',
                                'ERREUR_JOLENE','CONTEXTE_PARTICULIER','AUTRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif catégorie invalide');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 20 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 20 caractères)');
  END IF;

  -- Charger l'événement + check propriété + contestable
  IF p_evenement_type = 'SOIGNANT' THEN
    SELECT id, soignant_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_soignant WHERE id = p_evenement_id;
    v_proprio_id := v_event.soignant_id;
  ELSE
    SELECT id, etablissement_id AS proprio_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_etab WHERE id = p_evenement_id;
    v_proprio_id := v_event.proprio_id;
  END IF;

  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EVENT_INTROUVABLE',
                                'error', 'Événement de score introuvable');
  END IF;

  -- Auth : seul le propriétaire peut réclamer
  IF p_evenement_type = 'SOIGNANT' AND v_proprio_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;
  IF p_evenement_type = 'ETAB' AND NOT COALESCE(v_proprio_id = mon_etablissement_id(), false) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;

  IF NOT v_event.contestable THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_CONTESTABLE',
                                'error', 'Cet événement n''est pas contestable');
  END IF;

  IF v_event.decision_admin IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_TRAITE',
                                'error', 'Cet événement a déjà été traité par un admin');
  END IF;

  IF v_event.reclamation_id IS NOT NULL THEN
    SELECT id, statut INTO v_existante FROM public.reclamations_score WHERE id = v_event.reclamation_id;
    IF v_existante.statut = 'PENDING' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'RECLAMATION_EN_COURS',
                                  'error', 'Une réclamation est déjà ouverte pour cet événement',
                                  'reclamation_id', v_existante.id);
    END IF;
  END IF;

  -- Créer la réclamation
  INSERT INTO public.reclamations_score (
    evenement_type, evenement_soignant_id, evenement_etab_id,
    contesteur_id, motif_categorie, texte_libre, justificatif_storage_path
  ) VALUES (
    p_evenement_type,
    CASE WHEN p_evenement_type = 'SOIGNANT' THEN p_evenement_id ELSE NULL END,
    CASE WHEN p_evenement_type = 'ETAB' THEN p_evenement_id ELSE NULL END,
    v_uid, p_motif_categorie, trim(p_texte_libre), p_justificatif_storage_path
  ) RETURNING id INTO v_reclamation_id;

  -- Lier l'event à la réclamation
  IF p_evenement_type = 'SOIGNANT' THEN
    UPDATE public.evenements_score_soignant SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  ELSE
    UPDATE public.evenements_score_etab SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  END IF;

  -- Notification admin via externalisation
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('EMAIL_NOTIF', jsonb_build_object(
    'destinataire_role', 'ADMIN',
    'type', 'RECLAMATION_SCORE_NOUVELLE',
    'data', jsonb_build_object(
      'reclamation_id', v_reclamation_id,
      'evenement_type', p_evenement_type,
      'motif_categorie', p_motif_categorie,
      'contesteur_id', v_uid
    )
  ), 'AUTRE', v_reclamation_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'reclamation_score', v_reclamation_id,
    jsonb_build_object('evenement', 'RECLAMATION_SCORE_CREEE',
                        'event_score_id', p_evenement_id,
                        'event_type', p_evenement_type,
                        'motif_categorie', p_motif_categorie,
                        'justificatif', p_justificatif_storage_path IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'reclamation_id', v_reclamation_id, 'statut', 'PENDING');
END;
$fonction$;

-- fn_declarer_honoraires_retrocession(uuid,numeric,text) : LIVE 093135e6e6086e183023c612aa7bfa92 → 4223483a5500b8d865c4f529af6f1a99
CREATE OR REPLACE FUNCTION public.fn_declarer_honoraires_retrocession(p_mission_id uuid, p_montant_honoraires numeric, p_justificatif_cle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE
  v_m RECORD;
  v_retrocede numeric;
  v_taux_com numeric;
  v_com_ht numeric;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT COALESCE(v_m.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.mode_remuneration != 'RETROCESSION' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est pas en rétrocession.');
  END IF;
  IF v_m.statut != 'TERMINEE' THEN
    RETURN jsonb_build_object('error', 'Déclaration possible une fois la mission terminée.');
  END IF;
  IF v_m.montant_honoraires_bruts IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Honoraires déjà déclarés. Contactez le support pour rectifier.');
  END IF;
  IF p_montant_honoraires IS NULL OR p_montant_honoraires <= 0 OR p_montant_honoraires > 100000 THEN
    RETURN jsonb_build_object('error', 'Montant d''honoraires invalide.');
  END IF;
  IF p_justificatif_cle IS NULL OR length(trim(p_justificatif_cle)) < 5 THEN
    RETURN jsonb_build_object('error', 'Justificatif obligatoire : téléversez le relevé d''actes ou bordereau de la période.');
  END IF;

  v_retrocede := ROUND(p_montant_honoraires * COALESCE(v_m.retrocession_pct, 50) / 100.0, 2);
  v_taux_com := COALESCE(v_m.taux_commission_fige, v_m.taux_commission, 15);
  v_com_ht := ROUND(v_retrocede * v_taux_com / 100.0, 2);

  UPDATE missions SET
    montant_honoraires_bruts = p_montant_honoraires,
    justificatif_honoraires_cle = trim(p_justificatif_cle),
    total_brut = v_retrocede,
    net_a_payer = v_retrocede,
    montant_commission_ht = v_com_ht,
    montant_commission_tva = ROUND(v_com_ht * 0.20, 2),
    montant_commission_ttc = ROUND(v_com_ht * 1.20, 2),
    modifie_le = NOW()
  WHERE id = p_mission_id;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Relevé d''honoraires à confirmer 💶',
    'Le cabinet déclare ' || p_montant_honoraires || ' € d''honoraires (justificatif joint) pour "' || fn_html_escape(v_m.intitule) ||
    '" — votre rétrocession (' || COALESCE(v_m.retrocession_pct, 50) || '%) : ' || v_retrocede ||
    ' €. CONFIRMEZ le relevé sur la mission (ou contestez sous 48h via un litige). Sans action de votre part, le montant sera validé automatiquement sous 48h.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT');

  RETURN jsonb_build_object('success', TRUE, 'montant_retrocede', v_retrocede,
    'commission_ttc', ROUND(v_com_ht * 1.20, 2), 'en_attente_confirmation', TRUE);
END;
$fonction$;

-- fn_definir_retrocession_mission(uuid,numeric) : LIVE 89a25f4acaeed41f2850acea6d15530e → 52393260c791cbb5093278f303a93ebd
CREATE OR REPLACE FUNCTION public.fn_definir_retrocession_mission(p_mission_id uuid, p_pct numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fonction$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT COALESCE(v_m.etablissement_id = mon_etablissement_id(), false) AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut != 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Modifiable uniquement sur une mission ouverte.');
  END IF;
  IF p_pct IS NULL OR p_pct <= 0 OR p_pct > 100 THEN
    RETURN jsonb_build_object('error', 'Pourcentage de rétrocession invalide (1-100).');
  END IF;
  UPDATE missions SET mode_remuneration = 'RETROCESSION', retrocession_pct = p_pct,
    type_contrat_recherche = 'LIBERAL', modifie_le = NOW()
   WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'retrocession_pct', p_pct);
END;
$fonction$;

-- CREATE OR REPLACE conserve propriétaire et ACL ; aucun GRANT ni REVOKE.
-- Catégorie et justification d'inventaire inchangées ; seule l'empreinte suit le corps.
DO $gardes_null_apres$
DECLARE
  r record;
  p record;
  n integer := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
    ('fn_valider_alerte_presence(uuid)', 'p_presence_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '05a6e15c497e28d6f94b9cd1c243c811', '1ff0c4c48ccd906f161e1a9174034505'),
    ('fn_codes_pointage_mission(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'ca8d9013f736db6d3dca03b595aecf48', '478bc3d59e15a1a1c844443863a86d49'),
    ('fn_generer_code_secours_mission(uuid,text)', 'p_mission_id uuid, p_type text DEFAULT ''UNIVERSEL''::text', 'jsonb', 'v', ARRAY['search_path=public, extensions']::text[], 'MIXTE_TENANT_ADMIN', '3fbae3ee7274f92165cccb0ab705bdcd', '76c8e19c6f16a642b968d91a7850752b'),
    ('fn_generer_qr_mission(uuid,text)', 'p_mission_id uuid, p_type text DEFAULT ''UNIVERSEL''::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '6196379d17503a467d24beeb038b8897', '75869cf50e34d68dd982a6714c010c0b'),
    ('fn_soignants_urgence(uuid)', 'p_mission_id uuid', 'TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '9dcc20b932437733fbbdf5474cd1b39e', '9b8f736b8f7fd19729e26cc56f28d2c4'),
    ('fn_generer_donnees_dpae(uuid)', 'p_contrat_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'fd81d58a2e18b98fe7f57d458b467079', '1070a34cb7025565225d732ed7ac3906'),
    ('fn_enregistrer_numero_dpae(uuid,text)', 'p_contrat_id uuid, p_dpae_numero text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '1f54235815e67141e4994cb9a604aa2b', '0d6fb5c6692759e3972746d8dbc196f9'),
    ('fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'p_soignant_id uuid, p_mission_modele_id uuid, p_debut timestamp with time zone, p_fin timestamp with time zone', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'd404ad86634519ac9a63b3202e52d2db', '53a208f0c1ee8c78a6faab262f47eaa4'),
    ('fn_booster_mission(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', 'c22963698c0cbfc4cd6de19bb474f520', 'e57ceb0273b02fab0215e2d33e251200'),
    ('fn_presences_detail_mission(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '5063c38138004b599a721412b029c5ff', '1f653d7d432a87a356f3f62910a7ee38'),
    ('fn_activer_garantie_mission(uuid,boolean)', 'p_mission_id uuid, p_actif boolean', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '4f170971145ed66ddad01805abebae6f', '00b0feecc9dfc4893a04bc94b584a013'),
    ('fn_deposer_chorus(uuid,text)', 'p_facture_id uuid, p_chorus_id text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '3a42d1cf3e8bb1aecedd28c4e0782cae', '8b310b8e4c6bbabd58b039a9e915c675'),
    ('fn_generer_facture(uuid)', 'p_mission_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '5314c8689cd382ad000be9e7a9df6b29', '078777ead10a6a4d500694551299622b'),
    ('fn_diffuser_pool_urgence(uuid)', 'p_mission_id uuid', 'integer', 'v', ARRAY['search_path=pg_catalog, public, private']::text[], 'MIXTE_TENANT_ADMIN', 'ba942f8cc9f7997930c5bdc9d32af9df', '07cd19c650da67e2b8128d32d0ffbfe6'),
    ('fn_etablissement_pour_mission(uuid)', 'p_etablissement_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '1f9bc93c9cf7e4b097ace3a78720c689', '55493a7014ae20761ebf86fdab938f1c'),
    ('fn_annuler_serie(uuid)', 'p_serie_id uuid', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '71d57002916d856d6530d90f749676e1', '06255e7b0d58441d46ac69798276dfae'),
    ('fn_assigner_mission_admin(uuid,uuid,text)', 'p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '502101a70656f3b5e5eb01c14f23d5de', '3a3523b9ac79ebd8e34a5ef58e749de3'),
    ('fn_creer_reclamation_score(uuid,text,text,text,text)', 'p_evenement_id uuid, p_evenement_type text, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'RPC_UTILISATEUR_AUTH_INTERNE', '34855c0d2b9062792aa49dbafc32ae6b', '18be67db062364dadbd298fb90884947'),
    ('fn_declarer_honoraires_retrocession(uuid,numeric,text)', 'p_mission_id uuid, p_montant_honoraires numeric, p_justificatif_cle text DEFAULT NULL::text', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '093135e6e6086e183023c612aa7bfa92', '4223483a5500b8d865c4f529af6f1a99'),
    ('fn_definir_retrocession_mission(uuid,numeric)', 'p_mission_id uuid, p_pct numeric', 'jsonb', 'v', ARRAY['search_path=public']::text[], 'MIXTE_TENANT_ADMIN', '89a25f4acaeed41f2850acea6d15530e', '52393260c791cbb5093278f303a93ebd')
    ) AS v(signature, arguments, resultat, volatilite, configuration, categorie, md5_avant, md5_apres)
  LOOP
    n := n + 1;
    SELECT * INTO p FROM pg_catalog.pg_proc
    WHERE oid = pg_catalog.to_regprocedure('public.' || r.signature);
    IF NOT FOUND OR pg_catalog.md5(p.prosrc) <> r.md5_apres
      OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> r.volatilite
      OR p.proconfig IS DISTINCT FROM r.configuration
      OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
      OR pg_catalog.pg_get_function_arguments(p.oid) <> r.arguments
      OR pg_catalog.pg_get_function_result(p.oid) <> r.resultat
    THEN RAISE EXCEPTION 'GARDES_NULL_SOURCE_OU_ACL_APRES_DIVERGENTE : %', r.signature; END IF;
    IF pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      OR NOT pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
      OR EXISTS (SELECT FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                 WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    THEN RAISE EXCEPTION 'GARDES_NULL_ACL_APRES_DIVERGENTE : %', r.signature; END IF;
    UPDATE private.security_definer_inventory i
    SET definition_md5 = r.md5_apres, recense_le = now()
    WHERE i.signature = r.signature
      AND i.categorie = r.categorie
      AND i.definition_md5 = r.md5_avant;
    IF NOT FOUND OR (SELECT count(*) FROM private.security_definer_inventory i
        WHERE i.signature = r.signature
          AND i.categorie = r.categorie
          AND i.definition_md5 = pg_catalog.md5(p.prosrc)) <> 1
    THEN RAISE EXCEPTION 'GARDES_NULL_INVENTAIRE_NON_MIS_A_JOUR : %', r.signature; END IF;
  END LOOP;
  IF n <> 20 THEN RAISE EXCEPTION 'GARDES_NULL_PERIMETRE_INCOMPLET : % fonctions', n; END IF;
END;
$gardes_null_apres$;

NOTIFY pgrst, 'reload schema';
