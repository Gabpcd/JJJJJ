import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

/**
 * Non-régression Lot 11 — mécanique UX établissement.
 * Garde les invariants de la passe UX : plus de FAB flottant, garde-fou 48h
 * désactivant, labels visibles sous les onglets Paramètres, un seul
 * « Se déconnecter ». Viewport mobile de référence : 390×844.
 */

test.use({ viewport: { width: 390, height: 844 } });

test.describe('Lot 11 — UX établissement', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'etab');
  });

  test('aucun FAB flottant ne recouvre le contenu', async ({ page }) => {
    await page.goto('/etablissement/tableau-de-bord');
    await page.waitForLoadState('networkidle');
    // Le FAB « + Publier » (fixed, rond, bas-droite) a été supprimé au Lot 11.
    const fabs = page.locator('button.fixed, a.fixed').filter({ hasText: /publier/i });
    await expect(fabs).toHaveCount(0);
  });

  test('publication bloquée au-delà de 48h hebdo (bouton désactivé + erreur unique)', async ({ page }) => {
    const publications: string[] = [];
    // Ce test lit un compte réel mais ne crée rien, même en cas de régression.
    await page.route('**/rest/v1/rpc/fn_creer_mission*', async route => {
      publications.push(route.request().url());
      await route.abort();
    });
    await page.goto('/etablissement/missions/creer');
    await page.waitForLoadState('networkidle');
    await page.getByLabel('Intitulé *', { exact: true }).fill('Recette du contrôle hebdomadaire — ne pas publier');
    await page.locator('#mission-profession').click();
    await page.getByRole('option', { name: /Infirmier.*Diplômé.*IDE/ }).click();
    await page.getByRole('radio', { name: /^Salarié/ }).check();
    await page.getByLabel('Taux horaire brut * (€/h)', { exact: true }).fill('30');
    const lundi = new Date();
    lundi.setUTCDate(lundi.getUTCDate() + 14 - (lundi.getUTCDay() + 6) % 7);
    const samedi = new Date(lundi); samedi.setUTCDate(samedi.getUTCDate() + 5);
    const date = lundi.toISOString().slice(0, 10);
    await page.getByLabel('Première date affichée *', { exact: true }).fill(date);
    await page.getByLabel('Dernière date affichée *', { exact: true }).fill(samedi.toISOString().slice(0, 10));
    await page.getByRole('button', { name: 'Toutes les dates', exact: true }).click();
    await page.getByLabel(`Début du créneau 1 du ${date}`, { exact: true }).fill('07:00');
    await page.getByLabel(`Fin du créneau 1 du ${date}`, { exact: true }).fill('16:00');
    await page.getByRole('button', { name: 'Appliquer le 1er horaire aux jours sélectionnés', exact: true }).click();
    await expect(page.getByRole('alert')).toHaveCount(1);
    await expect(page.getByRole('alert')).toContainText('54 h travaillées. Maximum légal : 48 h/semaine.');
    const publier = page.getByRole('button', { name: /^Publier la mission(?: \(\d+ créneaux\))?$/ });
    await expect(publier).toBeDisabled();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    // Cas permis : le blocage constaté doit venir des heures, pas du profil.
    await page.getByLabel(`Fin du créneau 1 du ${date}`, { exact: true }).fill('15:00');
    await page.getByRole('button', { name: 'Appliquer le 1er horaire aux jours sélectionnés', exact: true }).click();
    await expect(page.getByRole('alert')).toHaveCount(0);
    await expect(page.getByTestId('recap-semaines')).toContainText('48 h');
    await expect(publier).toBeEnabled();
    expect(publications).toEqual([]);
    // Preuve simulée exécutée sur cinq formats : recette-complete-recurrence-etablissement.spec.ts.
  });

  test('Paramètres : les 4 onglets ont un label visible sur mobile', async ({ page }) => {
    await page.goto('/etablissement/parametres');
    await page.waitForLoadState('networkidle');
    for (const label of ['Profil', 'Groupe', 'Config', 'Exclusions']) {
      await expect(page.getByRole('tab', { name: new RegExp(label, 'i') })).toBeVisible();
    }
  });

  test('un seul « Se déconnecter » (fin de Mon compte)', async ({ page }) => {
    await page.goto('/etablissement/parametres');
    await page.waitForLoadState('networkidle');
    // L'onglet Profil ne porte plus le doublon mobile.
    await expect(page.getByRole('button', { name: /se déconnecter/i })).toHaveCount(0);
    await page.goto('/etablissement/mon-compte');
    await page.waitForLoadState('networkidle');
    await expect(page.getByText(/se déconnecter/i)).toHaveCount(1);
  });

  test('Publier expose « Type de contrat proposé » avec conséquences', async ({ page }) => {
    await page.goto('/etablissement/missions/creer');
    await page.waitForLoadState('networkidle');
    await expect(page.getByText('Type de contrat proposé')).toBeVisible();
    await expect(page.getByText(/vous êtes l.employeur/i)).toBeVisible();
  });
});
