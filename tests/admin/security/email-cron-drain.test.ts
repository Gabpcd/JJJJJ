import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import * as budgetHelpers from '../../../supabase/functions/_shared/email-cron-budget';
import * as rappelsHelpers from '../../../supabase/functions/_shared/rappels-quotidiens-queue';
import * as alertesHelpers from '../../../supabase/functions/_shared/alertes-filtres-queue';
import { FunctionsFetchError } from '@supabase/functions-js';

const source = ts.transpileModule(readFileSync('supabase/functions/email-cron/index.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;

function simulation(onboarding: number, emails: number) {
  type Ligne = { id: string; statut: string; [cle: string]: unknown };
  const tables: Record<string, Ligne[]> = {
    serie_email_envois: Array.from({length:onboarding},(_,i)=>({id:`serie-${i}`,statut:'PLANIFIE',utilisateur_id:'user',serie:'SOIGNANT_ONBOARDING',etape:i,tentatives:0})),
    email_queue: Array.from({length:emails},(_,i)=>({id:`email-${i}`,statut:'EN_ATTENTE',type:'NOUVELLES_MISSIONS_FILTRE',destinataire_id:'user',data:{count:1,missions:[]},cree_le:'2026-09-25T08:00:00Z'})),
    journaux_audit: [],
  };
  const transports: {nom:string;options:any}[] = [];
  const rpc: string[] = [];
  let now = Date.now();
  let resultatTransport: (p:any)=>any = () => ({data:{success:true},error:null});
  class Requete {
    filters: [string,unknown][] = []; maximum=Infinity; modification:Record<string,unknown>|null=null; insertion:Ligne|null=null; single=false;
    constructor(private table:string) { if (!tables[table]) throw new Error(`Table non simulée ${table}`); }
    select(){return this;} eq(k:string,v:unknown){this.filters.push([k,v]);return this;}
    lt(){return this;} order(){return this;} limit(n:number){this.maximum=n;return this;}
    update(v:Record<string,unknown>){this.modification=v;return this;} insert(v:Ligne){this.insertion=v;return this;}
    maybeSingle(){this.single=true;return Promise.resolve(this.executer());}
    executer(){
      if(this.insertion){tables[this.table].push(this.insertion);return{data:null,error:null};}
      const all=tables[this.table].filter(r=>this.filters.every(([k,v])=>r[k]===v));
      const rows=all.slice(0,this.maximum);
      if(this.modification)for(const row of rows)Object.assign(row,this.modification);
      return{data:this.single?(rows[0]??null):rows,error:null,count:all.length};
    }
    then(resolve:any,reject:any){return Promise.resolve().then(()=>this.executer()).then(resolve,reject);}
  }
  let optionsClient: any;
  const sb={
    from:(table:string)=>new Requete(table),
    rpc:async(nom:string)=>{
      rpc.push(nom);
      if(nom==='fn_verifier_skip_serie_onboarding')return{data:{skip:false},error:null};
      if(nom==='fn_obtenir_donnees_template_serie')return{data:{prenom:'Recette'},error:null};
      if(['fn_doit_notifier','fn_verifier_livraison_alerte_filtre'].includes(nom))return{data:true,error:null};
      if(['fn_reprendre_rappels_quotidiens','fn_reprendre_alertes_filtres','fn_evaluer_alertes_filtres','fn_reporter_echec_alerte_filtre'].includes(nom))return{data:0,error:null};
      throw new Error(`RPC non simulée ${nom}`);
    },
    functions:{invoke:async(nom:string,options:any)=>{
      if(!['send-email','send-sms'].includes(nom))throw new Error(`Transport non simulé ${nom}`);
      transports.push({nom,options});return resultatTransport(options);
    }},
  };
  let handler!: (req:Request)=>Promise<Response>;
  const modules:Record<string,unknown>={
    'https://esm.sh/@supabase/supabase-js@2':{createClient:(_url: string, _key: string, options: unknown)=>{optionsClient=options;return sb;}},
    '../_shared/alertes-filtres-queue.ts':alertesHelpers,
    '../_shared/rappels-quotidiens-queue.ts':rappelsHelpers,
    '../_shared/email-cron-budget.ts':{...budgetHelpers,creerBudgetEnvoi:(debut:number,ms:number)=>{
      now=debut;return budgetHelpers.creerBudgetEnvoi(debut,ms,()=>now,async delai=>{now+=delai;});
    }},
    '../_shared/cron-service-auth.ts':{verifyCronServiceAuth:async()=>({ok:true}),isCronAuthProbe:()=>false},
  };
  runInNewContext(source,{
    exports:{},require:(nom:string)=>{if(!(nom in modules))throw new Error(`Import non simulé ${nom}`);return modules[nom];},
    Deno:{env:{get:(cle:string)=>cle==='SUPABASE_URL'?'https://example.invalid':cle==='SUPABASE_SERVICE_ROLE_KEY'?'simulation':undefined},serve:(h:typeof handler)=>{handler=h;}},
    Date,Request,Response,AbortSignal,TextEncoder,crypto:webcrypto,console:{log(){},error(){},warn(){}},
    fetch:()=>{throw new Error('Réseau strictement interdit dans cette recette');},
  });
  return { tables, transports, rpc, get optionsClient(){return optionsClient;},
    transport(fn:typeof resultatTransport){resultatTransport=fn;},
    avancer(ms:number){now+=ms;},
    lancer:()=>handler(new Request('https://example.invalid/email-cron',{method:'POST',body:JSON.stringify({mode:'hourly'})})),
  };
}

describe('véritable handler email-cron avec transports entièrement simulés',()=>{
  it('écoule 5 onboarding et 20 messages, puis reprend le reste au tour suivant',async()=>{
    const s=simulation(8,45);
    const r=await s.lancer();expect(r.status).toBe(200);
    expect(s.optionsClient.global.headers.Authorization).toBe('Bearer simulation');
    expect(s.transports).toHaveLength(25);
    expect(s.tables.serie_email_envois.filter(r=>r.statut==='ENVOYE')).toHaveLength(5);
    expect(s.tables.email_queue.filter(r=>r.statut==='ENVOYE')).toHaveLength(20);
    expect((await r.json()).results).toMatchObject({email_queue_en_attente_initial:45,email_queue_lot_max:20,appels_transport:25});
    expect(s.transports.every(t=>t.options.timeout>0&&t.options.timeout<=8000)).toBe(true);
    expect((await s.lancer()).status).toBe(200);
    expect(s.tables.email_queue.filter(r=>r.statut==='ENVOYE')).toHaveLength(40);
    expect(s.tables.email_queue.filter(r=>r.statut==='EN_ATTENTE')).toHaveLength(5);
    expect(new Set(s.transports.map(t=>t.options.body.idempotency_key)).size).toBe(48);
  });
  it('un transport en attente ne consomme ni l’élément ni son identité',async()=>{
    const s=simulation(0,21);let premier=true;
    s.transport(()=>premier?{data:{success:true,pending:true},error:null}:{data:{success:true},error:null});
    expect((await s.lancer()).status).toBe(500);
    expect(s.tables.email_queue.every(r=>r.statut==='EN_ATTENTE')).toBe(true);
    const cle=s.transports[0].options.body.idempotency_key;premier=false;
    expect((await s.lancer()).status).toBe(200);
    expect(s.transports[20].options.body.idempotency_key).toBe(cle);
    expect(s.tables.email_queue.filter(r=>r.statut==='ENVOYE')).toHaveLength(20);
  });
  it('l’épuisement temporel laisse les messages non commencés disponibles',async()=>{
    const s=simulation(0,20);
    s.transport(()=>{s.avancer(8000);return{data:{success:true},error:null};});
    const r=await s.lancer();expect(r.status).toBe(200);
    expect(s.transports).toHaveLength(5);
    expect(s.tables.email_queue.filter(r=>r.statut==='EN_ATTENTE')).toHaveLength(15);
    expect((await r.json()).results.email_queue_budget_epuise).toBe(true);
  });
  it('une panne transport planifie la reprise et poursuit les autres éléments',async()=>{
    const s=simulation(0,2);let n=0;
    s.transport(()=>++n===1?{data:null,error:{message:'503 simulé'}}:{data:{success:true},error:null});
    expect((await s.lancer()).status).toBe(500);
    expect(s.tables.email_queue.map(r=>r.statut)).toEqual(['ERREUR','ENVOYE']);
    expect(s.rpc).toContain('fn_reporter_echec_alerte_filtre');
  });
  it.each(['AbortError','TimeoutError'])('un %s conserve email ordinaire, SMS et onboarding pour la même reprise',async nom=>{
    const s=simulation(1,2);
    s.tables.email_queue[0].type='FACTURE_EMISE';
    s.tables.email_queue[1].type='SMS_MISSION_URGENTE';
    s.tables.email_queue[1].data={telephone:'+33000000000',contenu:'Simulation sans réseau'};
    s.transport(()=>({data:null,error:new FunctionsFetchError(new DOMException('Délai simulé',nom))}));
    await s.lancer();
    expect(s.tables.email_queue.map(r=>r.statut)).toEqual(['EN_ATTENTE','EN_ATTENTE']);
    expect(s.tables.serie_email_envois[0]).toMatchObject({statut:'PLANIFIE',tentatives:0});
    expect(s.transports).toHaveLength(3);
    expect(s.transports[2].nom).toBe('send-sms');
    expect(s.transports[2].options.headers.Authorization).toBe('Bearer simulation');
    const cles=s.transports.map(t=>t.options.body.idempotency_key);
    s.transport(()=>({data:{success:true},error:null}));
    expect((await s.lancer()).status).toBe(200);
    expect(s.transports.slice(3).map(t=>t.options.body.idempotency_key)).toEqual(cles);
    expect(s.tables.email_queue.map(r=>r.statut)).toEqual(['ENVOYE','ENVOYE']);
    expect(s.tables.serie_email_envois[0]).toMatchObject({statut:'ENVOYE',tentatives:1});
  });
});
