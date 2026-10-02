import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { proveCatalogue, checkReference, rollbackSql } from '../../scripts/ci/connect-staging-catalogue-proof.mjs';
import { digest, canonical } from '../../scripts/ci/connect-staging-closed.mjs';

function scenario() {
  const candidate={sha:'a'.repeat(40),tree:'b'.repeat(40)};
  const source={candidate,migration:'BEGIN;\nSELECT 1;\nCOMMIT;\n',capacity:'-- table TEST vide',admission:'-- admission fermée'};
  const hashes={migrationSha256:digest(source.migration),capacitySha256:digest(source.capacity),admissionSha256:digest(source.admission)};
  Object.assign(source,hashes,{manifestSha256:digest(JSON.stringify(canonical({candidate,...hashes})))});
  const reference={schemaVersion:1,sources:{candidate,...hashes,manifestSha256:source.manifestSha256},deltaMd5:'d'.repeat(32),
    counts:{routines:34,relations:3,triggers:2,inventory:19,views:0,policies:0,columns:75,constraints:58,indexes:11}};
  const before={catalogue:'1'.repeat(32),registry:'2'.repeat(32),rows:'3'.repeat(32),all_rows:'4'.repeat(32),
    versions:['20261001194201'],quiescent:true,gate_closed:true,capacity_closed:true};
  const proof={schemaVersion:1,before:{catalogue:before.catalogue,registry:before.registry},
    after:{catalogue:'5'.repeat(32),registry:'6'.repeat(32)},deltaVerified:true,businessRowsUnchanged:true,closedStateVerified:true};
  const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'pull_request',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',
    STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'SENTINELLE_TEST',
    CANDIDATE_SHA:candidate.sha,BASE_SHA:'c'.repeat(40)};
  const calls=[];
  const responses=[[before],[{proof}], [structuredClone(before)]];
  const fetcher=async(url,options)=>{
    assert.equal(url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
    assert.equal(options.redirect,'error');
    calls.push(JSON.parse(options.body));
    const item=responses.shift();if(item instanceof Error)throw item;
    return {ok:true,text:async()=>JSON.stringify(item)};
  };
  return {source,reference,before,proof,env,calls,responses,fetcher,
    execute:()=>proveCatalogue({env,source,reference,versions:before.versions,fetcher})};
}

test('ne produit les pins qu’après delta exact et nouvelle lecture indépendante',async()=>{
  const s=scenario();const proof=await s.execute();
  assert.equal(proof.rollbackVerified,true);assert.equal(proof.protocolEnabled,false);assert.equal(proof.capabilityEnabled,false);
  assert.equal(s.calls.length,3);
  assert.deepEqual(s.calls.map(x=>x.read_only),[true,false,true]);
  assert.equal(s.calls[0].query,s.calls[2].query);
  assert.match(s.calls[1].query,/CONNECT_CATALOGUE_OUTSIDE_DELTA_CHANGED/);
  assert.match(s.calls[1].query,/CONNECT_CATALOGUE_REFERENCE_MISMATCH/);
  assert.match(s.calls[1].query,/CONNECT_CATALOGUE_DATA_OR_CLOSED_STATE_CHANGED/);
  assert.ok(s.calls[1].query.trimEnd().endsWith('ROLLBACK;'));
  assert.doesNotMatch(JSON.stringify(proof),/SENTINELLE/);
});

for(const [name,change] of [
  ['autre projet',s=>s.env.STAGING_SUPABASE_PROJECT_REF='autre'],
  ['production',s=>s.env.GITHUB_EVENT_NAME='push'],
  ['autre candidat',s=>s.env.CANDIDATE_SHA='e'.repeat(40)],
  ['source modifiée après empreinte',s=>s.source.capacity+='\nSELECT 2;'],
  ['manifeste altéré des deux côtés',s=>{s.source.manifestSha256='e'.repeat(64);s.reference.sources.manifestSha256=s.source.manifestSha256;}],
  ['référence d’une autre source',s=>s.reference.sources.admissionSha256='e'.repeat(64)],
  ['objet manquant dans le témoin',s=>s.reference.counts.routines=33],
  ['témoin avec politique inattendue',s=>s.reference.counts.policies=1],
  ['registre contient déjà la migration',s=>s.before.versions.push('20261001201055')],
]) test(`refus avant réseau : ${name}`,async()=>{
  const s=scenario();change(s);await assert.rejects(s.execute(),/CONNECT_CATALOGUE_/);assert.equal(s.calls.length,0);
});

for(const key of ['catalogue','registry','rows','all_rows']) test(`retour annulé divergent : ${key}`,async()=>{
  const s=scenario();s.responses[2][0][key]='e'.repeat(32);
  await assert.rejects(s.execute(),/ROLLBACK_NOT_RESTORED/);assert.equal(s.calls.length,3);
});

test('relit après erreur SQL/transport sans rejouer la transaction',async()=>{
  const s=scenario();s.responses[1]=new Error('transport');
  await assert.rejects(s.execute(),/QUERY_OR_TRANSPORT_REFUSED/);
  assert.equal(s.calls.length,3);assert.equal(s.calls.filter(x=>x.read_only===false).length,1);
});

for(const key of ['deltaVerified','businessRowsUnchanged','closedStateVerified']) test(`preuve fausse bloquante : ${key}`,async()=>{
  const s=scenario();s.proof[key]=false;
  await assert.rejects(s.execute(),/PROOF_REFUSED/);assert.equal(s.calls.length,3);
});

test('forme inconnue de réponse reste fermée même si le rollback est acquis',async()=>{
  const s=scenario();s.responses[1]=[];
  await assert.rejects(s.execute(),/PROOF_SHAPE/);assert.equal(s.calls.length,3);
});

test('ne publie aucun champ ajouté par le transport',async()=>{
  const s=scenario();s.proof.private='SENTINELLE';s.proof.after.sql='SENTINELLE';
  const proof=await s.execute();assert.doesNotMatch(JSON.stringify(proof),/SENTINELLE/);
  assert.deepEqual(Object.keys(proof.after).sort(),['catalogue','registry']);
});

test('le générateur refuse des transactions supplémentaires',()=>{
  const s=scenario();s.source.admission='COMMIT;';s.source.admissionSha256=digest(s.source.admission);
  s.reference.sources.admissionSha256=s.source.admissionSha256;
  s.source.manifestSha256=digest(JSON.stringify(canonical({candidate:s.source.candidate,
    migrationSha256:s.source.migrationSha256,capacitySha256:s.source.capacitySha256,admissionSha256:s.source.admissionSha256})));
  s.reference.sources.manifestSha256=s.source.manifestSha256;
  assert.throws(()=>rollbackSql(s.source,s.reference,s.before),/TRANSACTION_REQUIRED/);
});

test('contrat de livraison reste fermé et aucune branche de preuve ne le modifie',()=>{
  const c=JSON.parse(readFileSync('scripts/ci/connect-staging-closed.contract.json','utf8'));
  assert.equal(c.ready,false);assert.equal(c.candidate,null);assert.equal(c.expectedBefore,null);assert.equal(c.expectedAfter,null);
  checkReference(scenario().reference,scenario().source);
});
