// Cohorte STAGING du lot 5 (L5-T13) : verrou de projet, cycle préparer → scanner → vérifier → nettoyer et SQL, sur un
// transport simulé (aucun réseau, aucune base). Script : scripts/mobile/staging-lot5-fixture.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  executer, verifierProjet, destinationAdmise, sqlPreparer, sqlNettoyer, sqlCompter, sqlVerifier, manifeste,
  totalMarques, validerRelectures, COMPTES, STAGING_REF, PRODUCTION_REF, STAGING_URL, ECART_SCANS_MS, sha256,
} from '../../scripts/mobile/staging-lot5-fixture.mjs';

const ZERO = Object.fromEntries(COMPTES.map(c => [c, 0]));
const RELU_CONFORME = {
  candidature_statut: 'ACCEPTEE', candidature_traitee: true, m1_statut: 'ASSIGNEE', m1_assignee_s1: true, m1_contrats: 1,
  m2_contrat_statut: 'SIGNE_COMPLET', presence_validee: true, presence_valide_le: true, m2_notations: 1, escrow: 0,
  escrow_file: 0, notifications_hors_cohorte: 0, emails_cohorte: 0, canaux_ouverts: 0,
};

/** STAGING simulé : Auth admin, Management API (SQL reconnu par ses marqueurs), PostgREST rpc. */
function banc(t, surcharge = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-l5-node-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = {
    STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_ACCESS_TOKEN: 'faux-management-CANARI-jeton',
    LOT5_STAGING_ECRITURE: 'COHORTE_D5', LOT5_RUN_ID: 'node-1', GITHUB_ENV: join(dir, 'github-env'),
    LOT5_MANIFEST: join(dir, 'prive', 'manifeste.json'), LOT5_XCUITEST_JSON: join(dir, 'prive', 'entree.json'), ...surcharge,
  };
  const b = {
    env, dir, appels: [], logs: [], attentes: [], users: new Map(), code: '123456', prochain: 'OUVERTURE', scans: [],
    seeded: false, candidature: null, presence: null, nettoye: false, relu: { ...RELU_CONFORME }, reste: null, fail: null,
    horloge: new Date('2026-11-24T10:00:00.000Z'),
  };
  const rep = (corps, status = 200) => ({ status, ok: status >= 200 && status < 300, json: async () => corps });
  b.fetchImpl = async (url, opts) => {
    const corps = opts.body ? JSON.parse(opts.body) : undefined;
    b.appels.push({ url, methode: opts.method, corps, auth: opts.headers.Authorization });
    const u = new URL(url);
    if (u.hostname === 'api.supabase.com' && u.pathname.endsWith('/api-keys')) {
      return rep([{ name: 'anon', api_key: 'anon-CANARI-cle' }, { name: 'service_role', api_key: 'service-CANARI-cle' },
        { name: 'default', type: 'publishable', api_key: 'sb_publishable_CANARIpubliable0123' }]);
    }
    if (u.pathname.endsWith('/database/query')) {
      const sql = corps.query;
      if (sql.includes('$l5_seed$')) { b.seeded = true; return rep([{ prepare: true }]); }
      if (sql.includes('$l5_clean$')) { if (b.fail === 'dependance') return rep({ message: 'Dépendance hors lot L5 : public.x' }, 400); b.seeded = false; b.nettoye = true; return rep([{ nettoye: true }]); }
      if (sql.includes('code_pointage_actif AS code')) return rep([{ code: b.code, prochain_type_scan: b.prochain, statut: b.scans.length ? 'EN_COURS' : 'ASSIGNEE' }]);
      if (sql.includes('FROM public.candidatures') && sql.includes('SELECT id, statut')) return rep(b.candidature ? [b.candidature] : []);
      if (sql.includes('AS arrivee')) return rep(b.presence ? [b.presence] : []);
      if (sql.includes('AS candidature_statut')) return rep([b.relu]);
      if (sql.includes('AS auth,')) {
        const ligne = b.reste ?? (b.seeded ? { ...ZERO, missions: 2, auth: b.users.size } : { ...ZERO, auth: b.users.size });
        return rep([ligne]);
      }
      throw new Error('SQL inattendu');
    }
    if (u.pathname === '/auth/v1/admin/users' && opts.method === 'POST') {
      const user = { id: corps.id, email: corps.email, app_metadata: corps.app_metadata, password: corps.password };
      b.users.set(corps.id, user); return rep(user);
    }
    if (u.pathname.startsWith('/auth/v1/admin/users/')) {
      const id = u.pathname.split('/').at(-1);
      if (opts.method === 'DELETE') { b.users.delete(id); return rep({}); }
      return b.users.has(id) ? rep(b.users.get(id)) : rep({}, 404);
    }
    if (u.pathname === '/auth/v1/token') {
      const user = [...b.users.values()].find(x => x.email === corps.email && x.password === corps.password);
      return user ? rep({ access_token: `jwt-CANARI-${user.app_metadata.role}`, user: { id: user.id } }) : rep({ message: 'Invalid login' }, 400);
    }
    if (u.pathname === '/rest/v1/rpc/fn_postuler_mission') {
      b.candidature = { id: '0b6a2f5e-1c2d-4e3f-9a8b-7c6d5e4f3a2b', statut: 'EN_ATTENTE' }; return rep({ success: true });
    }
    if (u.pathname === '/rest/v1/rpc/fn_scanner_code_pointage') {
      if (corps.p_code !== b.code) return rep({ message: 'Code de pointage invalide ou expiré.' }, 404);
      b.scans.push({ type: b.prochain, auth: opts.headers.Authorization });
      b.code = b.prochain === 'OUVERTURE' ? '654321' : '111222';
      b.prochain = b.prochain === 'OUVERTURE' ? 'FERMETURE' : 'OUVERTURE';
      if (b.scans.length === 2) b.presence = { id: '1c7b3a6f-2d3e-4f40-8b9c-8d7e6f5a4b3c', arrivee: true, depart: true, validee: false };
      return rep({ success: true });
    }
    throw new Error(`URL inattendue ${url}`);
  };
  b.run = action => executer({ action, env, fetchImpl: b.fetchImpl, log: l => b.logs.push(l),
    attendre: async ms => { b.attentes.push(ms); b.horloge = new Date(b.horloge.getTime() + ms); }, maintenant: () => b.horloge,
    genererMotDePasse: (() => { let n = 0; return () => `Aa1!CANARI-mot-de-passe-${n++}-assez-long-pour-la-regle`; })() });
  return b;
}

const lignesPubliques = b => b.logs.filter(l => !l.startsWith('::add-mask::')).join('\n');

test('verrou : la référence de production est refusée nommément, avant tout appel réseau, pour chaque action', async t => {
  for (const action of ['acces', 'preparer', 'scanner', 'verifier', 'nettoyer', 'compter']) {
    for (const surcharge of [{ STAGING_SUPABASE_PROJECT_REF: PRODUCTION_REF },
      { STAGING_SUPABASE_URL: `https://${PRODUCTION_REF}.supabase.co` }, { SUPABASE_URL: `https://${PRODUCTION_REF}.supabase.co` }]) {
      const b = banc(t, surcharge);
      await assert.rejects(b.run(action), e => /PRODUCTION/.test(e.message) && e.message.includes(PRODUCTION_REF)
        && e.message.includes(STAGING_REF), `${action} ${JSON.stringify(surcharge)}`);
      assert.equal(b.appels.length, 0, `${action} : aucune requête`);
      assert.equal(existsSync(b.env.LOT5_MANIFEST), false, 'aucun manifeste');
    }
  }
});

test('verrou : une référence absente ou autre que le STAGING attendu est refusée, sans recopier la valeur', async t => {
  for (const ref of [undefined, '', 'autreprojetxyzabcdefg', `${STAGING_REF} `.repeat(2), STAGING_REF.toUpperCase()]) {
    const b = banc(t, { STAGING_SUPABASE_PROJECT_REF: ref });
    await assert.rejects(b.run('preparer'), e => /n'est pas explicitement le projet STAGING/.test(e.message)
      && (!ref || !e.message.includes(ref.trim()) || ref.trim() === STAGING_REF));
    assert.equal(b.appels.length, 0);
  }
  assert.throws(() => verifierProjet({ STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_URL: 'https://exemple.supabase.co' }),
    /STAGING_SUPABASE_URL/);
  assert.equal(verifierProjet({ STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_URL: STAGING_URL }), STAGING_REF);
});

test('verrou : seules la Management API du STAGING et le projet STAGING sont des destinations admises', () => {
  for (const url of [`${STAGING_URL}/rest/v1/rpc/x`, `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`]) {
    assert.equal(destinationAdmise(url), true, url);
  }
  for (const url of [`https://${PRODUCTION_REF}.supabase.co/rest/v1/rpc/x`, `https://api.supabase.com/v1/projects/${PRODUCTION_REF}/database/query`,
    `http://${STAGING_REF}.supabase.co/x`, `https://${STAGING_REF}.supabase.co:8443/x`, `https://${STAGING_REF}.supabase.co.exemple.com/x`,
    'https://api.supabase.com/v1/projects', 'pas une url']) {
    assert.equal(destinationAdmise(url), false, url);
  }
});

test('écriture : préparer, scanner et nettoyer exigent l approbation explicite du workflow', async t => {
  for (const action of ['preparer', 'scanner', 'nettoyer']) {
    const b = banc(t, { LOT5_STAGING_ECRITURE: '' });
    await assert.rejects(b.run(action), /LOT5_STAGING_ECRITURE=COHORTE_D5/);
    assert.equal(b.appels.length, 0);
  }
});

test('cycle complet : préparer → scanner → vérifier → nettoyer, secrets jamais publiés, nettoyage prouvé à 0', async t => {
  const b = banc(t);
  const prep = await b.run('preparer');
  assert.equal(prep.status, 'prepared');
  // Manifeste et entrée privés (0600), écrits par le runner seulement.
  for (const f of [b.env.LOT5_MANIFEST, b.env.LOT5_XCUITEST_JSON]) assert.equal(statSync(f).mode & 0o777, 0o600, f);
  const entree = JSON.parse(readFileSync(b.env.LOT5_XCUITEST_JSON, 'utf8'));
  assert.equal(entree.purpose, 'lot5-staging-etab-v1');
  assert.equal(entree.projectRef, STAGING_REF);
  assert.equal(entree.codeSha256, sha256('123456'), 'empreinte du code relu côté service');
  assert.ok(entree.etablissement.email.endsWith('@example.invalid'));
  assert.equal(entree.marker, 'RECETTE-L5-node-1');
  assert.ok(entree.m1.intitule.startsWith(entree.marker) && entree.m2.intitule.startsWith(entree.marker));
  assert.equal(entree.presenceId, null);
  assert.ok(!JSON.stringify(entree).includes('123456'), 'jamais le code en clair dans l entrée du XCUITest');
  const manif = JSON.parse(readFileSync(b.env.LOT5_MANIFEST, 'utf8'));
  assert.ok(!JSON.stringify(entree).includes(manif.soignant.password), 'mot de passe de S1 hors de l entrée du XCUITest');
  // Auth : E1 propriétaire legacy (aucun etablissement_id), S1 soignant ; tous deux marqués TEST et run.
  const posts = b.appels.filter(a => a.url.endsWith('/auth/v1/admin/users'));
  assert.deepEqual(posts.map(p => p.corps.app_metadata.role), ['ETABLISSEMENT', 'SOIGNANT']);
  for (const p of posts) {
    assert.equal(p.corps.email_confirm, true);
    assert.deepEqual(Object.keys(p.corps.app_metadata).sort(), ['est_compte_test', 'is_test_playwright', 'load_fixture_kind', 'load_fixture_run', 'role']);
  }
  const postuler = b.appels.find(a => a.url.endsWith('/rpc/fn_postuler_mission'));
  assert.equal(postuler.auth, 'Bearer jwt-CANARI-SOIGNANT', 'candidature déposée sous le JWT de S1');
  assert.equal(postuler.corps.p_choix_contrat, 'SALARIE');
  // Seules des destinations STAGING ont été contactées.
  assert.ok(b.appels.every(a => destinationAdmise(a.url)));

  await b.run('scanner');
  assert.deepEqual(b.scans.map(s => s.type), ['OUVERTURE', 'FERMETURE']);
  assert.ok(b.scans.every(s => s.auth === 'Bearer jwt-CANARI-SOIGNANT'), 'scans sous le JWT de S1');
  assert.equal(b.attentes[0], ECART_SCANS_MS, 'anti-rejeu : 125 s entre les deux scans');
  assert.ok(b.horloge.getTime() >= new Date(manif.m2.fin).getTime(), 'attente de la fin du créneau planifié');
  assert.equal(JSON.parse(readFileSync(b.env.LOT5_XCUITEST_JSON, 'utf8')).presenceId, '1c7b3a6f-2d3e-4f40-8b9c-8d7e6f5a4b3c');

  assert.deepEqual(await b.run('verifier'), { conforme: true });
  const etat = await b.run('nettoyer');
  assert.equal(etat.total, 0);
  assert.equal(b.users.size, 0, 'comptes Auth supprimés');
  assert.equal(existsSync(b.env.LOT5_XCUITEST_JSON), false, 'entrée privée effacée');
  assert.equal(JSON.parse(readFileSync(b.env.LOT5_MANIFEST, 'utf8')).status, 'cleaned');
  const deletes = b.appels.filter(a => a.methode === 'DELETE').length;
  assert.equal((await b.run('nettoyer')).total, 0, 'reprise idempotente');
  assert.equal(b.appels.filter(a => a.methode === 'DELETE').length, deletes, 'aucun second DELETE');

  // Aucun mot de passe, jeton, clé ni code dans les lignes publiques ; chaque secret a été masqué.
  const publiques = lignesPubliques(b);
  assert.doesNotMatch(publiques, /CANARI|123456|654321/);
  for (const secret of [manif.etablissement.password, manif.soignant.password, 'service-CANARI-cle', 'jwt-CANARI-SOIGNANT', '123456']) {
    assert.ok(b.logs.includes(`::add-mask::${secret}`), 'secret masqué');
  }
});

test('scanner : un code modifié depuis la préparation est refusé avant tout scan', async t => {
  const b = banc(t);
  await b.run('preparer');
  b.code = '999999';
  await assert.rejects(b.run('scanner'), /Code de M2 modifié/);
  assert.equal(b.scans.length, 0);
  assert.equal(b.appels.some(a => a.url.endsWith('/rpc/fn_scanner_code_pointage')), false);
});

test('préparer une seconde fois est refusé ; un nettoyage sans manifeste ne contacte rien', async t => {
  const b = banc(t);
  await b.run('preparer');
  await assert.rejects(b.run('preparer'), /déjà présent/);
  const vide = banc(t);
  assert.deepEqual(await vide.run('nettoyer'), { skipped: true });
  assert.equal(vide.appels.length, 0);
});

test('nettoyage : dépendance inconnue ou compte restant → échec, manifeste conservé, jamais « cleaned »', async t => {
  const dep = banc(t);
  await dep.run('preparer');
  dep.fail = 'dependance';
  await assert.rejects(dep.run('nettoyer'), /Dépendance hors lot L5/);
  assert.equal(dep.appels.filter(a => a.methode === 'DELETE').length, 0, 'aucune suppression Auth');
  assert.notEqual(JSON.parse(readFileSync(dep.env.LOT5_MANIFEST, 'utf8')).status, 'cleaned');

  const reste = banc(t);
  await reste.run('preparer');
  reste.reste = { ...ZERO, notations: 1 };
  await assert.rejects(reste.run('nettoyer'), /Nettoyage L5 incomplet/);
  assert.notEqual(JSON.parse(readFileSync(reste.env.LOT5_MANIFEST, 'utf8')).status, 'cleaned');
});

test('nettoyage : un compte Auth d un autre run n est jamais supprimé', async t => {
  const b = banc(t);
  await b.run('preparer');
  const e1 = [...b.users.values()].find(u => u.app_metadata.role === 'ETABLISSEMENT');
  e1.app_metadata = { ...e1.app_metadata, load_fixture_run: 'autre-run' };
  await assert.rejects(b.run('nettoyer'), /hors du run L5/);
  assert.equal(b.appels.filter(a => a.methode === 'DELETE').length, 0);
});

test('manifeste altéré : aucune action', async t => {
  const b = banc(t);
  await b.run('preparer');
  const m = JSON.parse(readFileSync(b.env.LOT5_MANIFEST, 'utf8'));
  writeFileSync(b.env.LOT5_MANIFEST, JSON.stringify({ ...m, projectRef: PRODUCTION_REF }));
  b.appels.length = 0;
  await assert.rejects(b.run('nettoyer'), /Manifeste L5 altéré/);
  assert.equal(b.appels.length, 0);
});

test('relectures : chaque écart est nommé ; un compte illisible n est jamais un zéro', () => {
  assert.deepEqual(validerRelectures(RELU_CONFORME), []);
  const ecarts = validerRelectures({ ...RELU_CONFORME, candidature_statut: 'EN_ATTENTE', escrow: 1, presence_validee: false });
  assert.equal(ecarts.length, 3);
  assert.ok(ecarts.some(e => e.startsWith('escrow : attendu 0')));
  assert.equal(validerRelectures(undefined).length, 14);
  assert.equal(totalMarques(ZERO), 0);
  assert.throws(() => totalMarques({ ...ZERO, missions: undefined }), /illisible \(missions\)/);
  assert.throws(() => totalMarques({ ...ZERO, missions: '0' }), /illisible/);
});

test('SQL : contexte service, verrou consultatif, aucun contournement de déclencheur, audits conservés', () => {
  const m = manifeste('controle-sql', new Date('2026-11-24T10:00:00.000Z'));
  m.candidatureId = '0b6a2f5e-1c2d-4e3f-9a8b-7c6d5e4f3a2b';
  m.presenceId = '1c7b3a6f-2d3e-4f40-8b9c-8d7e6f5a4b3c';
  const seed = sqlPreparer(m), clean = sqlNettoyer(m);
  for (const sql of [seed, clean]) {
    assert.match(sql, /pg_advisory_xact_lock/);
    assert.match(sql, /SET LOCAL request\.jwt\.claim\.role = 'service_role'/);
    assert.match(sql, /Contexte service requis \(L5\)/);
    assert.doesNotMatch(sql, /DISABLE TRIGGER|session_replication_role|TRUNCATE|DELETE FROM public\.journaux_audit/);
    assert.doesNotMatch(sql, new RegExp(PRODUCTION_REF));
  }
  // M2 assignée par le seul helper de test (CLAUDE.md), jamais par un UPDATE direct de missions.
  assert.match(seed, /public\.fn_test_update_mission\(/);
  assert.doesNotMatch(seed, /UPDATE public\.missions/);
  assert.match(seed, /'FACTURE_MENSUELLE'/);
  assert.match(seed, /'SIGNE_COMPLET'/);
  assert.match(seed, /est_compte_test/);
  assert.match(seed, /NOT \(u\.raw_app_meta_data \? 'etablissement_id'\)/, 'E1 propriétaire legacy');
  assert.match(seed, /aucune ligne membres_etablissement/);
  assert.match(seed, /'SALARIE'/);
  assert.doesNotMatch(seed, /'LIBERAL'/, 'aucune mission libérale : aucun escrow possible');
  assert.match(seed, /telephone_contact[\s\S]*NULL, true/, 'aucun téléphone de contact : aucun SMS');
  assert.match(clean, /Dépendance hors lot L5/);
  assert.ok(clean.indexOf('Dépendance hors lot L5') < clean.indexOf('DELETE FROM public.missions WHERE id'), 'contrôle avant les parents');
  assert.match(clean, /load_cleanup_pending/);
  assert.match(sqlVerifier(m), /AS escrow_file/);
  assert.match(sqlCompter(m), /AS preferences;$/);
  // Les horaires de M2 laissent le code affichable tout de suite et la présence validable à la fin du créneau.
  const debut = new Date(m.m2.debut).getTime(), fin = new Date(m.m2.fin).getTime(), t0 = Date.parse('2026-11-24T10:00:00.000Z');
  assert.ok(debut - t0 <= 15 * 60_000 && debut > t0, 'créneau dans la fenêtre d affichage (15 min avant le début)');
  assert.ok(fin - debut >= ECART_SCANS_MS + 60_000, 'les deux scans tiennent dans le créneau');
});
