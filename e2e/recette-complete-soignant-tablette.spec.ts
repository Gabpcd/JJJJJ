import { test, expect } from '@playwright/test';
import { simulerSoignant, entrer, preuve, sansDebordement, mission, ids } from './helpers/recette-complete-soignant';

test('SOIGNANT — carte Swipe proportionnée, contenu entier et actions accessibles', async ({ page }, info) => {
  const state = await simulerSoignant(page, 'minimal');
  state.offers = true;
  await entrer(page, 'inscription');
  const formats = [page.viewportSize()!];
  if (info.project.name.startsWith('ipad')) formats.push({ width: 1032, height: 1376 }, { width: 1376, height: 1032 });
  for (const format of formats) {
    await page.setViewportSize(format);
    const carte = page.getByRole('button', { name: /Mission IDE.*Toucher pour le détail/ });
    const verifier = page.getByRole('button', { name: 'Vérifier le planning avant de postuler à cette mission', exact: true });
    await expect(carte).toBeInViewport({ ratio: 1 });
    await expect(carte.getByText('Toucher pour voir le détail', { exact: true })).toBeInViewport({ ratio: 1 });
    for (const nom of ['Passer cette mission', 'Sauvegarder cette mission pour y revenir', 'Vérifier le planning avant de postuler à cette mission']) {
      await expect(page.getByRole('button', { name: nom, exact: true })).toBeInViewport({ ratio: 1 });
    }
    const cardBox = await carte.boundingBox();
    const actionBox = await verifier.boundingBox();
    expect(cardBox!.width).toBeLessThanOrEqual(448);
    expect(cardBox!.height).toBeGreaterThan(300);
    if (format.width >= 768) expect(actionBox!.y + actionBox!.height - cardBox!.y).toBeLessThanOrEqual(720);
    expect(await carte.evaluate(el => el.scrollHeight - el.clientHeight)).toBeLessThanOrEqual(1);
    await sansDebordement(page);
    await preuve(page, `swipe-proportions-${format.width}x${format.height}`, info, true);
    await carte.click();
    await expect(page.getByRole('dialog')).toContainText('Dates et horaires travaillés');
    await page.getByRole('button', { name: 'Fermer', exact: true }).click();
    await expect(page.getByRole('dialog')).not.toBeVisible();
  }
  expect(state.calls.some(c => /confirmer_action|creer_candidature|enregistrer_swipe/.test(c.name))).toBe(false);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('SOIGNANT — Explorer Carte, popup, retour et filtres ville réinitialisés', async ({ page }, info) => {
  const state = await simulerSoignant(page, 'minimal');
  state.offers = true;
  await entrer(page, 'inscription');
  await page.getByRole('tab', { name: 'Carte', exact: true }).click();
  await expect(page.locator('.leaflet-container')).toBeVisible();
  await page.getByTitle(mission.intitule, { exact: true }).click();
  await expect(page.locator('.leaflet-popup')).toContainText(mission.intitule);
  await preuve(page, 'explorer-carte-popup', info);
  await page.getByRole('link', { name: 'Voir la mission', exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
  await expect(page.getByRole('heading', { name: mission.intitule, exact: true })).toBeVisible();
  await page.goBack();
  await expect(page.getByRole('tab', { name: 'Carte', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('.leaflet-container')).toHaveCount(1);
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  await expect(page.getByText(mission.intitule, { exact: true })).toBeVisible();
  await page.getByRole('button', { name: /^Filtres/ }).click();
  const filtres = page.getByRole('dialog', { name: 'Filtres', exact: true });
  await filtres.getByLabel('📍 Ville ou code postal', { exact: true }).fill('Lyon');
  await expect(filtres.getByRole('button', { name: 'Voir 0 mission', exact: true })).toBeVisible();
  await preuve(page, 'explorer-filtres-ville', info);
  await filtres.getByRole('button', { name: 'Voir 0 mission', exact: true }).click();
  await expect(page.getByText(mission.intitule, { exact: true })).not.toBeVisible();
  await expect(page.getByRole('heading', { name: 'Aucune mission trouvée', exact: true })).toBeVisible();
  await page.getByRole('button', { name: /^Filtres/ }).click();
  await filtres.getByRole('button', { name: 'Réinitialiser', exact: true }).click();
  await expect(filtres.getByLabel('📍 Ville ou code postal', { exact: true })).toHaveValue('');
  await filtres.getByRole('button', { name: 'Voir 1 mission', exact: true }).click();
  await expect(page.getByText(mission.intitule, { exact: true })).toBeVisible();
  await preuve(page, 'explorer-filtres-reinitialises', info);
  expect(state.calls.some(c => /confirmer_action|creer_candidature|enregistrer_swipe/.test(c.name))).toBe(false);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});
