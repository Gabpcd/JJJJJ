import { expect, test, type Page } from '@playwright/test';
import { ouvrirDossierDepuisMission, remplirIdentite, simulerCompletionSoignant } from './helpers/recette-complete-completion-soignant';
import { attendreAPI, preuve, sansDebordement } from './helpers/recette-complete-soignant';
import { simulerBridgeNatif } from './helpers/native-bridge-simule';

// Interface réelle, réponses API simulées ; aucune inscription distante.
// Le défilement programmatique mesure les limites et la reprise du conteneur.
// Il ne valide pas l'inertie tactile ni le clavier d'un téléphone physique.
const formation = (page: Page) => page.getByRole('combobox', { name: 'Formation', exact: true });

test('formulaire : bas accessible et position conservée après les CGU', async ({ page }, info) => {
  const { state } = await simulerCompletionSoignant(page);
  await ouvrirDossierDepuisMission(page);
  await page.getByRole('combobox', { name: 'Profession *', exact: true }).click();
  await page.getByTestId('profession-option-MEDECIN').click();
  await page.getByRole('button', { name: 'Je suis étudiant en santé', exact: true }).click();
  await formation(page).selectOption('MEDECINE_DES');
  await remplirIdentite(page);
  await attendreAPI(page);
  const main = page.locator('main.auth-scroll');
  const bouton = page.getByRole('button', { name: 'Enregistrer mon profil', exact: true });
  const viewport = page.viewportSize()!;
  const mesures = [];
  for (let i = 0; i < 8; i++) {
    const box = await bouton.boundingBox();
    mesures.push(await main.evaluate(el => ({ scroll: el.scrollTop, height: el.clientHeight, total: el.scrollHeight, window: window.scrollY })));
    if (box && box.y >= 80 && box.y + box.height < viewport.height - 20) break;
    const avant = await main.evaluate(el => el.scrollTop);
    // WebKit mobile ne fournit pas de geste de glissement à Playwright :
    // mesurer ici la zone scrollable sans prétendre valider le toucher natif.
    await main.evaluate((el, distance) => el.scrollBy({ top: distance, behavior: 'instant' }), Math.round(viewport.height * .6));
    await expect.poll(() => main.evaluate(el => el.scrollTop)).toBeGreaterThan(avant);
  }
  const box = await bouton.boundingBox();
  expect(box).not.toBeNull();
  expect(box!.y).toBeGreaterThanOrEqual(80);
  expect(box!.y + box!.height).toBeLessThan(viewport.height - 20);
  expect(await page.evaluate(() => window.scrollY)).toBe(0);
  await preuve(page, 'bas-formulaire', info, true);
  await info.attach('mesures-defilement', { body: JSON.stringify(mesures), contentType: 'application/json' });
  await page.getByRole('link', { name: '📋 CGU', exact: true }).scrollIntoViewIfNeeded();
  const positionAvant = await main.evaluate(el => el.scrollTop);
  expect(positionAvant).toBeGreaterThan(100);
  await page.getByRole('link', { name: '📋 CGU', exact: true }).click();
  await expect(page).toHaveURL(/\/cgu$/);
  await attendreAPI(page);
  await page.goBack();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  await expect(formation(page)).toHaveValue('MEDECINE_DES');
  await attendreAPI(page);
  await expect.poll(() => main.evaluate(el => el.scrollTop)).toBeCloseTo(positionAvant, 0);
  const apres = await main.evaluate(el => ({ scroll: el.scrollTop, window: window.scrollY }));
  await info.attach('retour-formulaire', { body: JSON.stringify(apres), contentType: 'application/json' });
  await preuve(page, 'retour-formulaire', info, true);
  expect(apres.window).toBe(0);
  await sansDebordement(page);
  expect(state.unknown).toEqual([]);
  expect(state.errors).toEqual([]);
});

test('clavier simulé : champ visible sous le header après réduction puis rotation', async ({ page }, info) => {
  await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
  const { state } = await simulerCompletionSoignant(page);
  await page.route('**/rest/v1/rpc/fn_upsert_token_push', route => route.fulfill({ json: null }));
  await ouvrirDossierDepuisMission(page);
  await attendreAPI(page);
  await expect.poll(() => page.evaluate(() => (window as any).__native.listeners
    .some((listener: { plugin: string; event: string }) => listener.plugin === 'Keyboard' && listener.event === 'keyboardDidShow'))).toBe(true);
  const initial = page.viewportSize()!;
  const champ = page.getByLabel(/^Téléphone \*/);
  const main = page.locator('main.auth-scroll');
  const emit = (event: string, keyboardHeight: number) => page.evaluate(({ event, keyboardHeight }) =>
    (window as any).__native.emit('Keyboard', event, { keyboardHeight }), { event, keyboardHeight });
  for (const [nom, taille] of [['initial', initial], ['rotation', { width: initial.height, height: initial.width }]] as const) {
    await page.setViewportSize(taille);
    const hauteurClavier = Math.min(300, Math.round(taille.height * .35));
    await champ.focus();
    await emit('keyboardWillShow', hauteurClavier);
    await page.setViewportSize({ width: taille.width, height: taille.height - hauteurClavier });
    await emit('keyboardDidShow', hauteurClavier);
    await expect.poll(() => champ.evaluate(el => {
      const champRect = el.getBoundingClientRect();
      const mainRect = el.closest('main')!.getBoundingClientRect();
      return champRect.top >= mainRect.top + 11 && champRect.bottom <= Math.min(mainRect.bottom, innerHeight) - 19;
    })).toBe(true);
    // Placer le haut du champ juste derrière le header reproduit le défaut
    // que la vérification limitée au viewport ne détectait pas.
    await main.evaluate(el => {
      const field = el.querySelector<HTMLInputElement>('input[type="tel"]')!;
      el.scrollTop += field.getBoundingClientRect().top - el.getBoundingClientRect().top + 6;
    });
    await champ.evaluate(el => el.dispatchEvent(new FocusEvent('focusin', { bubbles: true })));
    await expect.poll(() => champ.evaluate(el => el.getBoundingClientRect().top - el.closest('main')!.getBoundingClientRect().top)).toBeGreaterThanOrEqual(11);
    await preuve(page, `clavier-simule-${nom}`, info, true);
    await emit('keyboardWillHide', 0);
    await page.setViewportSize(taille);
    await emit('keyboardDidHide', 0);
    await champ.blur();
  }
  await page.setViewportSize(initial);
  await sansDebordement(page);
  expect(state.unknown).toEqual([]);
  expect(state.errors).toEqual([]);
});
