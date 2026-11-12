// Gardes et numérotation de la livraison TestFlight de l'app Swift
// (scripts/mobile/ios-native-testflight.mjs, docs/mobile-swift/TESTFLIGHT.md).
// Tourne sur Linux : aucune dépendance à plutil, codesign ni security.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, generateKeyPairSync, verify } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  APP, GuardFailure, MARGE_BUILD, ascClient, ascToken, buildFloor, compareVersions, entitlementsGaps, evaluateBuildSettings, evaluateBundle, isVersion,
  evaluateProcessing, evaluateProfile, evaluateSignature, evaluateSources, listBuilds, loadSources, parsePlist,
  parseXcconfig, pngInfo, requiredEntitlements, resolveBuildNumber,
} from '../../scripts/mobile/ios-native-testflight.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const sources = () => structuredClone(loadSources(root));

// Certificat auto-signé jetable (CN de l'identité de distribution, clé détruite) : fixture de test.
const CERT = Buffer.from('MIICoDCCAgmgAwIBAgIUHQT2yINIfGPANxC+LABixlnl76UwDQYJKoZIhvcNAQELBQAwYjE0MDIGA1UEAwwrQXBwbGUgRGlzdHJpYnV0aW9uOiBKb2xlbmUgQXBwIChHRFU1QUEyOE05KTETMBEGA1UECwwKR0RVNUFBMjhNOTEVMBMGA1UECgwMVGVzdCBmaXh0dXJlMB4XDTI2MTEwOTA3NDIxMFoXDTM2MTEwNjA3NDIxMFowYjE0MDIGA1UEAwwrQXBwbGUgRGlzdHJpYnV0aW9uOiBKb2xlbmUgQXBwIChHRFU1QUEyOE05KTETMBEGA1UECwwKR0RVNUFBMjhNOTEVMBMGA1UECgwMVGVzdCBmaXh0dXJlMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCcvGthkrgQh9WCRTEfdqw7oR8YIYUrAk5r4Dlg76EQJGm4P44khj/vucQKaB0I9WXiEMz44tNQYfn6zA2iVZp04BY89y9w/3D4fE/9K1wgTGp7RoLh0kz7tH/YpRUuqtULcZ/NVJTInD6c0dxU9G42e6dlp+r0Y/oQqTHjxm8avQIDAQABo1MwUTAdBgNVHQ4EFgQU8kHEUCTRWkPMWF4wd/UZHz5IkE0wHwYDVR0jBBgwFoAU8kHEUCTRWkPMWF4wd/UZHz5IkE0wDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOBgQBgkeQ7EE+v/Jiwvcm3Ny19yyAqc4bsoDhibkKjm6f6EFrKiPtVeNGkUSk5xPF1A+63aG4dHhvvF2euxnQcRyHsaa0OzEx1GxjJD3Btpmy/FRgm4byMdSAdZP76XFMFnGtncXkROYIutWXAN8brVvTeVALYnzh/oaNoT6HGTGRxjQ==', 'base64');
const CERT_SHA1 = createHash('sha1').update(CERT).digest('hex').toUpperCase();

function refus(fn, garde, fragment) {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof GuardFailure, `GuardFailure attendue, reçu ${error}`);
    const lignes = error.failures.filter((line) => line.startsWith(`[${garde}]`));
    assert.ok(lignes.length, `garde ${garde} absente de : ${error.failures.join(' | ')}`);
    if (fragment) assert.ok(lignes.some((ligne) => fragment.test(ligne)), `${fragment} absent de : ${lignes.join(' | ')}`);
    for (const ligne of lignes) assert.match(ligne, /docs\/mobile-swift\/TESTFLIGHT\.md/);
    return true;
  });
}

const png = ({ size = 1024, colorType = 2, trns = false } = {}) => {
  const ihdr = Buffer.alloc(25);
  ihdr.writeUInt32BE(13, 0); ihdr.write('IHDR', 4); ihdr.writeUInt32BE(size, 8); ihdr.writeUInt32BE(size, 12); ihdr[16] = 8; ihdr[17] = colorType;
  const chunk = (type) => { const b = Buffer.alloc(12); b.write(type, 4); return b; };
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), ihdr, ...(trns ? [chunk('tRNS')] : []), chunk('IEND')]);
};

// --- Lecture --------------------------------------------------------------------------------

test('le lecteur de plist restitue types, imbrications et entités', () => {
  const value = parsePlist(`<?xml version="1.0"?><!-- c --><plist version="1.0"><dict>
    <key>a</key><string>x &amp; y</string><key>b</key><integer>24</integer><key>c</key><true/>
    <key>d</key><array><string>1</string><dict><key>e</key><false/></dict><array/></array>
    <key>f</key><date>2027-09-07T23:07:49Z</date><key>g</key><data>AQID</data><key>h</key><string/></dict></plist>`);
  assert.deepEqual({ ...value, f: value.f.toISOString(), g: [...value.g] },
    { a: 'x & y', b: 24, c: true, d: ['1', { e: false }, []], f: '2027-09-07T23:07:49.000Z', g: [1, 2, 3], h: '' });
  assert.throws(() => parsePlist('<plist><dict><key>a</key><array></dict></plist>'), /déséquilibrées/);
});

test('le lecteur de xcconfig ignore commentaires et include, et résout $()', () => {
  assert.deepEqual(parseXcconfig('#include "Base.xcconfig"\n// note\nURL = https:/$()/x.supabase.co // fin\nA[sdk=iphonesimulator*] = NO\n'),
    { URL: 'https://x.supabase.co', 'A[sdk=iphonesimulator*]': 'NO' });
});

test('l\'en-tête PNG donne dimensions et alpha', () => {
  assert.deepEqual(pngInfo(png()), { width: 1024, height: 1024, alpha: false });
  assert.equal(pngInfo(png({ colorType: 6 })).alpha, true);
  assert.equal(pngInfo(png({ colorType: 3, trns: true })).alpha, true);
});

// --- Garde du dépôt -------------------------------------------------------------------------

test('le dépôt actuel passe toutes les gardes statiques', () => {
  const files = loadSources(root);
  const { settings, entitlements } = evaluateSources(files);
  // Versions lues dans la source réelle : une 2.0.1 Swift ou une 1.1.0 Capacitor ne cassent pas ce test.
  const capacitor = JSON.parse(files.mobileRelease).marketingVersion;
  assert.ok(isVersion(settings.MARKETING_VERSION) && isVersion(capacitor));
  assert.ok(compareVersions(settings.MARKETING_VERSION, APP.minimumMarketingVersion) >= 0);
  assert.ok(compareVersions(settings.MARKETING_VERSION, capacitor) > 0);
  const requis = requiredEntitlements(entitlements, settings);
  assert.equal(requis['aps-environment'], 'production');
  assert.ok(requis['com.apple.developer.associated-domains'].includes('applinks:jolene.app'));
});

for (const [nom, garde, mutation, fragment] of [
  ['un autre bundle', 'identite', (f) => { f.baseXcconfig = f.baseXcconfig.replace(/^PRODUCT_BUNDLE_IDENTIFIER = .*$/m, 'PRODUCT_BUNDLE_IDENTIFIER = app.autre'); }, /PRODUCT_BUNDLE_IDENTIFIER/],
  ['une autre équipe', 'identite', (f) => { f.baseXcconfig = f.baseXcconfig.replace(/^DEVELOPMENT_TEAM = .*$/m, 'DEVELOPMENT_TEAM = FPQ78HDF4Y'); }, /DEVELOPMENT_TEAM/],
  ['la signature automatique', 'identite', (f) => { f.baseXcconfig = f.baseXcconfig.replace(/^CODE_SIGN_STYLE = .*$/m, 'CODE_SIGN_STYLE = Automatic'); }, /Manual/],
  ['une version Swift non supérieure à Capacitor', 'identite', (f) => {
    const swift = { ...parseXcconfig(f.baseXcconfig), ...parseXcconfig(f.productionXcconfig) }.MARKETING_VERSION;
    f.mobileRelease = JSON.stringify({ ...JSON.parse(f.mobileRelease), marketingVersion: swift });
  }, /dépasser la coquille Capacitor/],
  ['un push figé hors xcconfig', 'entitlements', (f) => { f.entitlements = f.entitlements.replace('<string>$(APS_ENVIRONMENT)</string>', '<string>development</string>'); }, /aps-environment/],
  ['des associated domains absents', 'entitlements', (f) => { f.entitlements = f.entitlements.replace(/<key>com\.apple\.developer\.associated-domains<\/key>\s*<array>[\s\S]*?<\/array>/, ''); }, /associated-domains absent/],
  ['le pistage', 'confidentialite', (f) => { f.privacyInfo = f.privacyInfo.replace(/(<key>NSPrivacyTracking<\/key>\s*)<false\/>/, '$1<true/>'); }, /NSPrivacyTracking/],
  ['une Release sans Production.xcconfig', 'environnement', (f) => { f.pbxproj = f.pbxproj.replace(/(baseConfigurationReference = \w+ \/\* )Production(\.xcconfig \*\/;)/, '$1Staging$2'); }, /Production\.xcconfig \(trouvé : Staging/],
  ['un scheme qui n\'archive pas en Release', 'environnement', (f) => { f.scheme = f.scheme.replace(/(<ArchiveAction\s+buildConfiguration = )"Release"/, '$1"Debug"'); }, /archiver en configuration Release/],
]) {
  test(`le dépôt refuse ${nom}`, () => {
    const files = sources();
    mutation(files);
    refus(() => evaluateSources(files), garde, fragment);
  });
}

test('le chiffrement non exempté non déclaré à false est refusé', () => {
  const files = sources();
  files.infoPlist = files.infoPlist.replace(/(<key>ITSAppUsesNonExemptEncryption<\/key>\s*)<false\/>/, '$1<true/>');
  refus(() => evaluateSources(files), 'chiffrement');
});

for (const [nom, mutation, fragment] of [
  ['une URL STAGING', (x) => x.replace('flripxtsyegjshnhzjkz', APP.stagingRef), /STAGING|URL Supabase/],
  ['le mode démo', (x) => x.replace('JOLENE_ENVIRONMENT = production', 'JOLENE_ENVIRONMENT = demo'), /démo/],
  ['le push de développement', (x) => x.replace('APS_ENVIRONMENT = production', 'APS_ENVIRONMENT = development'), /APS_ENVIRONMENT/],
  ['un include placé après les valeurs', (x) => `${x.replace('#include "Base.xcconfig"\n', '')}\n#include "Base.xcconfig"\n`, /commencer par #include/],
  ['une clé secrète', (x) => x.replace(/sb_publishable_\S+/, 'sb_secret_abc'), /publishable/],
]) {
  test(`la configuration Release refuse ${nom}`, () => {
    const files = sources();
    files.productionXcconfig = mutation(files.productionXcconfig);
    refus(() => evaluateSources(files), 'environnement', fragment);
  });
}

test('une valeur Info.plist figée au lieu du réglage xcconfig est refusée', () => {
  const files = sources();
  files.infoPlist = files.infoPlist.replace('<string>$(JOLENE_ENVIRONMENT)</string>', '<string>staging</string>');
  refus(() => evaluateSources(files), 'environnement', /JoleneEnvironment/);
});

test('une version marketing inférieure à 2.0.0 ou un relais de signature absent est refusé', () => {
  const files = sources();
  files.baseXcconfig = files.baseXcconfig.replace(/^MARKETING_VERSION = .*$/m, 'MARKETING_VERSION = 1.9.9');
  refus(() => evaluateSources(files), 'identite', /2\.0\.0 minimum/);
  const relay = sources();
  relay.productionXcconfig = relay.productionXcconfig.replace(/^PROVISIONING_PROFILE_SPECIFIER.*$/m, '');
  refus(() => evaluateSources(relay), 'identite', /relayer/);
});

test('un manifeste de confidentialité absent, faux ou incomplet est refusé', () => {
  const absent = sources();
  absent.privacyInfo = '';
  refus(() => evaluateSources(absent), 'confidentialite', /absent/);
  const raison = sources();
  raison.privacyInfo = raison.privacyInfo.replace('<string>CA92.1</string>', '<string>ZZZZ.9</string>');
  refus(() => evaluateSources(raison), 'confidentialite', /UserDefaults.*invalides/);
  const oubli = sources();
  oubli.privacyInfo = oubli.privacyInfo.replace(/<dict>\s*<key>NSPrivacyAccessedAPIType<\/key>\s*<string>NSPrivacyAccessedAPICategoryDiskSpace<\/string>[\s\S]*?<\/dict>/, '');
  oubli.swiftSources['ios-native/Jolene/Disque.swift'] = 'let libre = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])';
  refus(() => evaluateSources(oubli), 'confidentialite', /DiskSpace utilisée \(ios-native\/Jolene\/Disque\.swift\)/);
  const commentaire = sources();
  commentaire.privacyInfo = oubli.privacyInfo;
  commentaire.swiftSources['ios-native/Jolene/Disque.swift'] = '// volumeAvailableCapacityForImportantUsageKey : pas utilisé';
  assert.doesNotThrow(() => evaluateSources(commentaire));
  const ressources = sources();
  ressources.pbxproj = ressources.pbxproj.replaceAll('PrivacyInfo.xcprivacy in Resources', 'PrivacyInfo.xcprivacy');
  refus(() => evaluateSources(ressources), 'confidentialite', /ressources/);
});

test('l\'icône 1024 doit exister, mesurer 1024 et ne pas avoir d\'alpha', () => {
  const name = 'AppIcon-512@2x.png';
  for (const [buffer, fragment] of [[png({ colorType: 6 }), /alpha/], [png({ size: 512 }), /512 × 512/], [undefined, /absente/]]) {
    const files = sources();
    if (buffer) files.iconFiles[name] = buffer; else delete files.iconFiles[name];
    refus(() => evaluateSources(files), 'icone', fragment);
  }
  const sansEntree = sources();
  sansEntree.iconContents = JSON.stringify({ images: [{ idiom: 'universal', size: '512x512', filename: name }] });
  refus(() => evaluateSources(sansEntree), 'icone', /aucune icône 1024/);
});

// --- Numérotation ---------------------------------------------------------------------------

test('le numéro par défaut vaut max(dernier build App Store Connect, plancher) + 1, en ordre numérique', () => {
  assert.equal(resolveBuildNumber({ requested: '', existing: [], floor: 24 }), 25);
  assert.equal(resolveBuildNumber({ requested: undefined, existing: ['20', '24', '23'], floor: 24 }), 25);
  assert.equal(resolveBuildNumber({ requested: ' ', existing: ['9', '100', '30'], floor: 24 }), 101);
  assert.equal(resolveBuildNumber({ requested: '', existing: ['24'], floor: buildFloor({ buildNumber: 27 }) }), 28);
  assert.equal(buildFloor({ buildNumber: 12 }), 24);
});

test('un numéro saisi est refusé s\'il est invalide, inférieur ou égal à 24, ou déjà pris', () => {
  for (const requested of ['24', '1', '0', 'abc', '25.1', '-30', '026']) {
    assert.throws(() => resolveBuildNumber({ requested, existing: [], floor: 24 }), GuardFailure, requested);
  }
  assert.throws(() => resolveBuildNumber({ requested: '27', existing: ['25', '27'], floor: 24 }), /déjà présent/);
  assert.throws(() => resolveBuildNumber({ requested: '25', existing: ['25'], floor: 24 }), /déjà présent/);
  assert.equal(resolveBuildNumber({ requested: '40', existing: ['25', '27'], floor: 24 }), 40);
});

test('un numéro saisi trop haut (faute de frappe) est refusé au-delà du dernier build + 50', () => {
  assert.equal(MARGE_BUILD, 50);
  assert.equal(resolveBuildNumber({ requested: '75', existing: ['25'], floor: 24 }), 75);
  assert.throws(() => resolveBuildNumber({ requested: '76', existing: ['25'], floor: 24 }), /au plus 75/);
  assert.throws(() => resolveBuildNumber({ requested: '3100', existing: ['30'], floor: 24 }), /au plus 80/);
  assert.equal(resolveBuildNumber({ requested: '74', existing: [], floor: 24 }), 74);
});

// --- App Store Connect ----------------------------------------------------------------------

function cleAsc() {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return { publicKey, privateKeyBase64: Buffer.from(privateKey.export({ type: 'pkcs8', format: 'pem' })).toString('base64') };
}

test('le jeton ASC est un ES256 vérifiable, valable 15 minutes', () => {
  const { publicKey, privateKeyBase64 } = cleAsc();
  const token = ascToken({ keyId: 'KEY123', issuerId: 'issuer-uuid', privateKeyBase64, now: 1_800_000_000_000 });
  const [header, payload, signature] = token.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'KEY123', typ: 'JWT' });
  assert.deepEqual(JSON.parse(Buffer.from(payload, 'base64url')), { iss: 'issuer-uuid', iat: 1_800_000_000, exp: 1_800_000_900, aud: 'appstoreconnect-v1' });
  assert.ok(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
  assert.throws(() => ascToken({ keyId: 'K', issuerId: 'I', privateKeyBase64: Buffer.from('pas une clé').toString('base64') }), /n'est pas une clé \.p8/);
  assert.throws(() => ascToken({ keyId: '', issuerId: 'I', privateKeyBase64 }), /Secrets App Store Connect manquants/);
});

function fakeAsc(pages, { bundleId = APP.bundleId, status = 200 } = {}) {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(url.toString());
    if (status !== 200) return new Response(JSON.stringify({ errors: [{ code: 'NOT_AUTHORIZED', title: 'Authentication credentials are missing or invalid.' }] }), { status });
    if (url.pathname === `/v1/apps/${APP.appleId}`) return Response.json({ data: { attributes: { bundleId } } });
    const index = Number(url.searchParams.get('cursor') ?? 0);
    return Response.json(pages[index]);
  };
  return { get: ascClient({ fetchImpl, token: () => 'jeton' }), calls };
}

test('la liste des builds lit toutes les pages et vérifie le bundle de l\'app 6774672845', async () => {
  const next = 'https://api.appstoreconnect.apple.com/v1/builds?cursor=1';
  const { get, calls } = fakeAsc([
    { data: [{ attributes: { version: '23' } }, { attributes: { version: '24' } }], links: { next } },
    { data: [{ attributes: { version: '25' } }], links: {} },
  ]);
  const builds = await listBuilds(get);
  assert.deepEqual(builds.map((b) => b.attributes.version), ['23', '24', '25']);
  assert.match(calls[1], /filter\[app\]=6774672845/);
  await assert.rejects(listBuilds(fakeAsc([], { bundleId: 'app.autre' }).get), /ne correspond pas au bundle/);
  await assert.rejects(listBuilds(fakeAsc([{ data: [], links: { next: 'https://evil.example/v1/builds' } }]).get), /URL App Store Connect refusée/);
  await assert.rejects(listBuilds(fakeAsc([], { status: 401 }).get), /HTTP 401 : NOT_AUTHORIZED/);
});

test('une pagination App Store Connect qui boucle est refusée', async () => {
  const next = 'https://api.appstoreconnect.apple.com/v1/builds?cursor=1';
  const { get } = fakeAsc([
    { data: [{ attributes: { version: '25' } }], links: { next } },
    { data: [{ attributes: { version: '26' } }], links: { next } },
  ]);
  await assert.rejects(listBuilds(get), /Pagination App Store Connect en boucle/);
  await assert.rejects(listBuilds(fakeAsc([{ links: {} }]).get), /sans liste de builds/);
});

test('le traitement App Store Connect n\'est accepté qu\'en VALID avec conformité export false', () => {
  const build = (attributes) => [{ attributes: { version: '25', expired: false, usesNonExemptEncryption: false, ...attributes } }];
  assert.equal(evaluateProcessing([], 25), 'absent');
  assert.equal(evaluateProcessing(build({ processingState: 'PROCESSING' }), 25), 'processing');
  assert.equal(evaluateProcessing(build({ processingState: 'VALID' }), 25), 'valid');
  assert.throws(() => evaluateProcessing(build({ processingState: 'INVALID' }), 25), /ITMS/);
  assert.throws(() => evaluateProcessing(build({ processingState: 'VALID', usesNonExemptEncryption: null }), 25), /conformité export/);
  assert.throws(() => evaluateProcessing(build({ processingState: 'VALID', expired: true }), 25), /expiré/);
  assert.throws(() => evaluateProcessing([...build({ processingState: 'VALID' }), ...build({ processingState: 'VALID' })], 25), /plusieurs builds/);
});

// --- Profil, réglages, binaire, signature ---------------------------------------------------

const REQUIS = { 'aps-environment': 'production', 'com.apple.developer.associated-domains': ['applinks:jolene.app', 'webcredentials:jolene.app'] };
const profil = (overrides = {}, entitlements = {}) => ({
  Name: APP.profile, UUID: 'E32C340B-63C7-4FE2-A205-4E7F6E4A4E65', TeamIdentifier: [APP.teamId],
  ExpirationDate: new Date('2027-09-07T23:07:49Z'), DeveloperCertificates: [CERT],
  Entitlements: {
    'application-identifier': `${APP.teamId}.${APP.bundleId}`, 'com.apple.developer.team-identifier': APP.teamId,
    'get-task-allow': false, 'beta-reports-active': true, 'aps-environment': 'production',
    'com.apple.developer.associated-domains': '*', ...entitlements,
  },
  ...overrides,
});
const NOW = { now: new Date('2026-11-09T00:00:00Z'), identitySha1: CERT_SHA1 };

test('un profil App Store qui couvre les entitlements et le certificat du .p12 est accepté', () => {
  assert.deepEqual(evaluateProfile(profil(), REQUIS, { ...NOW, identitySha1: CERT_SHA1.match(/../g).join(':') }),
    { uuid: 'E32C340B-63C7-4FE2-A205-4E7F6E4A4E65', daysLeft: 302 });
  assert.doesNotThrow(() => evaluateProfile(profil({}, { 'com.apple.developer.associated-domains': [...REQUIS['com.apple.developer.associated-domains']] }), REQUIS, NOW));
});

for (const [nom, overrides, entitlements, fragment] of [
  ['sans push', {}, { 'aps-environment': undefined }, /aps-environment absent/],
  ['en push de développement', {}, { 'aps-environment': 'development' }, /aps-environment = "development"/],
  ['sans webcredentials', {}, { 'com.apple.developer.associated-domains': ['applinks:jolene.app'] }, /sans webcredentials:jolene\.app/],
  ['d\'un autre nom', { Name: 'iOS Team Store Provisioning Profile: app.jolene' }, {}, /« Jolene App Store Distribution » exigé/],
  ['de l\'ancienne équipe', {}, { 'application-identifier': 'FPQ78HDF4Y.app.jolene' }, /application-identifier/],
  ['de développement', { ProvisionedDevices: ['00008110'] }, { 'get-task-allow': true }, /profil App Store est exigé|get-task-allow/],
  ['sans beta-reports-active', {}, { 'beta-reports-active': undefined }, /TestFlight refuserait/],
  ['expiré', { ExpirationDate: new Date('2026-01-01T00:00:00Z') }, {}, /expiré/],
  ['sans le certificat de distribution', { DeveloperCertificates: [] }, {}, /aucun certificat/],
]) {
  test(`un profil ${nom} est refusé`, () => {
    const p = profil(overrides, entitlements);
    for (const [key, value] of Object.entries(p.Entitlements)) if (value === undefined) delete p.Entitlements[key];
    refus(() => evaluateProfile(p, REQUIS, NOW), 'profil', fragment);
  });
}

test('un .p12 dont le certificat n\'est pas dans le profil est refusé', () => {
  refus(() => evaluateProfile(profil(), REQUIS, { ...NOW, identitySha1: '00'.repeat(20) }), 'profil', /IOS_DISTRIBUTION_P12_BASE64/);
});

test('une empreinte du .p12 absente ou illisible fait échouer la garde, jamais un saut silencieux', () => {
  for (const identitySha1 of [undefined, '', '  ', 'pas-une-empreinte', CERT_SHA1.slice(0, 39)]) {
    refus(() => evaluateProfile(profil(), REQUIS, { ...NOW, identitySha1 }), 'profil', /empreinte SHA-1 du certificat du \.p12 absente ou invalide/);
  }
});

test('la couverture des entitlements accepte * et exige chaque domaine', () => {
  assert.deepEqual(entitlementsGaps(REQUIS, { 'aps-environment': 'production', 'com.apple.developer.associated-domains': ['*'] }), []);
  assert.deepEqual(entitlementsGaps({ x: true }, { x: false }), ['x = false, true attendu']);
});

const reglages = (overrides = {}) => ({
  CONFIGURATION: 'Release', PRODUCT_BUNDLE_IDENTIFIER: APP.bundleId, DEVELOPMENT_TEAM: APP.teamId, CODE_SIGN_STYLE: 'Manual',
  CODE_SIGN_IDENTITY: APP.identity, PROVISIONING_PROFILE_SPECIFIER: APP.profile, CURRENT_PROJECT_VERSION: '25', MARKETING_VERSION: '2.0.0',
  CODE_SIGN_ENTITLEMENTS: 'Jolene/Jolene.entitlements', INFOPLIST_FILE: 'Jolene/Info.plist', ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon',
  JOLENE_ENVIRONMENT: 'production', JOLENE_SUPABASE_URL: APP.productionUrl, JOLENE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x', APS_ENVIRONMENT: 'production',
  ...overrides,
});

test('les réglages Release résolus sont contrôlés (signature, build, DEBUG, production)', () => {
  assert.doesNotThrow(() => evaluateBuildSettings(reglages(), { buildNumber: 25 }));
  refus(() => evaluateBuildSettings(reglages({ SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG' }), { buildNumber: 25 }), 'reglages', /DEBUG/);
  for (const flags of ['-D DEBUG', '$(inherited) -DDEBUG', '-Xfrontend -foo -D  DEBUG']) {
    refus(() => evaluateBuildSettings(reglages({ OTHER_SWIFT_FLAGS: flags }), { buildNumber: 25 }), 'reglages', /OTHER_SWIFT_FLAGS contient -D DEBUG/);
  }
  assert.doesNotThrow(() => evaluateBuildSettings(reglages({ OTHER_SWIFT_FLAGS: '$(inherited) -D DEBUG_LOGS_OFF', SWIFT_OPTIMIZATION_LEVEL: '-O' }), { buildNumber: 25 }));
  refus(() => evaluateBuildSettings(reglages({ SWIFT_OPTIMIZATION_LEVEL: '-Onone' }), { buildNumber: 25 }), 'reglages', /-Onone/);
  refus(() => evaluateBuildSettings(reglages({ CODE_SIGN_IDENTITY: '' }), { buildNumber: 25 }), 'reglages', /CODE_SIGN_IDENTITY/);
  refus(() => evaluateBuildSettings(reglages(), { buildNumber: 26 }), 'reglages', /CURRENT_PROJECT_VERSION/);
  refus(() => evaluateBuildSettings(reglages({ JOLENE_SUPABASE_URL: `https://${APP.stagingRef}.supabase.co` }), { buildNumber: 25 }), 'reglages', /URL Supabase/);
});

const info = (overrides = {}) => ({
  CFBundleIdentifier: APP.bundleId, CFBundleShortVersionString: '2.0.0', CFBundleVersion: '25', ITSAppUsesNonExemptEncryption: false,
  JoleneEnvironment: 'production', JoleneSupabaseURL: APP.productionUrl, JoleneSupabasePublishableKey: 'sb_publishable_x',
  CFBundleIcons: { CFBundlePrimaryIcon: { CFBundleIconName: 'AppIcon' } }, ...overrides,
});

test('le binaire exporté est contrôlé (version, build, production, confidentialité, icône)', () => {
  const contexte = { buildNumber: 25, hasPrivacyInfo: true, privacyXml: sources().privacyInfo, hasAssetsCar: true, swiftSources: sources().swiftSources };
  assert.doesNotThrow(() => evaluateBundle(info(), contexte));
  refus(() => evaluateBundle(info({ JoleneEnvironment: 'demo' }), contexte), 'environnement', /démo/);
  refus(() => evaluateBundle(info({ CFBundleVersion: '24' }), contexte), 'binaire', /CFBundleVersion/);
  refus(() => evaluateBundle(info({ ITSAppUsesNonExemptEncryption: undefined }), contexte), 'chiffrement');
  refus(() => evaluateBundle(info(), { ...contexte, hasPrivacyInfo: false }), 'confidentialite', /racine/);
  refus(() => evaluateBundle(info(), { ...contexte, hasAssetsCar: false }), 'icone');
});

test('la signature exige l\'identité, le profil embarqué et les entitlements de production', () => {
  const entitlements = { ...profil().Entitlements, 'com.apple.developer.associated-domains': [...REQUIS['com.apple.developer.associated-domains']] };
  const uuid = profil().UUID;
  const base = {
    entitlements, embeddedProfile: { Name: APP.profile, UUID: uuid }, expectedProfileUuid: uuid,
    authorities: [APP.identity, 'Apple Worldwide Developer Relations Certification Authority'], required: REQUIS,
  };
  assert.doesNotThrow(() => evaluateSignature(base));
  refus(() => evaluateSignature({ ...base, authorities: ['Apple Development: X'] }), 'signature', /n'est pas signée/);
  refus(() => evaluateSignature({ ...base, entitlements: { ...entitlements, 'aps-environment': 'development' } }), 'signature', /production/);
  refus(() => evaluateSignature({ ...base, entitlements: { ...entitlements, 'get-task-allow': true } }), 'signature', /get-task-allow/);
  const sansDomaines = { ...entitlements };
  delete sansDomaines['com.apple.developer.associated-domains'];
  refus(() => evaluateSignature({ ...base, entitlements: sansDomaines }), 'signature', /associated-domains absent/);
  refus(() => evaluateSignature({ ...base, embeddedProfile: { Name: 'Autre profil', UUID: uuid } }), 'signature', /« Autre profil »/);
  refus(() => evaluateSignature({ ...base, embeddedProfile: { Name: APP.profile, UUID: '00000000-0000-0000-0000-000000000000' } }), 'signature', /différent du profil validé/);
  refus(() => evaluateSignature({ ...base, expectedProfileUuid: undefined }), 'signature', /UUID non transmis/);
  refus(() => evaluateSignature({ ...base, embeddedProfile: { Name: APP.profile, UUID: uuid, ProvisionedDevices: ['00008110'] } }), 'signature', /ad hoc/);
});

// --- Workflow et lane : TestFlight interne uniquement ---------------------------------------

const workflow = readFileSync(join(root, '.github/workflows/ios-native-testflight.yml'), 'utf8');
const fastfile = readFileSync(join(root, 'fastlane/Fastfile'), 'utf8');
const lane = fastfile.slice(fastfile.indexOf('lane :testflight_native'), fastfile.indexOf('platform :android'));

test('le workflow ne se déclenche qu\'à la main, depuis main, un envoi à la fois', () => {
  assert.match(workflow, /^on:\n {2}workflow_dispatch:\n/m);
  assert.doesNotMatch(workflow, /^ {2}(push|pull_request|schedule|workflow_run|release):/m);
  assert.match(workflow, /concurrency:\n {2}group: ios-native-testflight\n {2}cancel-in-progress: false/);
  assert.match(workflow, /"\$GITHUB_REF" != refs\/heads\/main/);
  assert.match(workflow, /^permissions:\n {2}contents: read\n\n/m);
});

test('le workflow n\'utilise que les secrets iOS déjà exigés par prepare-ci-signing.mjs', () => {
  // Liste de référence lue dans la source existante (branche iOS), jamais recopiée ici.
  const signing = readFileSync(join(root, 'scripts/mobile/prepare-ci-signing.mjs'), 'utf8');
  const branche = signing.slice(signing.indexOf("platform === 'ios'"));
  const attendus = [...new Set([...branche.matchAll(/'((?:IOS|ASC)_[A-Z0-9_]+)'/g)].map((m) => m[1]))].sort();
  assert.equal(attendus.length, 6);
  const utilises = [...new Set([...workflow.matchAll(/secrets\.(\w+)/g)].map((m) => m[1]))].sort();
  assert.deepEqual(utilises, attendus);
});

// Toute soumission, livraison de fiche ou distribution externe ; `default_platform(:ios)` rend
// `fastlane submit` équivalent à `fastlane ios submit`, d'où la forme sans plateforme.
const INTERDIT = /upload_to_app_store|\bdeliver\b|submit_for_review|automatic_release|distribute_external: true|groups:|notify_external_testers: true|\bfastlane\s+(?:ios\s+)?(?:submit|deliver|release|appstore)\b/;

test('le motif anti-soumission couvre les formes avec et sans plateforme', () => {
  for (const appel of ['bundle exec fastlane submit', 'fastlane ios submit', 'fastlane deliver', 'bundle exec fastlane ios release', 'upload_to_app_store(api_key: api)']) {
    assert.match(appel, INTERDIT, appel);
  }
  assert.doesNotMatch('bundle exec fastlane ios testflight_native', INTERDIT);
});

test('aucune soumission à la revue, aucun testeur externe, aucune mise en vente', () => {
  assert.doesNotMatch(workflow, INTERDIT);
  assert.doesNotMatch(lane, INTERDIT);
  assert.doesNotMatch(lane, /\bsubmit\b/);
  const appels = [...workflow.matchAll(/^(?!\s*#).*\bfastlane\s+(\S+(?:\s+\S+)?)/gm)].map((m) => m[1].trim());
  assert.deepEqual(appels, ['ios testflight_native'], 'seule la lane TestFlight interne peut être appelée');
  assert.match(workflow, /bundle exec fastlane ios testflight_native/);
  assert.match(lane, /skip_submission: true/);
  assert.match(lane, /distribute_external: false/);
});

test('l\'archive est signée par l\'identité et le profil attendus, et le trousseau toujours supprimé', () => {
  assert.match(workflow, /JOLENE_SIGNING_IDENTITY: 'Apple Distribution: Jolene App \(GDU5AA28M9\)'/);
  assert.match(workflow, /JOLENE_PROFILE_NAME: 'Jolene App Store Distribution'/);
  assert.match(workflow, /-configuration Release/);
  assert.match(workflow, /-exportOptionsPlist ios\/ExportOptions-AppStore\.plist/);
  const nettoyage = workflow.slice(workflow.indexOf('Supprimer le trousseau'));
  assert.match(nettoyage, /^ {8}if: always\(\)\n {8}run: \|\n.*security delete-keychain/m);
  assert.match(nettoyage, /rm -rf "\$RUNNER_TEMP\/jolene-signing"/);
  assert.doesNotMatch(workflow, /set -x|echo "\$\{?(IOS_|ASC_)/);
  const etapes = ['ios-native-testflight.mjs depot', 'build-number', ' profile ', ' settings ', 'xcodebuild archive', '-exportArchive', ' bundle ', ' signature ', 'verify-free', 'fastlane ios testflight_native', ' processing '];
  const positions = etapes.map((etape) => workflow.indexOf(etape));
  assert.ok(positions.every((p) => p >= 0), `étape manquante : ${etapes[positions.indexOf(-1)]}`);
  assert.deepEqual([...positions].sort((a, b) => a - b), positions, 'ordre des gardes avant l\'envoi');
});

test('la configuration Capacitor reste lisible à l\'identique (marketingVersion, buildNumber au premier niveau)', () => {
  const release = JSON.parse(readFileSync(join(root, 'config/mobile-release.json'), 'utf8'));
  assert.ok(isVersion(release.marketingVersion), release.marketingVersion);
  assert.ok(Number.isSafeInteger(release.buildNumber));
  assert.ok(buildFloor(release) >= APP.buildFloor);
});
