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
  GRAPHE_NETTOYAGE, grapheNettoyage, lireGraphe, RACINES_COHORTE, sqlRetrouverRun, cibleDepuisRecherche, emailsDuRun,
  NON_SUPPRIMABLES, sqlResidus, lireResidus, debutIntitule, controlerSessionEtablissement, choisirCleApp, messageServeur, decrireTemoinSansSession,
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
    recherches: 0, residus: {}, sessionEtab: [], permissions: null,
    horloge: new Date('2026-11-24T10:00:00.000Z'),
  };
  // Recherche par étiquette : ce que le STAGING simulé contient pour le run, sans mot de passe.
  b.recherche = () => {
    const e1 = [...b.users.values()].find(u => u.app_metadata.role === 'ETABLISSEMENT');
    const s1 = [...b.users.values()].find(u => u.app_metadata.role === 'SOIGNANT');
    return {
      etablissements: b.seeded && e1 ? [{ id: e1.id, test: true, email: e1.email }] : [],
      soignants: b.seeded && s1 ? [{ id: s1.id, test: true, email: s1.email }] : [],
      auth: [...b.users.values()].map(u => ({ id: u.id, email: u.email, role: u.app_metadata.role,
        run: u.app_metadata.load_fixture_run, kind: u.app_metadata.load_fixture_kind })),
    };
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
      if (sql.includes('AS auth;')) { b.recherches += 1; return rep([b.recherche()]); }
      if (sql.includes('AS residus;')) return rep([{ residus: { ...Object.fromEntries(Object.keys(NON_SUPPRIMABLES).map(t => [t, []])), ...b.residus } }]);
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
    const e1 = () => [...b.users.values()].find(x => x.app_metadata.role === 'ETABLISSEMENT');
    if (u.pathname === '/rest/v1/rpc/fn_get_my_role') {
      b.sessionEtab.push({ rpc: 'role', apikey: opts.headers.apikey, auth: opts.headers.Authorization });
      return rep({ user_id: e1().id, role: 'ADMIN_ETABLISSEMENT', etablissement_id: e1().id });
    }
    if (u.pathname === '/rest/v1/rpc/fn_mes_permissions_etab') {
      // Clé publishable en Authorization : ce que l'app envoie sans session enregistrée (rôle anon) → 401 42501.
      if (opts.headers.Authorization === `Bearer ${opts.headers.apikey}`) {
        b.sessionEtab.push({ rpc: 'temoin', apikey: opts.headers.apikey, auth: opts.headers.Authorization });
        return rep({ code: '42501', message: 'permission denied for function fn_mes_permissions_etab' }, 401);
      }
      b.sessionEtab.push({ rpc: 'permissions', apikey: opts.headers.apikey, corps });
      if (b.permissions === 'HTTP401') return rep({ code: 'PGRST301', message: 'JWT invalide' }, 401);
      return rep(b.permissions ?? { success: true, role: 'PROPRIETAIRE', etablissement_id: e1().id, permissions: {
        missions: true, candidatures: true, contrats: true, pointage: true, lecture: true, rh: true } });
    }
    if (u.pathname === '/rest/v1/rpc/fn_mon_etablissement_complet') {
      b.sessionEtab.push({ rpc: 'profil' });
      return rep({ id: e1().id, nom: e1().app_metadata.load_fixture_run ? `RECETTE-L5-${e1().app_metadata.load_fixture_run}` : null });
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
  for (const action of ['acces', 'preparer', 'scanner', 'verifier', 'nettoyer', 'nettoyer_run', 'compter']) {
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
  for (const action of ['preparer', 'scanner', 'nettoyer', 'nettoyer_run']) {
    const b = banc(t, { LOT5_STAGING_ECRITURE: '', LOT5_NETTOYER_RUN: 'node-1' });
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
  await assert.rejects(reste.run('nettoyer'), e => /Nettoyage L5 incomplet \(run node-1\)/.test(e.message)
    && e.message.includes("nettoyer_run=node-1") && !/manifeste conservé/.test(e.message), 'le message nomme la reprise par étiquette');
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
  assert.ok(clean.indexOf('Dépendance hors lot L5') < clean.indexOf('DELETE FROM public.missions WHERE ctid'), 'contrôle avant les parents');
  assert.match(clean, /load_cleanup_pending/);
  assert.match(sqlVerifier(m), /AS escrow_file/);
  assert.match(sqlCompter(m), /AS preferences;$/);
  // Les horaires de M2 laissent le code affichable tout de suite et la présence validable à la fin du créneau.
  const debut = new Date(m.m2.debut).getTime(), fin = new Date(m.m2.fin).getTime(), t0 = Date.parse('2026-11-24T10:00:00.000Z');
  assert.ok(debut - t0 <= 15 * 60_000 && debut > t0, 'créneau dans la fenêtre d affichage (15 min avant le début)');
  assert.ok(fin - debut >= ECART_SCANS_MS + 60_000, 'les deux scans tiennent dans le créneau');
});

// MARK: - Reprise par étiquette (revue de #1183, M1)

test('nettoyer_run : la cohorte d un run perdu est retrouvée par son étiquette et nettoyée sans manifeste', async t => {
  const b = banc(t);
  await b.run('preparer');
  rmSync(b.env.LOT5_MANIFEST); rmSync(b.env.LOT5_XCUITEST_JSON); // le runner hébergé disparaît avec eux
  b.env.LOT5_NETTOYER_RUN = 'node-1';
  const etat = await b.run('nettoyer_run');
  assert.equal(etat.total, 0);
  assert.equal(b.users.size, 0, 'les deux comptes Auth du run sont supprimés');
  assert.equal(b.recherches, 1);
  const nettoyage = b.appels.find(a => a.corps?.query?.includes('$l5_clean$')).corps.query;
  const [e1] = [...b.appels.filter(a => a.url.endsWith('/auth/v1/admin/users'))].map(a => a.corps.id);
  assert.ok(nettoyage.includes(e1), 'le nettoyage cible l établissement retrouvé');
  assert.doesNotMatch(lignesPubliques(b), /CANARI/);
  // Run déjà nettoyé (ou jamais créé) : rien trouvé, compte à 0, aucune suppression.
  const deletes = b.appels.filter(a => a.methode === 'DELETE').length;
  assert.deepEqual(await b.run('nettoyer_run'), { total: 0, introuvable: true });
  assert.equal(b.appels.filter(a => a.methode === 'DELETE').length, deletes);
});

test('nettoyer_run : étiquette absente ou mal formée refusée avant tout appel réseau', async t => {
  for (const run of [undefined, '', '-x', "x'; DROP", 'a'.repeat(41), 'é']) {
    const b = banc(t, { LOT5_NETTOYER_RUN: run });
    await assert.rejects(b.run('nettoyer_run'), /LOT5_NETTOYER_RUN invalide/);
    assert.equal(b.appels.length, 0, String(run));
  }
  assert.throws(() => sqlRetrouverRun("x'"), /invalide/);
});

test('nettoyer_run : chaque ambiguïté ou ligne hors du run est refusée sans suppression', () => {
  const run = 'node-1', em = emailsDuRun(run);
  const E = '0b6a2f5e-1c2d-4e3f-9a8b-7c6d5e4f3a2b', S = '1c7b3a6f-2d3e-4f40-8b9c-8d7e6f5a4b3c', X = '2d8c4b70-3e4f-4051-9cad-9e8f7a6b5c4d';
  const auth = [{ id: E, email: em.etablissement, role: 'ETABLISSEMENT', run, kind: 'LOT5_D5' },
    { id: S, email: em.soignant, role: 'SOIGNANT', run, kind: 'LOT5_D5' }];
  const ok = { etablissements: [{ id: E, test: true, email: em.etablissement }], soignants: [{ id: S, test: true, email: em.soignant }], auth };
  const cible = cibleDepuisRecherche(run, ok);
  assert.deepEqual([cible.etablissement.id, cible.soignant.id, cible.marker], [E, S, 'RECETTE-L5-node-1']);
  const refus = [
    [{ ...ok, etablissements: [ok.etablissements[0], { id: X, test: true, email: em.etablissement }] }, /Plusieurs établissements/],
    [{ ...ok, soignants: [ok.soignants[0], { id: X, test: true, email: em.soignant }] }, /Plusieurs soignants/],
    [{ ...ok, etablissements: [{ ...ok.etablissements[0], test: false }] }, /sans compte TEST/],
    [{ ...ok, soignants: [{ ...ok.soignants[0], test: false }] }, /sans compte TEST/],
    [{ ...ok, etablissements: [{ ...ok.etablissements[0], email: 'autre@example.invalid' }] }, /sans l'adresse du run/],
    [{ ...ok, auth: [...auth, { ...auth[0], id: X }] }, /Plus de deux identités/],
    [{ ...ok, auth: [{ ...auth[0], run: 'autre' }, auth[1]] }, /hors du run/],
    [{ ...ok, auth: [{ ...auth[0], kind: 'AUTRE' }, auth[1]] }, /hors du run/],
    [{ ...ok, auth: [{ ...auth[0], role: 'SOIGNANT' }, auth[1]] }, /hors du run/],
    [{ ...ok, auth: [{ ...auth[0], id: X }, auth[1]] }, /divergents/],
    [{ ...ok, auth: [auth[0], { ...auth[1], id: X }] }, /divergents/],
    [{ ...ok, auth: null }, /illisible/],
  ];
  for (const [ligne, motif] of refus) assert.throws(() => cibleDepuisRecherche(run, ligne), motif);
  assert.throws(() => cibleDepuisRecherche('../x', ok), /invalide/);
});

// MARK: - Liste des tables enfants prouvée par le dump (revue de #1183, m2)

test('GRAPHE_NETTOYAGE = fermeture des clés étrangères du dump vers la cohorte (aucune table oubliée, ordre valide)', () => {
  const dump = readFileSync(new URL('../../supabase/schema/public.sql', import.meta.url), 'utf8');
  assert.deepEqual(GRAPHE_NETTOYAGE, grapheNettoyage(dump),
    'le dump a changé : régénérer GRAPHE_NETTOYAGE (node scripts/mobile/staging-lot5-fixture.mjs graphe)');
  // Contrôle indépendant : toute FK non-CASCADE/non-SET NULL vers une table retenue a son lien dans le graphe.
  const tables = lireGraphe();
  const retenues = new Set([...RACINES_COHORTE, ...tables.map(t => t.table)]);
  const re = /ALTER TABLE ONLY "public"\."(\w+)"\s+ADD CONSTRAINT "\w+" FOREIGN KEY \("(\w+)"\) REFERENCES "public"\."(\w+)"\("id"\)([^;]*);/g;
  let restrictives = 0;
  for (const [, enfant, colonne, parent, reste] of dump.matchAll(re)) {
    if (!retenues.has(parent) || enfant === parent || RACINES_COHORTE.includes(enfant) || /ON DELETE SET (NULL|DEFAULT)/.test(reste)) continue;
    if (!/ON DELETE CASCADE/.test(reste)) restrictives += 1;
    const t = tables.find(x => x.table === enfant);
    assert.ok(t, `${enfant} (FK ${colonne} → ${parent}) absente de l ordre de suppression`);
    assert.ok(t.liens.some(l => l.colonne === colonne && l.parent === parent), `${enfant}.${colonne} → ${parent} absent`);
  }
  assert.ok(restrictives > 50, `FK restrictives relues : ${restrictives}`);
  for (const attendu of ['bulletins_paie', 'cotisations_sociales', 'paiements_soignant', 'paiements_mission', 'factures',
    'factures_honoraires', 'assurances_mission', 'litiges', 'reclamations', 'shift_affectations', 'calendar_events_sync']) {
    assert.ok(retenues.has(attendu), `${attendu} (constat m2 de la revue) retenue`);
  }
  // Parents avant enfants : chaque lien pointe vers une racine ou une table placée plus haut.
  const rang = new Map(tables.map((t, i) => [t.table, i]));
  for (const t of tables) for (const l of t.liens) {
    assert.ok(RACINES_COHORTE.includes(l.parent) || rang.get(l.parent) < rang.get(t.table), `${t.table} avant son parent ${l.parent}`);
  }
  // Le SQL supprime chaque table retenue, enfants d abord, avant les racines.
  const m = manifeste('graphe', new Date('2026-11-24T10:00:00.000Z'));
  const sql = sqlNettoyer(m);
  const positions = tables.map(t => sql.indexOf(NON_SUPPRIMABLES[t.table] ? `-- ${t.table} : non supprimable`
    : t.liens.every(l => l.cascade) ? `-- ${t.table} : supprimée par cascade` : `DELETE FROM public.${t.table} x WHERE`));
  assert.ok(positions.every(p => p > 0), 'une suppression (ou un saut nommé : non supprimable, cascade) par table retenue');
  // Le marqueur de cascade suit le dump : `*` si et seulement si la FK est ON DELETE CASCADE.
  for (const [, enfant, colonne, parent, reste] of dump.matchAll(re)) {
    const t = tables.find(x => x.table === enfant);
    const l = t?.liens.find(x => x.colonne === colonne && x.parent === parent);
    if (l) assert.equal(l.cascade, /ON DELETE CASCADE/.test(reste), `${enfant}.${colonne} → ${parent} : cascade`);
  }
  // Une table toute en cascade n'a de lien que vers des racines ou des tables qui partent avant elle.
  const sansSuppression = tables.filter(t => t.liens.every(l => l.cascade)).map(t => t.table);
  assert.ok(sansSuppression.includes('mission_creneaux') && sansSuppression.includes('documents_soignants'), sansSuppression.join(','));
  for (const t of Object.keys(NON_SUPPRIMABLES)) assert.doesNotMatch(sql, new RegExp(`DELETE FROM public\\.${t}\\b`), `${t} jamais supprimée`);
  for (const t of tables) for (const l of t.liens.filter(l => !RACINES_COHORTE.includes(l.parent) && !l.cascade)) {
    if (NON_SUPPRIMABLES[t.table] || NON_SUPPRIMABLES[l.parent]) continue;
    const parent = tables.find(x => x.table === l.parent);
    if (parent.liens.every(x => x.cascade)) continue; // parent supprimé par cascade, après ses enfants explicites
    assert.ok(positions[rang.get(t.table)] < positions[rang.get(l.parent)], `${t.table} supprimée avant ${l.parent}`);
  }
  assert.ok(Math.max(...positions) < sql.indexOf('DELETE FROM public.missions WHERE ctid'), 'enfants avant les missions');
});

// MARK: - Notifications des missions du run (revue de #1183, m3)

test('notifications des missions du run : comptées et supprimées quel que soit le destinataire', () => {
  const m = manifeste('notif', new Date('2026-11-24T10:00:00.000Z'));
  assert.match(sqlNettoyer(m), /DELETE FROM public\.notifications WHERE destinataire_id = ANY\(v_ids\) OR id_ressource = ANY\(v_missions\)/);
  assert.match(sqlCompter(m), /FROM public\.notifications WHERE destinataire_id = ANY\([^)]*\]::uuid\[\]\) OR id_ressource = ANY\(/);
});

// MARK: - Tour 2 de la revue de #1183

test('m-A : l étiquette est comparée exactement (le run N-1 ne reconnaît pas les missions de N-10)', () => {
  const m = manifeste('N-1', new Date('2026-11-24T10:00:00.000Z'));
  assert.equal(debutIntitule(m.marker), 'RECETTE-L5-N-1 · ');
  assert.ok(m.m1.intitule.startsWith('RECETTE-L5-N-1 · ') && m.m2.intitule.startsWith('RECETTE-L5-N-1 · '));
  assert.ok(!'RECETTE-L5-N-10 · M1 candidature'.startsWith(debutIntitule(m.marker)), 'N-10 exclu');
  for (const sql of [sqlNettoyer(m), sqlCompter(m)]) {
    assert.match(sql, /left\(intitule, 17\)/);
    assert.ok(sql.includes("'RECETTE-L5-N-1 · '"));
    assert.doesNotMatch(sql, /left\(intitule, 14\)/, 'plus de comparaison au seul marqueur');
  }
});

test('m-B : chaque déclencheur de suppression du graphe est classé (non supprimable ou admis), relu dans le dump', () => {
  const dump = readFileSync(new URL('../../supabase/schema/public.sql', import.meta.url), 'utf8');
  const graphe = new Set(lireGraphe().map(t => t.table));
  const declencheurs = [...dump.matchAll(/CREATE OR REPLACE TRIGGER "(\w+)" BEFORE [A-Z ]*DELETE[A-Z ]* ON "public"\."(\w+)"/g)]
    .filter(([, , table]) => graphe.has(table));
  // Admis : laissent passer le contexte du nettoyage (auth.uid() nul, request.jwt.claim.role service_role).
  const ADMIS = new Set(['trg_p0_rbac_api_keys', 'trg_p0_rbac_candidatures', 'trg_p0_rbac_codes_secours', 'trg_p0_rbac_contrats_mission',
    'trg_p0_rbac_contrats_travail', 'trg_bloquer_delete_doc_verifie', 'trg_invalider_preuve_siret_identite_delete',
    'trg_p0_rbac_membres_etablissement', 'trg_dec_verrouiller_planning_candidatures', 'trg_protect_creneaux_facture',
    'trg_p0_rbac_mission_series', 'trg_p0_rbac_presences', 'trg_p0_rbac_qr_codes', 'trg_p0_rbac_factures',
    'trg_p0_rbac_paiements_soignant', 'trg_p0_rbac_partages_rib']);
  const nonSupprimables = new Map(Object.entries(NON_SUPPRIMABLES).map(([t, raison]) => [raison.split(' ')[0], t]));
  for (const [, nom, table] of declencheurs) {
    assert.ok(ADMIS.has(nom) || nonSupprimables.get(nom) === table, `${table} : déclencheur ${nom} non classé`);
  }
  for (const [nom, table] of nonSupprimables) {
    assert.ok(declencheurs.some(([, n, t]) => n === nom && t === table), `${table} : ${nom} absent du dump`);
    assert.ok(graphe.has(table), `${table} : hors du graphe`);
  }
});

test('m-B : résidus non supprimables comptés AVANT, jamais supprimés, reste nettoyé, message exact sans « relancer »', async t => {
  const b = banc(t);
  await b.run('preparer');
  const ID = '3e9d5c81-4f50-4162-8dbe-0f9a8b7c6d5e';
  b.residus = { bulletins_paie: [ID] };
  b.reste = { ...ZERO, missions: 1, soignants: 1, etablissements: 1, auth: 0 };
  await assert.rejects(b.run('nettoyer'), e => /Nettoyage L5 partiel \(run node-1\) : 1 ligne\(s\) non supprimable\(s\) dans bulletins_paie \(trg_bp_no_delete/.test(e.message)
    && e.message.includes(`résidu de test conservé, identifiants bulletins_paie ${ID}`)
    && e.message.includes('etablissements 1, soignants 1, missions 1') && !e.message.includes('nettoyer_run'));
  const requetes = b.appels.map(a => a.corps?.query ?? '').filter(Boolean);
  const iResidus = requetes.findIndex(q => q.includes('AS residus;')), iNettoyage = requetes.findIndex(q => q.includes('$l5_clean$'));
  assert.ok(iResidus >= 0 && iResidus < iNettoyage, 'résidus comptés avant le nettoyage');
  assert.equal(b.nettoye, true, 'le reste de la cohorte est nettoyé');
  assert.throws(() => lireResidus({}), /illisibles/);
  assert.throws(() => lireResidus({ residus: { ...Object.fromEntries(Object.keys(NON_SUPPRIMABLES).map(x => [x, []])), factures: ['pas-un-uuid'] } }), /illisibles \(factures\)/);
  assert.deepEqual(lireResidus({ residus: Object.fromEntries(Object.keys(NON_SUPPRIMABLES).map(x => [x, []])) }), []);
});

test('m-B : SQL des résidus en lecture seule ; suppression ligne à ligne sur refus de clé étrangère seulement, aucun contournement', () => {
  const m = manifeste('residus', new Date('2026-11-24T10:00:00.000Z'));
  const r = sqlResidus(m);
  assert.match(r, /^WITH r_missions AS/);
  assert.doesNotMatch(r, /DELETE|UPDATE|INSERT|BEGIN/);
  for (const t of Object.keys(NON_SUPPRIMABLES)) assert.ok(r.includes(`r_${t} AS (`) && r.includes(`'${t}', (SELECT`), t);
  const clean = sqlNettoyer(m);
  assert.doesNotMatch(clean, /session_replication_role|DISABLE TRIGGER|ALTER TABLE|SET LOCAL ROLE|SET ROLE/);
  assert.doesNotMatch(clean, /EXCEPTION WHEN OTHERS/);
  assert.match(clean, /EXCEPTION WHEN foreign_key_violation THEN/);
});

// MARK: - Second parcours STAGING (25/11/2026) : pré-vol de la session établissement (revue de #1187, m4)

test('pré-vol : les trois lectures, sous le JWT d E1, avec la clé que reçoit l app ; la clé employée est dite, jamais montrée', async t => {
  const b = banc(t, { JOLENE_STAGING_PUBLISHABLE_KEY: 'sb_publishable_CANARIcleDeLApp000000' });
  await b.run('preparer');
  assert.deepEqual(b.sessionEtab.map(x => x.rpc), ['role', 'permissions', 'profil', 'temoin']);
  // Témoin (troisième parcours STAGING) : en-têtes de l'app sans session enregistrée, refus nommé, non bloquant.
  assert.equal(b.sessionEtab[3].auth, 'Bearer sb_publishable_CANARIcleDeLApp000000');
  assert.ok(b.logs.some(l => /^Témoin sans session .*: fn_mes_permissions_etab refusée, HTTP 401, code 42501 \(refus attendu du rôle anon\)\.$/.test(l)));
  assert.ok(b.sessionEtab.every(x => !x.apikey || x.apikey === 'sb_publishable_CANARIcleDeLApp000000'), 'clé de l app');
  assert.equal(b.sessionEtab[0].auth, 'Bearer jwt-CANARI-ETABLISSEMENT', 'JWT d E1');
  assert.deepEqual(b.sessionEtab[1].corps, { p_etablissement_id: null }, 'même corps que SupabaseEtabSessionGateway');
  assert.ok(b.logs.includes("Pré-vol de la session établissement d'E1 : clé de l'app (JOLENE_STAGING_PUBLISHABLE_KEY) (valeur masquée)."));
  assert.doesNotMatch(lignesPubliques(b), /CANARIcleDeLApp/);
  // Sans la clé de l'app : la publishable de la Management API, puis l'anon (dite comme écart).
  assert.match(choisirCleApp({}, { publishable: 'sb_publishable_x', anon: 'a' }).origine, /Management API/);
  assert.match(choisirCleApp({}, { anon: 'a' }).origine, /l'app ne l'emploie pas/);
  assert.match(choisirCleApp({ JOLENE_STAGING_PUBLISHABLE_KEY: 'pas-une-cle' }, { anon: 'a' }).origine, /anon/);
});

test('témoin sans session : acceptation = mécanisme démenti ; refus = statut et code bruts, sans valeur', () => {
  assert.match(decrireTemoinSansSession({ accepte: true }), /ACCEPTÉE — le mécanisme supposé est démenti\.$/);
  assert.match(decrireTemoinSansSession({ echec: { http: 401, code: 'PGRST301' } }), /refusée, HTTP 401, code PGRST301 \(refus attendu du rôle anon\)\.$/);
  assert.match(decrireTemoinSansSession({}), /refusée, HTTP 0 \(refus attendu/);
});

test('pré-vol : un refus arrête la préparation, nomme l écart, son statut HTTP et son code brut', async t => {
  for (const [permissions, motif] of [
    [{ success: false, role: null, permissions: {} }, /refus que l'app aurait aussi subi :\n- fn_mes_permissions_etab : success false/],
    [{ success: true, role: null, etablissement_id: null, permissions: {} }, /refus que l'app aurait aussi subi :\n- fn_mes_permissions_etab : rôle ou établissement absent/],
    [{ success: true, role: 'PROPRIETAIRE', etablissement_id: 'x', permissions: {} }, /périmètre divergent/],
    ['HTTP401', /fn_mes_permissions_etab : HTTP 401, code PGRST301/]]) {
    const b = banc(t);
    b.permissions = permissions;
    await assert.rejects(b.run('preparer'), e => /Session établissement d'E1 refusée par le serveur \(pré-vol, clé /.test(e.message) && motif.test(e.message));
    assert.equal(existsSync(b.env.LOT5_XCUITEST_JSON), false, 'aucune entrée de XCUITest');
  }
});

test('pré-vol : contrôles plus stricts que l app classés à part', () => {
  const doc = { etablissement: { id: 'e1' }, marker: 'M' };
  const ok = { role: { corps: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'e1' } },
    permissions: { corps: { success: true, role: 'PROPRIETAIRE', etablissement_id: 'e1', permissions: { missions: true, candidatures: true, contrats: true, pointage: true, lecture: true } } },
    profil: { corps: { id: 'e1', nom: 'M' } } };
  assert.doesNotThrow(() => controlerSessionEtablissement(doc, ok));
  // Repli sur le rôle signé, permissions absentes, nom : l'app ouvrirait l'espace, le parcours non.
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok,
    role: { echec: { http: 404, code: 'PGRST202', message: 'x' } },
    permissions: { corps: { ...ok.permissions.corps, permissions: {} } }, profil: { corps: { id: 'e1', nom: 'autre' } } }),
  e => !/refus que l'app aurait aussi subi/.test(e.message) && /contrôle plus strict que l'app/.test(e.message)
    && /fn_get_my_role : HTTP 404, code PGRST202/.test(e.message) && /permissions absentes missions, candidatures, contrats, pointage, lecture/.test(e.message)
    && /nom différent du marqueur/.test(e.message));
  // Rôle serveur non établissement : l'app n'ouvre aucun espace (bloquant) ; rôle legacy ETABLISSEMENT : strict seulement.
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, role: { corps: { role: 'INCONNU' } } }), /refus que l'app aurait aussi subi :\n- fn_get_my_role : rôle "INCONNU"/);
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, role: { corps: { role: 'ETABLISSEMENT', etablissement_id: null } } }),
    e => /contrôle plus strict/.test(e.message) && !/refus que l'app/.test(e.message));
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, permissions: { corps: { ...ok.permissions.corps, role: 'PLANNING' } } }), /rôle d'équipe non servi "PLANNING"/);
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, profil: { echec: { http: 500, code: '42883', message: 'y' } } }), /fn_mon_etablissement_complet : HTTP 500, code 42883/);
});

test('pré-vol (revue de #1187, r2) : un refus en HTTP 200 recopie le message de la fonction, masqué et tronqué', () => {
  const doc = { etablissement: { id: 'e1' }, marker: 'M' };
  const ok = { role: { corps: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'e1' } },
    permissions: { corps: { success: true, role: 'PROPRIETAIRE', etablissement_id: 'e1', permissions: { missions: true, candidatures: true, contrats: true, pointage: true, lecture: true } } },
    profil: { corps: { id: 'e1', nom: 'M' } } };
  const uuid = '3f2b9c1e-8a4d-4c2e-9b7a-1d2e3f4a5b6c';
  // Jeton et clé fabriqués à l'exécution : aucun littéral en forme de secret dans les sources (scanner de secrets).
  const segment = (objet) => Buffer.from(JSON.stringify(objet)).toString('base64url');
  const jwt = [segment({ alg: 'HS256' }), segment({ sub: 'x' }), Buffer.from('signature').toString('base64url')].join('.');
  const cle = ['sb', 'publishable', 'abcdefghijklmnop0123'].join('_');
  const brut = `Compte inactif pour ${uuid} (membre-1@example.invalid) jeton ${jwt} clé ${cle}`;
  const message = (corps) => { try { controlerSessionEtablissement(doc, { ...ok, permissions: { corps } }); } catch (e) { return e.message; } return ''; };
  const m = message({ success: false, error: brut });
  assert.match(m, /refus que l'app aurait aussi subi :\n- fn_mes_permissions_etab : success false, HTTP 200, message serveur « Compte inactif pour <uuid> \(<adresse>\) jeton <jeton> clé <clé> »/);
  for (const secret of [uuid, 'example.invalid', jwt, jwt.slice(0, 3), cle, cle.slice(0, 15), '3f2b9c1e']) assert.ok(!m.includes(secret), `jamais ${secret}`);
  // `{error}` seul (sans success) : même statut et même message ; un corps sans message le dit.
  assert.match(message({ error: 'Etablissement introuvable' }), /success null, HTTP 200, message serveur « Etablissement introuvable »/);
  assert.match(message({ success: false }), /success false, HTTP 200, sans message serveur/);
  // Masquage avant troncature : 160 caractères au plus, jamais un fragment d'uuid.
  const long = messageServeur(`${'a'.repeat(150)} ${uuid}`);
  assert.equal(long, `${'a'.repeat(150)} <uuid>`);
  assert.equal(messageServeur('b'.repeat(200)), `${'b'.repeat(160)}…`);
  assert.equal(messageServeur(`${'c'.repeat(155)} ${uuid}`).includes('3f2b'), false);
  // Profil et rôle en `{error}` HTTP 200 : nommés avec le message.
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, profil: { corps: { error: `Etablissement ${uuid} introuvable` } } }),
    /fn_mon_etablissement_complet : HTTP 200, message serveur « Etablissement <uuid> introuvable »/);
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, role: { corps: { error: 'Non authentifié' } } }),
    e => /contrôle plus strict/.test(e.message) && /fn_get_my_role : HTTP 200, message serveur « Non authentifié »/.test(e.message));
  // Un échec HTTP recopie aussi le message masqué.
  assert.throws(() => controlerSessionEtablissement(doc, { ...ok, profil: { echec: { http: 400, code: 'P0001', message: `refus ${uuid}` } } }),
    e => /HTTP 400, code P0001 — refus <uuid>/.test(e.message) && !e.message.includes(uuid));
});
