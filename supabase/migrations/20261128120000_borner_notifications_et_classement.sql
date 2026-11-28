-- B9 : notifications écrites par les clients et classement des soignants.
--
-- Constats (production relue en lecture seule le 28/11/2026, définitions LIVE) :
--
-- 1. public.fn_creer_notification (SECURITY DEFINER, md5 bc337810f500768fed6748fac74265e8)
--    est GRANT EXECUTE à authenticated et son seul contrôle est « auth.uid() non nul » :
--    tout compte connecté écrit une notification arbitraire (destinataire, type, titre,
--    corps, lien) à n'importe quel utilisateur, lien externe compris (hameçonnage sous le
--    nom de Jolene). Constat B9 de docs/mobile-swift/DECISIONS_LOT2.md (« Constat T0 —
--    fn_creer_notification »), dont ce correctif applique la proposition.
--    Appelants relus : dix fonctions SECURITY DEFINER (propriétaire postgres : six triggers de
--    litige, de message, de mission et d'anti-fraude, fn_valider_presence[s_lot],
--    fn_proposer_accord_partie, fn_relancer_candidatures_en_attente) et une fonction
--    SECURITY INVOKER non exécutable par authenticated (fn_notifier_documents_expirants).
--    Aucun appel natif (iOS : décision 9, RPC_JAMAIS_SUIVIES), aucun appel edge. Trois
--    appels web, remplacés par la PR qui porte cette migration :
--    - PanneauContestation.tsx (CONTESTATION_PRESENCE) : doublon de
--      trg_notifier_creation_litige, qui notifie déjà l'autre partie (LITIGE_OUVERT) à
--      l'insertion du litige, dans les deux sens. Appel retiré, comme le natif.
--    - DetailMission.tsx, alerte du pool d'urgence (MISSION_URGENTE) : remplacé par
--      public.fn_alerter_pool_urgence(uuid), ci-dessous.
--    - AdminMandatsFacturation.tsx, relance du mandat (RAPPEL_DOCUMENTS) : remplacé par
--      public.fn_admin_relancer_mandat_facturation(uuid), ci-dessous.
--    Correctif : REVOKE EXECUTE à PUBLIC, anon et authenticated ; service_role et le
--    propriétaire le gardent. Corps inchangé (même md5). Les appelants SECURITY DEFINER
--    s'exécutent sous le propriétaire postgres et ne sont pas touchés ; le préflight
--    refuse la migration si un appelant pouvait s'exécuter sous authenticated.
--
-- 2. public.fn_top_soignants (classement, SECURITY DEFINER, md5 1565a9c0a7908e833f8bdae9f96f852e)
--    renvoie à tout compte connecté (établissement, compte sans profil, compte de test,
--    compte de revue des stores) l'identifiant, le prénom, le nom complet, la note, le
--    score et le nombre de missions des cinquante premiers soignants RÉELS. Correctif :
--    - réservé aux soignants inscrits (profil non supprimé) et aux administrateurs ;
--      tout autre appelant reçoit zéro ligne ;
--    - cohorte de l'appelant : un compte de test (dont le soignant de revue des stores)
--      ne voit que des comptes de test, un compte réel que des comptes réels (même
--      prédicat est_compte_test que private.fn_comptes_meme_cohorte_test) ; un
--      administrateur voit la cohorte réelle, comme avant ;
--    - pseudonymisé : prénom et initiale du nom ; ni identifiant ni nombre d'évaluations
--      (non affichés par la page /soignant/classement, seule appelante).
--    Changement du type de retour : DROP puis CREATE, droits reposés explicitement.
--    Inchangés : borne 1..50, profession, fn_documents_ok_pour_mission, ordre de tri,
--    source des valeurs (colonnes de soignants).
--
-- Redéfinition : corps LIVE relus le 28/11/2026 (identiques à supabase/schema/public.sql,
-- re-baseline #1204). Préflight fail-closed sur md5(prosrc), attributs et appelants ;
-- post-condition sur les corps installés, les droits et l'inventaire SECURITY DEFINER.
--
-- Contrôles : tests/security/notifications-classement-b9.test.sql (staging, ROLLBACK ;
-- même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/notifications-classement-b9.pg17.mjs, qui reproduit d'abord les deux
-- failles sur le corps LIVE), garde statique tests/node/notifications-classement-b9.node.mjs.
-- B9 (GRANT + SECURITY DEFINER) : go écrit de Gabrielle du 24/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed ────────────────────────────────────────────────
DO $b9_notifications_avant$
DECLARE
  v_attendu record;
  v_proc record;
  v_appelants text;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_creer_notification(uuid,text,text,text,text,text,text,uuid)', 'bc337810f500768fed6748fac74265e8', 'search_path=public'),
      ('public.fn_top_soignants(text,integer)', '1565a9c0a7908e833f8bdae9f96f852e', 'search_path=public'),
      ('public.fn_soignants_urgence(uuid)', '9b8f736b8f7fd19729e26cc56f28d2c4', 'search_path=public')
    ) AS t(signature, empreinte, config)
  LOOP
    SELECT p.prosrc, p.prosecdef, p.proconfig, pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_attendu.config]::text[]
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS_SOURCE_DIVERGENTE : % en base (md5 %) ne correspond plus au corps LIVE relu le 28/11/2026 (md5 %). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature, COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'), v_attendu.empreinte;
    END IF;
  END LOOP;

  IF pg_catalog.to_regprocedure('public.est_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.mon_etablissement_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.fn_documents_ok_pour_mission(uuid,text)') IS NULL
     OR pg_catalog.to_regprocedure('private.fn_comptes_meme_cohorte_test(uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.fn_alerter_pool_urgence(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.fn_admin_relancer_mandat_facturation(uuid)') IS NOT NULL
  THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS_CATALOGUE_DIVERGENT : helpers absents ou RPC de remplacement déjà présentes.';
  END IF;

  -- Aucun appelant qui s'exécuterait sous authenticated après le REVOKE : un appelant
  -- SECURITY DEFINER s'exécute sous son propriétaire (postgres attendu) ; un appelant
  -- SECURITY INVOKER ne doit être ni une fonction de déclencheur, ni exécutable par
  -- authenticated ou anon.
  SELECT pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::text, ', ' ORDER BY p.oid::pg_catalog.regprocedure::text)
    INTO v_appelants
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
     AND p.prosrc ILIKE '%fn_creer_notification%'
     AND p.oid <> 'public.fn_creer_notification(uuid,text,text,text,text,text,text,uuid)'::pg_catalog.regprocedure
     AND ((p.prosecdef AND pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres')
       OR (NOT p.prosecdef AND (p.prorettype = 'trigger'::pg_catalog.regtype
            OR pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
            OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'))));
  IF v_appelants IS NOT NULL THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS_APPELANT_UTILISATEUR : % appelle fn_creer_notification sous un rôle utilisateur ; le REVOKE le casserait.', v_appelants;
  END IF;
END
$b9_notifications_avant$;

-- ── 1. fn_creer_notification : plus aucun appel direct par un compte ────────
REVOKE ALL ON FUNCTION public.fn_creer_notification(uuid, text, text, text, text, text, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_creer_notification(uuid, text, text, text, text, text, text, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_creer_notification(uuid, text, text, text, text, text, text, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_creer_notification(uuid, text, text, text, text, text, text, uuid) TO service_role;

-- ── 2. Alerte du pool d'urgence, côté serveur ───────────────────────────────
-- Remplace les appels web fn_creer_notification de DetailMission.tsx (un par soignant,
-- titre et corps écrits par le client). Même autorisation que fn_soignants_urgence
-- (administrateur, ou établissement de la mission, garde NULL-safe), même liste de
-- destinataires (fn_soignants_urgence, appelée dans le contexte de l'appelant, dont
-- l'éligibilité porte déjà la cohorte et écarte REVUE_STORE ; prédicat de cohorte
-- canonique relu ici, porte exigée de tout émetteur de diffusion de mission), texte
-- et lien posés ici. Mission urgente et ouverte seulement ; un soignant déjà notifié
-- pour cette mission (MISSION_URGENTE, notification automatique de
-- trg_auto_notify_mission_urgente comprise) ne l'est pas une seconde fois.
CREATE FUNCTION public.fn_alerter_pool_urgence(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn_alerter_pool_urgence$
DECLARE
  v_mission record;
  v_titre text;
  v_corps text;
  v_soignant record;
  v_notifies integer := 0;
  v_deja integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  SELECT m.id, m.etablissement_id, m.intitule, m.debut_le, m.statut::text AS statut, m.est_urgente
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id;
  IF NOT FOUND
     OR NOT (public.est_admin() OR COALESCE(v_mission.etablissement_id = public.mon_etablissement_id(), false))
  THEN
    RAISE EXCEPTION 'Mission introuvable ou hors de votre établissement' USING ERRCODE = '42501';
  END IF;
  IF v_mission.statut IS DISTINCT FROM 'OUVERTE' OR v_mission.est_urgente IS NOT TRUE THEN
    RAISE EXCEPTION 'Alerte du pool réservée aux missions urgentes ouvertes' USING ERRCODE = '22023';
  END IF;

  -- Une alerte à la fois par mission : le contrôle « déjà notifié » et l'écriture
  -- restent atomiques face à deux alertes simultanées (administrateur et établissement).
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('fn_alerter_pool_urgence:' || p_mission_id::text, 0));

  v_titre := '🚨 Mission urgente : ' || v_mission.intitule;
  v_corps := v_mission.intitule || ' — '
    || pg_catalog.to_char(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM "à" HH24:MI')
    || '. Premier arrivé, premier servi !';

  FOR v_soignant IN
    SELECT DISTINCT u.soignant_id
      FROM public.fn_soignants_urgence(p_mission_id) u
     WHERE private.fn_comptes_meme_cohorte_test(u.soignant_id, v_mission.etablissement_id)
  LOOP
    IF EXISTS (SELECT 1 FROM public.notifications n
                WHERE n.destinataire_id = v_soignant.soignant_id
                  AND n.type = 'MISSION_URGENTE'
                  AND n.id_ressource = p_mission_id) THEN
      v_deja := v_deja + 1;
      CONTINUE;
    END IF;
    PERFORM public.fn_creer_notification(
      v_soignant.soignant_id, 'SOIGNANT', 'MISSION_URGENTE', v_titre, v_corps,
      '/soignant/missions/' || p_mission_id::text, 'MISSION', p_mission_id
    );
    v_notifies := v_notifies + 1;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object('success', true, 'notifies', v_notifies, 'deja_notifies', v_deja);
END;
$fn_alerter_pool_urgence$;

REVOKE ALL ON FUNCTION public.fn_alerter_pool_urgence(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_alerter_pool_urgence(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_alerter_pool_urgence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_alerter_pool_urgence(uuid) TO service_role;

-- ── 3. Relance du mandat de facturation, côté serveur ───────────────────────
-- Remplace l'appel web fn_creer_notification d'AdminMandatsFacturation.tsx. Même
-- autorisation que fn_admin_mandats_stats (est_admin()) ; titre, corps et lien repris
-- mot pour mot de l'appel web (aucun nouveau texte) ; destinataire : un soignant non
-- supprimé.
CREATE FUNCTION public.fn_admin_relancer_mandat_facturation(p_soignant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn_admin_relancer_mandat_facturation$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.soignants s
                  WHERE s.id = p_soignant_id AND s.supprime_le IS NULL) THEN
    RAISE EXCEPTION 'Soignant introuvable' USING ERRCODE = 'P0002';
  END IF;
  RETURN public.fn_creer_notification(
    p_soignant_id, 'SOIGNANT', 'RAPPEL_DOCUMENTS',
    'Signez votre mandat de facturation',
    'Votre mandat de facturation attend votre signature. Il permet la génération de vos factures d''honoraires ; pour une mission explicitement éligible au paiement accéléré, il fait partie des prérequis.',
    '/soignant/mandat-facturation', NULL, NULL
  );
END;
$fn_admin_relancer_mandat_facturation$;

REVOKE ALL ON FUNCTION public.fn_admin_relancer_mandat_facturation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_admin_relancer_mandat_facturation(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_relancer_mandat_facturation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_relancer_mandat_facturation(uuid) TO service_role;

-- ── 4. Classement : soignants inscrits et admins, cohorte, pseudonymisé ─────
DROP FUNCTION public.fn_top_soignants(text, integer);

CREATE FUNCTION public.fn_top_soignants(
  p_profession text DEFAULT NULL,
  p_limit integer DEFAULT 20
)
RETURNS TABLE(
  prenom text,
  nom text,
  profession text,
  note_moyenne numeric,
  score_fiabilite integer,
  total_missions_terminees integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn_top_soignants$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_cohorte_test boolean;
BEGIN
  -- Cohorte de l'appelant : administrateur → comptes réels ; soignant inscrit → sa
  -- cohorte (est_compte_test) ; tout autre appelant (établissement, compte sans profil,
  -- profil supprimé) → aucune ligne (migration 20261128120000).
  IF public.est_admin() THEN
    v_cohorte_test := false;
  ELSE
    SELECT s.est_compte_test
      INTO v_cohorte_test
      FROM public.soignants s
     WHERE s.id = auth.uid()
       AND s.supprime_le IS NULL;
  END IF;
  IF v_cohorte_test IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.prenom,
    NULLIF(upper(left(btrim(s.nom), 1)), '') || '.',
    s.profession::text,
    s.note_moyenne,
    ROUND(COALESCE(s.score_fiabilite, 0))::integer,
    s.total_missions_terminees
  FROM public.soignants s
  WHERE s.supprime_le IS NULL
    AND s.est_compte_test = v_cohorte_test
    AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND (p_profession IS NULL OR s.profession::text = p_profession)
  ORDER BY
    s.note_moyenne DESC NULLS LAST,
    s.score_fiabilite DESC,
    s.total_missions_terminees DESC
  LIMIT v_limit;
END;
$fn_top_soignants$;

REVOKE ALL ON FUNCTION public.fn_top_soignants(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_top_soignants(text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_top_soignants(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_top_soignants(text, integer) TO service_role;

-- ── 5. Inventaire SECURITY DEFINER ─────────────────────────────────────────
INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT v.signature, v.categorie, pg_catalog.md5(p.prosrc), v.justification, pg_catalog.now()
  FROM (VALUES
    ('fn_creer_notification(uuid,text,text,text,text,text,text,uuid)', 'SERVICE_ONLY_REVOQUE',
     'Primitive d''écriture des notifications, appelée par les fonctions serveur (déclencheurs, RPC bornées, crons). EXECUTE retiré à PUBLIC, anon et authenticated : aucun compte ne choisit destinataire, texte ou lien. Source : 20261128120000_borner_notifications_et_classement.sql'),
    ('fn_alerter_pool_urgence(uuid)', 'MIXTE_TENANT_ADMIN',
     'Alerte du pool d''urgence : administrateur ou établissement de la mission (garde NULL-safe), mission urgente ouverte, destinataires de fn_soignants_urgence, texte et lien posés par le serveur, sans doublon. Source : 20261128120000_borner_notifications_et_classement.sql'),
    ('fn_admin_relancer_mandat_facturation(uuid)', 'ADMIN_EST_ADMIN_VALIDE',
     'Relance du mandat de facturation : est_admin(), soignant non supprimé, texte et lien fixes. Source : 20261128120000_borner_notifications_et_classement.sql'),
    ('fn_top_soignants(text,integer)', 'RPC_UTILISATEUR_AUTH_INTERNE',
     'Classement : soignant inscrit (sa cohorte de test ou réelle) ou administrateur (cohorte réelle), sinon aucune ligne ; prénom et initiale du nom, sans identifiant ; borné à cinquante. Source : 20261128120000_borner_notifications_et_classement.sql')
  ) AS v(signature, categorie, justification)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure('public.' || v.signature)
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ── 6. Post-condition ──────────────────────────────────────────────────────
DO $b9_notifications_apres$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_creer_notification(uuid,text,text,text,text,text,text,uuid)', 'bc337810f500768fed6748fac74265e8', false),
      ('public.fn_alerter_pool_urgence(uuid)', '5b86dde9fb3450ac0e654512e3819dfc', true),
      ('public.fn_admin_relancer_mandat_facturation(uuid)', 'fe171f70cf862988022d487ea962d104', true),
      ('public.fn_top_soignants(text,integer)', 'dd2dd814b3ed617b09652dd59decc133', true)
    ) AS t(signature, empreinte, authenticated)
  LOOP
    SELECT p.oid, p.prosrc, p.prosecdef, p.proconfig, pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS_POSTCONDITION : corps ou attributs inattendus pour %.', v_attendu.signature;
    END IF;
    IF pg_catalog.has_function_privilege('anon', v_proc.oid, 'EXECUTE')
       OR pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE') IS DISTINCT FROM v_attendu.authenticated
       OR NOT pg_catalog.has_function_privilege('service_role', v_proc.oid, 'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
                    (SELECT p2.proacl FROM pg_catalog.pg_proc p2 WHERE p2.oid = v_proc.oid),
                    pg_catalog.acldefault('f', (SELECT p3.proowner FROM pg_catalog.pg_proc p3 WHERE p3.oid = v_proc.oid)))) a
                   WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
    THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS_POSTCONDITION : droits EXECUTE inattendus pour %.', v_attendu.signature;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory i
                    WHERE 'public.' || i.signature = v_attendu.signature
                      AND i.definition_md5 = v_attendu.empreinte) THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS_POSTCONDITION : inventaire SECURITY DEFINER désaligné pour %.', v_attendu.signature;
    END IF;
  END LOOP;
  IF pg_catalog.pg_get_function_result('public.fn_top_soignants(text,integer)'::pg_catalog.regprocedure)
     IS DISTINCT FROM 'TABLE(prenom text, nom text, profession text, note_moyenne numeric, score_fiabilite integer, total_missions_terminees integer)'
  THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS_POSTCONDITION : colonnes du classement inattendues.';
  END IF;
END
$b9_notifications_apres$;
