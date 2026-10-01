import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ATTENDUS, CATALOGUE, SOURCE, executerTemoin, verifierCatalogue, verifierRouge } from '../../scripts/ci/f1-heures-temoin-avant-migration.mjs';

const copy = x => structuredClone(x);
const compteurs = Object.fromEntries(['auth_users','soignants','etablissements','missions','presences','creneaux','equipes','litiges','honoraires','commissions','audit_factures','audits','notifications','preferences','conformite','suivi','emails','externalisations','escrow','refunds','cessions','scoring','escrow_release','stripe_transfers','net_requests'].map(k => [k,0]));
const catalogue = [{ helper_remplacement_md5:'c793ac81eaef0fe18fb5920c9264c675', routines_md5:'a'.repeat(32), triggers_md5:'b'.repeat(32), residus:0, compteurs }];
const errorBody = (diagnostics=ATTENDUS) => ({message:'Failed to run sql query: ERROR:  P0001: F1_HEURES_CHAINE_COMMISSION_INCOHERENTE attendu suivante=12/2.40/14.40 cumul=140/21 ; observe='+JSON.stringify(diagnostics)+'\nCONTEXT:  PL/pgSQL function inline_code_block line 444 at RAISE\n'});
const env = {STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'fictif-jamais-envoye',RUNNER_TEMP:'/tmp/fictif'};

test('accepte uniquement les deux diagnostics exacts de l’erreur métier P0001', () => {
  assert.deepEqual(verifierRouge(400,errorBody()),ATTENDUS);
  assert.deepEqual(verifierCatalogue(catalogue),catalogue);
});
for (const [nom, mutate] of Object.entries({
  'autre code': b => { b.message=b.message.replace('P0001','JF141'); },
  'code contradictoire': b => { b.code='57014'; },
  'timeout': b => { b.message='Query timed out'; },
  'autre garde': b => { b.message=b.message.replace('F1_HEURES_CHAINE_COMMISSION_INCOHERENTE','F1_GARDE'); },
  'sentinelle interne': b => { b.message='F1_ANNULATION_ATTENDUE'; },
  'montant différent': b => { b.message=b.message.replace('10.5','10.6'); },
  'chaine plutôt que nombre': b => { b.message=b.message.replace('10.5','"10.5"'); },
  'json manquant': b => { b.message=b.message.replace(JSON.stringify(ATTENDUS),'null'); },
  'contexte absent': b => { b.message=b.message.split('\n')[0]; },
  'suffixe inconnu': b => { b.message+='autre échec'; },
  'champ supplémentaire': b => { const d=copy(ATTENDUS); d[0].autre=true; b.message=errorBody(d).message; },
  'troisième diagnostic': b => { b.message=errorBody([...ATTENDUS,ATTENDUS[0]]).message; },
  'un seul diagnostic': b => { b.message=errorBody([ATTENDUS[0]]).message; },
  'ordre inversé': b => { b.message=errorBody([...ATTENDUS].reverse()).message; },
  'clé dupliquée': b => { b.message=b.message.replace('"cas":"intermediaire"','"cas":"inattendu","cas":"intermediaire"'); },
})) test(`refuse ${nom}`, () => { const b=errorBody(); mutate(b); assert.throws(() => verifierRouge(400,b)); });
for (const status of [0,200,201,301,401,403,404,408,429,500,503,504]) test(`HTTP ${status} ne prouve pas le rouge`, () => assert.throws(() => verifierRouge(status,errorBody())));

function harness({response=errorBody(),status=400,after=catalogue,network=false,sourceChanged=false,before=catalogue}={}) {
  const calls=[],saved=[];
  return {calls,saved,options:{env,
    lire:async (path,encoding) => {
      if(path.endsWith('f1-catalogue-avant.json'))return JSON.stringify(before);
      const text=await readFile(path,encoding);return sourceChanged&&path===SOURCE?text+'\n':text;
    },
    ecrire:async (path,body) => { saved.push({path,body:JSON.parse(body)}); },
    fetcher:async (url,options) => {
      assert.equal(url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
      assert.equal(options.redirect,'error');assert.equal(options.method,'POST');
      const payload=JSON.parse(options.body);calls.push(payload);
      if(calls.length===1) {
        assert.equal(payload.read_only,false);assert.equal(payload.query,await readFile(SOURCE,'utf8'));
        if(network)throw new Error('Réseau indisponible');
        return {status,redirected:false,text:async()=>JSON.stringify(response)};
      }
      assert.equal(calls.length,2);assert.equal(payload.read_only,true);assert.equal(payload.query,await readFile(CATALOGUE,'utf8'));
      return {status:200,redirected:false,text:async()=>JSON.stringify(after)};
    },
  }};
}
test('exécute source inchangée une fois, contrôle indépendant puis preuve compacte',async()=>{
  const h=harness();const p=await executerTemoin(h.options);
  assert.equal(h.calls.length,2);assert.equal(h.saved.length,1);assert.equal(p.compteursVerifies,25);
  assert.equal(p.statut,'ROUGE_ATTENDU_PROUVE');assert.equal(p.sqlstateExterne,'P0001');assert.equal(p.sentinelleInterne,'JF141');
  assert(!JSON.stringify(h.saved).includes(env.STAGING_SUPABASE_ACCESS_TOKEN));
});
for(const [nom,options] of Object.entries({network:{network:true},autreErreur:{response:{message:'Erreur inattendue'}},succesInattendu:{status:200,response:[]}}))test(`contrôle après ${nom}, sans rejouer la fixture`,async()=>{
  const h=harness(options);await assert.rejects(executerTemoin(h.options),/ROUGE_NON_PROUVE/);
  assert.equal(h.calls.length,2);assert.equal(h.saved.length,0);
});
for(const [nom,mutate] of Object.entries({
  compteurs:c=>c[0].compteurs.missions++, catalogue:c=>c[0].routines_md5='c'.repeat(32), residu:c=>c[0].residus++,
  helper:c=>c[0].helper_remplacement_md5='b'.repeat(32), manque:c=>delete c[0].compteurs.presences,
  autre:c=>c[0].compteurs.autre=0, queue:c=>c[0].compteurs.net_requests++,
}))test(`refuse contrôle indépendant ${nom}`,async()=>{
  const after=copy(catalogue);mutate(after);const h=harness({after});
  await assert.rejects(executerTemoin(h.options));assert.equal(h.calls.length,2);assert.equal(h.saved.length,0);
});
test('source modifiée refusée avant tout réseau',async()=>{
  const h=harness({sourceChanged:true});await assert.rejects(executerTemoin(h.options),/SOURCE_MODIFIEE/);assert.equal(h.calls.length,0);
});
test('ancien helper staging refusé avant la fixture',async()=>{
  const before=copy(catalogue);before[0].helper_remplacement_md5='b35b9b246690238ccb77e19e484c2a77';
  const h=harness({before});await assert.rejects(executerTemoin(h.options));assert.equal(h.calls.length,0);
});
for(const ref of ['flripxtsyegjshnhzjkz','inconnu',''])test(`projet refusé ${ref}`,async()=>{
  const h=harness();h.options.env={...env,STAGING_SUPABASE_PROJECT_REF:ref};
  await assert.rejects(executerTemoin(h.options),/ENV_REFUSE/);assert.equal(h.calls.length,0);
});
test('workflow : après sync+catalogue et avant migrations, aucun continue-on-error',async()=>{
  const yaml=await readFile('.github/workflows/validate-pr.yml','utf8');
  const sync=yaml.indexOf('- name: Synchroniser le schéma main vers le staging');
  const avant=yaml.indexOf('- name: F1 — catalogue et absence de résidus avant transaction');
  const temoin=yaml.indexOf('- name: F1 — reproduction exacte avant la migration candidate');
  const migration=yaml.indexOf('- name: Exécuter les migrations ajoutées et les régressions SQL sans persister');
  const apres=yaml.indexOf('- name: F1 — SELECT indépendant après succès ou échec SQL');
  assert(sync<avant&&avant<temoin&&temoin<migration&&migration<apres);
  const step=yaml.slice(temoin,migration);assert(!step.includes('continue-on-error'));
  assert(step.includes("--diff-filter=A"));assert(step.includes('20261001102511_aligner_commissions_pieces_et_estimation.sql'));
  assert(step.includes("has_migrations == 'true' && steps.migration_scope.outputs.has_f1_regression == 'true'"));
});


test('la matrice rejoue les vrais blocs préflight/inventaire sans changer les deux corps métier', async () => {
  const migration=await readFile('supabase/migrations/20261001102511_aligner_commissions_pieces_et_estimation.sql','utf8');
  const sql=await readFile('tests/security/facturation-commissions-pieces-matrice-f1.test.sql','utf8');
  for(const [source,replay] of [['preflight','preflight'],['inventory','inventory']]) {
    const body=migration.split(`DO $${source}$`)[1].split(`$${source}$;`)[0];
    const executed=sql.split(`AS $replay_${replay}$`)[1].split(`$replay_${replay}$;`)[0];
    assert.equal(executed,body,`le bloc ${source} testé doit être celui installé`);
  }
  const {createHash}=await import('node:crypto');
  const bodies=[...migration.matchAll(/AS \$function\$([\s\S]*?)\$function\$;/g)].map(m=>createHash('md5').update(m[1]).digest('hex'));
  assert.deepEqual(bodies,['8030a296741d5bfe6dad70edd4d8f20d','2767aab47df4d531744cd751a4faed95']);
  assert.match(sql,/DELETE FROM private\.security_definer_inventory WHERE signature=ANY\(v_signatures\)/);
  assert.match(sql,/ARRAY\['empreinte','categorie'\]/);
  assert.match(sql,/ARRAY\['preflight','installation'\]/);
  assert.match(sql,/v_functions_after IS DISTINCT FROM v_functions_before/);
  assert.match(sql,/v_after IS DISTINCT FROM v_before/);
  assert.match(sql,/ROLLBACK;\s*$/);
});
