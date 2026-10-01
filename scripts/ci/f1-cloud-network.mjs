import { isDeepStrictEqual as equal } from 'node:util';
import { performance } from 'node:perf_hooks';
import { ORIGIN, documentBytes, refuse, sha256 } from './f1-cloud-core.mjs';
import { documentContractF1 } from './f1-cloud-document-contract.mjs';

export const UI_ORIGIN = 'http://127.0.0.1:8904';
const READ_RPC = new Set(['fn_get_my_role','fn_compte_auth_actif','fn_messages_non_lus','fn_dashboard_soignant_complet',
  'fn_mon_profil_soignant_complet','fn_mon_etablissement_complet','fn_stats_dashboard_etablissement','fn_mes_soignants_etablissement']);
const EXACT_RPC = new Set(['fn_etablissement_public','fn_etablissements_safe','fn_soignant_pour_etablissement','fn_mes_permissions_etab',
  'fn_note_moyenne','fn_mode_exercice','fn_est_bloque','fn_mon_score_etab','fn_bfa_info','fn_litige_pour_mission',
  'fn_user_id_pour_etablissement','fn_interlocuteurs_conversations','fn_suivi_escrow_mission','fn_alerte_cddu_repetitif','fn_score_etab_public','fn_etat_pointage_mission']);
const WRITE_RPC = new Set(['fn_audit_connexion','fn_maj_activite_soignant','fn_ecrire_audit_safe',
  'fn_obtenir_conversation','fn_marquer_messages_lus','fn_update_presence']);
const TABLES = new Set(['soignants','etablissements','missions','mission_creneaux','candidatures','notifications','contrats_mission','contrats_travail_missions',
  'documents_soignants','stripe_connect_onboarding','litiges','parcours_inscription','notations_missions','evaluations',
  'presences','paiements_soignant','paliers_commission','documents_requis_par_profession','presence_status','typing_status','conversations','messages_chat']);
const empty = x => equal(x ?? {}, {});
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;

/** Finite per-browser-context contract. No invite, message, payment, acceptance,
 * rating, pointage or generation endpoint is in this contract. Conversations are
 * learned solely from the exact successful mission RPC, never an arbitrary URL. */
export function uiContractF1(actor, manifest, documents) {
  const s = manifest.members[0].id, e = manifest.members[1].id, m = manifest.missionId;
  if (![s,e].includes(actor.id) || !UUID.test(m)) refuse('F1_UI_MANIFEST');
  const soignant = actor.id === s, other = soignant ? e : s;
  let conversation = null;
  const document = documentContractF1({ missionId: m, soignantId: s, documents });
  const counts = {}, limits = { auth: 1, fn_audit_connexion: 1, fn_maj_activite_soignant: soignant ? 1 : 0,
    fn_ecrire_audit_safe: soignant ? 0 : 1, fn_obtenir_conversation: 2, fn_marquer_messages_lus: 2,
    fn_update_presence: 10, options: 80, read: 180 };
  const consume = key => { if ((counts[key] ?? 0) >= limits[key]) return false; counts[key] = (counts[key] ?? 0) + 1; return key; };
  function authorize({ url, method, body = null }) {
    let u; try { u = new URL(url); } catch { return false; }
    if (u.origin !== ORIGIN || u.username || u.password || u.hash) return false;
    const rpc = u.pathname.startsWith('/rest/v1/rpc/') ? u.pathname.slice(13) : null;
    const table = u.pathname.startsWith('/rest/v1/') ? u.pathname.slice(9) : null;
    if (method === 'OPTIONS') return body === null && (['/auth/v1/token','/auth/v1/user'].includes(u.pathname)
      || READ_RPC.has(rpc) || EXACT_RPC.has(rpc) || WRITE_RPC.has(rpc) || TABLES.has(table)
      || u.pathname === '/rest/v1/factures_honoraires' || documents.some(d => u.pathname === `/storage/v1/object/sign/jolene-documents/${d.pdf.key}`)) ? consume('options') : false;
    if (document.authorize({ url, method, body })) return 'document';
    if (u.pathname === '/auth/v1/token') return method === 'POST' && u.search === '?grant_type=password'
      && body?.email === actor.email && body.password === actor.password
      && Object.keys(body).every(k => ['email','password','gotrue_meta_security'].includes(k))
      && (body.gotrue_meta_security === undefined || empty(body.gotrue_meta_security)) ? consume('auth') : false;
    if (u.pathname === '/auth/v1/user') return method === 'GET' && !u.search && body === null ? consume('read') : false;
    if (rpc) {
      if (method !== 'POST' || u.search) return false;
      if (rpc === 'fn_audit_connexion') return equal(body,{p_action:'CONNEXION'}) && consume(rpc);
      if (rpc === 'fn_maj_activite_soignant') return soignant && empty(body) && consume(rpc);
      if (rpc === 'fn_ecrire_audit_safe') return !soignant && typeof body?.p_navigateur === 'string' && body.p_navigateur.length < 512
        && equal(body,{p_acteur_id:e,p_type_acteur:'ADMIN_ETABLISSEMENT',p_action:'DONNEES_PERSO_CONSULTATION',p_type_ressource:'etablissement',
          p_id_ressource:e,p_cle_s3:null,p_details:{page:'dashboard_etablissement'},p_ip:null,p_navigateur:body.p_navigateur}) && consume(rpc);
      if (rpc === 'fn_obtenir_conversation') return equal(body,{p_autre_id:other,p_mission_id:m}) && consume(rpc);
      if (rpc === 'fn_marquer_messages_lus') return !!conversation && equal(body,{p_conversation_id:conversation}) && consume(rpc);
      if (rpc === 'fn_update_presence') return empty(body) && consume(rpc);
      if (READ_RPC.has(rpc)) return empty(body) && consume('read');
      const args = {
        fn_etablissement_public:{p_etablissement_id:e}, fn_etablissements_safe:{p_ids:[e]},
        fn_soignant_pour_etablissement:!soignant?{p_soignant_id:s}:null,
        fn_note_moyenne:{p_user_id:e}, fn_mode_exercice:{p_profession:'IDE',p_type_etab:'CLINIQUE_PRIVEE',p_finess_secteur:null},
        fn_est_bloque:{p_cible_id:other}, fn_mon_score_etab:!soignant?{}:null, fn_bfa_info:!soignant?{}:null,
        fn_score_etab_public:soignant?{p_etab_id:e}:null,fn_etat_pointage_mission:!soignant?{p_mission_id:m}:null,
        fn_suivi_escrow_mission:{p_mission_id:m},fn_alerte_cddu_repetitif:!soignant?{p_soignant_id:s,p_etablissement_id:e}:null,
        fn_litige_pour_mission:{p_mission_id:m}, fn_user_id_pour_etablissement:soignant?{p_etablissement_id:e}:null,
        fn_interlocuteurs_conversations:conversation?{p_conversation_ids:[conversation]}:null,
      };
      if (rpc === 'fn_mes_permissions_etab') return !soignant && [null,e].some(id=>equal(body,{p_etablissement_id:id})) && consume('read');
      return args[rpc] !== undefined && args[rpc] !== null && equal(body ?? {},args[rpc]) && consume('read');
    }
    if(u.pathname==='/rest/v1/factures_honoraires'&&method==='GET'&&body===null&&equal(Object.fromEntries(u.searchParams),{select:'statut,type_document',mission_id:`eq.${m}`})&&[...u.searchParams].length===2)return consume('read');
    if (!['GET','HEAD'].includes(method) || body !== null || !TABLES.has(table)) return false;
    const entries=[...u.searchParams], keys=entries.map(([k])=>k);
    if (new Set(keys).size !== keys.length || keys.some(k=>!['select','id','mission_id','soignant_id','soignant_assigne_id',
      'etablissement_id','destinataire_id','user_id','conversation_id','statut','order','limit','offset','profession','supprime_le',
      'started_at','lu','lue','type_creneau','est_actif','est_pause','debut_le','fin_le','accord_soignant','accord_etablissement','payload_modifications'].includes(k))) return false;
    const select=u.searchParams.get('select');
    // Named joins are limited to the two foreign keys of the owned mission.
    if (!select || !/^[a-zA-Z0-9_,.*()\s]+$/.test(select) || [...select.matchAll(/([a-z_]+)\s*\(/g)].some(x=>!['presences','etablissements'].includes(x[1])&&!(table==='litiges'&&x[1]==='missions'&&select==='id,mission_id,statut,payload_modifications,accord_soignant,accord_etablissement,missions(intitule)'))) return false;
    if (u.searchParams.has('limit') && !/^[1-9][0-9]{0,2}$/.test(u.searchParams.get('limit'))) return false;
    if (u.searchParams.has('offset') && u.searchParams.get('offset') !== '0') return false;
    for(const key of ['debut_le','fin_le'])if(u.searchParams.has(key)&&(table!=='missions'||!/^(?:gte|lte)\.\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(u.searchParams.get(key))))return false;
    for(const [key,value,allowedTable] of [['lue','eq.false','notifications'],['est_pause','eq.false','mission_creneaux'],['accord_soignant','eq.false','litiges'],['accord_etablissement','eq.true','litiges'],['payload_modifications','not.is.null','litiges']])if(u.searchParams.has(key)&&(table!==allowedTable||u.searchParams.get(key)!==value))return false;
    const eq=(key,id)=>id && u.searchParams.get(key)===`eq.${id}`;
    const lot=(key,id)=>eq(key,id)||u.searchParams.get(key)===`in.(${id})`;
    let owned=false;
    if (table==='missions') owned=lot('id',m)||eq('etablissement_id',e)||(soignant&&eq('soignant_assigne_id',s));
    else if (['mission_creneaux','candidatures','contrats_mission','contrats_travail_missions','presences','paiements_soignant'].includes(table)) owned=lot('mission_id',m);
    else if (table==='notifications') owned=eq('destinataire_id',actor.id);
    else if (table==='etablissements') owned=eq('id',e);
    else if (table==='soignants') owned=lot('id',s);
    else if (table==='parcours_inscription') owned=eq('user_id',actor.id);
    else if (table==='presence_status') owned=eq('user_id',other)&&select==='status,last_seen_at';
    else if (table==='typing_status') owned=eq('user_id',other)&&eq('conversation_id',conversation)&&select==='started_at'
      && /^gt\.\d{4}-\d\d-\d\dT/.test(u.searchParams.get('started_at')??'');
    else if (table==='conversations') owned=eq('id',conversation)&&select==='archived_at,soignant_id';
    else if (table==='messages_chat') owned=eq('conversation_id',conversation)&&select==='id,conversation_id,auteur_id,contenu,est_admin,lu,cree_le'
      && u.searchParams.get('order')==='cree_le.desc'&&u.searchParams.get('limit')==='500';
    else if (['documents_requis_par_profession','paliers_commission'].includes(table)) owned=keys.every(k=>['select','profession','order','est_actif'].includes(k))&&(!u.searchParams.has('est_actif')||u.searchParams.get('est_actif')==='eq.true');
    else owned=eq('soignant_id',s)||lot('mission_id',m);
    return owned && consume('read');
  }
  return {
    authorize,
    response({ url, method, data }) {
      const u=new URL(url),rpc=u.pathname.split('/').pop();
      if(rpc==='fn_obtenir_conversation'&&method==='POST') {
        if(!UUID.test(data??'')||(conversation&&data!==conversation))refuse('F1_CONVERSATION_RESPONSE');conversation=data;
      }
      if(rpc==='fn_user_id_pour_etablissement'&&data!==e)refuse('F1_INTERLOCUTOR_RESPONSE');
      if(u.pathname.startsWith('/storage/v1/object/sign/jolene-documents/')&&method==='POST') {
        if(!data||!equal(Object.keys(data),['signedURL'])||typeof data.signedURL!=='string'
          || !data.signedURL.startsWith('/object/sign/jolene-documents/'))refuse('F1_SIGN_RESPONSE');
        document.registerSignedPdf(decodeURIComponent(u.pathname.slice('/storage/v1/object/sign/jolene-documents/'.length)),`${ORIGIN}/storage/v1${data.signedURL}`);
      }
    },
    documentFor(url) {
      const u=new URL(url);return documents.find(d=>decodeURIComponent(u.pathname)===`/storage/v1/object/sign/jolene-documents/${d.pdf.key}`);
    },
    projection(){return {...counts,documents:document.projection()};},
    complete(){return counts.auth===1&&counts.fn_audit_connexion===1&&(soignant?counts.fn_maj_activite_soignant===1:counts.fn_ecrire_audit_safe===1)
      &&counts.fn_obtenir_conversation===2&&counts.fn_marquer_messages_lus===2&&counts.fn_update_presence>=2&&document.complete();},
  };
}

/** Closed diagnostic: known path templates only, never query/body/header/ID. */
export function networkFailureF1({url,method,error,status,start,now=performance.now()}) {
  let u;try{u=new URL(url);}catch{}
  const codes=new Set(['F1_CONTEXT_BOUND','F1_UI_ASSET_REFUSED','F1_NETWORK_REFUSED','F1_SESSION_BINDING','F1_NETWORK_HTTP',
    'F1_CONVERSATION_RESPONSE','F1_INTERLOCUTOR_RESPONSE','F1_SIGN_RESPONSE','F1_AUTH_OWNERSHIP','F1_AUTH_TOKEN']);
  let path='other';
  const known=[...READ_RPC,...EXACT_RPC,...WRITE_RPC].map(x=>'/rest/v1/rpc/'+x).concat([...TABLES].map(x=>'/rest/v1/'+x),
    ['/rest/v1/factures_honoraires','/auth/v1/token','/auth/v1/user','/functions/v1/send-email','/functions/v1/generate-invoice']);
  if(u?.origin===ORIGIN&&!u.username&&!u.password) {
    if(known.includes(u.pathname))path=u.pathname;
    else if(u.pathname.startsWith('/storage/v1/object/sign/jolene-documents/'))path='/storage/v1/object/sign/jolene-documents/:owned-path';
  } else if(u?.origin===UI_ORIGIN&&!u.username&&!u.password)path=u.pathname.startsWith('/assets/')?'/assets/:asset':'ui_route';
  return {category:codes.has(error?.message)?error.message:'F1_TRANSPORT_OR_RESPONSE',path,
    origin:u?.origin===ORIGIN?'staging':u?.origin===UI_ORIGIN?'preview':'other',
    method:['GET','HEAD','POST','OPTIONS'].includes(method)?method:'other',
    status:Number.isInteger(status)&&status>=100&&status<=599?status:null,
    relative_ms:Math.min(180000,Math.max(0,Math.round(now-start))),exception_sha256:sha256(String(error?.message??''))};
}

/** route.fetch forwards actual responses unchanged. Failed/unknown requests are
 * aborted and recorded; no HTTP/Auth/REST/Storage/Edge fixture is manufactured. */
export async function installNetworkF1(context, actor, manifest, documents, { recordAuth, assetPaths, diagnostic = async () => {} }) {
  const contract=uiContractF1(actor,manifest,documents),pending=new Set(),start=performance.now();
  let closed=false,errors=0,token=null;const failures=[];
  await context.addInitScript(()=>Object.defineProperty(window,'Stripe',{value:()=>{throw Error('F1_PAYMENT_REFUSED');}}));
  await context.route('**/*',route=>{
    const work=(async()=>{
      const request=route.request(); let body=null,u,status=null;
      try {
        u=new URL(request.url());body=request.postData()?request.postDataJSON():null;
        if(closed||performance.now()-start>180000)refuse('F1_CONTEXT_BOUND');
        if(u.protocol==='blob:'&&u.origin===UI_ORIGIN&&request.method()==='GET'&&body===null&&!u.search&&!u.hash){await route.continue();return;}
        if(u.origin===UI_ORIGIN) {
          const routes=['/connexion','/soignant/tableau-de-bord','/etablissement/tableau-de-bord',`/soignant/missions/${manifest.missionId}`,`/etablissement/missions/${manifest.missionId}`];
          if(request.method()!=='GET'||u.search||u.hash||u.username||u.password||(!assetPaths.has(u.pathname)&&!routes.includes(u.pathname)))refuse('F1_UI_ASSET_REFUSED');
          await route.continue();return;
        }
        const category=contract.authorize({url:u.href,method:request.method(),body});
        if(!category)refuse('F1_NETWORK_REFUSED');
        const signedDownload=category==='document'&&request.method()==='GET'&&!!contract.documentFor(u.href);
        if(!['auth','options'].includes(category)&&!signedDownload&&request.headers().authorization!==`Bearer ${token}`)refuse('F1_SESSION_BINDING');
        const response=await route.fetch({maxRedirects:0,maxRetries:0,timeout:25000});
        status=response.status();if(!response.ok())refuse('F1_NETWORK_HTTP');
        if(request.method()!=='HEAD'&&request.method()!=='OPTIONS'&&response.status()!==204) {
          const document=contract.documentFor(u.href);
          if(document&&request.method()==='GET') documentBytes(await response.body(),{...document.pdf,format:'pdf'});
          else {
            const data=await response.json();
            if(category==='auth'){await recordAuth(actor,data);token=data.access_token;}
            contract.response({url:u.href,method:request.method(),data});
          }
        }
        await route.fulfill({response});
      } catch(error) {errors++;
        const failure=networkFailureF1({url:request.url(),method:request.method(),error,status,start});
        if(failures.length<64)failures.push(failure);
        try{await diagnostic({role:actor.role,total:errors,failures:[...failures]});}catch{errors++;}
        await route.abort().catch(()=>{});
      }
    })();pending.add(work);work.finally(()=>pending.delete(work));return work;
  });
  return {close(){closed=true;},async drain(){while(pending.size)await Promise.allSettled([...pending]);},
    async assert(){if(errors)refuse('F1_NETWORK_FAILED');},
    complete(){if(errors||!contract.complete())refuse('F1_NETWORK_INCOMPLETE');return contract.projection();}};
}
