import {createHash} from 'node:crypto';

// Pure SQL constructor. Runtime bytes and identities stay in run-local memory.
export const ORIGINAL_SQL_SHA256='29098b4dc0caf44f2a4501517603ee8fa78b2b00ab84a0ca7a34031dadc63969';
export const CONTEXT_KEYS=Object.freeze(['search_path','TimeZone','DateStyle','IntervalStyle',
 'extra_float_digits','quote_all_identifiers','standard_conforming_strings','bytea_output',
 'lc_monetary','server_encoding','client_encoding']);

const query=`WITH expression_objects AS (
 SELECT 'policy'::text kind,jsonb_build_array(n.nspname,c.relname,p.polname) identity,
  'pg_catalog.pg_policy'::regclass classid,p.oid,
  jsonb_build_object('cmd',p.polcmd,'permissive',p.polpermissive,
   'rolesResolved',NOT EXISTS(SELECT 1 FROM unnest(p.polroles) z WHERE z<>0 AND NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=z)),
   'roles',ARRAY(SELECT jsonb_build_array(CASE WHEN x=0 THEN 'PUBLIC' ELSE 'ROLE' END,
     CASE WHEN x=0 THEN NULL ELSE pg_get_userbyid(x) END)
    FROM unnest(p.polroles) x ORDER BY (x<>0),pg_get_userbyid(x))) metadata,
  pg_get_expr(p.polqual,p.polrelid,false) definition,
  pg_get_expr(p.polqual,p.polrelid,true) pretty_definition,
  pg_get_expr(p.polwithcheck,p.polrelid,false) secondary_definition
 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private','auth','storage')
 UNION ALL
 SELECT 'constraint',jsonb_build_array(n.nspname,c.relname,k.conname),
  'pg_catalog.pg_constraint'::regclass,k.oid,
  jsonb_build_object('contype',k.contype,'convalidated',k.convalidated,
   'condeferrable',k.condeferrable,'condeferred',k.condeferred,'connoinherit',k.connoinherit,
   'conislocal',k.conislocal,'coninhcount',k.coninhcount,
   'confupdtype',k.confupdtype,'confdeltype',k.confdeltype,'confmatchtype',k.confmatchtype,
   'conkey',CASE WHEN k.conkey IS NULL THEN NULL ELSE ARRAY(
    SELECT a.attname FROM unnest(k.conkey) WITH ORDINALITY q(num,ord)
    LEFT JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=q.num ORDER BY q.ord) END,
   'confkey',CASE WHEN k.confkey IS NULL THEN NULL ELSE ARRAY(
    SELECT a.attname FROM unnest(k.confkey) WITH ORDINALITY q(num,ord)
    LEFT JOIN pg_attribute a ON a.attrelid=k.confrelid AND a.attnum=q.num ORDER BY q.ord) END,
   'confdelsetcols',CASE WHEN k.confdelsetcols IS NULL THEN NULL ELSE ARRAY(
    SELECT a.attname FROM unnest(k.confdelsetcols) WITH ORDINALITY q(num,ord)
    LEFT JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=q.num ORDER BY q.ord) END,
   'operators',(SELECT jsonb_object_agg(t.label,t.addresses) FROM (
    SELECT label,CASE WHEN ids IS NULL THEN NULL ELSE (
     SELECT coalesce(jsonb_agg(jsonb_build_array(a.type,a.object_names,a.object_args) ORDER BY q.ord),'[]'::jsonb)
     FROM unnest(ids) WITH ORDINALITY q(id,ord)
     CROSS JOIN LATERAL pg_identify_object_as_address('pg_catalog.pg_operator'::regclass,q.id,0) a) END addresses
    FROM (VALUES ('conpfeqop',k.conpfeqop),('conppeqop',k.conppeqop),
     ('conffeqop',k.conffeqop),('conexclop',k.conexclop)) arrays(label,ids)) t),
   'referencedRelation',CASE WHEN k.confrelid=0 THEN NULL ELSE
    (SELECT jsonb_build_array(a.type,a.object_names,a.object_args)
     FROM pg_identify_object_as_address('pg_catalog.pg_class'::regclass,k.confrelid,0) a) END,
   'parentConstraint',CASE WHEN k.conparentid=0 THEN NULL ELSE
    (SELECT jsonb_build_array(a.type,a.object_names,a.object_args)
     FROM pg_identify_object_as_address('pg_catalog.pg_constraint'::regclass,k.conparentid,0) a) END),
  pg_get_constraintdef(k.oid,false),pg_get_constraintdef(k.oid,true),pg_get_expr(k.conbin,k.conrelid,false)
 FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private','auth','storage')
), expressions AS (
 SELECT jsonb_build_object('kind',o.kind,'identity',o.identity,'localOid',o.oid,
  'metadata',o.metadata,'definition',o.definition,'prettyDefinition',o.pretty_definition,
  'secondaryDefinition',o.secondary_definition,
  'dependencies',(SELECT coalesce(jsonb_agg(z.v ORDER BY z.v::text),'[]'::jsonb) FROM (
   SELECT jsonb_build_array(d.deptype,a.type,a.object_names,a.object_args) v
   FROM pg_depend d CROSS JOIN LATERAL pg_identify_object_as_address(d.refclassid,d.refobjid,d.refobjsubid) a
   WHERE d.classid=o.classid AND d.objid=o.oid AND d.objsubid=0) z)) v
 FROM expression_objects o
), relations AS (
 SELECT jsonb_build_object('identity',jsonb_build_array(n.nspname,c.relname),
  'relkind',c.relkind,'owner',pg_get_userbyid(c.relowner),
  'identitiesResolved',EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=c.relowner)
   AND NOT EXISTS(SELECT 1 FROM aclexplode(c.relacl) z
    WHERE NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=z.grantor)
    OR (z.grantee<>0 AND NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=z.grantee))),
  'rawState',CASE WHEN c.relacl IS NULL THEN 'NULL' WHEN cardinality(c.relacl)=0 THEN 'EMPTY' ELSE 'PRESENT' END,
  'supported',c.relkind IN('r','p','v','m','f','S'),
  'expandedAcl',CASE WHEN c.relkind IN('r','p','v','m','f','S') THEN
   (SELECT coalesce(jsonb_agg(z.v ORDER BY z.v::text),'[]'::jsonb) FROM (
    SELECT jsonb_build_array(CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE 'ROLE' END,
     CASE WHEN x.grantee=0 THEN NULL ELSE pg_get_userbyid(x.grantee) END,
     pg_get_userbyid(x.grantor),x.privilege_type,x.is_grantable) v
    FROM aclexplode(coalesce(c.relacl,acldefault(
     CASE WHEN c.relkind='S' THEN 's'::"char" ELSE 'r'::"char" END,c.relowner))) x) z)
   ELSE NULL END,
  'initialPrivilegeKinds',ARRAY(SELECT i.privtype::text FROM pg_init_privs i
   WHERE i.classoid='pg_catalog.pg_class'::regclass AND i.objoid=c.oid AND i.objsubid=0 ORDER BY i.privtype),
  'extensionMember',EXISTS(SELECT 1 FROM pg_depend d
   WHERE d.classid='pg_catalog.pg_class'::regclass AND d.objid=c.oid AND d.objsubid=0 AND d.deptype='e')) v
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private','auth','storage')
), payload AS (
 SELECT jsonb_build_object('schemaVersion',1,'status','COMPLETE',
  'context',(SELECT jsonb_object_agg(k,current_setting(k)) FROM unnest(ARRAY[
   'search_path','TimeZone','DateStyle','IntervalStyle','extra_float_digits','quote_all_identifiers',
   'standard_conforming_strings','bytea_output','lc_monetary','server_encoding','client_encoding']) k),
  'resolvedSchemas',current_schemas(true),'currentUser',current_user,'sessionUser',session_user,
  'expressions',(SELECT coalesce(jsonb_agg(v ORDER BY v->>'kind',v->'identity'),'[]'::jsonb) FROM expressions),
  'relations',(SELECT coalesce(jsonb_agg(v ORDER BY v->'identity'),'[]'::jsonb) FROM relations)) v
)
SELECT CASE WHEN octet_length(v::text)>16777216 OR
 jsonb_array_length(v->'expressions')+jsonb_array_length(v->'relations')>100000
 THEN jsonb_build_object('schemaVersion',1,'status','BOUND_EXCEEDED') ELSE v END FROM payload;
`;

// The witnesses use the identical native projection, in their dedicated cluster.
// This is a fixed synthetic scope, never an environment or CLI override.
export function b21WitnessCaptureSql(schema) {
 if(!['b21_fixture','b21_expr'].includes(schema)) throw Error('B21_WITNESS_SCOPE');
 const scoped=query.replaceAll("n.nspname IN('public','private','auth','storage')",`n.nspname='${schema}'`);
 return `CREATE FUNCTION ${schema}.capture() RETURNS jsonb LANGUAGE sql VOLATILE AS $b21_capture$\n${scoped}$b21_capture$;\n`;
}

export function buildB21ProbeSql(original) {
 if(typeof original!=='string'||createHash('sha256').update(original).digest('hex')!==ORIGINAL_SQL_SHA256
  ||!original.startsWith('BEGIN READ ONLY;\n')||!original.endsWith('ROLLBACK;\n')) throw Error('B21_SQL_PIN');
 // The original facts CTE and hash SELECT stay byte-for-byte unchanged. Only
 // this additional probe transaction uses one repeatable snapshot for both views.
 const originalBody=original.slice('BEGIN READ ONLY;\n'.length,-'ROLLBACK;\n'.length);
 return 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n'+
  "DO $b21$ BEGIN IF current_setting('server_version_num')<>'170006' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='B21_VERSION'; END IF; END $b21$;\n"+
  originalBody+query+
  "SET LOCAL search_path=pg_catalog;\nSET LOCAL TimeZone='UTC';\nSET LOCAL DateStyle='ISO, YMD';\n"+
  "SET LOCAL IntervalStyle='postgres';\nSET LOCAL extra_float_digits=3;\nSET LOCAL quote_all_identifiers=off;\n"+
  "SET LOCAL standard_conforming_strings=on;\nSET LOCAL bytea_output=hex;\nSET LOCAL lc_monetary='C';\n"+
  query+'ROLLBACK;\n';
}

export function decodeB21Probe(bytes) {
 if(!Buffer.isBuffer(bytes)||bytes.length>40*1024*1024) throw Error('B21_PRIVATE_BOUND');
 if(!bytes.equals(Buffer.from(bytes.toString('utf8'))))throw Error('B21_PRIVATE_SHAPE');
 const lines=bytes.toString('utf8').trim().split('\n');
 if(lines.length!==3) throw Error('B21_PRIVATE_SHAPE');
 try {
  const [anchor,current,fixed]=lines.map(line=>JSON.parse(line));
  if(!anchor||typeof anchor.catalogue_sha256!=='string'||!/^[a-f0-9]{64}$/.test(anchor.catalogue_sha256)
   ||![current,fixed].every(v=>v&&v.schemaVersion===1&&['COMPLETE','BOUND_EXCEEDED'].includes(v.status))) throw Error();
  // Private return value: NEVER attach to a snapshot, throw it or write it to disk.
  // catalogue-semantics-diagnostic validates every field before using this value.
  return {anchor,current,fixed};
 } catch { throw Error('B21_PRIVATE_SHAPE'); }
}
