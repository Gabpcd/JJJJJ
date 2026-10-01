import {test,expect} from '@playwright/test';
import {creerSuiviSimule} from './helpers/recette-complete-suivi-mission';
import {ids} from './helpers/recette-complete-mission';
import {genererDocuments} from '../tests/helpers/facturation-documents-harness.mjs';
import {loginForm,openDocumentScreenF1,verifyDocumentCard,captureDocumentPortionsF1} from '../scripts/ci/f1-cloud-ui.mjs';
import {preparerHtmlPreview} from '../scripts/ci/f1-cloud-runtime.mjs';
import {uiContractF1} from '../scripts/ci/f1-cloud-network.mjs';
import {ORIGIN,sha256} from '../scripts/ci/f1-cloud-core.mjs';
// Explicitly offline: real compiled React UI + actual handler document bytes,
// Auth/REST/Storage responses simulated. Never a cloud/RLS/provider proof.
for(const role of ['SOIGNANT','ETABLISSEMENT'] as const)test(`F1 dashboard → document ${role}`,async({page,context},info)=>{
  const simulation=creerSuiviSimule(),{state}=simulation,banc=await genererDocuments({remplacement:true,unicode:true});
  const manifest={sql:{runId:'f1-ci-123456-1'},missionId:ids.mission};
  const marker=`RECETTE F1 SYNTHETIQUE ${manifest.sql.runId}`;
  Object.assign(state.soignant,banc.soignant,{id:ids.soignant,profession:'IDE',type_exercice:'LIBERAL',rpps_verifie:false,tous_documents_valides:false});
  Object.assign(state.etablissement,banc.etablissement,{id:ids.etablissement,type:'CLINIQUE_PRIVEE',est_compte_test:true,statut_verification:'EN_ATTENTE',peut_publier_missions:false});
  Object.assign(state.mission,banc.mission,{id:ids.mission,intitule:marker,statut:'EN_COURS',soignant_assigne_id:ids.soignant,etablissement_id:ids.etablissement,
    profession_requise:'IDE',type_contrat_recherche:'LIBERAL',type_contrat_applique:'LIBERAL',debut_le:'2026-09-21T09:00:00Z',fin_le:'2026-10-05T13:00:00Z',
    duree_heures:8,duree_heures_effective:4,nb_creneaux:2,taux_horaire_base:18,net_a_payer:144,montant_commission_ht:21.6,etablissements:state.etablissement});
  state.creneaux.splice(0,state.creneaux.length,...[
    ['2026-09-21','PREVISIONNEL'],['2026-10-05','PREVISIONNEL'],['2026-09-21','EFFECTIF']].map(([day,type],i)=>({id:`71000000-0000-4000-8000-00000000001${i}`,
      mission_id:ids.mission,debut:`${day}T09:00:00Z`,fin:`${day}T13:00:00Z`,type_creneau:type,est_pause:false})));
  for(const [key,doc] of [...banc.documents]){banc.documents.set(key.replace(banc.soignant.id,ids.soignant),doc);}
  for(const f of banc.factures){f.pdf_s3_key=f.pdf_s3_key.replace(banc.soignant.id,ids.soignant);f.facturx_xml_url=f.facturx_xml_url.replace(banc.soignant.id,ids.soignant);}
  const rows=banc.factures.map(f=>({...f,mission_id:ids.mission,soignant_id:ids.soignant,etablissement_id:ids.etablissement}));state.facture=rows[1];
  // Reuse the fixture responses, but suppress its preauthenticated session so
  // this scenario exercises the real form. No application source is changed.
  const noSession=new Proxy(context,{get(target,key){if(key==='addInitScript')return async()=>{};const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;}});
  await simulation.installer(noSession,role==='SOIGNANT'?'SOIGNANT':'ADMIN_ETABLISSEMENT');
  await context.addInitScript(()=>{Object.defineProperty(window,'Stripe',{value:()=>{throw Error('PAYMENT_FORBIDDEN');}});});
  await page.clock.setFixedTime(new Date('2026-10-01T12:00:00Z'));
  let guard;const refus:unknown[]=[];
  const errors:string[]=[],unknown:string[]=[],api:string[]=[],pending=new Set(),documents:number[]=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('request',r=>{if(r.isNavigationRequest()&&r.resourceType()==='document')documents.push(1);if(/\/(auth|rest|storage)\/v1\//.test(r.url()))pending.add(r);});
  page.on('requestfinished',r=>pending.delete(r));page.on('requestfailed',r=>pending.delete(r));
  await page.route('**/*',async route=>{
    const req=route.request(),u=new URL(req.url()),name=u.pathname.split('/').pop()!;
    if(u.protocol==='blob:'&&['127.0.0.1','localhost'].includes(new URL(u.pathname).hostname))return route.continue();
    if(!['127.0.0.1','localhost'].includes(u.hostname)){unknown.push('external');return route.abort();}
    if(req.isNavigationRequest()&&req.resourceType()==='document'){const response=await route.fetch();return route.fulfill({response,body:preparerHtmlPreview(await response.text())});}
    if(!/\/(auth|rest|storage|functions)\/v1\//.test(u.pathname))return route.fallback();
    api.push(`${req.method()} ${u.pathname}`);
    if(u.pathname.startsWith('/functions/')){unknown.push(u.pathname);return route.abort();}
    if(guard&&!guard.authorize({url:ORIGIN+u.pathname+u.search,method:req.method(),body:req.postData()?req.postDataJSON():null}))refus.push({path:u.pathname,query:[...u.searchParams],body:u.pathname.includes('/auth/')?'redacted':req.postData()?req.postDataJSON():null});
    const json=(data:unknown)=>{if(guard&&['fn_obtenir_conversation','fn_user_id_pour_etablissement'].includes(name)||guard&&u.pathname.startsWith('/storage/v1/object/sign/'))guard.response({url:ORIGIN+u.pathname+u.search,method:req.method(),data});return route.fulfill({json:data,headers:{'access-control-allow-origin':'*','access-control-expose-headers':'content-range','content-range':'0-0/1'}});};
    if(name==='fn_obtenir_conversation')return json('71000000-0000-4000-8000-000000000007');if(name==='fn_user_id_pour_etablissement')return json(ids.etablissement);
    if(name==='fn_audit_connexion'||name==='fn_maj_activite_soignant')return json(null);
    if(name==='fn_dashboard_soignant_complet')return json({profil:state.soignant,missions_ouvertes:[],mes_missions:[state.mission],documents:[],heures_semaine:0,
      gains_mois:{net_total:0,brut_total:0,nb_missions:0},gains_6mois:[],missions_semaine_cal:[],propositions:[],heures_totales_terminees:0,missions_oubliees_count:0,notifs_non_lues:0});
    if(name==='fn_stats_dashboard_etablissement')return json({missions_ouvertes:0,missions_assignees:0,missions_en_cours:1,missions_terminees:0,candidatures_en_attente:0,
      candidatures_recentes:[],missions_assignees_detail:[],pool_urgence_count:0,messages_non_lus:0,missions_a_payer:1,missions_terminees_ce_mois:0,soignants_ce_mois:0,commissions_impayees:0,nb_factures_impayees:0,litiges_ouverts:0});
    if(name==='fn_mon_score_etab')return json(null);if(name==='fn_bfa_info')return json(null);
    if(['missions','mission_creneaux'].includes(name)){
      const rows=(name==='missions'?[state.mission]:state.creneaux).filter(row=>[...u.searchParams].every(([k,v])=>{if(['select','order','limit','offset'].includes(k))return true;if(v.startsWith('eq.'))return String(row[k])===v.slice(3);if(v.startsWith('in.('))return v.slice(4,-1).split(',').includes(String(row[k]));return true;}));
      return route.fulfill({json:req.headers().accept?.includes('object')?(rows[0]??null):rows,headers:{'access-control-allow-origin':'*','access-control-expose-headers':'content-range','content-range':rows.length?`0-${rows.length-1}/${rows.length}`:'*/0'}});
    }
    if(name==='paliers_commission'||name==='stripe_connect_onboarding'||name==='documents_requis_par_profession')return json([]);
    if(name==='factures_honoraires')return json(u.searchParams.has('id')?rows.find(f=>`eq.${f.id}`===u.searchParams.get('id')):rows);
    if(u.pathname.startsWith('/storage/v1/object/sign/jolene-documents/')){
      const key=decodeURIComponent(u.pathname.slice('/storage/v1/object/sign/jolene-documents/'.length)),doc=banc.documents.get(key);
      expect(doc).toBeTruthy();if(req.method()==='POST')return json({signedURL:`/object/sign/jolene-documents/${key}?token=simulation-local`});
      expect(req.method()).toBe('GET');return route.fulfill({body:doc.bytes,contentType:'application/pdf',headers:{'access-control-allow-origin':'*'}});
    }
    return route.fallback();
  });
  const actor={role,email:role==='SOIGNANT'?state.soignant.email:state.etablissement.email_contact,password:'Local-synthetic-only!'};
  guard=uiContractF1({...actor,id:role==='SOIGNANT'?ids.soignant:ids.etablissement},{...manifest,members:[{id:ids.soignant},{id:ids.etablissement}]},rows.map((f,i)=>({id:f.id,slot:i?'replacement':'original',number:f.numero_facture,pdf:{key:f.pdf_s3_key}})));
  const drain=async()=>{await expect.poll(()=>pending.size).toBe(0);expect({errors,unknown:state.unknown,external:unknown}).toEqual({errors:[],unknown:[],external:[]});};
  await loginForm(page,actor,expect);await openDocumentScreenF1(page,actor,manifest,expect);expect(documents).toHaveLength(1);
  const docs=rows.map((f,i)=>({id:f.id,kind:'FACTURE',slot:i?'replacement':'original',number:f.numero_facture,pdf:{size:banc.documents.get(f.pdf_s3_key).bytes.length,sha256:sha256(banc.documents.get(f.pdf_s3_key).bytes)}}));
  const observations=await verifyDocumentCard({page,expect,documents:docs,drain,capture:async phase=>{
    await captureDocumentPortionsF1(page,role,expect,(locator,part)=>locator.screenshot({path:info.outputPath(`${role}-${phase}-${part}.png`),scale:'css',animations:'disabled'}));
  }});
  expect(documents).toHaveLength(2);expect(observations).toHaveLength(4);await drain();
  expect(refus).toEqual([]);expect(guard.complete()).toBe(true);
  expect(state.sms).toEqual([]);expect(state.emails).toEqual([]);expect(api.filter(x=>/fn_(?:envoyer|signer|confirmer|admin_|terminer)|checkout|generate-invoice/.test(x))).toEqual([]);
  await info.attach('closed-observations',{body:JSON.stringify({role,observations,api}),contentType:'application/json'});
});
