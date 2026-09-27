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
  const axe = await runAxe(page);
  const geometrie = await page.evaluate(() => ({ document: document.documentElement.scrollWidth, viewport: innerWidth }));
  const violations = axe.violations.filter(v => v.impact === 'serious' || v.impact === 'critical');
  await info.attach(`${etat}-axe`, { body: JSON.stringify(axe, null, 2), contentType: 'application/json' });
  await info.attach(`${etat}-aria`, { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
  await info.attach(`${etat}-geometrie`, { body: JSON.stringify(geometrie), contentType: 'application/json' });
  if (violations.length || geometrie.document > geometrie.viewport + 1) {
    await info.attach(`${etat}-capture`, { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
  }
  return { etat, violations: violations.map(v => ({ id: v.id, impact: v.impact, cibles: v.nodes.map(n => n.target) })), debordement: geometrie.document - geometrie.viewport };
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
      const entrees = theme === 'light' ? soignant : soignant.filter(e => ['recherche-missions', 'mon-compte'].includes(e.chemin));
      for (const entree of entrees) {
        await naviguer(page, info, 'soignant', entree, () => attendreAPI(page));
        rapports.push(await preuve(page, info, `soignant-${entree.chemin}`));
      }
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
      verifierRapports(rapports);
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
