import { expect, test } from '@playwright/test';
import { entrer as entrerEtablissement, simulerEtablissement, stabiliserLectures } from './helpers/recette-complete-etablissement';
import { attendreAPI, entrer as entrerSoignant, simulerSoignant } from './helpers/recette-complete-soignant';
import { mesurerTexteDegrade } from './helpers/contraste-degrades';

test.use({ reducedMotion: 'reduce' });

for (const theme of ['light', 'dark'] as const) test.describe(`Titres ${theme}`, () => {
  test.use({ colorScheme: theme });
  for (const scenario of ['etablissement-minimal', 'etablissement-complet', 'soignant'] as const) {
    test(`${scenario} : le texte en dégradé reste lisible`, async ({ page }, info) => {
      await page.addInitScript(theme => localStorage.setItem('theme', theme), theme);
      let inconnues: string[], erreurs: string[];
      if (scenario === 'soignant') {
        const etat = await simulerSoignant(page, 'complet');
        inconnues = etat.unknown; erreurs = etat.errors;
        await entrerSoignant(page, 'connexion');
        const sidebar = page.getByRole('navigation', { name: 'Sidebar', exact: true });
        const navigation = await sidebar.isVisible() ? sidebar : page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
        await navigation.getByRole('button', { name: 'Accueil', exact: true }).click();
        await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
        await expect(page.locator('h1 .text-gradient-hero')).toHaveText('Camille');
        await attendreAPI(page);
      } else {
        const minimal = scenario === 'etablissement-minimal';
        const { etat } = await simulerEtablissement(page, minimal ? 'minimal' : 'complet');
        etat.donnees = !minimal;
        inconnues = etat.inconnues; erreurs = etat.erreurs;
        await entrerEtablissement(page, 'connexion');
        await expect(page.locator('h1 .text-gradient-hero')).toHaveText(minimal ? 'première mission' : 'Résidence Camille — recette');
        await stabiliserLectures(page);
      }
      const titre = page.locator('h1 .text-gradient-hero');
      await expect(titre).toBeVisible();
      const mesure = await mesurerTexteDegrade(titre);
      await info.attach('contraste-titre', { body: JSON.stringify(mesure, null, 2), contentType: 'application/json' });
      expect(mesure.clip).toBe('text');
      expect(mesure.remplissageRgba[3], 'Le dégradé est bien utilisé comme couleur des glyphes').toBe(0);
      expect(mesure.arrets).toHaveLength(3);
      expect(mesure.arrets.every(arret => arret[3] === 255)).toBe(true);
      expect(mesure.fond[3]).toBe(255);
      expect(mesure.ancetres.every(ancetre => ancetre.image === 'none'), 'Aucun fond en image ignoré dans la mesure').toBe(true);
      expect([mesure.opacite, ...mesure.ancetres.map(ancetre => ancetre.opacite)].every(opacite => opacite === 1)).toBe(true);
      expect(mesure.minimum, 'Contraste AA du texte sur toute la plage du dégradé').toBeGreaterThanOrEqual(4.5);
      expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
      expect(inconnues).toEqual([]);
      expect(erreurs).toEqual([]);
    });
  }
});
