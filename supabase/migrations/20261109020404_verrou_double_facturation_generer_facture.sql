-- B9 (SECURITY DEFINER, facturation) — verrou du gap connu « double
-- facturation » de fn_generer_facture(uuid).
-- En attente du go explicite de Gabrielle : pas d'auto-merge (CLAUDE.md B9).
--
-- Décision prise par Claude sur délégation explicite de Gabrielle du
-- 08/11/2026 : verrouiller dans la PR des gardes NULL, par une migration
-- distincte postérieure à 20261109010957 (dont l'invariant « seule la garde
-- change » et le postflight ACL restent intacts).
--
-- Gap (docs/GARDES_NULL_SECURITY_DEFINER.md §5) : la RPC ne refuse qu'une
-- facture dont factures.mission_id = p_mission_id, alors que la facturation
-- courante rattache les missions autrement. Une mission déjà facturée peut
-- recevoir une seconde facture de commission, ensuite prélevée par
-- sepa-auto-charge. Depuis 20261109010957, seuls l'établissement sur sa propre
-- mission et l'admin plateforme pouvaient encore la déclencher, par un appel
-- RPC manuel : le gap restait déclenchable en silence.
--
-- Verrou : REVOKE EXECUTE de PUBLIC, anon et authenticated. service_role garde
-- EXECUTE ; propriétaire, corps, SECURITY DEFINER et search_path inchangés.
-- Tout appel client reçoit 42501 (permission denied). Appelants vérifiés le
-- 09/11/2026 :
--   * dépôt : aucun appel dans src/ (seul le type généré
--     src/integrations/supabase/types.ts la décrit), supabase/functions/,
--     ios-native/, mobile-native/, scripts/ ;
--   * production, lecture seule : 0 job cron.job, 0 fonction pg_proc qui
--     l'appelle, 0 appel dans pg_stat_statements depuis sa remise à zéro du
--     11/08/2026.
-- Les appelants SECURITY DEFINER internes ne sont pas touchés (il n'en existe
-- aucun ; le préflight le vérifie). La facturation de commission passe par
-- les chemins canoniques (factures mensuelles, generate-invoice), inchangés.
-- Inventaire SECURITY DEFINER : catégorie MIXTE_TENANT_ADMIN →
-- SERVICE_ONLY_REVOQUE, empreinte inchangée (corps inchangé).
--
-- Gardes, dans la transaction de la migration, empreintes calculées :
--   * préflight : propriétaire postgres, SECURITY DEFINER, corps corrigé par
--     20261109010957 (garde NULL-safe présente), ACL LIVE attendues
--     (authenticated et service_role, ni anon ni PUBLIC), inventaire
--     MIXTE_TENANT_ADMIN = md5 du corps, aucun appelant pg_proc ni cron ;
--   * postflight : ni PUBLIC, ni anon, ni authenticated ; service_role
--     conservé ; corps inchangé ; inventaire SERVICE_ONLY_REVOQUE = md5 du corps.
-- Un rejeu échoue au préflight (VERROU_FACTURE_PREFLIGHT_ACL_DRIFT).
-- Aucun BEGIN/COMMIT : la CLI possède la transaction.
-- Bancs : tests/security/gardes-null-security-definer.test.sql (staging,
-- annulé), tests/security/gardes-null-security-definer-isolated.test.sql et
-- tests/security/gardes-null-security-definer-rejeu.test.sql (PostgreSQL 17
-- isolé), tests/node/gardes-null-security-definer.node.mjs (statique).
SET LOCAL lock_timeout = '5s';

DO $verrou_facture_avant$
DECLARE
  v_oid oid := pg_catalog.to_regprocedure('public.fn_generer_facture(uuid)');
  p record;
BEGIN
  SELECT pr.prosrc, pr.prosecdef, pr.proacl, pr.proowner,
         pg_catalog.pg_get_userbyid(pr.proowner) AS proprietaire
    INTO p
    FROM pg_catalog.pg_proc pr
   WHERE pr.oid = v_oid;
  IF NOT FOUND
    OR p.proprietaire IS DISTINCT FROM 'postgres'
    OR p.prosecdef IS NOT TRUE
    OR pg_catalog.strpos(p.prosrc,
         'IF NOT est_admin() AND NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) THEN') = 0
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_PREFLIGHT_SOURCE_DRIFT: fn_generer_facture(uuid)';
  END IF;
  IF pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', v_oid, 'EXECUTE')
    OR EXISTS (
      SELECT FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
       WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_PREFLIGHT_ACL_DRIFT: fn_generer_facture(uuid)';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM private.security_definer_inventory i
       WHERE i.signature IN ('fn_generer_facture(uuid)', 'public.fn_generer_facture(uuid)')) <> 1
    OR NOT EXISTS (
      SELECT FROM private.security_definer_inventory i
       WHERE i.signature = 'fn_generer_facture(uuid)'
         AND i.categorie = 'MIXTE_TENANT_ADMIN'
         AND i.definition_md5 = pg_catalog.md5(p.prosrc))
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_PREFLIGHT_INVENTAIRE_DRIFT: fn_generer_facture(uuid)';
  END IF;
  -- Aucun appelant interne : le retrait ne casse aucune fonction ni aucun cron.
  IF EXISTS (
       SELECT FROM pg_catalog.pg_proc pr
        WHERE pr.oid <> v_oid
          AND pr.prosrc ~* 'fn_generer_facture\s*\(')
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_PREFLIGHT_APPELANT_INTERNE: fn_generer_facture(uuid)';
  END IF;
  IF pg_catalog.to_regclass('cron.job') IS NOT NULL THEN
    IF EXISTS (SELECT FROM cron.job j WHERE j.command ~* 'fn_generer_facture\s*\(') THEN
      RAISE EXCEPTION 'VERROU_FACTURE_PREFLIGHT_APPELANT_CRON: fn_generer_facture(uuid)';
    END IF;
  END IF;
END
$verrou_facture_avant$;

REVOKE EXECUTE ON FUNCTION public.fn_generer_facture(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.fn_generer_facture(uuid) IS 'Verrou double facturation (migration 20261109020404, docs/GARDES_NULL_SECURITY_DEFINER.md §5) : EXECUTE retiré à PUBLIC, anon et authenticated ; service_role seul. La facture de commission passe par les chemins canoniques.';

UPDATE private.security_definer_inventory i
   SET categorie = 'SERVICE_ONLY_REVOQUE',
       justification = 'Verrou double facturation (20261109020404) : EXECUTE retiré à authenticated, anon et PUBLIC ; aucun appelant client, interne ni cron. Voir docs/GARDES_NULL_SECURITY_DEFINER.md §5.',
       recense_le = pg_catalog.now()
  FROM pg_catalog.pg_proc pr
 WHERE pr.oid = pg_catalog.to_regprocedure('public.fn_generer_facture(uuid)')
   AND i.signature = 'fn_generer_facture(uuid)'
   AND i.categorie = 'MIXTE_TENANT_ADMIN'
   AND i.definition_md5 = pg_catalog.md5(pr.prosrc);

DO $verrou_facture_apres$
DECLARE
  v_oid oid := pg_catalog.to_regprocedure('public.fn_generer_facture(uuid)');
  p record;
BEGIN
  SELECT pr.prosrc, pr.prosecdef, pr.proacl, pr.proowner,
         pg_catalog.pg_get_userbyid(pr.proowner) AS proprietaire
    INTO p
    FROM pg_catalog.pg_proc pr
   WHERE pr.oid = v_oid;
  IF NOT FOUND
    OR p.proprietaire IS DISTINCT FROM 'postgres'
    OR p.prosecdef IS NOT TRUE
    OR pg_catalog.strpos(p.prosrc,
         'IF NOT est_admin() AND NOT COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false) THEN') = 0
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_POSTFLIGHT_CORPS: fn_generer_facture(uuid)';
  END IF;
  IF pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', v_oid, 'EXECUTE')
    OR EXISTS (
      SELECT FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
       WHERE a.privilege_type = 'EXECUTE'
         AND (a.grantee = 0
              OR a.grantee IN (SELECT r.oid FROM pg_catalog.pg_roles r
                                WHERE r.rolname IN ('anon', 'authenticated'))))
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_POSTFLIGHT_ACL: fn_generer_facture(uuid)';
  END IF;
  IF (SELECT pg_catalog.count(*) FROM private.security_definer_inventory i
       WHERE i.signature IN ('fn_generer_facture(uuid)', 'public.fn_generer_facture(uuid)')) <> 1
    OR NOT EXISTS (
      SELECT FROM private.security_definer_inventory i
       WHERE i.signature = 'fn_generer_facture(uuid)'
         AND i.categorie = 'SERVICE_ONLY_REVOQUE'
         AND i.definition_md5 = pg_catalog.md5(p.prosrc))
  THEN
    RAISE EXCEPTION 'VERROU_FACTURE_POSTFLIGHT_INVENTAIRE: fn_generer_facture(uuid)';
  END IF;
END
$verrou_facture_apres$;

NOTIFY pgrst, 'reload schema';
