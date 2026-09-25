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
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, app_metadata: { role: 'SOIGNANT' } });
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

async function connexion(page: Page, email: string, password: string) {
  await page.goto('/connexion');
  await page.locator('input[type=email]').fill(email);
  await page.locator('input[type=password]').first().fill(password);
  await page.getByTestId('login-submit').click();
  await expect(page).toHaveURL(/\/soignant\//);
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  await page.route('**/*', route => {
    const host = new URL(route.request().url()).hostname;
    if (host === 'flripxtsyegjshnhzjkz.supabase.co') throw new Error('Bundle configuré contre production : recette refusée.');
    return ['127.0.0.1', 'mejpriaetwgtcstbgfid.supabase.co'].includes(host) ? route.continue() : route.abort();
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
    await expect(page).toHaveURL('http://127.0.0.1:8891/');
    const { data: profil, error } = await admin.from('soignants').select('nom,email,supprime_le').eq('id', fixture.id).single();
    expect(error).toBeNull(); expect(profil?.nom).toBe('Supprimé');
    expect(profil?.email).toMatch(/@supprime\.jolene\.app$/); expect(profil?.supprime_le).toBeTruthy();
    const login = await client().auth.signInWithPassword({ email: fixture.email, password: fixture.password });
    expect(login.error).not.toBeNull(); expect(login.data.session).toBeNull();
    await page.goto('/soignant/mon-compte');
    await expect(page).toHaveURL(/\/connexion/);
  } finally { await fixture.cleanup(); }
});
