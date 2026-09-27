import { expect, test, type Locator, type TestInfo } from '@playwright/test';
import { simulerPublic } from './helpers/recette-complete-public';
import { composerCouleurs, echantillonnerDegrade, luminance, mesurerTexteDegrade, rapportContraste } from './helpers/contraste-degrades';

test.use({ reducedMotion: 'reduce' });

async function rendreVisible(cible: Locator) {
  await cible.scrollIntoViewIfNeeded();
  await expect(cible).toBeVisible();
  await expect.poll(() => cible.evaluate(element => {
    for (let parent: Element | null = element; parent; parent = parent.parentElement) {
      if (Number(getComputedStyle(parent).opacity) !== 1) return false;
    }
    return true;
  }), { message: 'Contenu et ancêtres totalement opaques après défilement' }).toBe(true);
}

async function verifierTexte(cible: Locator, info: TestInfo, nom: string, hero = false) {
  await rendreVisible(cible);
  const mesure = await mesurerTexteDegrade(cible);
  expect(mesure.clip).toContain('text');
  expect(mesure.remplissageRgba[3]).toBe(0);
  expect(mesure.arrets.length).toBeGreaterThanOrEqual(2);
  expect(mesure.arrets.every(c => c[3] === 255)).toBe(true);
  expect(mesure.fond[3]).toBe(255);
  expect(mesure.ancetres.every(a => a.image === 'none')).toBe(true);
  let minimum = mesure.minimum;
  let borneHero: unknown;
  if (hero) {
    // Ces décors sont des frères positionnés, pas des fonds des ancêtres.
    // Borne conservative : chaque canal couvre toutes les couleurs possibles
    // des quatre couches, même si leurs positions ne se superposent pas.
    const couches = await cible.evaluate(element => {
      const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
      const contexte = canvas.getContext('2d')!;
      return [...element.closest('section')!.querySelectorAll(':scope > div.absolute')].map(decor => {
        const style = getComputedStyle(decor);
        const arrets = (style.backgroundImage.match(/rgba?\([^)]+\)/g) ?? []).map(couleur => {
          contexte.clearRect(0, 0, 1, 1); contexte.fillStyle = couleur; contexte.fillRect(0, 0, 1, 1);
          const rgba = Array.from(contexte.getImageData(0, 0, 1, 1).data);
          rgba[3] *= Number(style.opacity);
          return rgba;
        });
        return { image: style.backgroundImage, arrets };
      });
    });
    expect(couches).toHaveLength(4);
    let bas = mesure.fond, haut = mesure.fond;
    for (const couche of couches) {
      expect(couche.arrets.length).toBeGreaterThanOrEqual(2);
      const possibilites = [bas, haut, ...couche.arrets.flatMap(couleur => [composerCouleurs(couleur, bas), composerCouleurs(couleur, haut)])];
      bas = [0, 1, 2].map(canal => Math.min(...possibilites.map(c => c[canal]))).concat(255);
      haut = [0, 1, 2].map(canal => Math.max(...possibilites.map(c => c[canal]))).concat(255);
    }
    const minFond = luminance(bas), maxFond = luminance(haut);
    minimum = Math.min(...echantillonnerDegrade(mesure.arrets).map(texte => {
      const lum = luminance(texte);
      return lum >= minFond && lum <= maxFond ? 1 : Math.min(rapportContraste(texte, bas), rapportContraste(texte, haut));
    }));
    borneHero = { methode: 'enveloppe conservative RGB des quatre décors composités', couches, bas, haut };
  }
  await info.attach(nom, { body: JSON.stringify({ ...mesure, minimum, borneHero }), contentType: 'application/json' });
  expect.soft(minimum, `${nom} : texte à dégradé, contraste minimum`).toBeGreaterThanOrEqual(4.5);
}

async function verifierBouton(cible: Locator, info: TestInfo, nom: string, seuil = 4.5) {
  await rendreVisible(cible);
  const mesure = await cible.evaluate(element => {
    const style = getComputedStyle(element);
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const contexte = canvas.getContext('2d')!;
    const rgba = (couleur: string) => {
      contexte.clearRect(0, 0, 1, 1); contexte.fillStyle = couleur; contexte.fillRect(0, 0, 1, 1);
      return Array.from(contexte.getImageData(0, 0, 1, 1).data);
    };
    return { texte: element.textContent, couleur: rgba(style.color), image: style.backgroundImage,
      arrets: (style.backgroundImage.match(/rgba?\([^)]+\)/g) ?? []).map(rgba) };
  });
  expect(mesure.arrets.length).toBeGreaterThanOrEqual(2);
  expect([mesure.couleur, ...mesure.arrets].every(c => c[3] === 255)).toBe(true);
  const minimum = Math.min(...echantillonnerDegrade(mesure.arrets).map(fond => rapportContraste(mesure.couleur, fond)));
  await info.attach(nom, { body: JSON.stringify({ ...mesure, minimum, seuil }), contentType: 'application/json' });
  expect.soft(minimum, `${nom} : contraste sur fond dégradé`).toBeGreaterThanOrEqual(seuil);
}

for (const theme of ['light', 'dark'] as const) test.describe(`CONTRASTES PUBLICS ${theme}`, () => {
  test.use({ colorScheme: theme });
  test('accueil et documents légaux : textes et actions à dégradés lisibles', async ({ page }, info) => {
    const state = await simulerPublic(page);
    await page.addInitScript(theme => {
      if (['localhost', '127.0.0.1'].includes(location.hostname)) localStorage.setItem('theme', theme);
    }, theme);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Le remplacement santé, enfin simple.', level: 1 })).toBeVisible();
    await verifierTexte(page.getByText('enfin simple.', { exact: true }), info, 'accueil-titre', true);
    const actions = [
      page.getByTestId('hero-cta-soignant'), page.getByTestId('hero-cta-etab'),
      page.getByRole('button', { name: 'Créer mon profil gratuit ✨', exact: true }),
      page.getByRole('button', { name: 'Publier ma première mission 🎯', exact: true }),
      page.getByTestId('bottom-cta-soignant'), page.getByTestId('bottom-cta-etab'),
    ];
    for (let index = 0; index < actions.length; index++) await verifierBouton(actions[index], info, `accueil-action-${index}`);
    for (const numero of [1, 2, 3]) await verifierTexte(page.getByText(`Étape ${numero}`, { exact: true }), info, `accueil-etape-${numero}`);
    await page.getByTestId('hero-cta-soignant').scrollIntoViewIfNeeded();
    await info.attach('accueil-actions', { body: await page.screenshot(), contentType: 'image/png' });
    for (const chemin of ['/cgu', '/cgv', '/confidentialite', '/mentions-legales']) {
      await page.goto(chemin);
      await verifierTexte(page.getByRole('heading', { level: 1 }), info, `legal${chemin.replace('/', '-')}`);
      if (chemin === '/cgu') {
        await info.attach('titre-legal', { body: await page.screenshot(), contentType: 'image/png' });
        await page.getByText('Autres pages légales', { exact: true }).scrollIntoViewIfNeeded();
        await verifierBouton(page.getByRole('button', { name: 'Retour en haut', exact: true }), info, 'legal-retour-haut', 3);
      }
    }
    await page.emulateMedia({ media: 'print' });
    const impression = await page.getByRole('heading', { level: 1 }).evaluate(element => {
      const style = getComputedStyle(element);
      return { image: style.backgroundImage, couleur: style.color, remplissage: style.webkitTextFillColor,
        fondPapier: getComputedStyle(document.body).backgroundColor };
    });
    await info.attach('legal-impression', { body: JSON.stringify(impression), contentType: 'application/json' });
    expect(impression).toEqual({ image: 'none', couleur: 'rgb(0, 0, 0)', remplissage: 'rgb(0, 0, 0)', fondPapier: 'rgb(255, 255, 255)' });
    await page.emulateMedia({ media: 'screen' });
    expect(state.unknown).toEqual([]);
    expect(state.errors).toEqual([]);
  });
});
