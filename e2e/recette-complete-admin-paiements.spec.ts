import { expect, test, type Page } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Contrat UI simulé uniquement. Aucune preuve de paiement/remboursement Stripe.
const litigeId = '79000000-0000-4000-8000-000000000099';
async function preparer(page: Page, resultat: unknown, resolu: boolean, avantReponse?: Promise<void>) {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('messages_litige', []);
  const litige = {
    id: litigeId, motif: 'Annulation fictive de recette', statut: 'REVUE_ADMIN',
    cree_le: '2026-09-28T12:00:00Z', soignant_id: ids.soignant, etablissement_id: ids.etab,
    mission_id: ids.mission, initie_par: 'ETABLISSEMENT', accord_soignant: true, accord_etablissement: true,
    accord_soignant_le: '2026-09-28T12:01:00Z', accord_etablissement_le: '2026-09-28T12:02:00Z',
    modifications_executees: false, payload_modifications: { type: 'ANNULATION_TOTALE', modifications: { motif_annulation: 'Annulation de recette' }, justification: 'Accord fictif entre les deux parties' },
    missions: { id: ids.mission, intitule: 'Mission de recette financière', debut_le: '2026-10-01T07:00:00Z' },
    soignants: { id: ids.soignant, prenom: 'Camille', nom: 'Recette', profession: 'IDE' },
    etablissements: { id: ids.etab, nom: 'Établissement de recette' },
  };
  etat.overrides.set('litiges', [litige]);
  let appels = 0;
  await page.route('**/rest/v1/rpc/fn_admin_valider_accord_litige', async route => {
    expect(route.request().postDataJSON()).toEqual({ p_litige_id: litigeId });
    appels++;
    await avantReponse;
    if (resolu) { litige.statut = 'RESOLU_ADMIN'; litige.modifications_executees = true; }
    await route.fulfill({ json: resultat });
  });
  await page.addInitScript(({ id }) => {
    sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-28T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
      expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    }));
  }, { id: ids.user });
  await page.goto(`/admin/litiges?litige=${litigeId}`);
  await expect(page.getByRole('heading', { name: 'Litiges — Supervision admin', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Valider l’accord et exécuter', exact: true })).toBeVisible();
  return { etat, appels: () => appels };
}

test('admin — accord financier : une seule requête pendant une réponse lente', async ({ page }, info) => {
  let terminer!: () => void;
  const attente = new Promise<void>(resolve => { terminer = resolve; });
  const { etat, appels } = await preparer(page, {
    success: true, statut: 'RESOLU_ADMIN', execution: { success: true },
  }, true, attente);
  try {
    const action = page.getByRole('button', { name: 'Valider l’accord et exécuter', exact: true });
    await action.click();
    await page.getByRole('alertdialog').getByRole('button', { name: 'Confirmer et exécuter', exact: true }).click();
    await expect.poll(appels).toBe(1);
    await expect(action).toBeDisabled();
    await preuve(page, 'accord-validation-en-attente', info);
    // Même un clic supplémentaire sur le bouton désactivé ne doit rien émettre.
    await action.click({ force: true });
    expect(appels()).toBe(1);
  } finally { terminer(); }
  await expect(page.getByText(confirmation, { exact: true })).toBeVisible();
  await stabiliserLectures(page);
  expect(appels()).toBe(1);
  expect(etat.inconnues).toEqual([]);
  expect(etat.erreurs).toEqual([]);
});

const confirmation = 'Accord validé. Consultez le suivi des paiements pour confirmer le traitement financier.';
const incertain = 'La validation n’a pas été confirmée. Actualisez le dossier avant de réessayer.';
for (const scenario of [
  { nom: 'remboursement en attente', resultat: { success: true, statut: 'RESOLU_ADMIN', execution: { success: true, refund_enfile: true } }, resolu: true, message: confirmation },
  { nom: 'réponse vide', resultat: null, resolu: false, message: incertain },
  { nom: 'succès incomplet', resultat: { success: true }, resolu: false, message: incertain },
  { nom: 'refus métier', resultat: { success: false, error: 'Aucun accord financier complet à valider sur ce litige' }, resolu: false, message: 'Aucun accord financier complet à valider sur ce litige' },
  { nom: 'réponse perdue après validation', resultat: null, resolu: true, message: incertain },
]) {
  test(`admin — accord financier : ${scenario.nom}`, async ({ page }, info) => {
    const { etat, appels } = await preparer(page, scenario.resultat, scenario.resolu);
    await preuve(page, 'accord-avant-validation', info);
    await page.getByRole('button', { name: 'Valider l’accord et exécuter', exact: true }).click();
    const dialog = page.getByRole('alertdialog');
    await expect(dialog).toContainText('Mission de recette financière');
    await dialog.getByRole('button', { name: 'Confirmer et exécuter', exact: true }).click();
    await expect(page.getByText(scenario.message, { exact: true })).toBeVisible();
    await info.attach('notification-financiere', {
      body: await page.getByText(scenario.message, { exact: true }).ariaSnapshot(), contentType: 'text/plain',
    });
    await expect(page.getByText('Accord validé — mouvement financier exécuté.', { exact: true })).toHaveCount(0);
    const dossier = page.locator(`[data-litige-id="${litigeId}"]`);
    await expect(dossier).toHaveAttribute('data-statut', scenario.resolu ? 'RESOLU_ADMIN' : 'REVUE_ADMIN');
    expect(appels()).toBe(1);
    await stabiliserLectures(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
    await preuve(page, 'accord-apres-validation', info);
    await page.reload();
    if (scenario.resolu) await page.getByRole('button', { name: /^Résolus 1$/ }).click();
    await expect(dossier).toHaveAttribute('data-statut', scenario.resolu ? 'RESOLU_ADMIN' : 'REVUE_ADMIN');
    expect(appels()).toBe(1);
    expect(etat.inconnues).toEqual([]);
    expect(etat.erreurs).toEqual([]);
  });
}
