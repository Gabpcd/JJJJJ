import { expect, test } from '@playwright/test';
import { simulerBridgeNatif } from './helpers/native-bridge-simule';
import { simulerSoignant, entrer as entrerSoignant, preuve } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, stabiliserLectures } from './helpers/recette-complete-etablissement';

for (const role of ['soignant', 'etablissement'] as const) {
  test(`${role} : activation volontaire des notifications puis reprise et rechargement`, async ({ page }, info) => {
    const android = info.project.name === 'android';
    await simulerBridgeNatif(page, android ? 'android' : 'ios');
    const state = role === 'soignant' ? await simulerSoignant(page) : (await simulerEtablissement(page)).etat;
    // Android may allow another permission request after an initial refusal.
    // Only an explicit request changes this fixture's permission to granted.
    await page.addInitScript(({ initial }) => {
      const w = window as any;
      w.__native.permission = sessionStorage.getItem('recette-push-permission') || initial;
      const original = w.Capacitor.nativePromise;
      w.Capacitor.nativePromise = async (plugin: string, method: string, args: unknown) => {
        if (plugin === 'PushNotifications' && method === 'requestPermissions') {
          w.__native.permission = 'granted';
          sessionStorage.setItem('recette-push-permission', 'granted');
        }
        return original(plugin, method, args);
      };
    }, { initial: android ? 'prompt-with-rationale' : 'prompt' });
    const inscriptions: Record<string, unknown>[] = [];
    await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => {
      inscriptions.push(route.request().postDataJSON());
      return route.fulfill({ json: null });
    });
    if (role === 'soignant') await entrerSoignant(page, 'connexion'); else await entrerEtablissement(page, 'connexion');
    await stabiliserLectures(page);
    await page.goto(`/${role}/parametres/notifications`);
    const statut = page.getByTestId('native-push-permission-status');
    await expect(statut).toContainText('le téléphone doit encore autoriser les notifications');
    await page.evaluate(() => (window as any).__native.emit('App', 'appStateChange', { isActive: true }));
    await expect.poll(() => page.evaluate(() => (window as any).__native.calls.filter((call: string) => call === 'PushNotifications.checkPermissions').length)).toBeGreaterThan(1);
    expect(await page.evaluate(() => (window as any).__native.calls.includes('PushNotifications.requestPermissions'))).toBe(false);
    expect(inscriptions).toEqual([]);
    await preuve(page, `${role}-avant-demande-notifications`, info, true);

    await statut.getByRole('button', { name: 'Activer sur cet appareil', exact: true }).click();
    await expect(statut).toContainText('Les notifications sont autorisées sur cet appareil.');
    expect(await page.evaluate(() => (window as any).__native.calls.filter((call: string) => call === 'PushNotifications.requestPermissions').length)).toBe(1);
    expect(inscriptions).toEqual([{ p_token: 'native-fixture-token', p_plateforme: android ? 'ANDROID' : 'IOS' }]);
    await expect(statut.getByRole('button', { name: 'Activer sur cet appareil', exact: true })).toHaveCount(0);
    await preuve(page, `${role}-notifications-activees`, info, true);

    await page.evaluate(() => (window as any).__native.emit('App', 'appStateChange', { isActive: true }));
    await expect(statut).toContainText('Les notifications sont autorisées sur cet appareil.');
    await stabiliserLectures(page);
    await page.reload();
    await expect(statut).toContainText('Les notifications sont autorisées sur cet appareil.');
    expect(await page.evaluate(() => (window as any).__native.calls.includes('PushNotifications.requestPermissions'))).toBe(false);
    await expect.poll(() => inscriptions.length).toBe(2);
    await preuve(page, `${role}-notifications-apres-rechargement`, info, true);
    expect('errors' in state ? state.errors : state.erreurs).toEqual([]);
    expect('unknown' in state ? state.unknown : state.inconnues).toEqual([]);
    await info.attach('inscriptions-push-simulees', { body: JSON.stringify(inscriptions), contentType: 'application/json' });
  });
}
