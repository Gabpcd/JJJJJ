import { expect, test } from '@playwright/test';
import { allerA, email, entrer, preuve, simulerEtablissement } from './helpers/recette-complete-etablissement';

const invitation = '/etab/invitation/79000000-0000-4000-8000-000000000099';

test('invitation équipe : connexion conserve le lien puis acceptation explicite', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page, 'minimal');
  // Aucun rôle/établissement avant l'acceptation, même pas un brouillon existant.
  etat.overrides.set('parcours_inscription', null);
  const acceptations: unknown[] = [];
  await page.route('**/rest/v1/rpc/fn_accepter_invitation_membre', async route => {
    acceptations.push(route.request().postDataJSON());
    etat.mode = 'complet';
    await route.fulfill({ json: { success: true } });
  });
  await page.goto(invitation);
  await expect(page).toHaveURL(/\/connexion\?return=/);
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Mot de passe', { exact: true }).fill('Mot!Solide-Recette2026');
  await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`${invitation}$`));
  await expect(page.getByRole('heading', { name: 'Invitation à rejoindre une équipe' })).toBeVisible();
  expect(acceptations).toEqual([]);
  await preuve(page, 'invitation-apres-connexion', info);
  await page.getByRole('button', { name: "Accepter l'invitation", exact: true }).click();
  await expect(page.getByText("Bienvenue dans l'équipe !", { exact: true })).toBeVisible();
  await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
  await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached();
  await expect(page.getByText('Votre compte est créé', { exact: true })).toHaveCount(0);
  expect(acceptations).toEqual([{ p_token: invitation.split('/').pop() }]);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
});

test('invitation équipe : erreurs métier françaises et panne récupérable', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  let code = 'INVITATION_EXPIREE';
  let panne = false;
  let appels = 0;
  await page.route('**/rest/v1/rpc/fn_accepter_invitation_membre', async route => {
    appels++;
    await route.fulfill(panne
      ? { status: 503, json: { message: 'Service Unavailable' } }
      : { json: code ? { success: false, error_code: code, error: 'Internal diagnostic' } : { success: true } });
  });
  await entrer(page, 'connexion');
  for (const [erreur, message] of [
    ['INVITATION_EXPIREE', 'Cette invitation a expiré (>7 jours).'],
    ['EMAIL_INCORRECT', 'Cette invitation est pour une autre adresse e-mail. Reconnectez-vous avec le bon compte.'],
    ['TOKEN_INVALIDE', "Le lien d'invitation est invalide."],
    ['INVITATION_TRAITEE', 'Cette invitation a déjà été traitée.'],
  ]) {
    code = erreur;
    await allerA(page, invitation);
    await page.getByRole('button', { name: "Accepter l'invitation", exact: true }).click();
    await expect(page.getByText(message, { exact: true })).toBeVisible();
    await preuve(page, `invitation-${erreur}`, info);
  }
  panne = true;
  await allerA(page, invitation);
  await page.getByRole('button', { name: "Accepter l'invitation", exact: true }).click();
  await expect(page.getByText('Une erreur est survenue. Veuillez réessayer.', { exact: true })).toBeVisible();
  await expect(page.locator('main')).not.toContainText('Service Unavailable');
  await preuve(page, 'invitation-panne-francaise', info);
  panne = false; code = '';
  await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
  expect(appels).toBe(6);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
});
