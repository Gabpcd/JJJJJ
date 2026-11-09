-- B9 (catégorie SECURITY DEFINER / RPC) — la DPAE couvre les contrats CDDU et
-- VACATION dans les cinq fonctions serveur qui les excluaient encore.
--
-- Décision : les contrats CDDU (CDD d'usage) et VACATION sont des contrats de
-- travail salariés ; la DPAE leur est obligatoire comme au CDD. Décision prise
-- par Claude sur délégation explicite de Gabrielle du 08/11/2026.
-- Sources primaires : C. trav. art. L.1221-10 (déclaration nominative préalable
-- à l'embauche de tout salarié) et art. R.1221-1 et suivants (contenu et
-- modalités) ; art. L.1242-2 3° et D.1242-1 (le CDD d'usage est un contrat à
-- durée déterminée, donc un contrat de travail salarié). Le backend applique
-- déjà cette règle dans fn_annuler_mission_etab et
-- fn_declarer_empechement_imperieux (CDD, CDDU, VACATION) ; le web suit la même
-- source unique (TYPES_CONTRAT_SALARIES = CDD, SALARIE, CDDU, VACATION, branche
-- fix/dpae-contrats-cddu-vacation).
--
-- Défaut : cinq fonctions filtrent encore sur une liste héritée d'un renommage
-- CDDU → CDD (« IN ('CDD', 'CDD', 'SALARIE') », « IN ('CDD', 'CDD') ») :
--   * fn_mes_dpae : liste « Mes documents › DPAE » du soignant ;
--   * fn_rappel_dpae_quotidien : push de rappel DPAE à l'établissement (cron
--     jolene_rappel_dpae_quotidien, 0 9 * * *) ;
--   * fn_pointer_arrivee : avertissement DPAE_NON_REGULARISEE et push
--     DPAE_NON_REGULARISEE_POINTAGE à l'établissement, au pointage d'arrivée
--     sans numéro DPAE ;
--   * fn_annuler_candidature_soignant : action DPAE_ANNULATION mise en file à
--     l'annulation d'une candidature acceptée dont le contrat est signé ;
--   * dec_email_contrat_signe_complet : métadonnée d'audit dpae_requise.
-- Un CDDU ou une VACATION signés n'apparaissaient donc ni dans la liste du
-- soignant, ni dans les rappels, ni dans l'alerte de pointage, et leur
-- annulation n'enfilait pas l'annulation de la DPAE.
--
-- Correctif, et seul changement :
--   1. public.fn_type_contrat_salarie(text) : source unique SQL des types de
--      contrat salariés (CDD, SALARIE, CDDU, VACATION). SQL IMMUTABLE,
--      PARALLEL SAFE, SECURITY INVOKER, search_path vide, propriétaire
--      postgres ; EXECUTE pour authenticated et service_role, retiré à PUBLIC
--      et anon (fonction pure, sans donnée). NULL renvoie NULL, comme l'ancien
--      « IN (...) ».
--   2. Les cinq fonctions sont redéfinies depuis leur corps LIVE (prosrc relu
--      en production le 08/11/2026, lecture seule, md5 identiques aux corps de
--      supabase/schema/public.sql) : seule différence, l'expression de liste
--      remplacée par public.fn_type_contrat_salarie(<colonne>). Signatures,
--      propriétaire, SECURITY DEFINER, volatilité, search_path et ACL
--      inchangés (CREATE OR REPLACE, aucun GRANT ni REVOKE sur elles).
--   3. L'inventaire SECURITY DEFINER suit le nouveau corps des trois
--      fonctions recensées (empreinte calculée ; catégorie et justification
--      inchangées). Les deux autres (cron et trigger, non exécutables par
--      authenticated) restent hors inventaire, comme en production.
--
-- Gardes, toutes dans la transaction de la migration :
--   * préflight : propriétaire, SECURITY DEFINER, volatilité, search_path,
--     ACL et inventaire LIVE attendus ; l'ancienne expression figure une seule
--     fois ; ni CDDU, ni VACATION, ni le helper dans le corps ; le helper
--     n'existe pas encore. Les corps LIVE sont capturés.
--   * postflight : md5(nouveau corps, appel au helper ramené à l'ancienne
--     liste) = md5(corps LIVE capturé). Toute autre différence (corps LIVE
--     dérivé hors de la liste) ou un rejeu annule la migration entière.
--     Les empreintes sont calculées, jamais écrites en dur.
-- Aucune table, aucune donnée métier, aucun CHECK modifiés : les valeurs
-- écrites (DPAE_ANNULATION / ANNULATION_MISSION dans externalisation_actions ;
-- SYSTEM, CONTRAT_SIGNE, SYSTEME, SOIGNANT dans journaux_audit) existent déjà
-- et sont admises par les CHECK LIVE relus le 08/11/2026.
-- Effet mesuré en production le 08/11/2026 (lecture seule) : aucun contrat
-- CDDU ni VACATION (un seul contrat, REMPLACEMENT_LIBERAL, SIGNE_ETABLISSEMENT) ;
-- aucune liste, aucun rappel, aucun pointage ni aucune annulation ne change de
-- résultat au déploiement.
-- Hors périmètre (listés dans la PR, non modifiés) :
-- fn_calculer_indemnite_annulation_etab (indemnité de fin de contrat exclue
-- pour le CDD d'usage, C. trav. L.1243-10 : question distincte), peut_exercer,
-- dec_appliquer_plafond_rist.
-- Bancs : tests/security/dpae-contrats-cddu-vacation-isolated.test.sql et
-- tests/security/dpae-contrats-cddu-vacation-rejeu.test.sql (PostgreSQL 17
-- isolé), tests/security/dpae-contrats-cddu-vacation.test.sql (staging,
-- annulé), tests/node/dpae-contrats-cddu-vacation.node.mjs (statique).
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

DO $dpae_salarie_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  IF pg_catalog.to_regprocedure('public.fn_type_contrat_salarie(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'DPAE_SALARIE_PREFLIGHT_HELPER_DEJA_PRESENT';
  END IF;

  -- Corps LIVE capturés pour la garde finale (même transaction).
  CREATE TEMP TABLE _dpae_salarie_avant (
    ordre integer PRIMARY KEY,
    fonction_oid oid NOT NULL,
    signature text NOT NULL,
    ancien_prosrc text NOT NULL,
    ancienne_acl text,
    ancien_config text[],
    ancien_volatile text NOT NULL,
    ancienne_expression text NOT NULL,
    nouvelle_expression text NOT NULL,
    categorie text
  ) ON COMMIT DROP;

  FOR v_attendu IN
    SELECT * FROM (VALUES
      (1, 'fn_mes_dpae()', 's', ARRAY['search_path=public']::text[],
       'cm.type_contrat IN (''CDD'', ''CDD'', ''SALARIE'')', 'cm.type_contrat',
       true, 'RPC_UTILISATEUR_AUTH_INTERNE'),
      (2, 'fn_rappel_dpae_quotidien()', 'v', ARRAY['search_path=public']::text[],
       'cm.type_contrat IN (''CDD'', ''CDD'', ''SALARIE'')', 'cm.type_contrat',
       false, NULL),
      (3, 'fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text)', 'v', ARRAY['search_path=public']::text[],
       'v_contrat.type_contrat IN (''CDD'', ''CDD'', ''SALARIE'')', 'v_contrat.type_contrat',
       true, 'RPC_UTILISATEUR_AUTH_INTERNE'),
      (4, 'fn_annuler_candidature_soignant(uuid,text,text,text)', 'v', ARRAY['search_path=public']::text[],
       'v_contrat.type_contrat IN (''CDD'', ''CDD'', ''SALARIE'')', 'v_contrat.type_contrat',
       true, 'RPC_UTILISATEUR_AUTH_INTERNE'),
      (5, 'dec_email_contrat_signe_complet()', 'v', ARRAY['search_path=""']::text[],
       '(NEW.type_contrat IN (''CDD'', ''CDD''))', 'NEW.type_contrat',
       false, NULL)
    ) AS t(ordre, signature, volatilite, config, ancienne_expression, colonne,
           authenticated_execute, categorie)
    ORDER BY ordre
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.provolatile::text AS volatilite,
           p.proconfig, p.proacl, p.proowner,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure('public.' || v_attendu.signature);
    IF NOT FOUND
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.volatilite IS DISTINCT FROM v_attendu.volatilite
      OR v_proc.proconfig IS DISTINCT FROM v_attendu.config
      -- L'expression attendue figure exactement une fois ; aucune trace d'un
      -- type déjà ajouté ni du helper (rejeu ou correction concurrente).
      OR (pg_catalog.length(v_proc.prosrc)
          - pg_catalog.length(pg_catalog.replace(v_proc.prosrc, v_attendu.ancienne_expression, '')))
         / pg_catalog.length(v_attendu.ancienne_expression) <> 1
      OR pg_catalog.strpos(v_proc.prosrc, 'fn_type_contrat_salarie') > 0
      OR pg_catalog.strpos(v_proc.prosrc, 'CDDU') > 0
      OR pg_catalog.strpos(v_proc.prosrc, 'VACATION') > 0
    THEN
      RAISE EXCEPTION 'DPAE_SALARIE_PREFLIGHT_SOURCE_DRIFT: %', v_attendu.signature;
    END IF;
    IF pg_catalog.has_function_privilege('anon', v_proc.oid, 'EXECUTE')
      OR pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')
         IS DISTINCT FROM v_attendu.authenticated_execute
      OR NOT pg_catalog.has_function_privilege('service_role', v_proc.oid, 'EXECUTE')
      OR EXISTS (
        SELECT FROM pg_catalog.aclexplode(COALESCE(v_proc.proacl, pg_catalog.acldefault('f', v_proc.proowner))) a
         WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    THEN
      RAISE EXCEPTION 'DPAE_SALARIE_PREFLIGHT_ACL_DRIFT: %', v_attendu.signature;
    END IF;
    IF v_attendu.categorie IS NULL THEN
      IF EXISTS (SELECT FROM private.security_definer_inventory i
                  WHERE i.signature IN (v_attendu.signature, 'public.' || v_attendu.signature)) THEN
        RAISE EXCEPTION 'DPAE_SALARIE_PREFLIGHT_INVENTORY_DRIFT: %', v_attendu.signature;
      END IF;
    ELSIF (SELECT pg_catalog.count(*) FROM private.security_definer_inventory i
            WHERE i.signature IN (v_attendu.signature, 'public.' || v_attendu.signature)) <> 1
      OR NOT EXISTS (
        SELECT FROM private.security_definer_inventory i
         WHERE i.signature = v_attendu.signature
           AND i.categorie = v_attendu.categorie
           AND i.definition_md5 = pg_catalog.md5(v_proc.prosrc))
    THEN
      RAISE EXCEPTION 'DPAE_SALARIE_PREFLIGHT_INVENTORY_DRIFT: %', v_attendu.signature;
    END IF;

    INSERT INTO _dpae_salarie_avant VALUES (
      v_attendu.ordre, v_proc.oid, v_attendu.signature, v_proc.prosrc,
      v_proc.proacl::text, v_proc.proconfig, v_proc.volatilite,
      v_attendu.ancienne_expression,
      'public.fn_type_contrat_salarie(' || v_attendu.colonne || ')',
      v_attendu.categorie);
  END LOOP;

  IF (SELECT pg_catalog.count(*) FROM _dpae_salarie_avant) <> 5 THEN
    RAISE EXCEPTION 'DPAE_SALARIE_PREFLIGHT_INCOMPLET';
  END IF;
END
$dpae_salarie_avant$;

-- ── 1. Source unique SQL des types de contrat salariés ──────────────────────
CREATE FUNCTION public.fn_type_contrat_salarie(p_type_contrat text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $fn_type_contrat_salarie$
  SELECT p_type_contrat = ANY (ARRAY['CDD', 'SALARIE', 'CDDU', 'VACATION']::text[]);
$fn_type_contrat_salarie$;

ALTER FUNCTION public.fn_type_contrat_salarie(text) OWNER TO postgres;

COMMENT ON FUNCTION public.fn_type_contrat_salarie(text) IS 'Source unique SQL des types de contrat salariés soumis à la DPAE (C. trav. L.1221-10) : CDD, SALARIE, CDDU (L.1242-2 3°, D.1242-1), VACATION. Miroir de TYPES_CONTRAT_SALARIES côté web. REMPLACEMENT_LIBERAL et LIBERAL exclus ; NULL renvoie NULL.';

REVOKE ALL ON FUNCTION public.fn_type_contrat_salarie(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_type_contrat_salarie(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_type_contrat_salarie(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_type_contrat_salarie(text) TO service_role;

-- ── 2. Cinq redéfinitions depuis les corps LIVE (seule la liste change) ─────
CREATE OR REPLACE FUNCTION public.fn_mes_dpae()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_mes_dpae$
DECLARE
  v_uid uuid := auth.uid();
  v_dpae jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'contrat_id', cm.id,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'etablissement_id', m.etablissement_id,
    'etablissement_nom', e.nom,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'type_contrat', cm.type_contrat,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_numero', cm.dpae_numero,
    'dpae_effectuee_le', cm.dpae_effectuee_le,
    'rappel_dpae_affiche', cm.rappel_dpae_affiche,
    'rappel_dpae_affiche_le', cm.rappel_dpae_affiche_le,
    'statut_contrat', cm.statut
  ) ORDER BY m.debut_le DESC), '[]'::jsonb)
  INTO v_dpae
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE cm.soignant_id = v_uid
    AND public.fn_type_contrat_salarie(cm.type_contrat)
    AND cm.statut IN ('SIGNE_COMPLET', 'SIGNE_PARTIEL');

  RETURN jsonb_build_object('success', true, 'dpae', v_dpae);
END;
$fn_mes_dpae$;

CREATE OR REPLACE FUNCTION public.fn_rappel_dpae_quotidien()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_rappel_dpae_quotidien$
DECLARE v_contrat RECORD; v_count int := 0;
BEGIN
  FOR v_contrat IN
    SELECT cm.id, cm.numero_contrat, cm.etablissement_id
    FROM public.contrats_mission cm
    WHERE cm.statut = 'SIGNE_COMPLET' AND public.fn_type_contrat_salarie(cm.type_contrat)
      AND COALESCE(cm.dpae_effectuee, false) = false
      AND cm.signature_soignant_le > NOW() - INTERVAL '7 days'
      AND cm.signature_soignant_le < NOW() - INTERVAL '1 day'
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
        body := jsonb_build_object('destinataire_id', v_contrat.etablissement_id,
          'type_evenement', 'DPAE_RAPPEL', 'titre', 'Rappel DPAE',
          'corps', 'Contrat ' || COALESCE(v_contrat.numero_contrat, '') ||
                   ' : la DPAE URSSAF doit être déclarée avant la prise de poste.',
          'data', jsonb_build_object('contrat_id', v_contrat.id,
            'lien', 'https://jolene.app/contrat/' || v_contrat.id::text))
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    v_count := v_count + 1;
  END LOOP;
  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'cron', NULL,
      jsonb_build_object('evenement', 'DPAE_RAPPEL_QUOTIDIEN', 'count', v_count, 'exec_le', NOW()));
  END IF;
  RETURN jsonb_build_object('success', true, 'count', v_count);
END; $fn_rappel_dpae_quotidien$;

CREATE OR REPLACE FUNCTION public.fn_pointer_arrivee(p_mission_id uuid, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_precision numeric DEFAULT NULL::numeric, p_terminal_id text DEFAULT NULL::text, p_modele text DEFAULT NULL::text, p_code_arrivee text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_pointer_arrivee$
DECLARE
  v_mission RECORD;
  v_contrat RECORD;
  v_etab RECORD;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_methode text;
  v_warnings jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
  IF v_mission.soignant_assigne_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN '{"error":"Mission non active"}'::JSONB; END IF;

  SELECT * INTO v_contrat FROM contrats_mission WHERE mission_id = p_mission_id AND statut = 'SIGNE_COMPLET';
  IF v_contrat IS NULL THEN RETURN '{"error":"Le contrat doit être signé avant le pointage."}'::JSONB; END IF;

  IF EXISTS (SELECT 1 FROM presences WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
    RETURN '{"error":"Vous avez déjà pointé votre arrivée."}'::JSONB;
  END IF;

  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
    INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

  IF p_code_arrivee IS NOT NULL THEN
    IF p_code_arrivee != v_mission.code_arrivee THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT', 'error', 'Code de pointage incorrect.');
    END IF;
    v_methode := 'CODE';
    v_perimetre_ok := true;
    v_distance_m := NULL;
  ELSE
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      v_distance_m := NULL;
      v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement (tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;

  IF public.fn_type_contrat_salarie(v_contrat.type_contrat)
     AND COALESCE(v_contrat.dpae_numero, '') = '' THEN
    v_warnings := v_warnings || jsonb_build_object(
      'code', 'DPAE_NON_REGULARISEE',
      'message', 'Votre DPAE URSSAF n''est pas encore enregistrée dans Jolene. L''établissement doit régulariser la déclaration auprès de l''URSSAF et saisir le numéro dans la plateforme.',
      'severite', 'warning'
    );

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'destinataire_id', v_mission.etablissement_id,
          'type_evenement', 'DPAE_NON_REGULARISEE_POINTAGE',
          'titre', '⚠️ DPAE à régulariser',
          'corps', 'Le soignant vient de pointer sur le contrat ' || COALESCE(v_contrat.numero_contrat, '') || ' mais le numéro URSSAF n''est pas saisi. À régulariser sous 24h.',
          'data', jsonb_build_object('contrat_id', v_contrat.id::text, 'mission_id', p_mission_id::text)
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  INSERT INTO presences (
    mission_id, soignant_id, pointage_arrivee_le,
    arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
    arrivee_id_terminal, arrivee_modele_terminal,
    methode_pointage_arrivee, distance_etablissement_m, perimetre_gps_valide
  ) VALUES (
    p_mission_id, auth.uid(), NOW(), p_lat, p_lng, p_precision,
    p_terminal_id, p_modele, v_methode, v_distance_m, v_perimetre_ok
  );

  UPDATE missions SET statut = 'EN_COURS', modifie_le = NOW()
   WHERE id = p_mission_id AND statut = 'ASSIGNEE';

  RETURN jsonb_build_object(
    'success', true,
    'methode', v_methode,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'warnings', v_warnings
  );
END;
$fn_pointer_arrivee$;

CREATE OR REPLACE FUNCTION public.fn_annuler_candidature_soignant(p_candidature_id uuid, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_annuler_candidature_soignant$
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

    IF public.fn_type_contrat_salarie(v_contrat.type_contrat)
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
$fn_annuler_candidature_soignant$;

CREATE OR REPLACE FUNCTION public.dec_email_contrat_signe_complet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $dec_email_contrat_signe_complet$
DECLARE
  v_lien text;
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

  -- Ne tirer que sur transition vers SIGNE_COMPLET
  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN
    RETURN NEW;
  END IF;

  v_lien := 'https://jolene.app/contrat/' || NEW.id::text;

  -- Email soignant
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.soignant_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Email étab
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.etablissement_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', 'SYSTEME',
    'CONTRAT_SIGNE', 'contrat_mission', NEW.id,
    jsonb_build_object(
      'evenement', 'CONTRAT_SIGNE_COMPLET_AUTO',
      'numero_contrat', NEW.numero_contrat,
      'type_contrat', NEW.type_contrat,
      'mode_signature', NEW.mode_signature,
      'dpae_requise', public.fn_type_contrat_salarie(NEW.type_contrat)
    )
  );

  RETURN NEW;
END;
$dec_email_contrat_signe_complet$;

-- ── 3. Inventaire SECURITY DEFINER : seule l'empreinte suit le corps ────────
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       recense_le = pg_catalog.now()
  FROM _dpae_salarie_avant a
  JOIN pg_catalog.pg_proc p ON p.oid = a.fonction_oid
 WHERE a.categorie IS NOT NULL
   AND i.signature = a.signature
   AND i.definition_md5 = pg_catalog.md5(a.ancien_prosrc);

-- ── 4. Postflight : helper, corps, attributs, ACL et inventaire ─────────────
DO $dpae_salarie_apres$
DECLARE
  v_helper constant regprocedure := 'public.fn_type_contrat_salarie(text)'::regprocedure;
  v_h record;
  r record;
  v_nb integer := 0;
BEGIN
  SELECT p.provolatile::text AS volatilite, p.proparallel::text AS parallele,
         p.prosecdef, p.proconfig, p.proacl, p.proowner,
         pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
    INTO v_h
    FROM pg_catalog.pg_proc p
   WHERE p.oid = v_helper;
  IF v_h.volatilite IS DISTINCT FROM 'i'
    OR v_h.parallele IS DISTINCT FROM 's'
    OR v_h.prosecdef IS DISTINCT FROM false
    OR v_h.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    OR v_h.proprietaire IS DISTINCT FROM 'postgres'
    OR pg_catalog.has_function_privilege('anon', v_helper, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', v_helper, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', v_helper, 'EXECUTE')
    OR EXISTS (
      SELECT FROM pg_catalog.aclexplode(COALESCE(v_h.proacl, pg_catalog.acldefault('f', v_h.proowner))) a
       WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  THEN
    RAISE EXCEPTION 'DPAE_SALARIE_HELPER_ATTRIBUTS_INATTENDUS';
  END IF;
  IF public.fn_type_contrat_salarie('CDD') IS NOT TRUE
    OR public.fn_type_contrat_salarie('SALARIE') IS NOT TRUE
    OR public.fn_type_contrat_salarie('CDDU') IS NOT TRUE
    OR public.fn_type_contrat_salarie('VACATION') IS NOT TRUE
    OR public.fn_type_contrat_salarie('REMPLACEMENT_LIBERAL') IS NOT FALSE
    OR public.fn_type_contrat_salarie('LIBERAL') IS NOT FALSE
    OR public.fn_type_contrat_salarie('cddu') IS NOT FALSE
    OR public.fn_type_contrat_salarie('') IS NOT FALSE
    OR public.fn_type_contrat_salarie(NULL) IS NOT NULL
  THEN
    RAISE EXCEPTION 'DPAE_SALARIE_HELPER_TABLE_DE_VERITE';
  END IF;

  FOR r IN
    SELECT a.*, p.prosrc AS nouveau_prosrc, p.proacl::text AS nouvelle_acl,
           p.proconfig AS nouveau_config, p.provolatile::text AS nouveau_volatile,
           p.prosecdef AS nouveau_secdef,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      FROM _dpae_salarie_avant a
      LEFT JOIN pg_catalog.pg_proc p ON p.oid = a.fonction_oid
     ORDER BY a.ordre
  LOOP
    IF r.nouveau_prosrc IS NULL
      OR r.proprietaire IS DISTINCT FROM 'postgres'
      OR r.nouveau_secdef IS NOT TRUE
      OR r.nouveau_volatile IS DISTINCT FROM r.ancien_volatile
      OR r.nouveau_config IS DISTINCT FROM r.ancien_config
      OR r.nouvelle_acl IS DISTINCT FROM r.ancienne_acl
      OR r.nouveau_prosrc = r.ancien_prosrc
      OR (pg_catalog.length(r.nouveau_prosrc)
          - pg_catalog.length(pg_catalog.replace(r.nouveau_prosrc, r.nouvelle_expression, '')))
         / pg_catalog.length(r.nouvelle_expression) <> 1
      OR pg_catalog.strpos(r.nouveau_prosrc, 'IN (''CDD'', ''CDD''') > 0
      -- Seule différence admise avec le corps LIVE capturé : l'appel au helper.
      OR pg_catalog.md5(pg_catalog.replace(r.nouveau_prosrc, r.nouvelle_expression, r.ancienne_expression))
         IS DISTINCT FROM pg_catalog.md5(r.ancien_prosrc)
    THEN
      RAISE EXCEPTION 'DPAE_SALARIE_POSTFLIGHT_CORPS_OU_ATTRIBUTS: %', r.signature;
    END IF;
    IF r.categorie IS NULL THEN
      IF EXISTS (SELECT FROM private.security_definer_inventory i
                  WHERE i.signature IN (r.signature, 'public.' || r.signature)) THEN
        RAISE EXCEPTION 'DPAE_SALARIE_POSTFLIGHT_INVENTAIRE: %', r.signature;
      END IF;
    ELSIF (SELECT pg_catalog.count(*) FROM private.security_definer_inventory i
            WHERE i.signature IN (r.signature, 'public.' || r.signature)) <> 1
      OR NOT EXISTS (
        SELECT FROM private.security_definer_inventory i
         WHERE i.signature = r.signature
           AND i.categorie = r.categorie
           AND i.definition_md5 = pg_catalog.md5(r.nouveau_prosrc))
    THEN
      RAISE EXCEPTION 'DPAE_SALARIE_POSTFLIGHT_INVENTAIRE: %', r.signature;
    END IF;
    v_nb := v_nb + 1;
  END LOOP;
  IF v_nb <> 5 THEN
    RAISE EXCEPTION 'DPAE_SALARIE_POSTFLIGHT_INCOMPLET: %', v_nb;
  END IF;
END
$dpae_salarie_apres$;
