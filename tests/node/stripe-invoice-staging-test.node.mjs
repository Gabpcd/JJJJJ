import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname,resolve} from 'node:path';
import {runInNewContext} from 'node:vm';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const require = createRequire(import.meta.url);
const ts = require('typescript');
const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const source=readFileSync(`${ROOT}/supabase/functions/_shared/stripe-invoice-staging-test.ts`,'utf8');
const balanceJs=ts.transpileModule(readFileSync(`${ROOT}/supabase/functions/_shared/commission-balance.ts`,'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const balanceUrl=`data:text/javascript;base64,${Buffer.from(balanceJs).toString('base64')}`;
const compiled=ts.transpileModule(source.replace('./commission-balance.ts',balanceUrl),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
assert.deepEqual(compiled.diagnostics,[]);
const h=await import(`data:text/javascript;base64,${Buffer.from(compiled.outputText).toString('base64')}`);
const E='fcaa6c97-46c1-4da9-8f74-1395aed616c5',S='abba3c93-5408-47bf-96e3-0864c7de3cb7';
const M='f1660000-0000-4000-8000-000000000001',F='f1660000-0000-4000-8000-000000000002';
const C='cus_VMjraPs5wJ1GBO',A='acct_1UM0NlI8RIUZoi0j',P='acct_1T9pt0EVhQ7cb53W';
const OWNER='connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915';
const now=Date.now();
const config={serverSha:'a'.repeat(40),uiSha:'b'.repeat(40),manifestSha256:'c'.repeat(64),missionId:M,factureId:F,amountCents:1742,
 createdAt:new Date(now).toISOString(),expiresAt:new Date(now+3600_000).toISOString(),returnOrigin:'http://127.0.0.1:8085'};
const env={SUPABASE_URL:'https://mejpriaetwgtcstbgfid.supabase.co',STRIPE_SECRET_KEY:'sk_test_SyntheticOnly',INVOICE_STAGING_TEST_RUN:JSON.stringify(config)};
const parse=(e=env)=>h.stagingInvoiceConfig(k=>e[k],now);
function fixture(){
 const calls=[];
 const users=Object.fromEntries([[E,'ADMIN_ETABLISSEMENT'],[S,'SOIGNANT']].map(([id,role])=>[id,{id,email_confirmed_at:'2026-10-16T00:00:00Z',app_metadata:{role,est_compte_test:true,jolene_connect_fixture_owner:OWNER,...(id===E?{etablissement_id:E}:{})}}]));
 const rows={etablissements:[{id:E,est_compte_test:true,supprime_le:null,stripe_customer_id:C}],soignants:[{id:S,est_compte_test:true,supprime_le:null,stripe_account_id:A}],
  factures:[{id:F,etablissement_id:E,mission_id:M,facture_honoraire_id:null,type_document:'FACTURE',statut:'EMISE',nombre_missions:1,montant_ttc:17.42,montant_avoirs_imputes:0,montant_a_payer:17.42,rapprochement_paiement_requis:false,mode_paiement:null}],
  missions:[{id:M,etablissement_id:E,soignant_assigne_id:S,type_contrat_applique:'SALARIE',statut:'TERMINEE',facture_id:null}],stripe_transfers:[],
  stripe_payment_flow_claims:[`FACTURE:${F}`,`MISSION:${M}`].map(resource_key=>({resource_key,flow:'CHECKOUT_INVOICE',owner_token:`invoice:${F}`,stripe_checkout_session_id:'cs_test_Synthetic',stripe_payment_intent_id:null}))};
 const sb={auth:{admin:{async getUserById(id){calls.push(`auth:${id}`);return {data:{user:structuredClone(users[id])},error:null};}}},from(table){
  assert.ok(rows[table],`unknown table ${table}`);calls.push(`read:${table}`);const filters=[];let limit=Infinity;
  const result=()=>({data:structuredClone(rows[table].filter(r=>filters.every(f=>f(r))).slice(0,limit)),error:null});
  const q={select(){return q;},eq(k,v){filters.push(r=>r[k]===v);return q;},neq(k,v){filters.push(r=>r[k]!==v);return q;},in(k,v){filters.push(r=>v.includes(r[k]));return q;},limit(n){limit=n;return q;},async single(){const r=result();assert.equal(r.data.length,1);return {...r,data:r.data[0]};},then(yes,no){return Promise.resolve(result()).then(yes,no);}};return q;
 }};
 const session={id:'cs_test_Synthetic',mode:'payment',livemode:false,currency:'eur',customer:C,client_reference_id:F,amount_total:1742,
  metadata:{facture_id:F,etablissement_id:E},expires_at:Math.floor(Date.parse(config.expiresAt)/1000),created:Math.floor(now/1000),payment_intent:'pi_Synthetic'};
 const identity={platform:P,live:false,customer:{id:C,livemode:false,metadata:{etablissement_id:E}}};
 const stripe={accounts:{async retrieve(){calls.push('stripe:account');return {id:identity.platform};}},balance:{async retrieve(){calls.push('stripe:balance');return {livemode:identity.live};}},customers:{async retrieve(id){calls.push('stripe:customer');assert.equal(id,C);return identity.customer;}},checkout:{sessions:{async retrieve(id){calls.push('stripe:session');assert.equal(id,session.id);return session;}}}};
 const event={type:'checkout.session.completed',livemode:false,data:{object:structuredClone(session)}};
 return {calls,users,rows,sb,identity,stripe,session,event};
}
function groupedFixture(s=fixture()) {
 Object.assign(s.rows.factures[0],{mission_id:null,montant_ht:14.52,montant_tva:2.90});
 Object.assign(s.rows.missions[0],{facture_id:F,commission_facturee:true,
  montant_commission_ht:14.52,montant_commission_tva:2.90,montant_commission_ttc:17.42});
 return s;
}
test('configuration absente : admission nulle sans transport',()=>assert.equal(parse({}),null));
test('configuration TEST exacte et expiration bornée',()=>{assert.deepEqual(parse(),config);assert.equal(h.stagingInvoiceCheckoutExpiry(parse(),now),Math.floor(Date.parse(config.expiresAt)/1000));});
for(const [key,value] of Object.entries({SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co',STRIPE_SECRET_KEY:'sk_live_NeverAllowed',SUPABASE_ENV:'production',CONNECT_STAGING_TEST_RUN:'active'}))
 test(`refuse environnement ${key}`,()=>assert.throws(()=>parse({...env,[key]:value}),/INVOICE_STAGING_TEST_REFUSED/));
for(const [key,value] of Object.entries({amountCents:10001,returnOrigin:'https://jolene.app',missionId:'invalid',extra:true,expiresAt:new Date(now+5*3600_000).toISOString()}))
 test(`refuse configuration ${key}`,()=>assert.throws(()=>parse({...env,INVOICE_STAGING_TEST_RUN:JSON.stringify({...config,[key]:value})}),/INVOICE_STAGING_TEST_REFUSED/));
test('expiration : rapprochement encore possible, nouvelle création refusée',()=>{
 const old={...config,createdAt:new Date(now-2*3600_000).toISOString(),expiresAt:new Date(now-3600_000).toISOString()};
 assert.ok(parse({...env,INVOICE_STAGING_TEST_RUN:JSON.stringify(old)}));assert.throws(()=>h.stagingInvoiceCheckoutExpiry(old,now));
});
test('cohorte et facture salariée exactes : lectures seulement',async()=>{const s=fixture();await h.requireStagingInvoiceScope(s.sb,parse(),F);assert.ok(s.calls.includes('auth:'+E));assert.ok(s.calls.includes('auth:'+S));assert.equal(s.calls.some(x=>/update|insert|rpc|create/.test(x)),false);});
for(const [name,change] of [
 ['autre facture',s=>s.rows.factures[0].id=M],['autre assigné',s=>s.rows.missions[0].soignant_assigne_id=E],
 ['mission libérale',s=>s.rows.missions[0].type_contrat_applique='LIBERAL'],['mission inachevée',s=>s.rows.missions[0].statut='EN_COURS'],
 ['montant changé',s=>s.rows.factures[0].montant_ttc=17.43],['net changé par avoir',s=>Object.assign(s.rows.factures[0],{montant_avoirs_imputes:1,montant_a_payer:16.42})],['solde absent',s=>delete s.rows.factures[0].montant_a_payer],['incident',s=>s.rows.factures[0].rapprochement_paiement_requis=true],['complément',s=>s.rows.factures[0].type_document='FACTURE_COMPLEMENTAIRE'],
 ['FH liée',s=>s.rows.factures[0].facture_honoraire_id=M],['facture groupée',s=>s.rows.factures[0].nombre_missions=2],
 ['autre mission groupée',s=>s.rows.missions.push({id:F,facture_id:F})],['Connect engagé',s=>s.rows.stripe_transfers.push({id:F,mission_id:M})],
 ['Auth non TEST',s=>s.users[S].app_metadata.est_compte_test=false],['owner étranger',s=>s.users[E].app_metadata.jolene_connect_fixture_owner='FOREIGN'],
 ['Customer changé',s=>s.rows.etablissements[0].stripe_customer_id='cus_Other'],['profil supprimé',s=>s.rows.soignants[0].supprime_le='2026-10-16'],
]) test(`scope refuse ${name}`,async()=>{const s=fixture();change(s);await assert.rejects(()=>h.requireStagingInvoiceScope(s.sb,parse(),F));});
test('facture groupée : seule mission liée, trois sommes canoniques et lectures seulement',async()=>{
 const s=groupedFixture();await h.requireStagingInvoiceScope(s.sb,parse(),F);
 assert.equal(s.calls.some(x=>/update|insert|rpc|create/.test(x)),false);
});
test('facture groupée : montants numériques PostgREST acceptés sans recalcul de taux',async()=>{
 const s=groupedFixture();for(const key of ['montant_ht','montant_tva','montant_ttc'])s.rows.factures[0][key]=String(s.rows.factures[0][key]);
 for(const key of ['montant_commission_ht','montant_commission_tva','montant_commission_ttc'])s.rows.missions[0][key]=String(s.rows.missions[0][key]);
 await h.requireStagingInvoiceScope(s.sb,parse(),F);
});
test('facture directe : ancien lien nullable ou inverse inchangé',async()=>{
 for(const link of [null,F]){const s=fixture();s.rows.missions[0].facture_id=link;await h.requireStagingInvoiceScope(s.sb,parse(),F);}
});
const groupedRefus = [
 ['aucun lien inverse',s=>s.rows.missions[0].facture_id=null],
 ['autre facture liée',s=>s.rows.missions[0].facture_id=M],
 ['mission_id absent',s=>delete s.rows.factures[0].mission_id],
 ['mission_id étranger',s=>s.rows.factures[0].mission_id=F],
 ['commission non facturée',s=>s.rows.missions[0].commission_facturee=false],
 ['plusieurs missions annoncées',s=>s.rows.factures[0].nombre_missions=2],
 ['autre mission effectivement liée',s=>s.rows.missions.push({id:F,facture_id:F})],
 ['HT mission différent',s=>s.rows.missions[0].montant_commission_ht=14.51],
 ['TVA mission différente',s=>s.rows.missions[0].montant_commission_tva=2.91],
 ['TTC mission différent',s=>s.rows.missions[0].montant_commission_ttc=17.43],
 ['HT facture différent',s=>s.rows.factures[0].montant_ht=14.51],
 ['TVA facture différente',s=>s.rows.factures[0].montant_tva=2.91],
 ['TTC facture différent',s=>s.rows.factures[0].montant_ttc=17.43],
 ['somme HT TVA incohérente',s=>{s.rows.factures[0].montant_ht=14.51;s.rows.missions[0].montant_commission_ht=14.51;}],
 ['montants négatifs compensés',s=>{Object.assign(s.rows.factures[0],{montant_ht:18.42,montant_tva:-1});Object.assign(s.rows.missions[0],{montant_commission_ht:18.42,montant_commission_tva:-1});}],
 ['trace Connect',s=>s.rows.stripe_transfers.push({id:F,mission_id:M})],
 ...['montant_ht','montant_tva','montant_ttc'].map(key=>['facture '+key+' absent',s=>s.rows.factures[0][key]=null]),
 ...['montant_commission_ht','montant_commission_tva','montant_commission_ttc'].map(key=>['mission '+key+' absent',s=>s.rows.missions[0][key]=null]),
 ...[NaN,Infinity,'',true,'invalide'].map(value=>['valeur non monétaire '+String(value),s=>s.rows.missions[0].montant_commission_ht=value]),
];
for(const [name,change] of groupedRefus)test(`facture groupée refuse ${name}`,async()=>{
 const s=groupedFixture();change(s);await assert.rejects(()=>h.requireStagingInvoiceScope(s.sb,parse(),F));
});
test('événements groupés : metadata facture réelles et deux claims exacts requis',async()=>{
 const s=groupedFixture();assert.equal(s.event.data.object.metadata.mission_id,undefined);
 assert.equal(await h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',s.event),true);
 const intent={id:'pi_Synthetic',livemode:false,currency:'eur',customer:C,amount:1742,metadata:{facture_id:F,etablissement_id:E}};
 assert.equal(await h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',{type:'payment_intent.succeeded',livemode:false,data:{object:intent}}),true);
 s.rows.stripe_payment_flow_claims=s.rows.stripe_payment_flow_claims.filter(row=>row.resource_key===`FACTURE:${F}`);
 await assert.rejects(()=>h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',s.event));
});
test('identité Stripe : lecture du Customer existant uniquement',async()=>{const s=fixture();assert.equal(await h.stagingInvoiceCustomer(s.stripe),C);assert.equal(s.calls.filter(x=>x.startsWith('stripe:')).length,3);});
for(const [name,change] of [['LIVE',s=>s.identity.live=true],['plateforme étrangère',s=>s.identity.platform='acct_Foreign'],['Customer LIVE',s=>s.identity.customer.livemode=true],['tenant étranger',s=>s.identity.customer.metadata.etablissement_id=S]])
 test(`identité Stripe refuse ${name}`,async()=>{const s=fixture();change(s);await assert.rejects(()=>h.stagingInvoiceCustomer(s.stripe));});
test('admet seulement les deux événements liés à sa Session claimée',async()=>{
 const s=fixture();assert.equal(await h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',s.event),true);
 const intent={id:'pi_Synthetic',livemode:false,currency:'eur',customer:C,amount:1742,metadata:{facture_id:F,etablissement_id:E}};
 assert.equal(await h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',{type:'payment_intent.succeeded',livemode:false,data:{object:intent}}),true);
});
for(const type of ['refund.updated','payout.paid','checkout.session.expired','charge.succeeded'])
 test(`aucune admission ${type}`,async()=>{const s=fixture();s.event.type=type;assert.equal(await h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',s.event),false);assert.deepEqual(s.calls,[]);});
for(const [name,change] of [['Session étrangère',s=>s.event.data.object.id='cs_test_Foreign'],['objet LIVE',s=>s.event.data.object.livemode=true],['montant étranger',s=>s.event.data.object.amount_total=1743],['claim concurrent',s=>s.rows.stripe_payment_flow_claims[0].flow='SEPA_INVOICE'],['claim non lié',s=>s.rows.stripe_payment_flow_claims[0].stripe_checkout_session_id=null],['PI concurrent',s=>s.rows.stripe_payment_flow_claims[0].stripe_payment_intent_id='pi_Foreign']])
 test(`événement refuse ${name}`,async()=>{const s=fixture();change(s);await assert.rejects(()=>h.requireStagingInvoiceEvent(s.sb,s.stripe,parse(),'PLATFORM',s.event));});
function checkoutParams(path){
 const s=readFileSync(path,'utf8');const start=s.indexOf('const sessionParams: any = {');const end=s.indexOf('\n    if (embedded)',start);
 assert.ok(start>0&&end>start);
 const block=s.slice(start,end).replace('const sessionParams: any =','const sessionParams =');
 return Function('customerId','facture','montantCents',block+'; return sessionParams;')(C,{id:F,numero_facture:'SYNTHETIC',nombre_missions:1,etablissement_id:E},1742);
}
test('reproduction locale du contrat Stripe : ancien descripteur carte rejeté, candidat accepté, SEPA conservé',()=>{
 // Contrat documenté : https://docs.stripe.com/api/payment_intents/create#payment_intent_create-statement_descriptor
 // Transport synthétique ; aucune requête fournisseur n'est émise.
 const transport=body=>{if(body.payment_intent_data.statement_descriptor!==undefined)throw Error('statement_descriptor is not supported for card payments');return {accepted:true};};
 const fresh=checkoutParams(`${ROOT}/supabase/functions/create-invoice-payment/index.ts`);
 // Paramètre présent dans la source avant correction, conservé ici comme négatif.
 const old={...fresh,payment_intent_data:{...fresh.payment_intent_data,statement_descriptor:'JOLENE'}};
 assert.throws(()=>transport(old),/statement_descriptor/);assert.deepEqual(transport(fresh),{accepted:true});
 assert.deepEqual(fresh.payment_intent_data.metadata,old.payment_intent_data.metadata);
 assert.match(readFileSync(`${ROOT}/supabase/functions/sepa-auto-charge/index.ts`,'utf8'),/statement_descriptor: "JOLENE"/);
});

// Vrais handlers et vrais helpers Auth/classification/claims/audit/charge.
// Seuls SDK Auth/PostgREST/Stripe sont remplacés par des transports en mémoire.
function handlers({grouped=false,nonTest=false,sepa=false}={}){
 const s=grouped?groupedFixture():fixture();s.rows.stripe_payment_flow_claims=[];
 const f=s.rows.factures[0];Object.assign(f,{numero_facture:'SYNTHETIC',stripe_payment_intent_id:null,stripe_hosted_url:null,est_secteur_public:false,chorus_pro_statut:null,
  etablissements:{id:E,nom:'SYNTHETIC',email_contact:'synthetic@example.invalid',stripe_customer_id:C,mode_paiement_commission:'MANUEL',est_secteur_public:false,chorus_pro_actif:false}});
 // Le chemin standard valide aussi le profil Customer existant. La fixture
 // Stripe doit le fournir, sinon le vrai helper tente une synchronisation
 // nom/email, interdite dans ce banc limité aux montants de paiement.
 Object.assign(s.identity.customer,{name:'SYNTHETIC',email:'synthetic@example.invalid'});
 // Non-TEST ne désigne ici que des objets en mémoire, jamais un fournisseur.
 if(nonTest){for(const user of Object.values(s.users))user.app_metadata.est_compte_test=false;for(const t of ['etablissements','soignants'])s.rows[t][0].est_compte_test=false;}
 if(sepa){f.mission_id=null;Object.assign(f.etablissements,{mode_paiement_commission:'SEPA_DEBIT',stripe_sepa_payment_method_id:'pm_Synthetic'});}
 const provider={sessions:[],intent:null,createCalls:0,intentCreates:[],checkoutBodies:[]};const mutations=[],clientOptions=[];
 const envRun={...env,INVOICE_STAGING_TEST_RUN:JSON.stringify(config),SUPABASE_ANON_KEY:'SYNTHETIC_ANON',SUPABASE_SERVICE_ROLE_KEY:'SYNTHETIC_SERVICE'};
 if(nonTest)delete envRun.INVOICE_STAGING_TEST_RUN;
 s.sb.auth.getUser=async token=>({data:{user:token==='SYNTHETIC_USER'?s.users[E]:null},error:token==='SYNTHETIC_USER'?null:{message:'invalid'}});
 s.sb.from=table=>{
  assert.ok(s.rows[table],`unknown table ${table}`);s.calls.push(`read:${table}`);
  const filters=[];let limit=Infinity,update=null;
  const result=()=>{if(table==='factures' && update && provider.beforeFactureWrite){const before=provider.beforeFactureWrite;delete provider.beforeFactureWrite;before();}let rows=s.rows[table].filter(r=>filters.every(fn=>fn(r))).slice(0,limit);if(update){mutations.push('update:'+table);rows.forEach(r=>Object.assign(r,structuredClone(update)));}return {data:structuredClone(rows),error:null};};
  const q={select(){return q;},eq(k,v){filters.push(r=>r[k]===v);return q;},neq(k,v){filters.push(r=>r[k]!==v);return q;},is(k,v){filters.push(r=>r[k]===v);return q;},in(k,v){filters.push(r=>v.includes(r[k]));return q;},not(k,op,v){assert.equal(op,'in');const vals=v.slice(1,-1).split(',');filters.push(r=>!vals.includes(r[k]));return q;},order(){return q;},limit(n){limit=n;return q;},update(v){update=v;return q;},async maybeSingle(){const r=result();assert.ok(r.data.length<=1);return {...r,data:r.data[0]??null};},single(){return q.maybeSingle();},then(yes,no){return Promise.resolve(result()).then(yes,no);}};return q;
 };
 s.sb.rpc=async(name,args)=>{
  s.calls.push('rpc:'+name);
  if(name==='fn_a_permission_etablissement')return {data:true,error:null};
  if(name==='fn_ecrire_audit_safe')return {data:{success:true},error:null};
  assert.equal(name,'fn_stripe_payment_flow_claim');
  assert.equal(args.p_flow,sepa?'SEPA_INVOICE':'CHECKOUT_INVOICE');assert.equal(args.p_facture_id,F);assert.equal(args.p_mission_id,null);
  if(!s.rows.stripe_payment_flow_claims.length){mutations.push('rpc:claim');s.rows.stripe_payment_flow_claims=[`FACTURE:${F}`,`MISSION:${M}`].map(resource_key=>({resource_key,flow:args.p_flow,owner_token:args.p_owner_token,stripe_checkout_session_id:null,stripe_payment_intent_id:null}));}
  const first=s.rows.stripe_payment_flow_claims[0];return {data:{acquired:true,resources:s.rows.stripe_payment_flow_claims.map(r=>r.resource_key),stripe_checkout_session_id:first.stripe_checkout_session_id,stripe_payment_intent_id:first.stripe_payment_intent_id},error:null};
 };
 const forbid=what=>{throw Error('UNEXPECTED_TRANSPORT:'+what);};
 class StripeTransport{
  static errors=new Proxy({},{get:()=>class StripeTestError extends Error{}});
  accounts=s.stripe.accounts;balance=s.stripe.balance;customers={...s.stripe.customers,create:()=>forbid('customer.create'),update:()=>forbid('customer.update')};
  paymentMethods={retrieve:async id=>({id,type:'sepa_debit',customer:C})};
  paymentIntents={create:async(body,opts)=>{assert.equal(opts.idempotencyKey,`jolene-sepa-facture-${F}`);provider.intentCreates.push(body);provider.intent={id:'pi_Synthetic',status:'processing',amount:body.amount,amount_received:0,currency:'eur',customer:C,metadata:body.metadata};return structuredClone(provider.intent);},search:async()=>({data:provider.intent?[provider.intent]:[],has_more:false}),list:async()=>({data:provider.intent?[provider.intent]:[],has_more:false}),retrieve:async id=>{assert.equal(id,provider.intent?.id);return structuredClone(provider.intent);}};
  charges={retrieve:async id=>{assert.equal(id,'ch_Synthetic');return {id,paid:true,captured:true,status:'succeeded',amount:Math.round(Number(f.montant_a_payer)*100),amount_refunded:0,refunded:false,disputed:false,currency:'eur',customer:C,payment_intent:'pi_Synthetic'};}};
  checkout={sessions:{list:async()=>({data:structuredClone(provider.sessions),has_more:false}),retrieve:async id=>{assert.equal(id,provider.sessions[0]?.id);return structuredClone(provider.sessions[0]);},create:async(body,options)=>{
   assert.equal(body.payment_intent_data.statement_descriptor,undefined);assert.equal(body.expires_at,nonTest?undefined:Math.floor(Date.parse(config.expiresAt)/1000));assert.equal(options.idempotencyKey,`invoice_checkout_${F}`);
   if(!nonTest)assert.equal(body.return_url,`${config.returnOrigin}/etablissement/facturation?paiement=succes&session_id={CHECKOUT_SESSION_ID}`);
   assert.deepEqual(JSON.parse(JSON.stringify(body.metadata)),{facture_id:F,etablissement_id:E});
   provider.checkoutBodies.push(body);provider.createCalls++;mutations.push('stripe:checkout:create');const session={...structuredClone(s.session),status:'open',payment_status:'unpaid',payment_intent:null,amount_total:body.line_items[0].price_data.unit_amount,url:null,client_secret:'SYNTHETIC_CLIENT_SECRET'};provider.sessions.push(session);return structuredClone(session);
  },expire:()=>forbid('session.expire')}};
 }
 const cache=new Map();const registered={};
 const base=process.env.JOLENE_INVOICE_BASE_ROOT??ROOT;
 function load(file){
  file=resolve(file);if(cache.has(file))return cache.get(file);const exports={};cache.set(file,exports);
  const sourceFile=existsSync(file)?file:resolve(base,file.slice(ROOT.length+1));
  const output=ts.transpileModule(readFileSync(sourceFile,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.deepEqual(output.diagnostics,[]);
  runInNewContext(output.outputText,{exports,Request,Response,Headers,URL,Date,Error,Map,Set,Promise,structuredClone,
   require:name=>name==='npm:stripe@20.4.1'?{default:StripeTransport}:name.startsWith('npm:@supabase/supabase-js@')?{createClient:(_url,key,options)=>{clientOptions.push({key,options});return s.sb;}}:name.startsWith('.')?load(resolve(dirname(file),name)):forbid('import:'+name),
   Deno:{env:{get:key=>envRun[key]},serve:fn=>{registered[file]=fn;}},fetch:()=>forbid('fetch'),console:{log(){},warn(){},error(){},info(){}}});
  return exports;
 }
 const createFile=resolve(ROOT,'supabase/functions/create-invoice-payment/index.ts');load(createFile);
 const confirmFile=resolve(ROOT,'supabase/functions/confirm-invoice-payment/index.ts');load(confirmFile);
 const sepaFile=resolve(ROOT,'supabase/functions/sepa-auto-charge/index.ts');load(sepaFile);
 const run=(file,token='SYNTHETIC_USER')=>registered[file](new Request('https://simulation.invalid',{method:'POST',headers:{Authorization:'Bearer '+token,Origin:config.returnOrigin,'x-jolene-paid-invoice-email':'injected-value'},body:JSON.stringify({facture_id:F,embedded:true})}));
 const pay=()=>{const session=provider.sessions[0];session.status='complete';session.payment_status='paid';session.payment_intent='pi_Synthetic';provider.intent={id:'pi_Synthetic',status:'succeeded',livemode:false,currency:'eur',amount:session.amount_total,amount_received:session.amount_total,customer:C,metadata:{facture_id:F,etablissement_id:E},created:Math.floor(now/1000),latest_charge:'ch_Synthetic'};};
 return {s,provider,mutations,clientOptions,envRun,pay,create:(token)=>run(createFile,token),confirm:(token)=>run(confirmFile,token),sepa:()=>run(sepaFile,'SYNTHETIC_SERVICE')};
}
test('vrais handlers : un Checkout puis reprise sans nouvelle création, paiement exact confirmé',async()=>{
 const r=handlers();let response=await r.create();assert.equal(response.status,200);assert.equal((await response.json()).client_secret,'SYNTHETIC_CLIENT_SECRET');
 response=await r.create();assert.equal(response.status,200);assert.equal((await response.json()).resumed,true);assert.equal(r.provider.createCalls,1);
 r.pay();response=await r.confirm();const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));assert.equal(body.confirmed,true);assert.equal(r.s.rows.factures[0].statut,'PAYEE');assert.equal(r.provider.createCalls,1);
 const admin = r.clientOptions.filter(c=>c.key==='SYNTHETIC_SERVICE').at(-1);
 assert.equal(admin.options.global.headers['x-jolene-paid-invoice-email'],'durable-v1');
});
test('vrais handlers : sans runtime TEST, ancienne interdiction préservée',async()=>{const r=handlers();delete r.envRun.INVOICE_STAGING_TEST_RUN;assert.equal((await r.create()).status,403);assert.equal((await r.confirm()).status,403);assert.deepEqual(r.mutations,[]);});
test('vrais handlers : PROD refuse ce runtime avant création ou écriture',async()=>{const r=handlers();r.envRun.SUPABASE_URL='https://flripxtsyegjshnhzjkz.supabase.co';assert.notEqual((await r.create()).status,200);assert.notEqual((await r.confirm()).status,200);assert.deepEqual(r.mutations,[]);});
test('vrais handlers : faux JWT et service_role ne contournent pas la session utilisateur',async()=>{for(const token of ['FORGED_USER','SYNTHETIC_SERVICE']){const r=handlers();assert.ok([401,403].includes((await r.create(token)).status));assert.ok([401,403].includes((await r.confirm(token)).status));assert.deepEqual(r.mutations,[]);}});
test('vrai handler : Session expirée ne crée aucune nouvelle tentative TEST',async()=>{const r=handlers();assert.equal((await r.create()).status,200);r.provider.sessions[0].status='expired';const before=r.mutations.length;assert.notEqual((await r.create()).status,200);assert.equal(r.provider.createCalls,1);assert.equal(r.mutations.length,before);});

test('vrais handlers groupés : Checkout unique, reprise et confirmation avec metadata facture',async()=>{
 const r=handlers({grouped:true});let response=await r.create();assert.equal(response.status,200);
 response=await r.create();assert.equal(response.status,200);assert.equal((await response.json()).resumed,true);assert.equal(r.provider.createCalls,1);
 assert.equal(r.provider.sessions[0].metadata.mission_id,undefined);
 assert.deepEqual(r.s.rows.stripe_payment_flow_claims.map(row=>row.resource_key).sort(),[`FACTURE:${F}`,`MISSION:${M}`].sort());
 r.pay();response=await r.confirm();const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));assert.equal(body.confirmed,true);
 assert.equal(r.s.rows.factures[0].statut,'PAYEE');assert.equal(r.s.rows.factures[0].mission_id,null);assert.equal(r.s.rows.missions[0].facture_id,F);
 assert.equal(r.provider.createCalls,1);
});
for(const [name,change] of groupedRefus)test(`vrai handler groupé refuse avant claim ou Checkout : ${name}`,async()=>{
 const r=handlers({grouped:true});change(r.s);assert.notEqual((await r.create()).status,200);
 assert.deepEqual(r.mutations,[]);assert.equal(r.provider.createCalls,0);
});
test('vrai handler groupé : variation de commission après paiement bloque la confirmation',async()=>{
 const r=handlers({grouped:true});assert.equal((await r.create()).status,200);r.pay();
 r.s.rows.missions[0].montant_commission_ht=14.51;const before=r.mutations.length;
 assert.notEqual((await r.confirm()).status,200);assert.equal(r.s.rows.factures[0].statut,'EMISE');assert.equal(r.mutations.length,before);
});

// Recettes des handlers avec SDK en mémoire : aucune admission TEST fournisseur ajoutée.
test('avoir partiel : Checkout débite le net et confirmation conserve les trois montants',async()=>{
 const r=handlers({nonTest:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:5,montant_a_payer:12.42});
 let response=await r.create();assert.equal(response.status,200,JSON.stringify(await response.json()));
 assert.equal(r.provider.checkoutBodies[0].line_items[0].price_data.unit_amount,1242);
 r.pay();response=await r.confirm();assert.equal(response.status,200,JSON.stringify(await response.json()));
 assert.equal(r.s.rows.factures[0].statut,'PAYEE');assert.equal(r.s.rows.factures[0].montant_ttc,17.42);assert.equal(r.s.rows.factures[0].montant_a_payer,12.42);
 response=await r.confirm();assert.equal(response.status,200);assert.equal(r.provider.createCalls,1);
});
test('avoir total déjà soldé : création et confirmation retournent PAYEE sans aucun objet Stripe',async()=>{
 const r=handlers({nonTest:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:17.42,montant_a_payer:0,statut:'PAYEE',mode_paiement:'AVOIR'});
 delete r.envRun.STRIPE_SECRET_KEY;
 for(const response of [await r.create(),await r.confirm()]){assert.equal(response.status,200);assert.equal((await response.json()).status,'PAYEE');}
 assert.equal(r.provider.createCalls,0);assert.deepEqual(r.mutations,[]);assert.equal(r.s.calls.some(x=>x.startsWith('stripe:')),false);
});
for(const [label,patch] of [['solde manquant',{montant_a_payer:undefined}],['net incohérent',{montant_a_payer:1}],['rapprochement requis',{rapprochement_paiement_requis:true}]])test(`handlers refusent ${label} avant transport`,async()=>{
 const r=handlers({nonTest:true});Object.assign(r.s.rows.factures[0],patch);
 assert.notEqual((await r.create()).status,200);assert.notEqual((await r.confirm()).status,200);assert.deepEqual(r.mutations,[]);assert.equal(r.provider.createCalls,0);
});
test('confirmation refuse un PI au TTC après imputation partielle',async()=>{
 const r=handlers({nonTest:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:5,montant_a_payer:12.42});
 assert.equal((await r.create()).status,200);r.pay();r.provider.intent.amount=1742;r.provider.intent.amount_received=1742;
 assert.notEqual((await r.confirm()).status,200);assert.equal(r.s.rows.factures[0].statut,'EMISE');
});
test('SEPA : débit du seul net, puis exclusion après liaison du PI',async()=>{
 const r=handlers({nonTest:true,sepa:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:5,montant_a_payer:12.42});
 let response=await r.sepa();assert.equal(response.status,200,JSON.stringify(await response.json()));
 assert.equal(r.provider.intentCreates.length,1);assert.equal(r.provider.intentCreates[0].amount,1242);
 assert.equal(r.s.rows.factures[0].stripe_payment_intent_id,'pi_Synthetic');
 response=await r.sepa();assert.equal(response.status,200);assert.equal(r.provider.intentCreates.length,1);
});
test('SEPA : facture soldée par avoir ou incident exclu avant le débit',async()=>{
 for(const patch of [{statut:'PAYEE',mode_paiement:'AVOIR',montant_avoirs_imputes:17.42,montant_a_payer:0},{rapprochement_paiement_requis:true}]){
  const r=handlers({nonTest:true,sepa:true});Object.assign(r.s.rows.factures[0],patch);assert.equal((await r.sepa()).status,200);assert.deepEqual(r.provider.intentCreates,[]);assert.deepEqual(r.mutations,[]);
 }
});

for(const cents of [1,49])test(`carte : net ${cents} centime(s) conservé, virement proposé sans création`,async()=>{
 const r=handlers({nonTest:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:(1742-cents)/100,montant_a_payer:cents/100});
 const response=await r.create();assert.equal(response.status,409);const body=await response.json();assert.equal(body.error,'CARD_AMOUNT_TOO_SMALL');assert.match(body.message,/virement/);
 assert.equal(r.provider.createCalls,0);assert.deepEqual(r.mutations,[]);assert.equal(r.s.rows.factures[0].montant_a_payer,cents/100);
});

for(const cents of [1,49])test(`SEPA : net ${cents} centime(s) sans tentative ni arrondi`,async()=>{
 const r=handlers({nonTest:true,sepa:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:(1742-cents)/100,montant_a_payer:cents/100});
 const response=await r.sepa();assert.equal(response.status,200);const body=await response.json();assert.equal(body.results[0].error,'SEPA_AMOUNT_TOO_SMALL');
 assert.deepEqual(r.provider.intentCreates,[]);assert.deepEqual(r.mutations,[]);assert.equal(r.s.rows.factures[0].montant_a_payer,cents/100);
});
test('frontière EUR : 50 centimes admis sans majoration, carte et SEPA',async()=>{
 for(const sepa of [false,true]){const r=handlers({nonTest:true,sepa});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:16.92,montant_a_payer:0.50});
 const response=sepa?await r.sepa():await r.create();assert.equal(response.status,200,JSON.stringify(await response.json()));
 assert.equal(sepa?r.provider.intentCreates[0].amount:r.provider.checkoutBodies[0].line_items[0].price_data.unit_amount,50);}
});

test('confirmation : incident concurrent fait perdre le CAS, aucun faux PAYEE',async()=>{
 const r=handlers({nonTest:true});Object.assign(r.s.rows.factures[0],{montant_avoirs_imputes:5,montant_a_payer:12.42});
 assert.equal((await r.create()).status,200);r.pay();r.provider.beforeFactureWrite=()=>{r.s.rows.factures[0].rapprochement_paiement_requis=true;};
 const response=await r.confirm();assert.equal(response.status,409,JSON.stringify(await response.json()));
 assert.equal(r.s.rows.factures[0].statut,'EMISE');assert.equal(r.s.rows.factures[0].rapprochement_paiement_requis,true);
});
