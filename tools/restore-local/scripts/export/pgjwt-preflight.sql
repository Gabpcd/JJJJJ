-- Catalogues uniquement. Aucun corps de routine, valeur métier, secret ou configuration de rôle renvoyé.
WITH e AS (
 SELECT e.oid,e.extname,e.extversion,n.nspname
 FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
 WHERE e.extname='pgjwt'
), members AS (
 SELECT d.classid,d.objid,d.objsubid FROM pg_catalog.pg_depend d JOIN e ON e.oid=d.refobjid
 WHERE d.refclassid='pg_catalog.pg_extension'::regclass AND d.deptype='e'
), objects AS (
 SELECT 'member'::text AS kind,m.classid,m.objid,m.objsubid,NULL::text AS dependency_type FROM members m
 UNION ALL
 SELECT 'direct_dependent',d.classid,d.objid,d.objsubid,d.deptype::text
 FROM pg_catalog.pg_depend d JOIN members m ON d.refclassid=m.classid AND d.refobjid=m.objid
 WHERE NOT EXISTS (SELECT 1 FROM members own WHERE own.classid=d.classid AND own.objid=d.objid)
), identified AS (
 SELECT DISTINCT kind,(pg_catalog.pg_identify_object(classid,objid,objsubid)).identity AS identity,dependency_type,
 CASE WHEN classid='pg_catalog.pg_proc'::regclass AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=objid AND p.prokind IN ('f','p'))
 THEN md5(pg_catalog.pg_get_functiondef(objid)) END AS function_md5 FROM objects
), member_names AS (
 SELECT DISTINCT p.proname FROM pg_catalog.pg_proc p JOIN members m ON m.classid='pg_catalog.pg_proc'::regclass AND m.objid=p.oid
), candidate_routines AS (
 SELECT p.oid::regprocedure::text AS identity,l.lanname AS language,md5(pg_catalog.pg_get_functiondef(p.oid)) AS definition_md5,
 ARRAY(SELECT m.proname FROM member_names m WHERE strpos(lower(p.prosrc),lower(m.proname))>0 ORDER BY m.proname) AS lexical_member_names,
 p.prosrc ~* '\mEXECUTE\M' AS dynamic_execute
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
), candidates AS (
 SELECT * FROM candidate_routines WHERE cardinality(lexical_member_names)>0 OR dynamic_execute
)
SELECT jsonb_build_object(
 'observed_at',clock_timestamp(),
 'postgres_version',current_setting('server_version'),
 'extension',(SELECT jsonb_build_object('name',extname,'version',extversion,'schema',nspname) FROM e),
 'member_count',(SELECT count(*) FROM members),
 'object_rows_total',(SELECT count(*) FROM identified),
 'object_rows_truncated',(SELECT count(*)>200 FROM identified),
 'objects',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.kind,x.identity,x.dependency_type) FROM (SELECT * FROM identified ORDER BY kind,identity,dependency_type LIMIT 200) x),'[]'::jsonb),
 'application_routines_scanned',(SELECT count(*) FROM candidate_routines),
 'candidate_rows_total',(SELECT count(*) FROM candidates),
 'candidate_rows_truncated',(SELECT count(*)>200 FROM candidates),
 'candidates',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.identity) FROM (SELECT * FROM candidates ORDER BY identity LIMIT 200) x),'[]'::jsonb),
 'conclusion','METADATA_ONLY_NOT_PROOF_OF_NO_DYNAMIC_DEPENDENCY'
) AS pgjwt_preflight;
