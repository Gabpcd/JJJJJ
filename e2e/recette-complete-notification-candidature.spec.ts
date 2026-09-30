import { expect, test, type Page } from '@playwright/test';
import { creerMissionSimulee, ids, now } from './helpers/recette-complete-mission';
import { simulerBridgeNatif } from './helpers/native-bridge-simule';

// Frontend with a fictional backend and native bridge; no APNs/FCM, SQL or
// delivery to a physical device is exercised by these scenarios.
const path = `/etablissement/missions/${ids.mission}`;
const retour = `/connexion?return=${encodeURIComponent(path)}`;
const rh = '71000000-0000-4000-8000-000000000099';
const candidature = { id: ids.candidature, mission_id: ids.mission, soignant_id: ids.soignant,
  message: 'Candidature reçue pendant mon absence', statut: 'EN_ATTENTE', cree_le: now };

test.afterEach(async ({ page }, info) => {
  await info.attach('route-finale', { body: page.url(), contentType: 'text/plain' });
});

async function cliquerPush(page: Page) {
  await page.evaluate(({ path, ids }) => (window as any).__native.emit('PushNotifications', 'pushNotificationActionPerformed', {
    notification: { data: { type_evenement: 'CANDIDATURE_RECUE', lien: path, mission_id: ids.mission, candidature_id: ids.candidature } },
  }), { path, ids });
}

for (const membreRH of [false, true]) {
  for (const scenario of ['fiche', 'connexion', 'retention'] as const) {
    const expiree = scenario !== 'fiche';
    test(`${membreRH ? 'RH' : 'principal'} : candidature ${scenario === 'retention' ? 'retenue avant connexion' : expiree ? 'après connexion et reload' : 'sur la même fiche native'}`, async ({ context, page }, info) => {
      const simulation = creerMissionSimulee();
      const { state } = simulation;
      const consoleErrors: string[] = [];
      const requetesEchouees: { url: string; erreur: string | null }[] = [];
      page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
      page.on('requestfailed', request => requetesEchouees.push({ url: request.url(), erreur: request.failure()?.errorText ?? null }));
      await simulation.installer(context, 'ADMIN_ETABLISSEMENT');
      await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
      await page.route('https://js.stripe.com/**', route => route.fulfill({ contentType: 'application/javascript', body: 'window.Stripe = function(){ return {}; };' }));
      await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
      const user = { id: membreRH ? rh : ids.etablissement, email: 'recette-notification@example.invalid',
        aud: 'authenticated', role: 'authenticated', email_confirmed_at: now,
        app_metadata: scenario === 'retention' ? {} : { role: 'ADMIN_ETABLISSEMENT', etablissement_id: ids.etablissement }, user_metadata: {}, identities: [] };
      const session = { user, token_type: 'bearer', access_token: 'recette-notification-fictive', refresh_token: 'recette-refresh-fictif', expires_in: 86400, expires_at: 1799999999 };
      await page.addInitScript(({ session, expiree }) => {
        sessionStorage.removeItem('sb-127-auth-token');
        if (!expiree || localStorage.getItem('recette.notification.connectee') === 'oui') {
          localStorage.setItem('sb-127-auth-token', JSON.stringify(session));
        } else localStorage.removeItem('sb-127-auth-token');
        localStorage.setItem('jolene_native_notice_dismissed', 'true');
      }, { session, expiree });
      await page.route('**/auth/v1/user', route => route.fulfill({ json: user }));
      await page.route('**/auth/v1/token?*', route => route.fulfill({ json: session }));
      await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => route.fulfill({ json: null }));
      await page.route('**/rest/v1/rpc/fn_audit_connexion', route => route.fulfill({ json: null }));
      let libererRole = () => {};
      if (scenario === 'retention') {
        const attenteRole = new Promise<void>(resolve => { libererRole = resolve; });
        await page.route('**/rest/v1/rpc/fn_get_my_role', async route => {
          await attenteRole;
          await route.fulfill({ json: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: ids.etablissement } });
        });
        // Same retained-event contract as Capacitor iOS/Android: a tap received
        // before Auth restoration is delivered when its listener is installed.
        await page.addInitScript(({ path, ids }) => {
          const bridge = (window as any).Capacitor;
          const ajouter = bridge.nativeCallback;
          let retenue = true;
          bridge.nativeCallback = (plugin: string, method: string, options: any, callback: Function) => {
            const id = ajouter(plugin, method, options, callback);
            if (retenue && plugin === 'PushNotifications' && options.eventName === 'pushNotificationActionPerformed') {
              retenue = false;
              queueMicrotask(() => callback({ notification: { data: { lien: path, type_evenement: 'CANDIDATURE_RECUE', mission_id: ids.mission } } }));
            }
            return id;
          };
        }, { path, ids });
      }
      // The API is on a distinct local port: PostgREST exposes Content-Range
      // through CORS. A missing expose header would make an exact count null.
      await page.route(/\/rest\/v1\/(candidatures|notifications)\?/, async route => {
        if (route.request().method() !== 'HEAD') return route.fallback();
        const name = new URL(route.request().url()).pathname.split('/').pop()!;
        state.calls.push({ role: 'ADMIN_ETABLISSEMENT', name, method: 'HEAD', body: null });
        const count = name === 'candidatures' && state.candidature ? 1 : 0;
        return route.fulfill({ status: 200, body: '', headers: {
          'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range',
          'content-range': `0-${Math.max(0, count - 1)}/${count}`,
        } });
      });
      await page.route('**/rest/v1/rpc/fn_mes_permissions_etab', route => route.fulfill({ json: {
        success: true, role: membreRH ? 'RH' : 'PROPRIETAIRE', etablissement_id: ids.etablissement,
        permissions: { lecture: true, lecture_missions: true, lecture_candidatures: true, missions: true, candidatures: true, rh: true, gerer_equipe: !membreRH, supprimer_compte: !membreRH },
      } }));
      await page.clock.setFixedTime(new Date(now));
      if (expiree) state.candidature = { ...candidature };
      await page.goto(scenario === 'retention' ? '/connexion' : path);
      if (expiree) {
        await expect(page).toHaveURL(new RegExp('/connexion'));
        await expect(page.getByRole('button', { name: 'Se connecter', exact: true })).toBeVisible();
        const destinationConnexion = scenario === 'retention' ? '/connexion' : retour;
        expect(new URL(page.url()).pathname + new URL(page.url()).search).toBe(destinationConnexion);
        await info.attach('avant-connexion', { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
        // The destination lives in the URL and survives a fresh login page.
        await page.waitForLoadState('networkidle');
        await page.reload();
        expect(new URL(page.url()).pathname + new URL(page.url()).search).toBe(destinationConnexion);
        await page.getByLabel('Email', { exact: true }).fill(user.email);
        await page.getByLabel('Mot de passe', { exact: true }).fill('MotDePasseRecette123!');
        await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
        await page.evaluate(() => localStorage.setItem('recette.notification.connectee', 'oui'));
        if (scenario === 'retention') {
          await expect(page).toHaveURL(new RegExp(`${path}$`));
          // Complete role lookup only after the retained tap has navigated.
          libererRole();
        }
      }
      await expect(page).toHaveURL(new RegExp(`${path}$`));
      await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
      await expect.poll(() => page.evaluate(() => (window as any).__native.listeners.some((l: any) => l.event === 'pushNotificationActionPerformed'))).toBe(true);
      if (!expiree) {
        await expect(page.getByText('En attente de candidats', { exact: true })).toBeVisible();
        await info.attach('avant-notification', { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
        const avant = await page.evaluate(() => history.length);
        state.candidature = { ...candidature };
        await cliquerPush(page);
        expect(await page.evaluate(() => history.length)).toBe(avant);
      }
      await expect(page.getByRole('heading', { name: 'Candidatures (1)', exact: true })).toBeVisible();
      await expect(page.getByText(/Candidature reçue pendant mon absence/)).toBeVisible();
      await expect(page.getByRole('button', { name: 'Accepter cette candidature', exact: true })).toBeVisible();
      await page.waitForLoadState('networkidle');
      await page.reload();
      await expect(page).toHaveURL(new RegExp(`${path}$`));
      await expect(page.getByText(/Candidature reçue pendant mon absence/)).toBeVisible();
      await page.waitForLoadState('networkidle');
      await info.attach('apres-notification', { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
      await page.screenshot({ path: info.outputPath('candidature.png'), fullPage: true, scale: 'css', animations: 'disabled' });
      await info.attach('preuve', { body: JSON.stringify({ url: page.url(), acteur: user.id, membreRH, expiree,
        lecturesCandidatures: state.calls.filter(c => c.name === 'candidatures').length,
        scenario, consoleErrors, requetesEchouees,
        mutationsCandidatures: state.calls.filter(c => c.name.startsWith('fn_traiter_candidature')).length }), contentType: 'application/json' });
      expect(state.calls.filter(c => c.name.startsWith('fn_traiter_candidature'))).toEqual([]);
      expect(state.sms).toEqual([]); expect(state.emails).toEqual([]);
      expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
      expect(consoleErrors).toEqual([]);
    });
  }
}
