import { randomUUID } from 'node:crypto';
import { test, expect, type Page } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';

const url = process.env.STAGING_SUPABASE_URL;
const anon = process.env.STAGING_SUPABASE_ANON_KEY;
const service = process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
if (url !== 'https://mejpriaetwgtcstbgfid.supabase.co' || !anon || !service) {
  throw new Error('Recette comptes réservée au staging, accès réels obligatoires.');
}
const options = { auth: { persistSession: false, autoRefreshToken: false }, global: {
  fetch: (input: RequestInfo | URL, init?: RequestInit) => fetch(input, { ...init, signal: AbortSignal.timeout(20_000) }),
} };
const admin = createClient(url, service, options);
const client = () => createClient(url!, anon!, options);

async function compteJetable() {
  const email = `playwright-test-national-${randomUUID()}@example.invalid`;
  const password = `Jolene!${randomUUID()}aA1`;
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, app_metadata: { role: 'SOIGNANT', is_test_playwright: true } });
  if (error || !data.user) throw new Error('Création fixture Auth refusée : ' + error?.message);
  const id = data.user.id;
  const cleanup = async () => {
    // Jamais un compte fixe ; UUID capturé à la création et marqueur test contrôlé.
    const { data: row, error: readError } = await admin.from('soignants').select('est_compte_test').eq('id', id).maybeSingle();
    expect(readError).toBeNull();
    if (row) {
      expect(row.est_compte_test).toBe(true);
      const { error: removeProfile } = await admin.from('soignants').delete().eq('id', id);
      expect(removeProfile).toBeNull();
    }
    const { error: removeAuth } = await admin.auth.admin.deleteUser(id);
    expect(removeAuth).toBeNull();
  };
  const { error: profileError } = await admin.from('soignants').insert({ id, email, prenom: 'Recette', nom: 'Jetable', profession: 'AS', type_exercice: 'SALARIE', est_compte_test: true });
  if (profileError) { await admin.auth.admin.deleteUser(id); throw new Error('Profil fixture refusé : ' + profileError.message); }
  return { id, email, password, cleanup };
}

async function etablissementJetable() {
  const email = `playwright-test-national-etab-${randomUUID()}@example.invalid`;
  const password = `Jolene!${randomUUID()}aA1`;
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true,
    app_metadata: { role: 'ADMIN_ETABLISSEMENT', is_test_playwright: true } });
  if (error || !data.user) throw new Error('Création fixture Auth établissement refusée : ' + error?.message);
  const id = data.user.id;
  const cleanup = async () => {
    const { data: row, error: readError } = await admin.from('etablissements').select('est_compte_test').eq('id', id).maybeSingle();
    expect(readError).toBeNull();
    if (row) {
      expect(row.est_compte_test).toBe(true);
      const { error: removeMembership } = await admin.from('membres_etablissement').delete().eq('etablissement_id', id).eq('user_id', id);
      expect(removeMembership).toBeNull();
      const { error: removeProfile } = await admin.from('etablissements').delete().eq('id', id);
      expect(removeProfile).toBeNull();
    }
    const { error: removeAuth } = await admin.auth.admin.deleteUser(id);
    expect(removeAuth).toBeNull();
  };
  try {
    const { error: metadataError } = await admin.auth.admin.updateUserById(id, {
      app_metadata: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: id, is_test_playwright: true },
    });
    if (metadataError) throw metadataError;
    const siret = '99' + BigInt('0x' + id.replaceAll('-', '').slice(0, 12)).toString().padStart(12, '0').slice(-12);
    const { error: profileError } = await admin.from('etablissements').insert({
      id, nom: 'RECETTE COMPTE JETABLE', siret, type: 'CLINIQUE_PRIVEE', email_contact: email,
      adresse_rue: 'Adresse fictive de recette', adresse_ville: 'Paris', adresse_code_postal: '75001',
      est_compte_test: true, peut_publier_missions: false,
    });
    if (profileError) throw profileError;
    const owner = await admin.rpc('fn_init_proprietaire_etab', { p_etablissement_id: id, p_user_id: id });
    if (owner.error || owner.data?.success !== true) throw new Error('Propriétaire de fixture refusé.');
  } catch (error) { await cleanup(); throw error; }
  return { id, email, password, cleanup };
}

async function connexion(page: Page, email: string, password: string, role: 'soignant' | 'etablissement' = 'soignant') {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill(email);
  await page.locator('input[type=password]').first().fill(password);
  await page.getByTestId('login-submit').click();
  await expect(page).toHaveURL(new RegExp(`/${role}/`));
}

test.beforeAll(async ({ request }) => {
  const preflight = await request.fetch(`${url}/functions/v1/delete-account`, {
    method: 'OPTIONS', headers: {
      Origin: 'http://localhost:5173',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'authorization,apikey,content-type',
    },
  });
  expect(preflight.status(), 'Le service réel doit autoriser cette origine de recette').toBe(204);
  expect(preflight.headers()['access-control-allow-origin']).toBe('http://localhost:5173');
});

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  await page.route('**/*', route => {
    const host = new URL(route.request().url()).hostname;
    if (host === 'flripxtsyegjshnhzjkz.supabase.co') throw new Error('Bundle configuré contre production : recette refusée.');
    return ['localhost', 'mejpriaetwgtcstbgfid.supabase.co'].includes(host) ? route.continue() : route.abort();
  });
});

test('mot de passe : refus ancien erroné, modification UI réelle, ancien refusé et nouveau accepté', async ({ page }) => {
  const fixture = await compteJetable();
  try {
    await connexion(page, fixture.email, fixture.password);
    await page.goto('/soignant/mon-compte');
    const form = page.locator('form').filter({ has: page.getByRole('button', { name: 'Modifier mon mot de passe' }) });
    const fields = form.locator('input');
    const nouveau = `Modifie!${randomUUID()}bB2`;
    await fields.nth(0).fill('AncienIncorrect!123');
    await fields.nth(1).fill(nouveau); await fields.nth(2).fill(nouveau);
    await form.getByRole('button', { name: 'Modifier mon mot de passe' }).click();
    await expect(page.getByText('Ancien mot de passe incorrect.', { exact: true })).toBeVisible();
    await fields.nth(0).fill(fixture.password);
    await form.getByRole('button', { name: 'Modifier mon mot de passe' }).click();
    await expect(page.getByText('Mot de passe modifié avec succès.', { exact: true })).toBeVisible();
    await expect(fields.nth(0)).toHaveValue('');
    const ancien = await client().auth.signInWithPassword({ email: fixture.email, password: fixture.password });
    expect(ancien.error?.code).toBe('invalid_credentials');
    const nouveauClient = client();
    const nouvelle = await nouveauClient.auth.signInWithPassword({ email: fixture.email, password: nouveau });
    expect(nouvelle.error).toBeNull(); expect(nouvelle.data.user?.id).toBe(fixture.id);
    await nouveauClient.auth.signOut();
  } finally { await fixture.cleanup(); }
});

test('suppression : confirmation UI → delete-account réel → profil anonymisé, session inutilisable', async ({ page }) => {
  // Le staging peut encore porter la fonction pré-correction. Refuser la
  // recette si une tentative PSC indépendante existe, même expirée.
  const { count, error: pscError } = await admin.from('psc_auth_sessions').select('state', { head: true, count: 'exact' });
  expect(pscError).toBeNull();
  expect(count, 'Aucune authentification PSC indépendante ne peut être interrompue').toBe(0);
  const fixture = await compteJetable();
  try {
    await test.step('Connexion du compte jetable', () => connexion(page, fixture.email, fixture.password));
    await test.step('Accès à la confidentialité', () => page.goto('/soignant/profil?tab=confidentialite#suppression-compte'));
    await expect(page.getByRole('heading', { name: 'Suppression de compte', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toBeDisabled();
    await page.getByPlaceholder('Tape SUPPRIMER').fill('SUPPRIMER');
    const reponse = page.waitForResponse(r => r.url().endsWith('/functions/v1/delete-account') && r.request().method() === 'POST', { timeout: 30_000 });
    await page.getByRole('button', { name: 'Supprimer définitivement' }).click();
    const resultat = await reponse;
    expect(resultat.status()).toBe(200);
    expect(await resultat.json()).toMatchObject({ success: true, auth_deleted: true });
    await expect(page).toHaveURL('http://localhost:5173/');
    const { data: profil, error } = await admin.from('soignants').select('nom,email,supprime_le').eq('id', fixture.id).single();
    expect(error).toBeNull(); expect(profil?.nom).toBe('Supprimé');
    expect(profil?.email).toMatch(/@supprime\.jolene\.app$/); expect(profil?.supprime_le).toBeTruthy();
    const login = await client().auth.signInWithPassword({ email: fixture.email, password: fixture.password });
    expect(login.error).not.toBeNull(); expect(login.data.session).toBeNull();
    await page.goto('/soignant/mon-compte');
    await expect(page).toHaveURL(/\/connexion/);
  } finally { await fixture.cleanup(); }
});

test('établissement : suppression confirmée dans l’interface, anonymisation et accès révoqué', async ({ page }) => {
  const fixture = await etablissementJetable();
  try {
    await connexion(page, fixture.email, fixture.password, 'etablissement');
    await page.goto('/etablissement/parametres?tab=securite#suppression-compte');
    await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
    const confirmation = page.getByRole('button', { name: 'Confirmer la suppression', exact: true });
    await expect(confirmation).toBeDisabled();
    await page.locator('#etablissement-confirmation-suppression').fill('SUPPRIMER');
    const response = page.waitForResponse(r => r.url().endsWith('/functions/v1/delete-account') && r.request().method() === 'POST', { timeout: 30_000 });
    await confirmation.click();
    const result = await response;
    expect(result.status()).toBe(200);
    expect(await result.json()).toMatchObject({ success: true, auth_deleted: true });
    await expect(page).toHaveURL('http://localhost:5173/');
    const { data: profil, error } = await admin.from('etablissements').select('nom,email_contact,supprime_le,peut_publier_missions').eq('id', fixture.id).single();
    expect(error).toBeNull(); expect(profil?.nom).toBe('Établissement supprimé');
    expect(profil?.email_contact).toMatch(/@supprime\.jolene\.app$/);
    expect(profil?.supprime_le).toBeTruthy(); expect(profil?.peut_publier_missions).toBe(false);
    const login = await client().auth.signInWithPassword({ email: fixture.email, password: fixture.password });
    expect(login.error).not.toBeNull(); expect(login.data.session).toBeNull();
    await page.goto('/etablissement/parametres');
    await expect(page).toHaveURL(/\/connexion/);
  } finally { await fixture.cleanup(); }
});

test('compte suspendu : le refus Data API conserve l’identité Auth et ne prétend pas anonymiser', async ({ request }) => {
  const fixture = await compteJetable();
  try {
    const { data: session, error: loginError } = await client().auth.signInWithPassword({ email: fixture.email, password: fixture.password });
    expect(loginError).toBeNull(); expect(session.session?.access_token).toBeTruthy();
    // Reproduit la suspension sur cette fixture uniquement, après émission du
    // jeton : un supprime_le présent ne prouve pas l’anonymisation des données.
    const { error: suspendError } = await admin.from('soignants').update({ supprime_le: new Date().toISOString() }).eq('id', fixture.id);
    expect(suspendError).toBeNull();
    const response = await request.post(`${url}/functions/v1/delete-account`, {
      headers: { Authorization: `Bearer ${session.session!.access_token}`, apikey: anon! }, data: {},
    });
    // Le pre-request PostgREST interdit les RPC aux comptes suspendus, même
    // avec un JWT antérieur valide. L’Edge doit respecter ce refus et ne pas
    // confondre supprime_le (suspension) avec une anonymisation déjà terminée.
    expect(response.status()).toBe(409);
    expect(await response.json()).toEqual({ error: 'Compte suspendu, supprimé ou désactivé' });
    const { data: profile, error: readError } = await admin.from('soignants').select('nom,email').eq('id', fixture.id).single();
    expect(readError).toBeNull(); expect(profile?.nom).toBe('Jetable');
    expect(profile?.email).toBe(fixture.email);
    const confirmation = await admin.rpc('fn_anonymisation_compte_confirmee', { p_utilisateur_id: fixture.id, p_type_profil: 'SOIGNANT' });
    expect(confirmation.error).toBeNull(); expect(confirmation.data).toBe(false);
    const identity = await admin.auth.admin.getUserById(fixture.id);
    expect(identity.error).toBeNull(); expect(identity.data.user?.email).toBe(fixture.email);
    const blockedRead = await request.get(`${url}/rest/v1/soignants?select=id&id=eq.${fixture.id}`, {
      headers: { Authorization: `Bearer ${session.session!.access_token}`, apikey: anon! },
    });
    expect(blockedRead.status()).toBe(403);
  } finally { await fixture.cleanup(); }
});

// Recette réelle, sans qualification, prime, mission ni appel fournisseur.
// La seule attribution est déclenchée par le navigateur avec le JWT du filleul.
test('parrainage : attribution UI réelle, reconnexion et unicité persistée', async ({ page }, testInfo) => {
  test.setTimeout(120_000);
  const run = randomUUID();
  const fixtures: { id: string; email: string; password: string; role: 'parrain' | 'filleul' }[] = [];
  const intentions: { role: 'parrain' | 'filleul'; email: string; etat: 'intention' | 'cree' | 'ambigu' }[] = [];
  let attributionDemandee = false;
  let attributionTerminee = false;
  const parrainagesCaptures = new Set<string>();
  const signalsCaptures = new Set<string>();
  const journal = async (etat: string) => testInfo.attach(`parrainage-${etat}`, {
    body: JSON.stringify({ version: 1, cible: 'mejpriaetwgtcstbgfid', run, etat,
      intentions, comptes: fixtures.map(({ id, role }) => ({ id, role })),
      parrainages: [...parrainagesCaptures], signaux: [...signalsCaptures] }),
    contentType: 'application/json',
  });
  const verifier: (condition: unknown, code: string) => asserts condition = (condition, code) => {
    if (!condition) throw new Error(`Recette parrainage : ${code}`);
  };
  const creer = async (role: 'parrain' | 'filleul') => {
    const email = `playwright-test-parrainage-${randomUUID()}@example.invalid`;
    const password = `Jolene!${randomUUID()}aA1`;
    const intention = { role, email, etat: 'intention' as 'intention' | 'cree' | 'ambigu' };
    intentions.push(intention);
    await journal('intention-auth'); // Aucun mot de passe ; avant l'appel distant.
    let response;
    try {
      response = await admin.auth.admin.createUser({ email, password, email_confirm: true,
        app_metadata: { role: 'SOIGNANT', is_test_playwright: true, recette_parrainage_run: run, recette_parrainage_fixture: role } });
    } catch {
      intention.etat = 'ambigu';
      throw new Error('Recette parrainage : creation_auth_ambigue_reconciliation_requise');
    }
    if (response.error || !response.data.user) {
      intention.etat = 'ambigu';
      throw new Error('Recette parrainage : creation_auth_non_confirmee_reconciliation_requise');
    }
    const fixture = { id: response.data.user.id, email, password, role };
    fixtures.push(fixture); // Capturer l'identifiant avant toute autre écriture.
    intention.etat = 'cree';
    await journal('auth-cree');
    const inserted = await admin.from('soignants').insert({ id: fixture.id, email, prenom: 'Recette', nom: 'Parrainage',
      profession: 'AS', type_exercice: 'SALARIE', est_compte_test: true,
      identite_verifiee: false, diplome_verifie: false, rpps_verifie: false, tous_documents_valides: false });
    verifier(!inserted.error, 'creation_profil_refusee');
    return fixture;
  };
  const relations = async () => {
    const filtre = fixtures.flatMap(({ id }) => [`parrain_id.eq.${id}`, `filleul_id.eq.${id}`]).join(',');
    const result = await admin.from('parrainages').select('id,parrain_id,filleul_id,statut,prime_versee_le,valide_le,commission_cumulee_filleul').or(filtre);
    verifier(!result.error && result.data, 'lecture_parrainages_refusee');
    for (const row of result.data!) parrainagesCaptures.add(row.id);
    return result.data!;
  };
  const profil = async (id: string) => {
    const result = await admin.from('soignants').select('id,code_parrainage,parraine_par,est_compte_test,identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides').eq('id', id).maybeSingle();
    verifier(!result.error, 'lecture_profil_refusee');
    return result.data;
  };
  const verifierProfilTest = (row: Awaited<ReturnType<typeof profil>>) => {
    verifier(row?.est_compte_test === true, 'cohorte_test_absente');
    verifier(row.identite_verifiee === false && row.diplome_verifie === false
      && row.rpps_verifie === false && row.tous_documents_valides === false, 'qualification_inattendue');
  };
  const nettoyer = async () => {
    verifier(intentions.every(intention => intention.etat === 'cree'), 'creation_auth_ambigue_reconciliation_requise');
    if (!fixtures.length) return;
    // Un transport interrompu ne prouve pas le rollback serveur. Conserver les
    // UUID pour réconciliation, sans annoncer un nettoyage sûr avant résolution.
    verifier(!attributionDemandee || attributionTerminee, 'attribution_ambigue_reconciliation_requise');
    for (const fixture of fixtures) {
      const auth = await admin.auth.admin.getUserById(fixture.id);
      const metadata = auth.data.user?.app_metadata;
      verifier(!auth.error && auth.data.user?.id === fixture.id && auth.data.user.email === fixture.email
        && metadata?.role === 'SOIGNANT' && metadata.is_test_playwright === true
        && metadata.recette_parrainage_run === run && metadata.recette_parrainage_fixture === fixture.role, 'propriete_privee_non_confirmee');
      const row = await profil(fixture.id);
      if (row) verifierProfilTest(row);
    }
    const rows = await relations();
    const parrain = fixtures.find(f => f.role === 'parrain');
    const filleul = fixtures.find(f => f.role === 'filleul');
    for (const row of rows) {
      verifier(row.parrain_id === parrain?.id && row.filleul_id === filleul?.id, 'relation_etrangere_refus_nettoyage');
      verifier(row.statut === 'EN_ATTENTE' && row.prime_versee_le === null && row.valide_le === null
        && Number(row.commission_cumulee_filleul) === 0, 'parrainage_qualifie_refus_nettoyage');
      const signals = await admin.from('parrainage_fraude_signals').select('id').eq('parrainage_id', row.id);
      verifier(!signals.error, 'lecture_signaux_refusee');
      for (const signal of signals.data ?? []) signalsCaptures.add(signal.id);
    }
    await journal('avant-nettoyage');
    const ids = fixtures.map(f => f.id);
    // Contrôler les journaux de transport sans lire leurs contenus ni supprimer
    // une preuve d'envoi. Les UUID ciblés appartiennent exclusivement à ce run.
    for (const table of ['emails_envoyes', 'sms_envoyes']) {
      const result = await admin.from(table).select('id', { count: 'exact', head: true }).in('destinataire_id', ids);
      verifier(!result.error && result.count === 0, 'transport_inattendu_conserver_preuves');
    }
    const queue = await admin.from('email_queue').select('id,statut,envoye').in('destinataire_id', ids);
    verifier(!queue.error && (queue.data ?? []).every(row => row.statut === 'EN_ATTENTE' && row.envoye === false), 'file_email_inattendue');
    const notifications = await admin.from('notifications').select('id,email_envoye,push_envoyee').in('destinataire_id', ids);
    verifier(!notifications.error && (notifications.data ?? []).every(row => !row.email_envoye && !row.push_envoyee), 'notification_envoyee_inattendue');
    for (const table of ['email_queue', 'notifications']) {
      const removed = await admin.from(table).delete().in('destinataire_id', ids);
      verifier(!removed.error, 'suppression_notification_refusee');
    }
    for (const row of rows) {
      const removed = await admin.from('parrainages').delete().eq('id', row.id).eq('parrain_id', row.parrain_id).eq('filleul_id', row.filleul_id);
      verifier(!removed.error, 'suppression_parrainage_refusee');
    }
    // FK LIVE : parrainage_fraude_signals.parrainage_id → parrainages ON DELETE CASCADE.
    if (parrainagesCaptures.size) {
      const remaining = await admin.from('parrainage_fraude_signals').select('id', { count: 'exact', head: true }).in('parrainage_id', [...parrainagesCaptures]);
      verifier(!remaining.error && remaining.count === 0, 'signaux_orphelins');
    }
    verifier((await relations()).length === 0, 'parrainages_residuels');
    for (const fixture of [...fixtures].reverse()) {
      const removed = await admin.from('soignants').delete().eq('id', fixture.id).eq('est_compte_test', true);
      verifier(!removed.error, 'suppression_profil_refusee');
      const authRemoved = await admin.auth.admin.deleteUser(fixture.id);
      verifier(!authRemoved.error, 'suppression_auth_refusee');
      verifier((await profil(fixture.id)) === null, 'profil_residuel');
      const authAbsent = await admin.auth.admin.getUserById(fixture.id);
      verifier(authAbsent.error?.status === 404 && !authAbsent.data.user, 'auth_residuel_ou_absence_non_confirmee');
    }
    for (const [table, colonne] of [['notifications', 'destinataire_id'], ['email_queue', 'destinataire_id'],
      ['preferences_notifications', 'utilisateur_id'], ['preferences_notifications_par_evenement', 'utilisateur_id']]) {
      const remaining = await admin.from(table).select('*', { count: 'exact', head: true }).in(colonne, ids);
      verifier(!remaining.error && remaining.count === 0, 'residus_apres_nettoyage');
    }
    await journal('nettoyage-verifie');
  };
  // Aucun Edge Function ne peut être déclenché dans ce scénario, même sur staging.
  await page.route('**/functions/v1/**', route => route.abort());
  page.on('request', request => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === '/rest/v1/rpc/fn_appliquer_parrainage') attributionDemandee = true;
  });
  let erreurParcours: unknown;
  let erreurNettoyage: unknown;
  try {
    const parrain = await creer('parrain');
    const filleul = await creer('filleul');
    verifierProfilTest(await profil(parrain.id)); verifierProfilTest(await profil(filleul.id));
    expect(await relations()).toHaveLength(0);
    const code = (await profil(parrain.id))?.code_parrainage;
    verifier(typeof code === 'string' && /^[A-Z0-9-]{4,16}$/.test(code), 'code_absent');
    await page.goto(`/inscription/soignant?ref=${encodeURIComponent(code)}`);
    // Observer l'effet du vrai point d'entrée, sans injecter l'attribution.
    await expect.poll(() => page.evaluate(() => sessionStorage.getItem('jolene.parrainage_code'))).toBe(code);
    const reponsePromise = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === '/rest/v1/rpc/fn_appliquer_parrainage').catch(() => null);
    await connexion(page, filleul.email, filleul.password);
    const reponse = await reponsePromise;
    verifier(reponse, 'reponse_attribution_absente');
    const resultat = await reponse.json();
    attributionTerminee = true;
    expect(reponse.ok()).toBe(true); expect(resultat.success).toBe(true);
    await expect(page.getByText('Code de parrainage enregistré.', { exact: true })).toBeVisible();
    await page.goto('/soignant/mon-compte');
    await page.getByRole('button', { name: 'Se déconnecter', exact: true }).last().click();
    await expect(page).toHaveURL(/\/(connexion)?$/);
    await connexion(page, filleul.email, filleul.password);
    const rows = await relations();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ parrain_id: parrain.id, filleul_id: filleul.id, statut: 'EN_ATTENTE', prime_versee_le: null, valide_le: null, commission_cumulee_filleul: 0 });
    const filleulApres = await profil(filleul.id);
    verifierProfilTest(filleulApres); verifierProfilTest(await profil(parrain.id));
    // Ne pas remplacer cette assertion par une correction via service_role :
    // elle détecte notamment un trigger qui annulerait silencieusement le lien.
    expect(filleulApres?.parraine_par).toBe(parrain.id);
  } catch (error) { erreurParcours = error; }
  finally {
    try { await page.close(); }
    catch (error) { erreurParcours = new AggregateError([erreurParcours, error].filter(Boolean), 'Fermeture navigateur incomplète.'); }
    try { await nettoyer(); }
    catch (error) { erreurNettoyage = error; await journal('nettoyage-incomplet-reconciliation-requise'); }
  }
  if (erreurParcours || erreurNettoyage) {
    throw new AggregateError([erreurParcours, erreurNettoyage].filter(Boolean), 'Recette parrainage non validée ; consulter les erreurs et le journal de nettoyage.');
  }
});
