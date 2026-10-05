-- Native witness candidate. Only in a NEW disposable cluster and database
-- named jolene_b21_semantics_test, under the same pinned PostgreSQL 17.6 image.
-- psql -X -v ON_ERROR_STOP=1 is required; accept output only after exit 0.
BEGIN;
SET LOCAL statement_timeout='45s';
SET LOCAL search_path=pg_catalog;
DO $guard$
BEGIN
 IF current_database()<>'jolene_b21_semantics_test' OR inet_server_addr() IS NOT NULL
 OR session_user<>'postgres' OR current_user<>session_user
 OR current_setting('server_version_num')<>'170006'
 OR current_setting('cron.launch_active_jobs')<>'off'
 OR current_setting('max_worker_processes')<>'0'
 OR EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('b21_owner','b21_reader','b21_delegate','b21_member','b21_other_owner'))
 OR EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='b21_fixture')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_SYNTHETIC_CONTEXT'; END IF;
END $guard$;
CREATE ROLE b21_owner NOLOGIN;
CREATE ROLE b21_reader NOLOGIN;
CREATE ROLE b21_delegate NOLOGIN;
CREATE ROLE b21_member NOLOGIN INHERIT;
CREATE ROLE b21_other_owner NOLOGIN;
CREATE SCHEMA b21_fixture;
-- B21_CAPTURE_FUNCTION
CREATE TEMP TABLE b21_cases(name text PRIMARY KEY, left_fact jsonb, right_fact jsonb);
CREATE FUNCTION b21_fixture.fact(r regclass) RETURNS jsonb LANGUAGE sql VOLATILE AS $fact$
 SELECT v FROM jsonb_array_elements(b21_fixture.capture()->'relations') q(v)
 JOIN pg_class c ON c.oid=r JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE v->'identity'=jsonb_build_array(n.nspname,c.relname)
$fact$;
GRANT USAGE,CREATE ON SCHEMA b21_fixture TO b21_owner;
GRANT USAGE ON SCHEMA b21_fixture TO b21_reader,b21_delegate,b21_member;

CREATE FUNCTION b21_fixture.acl_tuples(a aclitem[]) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $function$
 SELECT coalesce(jsonb_agg(t ORDER BY t::text),'[]'::jsonb) FROM (
  SELECT jsonb_build_array(CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE 'ROLE' END,
   CASE WHEN x.grantee=0 THEN NULL ELSE pg_get_userbyid(x.grantee) END,
   pg_get_userbyid(x.grantor),x.privilege_type,x.is_grantable) t
  FROM aclexplode(a) x) q
$function$;
CREATE FUNCTION b21_fixture.relation_acl(r regclass) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $function$
 SELECT b21_fixture.acl_tuples(coalesce(c.relacl,
  acldefault(CASE WHEN c.relkind='S' THEN 's'::"char" ELSE 'r'::"char" END,c.relowner)))
 FROM pg_class c WHERE c.oid=r AND c.relkind IN('r','p','v','m','f','S')
$function$;

SET LOCAL ROLE b21_owner;
CREATE TABLE b21_fixture.null_acl(id integer);
CREATE TABLE b21_fixture.explicit_default(id integer);
CREATE TABLE b21_fixture.empty_acl(id integer);
CREATE TABLE b21_fixture.order_a(id integer);
CREATE TABLE b21_fixture.order_b(id integer);
CREATE TABLE b21_fixture.grantor_a(id integer);
CREATE TABLE b21_fixture.grantor_b(id integer);
CREATE SEQUENCE b21_fixture.null_sequence;
CREATE SEQUENCE b21_fixture.explicit_sequence;
GRANT SELECT ON b21_fixture.explicit_default TO b21_reader;
REVOKE SELECT ON b21_fixture.explicit_default FROM b21_reader;
REVOKE ALL ON b21_fixture.empty_acl FROM b21_owner;
GRANT USAGE ON SEQUENCE b21_fixture.explicit_sequence TO b21_reader;
REVOKE USAGE ON SEQUENCE b21_fixture.explicit_sequence FROM b21_reader;
GRANT SELECT ON b21_fixture.order_a TO b21_reader;
GRANT UPDATE ON b21_fixture.order_a TO b21_delegate;
GRANT UPDATE ON b21_fixture.order_b TO b21_delegate;
GRANT SELECT ON b21_fixture.order_b TO b21_reader;
GRANT SELECT ON b21_fixture.grantor_a,b21_fixture.grantor_b TO b21_delegate WITH GRANT OPTION;
GRANT SELECT ON b21_fixture.grantor_a TO b21_reader;
RESET ROLE;
SET LOCAL ROLE b21_delegate;
GRANT SELECT ON b21_fixture.grantor_b TO b21_reader;
RESET ROLE;

DO $checks$
DECLARE a aclitem[]; b aclitem[]; owner_id oid;
BEGIN
 SELECT relacl,relowner INTO a,owner_id FROM pg_class WHERE oid='b21_fixture.null_acl'::regclass;
 SELECT relacl INTO b FROM pg_class WHERE oid='b21_fixture.explicit_default'::regclass;
 IF a IS NOT NULL OR b IS NULL OR b21_fixture.relation_acl('b21_fixture.null_acl')
  IS DISTINCT FROM b21_fixture.relation_acl('b21_fixture.explicit_default')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_NULL_DEFAULT'; END IF;
 SELECT relacl INTO b FROM pg_class WHERE oid='b21_fixture.empty_acl'::regclass;
 IF b IS NULL OR cardinality(b)<>0
  OR b21_fixture.relation_acl('b21_fixture.null_acl')=b21_fixture.relation_acl('b21_fixture.empty_acl')
  OR has_table_privilege('b21_owner','b21_fixture.empty_acl','SELECT')
  OR NOT has_table_privilege('b21_owner','b21_fixture.empty_acl','SELECT WITH GRANT OPTION')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_NULL_EMPTY_OWNER'; END IF;
 IF b21_fixture.relation_acl('b21_fixture.null_sequence') IS DISTINCT FROM b21_fixture.relation_acl('b21_fixture.explicit_sequence')
  OR b21_fixture.acl_tuples(acldefault('s',owner_id))=b21_fixture.acl_tuples(acldefault('r',owner_id))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_SEQUENCE_TYPE'; END IF;
 SELECT relacl INTO a FROM pg_class WHERE oid='b21_fixture.order_a'::regclass;
 SELECT relacl INTO b FROM pg_class WHERE oid='b21_fixture.order_b'::regclass;
 IF a=b OR b21_fixture.relation_acl('b21_fixture.order_a') IS DISTINCT FROM b21_fixture.relation_acl('b21_fixture.order_b')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_ORDER'; END IF;
 IF b21_fixture.relation_acl('b21_fixture.grantor_a')=b21_fixture.relation_acl('b21_fixture.grantor_b')
  OR NOT has_table_privilege('b21_reader','b21_fixture.grantor_a','SELECT')
  OR NOT has_table_privilege('b21_reader','b21_fixture.grantor_b','SELECT')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_GRANTOR_PRESERVED'; END IF;
END $checks$;
INSERT INTO b21_cases VALUES
 ('NULL_DEFAULT',b21_fixture.fact('b21_fixture.null_acl'),b21_fixture.fact('b21_fixture.explicit_default')),
 ('NULL_EMPTY',b21_fixture.fact('b21_fixture.null_acl'),b21_fixture.fact('b21_fixture.empty_acl')),
 ('SEQUENCE_DEFAULT',b21_fixture.fact('b21_fixture.null_sequence'),b21_fixture.fact('b21_fixture.explicit_sequence')),
 ('SEQUENCE_TABLE',b21_fixture.fact('b21_fixture.null_sequence'),b21_fixture.fact('b21_fixture.null_acl')),
 ('ORDER',b21_fixture.fact('b21_fixture.order_a'),b21_fixture.fact('b21_fixture.order_b')),
 ('GRANTOR',b21_fixture.fact('b21_fixture.grantor_a'),b21_fixture.fact('b21_fixture.grantor_b'));

-- A real REVOKE must stay different under the proposed tuple expansion.
SET LOCAL ROLE b21_owner;
REVOKE SELECT ON b21_fixture.order_b FROM b21_reader;
RESET ROLE;
DO $negative$
BEGIN
 IF b21_fixture.relation_acl('b21_fixture.order_a')=b21_fixture.relation_acl('b21_fixture.order_b')
  OR NOT has_table_privilege('b21_reader','b21_fixture.order_a','SELECT')
  OR has_table_privilege('b21_reader','b21_fixture.order_b','SELECT')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_REAL_REVOKE_NOT_REJECTED'; END IF;
END $negative$;
INSERT INTO b21_cases VALUES ('REAL_REVOKE',b21_fixture.fact('b21_fixture.order_a'),b21_fixture.fact('b21_fixture.order_b'));

-- Equal effective SELECT does not allow erasing grant option or owner identity.
SET LOCAL ROLE b21_owner;
GRANT SELECT ON b21_fixture.order_b TO b21_reader WITH GRANT OPTION;
RESET ROLE;
DO $option$
BEGIN
 IF b21_fixture.relation_acl('b21_fixture.order_a')=b21_fixture.relation_acl('b21_fixture.order_b')
 OR has_table_privilege('b21_reader','b21_fixture.order_a','SELECT WITH GRANT OPTION')
 OR NOT has_table_privilege('b21_reader','b21_fixture.order_b','SELECT WITH GRANT OPTION')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_GRANT_OPTION'; END IF;
END $option$;
INSERT INTO b21_cases VALUES ('GRANT_OPTION',b21_fixture.fact('b21_fixture.order_a'),b21_fixture.fact('b21_fixture.order_b'));
ALTER TABLE b21_fixture.explicit_default OWNER TO b21_other_owner;
DO $owner$
BEGIN
 IF b21_fixture.relation_acl('b21_fixture.null_acl')=b21_fixture.relation_acl('b21_fixture.explicit_default')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_OWNER'; END IF;
END $owner$;
INSERT INTO b21_cases VALUES ('OWNER',b21_fixture.fact('b21_fixture.null_acl'),b21_fixture.fact('b21_fixture.explicit_default'));

GRANT b21_delegate TO b21_member WITH INHERIT TRUE;
DO $inherit_on$
BEGIN
 IF NOT has_table_privilege('b21_member','b21_fixture.grantor_a','SELECT')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_INHERIT_ON'; END IF;
END $inherit_on$;
GRANT b21_delegate TO b21_member WITH INHERIT FALSE;
DO $inherit_off$
BEGIN
 IF has_table_privilege('b21_member','b21_fixture.grantor_a','SELECT')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_INHERIT_OFF'; END IF;
END $inherit_off$;

ALTER DEFAULT PRIVILEGES FOR ROLE b21_owner GRANT SELECT ON TABLES TO b21_reader;
SET LOCAL ROLE b21_owner;
CREATE TABLE b21_fixture.created_after_default_change(id integer);
RESET ROLE;
DO $default_scope$
BEGIN
 IF (SELECT relacl IS NOT NULL FROM pg_class WHERE oid='b21_fixture.null_acl'::regclass)
 OR has_table_privilege('b21_reader','b21_fixture.null_acl','SELECT')
 OR NOT has_table_privilege('b21_reader','b21_fixture.created_after_default_change','SELECT')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_DEFAULT_CREATION_ONLY'; END IF;
END $default_scope$;
SELECT jsonb_build_object('schemaVersion',1,'status','SYNTHETIC_WITNESSES_PASSED',
 'nullDefault',true,'nullEmptyDistinct',true,'ownerImplicitGrantOption',true,
 'sequenceTypeDistinct',true,'orderOnly',true,'grantorPreserved',true,'realRevokeRejected',true,
 'grantOptionPreserved',true,'ownerPreserved',true,'inheritOptionPreserved',true,'creationDefaultsOnly',true,
 'cases',(SELECT jsonb_agg(jsonb_build_object('name',name,'left',left_fact,'right',right_fact) ORDER BY name) FROM b21_cases));
ROLLBACK;
