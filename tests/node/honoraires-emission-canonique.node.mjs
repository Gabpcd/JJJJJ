import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerBanc, ids } from '../helpers/facturation-documents-harness.mjs';
// Le vrai générateur s'exécute ; seules les frontières réseau/SQL/Storage sont
// simulées. La nouvelle file/son acquittement sont exercés dans le banc PG17.
test('première finale unique canonique : snapshots, PDF/XML, version et FC ; reprise sans second numéro/version',async()=>{
 const b=creerBanc();Object.assign(b.mission,{statut:'TERMINEE',strategie_facturation:'FINALE_UNIQUE'});
 let r=await b.invoquer({mission_id:ids.mission});assert.equal(r.status,200);
 const body=await r.json();assert.equal(body.success,true);assert.equal(body.facture_commission_id,ids.commission);
 assert.equal(b.factures.length,1);assert.equal(b.versions.length,1);assert.equal(b.documents.size,2);
 assert.equal(b.factures[0].template_version,'v2_facturx');assert.equal(b.factures[0].nature_correction,'ORIGINALE');
 assert.equal(b.factures[0].est_facture_finale_mission,true);assert(b.factures[0].regime_tva_snapshot);
 assert(b.factures[0].pdf_s3_key);assert(b.factures[0].facturx_xml_url);
 const before={numero:b.factures[0].numero_facture,versions:b.versions.length,documents:b.documents.size};
 r=await b.invoquer({mission_id:ids.mission});assert.equal(r.status,409);assert.equal((await r.json()).facture_id,b.factures[0].id);
 assert.deepEqual({numero:b.factures[0].numero_facture,versions:b.versions.length,documents:b.documents.size},before);
 assert.equal(b.appels.filter(x=>x.path==='/functions/v1/send-email').length,0);
 assert.equal(b.appels.filter(x=>x.path==='/rest/v1/rpc/fn_preparer_facture_commission_periode').length,2);
 assert.deepEqual(b.inconnus,[]);
});
test('Storage initial incomplet : reprise finale sur même réservation et émission unique',async()=>{
 const b=creerBanc({panneXml:true});Object.assign(b.mission,{statut:'TERMINEE',strategie_facturation:'FINALE_UNIQUE'});
 let r=await b.invoquer({mission_id:ids.mission});assert.equal(r.status,500);assert.equal(b.factures.length,1);assert.equal(b.versions.length,0);
 const numero=b.factures[0].numero_facture;b.pannes.xml=false;
 r=await b.invoquer({mission_id:ids.mission});assert.equal(r.status,200);assert.equal(b.factures.length,1);
 assert.equal(b.factures[0].numero_facture,numero);assert.equal(b.versions.length,1);assert.deepEqual(b.inconnus,[]);
});
