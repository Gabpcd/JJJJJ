import { expect, test } from '@playwright/test';
import { attendreAPI, preuve, recharger, sansDebordement, simulerSoignant } from './helpers/recette-complete-soignant';
import { manifestePoolDashboard } from '../scripts/ci/prepare-dashboard-pool.mjs';

// Simulation locale du profil minimal construit par le banc E10. Les véritables
// identités staging et la navigation pendant k6 restent une recette distincte.
test.use({ actionTimeout: 15_000 });
const membres = manifestePoolDashboard('frontend-E10-local').membres;
for (const slot of [0, 1]) {
  test(`E10 — profil minimal ${slot}, compte exact et reprise`, async ({ page }, info) => {
    const m = membres[slot], voisin = membres[1 - slot];
    const state = await simulerSoignant(page);
    Object.assign(state.profile, { id: m.userId, email: m.email, prenom: m.prenom, nom: m.nom,
      profession: 'AS', type_exercice: 'SALARIE', telephone: null, numero_rpps: null, numero_adeli: null,
      identite_verifiee: false, diplome_verifie: false, rpps_verifie: false, tous_documents_valides: false,
      sms_actif: false, sms_alertes_actives: false, est_compte_test: true });
    state.preferences.global = { canal_email: false, canal_sms: false, canal_push: false, canal_in_app: false };
    const user = { id: m.userId, email: m.email, aud: 'authenticated', role: 'authenticated',
      email_confirmed_at: '2026-09-30T08:00:00Z', app_metadata: { role: 'SOIGNANT', est_compte_test: true }, user_metadata: {} };
    state.overrides.set('user', user);
    state.overrides.set('token', { user, access_token: `simulation-E10-${slot}`, refresh_token: `simulation-refresh-${slot}`,
      token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600 });
    await page.goto('/connexion');
    await page.getByLabel('Email', { exact: true }).fill(m.email);
    await page.getByLabel('Mot de passe', { exact: true }).fill('Mot!Solide-Recette2026');
    await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
    await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
    await expect(page.locator('main').getByRole('heading', { level: 1 })).toContainText('Recette');
    expect(state.calls.some(c => c.name === 'fn_dashboard_soignant_complet')).toBe(true);
    await attendreAPI(page);
    await preuve(page, `dashboard-E10-${slot}`, info);

    const sidebar = page.getByRole('navigation', { name: 'Sidebar', exact: true });
    const compte = await sidebar.isVisible()
      ? sidebar.getByRole('button', { name: 'Mon compte', exact: true })
      : page.getByRole('navigation', { name: 'Navigation mobile', exact: true }).getByRole('button', { name: 'Profil', exact: true });
    await compte.click();
    await expect(page).toHaveURL(/\/soignant\/mon-compte$/);
    await expect(page.getByRole('heading', { name: `${m.prenom} ${m.nom}`, exact: true })).toBeVisible();
    await expect(page.getByText(voisin.nom, { exact: false })).toHaveCount(0);
    await recharger(page);
    await expect(page.getByRole('heading', { name: `${m.prenom} ${m.nom}`, exact: true })).toBeVisible();
    await expect(page.getByText(voisin.nom, { exact: false })).toHaveCount(0);
    await attendreAPI(page);
    expect(state.calls.find(c => c.name === 'token')?.body.email).toBe(m.email);
    expect(state.calls.some(c => c.name === 'soignants' && c.url.includes(`id=eq.${m.userId}`))).toBe(true);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    await sansDebordement(page);
    await preuve(page, `compte-E10-${slot}-recharge`, info, true);
  });
}
