import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerBanc, ids } from '../helpers/facturation-documents-harness.mjs';
// Le vrai générateur s'exécute ; seules les frontières réseau/SQL/Storage sont
// simulées. La nouvelle file/son acquittement sont exercés dans le banc PG17.
for (const strategie of ['FINALE_UNIQUE','HEBDO_ET_FINALE']) {
 const demande = strategie === 'FINALE_UNIQUE' ? {mission_id:ids.mission} : {
  mission_id:ids.mission,periode_debut:'2026-09-28',periode_fin:'2026-10-04',est_facture_finale_mission:true,
 };
 test(`${strategie} : finale canonique, PDF/XML, version et FC ; reprise sans second numéro/version`,async()=>{
 const b=creerBanc();Object.assign(b.mission,{statut:'TERMINEE',strategie_facturation:strategie});
 let r=await b.invoquer(demande);assert.equal(r.status,200);
 const body=await r.json();assert.equal(body.success,true);assert.equal(body.facture_commission_id,ids.commission);
 assert.equal(b.factures.length,1);assert.equal(b.versions.length,1);assert.equal(b.documents.size,2);
 assert.equal(b.factures[0].template_version,'v2_facturx');assert.equal(b.factures[0].nature_correction,'ORIGINALE');
 assert.equal(b.factures[0].est_facture_finale_mission,true);assert(b.factures[0].regime_tva_snapshot);
 assert.equal(b.factures[0].quantite_heures_snapshot,strategie==='HEBDO_ET_FINALE'?4:8);
 assert.equal(b.factures[0].taux_horaire_snapshot,20);
 assert(b.factures[0].pdf_s3_key);assert(b.factures[0].facturx_xml_url);
 if(strategie==='HEBDO_ET_FINALE'){
  assert.equal(b.factures[0].periode_debut,demande.periode_debut);assert.equal(b.factures[0].periode_fin,demande.periode_fin);
  assert.equal(b.factures[0].montant_ht,80);assert.notEqual(b.factures[0].montant_ht,b.mission.net_a_payer);
  assert.deepEqual(b.appels.find(x=>x.path==='/rest/v1/rpc/fn_calculer_montant_periode' && x.body.p_periode_debut).body,{
   p_mission_id:ids.mission,p_periode_debut:demande.periode_debut,p_periode_fin:demande.periode_fin,
  });
 }else{
  assert.equal(b.factures[0].montant_ht,b.mission.net_a_payer);
 }
 const before={numero:b.factures[0].numero_facture,versions:b.versions.length,documents:b.documents.size};
 r=await b.invoquer(demande);assert.equal(r.status,409);assert.equal((await r.json()).facture_id,b.factures[0].id);
 assert.deepEqual({numero:b.factures[0].numero_facture,versions:b.versions.length,documents:b.documents.size},before);
 assert.equal(b.appels.filter(x=>x.path==='/functions/v1/send-email').length,0);
 assert.equal(b.appels.filter(x=>x.path==='/rest/v1/rpc/fn_preparer_facture_commission_periode').length,2);
 assert.deepEqual(b.inconnus,[]);
});
test(`${strategie} : erreur Storage gérée, reprise sur même réservation et émission unique`,async()=>{
 const b=creerBanc({panneXml:true});Object.assign(b.mission,{statut:'TERMINEE',strategie_facturation:strategie});
 let r=await b.invoquer(demande);assert.equal(r.status,500);assert.equal(b.factures.length,1);assert.equal(b.versions.length,0);
 const numero=b.factures[0].numero_facture;b.pannes.xml=false;
 r=await b.invoquer(demande);assert.equal(r.status,200);assert.equal(b.factures.length,1);
 assert.equal(b.factures[0].numero_facture,numero);assert.equal(b.versions.length,1);assert.deepEqual(b.inconnus,[]);
});
}
