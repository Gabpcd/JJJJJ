-- ═══════════════════════════════════════════════════════════════════════════
-- B9 : notifications écrites par les clients et classement des soignants
-- (migration 20261128150000_borner_notifications_et_classement).
--
-- ⚠️  JAMAIS EN PROD. Staging CI : job « sql-transaction » de validate-pr.yml,
--     après les migrations candidates, sous SAVEPOINT puis ROLLBACK global ;
--     PostgreSQL 17 éphémère et PGlite : tests/postgres/notifications-classement-b9.pg17.mjs.
--     Vraies routines et vrais déclencheurs ; profils fictifs ; zéro persistance.
--
-- Ce qu'il prouve :
--   A. fn_creer_notification n'est plus exécutable par anon ni authenticated
--      (42501 pour un soignant, un établissement ou un administrateur connectés),
--      l'est toujours par service_role ; corps inchangé ; ses appelants sont des
--      fonctions SECURITY DEFINER de postgres, ou ne s'exécutent jamais sous un
--      rôle utilisateur ;
--   B. fn_alerter_pool_urgence : refus hors administrateur et établissement de
--      la mission (42501), refus sans session (28000), mission non urgente
--      refusée (22023) ; sinon chaque soignant de fn_soignants_urgence reçoit une
--      seule notification MISSION_URGENTE au texte et au lien posés par le
--      serveur, même en cas de seconde alerte ;
--   C. fn_admin_relancer_mandat_facturation : refus hors administrateur (42501),
--      soignant absent ou supprimé refusé (P0002), texte et lien fixes ;
--   D. fn_top_soignants : réservé aux soignants inscrits et aux administrateurs
--      (établissement, compte sans profil, profil supprimé, appel sans session :
--      aucune ligne ; anon : 42501), cohorte de l'appelant (test ↔ test, réel ↔
--      réel, administrateur → réel), prénom et initiale du nom, sans identifiant.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- ── 1. Catalogue candidat ──────────────────────────────────────────────────
DO $b9_catalogue$
DECLARE
  v_attendu record;
  v_appelants text;
BEGIN
  IF session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS : maintenance isolée requise (postgres)';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id::text LIKE 'b9c10000-%')
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id::text LIKE 'b9c10000-%')
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS : identifiants de fixture déjà présents'; END IF;

  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_creer_notification(uuid,text,text,text,text,text,text,uuid)', 'bc337810f500768fed6748fac74265e8', false),
      ('public.fn_alerter_pool_urgence(uuid)', '5b86dde9fb3450ac0e654512e3819dfc', true),
      ('public.fn_admin_relancer_mandat_facturation(uuid)', 'fe171f70cf862988022d487ea962d104', true),
      ('public.fn_top_soignants(text,integer)', '50122640d61db0021246adba36f8a2d3', true)
    ) AS t(signature, empreinte, authenticated)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(v_attendu.signature)) IS DISTINCT FROM v_attendu.empreinte
       OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = to_regprocedure(v_attendu.signature)) IS NOT TRUE
       OR has_function_privilege('anon', v_attendu.signature, 'EXECUTE')
       OR has_function_privilege('authenticated', v_attendu.signature, 'EXECUTE') IS DISTINCT FROM v_attendu.authenticated
       OR NOT has_function_privilege('service_role', v_attendu.signature, 'EXECUTE')
       OR NOT EXISTS (SELECT 1 FROM private.security_definer_inventory i
                       WHERE 'public.' || i.signature = v_attendu.signature AND i.definition_md5 = v_attendu.empreinte)
    THEN RAISE EXCEPTION 'B9_NOTIFICATIONS A0 : corps, droits ou inventaire inattendus pour %', v_attendu.signature; END IF;
  END LOOP;
  IF (SELECT categorie FROM private.security_definer_inventory
       WHERE signature = 'fn_creer_notification(uuid,text,text,text,text,text,text,uuid)') IS DISTINCT FROM 'SERVICE_ONLY_REVOQUE'
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS A0 : catégorie d''inventaire de fn_creer_notification inattendue'; END IF;
  IF pg_get_function_result('public.fn_top_soignants(text,integer)'::regprocedure)
     IS DISTINCT FROM 'TABLE(prenom text, nom text, profession text, note_moyenne numeric, score_fiabilite integer, total_missions_terminees integer)'
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS D0 : colonnes du classement inattendues'; END IF;

  -- Appelants de fn_creer_notification : SECURITY DEFINER de postgres, ou jamais
  -- exécutés sous un rôle utilisateur (ni déclencheur, ni EXECUTE anon/authenticated).
  SELECT string_agg(p.oid::regprocedure::text, ', ')
    INTO v_appelants
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
     AND p.prosrc ILIKE '%fn_creer_notification%'
     AND p.oid <> 'public.fn_creer_notification(uuid,text,text,text,text,text,text,uuid)'::regprocedure
     AND ((p.prosecdef AND pg_get_userbyid(p.proowner) <> 'postgres')
       OR (NOT p.prosecdef AND (p.prorettype = 'trigger'::regtype
            OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
            OR has_function_privilege('anon', p.oid, 'EXECUTE'))));
  IF v_appelants IS NOT NULL THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS A0 : appelant exécuté sous un rôle utilisateur : %', v_appelants;
  END IF;
END
$b9_catalogue$;

-- ── 2. Fixtures (contexte service, SQL Auth direct) ────────────────────────
-- 01-02 soignants réels, 03-04 soignants de test, 05 soignant réel supprimé,
-- 06 compte soignant sans profil, 10 administrateur, 20-21 établissements réels,
-- 30 mission urgente ouverte et 31 mission ouverte non urgente de l'établissement 20.
-- Inscriptions publiques actives le temps de la transaction : sans elles, tout nouveau
-- compte est classé dans la cohorte de test (private.fn_forcer_compte_test_prelaunch).
INSERT INTO public.parametres_systeme (cle, valeur, label, description, unite, val_min, val_max, categorie, avertissement, cablee)
VALUES ('inscriptions_publiques_actives', 1, 'Inscriptions publiques actives', 'Fixture B9 notifications (transaction annulée).',
        'booléen', 0, 1, 'GENERAL', 'Fixture.', true)
ON CONFLICT (cle) DO UPDATE SET valeur = 1;
INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
SELECT ('b9c10000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-000000000000'::uuid,
       'b9-notifications-' || n || '@example.invalid', 'authenticated', 'authenticated',
       jsonb_build_object('role', CASE WHEN n <= 6 THEN 'SOIGNANT' WHEN n = 10 THEN 'ADMIN_PLATEFORME'
                                       ELSE 'ADMIN_ETABLISSEMENT' END,
                          'est_compte_test', n IN (3, 4)), now()
  FROM unnest(ARRAY[1, 2, 3, 4, 5, 6, 10, 20, 21]) n;

INSERT INTO public.soignants (id, prenom, nom, email, profession, est_compte_test, disponible_urgence, date_naissance)
SELECT ('b9c10000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       (ARRAY['B9ReelUn', 'B9ReelDeux', 'B9TestUn', 'B9TestDeux', 'B9Supprime'])[n],
       (ARRAY['Rémond', 'roussel', 'Thiers', 'Tavel', 'Sorel'])[n],
       'b9-notifications-' || n || '@example.invalid', 'AUXILIAIRE_PUERICULTURE', n IN (3, 4), n = 1, date '1990-01-15'
  FROM generate_series(1, 5) n;

INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact, est_compte_test)
SELECT ('b9c10000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'Fixture B9 ' || n, '9919400000' || lpad(n::text, 4, '0'), 'CLINIQUE_PRIVEE',
       '1 rue du Test', 'Paris', '75001', 'b9-notifications-' || n || '@example.invalid', false
  FROM unnest(ARRAY[20, 21]) n;

INSERT INTO public.equipe_admin (user_id, nom, prenom, email, actif, acces_groupes)
VALUES ('b9c10000-0000-4000-8000-000000000010', 'Fixture', 'Admin', 'b9-notifications-10@example.invalid', true,
        ARRAY['Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats', 'Finances', 'Messagerie',
              'Conformité & Technique', 'Fondateur']::text[]);

-- Pièces vérifiées (CNI et diplôme, seules exigées pour AUXILIAIRE_PUERICULTURE),
-- puis note maximale pour placer les fixtures en tête de leur profession.
INSERT INTO public.documents_soignants (soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
  est_critique, valide_jusqua, resultat_ia)
SELECT ('b9c10000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, d.type_document::public.type_document,
       'tests/b9-notifications/' || n || '/' || lower(d.type_document), lower(d.type_document) || '.pdf',
       'VERIFIE', true, d.valide_jusqua, d.resultat_ia::jsonb
  FROM generate_series(1, 5) n,
       (VALUES ('CARTE_IDENTITE', current_date + 365, '{}'),
               ('DIPLOME', NULL::date, '{"profession_certifiee":"AUXILIAIRE_PUERICULTURE"}'))
         AS d(type_document, valide_jusqua, resultat_ia);
SELECT set_config('jolene.system_update', 'true', true);
UPDATE public.soignants SET note_moyenne = 5.00, identite_verifiee = true, diplome_verifie = true
 WHERE id::text LIKE 'b9c10000-%';
UPDATE public.soignants SET supprime_le = now() - interval '1 day'
 WHERE id = 'b9c10000-0000-4000-8000-000000000005';
SELECT set_config('jolene.system_update', '', true);

SELECT public.fn_test_seed_mission(jsonb_build_object(
  'id', 'b9c10000-0000-4000-8000-0000000000' || m.suffixe,
  'etablissement_id', 'b9c10000-0000-4000-8000-000000000020',
  'intitule', m.intitule, 'profession_requise', 'AUXILIAIRE_PUERICULTURE',
  'debut_le', date_trunc('hour', now()) + interval '3 days 8 hours',
  'fin_le', date_trunc('hour', now()) + interval '3 days 14 hours',
  'taux_horaire_base', 25, 'statut', 'OUVERTE', 'est_urgente', m.urgente,
  'type_contrat_recherche', 'SALARIE'))
  FROM (VALUES ('30', 'Fixture B9 urgente', true), ('31', 'Fixture B9 non urgente', false)) AS m(suffixe, intitule, urgente);
SELECT set_config('app.internal_operation', '', true);
SELECT set_config('jolene.creer_mission_context', '', true);
SELECT set_config('app.test_bypass_protections', '', true);
-- La création de la mission urgente a notifié le pool d'alors (trg_auto_notify_mission_urgente) ;
-- le soignant 02 devient disponible ensuite : seule une alerte manuelle peut le prévenir.
SELECT set_config('jolene.system_update', 'true', true);
UPDATE public.soignants SET disponible_urgence = true WHERE id = 'b9c10000-0000-4000-8000-000000000002';
SELECT set_config('jolene.system_update', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

DO $b9_fixtures$
BEGIN
  IF (SELECT disponible_urgence FROM public.soignants WHERE id = 'b9c10000-0000-4000-8000-000000000002') IS NOT TRUE
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS : disponibilité du soignant 02 non posée'; END IF;
  IF (SELECT count(*) FROM public.soignants s
       WHERE s.id::text LIKE 'b9c10000-%' AND s.supprime_le IS NULL
         AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')) <> 4
     OR (SELECT count(*) FROM public.missions WHERE id::text LIKE 'b9c10000-%' AND statut = 'OUVERTE') <> 2
     OR (SELECT est_compte_test FROM public.soignants WHERE id = 'b9c10000-0000-4000-8000-000000000003') IS NOT TRUE
     OR (SELECT est_compte_test FROM public.soignants WHERE id = 'b9c10000-0000-4000-8000-000000000001') IS NOT FALSE
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS : fixtures inattendues'; END IF;
END
$b9_fixtures$;

-- ── A. fn_creer_notification : plus aucun appel direct ─────────────────────
SET LOCAL ROLE authenticated;
DO $b9_a_refus$
DECLARE
  v_acteur uuid;
  v_etat text;
BEGIN
  FOREACH v_acteur IN ARRAY ARRAY['b9c10000-0000-4000-8000-000000000001', 'b9c10000-0000-4000-8000-000000000020',
                                  'b9c10000-0000-4000-8000-000000000010']::uuid[] LOOP
    PERFORM set_config('request.jwt.claim.sub', v_acteur::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_acteur, 'role', 'authenticated')::text, true);
    v_etat := NULL;
    BEGIN
      PERFORM public.fn_creer_notification('b9c10000-0000-4000-8000-000000000002', 'SOIGNANT', 'SYSTEM',
        'Hameçonnage', 'Corps arbitraire', 'https://exemple.invalid/', NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE;
    END;
    IF v_etat IS DISTINCT FROM '42501' THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS A1 : notification arbitraire de % (SQLSTATE %)', v_acteur, COALESCE(v_etat, 'aucun refus');
    END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END
$b9_a_refus$;
RESET ROLE;

SET LOCAL ROLE anon;
DO $b9_a_anon$
DECLARE v_etat text;
BEGIN
  BEGIN
    PERFORM public.fn_creer_notification('b9c10000-0000-4000-8000-000000000002', 'SOIGNANT', 'SYSTEM', 'x', 'x', NULL, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE;
  END;
  IF v_etat IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS A2 : anon écrit une notification (SQLSTATE %)', COALESCE(v_etat, 'aucun refus');
  END IF;
  v_etat := NULL;
  BEGIN
    PERFORM count(*) FROM public.fn_top_soignants(NULL, 50);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE;
  END;
  IF v_etat IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS D1 : anon lit le classement (SQLSTATE %)', COALESCE(v_etat, 'aucun refus');
  END IF;
END
$b9_a_anon$;
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
DO $b9_a_service$
BEGIN
  IF public.fn_creer_notification('b9c10000-0000-4000-8000-000000000002', 'SOIGNANT', 'SYSTEM',
       'B9 service', 'Notification de service', NULL, NULL, NULL) IS NULL THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS A3 : service_role ne notifie plus';
  END IF;
END
$b9_a_service$;
SELECT set_config('request.jwt.claims', '', true);
RESET ROLE;

DO $b9_a_effets$
BEGIN
  IF EXISTS (SELECT 1 FROM public.notifications WHERE destinataire_id::text LIKE 'b9c10000-%' AND titre IN ('Hameçonnage', 'x'))
     OR (SELECT count(*) FROM public.notifications
          WHERE destinataire_id = 'b9c10000-0000-4000-8000-000000000002' AND titre = 'B9 service') <> 1
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS A4 : effets inattendus des appels directs'; END IF;
END
$b9_a_effets$;

-- ── B. Alerte du pool d'urgence ────────────────────────────────────────────
-- Destinataires attendus : fn_soignants_urgence, appelée par l'établissement de la mission.
SET LOCAL ROLE authenticated;
DO $b9_b_attendus$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'b9c10000-0000-4000-8000-000000000020', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"b9c10000-0000-4000-8000-000000000020","role":"authenticated"}', true);
  PERFORM set_config('b9.pool_attendu', COALESCE((SELECT string_agg(DISTINCT u.soignant_id::text, ',' ORDER BY u.soignant_id::text)
    FROM public.fn_soignants_urgence('b9c10000-0000-4000-8000-000000000030') u), ''), true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END
$b9_b_attendus$;
RESET ROLE;

DO $b9_b_attendus_controle$
DECLARE
  v_attendu text[] := string_to_array(current_setting('b9.pool_attendu'), ',');
  v_auto text[];
BEGIN
  -- Les deux soignants réels disponibles sont éligibles ; les autres fixtures ne le sont pas
  -- (cohorte de test, indisponibles, profil supprimé).
  IF NOT v_attendu @> ARRAY['b9c10000-0000-4000-8000-000000000001', 'b9c10000-0000-4000-8000-000000000002']
     OR v_attendu && ARRAY['b9c10000-0000-4000-8000-000000000003', 'b9c10000-0000-4000-8000-000000000004',
                           'b9c10000-0000-4000-8000-000000000005']
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS B0 : pool attendu inattendu (%)', current_setting('b9.pool_attendu'); END IF;
  -- Déjà notifiés pour cette mission avant toute alerte manuelle (notification automatique).
  SELECT COALESCE(array_agg(DISTINCT n.destinataire_id::text), ARRAY[]::text[]) INTO v_auto
    FROM public.notifications n
   WHERE n.type = 'MISSION_URGENTE' AND n.id_ressource = 'b9c10000-0000-4000-8000-000000000030';
  IF v_auto && ARRAY['b9c10000-0000-4000-8000-000000000002'] THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS B0 : le soignant 02 est déjà notifié avant l''alerte';
  END IF;
  PERFORM set_config('b9.pool_auto', array_to_string(v_auto, ','), true);
  PERFORM set_config('b9.pool_nouveaux', (SELECT count(*) FROM unnest(v_attendu) a WHERE NOT a = ANY (v_auto))::text, true);
  PERFORM set_config('b9.pool_deja', (SELECT count(*) FROM unnest(v_attendu) a WHERE a = ANY (v_auto))::text, true);
END
$b9_b_attendus_controle$;

SET LOCAL ROLE authenticated;
DO $b9_b_alertes$
DECLARE
  v_cas record;
  v_etat text;
  v_res jsonb;
  v_nouveaux integer := current_setting('b9.pool_nouveaux')::integer;
  v_deja integer := current_setting('b9.pool_deja')::integer;
BEGIN
  -- Refus : soignant, autre établissement, mission absente, sans session, mission non urgente.
  FOR v_cas IN
    SELECT * FROM (VALUES
      ('b9c10000-0000-4000-8000-000000000001', 'b9c10000-0000-4000-8000-000000000030', '42501'),
      ('b9c10000-0000-4000-8000-000000000021', 'b9c10000-0000-4000-8000-000000000030', '42501'),
      ('b9c10000-0000-4000-8000-000000000020', 'b9c10000-0000-4000-8000-000000000099', '42501'),
      ('', 'b9c10000-0000-4000-8000-000000000030', '28000'),
      ('b9c10000-0000-4000-8000-000000000020', 'b9c10000-0000-4000-8000-000000000031', '22023')
    ) AS t(acteur, mission, etat)
  LOOP
    PERFORM set_config('request.jwt.claim.sub', v_cas.acteur, true);
    PERFORM set_config('request.jwt.claims', CASE WHEN v_cas.acteur = '' THEN '{"role":"authenticated"}'
      ELSE jsonb_build_object('sub', v_cas.acteur, 'role', 'authenticated')::text END, true);
    v_etat := NULL;
    BEGIN
      PERFORM public.fn_alerter_pool_urgence(v_cas.mission::uuid);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE;
    END;
    IF v_etat IS DISTINCT FROM v_cas.etat THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS B1 : alerte de % sur % : SQLSTATE % au lieu de %',
        COALESCE(NULLIF(v_cas.acteur, ''), 'sans session'), v_cas.mission, COALESCE(v_etat, 'aucun refus'), v_cas.etat;
    END IF;
  END LOOP;

  -- Établissement de la mission : les soignants du pool pas encore notifiés le sont, une fois.
  PERFORM set_config('request.jwt.claim.sub', 'b9c10000-0000-4000-8000-000000000020', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"b9c10000-0000-4000-8000-000000000020","role":"authenticated"}', true);
  v_res := public.fn_alerter_pool_urgence('b9c10000-0000-4000-8000-000000000030');
  IF v_nouveaux < 1
     OR v_res IS DISTINCT FROM jsonb_build_object('success', true, 'notifies', v_nouveaux, 'deja_notifies', v_deja) THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS B2 : première alerte inattendue (% ; % nouveaux et % déjà notifiés attendus)',
      v_res, v_nouveaux, v_deja;
  END IF;
  -- Administrateur, seconde alerte : aucun doublon.
  PERFORM set_config('request.jwt.claim.sub', 'b9c10000-0000-4000-8000-000000000010', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"b9c10000-0000-4000-8000-000000000010","role":"authenticated"}', true);
  v_res := public.fn_alerter_pool_urgence('b9c10000-0000-4000-8000-000000000030');
  IF v_res IS DISTINCT FROM jsonb_build_object('success', true, 'notifies', 0, 'deja_notifies', v_nouveaux + v_deja) THEN
    RAISE EXCEPTION 'B9_NOTIFICATIONS B3 : seconde alerte inattendue (%)', v_res;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END
$b9_b_alertes$;
RESET ROLE;

DO $b9_b_effets$
DECLARE
  v_debut timestamptz := (SELECT debut_le FROM public.missions WHERE id = 'b9c10000-0000-4000-8000-000000000030');
  v_attendu text[] := string_to_array(current_setting('b9.pool_attendu'), ',');
  v_auto text[] := string_to_array(NULLIF(current_setting('b9.pool_auto'), ''), ',');
BEGIN
  -- Une seule notification MISSION_URGENTE par soignant du pool pour cette mission.
  IF EXISTS (SELECT 1 FROM unnest(v_attendu) a
              WHERE (SELECT count(*) FROM public.notifications n
                      WHERE n.destinataire_id = a::uuid AND n.type = 'MISSION_URGENTE'
                        AND n.id_ressource = 'b9c10000-0000-4000-8000-000000000030') <> 1)
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS B4 : doublon ou absence de notification dans le pool'; END IF;
  -- Les notifications de l'alerte manuelle : destinataires non encore notifiés, texte et lien du serveur.
  IF (SELECT array_agg(n.destinataire_id::text ORDER BY n.destinataire_id::text) FROM public.notifications n
       WHERE n.type = 'MISSION_URGENTE' AND n.id_ressource = 'b9c10000-0000-4000-8000-000000000030'
         AND n.type_ressource = 'MISSION')
       IS DISTINCT FROM (SELECT array_agg(a ORDER BY a) FROM unnest(v_attendu) a WHERE NOT a = ANY (COALESCE(v_auto, ARRAY[]::text[])))
     OR EXISTS (SELECT 1 FROM public.notifications n
                 WHERE n.type = 'MISSION_URGENTE' AND n.id_ressource = 'b9c10000-0000-4000-8000-000000000030'
                   AND n.type_ressource = 'MISSION'
                   AND (n.type_destinataire <> 'SOIGNANT'
                     OR n.titre <> '🚨 Mission urgente : Fixture B9 urgente'
                     OR n.corps <> 'Fixture B9 urgente — ' || to_char(v_debut AT TIME ZONE 'Europe/Paris', 'DD/MM "à" HH24:MI')
                                   || '. Premier arrivé, premier servi !'
                     OR n.lien <> '/soignant/missions/b9c10000-0000-4000-8000-000000000030'))
     OR EXISTS (SELECT 1 FROM public.notifications n WHERE n.id_ressource = 'b9c10000-0000-4000-8000-000000000031')
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS B5 : notifications de l''alerte manuelle inattendues'; END IF;
END
$b9_b_effets$;

-- ── C. Relance du mandat de facturation ────────────────────────────────────
SET LOCAL ROLE authenticated;
DO $b9_c_relance$
DECLARE
  v_cas record;
  v_etat text;
  v_id uuid;
BEGIN
  FOR v_cas IN
    SELECT * FROM (VALUES
      ('b9c10000-0000-4000-8000-000000000001', 'b9c10000-0000-4000-8000-000000000002', '42501'),
      ('b9c10000-0000-4000-8000-000000000020', 'b9c10000-0000-4000-8000-000000000002', '42501'),
      ('b9c10000-0000-4000-8000-000000000010', 'b9c10000-0000-4000-8000-000000000099', 'P0002'),
      ('b9c10000-0000-4000-8000-000000000010', 'b9c10000-0000-4000-8000-000000000005', 'P0002')
    ) AS t(acteur, soignant, etat)
  LOOP
    PERFORM set_config('request.jwt.claim.sub', v_cas.acteur, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_cas.acteur, 'role', 'authenticated')::text, true);
    v_etat := NULL;
    BEGIN
      PERFORM public.fn_admin_relancer_mandat_facturation(v_cas.soignant::uuid);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE;
    END;
    IF v_etat IS DISTINCT FROM v_cas.etat THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS C1 : relance de % pour % : SQLSTATE % au lieu de %',
        v_cas.acteur, v_cas.soignant, COALESCE(v_etat, 'aucun refus'), v_cas.etat;
    END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', 'b9c10000-0000-4000-8000-000000000010', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"b9c10000-0000-4000-8000-000000000010","role":"authenticated"}', true);
  v_id := public.fn_admin_relancer_mandat_facturation('b9c10000-0000-4000-8000-000000000002');
  PERFORM set_config('b9.relance_id', v_id::text, true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END
$b9_c_relance$;
RESET ROLE;

DO $b9_c_effets$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.notifications n
                  WHERE n.id = current_setting('b9.relance_id')::uuid
                    AND n.destinataire_id = 'b9c10000-0000-4000-8000-000000000002'
                    AND n.type_destinataire = 'SOIGNANT' AND n.type = 'RAPPEL_DOCUMENTS'
                    AND n.titre = 'Signez votre mandat de facturation'
                    AND n.lien = '/soignant/mandat-facturation'
                    AND n.corps LIKE 'Votre mandat de facturation attend votre signature.%')
     OR (SELECT count(*) FROM public.notifications WHERE type = 'RAPPEL_DOCUMENTS' AND destinataire_id::text LIKE 'b9c10000-%') <> 1
  THEN RAISE EXCEPTION 'B9_NOTIFICATIONS C2 : relance inattendue'; END IF;
END
$b9_c_effets$;

-- ── D. Classement ──────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
DO $b9_d_classement$
DECLARE
  v_cas record;
  v_lus text;
  v_total integer;
  v_noms_complets integer;
BEGIN
  FOR v_cas IN
    SELECT * FROM (VALUES
      ('b9c10000-0000-4000-8000-000000000001', 'B9ReelDeux:R.,B9ReelUn:R.'),     -- soignant réel
      ('b9c10000-0000-4000-8000-000000000003', 'B9TestDeux:T.,B9TestUn:T.'),     -- soignant de test
      ('b9c10000-0000-4000-8000-000000000010', 'B9ReelDeux:R.,B9ReelUn:R.'),     -- administrateur
      ('b9c10000-0000-4000-8000-000000000020', NULL),                            -- établissement
      ('b9c10000-0000-4000-8000-000000000006', NULL),                            -- compte sans profil
      ('b9c10000-0000-4000-8000-000000000005', NULL),                            -- profil supprimé
      ('', NULL)                                                                 -- sans session
    ) AS t(acteur, attendu)
  LOOP
    PERFORM set_config('request.jwt.claim.sub', v_cas.acteur, true);
    PERFORM set_config('request.jwt.claims', CASE WHEN v_cas.acteur = '' THEN '{"role":"authenticated"}'
      ELSE jsonb_build_object('sub', v_cas.acteur, 'role', 'authenticated')::text END, true);
    SELECT string_agg(c.prenom || ':' || c.nom, ',' ORDER BY c.prenom) FILTER (WHERE c.prenom LIKE 'B9%'),
           count(*),
           count(*) FILTER (WHERE c.nom IS NOT NULL AND c.nom !~ '^.\.$')
      INTO v_lus, v_total, v_noms_complets
      FROM public.fn_top_soignants('AUXILIAIRE_PUERICULTURE', 50) c;
    IF v_lus IS DISTINCT FROM v_cas.attendu OR v_noms_complets <> 0
       OR (v_cas.attendu IS NULL AND v_total <> 0) THEN
      RAISE EXCEPTION 'B9_NOTIFICATIONS D2 : classement vu par % : % (% lignes, % noms complets), attendu %',
        COALESCE(NULLIF(v_cas.acteur, ''), 'sans session'), v_lus, v_total, v_noms_complets, v_cas.attendu;
    END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END
$b9_d_classement$;
RESET ROLE;

ROLLBACK;
