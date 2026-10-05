import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { attendreAPI, entrer, simulerSoignant } from './helpers/recette-complete-soignant';
import { luminance, rapportContraste } from './helpers/contraste-degrades';

test.use({ reducedMotion: 'reduce' });

async function verifierLibelle(checklist: Locator, info: TestInfo, etat: string) {
  // Mesurer le vrai texte enfant : la couleur du bouton n'est pas héritée
  // par ce libellé qui possède son propre token.
  const libelle = checklist.getByText('Dernière étape', { exact: true });
  await expect(libelle).toBeVisible();
  await libelle.scrollIntoViewIfNeeded();
  await expect.poll(() => libelle.evaluate(element => {
    for (let parent: Element | null = element; parent; parent = parent.parentElement) {
      if (Number(getComputedStyle(parent).opacity) !== 1) return false;
    }
    return true;
  }), { message: 'Libellé et ancêtres opaques avant la mesure' }).toBe(true);

  const mesure = await libelle.evaluate(element => {
    const bouton = element.closest('[data-testid="checklist-activation"]');
    if (!bouton || bouton.tagName !== 'BUTTON') throw new Error('Bouton checklist absent');
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const contexte = canvas.getContext('2d')!;
    const rgba = (couleur: string) => {
      contexte.clearRect(0, 0, 1, 1); contexte.fillStyle = couleur; contexte.fillRect(0, 0, 1, 1);
      return Array.from(contexte.getImageData(0, 0, 1, 1).data);
    };
    const style = getComputedStyle(element), fond = getComputedStyle(bouton);
    const couches = [];
    let avantBouton = true;
    for (let parent: Element | null = element; parent; parent = parent.parentElement) {
      const css = getComputedStyle(parent);
      couches.push({ tag: parent.tagName, bouton: parent === bouton, avantBouton,
        couleur: rgba(css.backgroundColor), image: css.backgroundImage,
        opacite: Number(css.opacity), filtre: css.filter, filtreFond: css.backdropFilter,
        melange: css.mixBlendMode,
        pseudos: ['::before', '::after'].map(pseudo => {
          const p = getComputedStyle(parent!, pseudo);
          return { contenu: p.content, affichage: p.display, visibilite: p.visibility,
            largeur: parseFloat(p.width), hauteur: parseFloat(p.height) };
        }) });
      if (parent === bouton) avantBouton = false;
    }
    const boite = element.getBoundingClientRect(), boiteBouton = bouton.getBoundingClientRect();
    return { texte: element.textContent, couleur: rgba(style.color), remplissage: rgba(style.webkitTextFillColor),
      taille: parseFloat(style.fontSize), graisse: style.fontWeight, ombreTexte: style.textShadow,
      image: fond.backgroundImage,
      arrets: (fond.backgroundImage.match(/rgba?\([^)]+\)/g) ?? []).map(rgba), couches,
      dansBouton: boite.left >= boiteBouton.left && boite.right <= boiteBouton.right
        && boite.top >= boiteBouton.top && boite.bottom <= boiteBouton.bottom };
  });

  // Une enveloppe RGB conservative couvre toutes les positions du dégradé,
  // y compris entre les arrêts : aucun échantillon ne peut manquer un creux.
  const bas = [0, 1, 2].map(c => Math.min(...mesure.arrets.map(a => a[c]))).concat(255);
  const haut = [0, 1, 2].map(c => Math.max(...mesure.arrets.map(a => a[c]))).concat(255);
  const lumTexte = luminance(mesure.couleur);
  const minimum = lumTexte >= luminance(bas) && lumTexte <= luminance(haut) ? 1
    : Math.min(rapportContraste(mesure.couleur, bas), rapportContraste(mesure.couleur, haut));
  await info.attach(`checklist-${etat}-contraste`, {
    body: JSON.stringify({ ...mesure, bas, haut, minimum, seuil: 4.5,
      methode: 'Enveloppe RGB conservative du fond opaque sous le vrai libellé' }), contentType: 'application/json',
  });
  expect(mesure.texte).toBe('Dernière étape');
  expect(mesure.taille).toBe(11);
  expect(mesure.couleur[3]).toBe(255);
  expect(mesure.remplissage).toEqual(mesure.couleur);
  expect(mesure.ombreTexte).toBe('none');
  expect(mesure.dansBouton).toBe(true);
  expect(mesure.image).toMatch(/^linear-gradient\(/);
  expect(mesure.image.match(/gradient\(/g)).toHaveLength(1);
  expect(mesure.arrets).toHaveLength(2);
  expect(mesure.arrets.every(a => a[3] === 255)).toBe(true);
  expect(mesure.couches.filter(c => c.bouton)).toHaveLength(1);
  // Le fond opaque du bouton masque ceux de ses ancêtres. Les couches entre
  // le texte et ce fond doivent être transparentes, sans image interposée.
  expect(mesure.couches.filter(c => c.avantBouton && !c.bouton)
    .every(c => c.couleur[3] === 0 && c.image === 'none')).toBe(true);
  expect(mesure.couches.every(c => c.opacite === 1 && c.filtre === 'none'
    && (!c.filtreFond || c.filtreFond === 'none') && c.melange === 'normal')).toBe(true);
  expect(mesure.couches.every(c => c.pseudos.every(p => p.contenu === 'none' || p.contenu === 'normal'
    || p.affichage === 'none' || p.visibilite === 'hidden' || p.largeur === 0 || p.hauteur === 0)),
    'Aucun pseudo-élément peint ignoré').toBe(true);
  expect(minimum, 'Petit texte : contraste AA sur toute la plage du dégradé').toBeGreaterThanOrEqual(4.5);
}

async function verifierDocuments(page: Page) {
  await expect(page).toHaveURL(/\/soignant\/mes-documents$/);
  await expect(page.getByRole('heading', { name: 'Mes documents', exact: true })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Justificatifs', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByText('À quoi sert ton RIB ?', { exact: true })).toBeVisible();
  await attendreAPI(page);
}

for (const theme of ['light', 'dark'] as const) test.describe(`Checklist ${theme}`, () => {
  test.use({ colorScheme: theme });
  test('Dernière étape : contraste, destination et reprise', async ({ page }, info) => {
    await page.addInitScript(theme => localStorage.setItem('theme', theme), theme);
    const consoles: string[] = [];
    page.on('console', message => { if (message.type() === 'error') consoles.push(message.text()); });
    const etat = await simulerSoignant(page, 'complet');
    // Le réseau fournisseur est interdit par la fixture. La feuille de police
    // publique reçoit une réponse simulée explicite, sans téléchargement :
    // le rendu utilise la police de repli locale, comme les autres recettes.
    const police = 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap';
    let feuillesSimulees = 0;
    await page.route(police, route => {
      feuillesSimulees++;
      return route.fulfill({ status: 200, contentType: 'text/css', body: '/* Simulation : police locale de repli. */' });
    });
    await entrer(page, 'connexion');
    const sidebar = page.getByRole('navigation', { name: 'Sidebar', exact: true });
    const navigation = await sidebar.isVisible() ? sidebar : page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
    await navigation.getByRole('button', { name: 'Accueil', exact: true }).click();
    await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
    const checklist = page.getByTestId('checklist-activation');
    await expect(checklist.getByText('Ton RIB', { exact: true })).toBeVisible();
    await attendreAPI(page);
    await verifierLibelle(checklist, info, 'initial');
    await info.attach('checklist-avant-aria', { body: await checklist.ariaSnapshot(), contentType: 'text/plain' });
    await page.reload();
    await expect(checklist.getByText('Ton RIB', { exact: true })).toBeVisible();
    await attendreAPI(page);
    await verifierLibelle(checklist, info, 'apres-rechargement');
    await info.attach('checklist-rendu', { body: await checklist.screenshot(), contentType: 'image/png' });
    await checklist.click();
    await verifierDocuments(page);
    await page.reload();
    await verifierDocuments(page);
    await info.attach('documents-apres-reprise-aria', { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
    await info.attach('police-simulee', { body: JSON.stringify({ url: police, reponsesSimulees: feuillesSimulees, telechargementExterne: false, rendu: 'police locale de repli' }), contentType: 'application/json' });
    expect(feuillesSimulees).toBeGreaterThan(0);
    expect(etat.unknown).toEqual([]);
    expect(etat.errors).toEqual([]);
    expect(consoles).toEqual([]);
  });
});
