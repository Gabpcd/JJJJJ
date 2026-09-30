import { test, expect } from '@playwright/test';
import { creerMissionSimulee, ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// Simulation UI stricte : réponses locales uniquement, aucun original personnel ni backend réel.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`CONTRAT ORIGINAL — ${role} : lecture, téléchargement, absence, refus et reprise`, async ({ context, page }, info) => {
    const { state, installer } = creerMissionSimulee();
    state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
    Object.assign(state.contrat, { statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true,
      contenu_html: '<article><h2>Original synthétique signé</h2><p>Texte historique : 10h/jour (L3121-18)</p></article>' });
    const original = { ...state.contrat };
    await installer(context, role); await page.clock.setFixedTime(new Date(now));
    let renduAutorise = false, lectureAutorisee = true;
    const generations: unknown[] = [];
    await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
      if (route.request().method() === 'OPTIONS') return route.fulfill({ json: {}, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
      generations.push(route.request().postDataJSON());
      if (renduAutorise) Object.assign(state.contrat, { storage_path: 'simulation/nouveau-original.html', hash_document: 'b'.repeat(64), contenu_html_rendu_le: now,
        contenu_html: '<article><h2>Nouveau document autorisé</h2><p>Rendu synthétique figé.</p></article>' });
      await route.fulfill({ status: renduAutorise ? 200 : 403, json: renduAutorise ? { success: true } : { error: 'Accès au contrat refusé.' },
        headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    });
    await context.route('**/rest/v1/contrats_mission*', async route => {
      if (lectureAutorisee) return route.fallback();
      return route.fulfill({ status: 403, json: { message: 'Accès refusé' }, headers: { 'access-control-allow-origin': '*' } });
    });
    try {
      await page.goto(`/contrat/${ids.contrat}`);
      await expect(page.getByRole('heading', { name: 'Original synthétique signé', exact: true })).toBeVisible();
      await expect(page.getByText('Texte historique : 10h/jour (L3121-18)', { exact: true })).toBeVisible();
      await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
      const downloadPromise = page.waitForEvent('download');
      await page.getByRole('button', { name: 'Télécharger le contrat', exact: true }).click();
      const download = await downloadPromise; expect(download.suggestedFilename()).toBe('SIM-2026-0001.html');
      const stream = await download.createReadStream(); const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(chunk);
      const bytes = Buffer.concat(chunks).toString('utf8'); expect(bytes).toContain(original.contenu_html);
      expect(bytes).not.toContain('Nouveau document autorisé');
      await page.reload(); await expect(page.getByRole('heading', { name: 'Original synthétique signé', exact: true })).toBeVisible();
      expect(generations).toHaveLength(0); expect(state.contrat).toEqual(original);
      await preuveMission(page, info, role+'-original-apres-reload');
      // Une seule partie a signé : même interdiction de reconstitution automatique.
      Object.assign(state.contrat, { statut: role === 'SOIGNANT' ? 'SIGNE_ETABLISSEMENT' : 'SIGNE_SOIGNANT',
        signature_soignant: role !== 'SOIGNANT', signature_etablissement: role === 'SOIGNANT',
        contenu_html: null, storage_path: null, hash_document: null, contenu_html_rendu_le: null });
      await page.reload();
      await expect(page.getByText('Le document signé d’origine est indisponible. Aucune reconstitution automatique n’est effectuée.', { exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Télécharger le contrat', exact: true })).toBeDisabled();
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeDisabled();
      expect(generations).toHaveLength(0);
      await preuveMission(page, info, role+'-original-manquant');
      // Brouillon sans preuve : refus serveur visible, puis reprise après reload.
      Object.assign(state.contrat, { statut: 'EN_ATTENTE_SIGNATURES', signature_soignant: false, signature_etablissement: false });
      await page.reload(); await expect(page.getByRole('alert')).toContainText('Le document contractuel final n’a pas pu être préparé.');
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeDisabled();
      expect(generations).toHaveLength(1); await preuveMission(page, info, role+'-rendu-refuse');
      renduAutorise = true; await page.reload();
      await expect(page.getByRole('heading', { name: 'Nouveau document autorisé', exact: true })).toBeVisible();
      await expect(page.getByRole('alert')).toHaveCount(0);
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeEnabled();
      expect(generations).toHaveLength(2); await page.reload();
      await expect(page.getByRole('heading', { name: 'Nouveau document autorisé', exact: true })).toBeVisible();
      expect(generations).toHaveLength(2); await preuveMission(page, info, role+'-reprise-figee');
      // La lecture ordinaire refusée après fermeture/révocation n'affiche plus le contrat.
      lectureAutorisee = false; await page.reload(); await expect(page.getByText('Contrat introuvable', { exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Télécharger le contrat', exact: true })).toHaveCount(0);
      expect(generations).toHaveLength(2); expect(state.signatures).toEqual([]); expect(state.sms).toEqual([]);
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    } finally {
      await info.attach('journal-synthetique', { body: JSON.stringify({ generations, calls: state.calls, errors: state.errors, unknown: state.unknown }), contentType: 'application/json' });
    }
  });
}
