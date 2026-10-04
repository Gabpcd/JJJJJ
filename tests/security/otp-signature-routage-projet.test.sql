-- Exécute le corps installé avec dépendances temporaires et transport capturé.
-- Aucun Vault réel, OTP existant, profil ou prestataire n'est lu/appelé.
-- Le test complet est annulé, y compris les fonctions de capture.
BEGIN;

CREATE TEMP TABLE otp_vault_config(name text PRIMARY KEY, decrypted_secret text);
CREATE TEMP TABLE otp_comptes_fictifs(user_id uuid PRIMARY KEY, actif boolean NOT NULL);
CREATE TEMP TABLE soignants(id uuid PRIMARY KEY, telephone text);
CREATE TEMP TABLE etablissements(id uuid PRIMARY KEY, telephone_contact text);
CREATE TEMP TABLE contrats_mission(
  id uuid PRIMARY KEY, soignant_id uuid, etablissement_id uuid, contenu_html text,
  statut text, signature_soignant boolean, signature_etablissement boolean
);
CREATE TEMP TABLE signatures_contrats(
  contrat_id uuid, signataire_user_id uuid, signataire_role text,
  otp_envoye_a timestamptz, otp_code_hash text, statut_signature text,
  audit_trail jsonb, sms_envoyes_count integer, sms_premier_envoi_a timestamptz,
  otp_tentatives integer DEFAULT 0, modifie_le timestamptz,
  UNIQUE(contrat_id, signataire_role)
);
CREATE TEMP TABLE otp_routes_capturees(
  url text, authentification_fictive_correcte boolean, payload_correct boolean
);

CREATE FUNCTION pg_temp.otp_capturer_transport(url text, headers jsonb, body jsonb)
RETURNS bigint LANGUAGE plpgsql AS $capture$
BEGIN
  -- Le contenu OTP et les headers ne sont jamais conservés ni affichés.
  INSERT INTO pg_temp.otp_routes_capturees VALUES (
    url,
    headers->>'Authorization' = 'Bearer cle-fictive-locale-sans-validite',
    headers->>'Content-Type' = 'application/json'
      AND body->>'type' = 'OTP_SIGNATURE'
      AND body->>'prefix_type' = 'SIGNATURE'
      AND body->>'idempotency_key' LIKE 'otp-signature.%'
      AND body->'data'->>'contrat_id' = '97600000-0000-4000-8000-000000000003'
  );
  RETURN 1;
END;
$capture$;
-- Seule la dépendance Auth de la copie temporaire est simulée. La garde
-- installée reste exigée ci-dessous ; son comportement réel est qualifié par
-- signature-otp-pg17, avec comptes bannis/supprimés et rôles canoniques.
CREATE FUNCTION pg_temp.otp_compte_auth_actif() RETURNS boolean
LANGUAGE sql STABLE AS $compte_fictif$
  SELECT COALESCE((SELECT actif FROM pg_temp.otp_comptes_fictifs
                  WHERE user_id = auth.uid()), false)
$compte_fictif$;
CREATE FUNCTION pg_temp.otp_rate_limit(inet) RETURNS jsonb
LANGUAGE sql AS $$ SELECT '{"allowed":true}'::jsonb $$;
CREATE FUNCTION pg_temp.otp_etab_id() RETURNS uuid
LANGUAGE sql AS $$ SELECT NULL::uuid $$;

DO $isoler_dependances$
DECLARE definition text;
BEGIN
  definition := pg_get_functiondef('public.fn_envoyer_otp_signature(uuid)'::regprocedure);
  IF position('IF public.fn_compte_auth_actif() IS NOT TRUE THEN' IN definition) = 0 THEN
    RAISE EXCEPTION 'Garde du compte actif absente du corps installé';
  END IF;
  definition := replace(definition, 'public.fn_compte_auth_actif()', 'pg_temp.otp_compte_auth_actif()');
  definition := replace(definition,
    'FUNCTION public.fn_envoyer_otp_signature(', 'FUNCTION pg_temp.otp_routage_sous_test(');
  definition := replace(definition, 'vault.decrypted_secrets', 'pg_temp.otp_vault_config');
  definition := replace(definition, 'public.soignants', 'pg_temp.soignants');
  definition := replace(definition, 'public.etablissements', 'pg_temp.etablissements');
  definition := replace(definition, 'public.contrats_mission', 'pg_temp.contrats_mission');
  definition := replace(definition, 'public.signatures_contrats', 'pg_temp.signatures_contrats');
  definition := replace(definition, 'public.fn_check_rate_limit_ip_signature', 'pg_temp.otp_rate_limit');
  definition := replace(definition, 'public.mon_etablissement_id()', 'pg_temp.otp_etab_id()');
  definition := replace(definition, 'net.http_post(', 'pg_temp.otp_capturer_transport(');
  IF definition NOT LIKE '%FUNCTION pg_temp.otp_routage_sous_test(%'
     OR definition LIKE '%net.http_post%'
     OR definition LIKE '%vault.decrypted_secrets%'
     OR definition LIKE '%public.fn_compte_auth_actif()%'
     OR position('IF pg_temp.otp_compte_auth_actif() IS NOT TRUE THEN' IN definition) = 0 THEN
    RAISE EXCEPTION 'Isolation du transport et du Vault impossible';
  END IF;
  EXECUTE definition;
END;
$isoler_dependances$;

INSERT INTO pg_temp.soignants VALUES ('97600000-0000-4000-8000-000000000001', '+33600000001');
INSERT INTO pg_temp.etablissements VALUES ('97600000-0000-4000-8000-000000000002', '+33600000002');
INSERT INTO pg_temp.contrats_mission VALUES (
  '97600000-0000-4000-8000-000000000003',
  '97600000-0000-4000-8000-000000000001',
  '97600000-0000-4000-8000-000000000002', '<p>Document fictif</p>',
  'EN_ATTENTE_SIGNATURES', false, false
);
SELECT set_config('request.jwt.claims', '{"sub":"97600000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '97600000-0000-4000-8000-000000000001', true);
SELECT set_config('request.headers', '{}', true);

DO $compte_inactif$
DECLARE etat text; resultat jsonb;
BEGIN
  INSERT INTO pg_temp.otp_vault_config VALUES
    ('supabase_url', 'https://abcdefghijklmnopqrst.supabase.co'),
    ('service_role_key', 'cle-fictive-locale-sans-validite');
  FOREACH etat IN ARRAY ARRAY['inactif', 'absent'] LOOP
    TRUNCATE pg_temp.otp_comptes_fictifs;
    IF etat = 'inactif' THEN
      INSERT INTO pg_temp.otp_comptes_fictifs VALUES
        ('97600000-0000-4000-8000-000000000001', false);
    END IF;
    resultat := pg_temp.otp_routage_sous_test('97600000-0000-4000-8000-000000000003');
    IF resultat->>'error_code' IS DISTINCT FROM 'NON_AUTORISE'
       OR resultat->>'success' IS DISTINCT FROM 'false'
       OR EXISTS (SELECT 1 FROM pg_temp.signatures_contrats)
       OR EXISTS (SELECT 1 FROM pg_temp.otp_routes_capturees) THEN
      RAISE EXCEPTION 'Compte inactif ou absent : création OTP ou transport non refusé';
    END IF;
  END LOOP;
  INSERT INTO pg_temp.otp_comptes_fictifs VALUES
    ('97600000-0000-4000-8000-000000000001', true);
  TRUNCATE pg_temp.otp_vault_config;
END;
$compte_inactif$;

DO $destinations$
DECLARE projet text; resultat jsonb;
BEGIN
  -- Même fonction : le projet change uniquement via sa configuration locale.
  FOREACH projet IN ARRAY ARRAY[
    'https://mejpriaetwgtcstbgfid.supabase.co',
    'https://flripxtsyegjshnhzjkz.supabase.co',
    'https://abcdefghijklmnopqrst.supabase.co/'
  ] LOOP
    TRUNCATE pg_temp.otp_vault_config, pg_temp.signatures_contrats, pg_temp.otp_routes_capturees;
    INSERT INTO pg_temp.otp_vault_config VALUES
      ('supabase_url', projet), ('service_role_key', 'cle-fictive-locale-sans-validite');
    resultat := pg_temp.otp_routage_sous_test('97600000-0000-4000-8000-000000000003');
    IF resultat->>'success' IS DISTINCT FROM 'true'
       OR resultat->>'role' IS DISTINCT FROM 'soignant'
       OR (SELECT count(*) FROM pg_temp.signatures_contrats) <> 1
       OR (SELECT count(*) FROM pg_temp.otp_routes_capturees) <> 1
       OR NOT EXISTS (SELECT 1 FROM pg_temp.otp_routes_capturees
         WHERE url = rtrim(projet, '/') || '/functions/v1/send-sms'
           AND authentification_fictive_correcte AND payload_correct) THEN
      RAISE EXCEPTION 'Routage OTP ou contrat du transport incorrect';
    END IF;
  END LOOP;
END;
$destinations$;

DO $configurations_invalides$
DECLARE projet text; cle text; resultat jsonb;
BEGIN
  FOREACH projet IN ARRAY ARRAY[
    NULL, '', 'http://mejpriaetwgtcstbgfid.supabase.co',
    'https://mejpriaetwgtcstbgfid.supabase.co.evil.invalid',
    'https://mejpriaetwgtcstbgfid.supabase.co/functions/v1',
    'https://mejpriaetwgtcstbgfid.supabase.co?redirect=autre',
    'https://user@mejpriaetwgtcstbgfid.supabase.co'
  ] LOOP
    TRUNCATE pg_temp.otp_vault_config, pg_temp.signatures_contrats, pg_temp.otp_routes_capturees;
    INSERT INTO pg_temp.otp_vault_config VALUES
      ('supabase_url', projet), ('service_role_key', 'cle-fictive-locale-sans-validite');
    resultat := pg_temp.otp_routage_sous_test('97600000-0000-4000-8000-000000000003');
    IF resultat->>'error_code' IS DISTINCT FROM 'CONFIGURATION_SMS_INDISPONIBLE'
       OR resultat->>'success' IS DISTINCT FROM 'false'
       OR EXISTS (SELECT 1 FROM pg_temp.signatures_contrats)
       OR EXISTS (SELECT 1 FROM pg_temp.otp_routes_capturees) THEN
      RAISE EXCEPTION 'Configuration URL invalide : création OTP ou transport non refusé';
    END IF;
  END LOOP;
  FOREACH cle IN ARRAY ARRAY[NULL, '', '   '] LOOP
    TRUNCATE pg_temp.otp_vault_config;
    INSERT INTO pg_temp.otp_vault_config VALUES
      ('supabase_url', 'https://mejpriaetwgtcstbgfid.supabase.co'), ('service_role_key', cle);
    resultat := pg_temp.otp_routage_sous_test('97600000-0000-4000-8000-000000000003');
    IF resultat->>'error_code' IS DISTINCT FROM 'CONFIGURATION_SMS_INDISPONIBLE'
       OR EXISTS (SELECT 1 FROM pg_temp.signatures_contrats)
       OR EXISTS (SELECT 1 FROM pg_temp.otp_routes_capturees) THEN
      RAISE EXCEPTION 'Configuration authentification absente non refusée';
    END IF;
  END LOOP;
  -- Noms totalement absents du Vault fictif : aucun repli vers la production.
  TRUNCATE pg_temp.otp_vault_config;
  resultat := pg_temp.otp_routage_sous_test('97600000-0000-4000-8000-000000000003');
  IF resultat->>'error_code' IS DISTINCT FROM 'CONFIGURATION_SMS_INDISPONIBLE'
     OR EXISTS (SELECT 1 FROM pg_temp.signatures_contrats)
     OR EXISTS (SELECT 1 FROM pg_temp.otp_routes_capturees) THEN
    RAISE EXCEPTION 'Configuration entièrement absente non refusée';
  END IF;
END;
$configurations_invalides$;

DO $droits_et_inventaire$
BEGIN
  IF has_function_privilege('anon', 'public.fn_envoyer_otp_signature(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_envoyer_otp_signature(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.fn_envoyer_otp_signature(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Droits RPC OTP modifiés';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM private.security_definer_inventory i
    JOIN pg_proc p ON p.oid = 'public.fn_envoyer_otp_signature(uuid)'::regprocedure
    WHERE i.signature = 'fn_envoyer_otp_signature(uuid)'
      AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
      AND i.definition_md5 = md5(p.prosrc) AND p.prosecdef
  ) THEN RAISE EXCEPTION 'Inventaire RPC OTP incohérent'; END IF;
END;
$droits_et_inventaire$;
ROLLBACK;
