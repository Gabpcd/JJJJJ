import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerBanc, genererDocuments, verifierXml, sha256 }  from '../helpers/facturation-documents-harness.mjs';

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

test('Unicode exact : Łukasz, İpek, accents, grec et cyrillique dans facture et avoir paginés', async () => {
  const banc = await genererDocuments({ unicode: true, pagination: true });
  assert.equal(banc.factures[0].emetteur_identite_snapshot, "Łukasz İpek D'Été de la Vallée de Saint-Martin");
  assert.equal(banc.factures[0].destinataire_nom_snapshot, 'Clinique fictive Жанна & Santé');
  assert(!banc.logs.some(l => l.level === 'error'));
});

function sansEffet(banc, depuis = 0) {
  assert.deepEqual(banc.inconnus, []);
  const effets = banc.appels.slice(depuis).filter(a => a.method !== 'GET'
    && !['/rest/v1/rpc/fn_verifier_pre_facturation','/rest/v1/rpc/fn_calculer_montant_periode'].includes(a.path));
  assert.deepEqual(effets, [], 'aucun numéro, insert/update, Storage, émission, commission ni email');
}

test('caractère absent : refus explicite avant numéro ou écriture, sans altérer identité ou adresse', async () => {
  for (const cible of ['soignant', 'etablissement', 'adresse']) {
    const banc = creerBanc();
    if (cible === 'soignant') banc.soignant.prenom = '李';
    else if (cible === 'etablissement') banc.etablissement.nom = 'Clinique 李';
    else banc.soignant.adresse_rue = '1 rue 😀';
    const response = await banc.genererFacture(), body = await response.json();
    assert.equal(response.status, 422); assert.equal(body.code, 'CARACTERE_PDF_NON_PRIS_EN_CHARGE');
    assert.equal(body.error, body.code); assert.match(body.details.codepoint, /^U\+(674E|1F600)$/);
    assert.equal(body.message, 'La facture ne peut pas être générée : un caractère du document n’est pas encore pris en charge. Contactez l’assistance sans modifier l’identité.');
    sansEffet(banc);
    assert.equal(banc.documents.size, 0); assert.equal(banc.factures.length, 0); assert.equal(banc.versions.length, 0);
  }
});

test('police normale ou grasse absente/corrompue : échec fermé avant tout effet', async () => {
  for (const pannePolice of ['normale-absente', 'normale-corrompue', 'gras-absente', 'gras-corrompue']) {
    const banc = creerBanc({ pannePolice }), response = await banc.genererFacture();
    assert.equal(response.status, 500); assert.deepEqual(await response.json(), { error: 'POLICE_PDF_INVALIDE', code: 'POLICE_PDF_INVALIDE',
      message: 'Le PDF de la facture ne peut pas être généré pour le moment. Contactez l’assistance.' });
    sansEffet(banc); assert.equal(banc.documents.size, 0); assert.equal(banc.factures.length, 0);
  }
});

test('regen : snapshots canoniques conservés, puis caractère absent refusé sans remplacement de fichier', async () => {
  const banc = await genererDocuments({ unicode: true });
  banc.soignant.prenom = '李'; banc.etablissement.nom = 'Autre 李';
  let response = await banc.invoquer({ facture_id: banc.factures[0].id });
  assert.equal(response.status, 200);
  verifierXml(banc.documents.get(banc.factures[0].facturx_xml_url).bytes, banc.factures[0], undefined,
    "Łukasz İpek D'Été", 'Clinique fictive Жанна & Santé');
  for (const champ of ['emetteur_identite_snapshot', 'destinataire_nom_snapshot', 'description_prestation_snapshot']) {
    const f = banc.factures[1], ancien = f[champ], depuis = banc.appels.length, versions = banc.versions.length, documents = banc.documents.size;
    f[champ] = '李'; response = await banc.invoquer({ facture_id: f.id });
    assert.equal(response.status, 422); assert.equal((await response.json()).code, 'CARACTERE_PDF_NON_PRIS_EN_CHARGE');
    sansEffet(banc, depuis); assert.equal(banc.versions.length, versions); assert.equal(banc.documents.size, documents);
    f[champ] = ancien;
  }
});

test('doublon : le nouveau contrôle ne bloque pas la réparation idempotente de commission existante', async () => {
  const banc = await genererDocuments(), depuis = banc.appels.length;
  banc.soignant.prenom = '李';
  const response = await banc.genererFacture();
  assert.equal(response.status, 409); assert.equal((await response.json()).facture_id, banc.factures[0].id);
  assert.deepEqual(banc.appels.slice(depuis).filter(a => a.method !== 'GET').map(a => a.path),
    ['/rest/v1/rpc/fn_calculer_montant_periode', '/rest/v1/rpc/fn_verifier_pre_facturation', '/rest/v1/rpc/fn_preparer_facture_commission_periode']);
  assert.equal(banc.documents.size, 4); assert.equal(banc.versions.length, 2); assert.deepEqual(banc.inconnus, []);
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


test('remplacement réel : XML380, filiation numéro/date, 4h × 18 = 72 et octets originaux inchangés', async () => {
  const banc = creerBanc({ unicode: true });
  assert.equal((await banc.genererFacture()).status, 200);
  const original = banc.factures[0];
  const avant = { pdf: Buffer.from(banc.documents.get(original.pdf_s3_key).bytes),
    xml: Buffer.from(banc.documents.get(original.facturx_xml_url).bytes), version: structuredClone(banc.versions[0]),
    pdfKey: original.pdf_s3_key, xmlKey: original.facturx_xml_url };
  const remplacement = banc.preparerRemplacement();
  const response = await banc.invoquer({ facture_id: remplacement.id });
  assert.equal(response.status, 200, JSON.stringify(await response.json()));
  assert.deepEqual(banc.inconnus, []); assert(!banc.logs.some(l => l.level === 'error'));
  const pdf = banc.documents.get(remplacement.pdf_s3_key), xml = banc.documents.get(remplacement.facturx_xml_url);
  assert.equal(pdf.contentType, 'application/pdf'); assert.equal(pdf.bytes.subarray(0, 5).toString(), '%PDF-');
  assert.equal(xml.contentType, 'application/xml');
  const resultat = verifierXml(xml.bytes, remplacement, original, "Łukasz İpek D'Été", 'Clinique fictive Жанна & Santé');
  assert.equal(resultat.type, '380'); assert.equal(resultat.ht, 72); assert.equal(resultat.ttc, 72);
  assert.equal(remplacement.taux_horaire_snapshot, 18); assert.equal(remplacement.quantite_heures_snapshot, 4);
  assert.equal(original.montant_ht, 80); assert.equal(original.statut, 'REMPLACEE');
  assert.equal(remplacement.statut, 'EMISE');
  assert.equal(banc.documents.size, 4); assert.equal(banc.versions.length, 2);
  assert.equal(banc.versions[1].pdf_sha256, sha256(pdf.bytes));
  assert.equal(banc.versions[1].xml_sha256, sha256(xml.bytes));
  assert.deepEqual(banc.versions[0], avant.version);
  assert.equal(original.pdf_s3_key, avant.pdfKey); assert.equal(original.facturx_xml_url, avant.xmlKey);
  assert.deepEqual(banc.documents.get(avant.pdfKey).bytes, avant.pdf);
  assert.deepEqual(banc.documents.get(avant.xmlKey).bytes, avant.xml);
  assert.notEqual(remplacement.pdf_s3_key, avant.pdfKey); assert.notEqual(remplacement.facturx_xml_url, avant.xmlKey);
  for (const [before, after] of [
    ['<ram:TypeCode>380', '<ram:TypeCode>381'],
    [original.numero_facture, 'AUTRE-REFERENCE'],
    ['<qdt:DateTimeString format="102">20260930', '<qdt:DateTimeString format="102">20260929'],
    ['<ram:ChargeAmount>18.00', '<ram:ChargeAmount>20.00'],
  ]) {
    assert(xml.bytes.toString().includes(before));
    assert.throws(() => verifierXml(Buffer.from(xml.bytes.toString().replace(before, after)), remplacement, original,
      "Łukasz İpek D'Été", 'Clinique fictive Жанна & Santé'));
  }
});

test('remplacement : filiation invalide refusée avant upload, émission, registre, commission ou email', async () => {
  const cas = [
    ['remplacement', 'facture_precedente_id', null], ['remplacement', 'facture_precedente_id', 'self'],
    ['remplacement', 'type_document', 'AVOIR'], ['original', 'type_document', 'AVOIR'],
    ['original', 'mission_id', 'f1300009-9000-4000-8000-000000000009'],
    ['original', 'soignant_id', 'f1300009-9000-4000-8000-000000000009'],
    ['original', 'etablissement_id', 'f1300009-9000-4000-8000-000000000009'],
    ['original', 'numero_facture', null], ['original', 'numero_facture', '   '],
    ['original', 'date_emission', null], ['original', 'date_emission', '2026-02-30'],
    ['original', 'date_emission', '30/09/2026'],
  ];
  for (const [cible, champ, valeur] of cas) {
    // A fresh request cohort per case preserves the real rate-limit guard.
    const banc = creerBanc(); assert.equal((await banc.genererFacture()).status, 200);
    const original = banc.factures[0], remplacement = banc.preparerRemplacement();
    const objet = cible === 'original' ? original : remplacement;
    const depuis = banc.appels.length; objet[champ] = valeur === 'self' ? remplacement.id : valeur;
    const response = await banc.invoquer({ facture_id: remplacement.id });
    assert.equal(response.status, 400, champ);
    assert.deepEqual(await response.json(), { error: 'FILIATION_REMPLACEMENT_INVALIDE' });
    sansEffet(banc, depuis); assert.equal(banc.documents.size, 2); assert.equal(banc.versions.length, 1);
    assert.equal(remplacement.statut, 'BROUILLON');
  }
});

test('remplacement : parent absent ou lecture en erreur refuse sans effet documentaire', async () => {
  for (const pannePrecedente of ['absente', 'erreur']) {
    const banc = creerBanc({ pannePrecedente }); assert.equal((await banc.genererFacture()).status, 200);
    const f = banc.preparerRemplacement(), depuis = banc.appels.length;
    const response = await banc.invoquer({ facture_id: f.id });
    assert.equal(response.status, 400); assert.deepEqual(await response.json(), { error: 'FILIATION_REMPLACEMENT_INVALIDE' });
    sansEffet(banc, depuis); assert.equal(banc.documents.size, 2); assert.equal(banc.versions.length, 1);
  }
});


test('une facture ordinaire liée à une période précédente reste380 sans mention de remplacement', async () => {
  const banc = creerBanc(); assert.equal((await banc.genererFacture()).status, 200);
  const f = banc.preparerRemplacement(); f.nature_correction = 'ORIGINALE';
  f.description_prestation_snapshot = banc.factures[0].description_prestation_snapshot;
  const response = await banc.invoquer({ facture_id: f.id });
  assert.equal(response.status, 200);
  const xml = banc.documents.get(f.facturx_xml_url).bytes;
  const resultat = verifierXml(xml, f);
  assert.equal(resultat.type, '380'); assert.deepEqual(banc.inconnus, []);
});


test('fixture frontend de remplacement : vrais PDF paginés Unicode et XML380 au taux18', async () => {
  const banc = await genererDocuments({ remplacement: true, unicode: true, pagination: true });
  assert.equal(banc.factures[1].nature_correction, 'REMPLACEMENT');
  assert.equal(banc.factures[1].montant_ttc, 72); assert.equal(banc.factures[1].taux_horaire_snapshot, 18);
  assert.equal(banc.factures[0].statut, 'REMPLACEE');
});

test('bornes effectives : la dernière vacation après minuit peut être facturée', async () => {
  const banc=creerBanc({bornesFacturation:{borne_debut_facturation:'2026-09-21',borne_fin_facturation:'2026-09-28'}});
  banc.mission.fin_le='2026-09-27T23:45:00Z';banc.mission.statut='TERMINEE';
  const response=await banc.invoquer({mission_id:banc.mission.id,periode_debut:'2026-09-21',periode_fin:'2026-09-28',est_facture_finale_mission:true});
  assert.equal(response.status,200,JSON.stringify(await response.json()));
  assert.equal(banc.factures[0].periode_fin,'2026-09-28');
  assert.deepEqual(banc.inconnus,[]);
});
test('historique incohérent : refus409 explicite avant toute réservation ou émission', async () => {
  const banc=creerBanc({erreurHistorique:true});
  const response=await banc.genererFacture();
  assert.equal(response.status,409);
  const body=await response.json();
  assert.equal(body.error,'FACTURATION_HISTORIQUE_A_RECONCILIER');
  assert.match(body.message,/factures précédentes doivent être régularisées/);
  sansEffet(banc);
});
