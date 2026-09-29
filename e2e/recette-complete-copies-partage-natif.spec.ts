import { test, expect } from '@playwright/test';
import { createHash } from 'node:crypto';
import { simulerBridgeNatif } from './helpers/native-bridge-simule';
import { simulerEtablissement, entrer } from './helpers/recette-complete-etablissement';
import { ids as soignantIds } from './helpers/recette-complete-soignant';
import { recetteCopies } from './helpers/recette-copies-bulletins';

// Real UI/SDK path with a simulated native chooser/filesystem, not Android/iOS
// delivery to a physical recipient app. Deferred cleanup is unit-tested too.
test('copie native : PDF exact conservé après partage, chemins distincts et limite visible', async ({ page }, info) => {
  await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
  const etab = await simulerEtablissement(page);
  await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => route.fulfill({ json: null }));
  const recette = recetteCopies(); const pdf = recette.enregistrerPdf();
  await recette.installer(page); await entrer(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const section = page.getByRole('region', { name: 'Copies des bulletins officiels', exact: true });
  await section.getByRole('button', { name: 'Déposer une copie officielle', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Début de période', { exact: true }).fill('2026-09-01');
  await dialog.getByLabel('Fin de période', { exact: true }).fill('2026-09-30');
  await expect(dialog.getByRole('combobox', { name: 'Destinataire', exact: true })).toBeEnabled();
  await dialog.getByRole('combobox', { name: 'Destinataire', exact: true }).selectOption(soignantIds.user);
  await dialog.getByRole('checkbox', { name: /Mission salariée 1/ }).check();
  await dialog.getByLabel('PDF officiel (10 Mo maximum)', { exact: true }).setInputFiles(pdf);
  await dialog.getByRole('button', { name: 'Aperçu et confirmation', exact: true }).click();
  await expect(dialog.getByTestId('apercu-pdf-canvas')).toHaveAttribute('data-ready', 'true');
  await dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ }).check();
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section.getByText('Copie disponible', { exact: true })).toBeVisible();
  const ouvrir = section.getByRole('button', { name: 'Ouvrir / télécharger le PDF original', exact: true });
  for (let n = 1; n <= 5; n++) {
    await ouvrir.click();
    await expect.poll(() => page.evaluate(() => (window as any).__native.shares.length)).toBe(n);
    await expect(ouvrir).toBeEnabled();
  }
  const native = await page.evaluate(() => ({ files: (window as any).__native.files as Record<string, string>, shares: (window as any).__native.shares as { url: string; data: string }[], calls: (window as any).__native.calls as string[] }));
  expect(Object.keys(native.files)).toHaveLength(5);
  expect(new Set(native.shares.map(s => s.url)).size).toBe(5);
  for (const share of native.shares) {
    expect(createHash('sha256').update(Buffer.from(share.data, 'base64')).digest('hex')).toBe(pdf.sha256);
    expect(native.files[share.url.replace('file:///cache/', '')]).toBe(share.data);
  }
  expect(native.calls).not.toContain('Filesystem.deleteFile');
  // Simulate recent large attachments without allocating 50 MiB in the test.
  await page.evaluate(() => {
    const state = (window as any).__native;
    for (let i = 0; i < 5; i++) {
      const path = `copies-bulletins-partage/${Date.now()}-${crypto.randomUUID()}.pdf`;
      state.files[path] = btoa('Fichier fictif pour tester la capacité');
      state.fileSizes[path] = 10 * 1024 * 1024;
    }
  });
  await ouvrir.click();
  await expect(section.getByRole('alert')).toContainText('L’espace temporaire des PDF partagés est plein.');
  expect(await page.evaluate(() => (window as any).__native.shares.length)).toBe(5);
  await info.attach('limite-partages-recents', { body: await section.ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath('partage-natif-limite.png'), animations: 'disabled' });
  expect(etab.etat.erreurs).toEqual([]); expect(etab.etat.inconnues).toEqual([]);
  expect(recette.state.appels.some(a => /paiement|escrow|stripe/.test(a.nom))).toBe(false);
});
