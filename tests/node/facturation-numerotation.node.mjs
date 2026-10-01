import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerBanc, verifierXml, ids } from '../helpers/facturation-documents-harness.mjs';

// Vrai handler et vrais octets, IO RPC/Storage fictives. La réservation SQL et
// les courses PostgreSQL ont leur banc distinct, jamais déduites de ce double.
const numero = 'JOL-11111111111141118111111111111111-2026-00001';
const reserve = '/rest/v1/rpc/fn_reserver_facture_honoraires';

test('nouvelle série entière : numéro exact dans XML et une seule réservation avant Storage', async () => {
  const b = creerBanc({ numeroFacture: numero });
  const r = await b.genererFacture(), body = await r.json();
  assert.equal(r.status, 200, JSON.stringify(body));
  assert.equal(body.numero_facture, numero); assert(!Object.hasOwn(body, 'token'));
  assert.deepEqual(b.inconnus, []); assert.equal(b.factures.length, 1);
  assert.equal(b.versions.length, 1); assert.equal(b.emissions.length, 1);
  assert.equal(b.appels.filter(a => a.path === reserve).length, 1);
  assert(b.appels.findIndex(a => a.path === reserve) < b.appels.findIndex(a => a.path.startsWith('/storage/')));
  assert(!b.appels.some(a => a.path.endsWith('/next_invoice_number') || (a.path === '/rest/v1/factures_honoraires' && a.method === 'POST')));
  verifierXml(b.documents.get(b.factures[0].facturx_xml_url).bytes, b.factures[0]);
});

test('upload XML interrompu : reprise du même id et numéro avec snapshots conservés', async () => {
  const b = creerBanc({ numeroFacture: numero, panneXml: true });
  assert.equal((await b.genererFacture()).status, 500);
  const f = b.factures[0], id = f.id, snapshot = f.emetteur_identite_snapshot;
  assert.equal(f.statut, 'ERREUR_GENERATION'); assert.equal(b.versions.length, 0); assert.equal(b.emissions.length, 0);
  const partiel = [...b.documents.keys()]; assert.equal(partiel.length, 1);
  b.pannes.xml = false; b.soignant.prenom = 'Prénom actuel différent'; b.mission.taux_horaire_base = 999;
  const r = await b.invoquer({ facture_id: id }), body = await r.json();
  assert.equal(r.status, 200, JSON.stringify(body)); assert.equal(body.facture_id, id);
  assert.equal(f.numero_facture, numero); assert.equal(f.emetteur_identite_snapshot, snapshot);
  assert.equal(f.montant_ht, 80); assert.equal(f.taux_horaire_snapshot, 20);
  assert.equal(b.factures.length, 1); assert.equal(b.versions.length, 1); assert.deepEqual(b.emissions, [id]);
  assert.equal(b.appels.filter(a => a.path === reserve).length, 1);
  assert(b.documents.has(partiel[0]), 'aucune suppression arbitraire de l’objet partiel');
  assert.notEqual(f.pdf_s3_key, partiel[0]);
  verifierXml(b.documents.get(f.facturx_xml_url).bytes, f);
  assert.deepEqual(b.inconnus, []);
});

test('deux demandes : une réponse occupée, aucun second rendu ni jeton livré', async () => {
  const b = creerBanc({ numeroFacture: numero });
  const responses = await Promise.all([b.genererFacture(), b.genererFacture()]);
  const bodies = await Promise.all(responses.map(r => r.json()));
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 409], JSON.stringify(bodies));
  assert(bodies.every(body => !Object.hasOwn(body, 'token')));
  assert.equal(b.factures.length, 1); assert.equal(b.versions.length, 1); assert.equal(b.documents.size, 2);
  assert.equal(b.emissions.length, 1); assert.deepEqual(b.inconnus, []);
});

test('réponse perdue après émission : pas de rétrogradation ni de seconde émission à la reprise', async () => {
  const b = creerBanc({ numeroFacture: numero }); b.pannes.perdreReponseFinale = true;
  const r = await b.genererFacture(); assert.equal(r.status, 500);
  const f = b.factures[0], paths = [f.pdf_s3_key, f.facturx_xml_url];
  assert.equal(f.statut, 'EMISE'); assert.equal(b.emissions.length, 1); assert.equal(b.versions.length, 1);
  const retry = await b.genererFacture(), body = await retry.json();
  assert.equal(retry.status, 409); assert.equal(body.facture_id, f.id);
  assert.deepEqual([f.pdf_s3_key, f.facturx_xml_url], paths);
  assert.equal(b.emissions.length, 1); assert.equal(b.versions.length, 1); assert.equal(b.documents.size, 2);
  assert.deepEqual(b.inconnus, []);
});


test('premier rendu : les snapshots persistés gouvernent les octets, même après retour différent de la réservation', async () => {
  const vendeur = "Łukasz L'Été & İpek";
  const b = creerBanc({ numeroFacture: numero, apresReservation(f) {
    f.emetteur_identite_snapshot = vendeur;
    f.montant_ht = 72; f.montant_ttc = 72; f.taux_horaire_snapshot = 18;
  } });
  const r = await b.genererFacture(), body = await r.json();
  assert.equal(r.status, 200, JSON.stringify(body));
  const f = b.factures[0];
  verifierXml(b.documents.get(f.facturx_xml_url).bytes, f, undefined, vendeur);
  assert.equal(f.montant_ttc, 72); assert.equal(b.versions.length, 1);
  assert.deepEqual(b.inconnus, []);
});

test('réservation découvrant une émission concurrente : commission réparée sans second rendu', async () => {
  const b = creerBanc({ numeroFacture: numero, reservationConcurrenteEmise: true });
  const r = await b.genererFacture(), body = await r.json();
  assert.equal(r.status, 409, JSON.stringify(body)); assert.equal(body.facture_id, b.factures[0].id);
  assert.equal(b.appels.filter(a => a.path.endsWith('/fn_preparer_facture_commission_periode')).length, 1);
  assert.equal(b.documents.size, 0); assert.equal(b.versions.length, 0); assert.equal(b.emissions.length, 0);
  assert(!Object.hasOwn(body, 'token')); assert.deepEqual(b.inconnus, []);
});

for (const mode of ['lecture_initiale', 'reservation_concurrente']) {
  for (const statut of ['EMISE', 'PAYEE']) test(`remplacement ${statut}, ${mode} : seul helper rectificatif, aucune seconde émission`, async () => {
    const b = mode === 'reservation_concurrente'
      ? creerBanc({ reservationConcurrenteEmise: statut, apresReservation(f) {
        f.id = ids.remplacement; f.nature_correction = 'REMPLACEMENT'; f.facture_precedente_id = ids.facture;
      } }) : creerBanc();
    if (mode === 'lecture_initiale') {
      assert.equal((await b.genererFacture()).status, 200);
      b.preparerRemplacement().statut = statut;
    }
    const avant = { appels: b.appels.length, documents: b.documents.size, versions: b.versions.length, emissions: b.emissions.length };
    const response = await b.genererFacture(), body = await response.json();
    assert.equal(response.status, 409, JSON.stringify(body)); assert.equal(body.facture_id, ids.remplacement);
    const appels = b.appels.slice(avant.appels);
    const commissions = appels.filter(a => a.path.includes('/fn_preparer_'));
    assert.deepEqual(commissions.map(a => a.path), ['/rest/v1/rpc/fn_preparer_commission_remplacement_honoraires']);
    assert.equal(commissions[0].body.p_facture_honoraire_id, ids.remplacement);
    assert.equal(b.documents.size, avant.documents); assert.equal(b.versions.length, avant.versions); assert.equal(b.emissions.length, avant.emissions);
    assert(!appels.some(a => a.path.startsWith('/storage/') || a.path.endsWith('/send-email')));
    assert.deepEqual(b.inconnus, []);
  });
}
