import { expect, test } from '@playwright/test';
import { allerA, entrer, preuve, simulerEtablissement, stabiliserLectures } from './helpers/recette-complete-etablissement';

for (const entree of ['inscription', 'connexion'] as const) {
  test(`dashboard minimal après ${entree} : prochaine étape sans fausse situation financière`, async ({ page }, info) => {
    const { etat } = await simulerEtablissement(page, 'minimal');
    etat.overrides.set('fn_mes_permissions_etab', { success: false, role: null, permissions: {} });
    await entrer(page, entree);
    const main = page.locator('main');
    await expect(main.getByRole('heading', { name: 'Préparez votre première mission', exact: true })).toBeVisible();
    await expect(main.getByText('À compléter avant publication', { exact: true })).toBeVisible();
    for (const absent of ['Paiements à jour', 'Soignants ce mois', 'Vérification en cours', 'Validé']) {
      await expect(main.getByText(absent, { exact: true })).toHaveCount(0);
    }
    expect(etat.appels).not.toContain('POST fn_stats_dashboard_etablissement');
    expect(etat.appels).not.toContain('POST fn_obligations_financieres');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
    await preuve(page, `dashboard-minimal-${entree}`, info);

    // Le menu compte doit rester accessible sans compléter le dossier,
    // aussi depuis la navigation latérale des tablettes et ordinateurs.
    const sidebar = page.getByRole('navigation', { name: 'Sidebar', exact: true });
    const compte = await sidebar.isVisible()
      ? sidebar.getByRole('button', { name: 'Mon compte', exact: true })
      : page.getByRole('navigation', { name: 'Navigation mobile', exact: true }).getByRole('button', { name: 'Menu', exact: true });
    await compte.click();
    await expect(page).toHaveURL(/\/etablissement\/mon-compte$/);
    await expect(main.getByRole('button', { name: 'Se déconnecter', exact: true })).toBeVisible();
    await expect(main.getByRole('button', { name: 'Supprimer mon compte', exact: true })).toBeVisible();
    await expect(main.getByRole('button', { name: 'Contacter Jolene', exact: true })).toBeVisible();
    await preuve(page, `compte-minimal-${entree}`, info);
    await allerA(page, '/etablissement/tableau-de-bord');

    await main.getByRole('button', { name: 'Préparer une mission', exact: true }).click();
    await expect(page).toHaveURL(/\/etablissement\/missions\/creer$/);
    await expect(page.getByRole('heading', { name: 'Publier une mission', exact: true })).toBeVisible();
    await allerA(page, '/etablissement/tableau-de-bord');
    await main.getByRole('button', { name: 'Compléter mon établissement', exact: true }).click();
    await expect(page).toHaveURL(/\/inscription\/completer$/);
    await expect(page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true })).toBeVisible();
    await stabiliserLectures(page);
    expect(etat.inconnues).toEqual([]);
    expect(etat.erreurs).toEqual([]);
    expect(etat.ecritures).toEqual([]);
  });
}
