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

async function verifierTexteSurFondRendu(cible: Locator, info: TestInfo, nom: string, badge = false) {
  await rendreVisible(cible);
  const mesure = await cible.evaluate((element, badge) => {
    const style = getComputedStyle(element);
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const contexte = canvas.getContext('2d')!;
    contexte.fillStyle = style.color; contexte.fillRect(0, 0, 1, 1);
    const plage = document.createRange();
    plage.selectNodeContents(element);
    if (badge) {
      // Exclure l'emoji multicolore de la mesure du libellé. Sa peinture
      // ne suit pas nécessairement la couleur CSS du texte.
      const noeud = [...element.childNodes].find(n => n.nodeType === Node.TEXT_NODE && n.textContent?.includes('Missions,'))!;
      plage.selectNodeContents(noeud);
      plage.setStart(noeud, noeud.textContent!.indexOf('Missions,'));
      plage.setEnd(noeud, noeud.textContent!.indexOf('tout-en-un') + 'tout-en-un'.length);
    }
    const rect = plage.getBoundingClientRect();
    return {
      texte: element.textContent?.trim(), couleur: Array.from(contexte.getImageData(0, 0, 1, 1).data),
      taille: style.fontSize, graisse: style.fontWeight, soulignement: style.textDecorationLine,
      styleInitial: element.getAttribute('style'),
      rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
    };
  }, badge);
  let capture: Buffer;
  try {
    // Masquer uniquement les glyphes, sans toucher au fond translucide,
    // aux décors frères ni à la géométrie : les pixels obtenus sont ceux
    // effectivement peints derrière le texte, pas une borne hypothétique.
    await cible.evaluate(element => {
      const style = (element as HTMLElement).style;
      style.setProperty('color', 'transparent', 'important');
      style.setProperty('-webkit-text-fill-color', 'transparent', 'important');
      style.setProperty('text-shadow', 'none', 'important');
      style.setProperty('transition', 'none', 'important');
    });
    capture = await cible.page().screenshot({ clip: mesure.rect, animations: 'disabled' });
  } finally {
    await cible.evaluate((element, styleInitial) => {
      if (styleInitial === null) element.removeAttribute('style');
      else element.setAttribute('style', styleInitial);
    }, mesure.styleInitial);
  }
  const pixels = await cible.page().evaluate(async base64 => {
    const octets = Uint8Array.from(atob(base64), caractere => caractere.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([octets], { type: 'image/png' }));
    const canvas = document.createElement('canvas'); canvas.width = bitmap.width; canvas.height = bitmap.height;
    const contexte = canvas.getContext('2d')!; contexte.drawImage(bitmap, 0, 0);
    const rgba = contexte.getImageData(0, 0, canvas.width, canvas.height).data;
    const fonds = new Map<string, number[]>();
    for (let index = 0; index < rgba.length; index += 4) {
      const couleur = Array.from(rgba.slice(index, index + 4)); fonds.set(couleur.join(','), couleur);
    }
    bitmap.close();
    return { nombre: rgba.length / 4, fonds: [...fonds.values()] };
  }, capture!.toString('base64'));
  const minimum = Math.min(...pixels.fonds.map(fond => rapportContraste(composerCouleurs(mesure.couleur, fond), fond)));
  await info.attach(nom, { body: JSON.stringify({ ...mesure, pixels, minimum }), contentType: 'application/json' });
  expect(pixels.nombre).toBeGreaterThan(0);
  expect(pixels.fonds.every(fond => fond[3] === 255)).toBe(true);
  expect.soft(minimum, `${nom} : contraste effectif du texte sur les décors peints`).toBeGreaterThanOrEqual(4.5);
  return mesure;
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
    await verifierTexteSurFondRendu(page.getByText('✨ Missions, contrats, paie : tout-en-un', { exact: true }), info, 'accueil-badge', true);
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
      const sommaire = page.getByRole('navigation', { name: 'Sommaire', exact: true });
      const ouvrir = sommaire.getByRole('button', { name: '📑 Sommaire', exact: true });
      if (await ouvrir.isVisible()) await ouvrir.click();
      const liens = sommaire.getByRole('link');
      await expect(liens.first()).toBeVisible();
      await verifierTexteSurFondRendu(liens.first(), info, `sommaire-${chemin}-debut`);
      await verifierTexteSurFondRendu(liens.last(), info, `sommaire-${chemin}-fin`);
      await liens.first().hover();
      const survole = await verifierTexteSurFondRendu(liens.first(), info, `sommaire-${chemin}-survol`);
      expect(survole.soulignement).toContain('underline');
      expect(survole.couleur[3], 'Le survol ne rend pas le lien semi-transparent').toBe(255);
      await page.mouse.move(0, 0);
      if (chemin === '/cgu') {
        await page.getByRole('heading', { level: 1 }).scrollIntoViewIfNeeded();
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
