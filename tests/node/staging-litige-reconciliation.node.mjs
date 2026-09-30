import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { reconciliationSql, sources } from '../../scripts/ci/reconcile-staging-litige-base.mjs';
const read = path => readFileSync(new URL(`../../${path}`,import.meta.url),'utf8');
const sourceTexts = sources.map(([name])=>read(`supabase/migrations/${name}`));
const registry = sources.map(([name])=>({version:name.slice(0,14)}));
const input = {projectRef:'mejpriaetwgtcstbgfid',sourceTexts,registry};
const sql = reconciliationSql(input);
const md5 = value => createHash('md5').update(value).digest('hex');

test('reconstruit exactement le corps main depuis les deux sources figées',()=>{
 const definition=sql.split('$canonical_definition$')[1];
 const body=definition.split('AS $body$')[1].split('$body$')[0];
 assert.equal(md5(body),'1d1a6d0593e1899ff2c58c48a38f3a4d');
 const marker=sourceTexts[1].split('$marker$')[1], injection=sourceTexts[1].split('$injection$')[1];
 assert.equal(md5(body.replace(marker,injection).replace(marker,injection)),'8cc14fc83a8e1adc73ebcda417074d84');
 assert.equal((body.match(/RETURN public.fn_admin_resoudre_litige_salarie\(/g)||[]).length,1);
});
test('refuse toute cible autre que staging, tout registre ou source inexpliqués',()=>{
 for(const projectRef of ['flripxtsyegjshnhzjkz','',undefined,'other']) assert.throws(()=>reconciliationSql({...input,projectRef}),/réservée au staging/);
 for(const bad of [[sourceTexts[0]+' ',sourceTexts[1]],[sourceTexts[0],null],[],[null]]) assert.throws(()=>reconciliationSql({...input,sourceTexts:bad}),/source|Source/);
 for(const bad of [null,{},[{}],[{version:123}]]) assert.throws(()=>reconciliationSql({...input,registry:bad}),/Registre/);
});
test('un staging vierge est confié à db push, aucune réparation implicite des migrations',()=>{
 assert.doesNotMatch(reconciliationSql({...input,registry:[]}),/\b(?:DO|EXECUTE|CREATE|UPDATE|DELETE|INSERT)\b/);
 assert.doesNotMatch(reconciliationSql({...input,sourceTexts:[null,null]}),/\b(?:DO|EXECUTE|CREATE|UPDATE|DELETE|INSERT)\b/);
 assert.throws(()=>reconciliationSql({...input,registry:[{version:'20260930091209'}]}),/Historique litige incomplet/);
});
test('DDL seulement pour le corps staging exact ; aucun retour en arrière après garde main',()=>{
 assert.match(sql,/IF md5\(p.prosrc\) = '1d1a6d0593e1899ff2c58c48a38f3a4d' THEN RETURN/);
 assert.match(sql,/IF false OR md5\(p.prosrc\) IS DISTINCT FROM '8cc14fc83a8e1adc73ebcda417074d84' THEN/);
 assert.ok(sql.indexOf('RAISE EXCEPTION \'Corps staging') < sql.indexOf('EXECUTE $canonical_definition$'));
 const guarded=reconciliationSql({...input,registry:[...registry,{version:'20260930091209'}]});
 assert.match(guarded,/IF md5\(p.prosrc\) = '5a13493bf67426d968d0d75aad16b86c' THEN RETURN/);
 assert.match(guarded,/IF true OR md5\(p.prosrc\) IS DISTINCT FROM/);
 assert.match(sql,/has_function_privilege\('anon'/);
 assert.match(sql,/a.grantee=0 AND a.privilege_type='EXECUTE'/);
 assert.match(sql,/IS DISTINCT FROM ROW\(p.proacl,p.proowner,p.proconfig,p.prosecdef\)/);
 const shell=sql.split('$canonical_definition$')[0]+sql.split('$canonical_definition$')[2];
 assert.doesNotMatch(shell,/\b(?:GRANT|REVOKE|DELETE|TRUNCATE|INSERT|UPDATE)\s/i);
});
test('workflow borne la correction à la base avant les migrations PR ; préflight prod inchangé',()=>{
 const workflow=read('.github/workflows/validate-pr.yml');
 const repair=workflow.indexOf('node scripts/ci/reconcile-staging-litige-base.mjs');
 assert.ok(repair>workflow.indexOf('node scripts/ci/check-staging-migration-base.mjs'));
 assert.ok(repair<workflow.indexOf('supabase db push'));
 assert.ok(repair<workflow.indexOf('Exécuter les migrations ajoutées'));
 const production=read('supabase/migrations/20260930091209_garder_resolveur_litige_avant_lecture.sql');
 assert.ok(!production.includes('8cc14fc83a8e1adc73ebcda417074d84'));
 assert.match(production,/'1d1a6d0593e1899ff2c58c48a38f3a4d', '5a13493bf67426d968d0d75aad16b86c'/);
});
