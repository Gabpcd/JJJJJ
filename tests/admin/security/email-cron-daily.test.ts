import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import { FunctionsFetchError } from '@supabase/functions-js';
import * as budgetHelpers from '../../../supabase/functions/_shared/email-cron-budget';
import * as alertesHelpers from '../../../supabase/functions/_shared/alertes-filtres-queue';
import * as rappelsHelpers from '../../../supabase/functions/_shared/rappels-quotidiens-queue';

const source=ts.transpileModule(readFileSync('supabase/functions/email-cron/index.ts','utf8'),{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},
}).outputText;
const maintenance=['fn_verifier_documents_expirants','fn_auto_facturation_mensuelle','fn_purger_gps_ancien','fn_nettoyer_tokens_push'];
function simulation(missions=30) {
  type Ligne={id:string;type:string;statut:string;cree_le:string;destinataire_id:string;data:any};
  const queue:Ligne[]=[];const recus=new Map<string,any>();const appels:string[]=[];
  const transports:{nom:string;options:any}[]=[];const contrats:string[]=[];
  let now=Date.now();let handler!:(r:Request)=>Promise<Response>;
  let transport:()=>any=()=>({data:{success:true},error:null});let refusAcquittement=false;
  const sb={from:(table:string)=>{
    if(!['email_queue','serie_email_envois'].includes(table))throw new Error(`Table imprévue ${table}`);
    let limit=Infinity;const query={select(){return query;},eq(){return query;},lt(){return query;},order(){return query;},
      limit(n:number){limit=n;return query;},then(resolve:any,reject:any){return Promise.resolve().then(()=>{
        const rows=table==='email_queue'?queue.filter(r=>r.statut==='EN_ATTENTE'):[];
        return{data:rows.slice(0,limit),error:null,count:rows.length};
      }).then(resolve,reject);}};return query;
  },rpc:async(nom:string,p:any)=>{
    appels.push(nom);
    if(nom==='fn_preparer_rappels_quotidiens'){
      let total=0;
      for(let m=0;m<missions;m++)for(const nature of ['MISSION_EMAIL','MISSION_SMS','CONTRAT_ETAB','CONTRAT_SOIGNANT']){
        const id=`${m}-${nature}`;if(recus.has(id))continue;
        const sms=nature==='MISSION_SMS';
        const corps=sms?{type:'RAPPEL_MISSION_J1',destinataire_id:'soignant',telephone:'+33000000000',contenu:`Mission ${m}`,prefix_type:'RAPPEL_MISSION_J1'}
          :{type:nature==='MISSION_EMAIL'?'RAPPEL_MISSION':nature==='CONTRAT_ETAB'?'CONTRAT_TRAVAIL_RAPPEL_ETAB':'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT',destinataire_id:nature==='CONTRAT_ETAB'?'etab':'soignant',data:{mission_id:`mission-${m}`,prenom:'Recette'}};
        recus.set(id,{valide:true,canal:sms?'SMS':'EMAIL',scope:`daily-${nature}`,identite:{mission_id:`mission-${m}`,jour:'2026-09-25'},corps});
        queue.push({id,type:`CRON_DAILY_${nature}`,statut:'EN_ATTENTE',cree_le:'2026-09-25T08:00:00Z',destinataire_id:corps.destinataire_id,data:corps});total++;
      }
      return{data:{total},error:null};
    }
    if(nom==='fn_lire_rappel_quotidien')return{data:recus.get(p.p_email_id),error:null};
    if(nom==='fn_acquitter_rappel_quotidien'){
      if(refusAcquittement)return{data:null,error:{message:'503 acquittement'}};
      const row=queue.find(r=>r.id===p.p_email_id)!;
      if(row.statut==='EN_ATTENTE'){
        row.statut=p.p_resultat;
        if(p.p_resultat==='ENVOYE'&&row.type.includes('CONTRAT'))contrats.push(row.id);
      }
      return{data:null,error:null};
    }
    if(nom==='fn_reprendre_rappels_quotidiens'){
      for(const row of queue)if(row.statut==='ERREUR')row.statut='EN_ATTENTE';
      return{data:0,error:null}; // Backoff réel couvert par le test PostgreSQL.
    }
    if(maintenance.includes(nom))return{data:7,error:null};
    if(nom==='fn_basculer_litiges_revue_admin_timeout')return{data:{count:3},error:null};
    if(nom==='fn_envoyer_rappels_notation_j1')return{data:{count_etab:4,count_soignant:5},error:null};
    if(['fn_reprendre_alertes_filtres','fn_evaluer_alertes_filtres'].includes(nom))return{data:0,error:null};
    throw new Error(`RPC imprévue ${nom}`);
  },functions:{invoke:async(nom:string,options:any)=>{
    if(!['send-email','send-sms'].includes(nom))throw new Error(`Transport imprévu ${nom}`);
    transports.push({nom,options});return transport();
  }}};
  const modules:Record<string,unknown>={
    'https://esm.sh/@supabase/supabase-js@2':{createClient:()=>sb},
    '../_shared/alertes-filtres-queue.ts':alertesHelpers,
    '../_shared/rappels-quotidiens-queue.ts':rappelsHelpers,
    '../_shared/email-cron-budget.ts':{...budgetHelpers,creerBudgetEnvoi:(debut:number,ms:number)=>{
      now=debut;return budgetHelpers.creerBudgetEnvoi(debut,ms,()=>now,async delai=>{now+=delai;});}},
    '../_shared/cron-service-auth.ts':{verifyCronServiceAuth:async()=>({ok:true}),isCronAuthProbe:()=>false},
  };
  runInNewContext(source,{exports:{},require:(nom:string)=>{if(!(nom in modules))throw new Error(`Import imprévu ${nom}`);return modules[nom];},
    Deno:{env:{get:(cle:string)=>cle==='SUPABASE_URL'?'https://example.invalid':cle==='SUPABASE_SERVICE_ROLE_KEY'?'simulation':undefined},serve:(h:typeof handler)=>{handler=h;}},
    Date,Request,Response,AbortSignal,TextEncoder,crypto:webcrypto,console:{log(){},error(){},warn(){}},
    fetch:()=>{throw new Error('Réseau interdit');}});
  return{queue,recus,appels,transports,contrats,
    reponse(fn:typeof transport){transport=fn;},refuserAcquittement(v:boolean){refusAcquittement=v;},
    lancer:(mode='daily')=>handler(new Request('https://example.invalid/cron',{method:'POST',body:JSON.stringify({mode})})),
  };
}
describe('daily durable : vrai handler et drain, sans réseau',()=>{
  it('prépare 120 reçus sans transport, garde la maintenance et écoule six lots de 20 sans perte',async()=>{
    const s=simulation();const r=await s.lancer();expect(r.status).toBe(200);
    expect(s.transports).toHaveLength(0);expect(s.queue).toHaveLength(120);expect(s.contrats).toEqual([]);
    expect((await r.json()).results).toMatchObject({rappels_quotidiens_mis_en_file:{total:120},docs_expirants:7,factures:7,purge_gps:7,tokens_push:7,
      litiges_basculer_revue_admin:3,rappels_notation_etab:4,rappels_notation_soignant:5});
    for(const fn of maintenance)expect(s.appels.filter(n=>n===fn)).toHaveLength(1);
    expect((await (await s.lancer()).json()).results.rappels_quotidiens_mis_en_file.total).toBe(0);
    for(let tour=1;tour<=6;tour++){
      expect((await s.lancer('hourly')).status).toBe(200);
      expect(s.transports).toHaveLength(20*tour);
      expect(s.queue.filter(q=>q.statut==='ENVOYE')).toHaveLength(20*tour);
    }
    expect(s.queue.every(q=>q.statut==='ENVOYE')).toBe(true);
    expect(s.contrats).toHaveLength(60);expect(new Set(s.transports.map(t=>t.options.body.idempotency_key)).size).toBe(120);
    const sms=s.transports.filter(t=>t.nom==='send-sms');expect(sms).toHaveLength(30);
    expect(sms.every(t=>t.options.body.type==='RAPPEL_MISSION_J1'&&t.options.headers.Authorization==='Bearer simulation')).toBe(true);
    expect(s.transports.every(t=>t.options.timeout>0&&t.options.timeout<=8000)).toBe(true);
  });
  it('mode all applique aussi le budget et conserve le reste pour le drain minute',async()=>{
    const s=simulation();expect((await s.lancer('all')).status).toBe(200);
    expect(s.transports).toHaveLength(20);expect(s.queue.filter(q=>q.statut==='EN_ATTENTE')).toHaveLength(100);
  });
  it('timeout garde les reçus en attente et les quatre identités au prochain passage',async()=>{
    const s=simulation(1);await s.lancer();
    s.reponse(()=>({data:null,error:new FunctionsFetchError(new DOMException('Délai','TimeoutError'))}));
    expect((await s.lancer('hourly')).status).toBe(500);
    expect(s.queue.every(q=>q.statut==='EN_ATTENTE')).toBe(true);expect(s.contrats).toEqual([]);
    const cles=s.transports.map(t=>t.options.body.idempotency_key);
    s.reponse(()=>({data:{success:true},error:null}));await s.lancer('hourly');
    expect(s.transports.slice(4).map(t=>t.options.body.idempotency_key)).toEqual(cles);expect(s.contrats).toHaveLength(2);
  });
  it('503 transport est reprenable ; le payload demeure identique',async()=>{
    const s=simulation(1);await s.lancer();s.reponse(()=>({data:null,error:{message:'503'}}));
    expect((await s.lancer('hourly')).status).toBe(500);expect(s.queue.every(q=>q.statut==='ERREUR')).toBe(true);
    const corps=s.transports.map(t=>t.options.body);s.reponse(()=>({data:{success:true},error:null}));
    await s.lancer('hourly');expect(s.transports.slice(4).map(t=>t.options.body)).toEqual(corps);
  });
  it('refus de préférences annule sans comptabiliser un contrat',async()=>{
    const s=simulation(1);await s.lancer();s.reponse(()=>({data:{success:true,skipped:true,reason:'notification_disabled'},error:null}));
    expect((await s.lancer('hourly')).status).toBe(200);expect(s.queue.every(q=>q.statut==='ANNULE')).toBe(true);expect(s.contrats).toEqual([]);
  });
  it('succès suivi d’acquittement perdu rejoue la même clé et comptabilise une seule fois',async()=>{
    const s=simulation(1);await s.lancer();s.refuserAcquittement(true);await s.lancer('hourly');
    expect(s.queue.every(q=>q.statut==='EN_ATTENTE')).toBe(true);expect(s.contrats).toEqual([]);
    const cles=s.transports.map(t=>t.options.body.idempotency_key);s.refuserAcquittement(false);
    s.reponse(()=>({data:{success:true,skipped:true,reason:'idempotency_already_sent'},error:null}));
    expect((await s.lancer('hourly')).status).toBe(200);
    expect(s.transports.slice(4).map(t=>t.options.body.idempotency_key)).toEqual(cles);
    expect(s.queue.every(q=>q.statut==='ENVOYE')).toBe(true);expect(s.contrats).toHaveLength(2);
  });
  it('rappel devenu inutile est annulé sans transport',async()=>{
    const s=simulation(1);await s.lancer();for(const r of s.recus.values())r.valide=false;
    expect((await s.lancer('hourly')).status).toBe(200);expect(s.transports).toEqual([]);expect(s.queue.every(q=>q.statut==='ANNULE')).toBe(true);
  });
});
