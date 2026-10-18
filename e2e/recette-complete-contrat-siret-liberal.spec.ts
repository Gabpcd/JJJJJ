import { createHash } from 'node:crypto';
import { test, expect } from '@playwright/test';
import { creerMissionSimulee, ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// Simulation frontend sur les cinq projets de playwright.recette-complete.config.ts.
// Le générateur réel est exercé séparément par contrat-original-acces.test.ts.
// Ici l'API, le stockage et les profils sont fictifs ; aucun SMS ou backend réel.
const template = '<article><h2>Contrat libéral synthétique</h2><p>SIRET du soignant : {{soignant_siret}}</p><p>SIRET établissement : {{etablissement_siret}}</p></article>';
const rendered = '<article><h2>Contrat libéral synthétique</h2><p>SIRET du soignant : 11111111111111</p><p>SIRET établissement : 22222222222222</p></article>';
const renderedHash = createHash('sha256').update(rendered).digest('hex');

for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`CONTRAT SIRET LIBÉRAL — ${role} : aperçu canonique puis original figé après changement du profil`, async ({ context, page }, info) => {
    const { state, installer } = creerMissionSimulee();
    state.contratCree = true;
    Object.assign(state.mission, { statut: 'ASSIGNEE', type_contrat_applique: 'LIBERAL', soignant_assigne_id: ids.soignant });
    Object.assign(state.soignant, { siret_liberal: '11111111111111', siret: '99999999999999' });
    state.etablissement.siret = '22222222222222';
    Object.assign(state.contrat, { type_contrat: 'LIBERAL', contenu_html: null, storage_path: null,
      hash_document: null, contenu_html_rendu_le: null });
    await installer(context, role);
    // CSS de police remplacé localement ; toute autre origine reste refusée.
    await context.route('https://fonts.googleapis.com/**', async route => {
      if (route.request().method() !== 'GET') return route.fallback();
      return route.fulfill({ contentType: 'text/css', body: '' });
    });
    await page.clock.setFixedTime(new Date(now));
    let templateCourant = template;
    let autoriserRendu = false;
    const generations: unknown[] = [];
    const requetesRefusees: string[] = [];
    const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };
    await context.route('**/rest/v1/templates_contrat*', async route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ json: {}, headers });
      const url = new URL(req.url());
      if (req.method() !== 'GET' || req.headers().authorization !== `Bearer simulation-mission-${role}`
        || url.searchParams.get('select') !== 'contenu_html'
        || url.searchParams.get('type_contrat') !== 'eq.LIBERAL'
        || url.searchParams.get('est_actif') !== 'eq.true' || [...url.searchParams].length !== 3) {
        requetesRefusees.push(`${req.method()} ${url.pathname} ${url.search}`);
        return route.fulfill({ status: 501, json: { error: 'Lecture de modèle non prévue' }, headers });
      }
      return route.fulfill({ json: { contenu_html: templateCourant }, headers });
    });
    await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ json: {}, headers });
      const body = req.postDataJSON();
      if (req.method() !== 'POST' || req.headers().authorization !== `Bearer simulation-mission-${role}`
        || JSON.stringify(body) !== JSON.stringify({ contrat_id: ids.contrat })) {
        requetesRefusees.push(`${req.method()} ${new URL(req.url()).pathname}`);
        return route.fulfill({ status: 501, json: { error: 'Rendu non prévu' }, headers });
      }
      generations.push(body);
      if (!autoriserRendu) return route.fulfill({ status: 503, json: { error: 'Rendu momentanément indisponible (simulation)' }, headers });
      Object.assign(state.contrat, { contenu_html: rendered, storage_path: 'simulation/contrat-liberal-siret.html',
        hash_document: renderedHash, contenu_html_rendu_le: now });
      return route.fulfill({ json: { success: true }, headers });
    });

    try {
      await page.goto(`/contrat/${ids.contrat}`);
      // Le vrai fallback frontend doit utiliser siret_liberal, même si une autre
      // propriété siret existe. L'aperçu reste impropre à une signature SMS.
      await expect(page.getByRole('heading', { name: 'Contrat libéral synthétique', exact: true })).toBeVisible();
      await expect(page.getByText('SIRET du soignant : 11111111111111', { exact: true })).toBeVisible();
      await expect(page.getByText('SIRET établissement : 22222222222222', { exact: true })).toBeVisible();
      await expect(page.getByText(/99999999999999/)).toHaveCount(0);
      await expect(page.getByRole('alert')).toContainText('Le document contractuel final n’a pas pu être préparé.');
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeDisabled();
      expect(generations).toHaveLength(1);
      expect(state.contrat.storage_path).toBeNull();
      await preuveMission(page, info, role + '-siret-apercu-non-signable');

      autoriserRendu = true;
      await page.reload();
      await expect(page.getByText('SIRET du soignant : 11111111111111', { exact: true })).toBeVisible();
      await expect(page.getByText(/Document officiel figé le/)).toBeVisible();
      await expect(page.getByRole('alert')).toHaveCount(0);
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeEnabled();
      expect(generations).toHaveLength(2);
      const frozen = structuredClone(state.contrat);

      // Changement du profil/modèle simulé au serveur, puis vraie reprise UI.
      Object.assign(state.soignant, { siret_liberal: '33333333333333' });
      state.etablissement.siret = '44444444444444';
      templateCourant = '<article><h2>Modèle futur</h2><p>SIRET changé : {{soignant_siret}}</p></article>';
      await page.reload();
      await expect(page.getByRole('heading', { name: 'Contrat libéral synthétique', exact: true })).toBeVisible();
      await expect(page.getByText('SIRET du soignant : 11111111111111', { exact: true })).toBeVisible();
      await expect(page.getByText('SIRET établissement : 22222222222222', { exact: true })).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Modèle futur', exact: true })).toHaveCount(0);
      await expect(page.getByText(/33333333333333|44444444444444|99999999999999/)).toHaveCount(0);
      expect(generations).toHaveLength(2);
      expect(state.contrat).toEqual(frozen);

      const downloadPromise = page.waitForEvent('download');
      await page.getByRole('button', { name: 'Télécharger le contrat', exact: true }).click();
      const download = await downloadPromise;
      expect(download.suggestedFilename()).toBe('SIM-2026-0001.html');
      const stream = await download.createReadStream();
      const chunks: Buffer[] = [];
      for await (const chunk of stream!) chunks.push(chunk);
      const bytes = Buffer.concat(chunks).toString('utf8');
      expect(bytes).toContain(rendered);
      expect(bytes).not.toMatch(/33333333333333|44444444444444|99999999999999|Modèle futur/);
      await preuveMission(page, info, role + '-siret-original-apres-reload');
      expect(state.sms).toEqual([]);
      expect(state.signatures).toEqual([]);
      expect(state.calls.filter(call => ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp'].includes(call.name))).toEqual([]);
      expect(requetesRefusees).toEqual([]);
      expect(state.unknown).toEqual([]);
      expect(state.external).toEqual([]);
      expect(state.errors).toEqual([]);
    } finally {
      await info.attach('journal-siret-simulation', { body: JSON.stringify({ generations, requetesRefusees,
        calls: state.calls, unknown: state.unknown, external: state.external, errors: state.errors }), contentType: 'application/json' });
    }
  });
}
