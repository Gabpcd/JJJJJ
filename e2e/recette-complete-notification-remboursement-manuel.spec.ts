import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Simulation de consultation : aucun virement, remboursement, SQL ou envoi réel.
test('admin — notification de remboursement manuel, onglet Avoirs, panne et rechargement', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('fn_admin_incoherences_identite', []);
  etat.overrides.set('documents_soignants', []);
  await page.route('**/rest/v1/stripe_refunds_queue?*', async route => {
    expect(route.request().method()).toBe('GET');
    expect(new URL(route.request().url()).searchParams.get('statut')).toBe('in.(EN_ATTENTE,EN_COURS)');
    await route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*',
      'access-control-expose-headers': 'content-range', 'content-range': '*/0' } });
  });
  etat.overrides.set('soignants', [{ id: ids.soignant, prenom: 'Camille', nom: 'Recette' }]);
  etat.overrides.set('etablissements', [{ id: ids.etab, nom: 'Établissement de recette' }]);
  const avoir = { id: ids.facture, numero_facture: 'AV-RECETTE-001', type_document: 'AVOIR', statut: 'EMISE',
    mode_remboursement: 'VIREMENT_MANUEL', montant_ht: 60, montant_tva: 12, montant_ttc: 72,
    date_emission: '2026-10-01T10:00:00Z', date_remboursement: null, reference_remboursement: null,
    soignant_id: ids.soignant, etablissement_id: ids.etab, litige_id: null };
  etat.overrides.set('factures_honoraires', [avoir]);
  await page.route('**/rest/v1/factures_honoraires?*', async route => {
    expect(route.request().method()).toBe('GET');
    await route.fallback();
  });
  const notification = { id: '79000000-0000-4000-8000-000000000091', destinataire_id: ids.user,
    titre: '💸 Remboursement manuel à traiter', corps: 'Avoir AV-RECETTE-001 — 72,00 €. Remboursement manuel à traiter et à confirmer après vérification de la preuve bancaire.',
    type: 'REMBOURSEMENT_MANUEL_A_FAIRE', lien: '/admin/moderation?onglet=avoirs',
    lue: false, cree_le: '2026-10-01T10:00:00Z' };
  let marquages = 0;
  await page.route('**/rest/v1/notifications?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(url.searchParams.get('destinataire_id')).toBe(`eq.${ids.user}`);
    if (req.method() === 'PATCH') {
      expect(url.searchParams.get('id')).toBe(`in.(${notification.id})`);
      expect(req.postDataJSON()).toMatchObject({ lue: true });
      marquages++; notification.lue = true;
      return route.fulfill({ status: 204 });
    }
    expect(['GET', 'HEAD']).toContain(req.method());
    return route.fulfill({ json: req.method() === 'GET' ? [notification] : undefined, body: req.method() === 'HEAD' ? '' : undefined,
      headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': notification.lue ? '*/0' : '0-0/1' } });
  });
  await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
    user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-10-01T10:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
    access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
    expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  })), { id: ids.user });

  await page.goto('/admin/moderation?onglet=documents&origine=recette');
  await expect(page.getByRole('tab', { name: /^Documents/ })).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('button', { name: /^Notifications/ }).first().click();
  await expect(page.getByText(notification.corps, { exact: true })).toBeVisible();
  etat.pannes.add('factures_honoraires');
  await page.getByText(notification.titre, { exact: true }).click();
  await expect(page).toHaveURL(/\/admin\/moderation\?onglet=avoirs$/);
  await expect(page.getByRole('tab', { name: 'Avoirs', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByTestId('avoirs-list')).toContainText('Avoirs indisponibles');
  await expect(page.getByText('Aucun avoir à rembourser', { exact: true })).toHaveCount(0);
  await preuve(page, 'notification-avoir-erreur', info);
  etat.pannes.delete('factures_honoraires');
  await page.getByTestId('avoirs-list').getByRole('button', { name: 'Réessayer', exact: true }).click();
  const ligne = page.locator(`[data-avoir-id="${ids.facture}"]`);
  await expect(ligne).toContainText('AV-RECETTE-001');
  await expect(ligne).toContainText('Camille Recette');
  await expect(ligne).toContainText('Établissement de recette');
  await expect(ligne).toContainText('Virement manuel requis');
  await expect(ligne).toContainText('Émis — en attente remboursement');
  for (const valeur of ['AV-RECETTE-001', '60,00 €', '12,00 €', '72,00 €']) {
    const cellule = ligne.getByRole('cell', { name: valeur, exact: true });
    await expect(cellule).toBeVisible();
    expect(await cellule.evaluate(element => {
      const range = document.createRange();
      range.selectNodeContents(element);
      return new Set([...range.getClientRects()].map(rect => Math.round(rect.top))).size;
    }), `${valeur} doit rester sur une ligne`).toBe(1);
  }
  await expect.poll(() => marquages).toBe(1);
  await preuve(page, 'notification-avoir-reprise', info);
  await page.screenshot({ path: info.outputPath('avoir-lisible.png'), fullPage: true, animations: 'disabled' });
  await ligne.getByRole('button', { name: 'Confirmer remboursement avoir AV-RECETTE-001', exact: true }).click();
  const dialogue = page.getByRole('dialog');
  await expect(dialogue.getByRole('heading', { name: 'Confirmer le remboursement manuel' })).toBeVisible();
  await expect(dialogue.getByRole('button', { name: 'Confirmer 72,00 € TTC', exact: true })).toBeDisabled();
  await preuve(page, 'confirmation-manuelle-non-validee', info);
  await dialogue.getByRole('button', { name: 'Annuler', exact: true }).click();
  await stabiliserLectures(page);
  await page.reload();
  await expect(page.getByRole('tab', { name: 'Avoirs', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(ligne).toBeVisible();
  await page.getByRole('tab', { name: /^Documents/ }).click();
  await expect(page).toHaveURL(/onglet=documents/);
  await stabiliserLectures(page);
  await page.reload();
  await expect(page.getByRole('tab', { name: /^Documents/ })).toHaveAttribute('aria-selected', 'true');
  await stabiliserLectures(page);
  await page.goto('/admin/moderation?onglet=inconnu&origine=recette');
  await expect(page.getByRole('tab', { name: /^Litiges/ })).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('tab', { name: 'Avoirs', exact: true }).click();
  await expect(page).toHaveURL(/onglet=avoirs&origine=recette$/);
  await expect(ligne).toBeVisible();
  await stabiliserLectures(page);
  await expect(page.getByRole('alert')).toHaveCount(0);
  await preuve(page, 'onglet-avoir-conserve', info);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
  expect(etat.operations).toEqual([]); expect(etat.ecritures).toEqual([]);
  expect(avoir.date_remboursement).toBeNull();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
});
