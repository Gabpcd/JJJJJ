import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, preuve, sansDebordement, mission, ids } from './helpers/recette-complete-soignant';

test('charges — données des missions, caisse médecin, export et accès documents', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  Object.assign(etat.profile, { profession: 'MEDECIN', type_exercice: 'MIXTE', statut_liberal: 'ACTIF' });
  const fin = new Date();
  const row = { ...mission, soignant_assigne_id: ids.user, statut: 'TERMINEE', type_contrat_applique: 'LIBERAL', debut_le: new Date(fin.getTime() - 8 * 3600000).toISOString(), fin_le: fin.toISOString(), total_brut: 320, duree_heures: 8 };
  etat.tables.set('missions', [row, { ...row, id: 'mission-salariee-exclue', type_contrat_applique: 'SALARIE', total_brut: 1000 }]);
  await entrer(page, 'connexion'); await aller(page, '/soignant/charges');
  await expect(page.getByRole('heading', { name: 'Mes charges sociales', exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: /CARMF.*site officiel/ })).toBeVisible();
  await expect(page.locator('main')).not.toContainText(/CARPIMKO|21,2|1,6|15 mai|Revenu net estimé|Prochaines échéances/);
  const recap = page.getByRole('button', { name: /Honoraires bruts des missions terminées/ });
  await expect(recap).toContainText(/320,00\s*€/); await expect(recap).toContainText('1 mission');
  await recap.press('Enter'); await expect(page.getByRole('button', { name: /Renfort infirmier — simulation/ })).toBeVisible();
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Exporter le récapitulatif des missions' }).click();
  const fichier = await download; const chemin = info.outputPath('missions.csv'); await fichier.saveAs(chemin);
  const csv = await readFile(chemin, 'utf8'); expect(csv).toContain('terminees,320.00'); expect(csv).not.toMatch(/CARPIMKO|URSSAF|estimé|1800|400/);
  await sansDebordement(page); await preuve(page, 'charges-medecin-missions', info, true);
  await page.getByRole('button', { name: /Assurance RCP/ }).click();
  await expect(page).toHaveURL(/\/soignant\/mes-documents\?tab=justificatifs$/);
  await expect(page.getByRole('heading', { name: 'Mes documents', exact: true })).toBeVisible();
  await aller(page, '/soignant/mes-gains');
  await page.getByRole('link', { name: 'Mes charges et mon régime fiscal' }).click();
  await expect(page.getByRole('heading', { name: 'Mes charges sociales', exact: true })).toBeVisible();
  const retourPage = page.getByRole('button', { name: 'Retour aux gains', exact: true });
  if (await retourPage.isVisible()) await retourPage.click();
  else await page.getByRole('banner').getByRole('button', { name: 'Retour', exact: true }).click();
  await expect(page).toHaveURL(/\/soignant\/mes-gains$/);
  expect(etat.errors).toEqual([]); expect(etat.unknown).toEqual([]);
});

test('charges — RCP issue du document vérifié, valide puis expirée, sans montant supposé', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  Object.assign(etat.profile, { profession: 'MEDECIN', type_exercice: 'LIBERAL', statut_liberal: 'ACTIF' });
  const document = { id: 'rcp-recette', soignant_id: ids.user, type_document: 'RCP_ASSURANCE', statut_verification: 'VERIFIE', supprime_le: null, valide_jusqua: new Date(Date.now() + 90 * 86400000).toISOString() as string | null };
  etat.tables.set('documents_soignants', [document]);
  await entrer(page, 'connexion'); await aller(page, '/soignant/charges');
  const carte = page.getByRole('button', { name: /Assurance RCP/ });
  await expect(carte).toContainText('✅ Valide'); await expect(carte).not.toContainText('400');
  document.valide_jusqua = new Date(Date.now() - 2 * 86400000).toISOString();
  await recharger(page); await expect(carte).toContainText('❌ Expirée');
  document.valide_jusqua = null;
  await recharger(page); await expect(carte).toContainText('RCP vérifiée — date d’expiration non renseignée.');
  await expect(carte).not.toContainText('Aucune RCP vérifiée');
  await preuve(page, 'charges-rcp-expiration-document', info, true); await sansDebordement(page);
  expect(etat.errors).toEqual([]); expect(etat.unknown).toEqual([]);
});

test('charges — panne visible, reprise et régime inconnu sans sélection implicite', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  Object.assign(etat.profile, { profession: 'MEDECIN', type_exercice: 'LIBERAL', statut_liberal: 'ACTIF' });
  await entrer(page, 'connexion'); etat.failures.add('missions'); await aller(page, '/soignant/charges');
  await expect(page.getByRole('alert')).toContainText('Impossible de charger tes informations.');
  etat.failures.delete('missions'); await page.getByRole('button', { name: 'Réessayer' }).click();
  await expect(page.getByRole('heading', { name: 'Aucune mission libérale terminée cette année' })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Micro-BNC/ })).toHaveAttribute('aria-pressed', 'false');
  await expect(page.getByRole('button', { name: /^Déclaration contrôlée/ })).toHaveAttribute('aria-pressed', 'false');
  await recharger(page); await expect(page.getByText('Régime fiscal à renseigner', { exact: true })).toBeVisible();
  await preuve(page, 'charges-reprise-sans-regime', info, true); await sansDebordement(page);
  expect(etat.errors).toEqual([]); expect(etat.unknown).toEqual([]);
});

test('charges — sauvegarde vérifiée, erreur sans faux succès et clics concurrents', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  Object.assign(etat.profile, { type_exercice: 'LIBERAL', statut_liberal: 'ACTIF' });
  await entrer(page, 'connexion'); await aller(page, '/soignant/charges');
  let mode: 'erreur' | 'vide' | 'lent' = 'erreur', appels = 0;
  let liberer = () => {};
  await page.route('**/rest/v1/soignants?*', async route => {
    if (route.request().method() !== 'PATCH') return route.fallback();
    appels++;
    if (mode === 'erreur') return route.fulfill({ status: 503, json: { message: 'Indisponible' } });
    if (mode === 'vide') return route.fulfill({ json: {} });
    await new Promise<void>(resolve => { liberer = resolve; });
    Object.assign(etat.profile, route.request().postDataJSON());
    return route.fulfill({ json: { regime_fiscal: etat.profile.regime_fiscal, regime_fiscal_confirme: true } });
  });
  const declaration = page.getByRole('button', { name: /^Déclaration contrôlée/ });
  await declaration.click(); await expect(page.getByText(/Impossible d'enregistrer ton régime fiscal/).first()).toBeVisible();
  await expect(declaration).toHaveAttribute('aria-pressed', 'false');
  mode = 'vide'; await declaration.click(); await expect.poll(() => appels).toBe(2); await expect(declaration).toBeEnabled();
  await expect(declaration).toHaveAttribute('aria-pressed', 'false');
  mode = 'lent'; await declaration.click(); await expect.poll(() => appels).toBe(3);
  try {
    await expect(declaration).toBeDisabled(); await declaration.dispatchEvent('click'); expect(appels).toBe(3);
  } finally { liberer(); }
  await expect(declaration).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByText('Régime déclaration contrôlée enregistré', { exact: true })).toBeVisible();
  await recharger(page); await expect(declaration).toHaveAttribute('aria-pressed', 'true');
  await preuve(page, 'charges-regime-enregistre', info, true); await sansDebordement(page);
  expect(etat.errors).toEqual([]); expect(etat.unknown).toEqual([]);
});
