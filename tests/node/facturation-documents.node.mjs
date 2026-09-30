import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerBanc, genererDocuments, verifierXml } from '../helpers/facturation-documents-harness.mjs';

test('vrai handler : facture hebdomadaire et avoir, PDF lisibles, XML cohérents et empreintes des octets uploadés', async () => {
  const banc = await genererDocuments();
  assert.equal(banc.factures[0].montant_ttc, 80);
  assert.equal(banc.factures[1].montant_ttc, 20);
  assert.equal(banc.appels.filter(a => a.path === '/functions/v1/send-email').length, 4);
  assert(!banc.logs.some(l => l.level === 'error'));
  // Capturés avant le correctif PDF sur la source byte-identique LIVE v676 :
  // la mise en page ne doit modifier aucun octet du XML facture/avoir.
  assert.deepEqual(banc.versions.map(v => v.xml_sha256), [
    'd269ab611ebcb7b9c3f492018175de040996a0c9fe62d9b60732a0ee9f1f0d6b',
    'cec8402d2b823de1b1f3e7e87f4da5f55770672f35d148ce3af2c591a3d58b4c',
  ]);
});

test('identité composée et description longue : facture et avoir conservent une seconde page', async () => {
  await genererDocuments({ pagination: true });
});

test('échec Storage XML : aucun succès, émission ni registre documentaire', async () => {
  const banc = creerBanc({ panneXml: true }), response = await banc.genererFacture();
  assert.equal(response.status, 500); assert.deepEqual(banc.inconnus, []);
  assert.equal(banc.factures[0].statut, 'ERREUR_GENERATION');
  assert.equal(banc.versions.length, 0);
  assert(!banc.appels.some(a => /fn_emettre_document|send-email/.test(a.path)));
});

test('l’analyse refuse les identités, références, devise, type ou espaces de noms divergents et un XML mal formé', async () => {
  const banc = await genererDocuments(), f = banc.factures[0], xml = banc.documents.get(f.facturx_xml_url).bytes;
  for (const [avant, apres] of [[f.numero_facture, 'FAUX'], ['<ram:Name>Élodie', '<ram:Name>Autre'], ['&amp; Santé', '&amp; Autre'],
    ['<ram:InvoiceCurrencyCode>EUR', '<ram:InvoiceCurrencyCode>USD'], ['<ram:TypeCode>380', '<ram:TypeCode>381'],
    ['ReusableAggregateBusinessInformationEntity:100', 'ReusableAggregateBusinessInformationEntity:999']]) {
    assert(xml.toString().includes(avant));
    assert.throws(() => verifierXml(Buffer.from(xml.toString().replace(avant, apres)), f));
  }
  const avoir = banc.factures[1], avoirXml = banc.documents.get(avoir.facturx_xml_url).bytes;
  assert.throws(() => verifierXml(Buffer.from(avoirXml.toString().replace(f.numero_facture, 'AUTRE-FACTURE')), avoir, f));
  assert.throws(() => verifierXml(Buffer.from('<broken>'), f));
});
