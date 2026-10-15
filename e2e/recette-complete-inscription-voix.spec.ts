import { expect, test } from '@playwright/test';
import { ouvrirDossierDepuisMission, remplirIdentite, simulerCompletionSoignant } from './helpers/recette-complete-completion-soignant';
import { aller, attendreAPI, ids, preuve, simulerSoignant } from './helpers/recette-complete-soignant';

for (const type of ['SOIGNANT', 'ETABLISSEMENT'] as const) {
  test(`inscription ${type} : confirmation sur l’origine web courante, Auth et email simulés`, async ({ page }, info) => {
    const state = await simulerSoignant(page, 'minimal');
    // Pas de session ni d'envoi d'email : le SDK réel reçoit la réponse Auth
    // d'un compte qui attend une confirmation, entièrement interceptée.
    state.overrides.set('signup', {
      id: ids.user, email: 'confirmation-origine@example.invalid',
      aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {},
      identities: [{ id: 'confirmation-simulee', provider: 'email' }],
    });
    const path = type === 'SOIGNANT' ? '/inscription/soignant' : '/inscription/etablissement';
    await page.goto(path);
    await expect(page.getByRole('heading', { name: 'Créez votre compte.', exact: true })).toBeVisible();
    const origin = new URL(page.url()).origin;
    expect(origin).not.toBe('https://jolene.app');
    await page.getByLabel('Email', { exact: true }).fill('confirmation-origine@example.invalid');
    await page.getByLabel('Mot de passe', { exact: true }).fill('Recette!Origine-2026');
    if (type === 'SOIGNANT') await page.getByLabel('Profession', { exact: true }).selectOption('IDE');
    else await page.getByLabel('Nom de l’établissement', { exact: true }).fill('Établissement confirmation simulée');
    await page.getByRole('checkbox', { name: /CGU/ }).check();
    if (type === 'ETABLISSEMENT') await page.getByRole('checkbox', { name: /conditions générales de vente/ }).check();
    await page.getByRole('button', { name: 'Créer mon compte', exact: true }).click();
    await expect(page.getByRole('status')).toContainText('Un lien de confirmation vient de vous être envoyé.');
    await expect(page.getByRole('button', { name: 'J’ai confirmé mon email', exact: true })).toBeEnabled();
    await expect(page).toHaveURL(new RegExp(`${path}$`));
    const requests = state.calls.filter(call => call.name === 'signup');
    expect(requests).toHaveLength(1);
    expect(requests[0].method).toBe('POST');
    expect(new URL(requests[0].url, origin).searchParams.get('redirect_to')).toBe(`${origin}/inscription/confirmer`);
    expect(requests[0].body.data.inscription_progressive.type).toBe(type);
    expect(state.calls.some(call => ['fn_demarrer_inscription', 'register-soignant', 'register-etablissement', 'send-email'].includes(call.name))).toBe(false);
    await preuve(page, `inscription-${type.toLowerCase()}-confirmation-origine-simulee`, info);
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Créez votre compte.', exact: true })).toBeVisible();
    await expect(page.getByLabel('Email', { exact: true })).toHaveValue('');
    await expect(page.getByRole('status')).toHaveCount(0);
    expect(state.calls.filter(call => call.name === 'signup')).toHaveLength(1);
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
  });
}

test('inscription : vouvoiement du dossier et de ses erreurs, retour libre à l’espace soignant', async ({ page }, info) => {
  const { state, completion } = await simulerCompletionSoignant(page);
  state.overrides.set('fn_types_exercice_autorises', ['SALARIE']);
  await page.goto('/inscription/soignant');
  await expect(page.getByRole('heading', { name: 'Créez votre compte.', exact: true })).toBeVisible();
  await expect(page.getByText('Découvrez les missions. Votre dossier professionnel se complète ensuite.', { exact: true })).toBeVisible();
  await attendreAPI(page);
  await ouvrirDossierDepuisMission(page);
  await expect(page.getByText('Le mode libéral n’est pas proposé pour votre profession sur Jolene. Le mode salarié comprend les CDD et les CDD courts.', { exact: true })).toBeVisible();
  await remplirIdentite(page);
  completion.professionRppsCorrespond = false;
  await page.getByPlaceholder(/^11 chiffres/).fill('10000000000');
  const alerte = page.getByRole('alert').filter({ hasText: 'Ce RPPS correspond à la profession' });
  await expect(alerte).toContainText('Vérifiez votre numéro ou votre profession.');
  await expect(page.getByRole('heading', { name: 'Vos informations professionnelles', exact: true })).toBeVisible();
  await expect(page.locator('form')).not.toContainText(/\b(?:[Tt]u|[Tt]on|[Tt]a|[Tt]es|[Tt]e)\b/);
  await page.getByRole('button', { name: 'Enregistrer mon profil', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Vérifiez les informations suivantes' })).toContainText('cohérence du RPPS');
  expect(completion.soumissions).toEqual([]);
  await preuve(page, 'inscription-voix-vous-erreur-rpps', info, true);
  await aller(page, '/soignant/tableau-de-bord');
  await expect(page.locator('main')).toContainText(/Tes missions|tes missions|ton profil|ton compte|tu peux/);
  await preuve(page, 'espace-soignant-voix-conservee', info);
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});
