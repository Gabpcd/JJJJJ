import { test, expect, type Download } from '@playwright/test';
import { simulerSoignant, entrer, aller, preuve, ids, simulations } from './helpers/recette-complete-soignant';

test.use({ actionTimeout: 15_000 });
test.afterEach(async ({ page }, info) => {
  const state = simulations.get(page);
  if (state) await info.attach('appels-api-simules', { body: JSON.stringify(state, null, 2), contentType: 'application/json' });
});

async function contenuTelecharge(download: Download) {
  const stream = await download.createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks).toString('utf8');
}

test('SOIGNANT — export des données JSON et CSV, puis refus explicite sans fichier erreur', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  const donnees = { profil: { id: ids.user, prenom: 'Camille', nom: 'Recette' }, missions: [] };
  state.overrides.set('fn_rgpd_exporter_rate_limited', donnees);
  await entrer(page, 'connexion');
  await aller(page,'/soignant/profil?tab=confidentialite');
  await expect(page.getByRole('tab', { name: 'Confidentialité', exact: true })).toHaveAttribute('aria-selected', 'true');
  for (const format of ['JSON', 'CSV']) {
    const telechargement = page.waitForEvent('download');
    await page.getByRole('button', { name: `Exporter ${format}`, exact: true }).click();
    const fichier = await telechargement;
    expect(fichier.suggestedFilename()).toMatch(new RegExp(`^mes-donnees-jolene-\\d{4}-\\d{2}-\\d{2}\\.${format.toLowerCase()}$`));
    const contenu = await contenuTelecharge(fichier);
    if (format === 'JSON') expect(JSON.parse(contenu)).toEqual(donnees);
    else { expect(contenu).toContain('Champ,Valeur'); expect(contenu).toContain('"profil.prenom","Camille"'); }
    await expect(page.getByText(`Données exportées en ${format}.`, { exact: true })).toBeVisible();
  }
  let fichierErreur = false;
  page.on('download', () => { fichierErreur = true; });
  state.overrides.set('fn_rgpd_exporter_rate_limited', { error: 'Limite de simulation : deux exports par jour.' });
  await page.getByRole('button', { name: 'Exporter JSON', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Limite de simulation : deux exports par jour.');
  await expect(page.getByRole('button', { name: 'Exporter JSON', exact: true })).toBeEnabled();
  expect(fichierErreur).toBe(false);
  await preuve(page, 'compte-export-refuse', info);
  expect(state.calls.filter(c => c.name === 'fn_ecrire_audit_safe' && c.body.p_action === 'RGPD_EXPORT_DONNEES').map(c => c.body.p_details.format)).toEqual(['json', 'csv']);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('SOIGNANT — suppression compte annulée, refusée puis simulée avec déconnexion', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  state.overrides.set('delete-account', { success: true });
  state.overrides.set('fn_missions_publiques_recherche', []);
  await entrer(page, 'connexion');
  await aller(page,'/soignant/mon-compte');
  await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
  await expect(page).toHaveURL(/profil\?tab=confidentialite#suppression-compte$/);
  await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Supprimer définitivement', exact: true })).toBeDisabled();
  await page.getByPlaceholder('Tape SUPPRIMER', { exact: true }).fill('SUPPRIMER');
  await page.getByRole('button', { name: 'Annuler', exact: true }).click();
  expect(state.calls.some(c => c.name === 'delete-account')).toBe(false);
  await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
  await expect(page.getByPlaceholder('Tape SUPPRIMER', { exact: true })).toHaveValue('');
  await page.getByPlaceholder('Tape SUPPRIMER', { exact: true }).fill('SUPPRIMER');
  state.failures.add('delete-account');
  await page.getByRole('button', { name: 'Supprimer définitivement', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText(/erreur|impossible|status code/i);
  await expect(page).toHaveURL(/soignant\/profil/);
  await preuve(page, 'compte-suppression-refusee', info);
  state.failures.clear();
  await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
  await page.getByPlaceholder('Tape SUPPRIMER', { exact: true }).fill('SUPPRIMER');
  await page.getByRole('button', { name: 'Supprimer définitivement', exact: true }).click();
  await expect(page).not.toHaveURL(/\/soignant\//);
  await aller(page,'/soignant/mes-documents');
  await expect(page).toHaveURL(/\/connexion/);
  expect(state.calls.filter(c => c.name === 'delete-account')).toHaveLength(2);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});
