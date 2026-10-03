import { test, expect, type Page, type Request } from '@playwright/test';
import { creerMissionSimulee, ids } from './helpers/recette-complete-mission';

// Interface réelle, réponses exclusivement simulées. Aucun compte, fournisseur
// ni paiement réel ; la panne SQL de la CI reste une preuve séparée.
function lectureCritique(request: Request) {
  const url = new URL(request.url());
  return request.method() === 'GET' && url.pathname === '/rest/v1/missions'
    && url.searchParams.get('id') === `eq.${ids.mission}`
    && (url.searchParams.get('select') ?? '').includes('choix_contrat_soignant');
}

async function deuxRendus(page: Page) {
  await page.evaluate(() => new Promise<void>(resolve => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
  }));
}

test.beforeEach(async ({ context, page }) => {
  await context.addInitScript(() => {
    if (!Reflect.deleteProperty(Object.getPrototypeOf(navigator), 'serviceWorker') || 'serviceWorker' in navigator)
      throw new Error('La simulation exige un navigateur sans Service Worker.');
  });
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
});

for (const scenario of ['role-tardif', 'erreur-et-reprise', 'delai-et-annulation'] as const) {
  test(`mission terminée — ${scenario}`, async ({ context, page }, info) => {
    const simulation = creerMissionSimulee();
    const { state } = simulation;
    state.mission.statut = 'TERMINEE';
    state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = 'LIBERAL';
    await simulation.installer(context, 'SOIGNANT');
    await page.route('**/rest/v1/rpc/fn_score_etab_public', route => route.fulfill({ json: null }));
    await page.route('**/rest/v1/rpc/fn_user_id_pour_etablissement', route => route.fulfill({ json: ids.etablissement }));
    await page.route('**/rest/v1/notations_missions?**', route => route.fulfill({ json: null }));

    let lectures = 0;
    let interruptions = 0;
    let refuser = scenario === 'erreur-et-reprise';
    let roleLibere = scenario !== 'role-tardif';
    const liberations: (() => void)[] = [];
    const rolesEnAttente: Promise<void>[] = [];
    const rolesTermines: Promise<void>[] = [];
    const rolesRecus: Promise<Error | null>[] = [];
    page.on('requestfailed', request => { if (lectureCritique(request)) interruptions += 1; });
    page.on('response', response => {
      if (response.request().method() === 'POST' && new URL(response.url()).pathname === '/rest/v1/rpc/fn_get_my_role')
        rolesRecus.push(response.finished());
    });
    const attendreRolesRecus = async () => {
      await expect.poll(() => rolesRecus.length).toBe(rolesTermines.length);
      expect(await Promise.all(rolesRecus)).toEqual(rolesRecus.map(() => null));
      await deuxRendus(page);
    };

    await page.route('**/rest/v1/rpc/fn_get_my_role', async route => {
      if (route.request().method() !== 'POST') return route.fallback();
      if (!roleLibere) {
        const attente = new Promise<void>(resolve => liberations.push(resolve));
        rolesEnAttente.push(attente);
        await attente;
      }
      const termine = route.fulfill({ json: { role: 'SOIGNANT', etablissement_id: null } });
      rolesTermines.push(termine);
      await termine;
    });
    await page.route('**/rest/v1/missions?**', async route => {
      if (!lectureCritique(route.request())) return route.fallback();
      lectures += 1;
      if (refuser) return route.fulfill({ status: 503, json: { message: 'Panne synthétique de lecture' } });
      if (scenario === 'delai-et-annulation' && lectures === 1) {
        await new Promise<void>(resolve => liberations.push(resolve));
        // Le client doit déjà avoir annulé. Libération du harnais uniquement.
        await route.abort('timedout').catch(() => {});
        return;
      }
      return route.fallback();
    });

    const titre = page.getByRole('heading', { level: 1, name: state.mission.intitule, exact: true });
    const noter = page.getByRole('button', { name: "Noter l'établissement", exact: true });
    const chemin = `/soignant/missions/${ids.mission}`;
    try {
      if (scenario === 'delai-et-annulation') await page.clock.install({ time: new Date('2026-09-30T10:00:00Z') });
      else await page.clock.setFixedTime(new Date('2026-09-30T10:00:00Z'));
      await page.goto(chemin);

      if (scenario === 'role-tardif') {
        await expect(titre).toBeVisible();
        await expect(noter).toBeVisible();
        expect(lectures).toBe(1);
        expect(rolesEnAttente.length).toBeGreaterThan(0);
        roleLibere = true;
        for (const liberer of liberations.splice(0)) liberer();
        await Promise.all(rolesEnAttente);
        await expect.poll(() => rolesTermines.length).toBeGreaterThanOrEqual(rolesEnAttente.length);
        await Promise.all(rolesTermines);
        await attendreRolesRecus();
        await expect(titre).toBeVisible();
        await expect(noter).toBeVisible();
        expect(lectures, 'La revalidation du même rôle ne recharge pas une mission déjà affichée.').toBe(1);
      } else if (scenario === 'erreur-et-reprise') {
        await expect(page.getByRole('heading', { name: 'Impossible de charger la mission', exact: true })).toBeVisible();
        expect(lectures).toBe(2);
        await expect(noter).toHaveCount(0);
        await page.screenshot({ path: info.outputPath('mission-erreur-visible.png') });
        refuser = false;
        await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
        await expect(titre).toBeVisible();
        await expect(noter).toBeVisible();
        expect(lectures).toBe(3);
      } else {
        await expect.poll(() => lectures).toBe(1);
        await page.clock.fastForward(8_100);
        await expect.poll(() => interruptions).toBe(1);
        await page.clock.fastForward(400);
        await expect(titre).toBeVisible();
        await expect(noter).toBeVisible();
        expect(lectures).toBe(2);
        await page.clock.resume();
      }

      await noter.scrollIntoViewIfNeeded();
      await page.screenshot({ path: info.outputPath(`mission-${scenario}-reussie.png`) });
      const avantReload = lectures;
      await page.reload();
      await expect(titre).toBeVisible();
      await expect(noter).toBeVisible();
      await attendreRolesRecus();
      expect(lectures).toBe(avantReload + 1);
      expect(state.unknown).toEqual([]);
      expect(state.errors).toEqual([]);
      expect(state.external).toEqual([]);
      expect(state.signatures).toHaveLength(0);
      expect(state.sms).toHaveLength(0);
      expect(state.emails).toHaveLength(0);
    } finally {
      for (const liberer of liberations) liberer();
      await info.attach('preuve-chargement-mission', { contentType: 'application/json', body: JSON.stringify({
        scenario, lectures, interruptions, refuser, rolesAttendus: rolesEnAttente.length,
        rolesTermines: rolesTermines.length, unknown: state.unknown, errors: state.errors, external: state.external,
      }) });
    }
  });
}
