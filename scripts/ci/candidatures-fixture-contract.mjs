import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { STAGING_REF, STAGING_URL } from './prepare-load-fixtures.mjs';
export { STAGING_REF, STAGING_URL };
export const literal = v => `'${String(v).replaceAll("'", "''")}'`;
const uuid = s => { const h=createHash('sha256').update(`jolene-D2:${STAGING_REF}:${s}`).digest('hex'); return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`; };
export function manifesteD(runId, jour) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(runId||'') || !/^\d{4}-\d{2}-\d{2}$/.test(jour||'') || new Date(`${jour}T09:00:00Z`).toISOString().slice(0,10)!==jour) throw new Error('Run et jour D explicites requis.');
  const membres=Array.from({length:3},(_,slot)=>({slot,userId:uuid(`${runId}:user:${slot}`),role:slot===2?'ADMIN_ETABLISSEMENT':'SOIGNANT',prenom:slot===0?'Alice':slot===1?'Basile':'Clinique',nom:'Recette D',email:`recette-d-${uuid(`${runId}:user:${slot}`)}@example.invalid`}));
  return {version:1,projectRef:STAGING_REF,runId,jour,marker:`RECETTE D ${runId}`,membres,
    missionId:uuid(`${runId}:mission`),creneauId:uuid(`${runId}:creneau`),preuveId:uuid(`${runId}:preuve`),nettoyageId:uuid(`${runId}:nettoyage`),
    debut:`${jour}T09:00:00.000Z`,fin:`${jour}T13:00:00.000Z`,siret:'99'+(BigInt('0x'+createHash('sha256').update(runId).digest('hex').slice(0,12))%1000000000000n).toString().padStart(12,'0')};
}
export const statutsD=['planned','auth-created','prepared','cleanup-started','cleaned'];
export function validerManifesteD(m,runId,jour) {
  const attendu=manifesteD(runId,jour);
  if (!m || Object.keys(m).sort().join()!==[...Object.keys(attendu),'status','authStatus'].sort().join()
    || Object.keys(attendu).some(k=>JSON.stringify(m[k])!==JSON.stringify(attendu[k])) || !statutsD.includes(m.status)
    || !Array.isArray(m.authStatus) || m.authStatus.length!==3 || m.authStatus.some(s=>!['not-started',...statutsD].includes(s))) throw new Error('Manifeste D incohérent : aucun accès distant.');
  return m;
}
export function configurationD(env) {
  if(env.STAGING_SUPABASE_PROJECT_REF!==STAGING_REF || env.STAGING_SUPABASE_URL!==STAGING_URL) throw new Error('D réservé au staging Jolene exact.');
  const m=manifesteD(env.LOAD_TEST_RUN_ID,env.LOAD_D_JOUR);
  if (env.LOAD_TEST_VUS || env.LOAD_TEST_DURATION || env.LOAD_FIXTURE_COUNT) throw new Error('D2 fixe : aucun volume ou durée configurable.');
  return {m,path:resolve(env.LOAD_D_MANIFEST||'tests/load/results/fixture-D2.json')};
}
export function utilisateurDValide(u,m,i) { const a=m.membres[i]; return u?.id===a.userId && u.email===a.email && u.app_metadata?.role===a.role
  && u.app_metadata.est_compte_test===true && u.app_metadata.is_test_playwright===true && u.app_metadata.load_fixture_kind==='CANDIDATURES_D2' && u.app_metadata.load_fixture_run===m.runId && (i!==2 || u.app_metadata.etablissement_id===a.userId); }
export const tablesD=['auth.users','public.soignants','public.etablissements','public.missions','public.mission_creneaux','public.candidatures','public.notifications','public.preferences_notifications','public.rate_limits','public.journaux_audit'];
// Snapshot staging lu le 30/09/2026 ; aucune actualisation automatique. Le
// hash large bloque aussi une modification d'un helper indirect non inventorié.
export const catalogueD={schema:'c08ea254b6046c8e722425d54ca440f6',fonctions:'61e759a93b1cd36ad15c84c8799ef425',triggers:'c07c6a042974d351870d2e16a4b777fa'};
export const sqlSchemaD=`SELECT md5(jsonb_build_object(
 'colonnes',(SELECT jsonb_agg(jsonb_build_array(a.attrelid::regclass::text,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attrelid::regclass::text,a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attnum>0 AND NOT a.attisdropped AND a.attrelid IN (${tablesD.map(t=>`${literal(t)}::regclass`).join(',')})),
 'contraintes',(SELECT jsonb_agg(jsonb_build_array(c.conrelid::regclass::text,c.conname,pg_get_constraintdef(c.oid)) ORDER BY c.conrelid::regclass::text,c.conname) FROM pg_constraint c WHERE c.conrelid IN (${tablesD.map(t=>`${literal(t)}::regclass`).join(',')}) OR c.confrelid IN (${tablesD.map(t=>`${literal(t)}::regclass`).join(',')}))
)::text) AS schema`;
export const sqlCatalogueD=`SELECT
(${sqlSchemaD}) AS schema,
(SELECT md5(string_agg(n.nspname||'.'||p.oid::regprocedure::text||':'||pg_get_functiondef(p.oid)||':'||coalesce(p.proacl::text,''),'|' ORDER BY n.nspname,p.oid::regprocedure::text)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')) AS fonctions,
(SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text||':'||pg_get_functiondef(t.tgfoid),'|' ORDER BY t.tgrelid::regclass::text,t.tgname)) FROM pg_trigger t WHERE NOT t.tgisinternal AND t.tgrelid IN (${tablesD.map(t=>`${literal(t)}::regclass`).join(',')})) AS triggers,
(SELECT count(*)::integer FROM cron.job WHERE active) AS crons_actifs,
(SELECT count(*)::integer FROM pg_constraint WHERE contype='f' AND conrelid='public.journaux_audit'::regclass AND confrelid IN (${tablesD.filter(t=>t!=='public.journaux_audit').map(t=>`${literal(t)}::regclass`).join(',')})) AS audit_fk`;
export function validerCatalogueD(c) { if(c?.fonctions!==catalogueD.fonctions || c.triggers!==catalogueD.triggers || c.schema!==catalogueD.schema || c.crons_actifs!==0 || c.audit_fk!==0) throw new Error('Catalogue D différent ou cron/audit FK actif : revue requise avant fixture.'); }
export function validerEtatD(s,phase,m) {
  if(!s || !['prepared','apres','cleaned'].includes(phase) || s.inattendus!==0 || !Array.isArray(s.candidatures)) throw new Error('État D incomplet ou effet non prévu.');
  if(phase==='cleaned') { if([s.auth,s.profils,s.etablissements,s.missions,s.creneaux,s.preferences,s.notifications,s.limites,s.sessions,s.identites,s.candidatures.length].some(n=>n!==0)||s.recu_cleanup!==1) throw new Error('Zéros D non confirmés.'); }
  else if(s.auth!==3 || s.profils!==2 || s.etablissements!==1 || s.missions!==1 || s.creneaux!==1 || s.preferences!==3 || s.candidatures.length!==(phase==='apres'?2:0)||s.notifications!==(phase==='apres'?4:0)) throw new Error('Lot métier D incomplet.');
  if(m && phase==='apres' && (new Set(s.candidatures.map(c=>c.id)).size!==2 || m.membres.slice(0,2).some(a=>s.candidatures.filter(c=>c.soignant_id===a.userId && /^[a-f0-9-]{36}$/.test(c.id)).length!==1))) throw new Error('Identités des candidatures D non confirmées.');
  const champs=['auth','profils','etablissements','missions','creneaux','preferences','notifications','limites','sessions','identites','audits_conserves','recu_cleanup','inattendus'];
  return {...Object.fromEntries(champs.map(k=>[k,s[k]])),candidatures:s.candidatures.map(c=>({id:c.id,soignant_id:c.soignant_id}))};
}
