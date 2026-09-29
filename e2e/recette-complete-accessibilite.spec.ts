import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { runAxe } from './helpers/axe';
import { simulerSoignant, entrer as entrerSoignant, attendreAPI } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, stabiliserLectures } from './helpers/recette-complete-etablissement';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids, now, type RoleRecette } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

test.use({ actionTimeout: 15_000, reducedMotion: 'reduce' });
test.setTimeout(180_000);

type Entree = { nom: string; bureau: string; chemin: string };
type Rapport = { etat: string; violations: { id: string; impact: string | null | undefined; cibles: unknown[] }[]; debordement: number };
const soignant: Entree[] = [
  { nom: 'Accueil', bureau: 'Accueil', chemin: 'tableau-de-bord' },
  { nom: 'Explorer', bureau: 'Trouver une mission', chemin: 'recherche-missions' },
  { nom: 'Mes missions', bureau: 'Mes missions', chemin: 'missions' },
  { nom: 'Revenus', bureau: 'Revenus', chemin: 'mes-gains' },
  { nom: 'Profil', bureau: 'Mon compte', chemin: 'mon-compte' },
];
const etablissement: Entree[] = [
  { nom: 'Accueil', bureau: 'Accueil', chemin: 'tableau-de-bord' },
  { nom: 'Missions', bureau: 'Missions', chemin: 'missions' },
  { nom: 'Publier', bureau: 'Publier une mission', chemin: 'missions/creer' },
  { nom: 'Messages', bureau: 'Messagerie', chemin: 'messagerie' },
  { nom: 'Menu', bureau: 'Mon compte', chemin: 'mon-compte' },
];

async function preuve(page: Page, info: TestInfo, etat: string): Promise<Rapport> {
  await page.waitForLoadState('networkidle');
  const navigation = page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
  if (await navigation.isVisible()) {
    const fond = await navigation.evaluate(element => {
      const style = getComputedStyle(element);
      const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
      const contexte = canvas.getContext('2d')!;
      contexte.fillStyle = style.backgroundColor; contexte.fillRect(0, 0, 1, 1);
      const opacites: number[] = [];
      for (let parent: Element | null = element; parent; parent = parent.parentElement) {
        opacites.push(Number(getComputedStyle(parent).opacity));
      }
      const rect = element.getBoundingClientRect();
      return { couleur: style.backgroundColor, alpha: contexte.getImageData(0, 0, 1, 1).data[3] / 255,
        opacites, gauche: rect.left, droite: rect.right, bas: rect.bottom, largeurViewport: innerWidth, hauteurViewport: innerHeight };
    });
    await info.attach(`${etat}-fond-navigation`, { body: JSON.stringify(fond), contentType: 'application/json' });
    expect(fond.alpha, 'Le contenu sous la navigation ne modifie pas son fond').toBe(1);
    expect(fond.opacites.every(opacite => opacite === 1), 'Navigation et ancêtres opaques').toBe(true);
    expect(fond.gauche).toBeGreaterThanOrEqual(-1);
    expect(fond.droite).toBeLessThanOrEqual(fond.largeurViewport + 1);
    expect(Math.abs(fond.bas - fond.hauteurViewport), 'Navigation ancrée au bas du viewport').toBeLessThanOrEqual(1);
  }
  const onglets = page.locator('[role="tab"][aria-selected="true"]:visible');
  for (let index = 0; index < await onglets.count(); index++) {
    const onglet = onglets.nth(index);
    if ((await onglet.evaluate(element => getComputedStyle(element).backgroundImage)).includes('gradient(')) {
      await verifierTexteSurDegrade(onglet, info, `${etat}-onglet-${index}`);
    }
  }
  const axe = await runAxe(page);
  const geometrie = await page.evaluate(() => ({ document: document.documentElement.scrollWidth, viewport: innerWidth }));
  const violations = axe.violations.filter(v => v.impact === 'serious' || v.impact === 'critical');
  await info.attach(`${etat}-axe`, { body: JSON.stringify(axe, null, 2), contentType: 'application/json' });
  await info.attach(`${etat}-aria`, { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
  await info.attach(`${etat}-geometrie`, { body: JSON.stringify(geometrie), contentType: 'application/json' });
  if (violations.length || geometrie.document > geometrie.viewport + 1) {
    await info.attach(`${etat}-capture`, { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
  }
  if (etat.endsWith('-apres-reprise') || etat.endsWith('-danger-survol')) await info.attach(`${etat}-capture`, { body: await page.screenshot({ scale: 'css' }), contentType: 'image/png' });
  return { etat, violations: violations.map(v => ({ id: v.id, impact: v.impact, cibles: v.nodes.map(n => n.target) })), debordement: geometrie.document - geometrie.viewport };
}

async function verifierNavigationApresReprise(page: Page, info: TestInfo, etat: string, stabiliser: () => Promise<void>) {
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await stabiliser();
  const apresDefilement = await preuve(page, info, `${etat}-apres-defilement`);
  await page.reload();
  await expect(page.locator('main')).toBeVisible();
  await stabiliser();
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  const apresReprise = await preuve(page, info, `${etat}-apres-reprise`);
  if (etat === 'soignant-mes-gains') {
    const cta = page.locator('main').getByRole('button', { name: 'Trouver une mission', exact: true });
    await cta.scrollIntoViewIfNeeded();
    await expect(cta).toBeInViewport();
    const navigation = page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
    if (await navigation.isVisible()) {
      const basCta = await cta.evaluate(element => element.getBoundingClientRect().bottom);
      const hautNavigation = await navigation.evaluate(element => element.getBoundingClientRect().top);
      expect(basCta, 'Le CTA reste entièrement au-dessus de la navigation opaque').toBeLessThanOrEqual(hautNavigation);
    }
    await cta.click();
    await expect(page).toHaveURL(/\/soignant\/recherche-missions$/);
    await stabiliser();
    await page.goBack();
    await expect(page).toHaveURL(/\/soignant\/mes-gains$/);
    await expect(cta).toBeVisible();
    await stabiliser();
  }
  return [apresDefilement, apresReprise];
}

async function verifierFocusClavier(page: Page, cible: Locator, info: TestInfo, etat: string) {
  await cible.focus();
  await expect(cible).toBeFocused();
  // WebKit/macOS réserve Tab aux champs avec le réglage clavier système par
  // défaut. Option+Tab inclut les boutons ; le témoin HTML minimal reproduit
  // exactement cette différence, indépendamment de l'application.
  const optionTab = process.platform === 'darwin' && page.context().browser()?.browserType().name() === 'webkit';
  await page.keyboard.press(optionTab ? 'Alt+Tab' : 'Tab');
  await page.keyboard.press(optionTab ? 'Alt+Shift+Tab' : 'Shift+Tab');
  await expect(cible).toBeFocused();
  const focus = await cible.evaluate(element => {
    const style = getComputedStyle(element);
    return { visible: element.matches(':focus-visible'), outlineStyle: style.outlineStyle, outlineWidth: parseFloat(style.outlineWidth), boxShadow: style.boxShadow };
  });
  await info.attach(`${etat}-focus`, { body: JSON.stringify(focus), contentType: 'application/json' });
  expect(focus.visible, `${etat} : état focus-visible au clavier`).toBe(true);
  expect((focus.outlineStyle !== 'none' && focus.outlineWidth > 0) || focus.boxShadow !== 'none', `${etat} : indicateur visuel de focus`).toBe(true);
}

async function verifierLigneDanger(page: Page, info: TestInfo, etat: string) {
  const deconnexion = page.locator('main').getByRole('button', { name: 'Se déconnecter', exact: true });
  await deconnexion.scrollIntoViewIfNeeded();
  await deconnexion.hover();
  expect(await deconnexion.evaluate(element => element.matches(':hover')), 'Survol effectif de la ligne danger').toBe(true);
  const survol = await preuve(page, info, `${etat}-danger-survol`);
  await page.mouse.move(1, 1);
  expect(await deconnexion.evaluate(element => element.matches(':hover'))).toBe(false);
  await verifierFocusClavier(page, deconnexion, info, `${etat}-danger`);
  return [survol, await preuve(page, info, `${etat}-danger-focus`)];
}

async function verifierCombobox(page: Page, nom: string) {
  // Radix masque le déclencheur aux lecteurs d'écran pendant l'ouverture du
  // portail modal. Conserver ce même élément pour vérifier aria-expanded.
  const champ = page.getByRole('combobox', { name: nom, exact: true, includeHidden: true });
  await expect(champ).toBeVisible();
  await expect(champ).toHaveAccessibleName(nom);
  await champ.focus();
  await page.keyboard.press('Enter');
  await expect(champ).toHaveAttribute('aria-expanded', 'true');
  const contenuId = await champ.getAttribute('aria-controls');
  expect(contenuId).toBeTruthy();
  await expect(page.locator(`[id="${contenuId}"]`)).toBeVisible();
  // Le trigger peut annoncer l'ouverture avant l'installation du portail et
  // l'autofocus Radix. Attendre le contrôle réellement prêt avant Échap.
  if (nom === 'Profession requise *' && page.viewportSize()!.width >= 768) {
    await expect(page.getByPlaceholder('Rechercher une profession...', { exact: true })).toBeFocused();
  } else if (nom === 'Période des revenus') {
    await expect(page.getByRole('option', { name: 'Ce mois', exact: true })).toBeFocused();
  }
  await page.keyboard.press('Escape');
  await expect(champ).toHaveAttribute('aria-expanded', 'false');
  await expect(champ).toBeFocused();
}

async function naviguer(page: Page, info: TestInfo, role: 'soignant' | 'etablissement', entree: Entree, stabiliser: () => Promise<void>) {
  await stabiliser();
  const navigationMobile = page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
  const mobile = await navigationMobile.isVisible();
  const navigation = mobile ? navigationMobile : page.getByRole('navigation', { name: 'Sidebar', exact: true });
  const cible = navigation.getByRole('button', { name: mobile ? entree.nom : entree.bureau, exact: true });
  if (!await cible.isVisible() && role === 'soignant' && ['Explorer', 'Mes missions'].includes(entree.nom)) {
    await navigation.getByRole('button', { name: 'Missions', exact: true }).click();
  }
  await expect(cible).toBeVisible();
  await cible.focus();
  await page.keyboard.press('Enter');
  await expect(page).toHaveURL(new RegExp(`/${role}/${entree.chemin}$`));
  if (role === 'soignant' && entree.chemin === 'recherche-missions') {
    const quiz = page.getByRole('dialog', { name: '5 questions pour un deck qui te ressemble', exact: true });
    await expect(quiz).toBeVisible();
    await quiz.getByRole('button', { name: 'Plus tard', exact: true }).click();
    await expect(quiz).toHaveCount(0);
  }
  await stabiliser();
  await expect(cible).toHaveAttribute('aria-current', 'page');
  await verifierFocusClavier(page, cible, info, `${role}-${entree.chemin}`);
  if (role === 'soignant' && entree.chemin === 'mes-gains') await verifierCombobox(page, 'Période des revenus');
  if (role === 'etablissement' && entree.chemin === 'missions/creer') await verifierCombobox(page, 'Profession requise *');
}

function verifierRapports(rapports: Rapport[]) {
  // Rapporter chaque écran avant l'assertion permet de conserver tous les défauts,
  // sans réduire la sévérité ou interrompre l'inventaire au premier contraste.
  expect(rapports.filter(r => r.violations.length > 0), 'Aucune violation axe serious/critical').toEqual([]);
  expect(rapports.filter(r => r.debordement > 1), 'Aucun débordement horizontal').toEqual([]);
}

async function verifierTexteSurDegrade(cible: Locator, info: TestInfo, etat: string) {
  // Axe ne calcule pas le contraste sur background-image. Échantillonner les
  // couleurs réellement rendues complète son audit pour nos dégradés opaques.
  const couleurs = await cible.evaluate(element => {
    const style = getComputedStyle(element);
    const arrets = style.backgroundImage.match(/rgba?\([^)]+\)/g) ?? [];
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const contexte = canvas.getContext('2d')!;
    const rgba = (couleur: string) => {
      contexte.clearRect(0, 0, 1, 1); contexte.fillStyle = couleur; contexte.fillRect(0, 0, 1, 1);
      return Array.from(contexte.getImageData(0, 0, 1, 1).data);
    };
    const opacites: number[] = [];
    for (let parent: Element | null = element; parent; parent = parent.parentElement) {
      opacites.push(Number(getComputedStyle(parent).opacity));
    }
    return { texte: rgba(style.color), arrets: arrets.map(rgba), fond: style.backgroundImage, opacites };
  });
  expect(couleurs.arrets.length, `${etat} : dégradé effectivement chargé`).toBeGreaterThanOrEqual(2);
  expect(couleurs.opacites.every(opacite => opacite === 1), `${etat} : cible et ancêtres opaques`).toBe(true);
  for (const couleur of [couleurs.texte, ...couleurs.arrets]) expect(couleur[3]).toBe(255);
  const luminance = (couleur: number[]) => couleur.slice(0, 3).reduce((total, composante, index) => {
    const s = composante / 255;
    return total + [0.2126, 0.7152, 0.0722][index] * (s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4);
  }, 0);
  const texte = luminance(couleurs.texte);
  const rapports: number[] = [];
  for (let index = 1; index < couleurs.arrets.length; index++) {
    for (let pas = 0; pas <= 32; pas++) {
      const t = pas / 32;
      const fond = luminance(couleurs.arrets[index].map((composante, canal) => couleurs.arrets[index - 1][canal] * (1 - t) + composante * t));
      rapports.push((Math.max(texte, fond) + 0.05) / (Math.min(texte, fond) + 0.05));
    }
  }
  const minimum = Math.min(...rapports);
  await info.attach(`${etat}-contraste-degrade`, { body: JSON.stringify({ ...couleurs, minimum }), contentType: 'application/json' });
  expect(minimum, `${etat} : contraste du petit texte sur le dégradé`).toBeGreaterThanOrEqual(4.5);
}

for (const theme of ['light', 'dark'] as const) test.describe(`ACCESSIBILITÉ ${theme}`, () => {
  test.use({ colorScheme: theme });
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(theme => localStorage.setItem('theme', theme), theme);
  });

  test('soignant — navigation et contenu authentifiés', async ({ page }, info) => {
    const state = await simulerSoignant(page, 'complet');
    const rapports: Rapport[] = [];
    try {
      await entrerSoignant(page, 'connexion');
      const entrees = theme === 'light' ? soignant : soignant.filter(e => ['recherche-missions', 'mes-gains', 'mon-compte'].includes(e.chemin));
      for (const entree of entrees) {
        await naviguer(page, info, 'soignant', entree, () => attendreAPI(page));
        rapports.push(await preuve(page, info, `soignant-${entree.chemin}`));
        if (entree.chemin === 'mes-gains') rapports.push(...await verifierNavigationApresReprise(page, info, 'soignant-mes-gains', () => attendreAPI(page)));
        if (entree.chemin === 'mon-compte') rapports.push(...await verifierLigneDanger(page, info, 'soignant-mon-compte'));
      }
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
      verifierRapports(rapports);
    } finally {
      await info.attach('api-strictement-simulee', { body: JSON.stringify(state, null, 2), contentType: 'application/json' });
    }
  });

  test('soignant — carte de mission renseignée', async ({ page }, info) => {
    const state = await simulerSoignant(page, 'complet');
    state.offers = true;
    try {
      await entrerSoignant(page, 'connexion');
      await naviguer(page, info, 'soignant', soignant[1], () => attendreAPI(page));
      await expect(page.getByRole('button', { name: /^Mission IDE à Résidence Camille/ })).toBeVisible();
      await expect(page.getByText('Salarié (CDD)', { exact: true })).toBeVisible();
      verifierRapports([await preuve(page, info, 'soignant-carte-mission-renseignee')]);
      await verifierTexteSurDegrade(page.getByRole('tab', { name: 'Swipe', exact: true }), info, 'vue-selectionnee');
      const jour = page.getByRole('button', { name: '☀️ Jour', exact: true });
      await jour.click();
      await verifierTexteSurDegrade(jour, info, 'filtre-selectionne');
      await info.attach('carte-mission-contrastes', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    } finally {
      await info.attach('api-strictement-simulee', { body: JSON.stringify(state, null, 2), contentType: 'application/json' });
    }
  });

  test('établissement — navigation et contenu authentifiés', async ({ page }, info) => {
    const { etat } = await simulerEtablissement(page, 'complet');
    const rapports: Rapport[] = [];
    try {
      await entrerEtablissement(page, 'connexion');
      const entrees = theme === 'light' ? etablissement : etablissement.filter(e => e.chemin === 'mon-compte');
      for (const entree of entrees) {
        await naviguer(page, info, 'etablissement', entree, () => stabiliserLectures(page));
        rapports.push(await preuve(page, info, `etablissement-${entree.chemin.replaceAll('/', '-')}`));
        if (entree.chemin === 'mon-compte') {
          rapports.push(...await verifierNavigationApresReprise(page, info, 'etablissement-mon-compte', () => stabiliserLectures(page)));
          rapports.push(...await verifierLigneDanger(page, info, 'etablissement-mon-compte'));
        }
      }
      expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.operations).toEqual([]);
      verifierRapports(rapports);
    } finally {
      await info.attach('api-strictement-simulee', { body: JSON.stringify(etat, null, 2), contentType: 'application/json' });
    }
  });

  for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) test(`${role} — suivi mission déplié`, async ({ context, page }, info) => {
    const { state, installer } = creerSuiviSimule();
    state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = 'LIBERAL'; state.contratCree = true;
    await installer(context, role); await page.clock.setFixedTime(new Date(now));
    try {
      const prefixe = role === 'SOIGNANT' ? 'soignant' : 'etablissement';
      await page.goto(`/${prefixe}/missions/${ids.mission}`);
      const region = page.getByRole('region', { name: 'Suivi de la mission', exact: true });
      const ouvrir = region.getByRole('button', { name: 'Afficher le détail du suivi', exact: true });
      await expect(ouvrir).toBeVisible(); await stabiliserActionsNationales(page);
      await verifierFocusClavier(page, ouvrir, info, `${prefixe}-suivi`);
      await page.keyboard.press('Enter');
      const fermer = region.getByRole('button', { name: 'Masquer le détail du suivi', exact: true });
      await expect(fermer).toHaveAttribute('aria-expanded', 'true'); await expect(fermer).toBeFocused();
      await expect(region.getByTestId('suivi-planning')).toContainText('Créneaux prévus disponibles');
      await stabiliserActionsNationales(page);
      await expect(page.getByRole('img', { name: /^Statut : / })).toBeVisible();
      const rapport = await preuve(page, info, `${prefixe}-suivi-deplie`);
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
      expect(state.signatures).toEqual([]); expect(state.sms).toEqual([]); expect(state.emails).toEqual([]);
      verifierRapports([rapport]);
    } finally {
      await info.attach('api-strictement-simulee', { body: JSON.stringify(state, null, 2), contentType: 'application/json' });
    }
  });
});
