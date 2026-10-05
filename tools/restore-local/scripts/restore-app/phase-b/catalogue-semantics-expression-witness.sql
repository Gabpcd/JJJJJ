-- Native witness candidate. Dedicated synthetic cluster, never source/target.
-- These witnesses characterize representation AND real semantic/metadata drift.
BEGIN;
SET LOCAL statement_timeout='45s';
SET LOCAL search_path=pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, YMD';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=3;
SET LOCAL quote_all_identifiers=off;
DO $guard$
BEGIN
 IF current_database()<>'jolene_b21_semantics_test' OR inet_server_addr() IS NOT NULL
 OR session_user<>'postgres' OR current_user<>session_user
 OR current_setting('server_version_num')<>'170006'
 OR current_setting('cron.launch_active_jobs')<>'off'
 OR current_setting('max_worker_processes')<>'0'
 OR EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='b21_expr')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_SYNTHETIC_CONTEXT'; END IF;
END $guard$;
CREATE SCHEMA b21_expr;
-- B21_CAPTURE_FUNCTION
CREATE TEMP TABLE b21_cases(name text PRIMARY KEY,left_fact jsonb,right_fact jsonb);
CREATE FUNCTION b21_expr.fact(k text,r regclass,n text) RETURNS jsonb LANGUAGE sql VOLATILE AS $fact$
 SELECT v FROM jsonb_array_elements(b21_expr.capture()->'expressions') q(v)
 JOIN pg_class c ON c.oid=r JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE v->>'kind'=k AND v->'identity'=jsonb_build_array(ns.nspname,c.relname,n)
$fact$;
CREATE TABLE b21_expr.parent(id integer PRIMARY KEY);
CREATE TABLE b21_expr.oid_target(id integer);
CREATE TABLE b21_expr.subject(id integer,clock timestamptz,
 CONSTRAINT positive CHECK (id>0),
 CONSTRAINT clock_bound CHECK (clock>=TIMESTAMPTZ '2026-01-01 00:00:00+00'),
 CONSTRAINT parent_ref FOREIGN KEY(id) REFERENCES b21_expr.parent(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED);
CREATE TABLE b21_expr.copy_subject(id integer,clock timestamptz);
CREATE POLICY probe ON b21_expr.subject USING (id>0 AND 'b21_expr.oid_target'::regclass IS NOT NULL);

-- The shared projection must transport OIDs as JSON numbers, without truncating
-- the unsigned 32-bit range or relaxing the JavaScript row validator.
DO $oid_json_type$
DECLARE captured jsonb;
BEGIN
 captured:=b21_expr.capture();
 IF jsonb_typeof(to_jsonb(4294967295::oid)) IS DISTINCT FROM 'string'
  OR to_jsonb(4294967295::oid::bigint) IS DISTINCT FROM to_jsonb(4294967295::bigint)
  OR jsonb_array_length(captured->'expressions')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(captured->'expressions') q(v)
   WHERE jsonb_typeof(v->'localOid') IS DISTINCT FROM 'number')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_OID_JSON_TYPE'; END IF;
END $oid_json_type$;

CREATE FUNCTION b21_expr.policy_dependencies() RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $function$
 SELECT coalesce(jsonb_agg(j ORDER BY j::text),'[]'::jsonb) FROM (
  SELECT jsonb_build_array(d.deptype, a.type,a.object_names,a.object_args) j
  FROM pg_policy p JOIN pg_depend d ON d.classid='pg_policy'::regclass AND d.objid=p.oid
  CROSS JOIN LATERAL pg_identify_object_as_address(d.refclassid,d.refobjid,d.refobjsubid) a
  WHERE p.polrelid='b21_expr.subject'::regclass AND p.polname='probe') q
$function$;

DO $roundtrips$
DECLARE before_def text; after_def text; before_deps jsonb; before_fact jsonb; old_oid oid; new_oid oid;
BEGIN
 SELECT pg_get_constraintdef(oid,false) INTO before_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='positive';
 EXECUTE format('ALTER TABLE b21_expr.copy_subject ADD CONSTRAINT positive %s',before_def);
 SELECT pg_get_constraintdef(oid,false) INTO after_def FROM pg_constraint
  WHERE conrelid='b21_expr.copy_subject'::regclass AND conname='positive';
 IF before_def IS DISTINCT FROM after_def THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_CHECK_ROUNDTRIP'; END IF;
 INSERT INTO b21_cases VALUES ('CHECK_ROUNDTRIP',b21_expr.fact('constraint','b21_expr.subject','positive'),b21_expr.fact('constraint','b21_expr.copy_subject','positive'));

 SELECT pg_get_constraintdef(oid,false) INTO before_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='clock_bound';
 before_fact:=b21_expr.fact('constraint','b21_expr.subject','clock_bound');
 PERFORM set_config('TimeZone','Europe/Paris',true);
 SELECT pg_get_constraintdef(oid,false) INTO after_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='clock_bound';
 IF before_def IS NOT DISTINCT FROM after_def THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_TIMEZONE_VARIATION'; END IF;
 INSERT INTO b21_cases VALUES ('TIMEZONE_VARIATION',before_fact,b21_expr.fact('constraint','b21_expr.subject','clock_bound'));
 PERFORM set_config('TimeZone','UTC',true);
 IF before_def IS DISTINCT FROM (SELECT pg_get_constraintdef(oid,false) FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='clock_bound') THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_FIXED_CONTEXT'; END IF;
 INSERT INTO b21_cases VALUES ('FIXED_CONTEXT',before_fact,b21_expr.fact('constraint','b21_expr.subject','clock_bound'));

 SELECT pg_get_expr(polqual,polrelid,false) INTO before_def FROM pg_policy
  WHERE polrelid='b21_expr.subject'::regclass AND polname='probe';
 before_deps:=b21_expr.policy_dependencies();
 before_fact:=b21_expr.fact('policy','b21_expr.subject','probe');
 old_oid:='b21_expr.oid_target'::regclass;
 DROP POLICY probe ON b21_expr.subject;
 DROP TABLE b21_expr.oid_target;
 CREATE TABLE b21_expr.oid_target(id integer);
 new_oid:='b21_expr.oid_target'::regclass;
 -- Native parsing rebinds a symbolic regclass to the new object. No OID rewriting.
 EXECUTE format('CREATE POLICY probe ON b21_expr.subject USING (%s)',before_def);
 SELECT pg_get_expr(polqual,polrelid,false) INTO after_def FROM pg_policy
  WHERE polrelid='b21_expr.subject'::regclass AND polname='probe';
 IF old_oid=new_oid OR before_def IS DISTINCT FROM after_def
  OR before_deps IS DISTINCT FROM b21_expr.policy_dependencies() THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_REGCLASS_NATIVE_REBIND'; END IF;
 INSERT INTO b21_cases VALUES ('REGCLASS_REBIND',before_fact,b21_expr.fact('policy','b21_expr.subject','probe'));
 -- A real changed predicate must still differ; dependencies alone do not prove it.
 ALTER POLICY probe ON b21_expr.subject USING (id>=0 AND 'b21_expr.oid_target'::regclass IS NOT NULL);
 SELECT pg_get_expr(polqual,polrelid,false) INTO after_def FROM pg_policy
  WHERE polrelid='b21_expr.subject'::regclass AND polname='probe';
 IF before_def IS NOT DISTINCT FROM after_def
  OR before_deps IS DISTINCT FROM b21_expr.policy_dependencies()
  OR (0>0) IS NOT FALSE OR (0>=0) IS NOT TRUE THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_POLICY_CHANGE_REJECTED'; END IF;
 INSERT INTO b21_cases VALUES ('PREDICATE_CHANGE',before_fact,b21_expr.fact('policy','b21_expr.subject','probe'));
END $roundtrips$;

ALTER TABLE b21_expr.subject ADD CONSTRAINT validation_state CHECK(id>=0) NOT VALID;
DO $validation$
DECLARE before_def text; after_def text; before_fact jsonb;
BEGIN
 SELECT pg_get_constraintdef(oid,false) INTO before_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='validation_state' AND NOT convalidated;
 IF before_def IS NULL OR position('NOT VALID' IN before_def)=0 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_NOT_VALID_CAPTURED'; END IF;
 before_fact:=b21_expr.fact('constraint','b21_expr.subject','validation_state');
 ALTER TABLE b21_expr.subject VALIDATE CONSTRAINT validation_state;
 SELECT pg_get_constraintdef(oid,false) INTO after_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='validation_state' AND convalidated;
 IF after_def IS NULL OR before_def=after_def OR position('NOT VALID' IN after_def)>0 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_VALIDATION_CHANGE_REJECTED'; END IF;
 INSERT INTO b21_cases VALUES ('VALIDATION_CHANGE',before_fact,b21_expr.fact('constraint','b21_expr.subject','validation_state'));
END $validation$;
DO $deferrability$
DECLARE before_def text; after_def text; before_fact jsonb;
BEGIN
 SELECT pg_get_constraintdef(oid,false) INTO before_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='parent_ref'
   AND contype='f' AND condeferrable AND condeferred AND confdeltype='c';
 before_fact:=b21_expr.fact('constraint','b21_expr.subject','parent_ref');
 ALTER TABLE b21_expr.subject ALTER CONSTRAINT parent_ref NOT DEFERRABLE;
 SELECT pg_get_constraintdef(oid,false) INTO after_def FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='parent_ref'
   AND contype='f' AND NOT condeferrable AND NOT condeferred;
 IF before_def IS NULL OR after_def IS NULL OR before_def=after_def THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_DEFERRABILITY_CHANGE_REJECTED'; END IF;
 INSERT INTO b21_cases VALUES ('DEFERRABILITY_CHANGE',before_fact,b21_expr.fact('constraint','b21_expr.subject','parent_ref'));
END $deferrability$;
ALTER TABLE b21_expr.copy_subject DROP CONSTRAINT positive;
ALTER TABLE b21_expr.copy_subject ADD CONSTRAINT positive CHECK(id>1);
DO $literal$
BEGIN
 IF (SELECT pg_get_constraintdef(oid,false) FROM pg_constraint
  WHERE conrelid='b21_expr.subject'::regclass AND conname='positive')
  =(SELECT pg_get_constraintdef(oid,false) FROM pg_constraint
  WHERE conrelid='b21_expr.copy_subject'::regclass AND conname='positive')
  OR (1>0) IS NOT TRUE OR (1>1) IS NOT FALSE THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_LITERAL_CHANGE_REJECTED'; END IF;
END $literal$;
INSERT INTO b21_cases VALUES ('LITERAL_CHANGE',b21_expr.fact('constraint','b21_expr.subject','positive'),b21_expr.fact('constraint','b21_expr.copy_subject','positive'));

-- V2 cases use the SAME object before/after native DDL. Their resolved binding
-- identities are therefore comparable without rewriting OIDs or dependencies.
CREATE TEMP TABLE b22_cases(name text PRIMARY KEY,left_fact jsonb,right_fact jsonb);
CREATE TABLE b21_expr.v2_subject(a boolean,b boolean,c boolean,x integer,y integer,z integer,label text);
CREATE COLLATION b21_expr.user_collation (provider=libc,locale='C');
CREATE DOMAIN b21_expr.user_domain AS integer;
ALTER TABLE b21_expr.v2_subject ADD COLUMN custom b21_expr.user_domain;
ALTER TABLE b21_expr.v2_subject ADD COLUMN custom_array b21_expr.user_domain[];
CREATE FUNCTION b21_expr.user_compare(integer,integer) RETURNS boolean LANGUAGE sql IMMUTABLE AS 'SELECT $1 > $2';
CREATE OPERATOR b21_expr.## (LEFTARG=integer,RIGHTARG=integer,FUNCTION=b21_expr.user_compare);
DO $b22_checks$
DECLARE r record; l jsonb; v jsonb; ddl text;
BEGIN
 FOR r IN SELECT * FROM (VALUES
  ('CHECK_PRETTY_ROUNDTRIP','a AND (b AND c)',NULL::text,true,false),
  ('BOOLEAN_PRECEDENCE','(a OR b) AND c','a OR (b AND c)',false,false),
  ('RIGHT_SUBTRACTION','(x-y)-z>0','x-(y-z)>0',false,false),
  ('CAST_CHANGE','(x::bigint/y)>0','(x::numeric/y)>0',false,false),
  ('LITERAL_SAME_BINDINGS','x>0','x>1',false,false),
  ('USER_COLLATION','label COLLATE b21_expr.user_collation <> '''' AND (a AND b)',NULL,true,true),
  ('USER_DOMAIN','custom>0 AND (a AND b)',NULL,true,true),
  ('USER_ARRAY','custom_array IS NOT NULL AND (a AND b)',NULL,true,true),
  ('USER_OPERATOR','x OPERATOR(b21_expr.##) y AND (a AND b)',NULL,true,true)
 ) t(name,original,changed,pretty_equal,uncovered) LOOP
  EXECUTE format('ALTER TABLE b21_expr.v2_subject ADD CONSTRAINT probe_check CHECK (%s)',r.original);
  l:=b21_expr.fact('constraint','b21_expr.v2_subject','probe_check');
  ddl:=CASE WHEN r.changed IS NULL THEN l->>'prettyDefinition' ELSE format('CHECK (%s)',r.changed) END;
  ALTER TABLE b21_expr.v2_subject DROP CONSTRAINT probe_check;
  EXECUTE format('ALTER TABLE b21_expr.v2_subject ADD CONSTRAINT probe_check %s',ddl);
  v:=b21_expr.fact('constraint','b21_expr.v2_subject','probe_check');
  IF (l->>'prettyDefinition'=v->>'prettyDefinition') IS DISTINCT FROM r.pretty_equal
   OR (r.pretty_equal AND (l->>'definition'=v->>'definition'
     OR l->>'secondaryPrettyDefinition' IS DISTINCT FROM v->>'secondaryPrettyDefinition'))
   OR (r.uncovered AND (l->'bindings'->>'complete'<>'false' OR v->'bindings'->>'complete'<>'false'))
   OR (NOT r.uncovered AND (l->'bindings'->>'complete'<>'true' OR v->'bindings'->>'complete'<>'true'))
  THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B22_CHECK_CASE'; END IF;
  INSERT INTO b22_cases VALUES(r.name,l,v);
  ALTER TABLE b21_expr.v2_subject DROP CONSTRAINT probe_check;
 END LOOP;
 -- Concrete counterexamples, including SQL's three-valued boolean semantics.
 IF ((true OR false) AND false) IS NOT FALSE OR (true OR (false AND false)) IS NOT TRUE
  OR ((3-2)-2>0) IS NOT FALSE OR (3-(2-2)>0) IS NOT TRUE
  OR (1::bigint/2>0) IS NOT FALSE OR (1::numeric/2>0) IS NOT TRUE
  OR (NULL::boolean IS NOT TRUE) IS NOT TRUE OR (NOT NULL::boolean) IS NOT NULL
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B22_COUNTEREXAMPLE'; END IF;
END $b22_checks$;
CREATE POLICY probe_policy ON b21_expr.v2_subject USING (a OR (b OR c)) WITH CHECK(a);
DO $b22_policies$
DECLARE l jsonb; v jsonb;
BEGIN
 l:=b21_expr.fact('policy','b21_expr.v2_subject','probe_policy');
 EXECUTE format('ALTER POLICY probe_policy ON b21_expr.v2_subject USING (%s)',l->>'prettyDefinition');
 v:=b21_expr.fact('policy','b21_expr.v2_subject','probe_policy');
 IF l->>'definition'=v->>'definition' OR l->>'prettyDefinition' IS DISTINCT FROM v->>'prettyDefinition'
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B22_POLICY_ROUNDTRIP'; END IF;
 INSERT INTO b22_cases VALUES('POLICY_PRETTY_ROUNDTRIP',l,v);
 l:=v;
 ALTER POLICY probe_policy ON b21_expr.v2_subject WITH CHECK(b);
 v:=b21_expr.fact('policy','b21_expr.v2_subject','probe_policy');
 IF l->>'prettyDefinition' IS DISTINCT FROM v->>'prettyDefinition' OR l->'dependencies' IS DISTINCT FROM v->'dependencies'
  OR l->>'secondaryDefinition'=v->>'secondaryDefinition'
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B22_WITH_CHECK'; END IF;
 INSERT INTO b22_cases VALUES('WITH_CHECK',l,v);
 ALTER POLICY probe_policy ON b21_expr.v2_subject USING (a IS NOT TRUE);
 l:=b21_expr.fact('policy','b21_expr.v2_subject','probe_policy');
 ALTER POLICY probe_policy ON b21_expr.v2_subject USING (NOT a);
 INSERT INTO b22_cases VALUES('NULL_PREDICATE',l,b21_expr.fact('policy','b21_expr.v2_subject','probe_policy'));
END $b22_policies$;
SELECT jsonb_build_object('schemaVersion',1,'status','SYNTHETIC_WITNESSES_PASSED',
 'checkNativeRoundtrip',true,'timezoneCanChangeDeparse',true,'fixedContextReproduces',true,
 'regclassNativeRebind',true,'sameDependenciesDoNotErasePredicateChange',true,
 'notValidPreserved',true,'deferrabilityPreserved',true,'literalChangeRejected',true,
 'cases',(SELECT jsonb_agg(jsonb_build_object('name',name,'left',left_fact,'right',right_fact) ORDER BY name) FROM b21_cases),
 'v2Cases',(SELECT jsonb_agg(jsonb_build_object('name',name,'left',left_fact,'right',right_fact) ORDER BY name) FROM b22_cases));
ROLLBACK;
