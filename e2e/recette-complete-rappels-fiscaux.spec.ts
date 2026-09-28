import { expect, test } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, sansDebordement, preuve } from './helpers/recette-complete-soignant';

// Réponses simulées : la projection reproduit PostgREST pour vérifier aussi
// que MesGains charge effectivement la profession depuis le profil.
for (const cas of [
  { profession: 'MEDECIN', regime: null, confirme: false, caisse: 'CARMF', href: 'https://www.carmf.fr', libelle: 'Régime fiscal à renseigner' },
  { profession: 'IDE', regime: 'DECLARATION_CONTROLEE', confirme: true, caisse: 'CARPIMKO', href: 'https://www.carpimko.com', libelle: 'Déclaration contrôlée' },
]) {
  test(`revenus — échéanciers officiels pour ${cas.profession}, sans calendrier supposé`, async ({ page }, info) => {
    const etat = await simulerSoignant(page);
    Object.assign(etat.profile, { profession: cas.profession, type_exercice: 'LIBERAL', statut_liberal: 'ACTIF', regime_fiscal: cas.regime, regime_fiscal_confirme: cas.confirme });
    const projections: string[][] = [];
    await page.route('**/rest/v1/soignants?*', async route => {
      const request = route.request();
      if (request.method() !== 'GET') return route.fallback();
      const select = new URL(request.url()).searchParams.get('select') || '*';
      if (select === '*') return route.fallback();
      const colonnes = select.split(',').map(c => c.trim());
      projections.push(colonnes);
      const profil = Object.fromEntries(colonnes.map(c => [c, etat.profile[c] ?? null]));
      await route.fulfill({ json: request.headers().accept?.includes('object') ? profil : [profil], headers: { 'access-control-allow-origin': '*' } });
    });
    await entrer(page, 'connexion');
    await aller(page, '/soignant/mes-gains');
    const rappels = page.getByRole('region', { name: 'Mes échéances fiscales et sociales' });
    for (const apresRechargement of [false, true]) {
      if (apresRechargement) await recharger(page);
      await expect(rappels).toBeVisible();
      await expect(rappels.getByText(cas.libelle, { exact: true })).toBeVisible();
      await expect(rappels.getByRole('link', { name: `${cas.caisse} — site officiel (nouvelle fenêtre)` })).toHaveAttribute('href', cas.href);
      await expect(rappels).not.toContainText(/Échéance dans|Échue|aujourd’hui|Micro-BNC|cotisation annuelle/);
      if (cas.profession === 'MEDECIN') await expect(rappels).not.toContainText('CARPIMKO');
      await sansDebordement(page);
    }
    expect(projections.some(c => c.includes('regime_fiscal') && c.includes('profession'))).toBe(true);
    await preuve(page, `rappels-${cas.profession}`, info, true);
    expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
  });
}
