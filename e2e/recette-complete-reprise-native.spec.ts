import { expect, test, type Page } from '@playwright/test';
import { simulerBridgeNatif } from './helpers/native-bridge-simule';
import { simulerSoignant, entrer as entrerSoignant, preuve, ids as soignantIds } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtab, ids as etabIds } from './helpers/recette-complete-etablissement';

async function reprendre(page: Page, minutes: number) {
  const now = await page.evaluate(() => Date.now());
  await page.evaluate(() => (window as any).__native.emit('App', 'appStateChange', { isActive: false }));
  await page.clock.setFixedTime(now + minutes * 60_000);
  await page.evaluate(() => (window as any).__native.emit('App', 'appStateChange', { isActive: true }));
}

test.afterEach(async ({ page }, info) => { await info.attach('native-bridge', { body: JSON.stringify(await page.evaluate(() => ({ url: location.href, calls: (window as any).__native?.calls, listeners: (window as any).__native?.listeners, background: Object.fromEntries(Object.entries(localStorage).filter(([key]) => key.startsWith('jolene.native'))), platform: (window as any).Capacitor?.getPlatform() }))), contentType: 'application/json' }); });

for (const role of ['soignant', 'etablissement'] as const) {
  for (const entree of ['connexion', 'inscription'] as const) {
    test(`${role} après ${entree} : reprise courte, longue et notification`, async ({ page }, info) => {
      await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
      const state = role === 'soignant' ? await simulerSoignant(page, entree === 'inscription' ? 'minimal' : 'complet') : (await simulerEtablissement(page, entree === 'inscription' ? 'minimal' : 'complet')).etat;
      // The registration RPC is a server acknowledgment, not merely OS consent.
      await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => route.fulfill({ json: null }));
      if (role === 'soignant') await entrerSoignant(page, entree); else await entrerEtab(page, entree);
      await expect(page).toHaveURL(new RegExp(`/${role}/(?:tableau-de-bord|recherche-missions)`));
      await page.goto(`/${role}/messagerie`);
      await expect(page.locator('main')).toBeVisible();
      await expect.poll(() => page.evaluate(() => (window as any).__native.calls.filter((name: string) => name === 'PushNotifications.register').length)).toBeGreaterThan(0);
      await reprendre(page, 2); await page.waitForTimeout(500);
      await expect(page).toHaveURL(new RegExp(`/${role}/messagerie`));
      await reprendre(page, 31); await expect(page).toHaveURL(new RegExp(`/${role}/tableau-de-bord`));
      expect(await page.evaluate(() => Object.keys(localStorage).some(key => key.endsWith('-auth-token') && !!localStorage.getItem(key)))).toBe(true);
      await expect(page.locator('main').getByRole('heading', { level: 1 })).toBeVisible();
      await preuve(page, `${role}-${entree}-reprise-dashboard`, info, true);
      await page.evaluate(() => (window as any).__native.emit('PushNotifications', 'pushNotificationActionPerformed', { notification: { data: { lien: location.pathname.replace('tableau-de-bord', 'messagerie') } } }));
      await expect(page).toHaveURL(new RegExp(`/${role}/messagerie`));
      const user = role === 'soignant' ? soignantIds.user : etabIds.user;
      const retour = await page.evaluate(() => Date.now());
      await page.clock.setFixedTime(retour - 86400_000);
      await page.evaluate(() => (window as any).__native.emit('App', 'appStateChange', { isActive: false }));
      expect(await page.evaluate(({ user }) => Number(localStorage.getItem(`jolene.native.background.${user}`)), { user })).toBe(retour - 86400_000);
      await page.clock.setFixedTime(retour);
      await page.reload(); await expect(page).toHaveURL(new RegExp(`/${role}/tableau-de-bord`));
      const errors = 'errors' in state ? state.errors : state.erreurs;
      const unknown = 'unknown' in state ? state.unknown : state.inconnues;
      expect(errors).toEqual([]); expect(unknown).toEqual([]);
    });
  }
}

test('mise à jour store visible, refermable et ouvrable depuis le compte', async ({ page }, info) => {
  await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios', 2);
  const state = await simulerSoignant(page);
  await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => route.fulfill({ json: null }));
  await entrerSoignant(page, 'connexion');
  const banner = page.getByRole('complementary', { name: 'Mise à jour de Jolene' });
  await expect(banner).toBeVisible();
  expect(await banner.evaluate(el => el.getBoundingClientRect().right <= innerWidth)).toBe(true);
  const messageConnexion = page.getByRole('region', { name: 'Notifications', exact: true }).getByRole('status').filter({ hasText: 'Connexion réussie' });
  await expect(messageConnexion).toBeVisible();
  await expect.poll(async () => {
    const message = await messageConnexion.boundingBox();
    const panneau = await banner.boundingBox();
    return message && panneau ? message.y + message.height <= panneau.y : false;
  }).toBe(true);
  await preuve(page, 'mise-a-jour-store-visible', info, true);
  await banner.getByRole('button', { name: 'Mettre à jour', exact: true }).click();
  expect(await page.evaluate(() => (window as any).__native.storeOpened)).toBe(true);
  await banner.getByRole('button', { name: 'Me le rappeler plus tard' }).click(); await expect(banner).toBeHidden();
  await page.goto('/soignant/mon-compte');
  await banner.getByRole('button', { name: 'Me le rappeler plus tard' }).click();
  await expect(banner).toBeHidden();
  await page.getByRole('button', { name: 'Vérifier les mises à jour' }).click(); await expect(banner).toBeVisible();
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});

test('notifications autorisées mais inscription serveur en panne : erreur visible puis réessai', async ({ page }, info) => {
  await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
  const state = await simulerSoignant(page);
  let disponible = false;
  let inscriptions = 0;
  await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => {
    inscriptions++;
    return disponible ? route.fulfill({ json: null }) : route.fulfill({ status: 503, json: { message: 'Indisponibilité simulée du registre push' } });
  });
  await entrerSoignant(page, 'connexion');
  await page.goto('/soignant/parametres/notifications');
  const statut = page.getByTestId('native-push-permission-status');
  await expect(statut).toContainText('cet appareil n’a pas pu être enregistré');
  await expect(statut).not.toContainText('Les notifications sont autorisées sur cet appareil.');
  await preuve(page, 'notifications-inscription-serveur-en-panne', info, true);
  disponible = true;
  const avant = inscriptions;
  await statut.getByRole('button', { name: 'Activer sur cet appareil', exact: true }).click();
  await expect(statut).toContainText('Les notifications sont autorisées sur cet appareil.');
  expect(inscriptions).toBeGreaterThan(avant);
  await expect(statut.getByRole('button', { name: 'Activer sur cet appareil', exact: true })).toHaveCount(0);
  await preuve(page, 'notifications-inscription-serveur-reprise', info, true);
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});
