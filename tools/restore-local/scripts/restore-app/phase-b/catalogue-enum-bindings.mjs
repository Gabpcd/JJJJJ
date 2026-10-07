// Private native evidence for scalar enums only. Never exported in receipts.
// Shape follows PostgreSQL REL_17_6 DefineEnum; labels retain enumsortorder order.
const identifier=v=>typeof v==='string'&&/^[a-z_][a-z0-9_]*$/.test(v)&&v.length<=63;
const text=v=>typeof v==='string'&&!v.includes('\0')&&Buffer.byteLength(v)<=65536;
export function enumColumnValid(c){
 const e=c?.[3];
 return Array.isArray(c)&&c.length===4&&typeof c[0]==='string'&&c[2]===null
  &&e!==null&&typeof e==='object'&&!Array.isArray(e)
  &&Object.keys(e).sort().join(',')==='acl,column,identity,labels,owner,schemaVersion,shape'
  &&e.schemaVersion===1&&e.shape==='PG17_SCALAR_ENUM'
  &&Array.isArray(e.identity)&&e.identity.length===2&&e.identity.every(identifier)
  &&Array.isArray(e.column)&&e.column.length===3&&e.column.every(v=>text(v)&&v.length>0)
  &&c[0]===e.column.join('.')&&c[1]===e.identity.join('.')
  &&text(e.owner)&&e.owner.length>0
  &&(e.acl===null||Array.isArray(e.acl)&&e.acl.length<=100000&&e.acl.every(text))
  &&Array.isArray(e.labels)&&e.labels.length>0&&e.labels.length<=100000
  &&e.labels.every(v=>text(v)&&Buffer.byteLength(v)<=63)&&new Set(e.labels).size===e.labels.length;
}
export function columnFactTypeMatches(column,factType){
 if(column.length===3)return column[1]===factType;
 // The original native fact may omit a visible schema. The new proof always
 // uses a qualified identity, linked to this exact column in the same capture.
 return enumColumnValid(column)&&(factType===column[1]||factType===column[3].identity[1]);
}
const enums=`), proven_scalar_enums AS (
 SELECT t.oid,n.nspname,t.typname,pg_get_userbyid(t.typowner) owner,t.typacl acl,
  (SELECT jsonb_agg(e.enumlabel ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid=t.oid) labels
 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
 WHERE n.nspname IN('public','private','auth','storage')
  AND n.nspname ~ '^[a-z_][a-z0-9_]*$' AND t.typname ~ '^[a-z_][a-z0-9_]*$'
  AND quote_ident(n.nspname)=n.nspname AND quote_ident(t.typname)=t.typname
  AND t.typtype='e' AND t.typcategory='E' AND t.typisdefined AND t.typlen=4 AND t.typbyval
  AND t.typalign='i' AND t.typstorage='p' AND NOT t.typispreferred AND t.typdelim=','
  AND t.typrelid=0 AND t.typbasetype=0 AND t.typelem=0 AND t.typtypmod=-1 AND t.typndims=0
  AND NOT t.typnotnull AND t.typcollation=0 AND t.typdefault IS NULL AND t.typdefaultbin IS NULL
  AND t.typinput='pg_catalog.enum_in'::regproc AND t.typoutput='pg_catalog.enum_out'::regproc
  AND t.typreceive='pg_catalog.enum_recv'::regproc AND t.typsend='pg_catalog.enum_send'::regproc
  AND t.typmodin=0 AND t.typmodout=0 AND t.typanalyze=0 AND t.typsubscript=0
  AND EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=t.typowner)
  AND NOT EXISTS(SELECT 1 FROM aclexplode(t.typacl) a WHERE
   NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=a.grantor)
   OR (a.grantee<>0 AND NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=a.grantee)))
  AND EXISTS(SELECT 1 FROM pg_enum e WHERE e.enumtypid=t.oid)
  AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_type'::regclass AND d.objid=t.oid
   AND NOT(d.objsubid=0 AND d.deptype='n' AND d.refclassid='pg_namespace'::regclass AND d.refobjid=t.typnamespace AND d.refobjsubid=0))
  AND NOT EXISTS(SELECT 1 FROM pg_cast c WHERE c.castsource=t.oid OR c.casttarget=t.oid)
  AND NOT EXISTS(SELECT 1 FROM pg_operator o WHERE o.oprleft=t.oid OR o.oprright=t.oid)
  AND NOT EXISTS(SELECT 1 FROM pg_opclass o WHERE o.opcintype=t.oid OR o.opckeytype=t.oid)
  AND NOT EXISTS(SELECT 1 FROM pg_amop o WHERE o.amoplefttype=t.oid OR o.amoprighttype=t.oid)
  AND NOT EXISTS(SELECT 1 FROM pg_amproc o WHERE o.amproclefttype=t.oid OR o.amprocrighttype=t.oid)
), covered_columns AS (`;
export function extendScalarEnumBindings(query){
 const binding=`jsonb_build_array(n.nspname||'.'||c.relname||'.'||a.attname,format_type(a.atttypid,a.atttypmod),`;
 const covered=`a.atttypid IN(SELECT oid FROM builtin_types)
   AND (a.attcollation=0 OR a.attcollation IN(SELECT oid FROM builtin_collations)) types_covered`;
 const replacement=`CASE WHEN et.oid IS NOT NULL AND a.atttypmod=-1 AND a.attcollation=0 THEN
   jsonb_build_array(n.nspname||'.'||c.relname||'.'||a.attname,et.nspname||'.'||et.typname,NULL,
    jsonb_build_object('schemaVersion',1,'shape','PG17_SCALAR_ENUM',
     'column',jsonb_build_array(n.nspname,c.relname,a.attname),'identity',jsonb_build_array(et.nspname,et.typname),
     'owner',et.owner,'acl',et.acl,'labels',et.labels))
  ELSE ${binding}`;
 const needle=`FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace\n WHERE`;
 for(const token of [binding,covered,needle,`), covered_columns AS (`])if(query.split(token).length!==2)throw Error('B27_ENUM_RENDER_SCOPE');
 return query.replace(`), covered_columns AS (`,()=>enums).replace(binding,replacement)
  .replace(`END) binding_type,`,`END) END binding_type,`)
  .replace(covered,`((a.atttypid IN(SELECT oid FROM builtin_types)
   AND (a.attcollation=0 OR a.attcollation IN(SELECT oid FROM builtin_collations)))
   OR (et.oid IS NOT NULL AND a.atttypmod=-1 AND a.attcollation=0)) types_covered`)
  .replace(needle,needle.replace('\n WHERE',`\n LEFT JOIN proven_scalar_enums et ON et.oid=a.atttypid\n WHERE`));
}
