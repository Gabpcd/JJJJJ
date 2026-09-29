import { expect, test } from '@playwright/test';
import { simulerSoignant, entrer, preuve } from './helpers/recette-complete-soignant';

const actif = { statut: 'COMPLET', onboarding_complete: true, charges_enabled: true, payouts_enabled: true, iban_last4: '1234' };

test.afterEach(async ({ page }) => {
  await expect(page.locator('main')).not.toContainText('NaN');
});

test('paiement salarié : employeur et bulletin distincts, sans activation Stripe', async ({ page }, info) => {
  const s = await simulerSoignant(page); s.profile.type_exercice = 'SALARIE';
  await entrer(page, 'connexion'); await page.goto('/soignant/stripe-connect');
  await expect(page.getByRole('heading', { name: 'Mode salarié' })).toBeVisible();
  await expect(page.getByText('il ne prouve pas que le virement a été reçu.', { exact: false })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Connecter mon compte bancaire' })).toHaveCount(0);
  expect(s.calls.filter(c => c.name.startsWith('stripe-connect-'))).toEqual([]);
  await preuve(page, 'salarie-paiement-employeur-bulletin-distinct', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});

test('Stripe indisponible : aucun faux compte à créer, réessai puis statut connecté persistant', async ({ page }, info) => {
  const s = await simulerSoignant(page); Object.assign(s.profile, { type_exercice: 'LIBERAL', est_compte_test: false });
  s.failures.add('stripe-connect-status');
  await entrer(page, 'connexion'); await page.goto('/soignant/stripe-connect');
  const alert = page.getByRole('alert').filter({ hasText: 'Statut de paiement indisponible' });
  await expect(alert).toBeVisible();
  await expect(page.getByRole('button', { name: 'Connecter mon compte bancaire' })).toHaveCount(0);
  await expect(page.getByText('Compte connecté', { exact: true })).toHaveCount(0);
  await alert.getByRole('button', { name: 'Réessayer' }).click();
  await expect(alert.getByRole('button', { name: 'Réessayer' })).toBeEnabled();
  await expect(page.getByText('Statut actualisé', { exact: true })).toHaveCount(0);
  await preuve(page, 'statut-stripe-indisponible', info, true);
  s.failures.delete('stripe-connect-status'); s.overrides.set('stripe-connect-status', actif);
  await alert.getByRole('button', { name: 'Réessayer' }).click();
  await expect(page.getByText('Compte connecté', { exact: true })).toBeVisible();
  await expect(alert).toHaveCount(0);
  expect(s.calls.some(c => c.name === 'stripe-connect-status' && c.url.endsWith('?force=true'))).toBe(true);
  await page.reload(); await expect(page.getByText('Compte connecté', { exact: true })).toBeVisible();
  await preuve(page, 'statut-stripe-repris', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});

test('échec d’actualisation : le statut prêt disparaît jusqu’à une réponse valide', async ({ page }, info) => {
  const s = await simulerSoignant(page); Object.assign(s.profile, { type_exercice: 'LIBERAL', est_compte_test: false });
  s.overrides.set('stripe-connect-status', actif);
  await entrer(page, 'connexion'); await page.goto('/soignant/stripe-connect');
  await expect(page.getByText('Compte connecté', { exact: true })).toBeVisible();
  s.failures.add('stripe-connect-status'); await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Statut de paiement indisponible' })).toBeVisible();
  await expect(page.getByText('Compte connecté', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Statut actualisé', { exact: true })).toHaveCount(0);
  s.failures.delete('stripe-connect-status'); s.overrides.set('stripe-connect-status', { statut: 'SUSPENDU', onboarding_complete: false });
  await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page.getByText('Compte suspendu', { exact: true })).toBeVisible();
  await preuve(page, 'statut-stripe-suspendu-apres-reprise', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});

test('retour Stripe invalide : aucune confirmation de mise à jour réussie', async ({ page }, info) => {
  const s = await simulerSoignant(page); Object.assign(s.profile, { type_exercice: 'LIBERAL', est_compte_test: false });
  s.overrides.set('stripe-connect-status', { ...actif, onboarding_complete: false });
  await entrer(page, 'connexion'); await page.goto('/soignant/stripe-connect?success=true');
  await expect(page.getByRole('alert').filter({ hasText: 'Statut de paiement indisponible' })).toBeVisible();
  await expect(page.getByText('Compte connecté', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Statut mis à jour !', { exact: true })).toHaveCount(0);
  await preuve(page, 'statut-stripe-incoherent-refuse', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});

for (const resultat of ['erreur', 'suspension'] as const) {
  test(`retour Stripe après ${resultat} : une seule lecture forcée, sans cache concurrent`, async ({ page }, info) => {
    const s = await simulerSoignant(page); Object.assign(s.profile, { type_exercice: 'LIBERAL', est_compte_test: false });
    await entrer(page, 'connexion');
    const lectures: boolean[] = [];
    await page.route('**/functions/v1/stripe-connect-status*', async route => {
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 200, headers });
      const force = new URL(route.request().url()).searchParams.get('force') === 'true';
      lectures.push(force);
      if (!force) return route.fulfill({ headers, json: { ...actif, cached: true } });
      return resultat === 'erreur'
        ? route.fulfill({ status: 503, headers, json: { error: 'STRIPE_STATUS_UNAVAILABLE' } })
        : route.fulfill({ headers, json: { statut: 'SUSPENDU', onboarding_complete: false, charges_enabled: false, payouts_enabled: false, cached: false } });
    });
    await page.goto('/soignant/stripe-connect?success=true');
    if (resultat === 'erreur') await expect(page.getByRole('alert').filter({ hasText: 'Statut de paiement indisponible' })).toBeVisible();
    else await expect(page.getByText('Compte suspendu', { exact: true })).toBeVisible();
    await preuve(page, `retour-stripe-lecture-unique-${resultat}`, info, true);
    expect(lectures).toEqual([true]);
    await expect(page.getByText('Compte connecté', { exact: true })).toHaveCount(0);
    expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
  });
}

test('revenus invalides ou en panne : aucune somme inventée, réessai avec les montants reçus', async ({ page }, info) => {
  const s = await simulerSoignant(page); Object.assign(s.profile, { type_exercice: 'LIBERAL', est_compte_test: false });
  s.overrides.set('stripe-connect-status', actif);
  s.overrides.set('fn_mes_revenus_connect', { total_recu: 0 });
  await entrer(page, 'connexion'); await page.goto('/soignant/stripe-connect');
  const indisponible = page.getByRole('status').filter({ hasText: 'Tes revenus sont temporairement indisponibles' });
  await expect(indisponible).toBeVisible();
  await expect(page.getByText('Ce mois', { exact: true })).toHaveCount(0);
  s.failures.add('fn_mes_revenus_connect');
  await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Actualiser', exact: true })).toBeEnabled();
  await expect(indisponible).toBeVisible();
  await preuve(page, 'revenus-indisponibles-sans-faux-zero', info, true);
  s.failures.delete('fn_mes_revenus_connect');
  s.overrides.set('fn_mes_revenus_connect', { mois_en_cours: 123.45, total: 456.78, en_attente: 67.89, stripe_connect_actif: true });
  await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
  await expect(indisponible).toHaveCount(0);
  for (const montant of [/123,45\s*€/, /456,78\s*€/, /67,89\s*€/]) await expect(page.locator('main')).toContainText(montant);
  await preuve(page, 'revenus-repris-montants-confirmes', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});
