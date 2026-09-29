import { test, expect } from '@playwright/test';
import { simulerEtablissement, entrer } from './helpers/recette-complete-etablissement';
import { ids as soignantIds } from './helpers/recette-complete-soignant';
import { recetteCopies } from './helpers/recette-copies-bulletins';

// Playwright otherwise hides Chromium scrollbars, masking this desktop case.
test.use({ launchOptions: { ignoreDefaultArgs: ['--hide-scrollbars'] } });

test('aperçu PDF : rendu et confirmation stables avec barre de défilement classique', async ({ page }, info) => {
  const etab = await simulerEtablissement(page);
  const recette = recetteCopies(); const pdf = recette.enregistrerPdf();
  await recette.installer(page); await entrer(page, 'connexion');
  await page.goto('/etablissement/export-paie');
  // A non-overlay scrollbar changes the available content width. This is an
  // environment variant, not a replacement of the actual PDF renderer.
  await page.addStyleTag({ content: '::-webkit-scrollbar { width: 18px; height: 18px; } ::-webkit-scrollbar-thumb { background: #777; }' });
  const section = page.getByRole('region', { name: 'Copies des bulletins officiels', exact: true });
  await section.getByRole('button', { name: 'Déposer une copie officielle', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Début de période', { exact: true }).fill('2026-09-01');
  await dialog.getByLabel('Fin de période', { exact: true }).fill('2026-09-30');
  await expect(dialog.getByRole('combobox', { name: 'Destinataire', exact: true })).toBeEnabled();
  await dialog.getByRole('combobox', { name: 'Destinataire', exact: true }).selectOption(soignantIds.user);
  for (const n of [1, 2]) await dialog.getByRole('checkbox', { name: new RegExp(`Mission salariée ${n}`) }).check();
  await dialog.getByLabel('PDF officiel (10 Mo maximum)', { exact: true }).setInputFiles(pdf);
  await dialog.getByRole('button', { name: 'Aperçu et confirmation', exact: true }).click();
  const canvas = dialog.getByTestId('apercu-pdf-canvas');
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  const corps = dialog.locator('.overscroll-contain');
  const geometrie = await corps.evaluate(el => ({ deborde: el.scrollHeight > el.clientHeight, gouttiere: el.offsetWidth - el.clientWidth }));
  expect(geometrie.deborde).toBe(true);
  if (info.project.name === 'ordinateur') expect(geometrie.gouttiere).toBeGreaterThan(0);
  for (const direction of ['Page suivante', 'Page précédente']) {
    await dialog.getByRole('button', { name: direction, exact: true }).click();
    await expect(canvas).toHaveAttribute('data-ready', 'true');
  }
  const accord = dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ });
  await accord.check();
  const stabilite = await canvas.evaluate(async el => {
    const apercu = el.closest('section')!;
    const changements: string[] = [];
    const observer = new MutationObserver(() => { if (el.getAttribute('data-ready') !== 'true') changements.push('rendu relancé'); });
    observer.observe(el, { attributes: true, attributeFilter: ['data-ready'] });
    const largeurs = new Set<number>();
    for (let frame = 0; frame < 60; frame++) {
      await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
      largeurs.add(apercu.getBoundingClientRect().width);
    }
    observer.disconnect();
    return { changements, largeurs: [...largeurs] };
  });
  expect(stabilite.changements).toEqual([]); expect(stabilite.largeurs).toHaveLength(1);
  await expect(accord).toBeChecked();
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeEnabled();
  // Window resizing / tablet rotation re-renders the same content without
  // making the user confirm it again. A different page still requires consent.
  const initial = page.viewportSize()!;
  const largeurRendue = await canvas.evaluate(el => el.style.width);
  await info.attach('confirmation-avant-redimensionnement', { body: await dialog.ariaSnapshot(), contentType: 'text/plain' });
  // Wide dialogs have a max width: cross that threshold to resize the PDF too.
  await page.setViewportSize({ width: initial.width > 700 ? 620 : initial.width + 96, height: initial.height });
  await expect.poll(() => canvas.evaluate(el => el.style.width)).not.toBe(largeurRendue);
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  await expect(accord).toBeChecked();
  const largeurRedimensionnee = await canvas.evaluate(el => el.style.width);
  await page.setViewportSize(initial);
  // WebKit may change between overlay/classic gutters after orientation changes.
  await expect.poll(() => canvas.evaluate(el => el.style.width)).not.toBe(largeurRedimensionnee);
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  await expect(accord).toBeChecked();
  await dialog.getByRole('button', { name: 'Page suivante', exact: true }).click();
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  await expect(accord).not.toBeChecked();
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeDisabled();
  await accord.check();
  // Full-page capture temporarily expands the viewport: also exercise that
  // resize, then keep a normal viewport image after the renderer settles.
  await page.screenshot({ path: info.outputPath('redimensionnement-capture.png'), fullPage: true, animations: 'disabled' });
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  await expect(accord).toBeChecked();
  await canvas.scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath('apercu-stable.png'), animations: 'disabled' });
  await info.attach('confirmation-apres-redimensionnement', { body: await dialog.ariaSnapshot(), contentType: 'text/plain' });
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section.getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(recette.state.copies).toHaveLength(1);
  await info.attach('copie-publiee', { body: await section.ariaSnapshot(), contentType: 'text/plain' });
  await page.reload(); await expect(section.getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(etab.etat.erreurs).toEqual([]); expect(etab.etat.inconnues).toEqual([]);
  expect(recette.state.appels.some(a => /paiement|escrow|stripe/.test(a.nom))).toBe(false);
});
