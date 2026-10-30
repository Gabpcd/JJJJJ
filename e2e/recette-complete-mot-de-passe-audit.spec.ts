import { test, expect } from '@playwright/test';
import { simulerSoignant, entrer, aller, preuve, sansDebordement } from './helpers/recette-complete-soignant';

test('confirme le nouveau mot de passe avant la réponse du journal et reste utilisable après sa panne', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  await entrer(page, 'connexion');
  await aller(page, '/soignant/mon-compte');
  const actuel = page.getByLabel('Mot de passe actuel', { exact: true });
  const nouveau = page.getByLabel('Nouveau mot de passe', { exact: true });
  const confirmation = page.getByLabel('Confirmer le nouveau mot de passe', { exact: true });
  await actuel.fill('MotActuel!123456');
  await nouveau.fill('MotNouveau!789Abc');
  await confirmation.fill('MotNouveau!789Abc');

  // Une réponse volontairement retenue, et non un délai ou une attente élargie,
  // prouve que le succès Auth n'attend plus le journal. Aucun fournisseur réel.
  let libererAudit!: () => void;
  const auditEnAttente = new Promise<void>(resolve => { libererAudit = resolve; });
  let appelsAudit = 0;
  let auditTermine = false;
  await page.route('**/rest/v1/rpc/fn_ecrire_audit_safe', async route => {
    if (route.request().method() === 'OPTIONS') return route.fallback();
    appelsAudit += 1;
    await auditEnAttente;
    await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ message: 'CANARI_AUDIT_NON_PUBLIC', code: '57014' }), headers: { 'access-control-allow-origin': '*' } });
    auditTermine = true;
  });
  try {
    await page.getByRole('button', { name: 'Modifier mon mot de passe', exact: true }).click();
    await expect.poll(() => appelsAudit).toBe(1);
    await expect(page.getByText('Mot de passe modifié avec succès.', { exact: true })).toBeVisible();
    expect(auditTermine).toBe(false);
    for (const champ of [actuel, nouveau, confirmation]) await expect(champ).toHaveValue('');
    expect(state.calls.filter(call => call.name === 'user' && call.method === 'PUT')).toHaveLength(1);
    await sansDebordement(page);
    await info.attach('confirmation-pendant-audit-en-attente', { body: await page.screenshot({ animations: 'disabled' }), contentType: 'image/png' });
  } finally {
    libererAudit();
  }
  await expect.poll(() => auditTermine).toBe(true);
  await expect(page.getByText('CANARI_AUDIT_NON_PUBLIC', { exact: false })).toHaveCount(0);
  await preuve(page, 'mot-de-passe-confirme-audit-indisponible', info, true);
  expect(appelsAudit).toBe(1);
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Changer mon mot de passe', exact: true })).toBeVisible();
  for (const champ of [actuel, nouveau, confirmation]) await expect(champ).toHaveValue('');
  expect(state.calls.filter(call => call.name === 'user' && call.method === 'PUT')).toHaveLength(1);
  await preuve(page, 'compte-recharge-sans-rejouer-la-modification', info, true);
  expect(state.unknown).toEqual([]);
  expect(state.errors).toEqual([]);
});
