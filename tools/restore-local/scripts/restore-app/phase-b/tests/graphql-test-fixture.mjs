// Synthetic memory fixtures only; no accounts, production state or archive.
import {createHash} from 'node:crypto';
import {normalizedGraphqlTocHash} from '../graphql-restore-plan.mjs';
import {GRAPHQL_COMPONENTS} from '../contract.mjs';
const hash=v=>createHash('sha256').update(v).digest('hex');
export const witness=()=>({schemaVersion:2,context:true,nativeExtensionExact:true,wrapperSignatureExact:true,
 wrapperBodyExact:true,wrapperMembershipExact:true,wrapperOwnerExact:true,hookSignatureExact:true,
 hookBodyExact:true,hookOwnerExact:true,hookNotExtensionMember:true,triggerExact:true,schemaOwnersExact:true,
 defaultFunctionAclExact:true,noGlobalFunctionDefaultAcl:true,initialPrivilegesCount:1,fingerprint:'a'.repeat(64),components:Object.fromEntries(GRAPHQL_COMPONENTS.map(key=>[key,'a'.repeat(64)]))});
export const descriptions=()=>[
 'SCHEMA - extensions postgres','SCHEMA - graphql_public supabase_admin',
 'EXTENSION - pg_graphql ',
 'FUNCTION extensions grant_pg_graphql_access() supabase_admin',
 ...Array.from({length:105},(_,i)=>`TABLE public synthetic_${i} postgres`),
 'TABLE DATA auth users supabase_auth_admin','TABLE DATA auth identities supabase_auth_admin',
 'TABLE DATA storage objects supabase_storage_admin','TABLE DATA public factures_honoraires postgres',
 'TABLE DATA public factures_honoraires_documents postgres',
 'ACL graphql_public FUNCTION graphql("operationName" text, query text, variables jsonb, extensions jsonb) supabase_admin',
 'ACL public TABLE synthetic_0 postgres',
 'DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS supabase_admin',
 'EVENT TRIGGER - issue_pg_graphql_access supabase_admin',
 'EVENT TRIGGER - unrelated_native_hook supabase_admin',
];
export const tocOf=rows=>Buffer.from('; Synthetic fixture, no real dump or identifiers\n'+rows.map((d,i)=>`${i+1}; 0 ${i+1000} ${d}`).join('\n')+'\n');
export function input(rows=descriptions()) {const archive=Buffer.from('PGDMP_SYNTHETIC_ARCHIVE'),toc=tocOf(rows);return{archive,archiveSha256:hash(archive),toc,witness:witness(),review:{nativeGraphqlRepairReviewed:true,nativeRestoreTocSha256:normalizedGraphqlTocHash(toc)}};}
