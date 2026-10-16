import { expect, test } from '@playwright/test';
import { simulerEtablissement, entrer, allerA, stabiliserLectures, etablissement, ids } from './helpers/recette-complete-etablissement';

// Réponses intégralement fictives : aucun prélèvement, fournisseur ou publication.
test('Commission négociée groupe : dashboard et estimation mission utilisent le taux effectif après recharge', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page); etat.donnees = true;
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, taux_commission_negocie: null,
    taux_commission_effectif: 12, groupe_sante_id: '79000000-0000-4000-8000-000000000099',
    groupes_sante: { nom: 'Groupe de recette', taux_commission_negocie: 12 } });
  await entrer(page, 'connexion');
  await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
  await expect(page.getByText('12 % HT', { exact: true })).toBeVisible();
  await expect(page.getByText('14,4 % TTC', { exact: true })).toBeVisible();
  await allerA(page, `/etablissement/missions/${ids.mission}/modifier`);
  for (const recharge of [false, true]) {
    if (recharge) { await stabiliserLectures(page); await page.reload(); }
    await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('Renfort IDE — recette complète');
    const estimation = page.getByText('Frais Jolene distincts', { exact: true }).locator('..').locator('..');
    await expect(estimation).toContainText('12% HT');
    await expect(estimation).toContainText('14,4% TTC');
    await expect(estimation).toContainText('~43.20 €');
    await expect(estimation).toContainText('~51.84 €');
    await expect(estimation).not.toContainText('15%');
  }
  await info.attach('commission-groupe-simulation', { body: JSON.stringify({ simulation: true,
    groupRateHT: 12, baseEstimee: 360, commissionHT: 43.2, commissionTTC: 51.84,
    published: false, backendVerified: false }), contentType: 'application/json' });
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
  expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
});

test('Admin SEPA : demande initiée sans annoncer encaissement confirmé, facture encore émise après recharge', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('fn_admin_lister_revues_tva_missions', []);
  const facture = { id: ids.facture, numero_facture: 'COM-SEPA-SIMULATION-001', type_document: 'FACTURE', statut: 'EMISE',
    montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4, montant_signe: 12,
    date_emission: '2026-10-01', date_echeance: '2026-10-31', nombre_missions: 1,
    etablissement_id: ids.etab, etablissements: { nom: 'Établissement SEPA fictif', est_compte_test: false } };
  etat.overrides.set('factures', [facture]);
  let demandes = 0;
  await page.route('**/functions/v1/sepa-auto-charge', async route => {
    expect(['127.0.0.1', 'localhost']).toContain(new URL(route.request().url()).hostname);
    expect(route.request().method()).toBe('POST'); demandes++;
    expect(demandes).toBe(1);
    return route.fulfill({ json: { success: true, charged: 1, failed: 0, skipped_test: 0 }, headers: { 'access-control-allow-origin': '*' } });
  });
  await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
    user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-10-01T10:00:00Z',
      app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
    access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
    expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  })), { id: ids.user });
  await page.goto('/admin/facturation?q=COM-SEPA-SIMULATION-001');
  await expect(page.getByText(facture.numero_facture, { exact: true }).filter({ visible: true })).toBeVisible();
  await page.getByText('Exports et prélèvements', { exact: true }).click();
  await page.getByRole('button', { name: 'Prélever SEPA', exact: true }).click();
  await expect(page.getByText('1 prélèvement(s) SEPA initié(s) — confirmation bancaire à suivre', { exact: true })).toBeVisible();
  await expect(page.getByText(/facture\(s\) prélevée\(s\)|prélèvement\(s\) confirmé\(s\)/)).toHaveCount(0);
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText(facture.numero_facture, { exact: true }).filter({ visible: true })).toBeVisible();
  await expect(page.getByText('Émise', { exact: true }).filter({ visible: true })).toBeVisible();
  expect(facture.statut).toBe('EMISE'); expect(demandes).toBe(1);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
  await info.attach('sepa-lancement-simulation', { body: JSON.stringify({ simulation: true, sepaRequests: 1,
    invoiceStatus: 'EMISE', settlementClaimed: false, providerVerified: false }), contentType: 'application/json' });
});
