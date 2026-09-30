/** D2 : exactement deux candidatures salariées, sans acceptation ni finance.
 * Aucun workflow ne prépare ce lot automatiquement. Lire docs/tests-charge.md.
 */
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';
import k6Execution from 'k6/execution';
import { SUPABASE_URL,anonHeaders,authedHeaders } from '../helpers/auth.js';
import { donneesRapportCharge,resumeCharge } from '../helpers/resume.js';
import { lireCandidaturesD,utilisateurD,corpsPostulerD,candidatureDValide } from '../helpers/candidatures-pool.js';
const confirmations=new Counter('candidatures_confirmees');
if(__ENV.LOAD_TEST_VUS||__ENV.LOAD_TEST_DURATION)throw new Error('D2 est borné à deux VUs, une itération : aucun override.');
export const options={scenarios:{candidatures_simultanees:{executor:'per-vu-iterations',vus:2,iterations:1,maxDuration:'60s'}},
  thresholds:{checks:['rate==1'],iterations:['count==2'],'candidatures_confirmees{slot:0}':['count==1'],'candidatures_confirmees{slot:1}':['count==1']}};
function lire(path,jwt){const r=http.get(`${SUPABASE_URL}/rest/v1/${path}`,{headers:authedHeaders(jwt),tags:{name:'D2_verification'},timeout:'15s'});if(r.status!==200)throw new Error('Lecture D2 refusée.');try{return r.json();}catch{throw new Error('Lecture D2 invalide.');}}
export function setup(){
  const m=lireCandidaturesD(__ENV.LOAD_CANDIDATURES_JSON,__ENV.LOAD_TEST_RUN_ID);
  const sessions=m.identites.map(a=>{const r=http.post(`${SUPABASE_URL}/auth/v1/token?grant_type=password`,JSON.stringify({email:a.email,password:a.password}),{headers:anonHeaders(),tags:{name:'D2_auth'},timeout:'15s'});
    let s;try{s=r.json();}catch{throw new Error('Auth D2 invalide.');}
    if(r.status!==200||typeof s?.access_token!=='string'||!s.access_token||!utilisateurD(s.user,a,m.runId))throw new Error('Identité D2 non confirmée.');return {jwt:s.access_token,userId:a.userId,slot:a.slot};});
  for(const [i,a] of m.identites.slice(0,2).entries()){
    const rows=lire(`soignants?id=eq.${a.userId}&select=id,profession,type_exercice,est_compte_test,identite_verifiee,tous_documents_valides`,sessions[i].jwt);
    if(rows.length!==1||rows[0].id!==a.userId||rows[0].profession!=='AS'||rows[0].type_exercice!=='SALARIE'||rows[0].est_compte_test!==true||rows[0].identite_verifiee!==false||rows[0].tous_documents_valides!==false)throw new Error('Profil D2 inéligible au pilote.');
    const missions=lire(`missions?id=eq.${m.missionId}&select=id,etablissement_id,statut,est_urgente,soignant_assigne_id,type_contrat_recherche,mode_attribution`,sessions[i].jwt);
    if(missions.length!==1||missions[0].id!==m.missionId||missions[0].etablissement_id!==m.identites[2].userId||missions[0].statut!=='OUVERTE'||missions[0].est_urgente!==false||missions[0].soignant_assigne_id!==null||missions[0].type_contrat_recherche!=='SALARIE'||missions[0].mode_attribution!=='CANDIDATURE')throw new Error('Mission D2 non conforme.');
    const cs=lire(`mission_creneaux?mission_id=eq.${m.missionId}&select=id,debut,fin,type_creneau,est_pause`,sessions[i].jwt);
    if(cs.length!==1||cs[0].id!==m.creneauId||Date.parse(cs[0].debut)!==Date.parse(m.debut)||Date.parse(cs[0].fin)!==Date.parse(m.fin)||cs[0].type_creneau!=='PREVISIONNEL'||cs[0].est_pause!==false)throw new Error('Planning D2 non conforme.');
    if(lire(`candidatures?mission_id=eq.${m.missionId}&select=id`,sessions[i].jwt).length!==0)throw new Error('Mission D2 déjà utilisée.');
  }
  // Le setup ne retransmet aucun mot de passe aux VUs/rapport.
  const {identites,...publicM}=m;return {m:{...publicM,identites:identites.map(({password:_password,...a})=>a)},sessions};
}
export default function(data){
  const slot=__VU-1;if(![0,1].includes(slot)||__ITER!==0||data?.sessions?.length!==3||data.sessions[slot].slot!==slot||!data.sessions[slot].jwt)throw new Error('Exécution D2 hors borne ou setup absent.');
  const {m,sessions}=data,a=m.identites[slot];
  const r=http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_confirmer_action_planning_v1`,JSON.stringify(corpsPostulerD(m)),{headers:authedHeaders(sessions[slot].jwt),tags:{name:'rpc_postuler_D2',slot:String(slot)},timeout:'15s'});
  let out;try{out=r.json();}catch{out=null;}
  const ok=check(r,{'D2 candidature créée':()=>r.status===200&&out?.success===true&&!out.error&&out.choix_contrat==='SALARIE'&&out.profession_requise==='AS'&&out.docs_a_completer===true&&typeof out.candidature_id==='string'});
  if(!ok)return;
  const rows=lire(`candidatures?mission_id=eq.${m.missionId}&soignant_id=eq.${a.userId}&select=id,mission_id,soignant_id,statut,type_contrat_choisi,message`,sessions[slot].jwt);
  if(check(rows,{'D2 ligne métier exacte':()=>rows.length===1&&candidatureDValide(rows[0],m,a,out.candidature_id)}))confirmations.add(1,{slot:String(slot)});
}
export function teardown({m,sessions}){
  const rows=lire(`candidatures?mission_id=eq.${m.missionId}&select=id,mission_id,soignant_id,statut,type_contrat_choisi,message`,sessions[2].jwt);
  if(!check(rows,{'D2 établissement voit exactement deux candidatures':()=>rows.length===2&&new Set(rows.map(c=>c.id)).size===2&&m.identites.slice(0,2).every(a=>rows.filter(c=>c.soignant_id===a.userId&&candidatureDValide(c,m,a,c.id)).length===1)}))throw new Error('Résultat D2 métier incomplet.');
}
export function handleSummary(data){return {'stdout':resumeCharge(data,'D2 — Deux candidatures salariées','rpc_postuler_D2',k6Execution.test.options)+'\nDeux profils seulement ; vérifier le rapport SQL et le cleanup du même run.\n',
 'tests/load/results/04-candidatures-simultanees.json':JSON.stringify({...donneesRapportCharge(data),profils_attendus:2,preuve_metier:false,verification_sql_et_cleanup_requis:true},null,2)};}
