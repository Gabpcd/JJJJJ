import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { articleAide, missionPublique, simulerPublic } from './helpers/recette-complete-public';
import { simulerSoignant, entrer as entrerSoignant } from './helpers/recette-complete-soignant';

async function preuve(page: Page, info: TestInfo, name: string) {
  await info.attach(`${name}.aria.yml`, { body: await page.locator('body').ariaSnapshot(), contentType: 'text/yaml' });
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth), { message: `${name} sans débordement horizontal` }).toBeLessThanOrEqual(2);
}

test('pages publiques : contenu, retours, liens légaux et absence de débordement', async ({ page }, info) => {
  test.setTimeout(180_000);
  const state = await simulerPublic(page);
  const routes: [string, string | RegExp][] = [
    ['/', 'Le remplacement santé, enfin simple.'], ['/tarifs', 'Nos tarifs — Transparence totale'],
    ['/devenir-soignant', 'Devenir soignant sur Jolene'], ['/recruter-soignants', 'Recrutez des soignants qualifiés, sans intermédiaire'],
    ['/infirmiere-liberale', 'Passer infirmière libérale avec Jolene'], ['/emploi-soignant/paris', 'Missions soignants à Paris'],
    ['/metier/infirmier-ide', /Missions Infirmier/], ['/a-propos', 'Simplifier le staffing médical. Pour de bon.'],
    ['/telecharger', 'Jolene dans votre poche'], ['/contact', 'Une question ? Écrivez-nous.'],
    ['/cgu', "Conditions Générales d'Utilisation"], ['/cgv', 'Conditions Générales de Vente'],
    ['/confidentialite', 'Politique de Confidentialité'], ['/politique-confidentialite', 'Politique de Confidentialité'],
    ['/mentions-legales', 'Mentions Légales'], ['/supprimer-mon-compte', 'Supprimer mon compte'],
    ['/accessibilite', 'Engagement accessibilité'], ['/aide/pro-sante-connect', 'Aide Pro Santé Connect'],
    ['/adresse-inexistante-recette', '404'],
  ];
  for (const [route, title] of routes) await test.step(route, async () => {
    await page.goto(route);
    await expect(page.getByRole('heading', { name: title, level: 1, exact: typeof title === 'string' })).toBeVisible();
    await preuve(page, info, route.replaceAll('/', '-') || 'accueil');
  });
  await page.getByRole('link', { name: "Retour à l'accueil" }).click();
  await expect(page).toHaveURL(/\/$/);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('mission publique : contenu, candidature, mission réellement clôturée', async ({ page }, info) => {
  const state = await simulerPublic(page);
  await page.goto(`/mission/${missionPublique.id}`);
  await expect(page.getByRole('heading', { name: missionPublique.intitule })).toBeVisible();
  await expect(page.getByText('30 €/h', { exact: true })).toBeVisible();
  await expect(page.getByText('CDD salarié · bulletin de paie', { exact: true })).toBeVisible();
  await preuve(page, info, 'mission-ouverte');
  await page.getByRole('link', { name: 'Postuler gratuitement' }).click();
  await expect(page).toHaveURL(/\/inscription\/soignant\?/);
  await expect(page.getByLabel('Email', { exact: true })).toBeVisible();
  state.missingMission = true;
  await page.goto(`/mission/${missionPublique.id}`);
  await expect(page.getByRole('heading', { name: "Cette mission n'est plus disponible" })).toBeVisible();
  await preuve(page, info, 'mission-fermee');
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('mission publique : une panne ne signifie pas que la mission est clôturée, reprise possible', async ({ page }, info) => {
  const state = await simulerPublic(page); state.failures.add('fn_mission_publique');
  await page.goto(`/mission/${missionPublique.id}`);
  await info.attach('mission-503.aria.yml', { body: await page.locator('body').ariaSnapshot(), contentType: 'text/yaml' });
  await expect(page.getByRole('heading', { name: 'Mission temporairement indisponible' })).toBeVisible();
  await expect(page.getByText(/Elle a été pourvue ou clôturée/)).toHaveCount(0);
  await preuve(page, info, 'mission-erreur');
  state.failures.clear();
  await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page.getByRole('heading', { name: missionPublique.intitule })).toBeVisible();
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('aide : recherche, filtres, article, retour et alias', async ({ page }, info) => {
  const state = await simulerPublic(page);
  for (const route of ['/aide', '/faq', '/help']) {
    await page.goto(route);
    await expect(page.getByRole('heading', { name: "Centre d'aide" })).toBeVisible();
    await expect(page.getByRole('link', { name: /Préparer une mission/ })).toBeVisible();
    await preuve(page, info, route.replaceAll('/', '-'));
  }
  await page.getByRole('button', { name: 'Soignant', exact: true }).click();
  await expect(page).toHaveURL(/aud=SOIGNANT/);
  await page.getByRole('button', { name: 'Établissement', exact: true }).click();
  await expect(page).toHaveURL(/aud=ETABLISSEMENT/);
  await page.getByRole('button', { name: 'Tous', exact: true }).click();
  await page.getByRole('searchbox').fill('introuvable');
  await expect(page.getByText('Aucun article ne correspond à "introuvable".')).toBeVisible();
  await page.getByRole('searchbox').fill('mission');
  await page.getByRole('link', { name: /Préparer une mission/ }).click();
  await expect(page.getByRole('heading', { name: articleAide.titre, exact: true, level: 1 })).toBeVisible();
  await expect(page.getByText('Vérifiez le lieu', { exact: true })).toBeVisible();
  await preuve(page, info, 'article-aide');
  await page.getByRole('button', { name: "Retour au centre d'aide" }).click();
  await expect(page).toHaveURL(/\/aide$/);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('récupération : lien vérifié, validation, changement puis déconnexion', async ({ page }, info) => {
  const state = await simulerPublic(page);
  await page.goto('/reset-password?token_hash=recette-fictive&type=recovery');
  await expect(page.getByLabel('Nouveau mot de passe *', { exact: true })).toBeVisible();
  await expect(page).toHaveURL(/\/reset-password$/);
  const submit = page.getByRole('button', { name: 'Modifier mon mot de passe', exact: true });
  await expect(submit).toBeDisabled();
  await page.getByLabel('Nouveau mot de passe *', { exact: true }).fill('Recette!Secret2026');
  await page.getByLabel('Confirmer le mot de passe *', { exact: true }).fill('Different!2026');
  await expect(page.getByRole('alert').filter({ hasText: 'Les mots de passe ne correspondent pas' })).toBeVisible();
  await expect(submit).toBeDisabled();
  await page.getByLabel('Confirmer le mot de passe *', { exact: true }).fill('Recette!Secret2026');
  await submit.click();
  await expect(page.getByText('Mot de passe modifié', { exact: true })).toBeVisible();
  await preuve(page, info, 'recovery-succes');
  await expect(page).toHaveURL(/\/connexion$/);
  expect(state.calls.filter(c => c.name === 'user' && c.method === 'PUT')).toHaveLength(1);
  expect(state.calls.some(c => c.name === 'logout')).toBe(true);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('retours de confirmation : email, liens expirés, PSC annulé et secours email', async ({ page }, info) => {
  const state = await simulerPublic(page);
  await page.goto('/confirmer-email');
  await expect(page.getByRole('heading', { name: 'Vérifie ton adresse email', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Retour à la connexion', exact: true }).click();
  await expect(page).toHaveURL(/\/connexion$/);
  await expect(page.getByTestId('login-submit')).toBeVisible();
  await page.goto('/inscription/confirmer?token_hash=non-valide&type=recovery');
  await expect(page.getByRole('heading', { name: 'Reprendre votre inscription', exact: true })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Ce lien n’a pas pu être validé.');
  await expect(page).toHaveURL(/\/inscription\/confirmer$/);
  for (const [statut, titre] of [['ok', 'Adresse e-mail confirmée'], ['expire', 'Lien expiré'], ['invalide', 'Lien invalide'], ['erreur', 'Une erreur est survenue']]) {
    await page.goto(`/verification-email-etab?statut=${statut}`);
    await expect(page.getByRole('heading', { name: titre, exact: true })).toBeVisible();
    await preuve(page, info, `email-etab-${statut}`);
    await page.getByRole('button', { name: statut === 'ok' ? 'Aller à mon tableau de bord' : 'Retour à la vérification', exact: true }).click();
    await expect(page).toHaveURL(/\/connexion/);
    await expect(page.getByTestId('login-submit')).toBeVisible();
  }
  await page.goto('/auth/psc/callback?status=error&message=Connexion%20annul%C3%A9e');
  await expect(page.getByText("La connexion à Pro Santé Connect n'a pas fonctionné", { exact: true })).toBeVisible();
  await expect(page).toHaveURL(/\/auth\/psc\/callback\?status=error$/);
  await page.getByRole('button', { name: "S'inscrire par email", exact: true }).click();
  await expect(page).toHaveURL(/\/inscription\/soignant$/);
  await expect(page.getByLabel('Email', { exact: true })).toBeVisible();
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('aide : panne de recherche et article indisponible se récupèrent sans faux état vide', async ({ page }, info) => {
  const state = await simulerPublic(page); state.failures.add('fn_rechercher_aide');
  await page.goto('/aide');
  await expect(page.getByRole('alert').filter({ hasText: 'Impossible de charger les articles' })).toBeVisible();
  await expect(page.getByText('Aucun article disponible.')).toHaveCount(0);
  await preuve(page, info, 'aide-erreur');
  state.failures.clear(); await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page.getByRole('link', { name: /Préparer une mission/ })).toBeVisible();
  state.failures.add('articles_aide');
  await page.getByRole('link', { name: /Préparer une mission/ }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Impossible de charger cet article' })).toBeVisible();
  await expect(page.getByText('Article introuvable')).toHaveCount(0);
  await preuve(page, info, 'article-erreur');
  state.failures.clear(); await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page.getByRole('heading', { name: articleAide.titre, exact: true })).toBeVisible();
  state.missingArticle = true; await page.goto('/aide/article-absent');
  await expect(page.getByText('Article introuvable', { exact: true })).toBeVisible();
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('aide connectée : le choix Tous reste appliqué malgré l’audience par défaut', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  state.overrides.set('fn_rechercher_aide', { articles: [articleAide] });
  await entrerSoignant(page, 'connexion');
  await page.goto('/aide');
  await expect(page).toHaveURL(/aud=SOIGNANT/);
  await expect(page.getByRole('link', { name: /Préparer une mission/ })).toBeVisible();
  await page.getByRole('button', { name: 'Tous', exact: true }).click();
  await expect.poll(() => state.calls.filter(c => c.name === 'fn_rechercher_aide').at(-1)?.body.p_audience).toBeNull();
  await expect(page.getByRole('link', { name: /Préparer une mission/ })).toBeVisible();
  await expect(page).toHaveURL(/\/aide$/);
  await preuve(page, info, 'aide-connectee-tous');
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('connexion : erreurs françaises, affichage du mot de passe, récupération et protections', async ({ page }, info) => {
  const state = await simulerPublic(page);
  await page.goto('/connexion');
  await page.getByLabel('Email', { exact: true }).fill('recette@example.invalid');
  await page.getByLabel('Mot de passe', { exact: true }).fill('ErreurDeTest!47');
  await page.getByRole('button', { name: 'Afficher le mot de passe', exact: true }).click();
  await expect(page.getByLabel('Mot de passe', { exact: true })).toHaveAttribute('type', 'text');
  await page.getByRole('button', { name: 'Masquer le mot de passe', exact: true }).click();
  await page.getByTestId('login-submit').click();
  await expect(page.getByText('Email ou mot de passe incorrect.', { exact: true })).toBeVisible();
  await expect(page.getByLabel('Email', { exact: true })).toHaveValue('recette@example.invalid');
  state.authError = 'email_not_confirmed'; await page.getByTestId('login-submit').click();
  await expect(page.getByText('Veuillez confirmer votre adresse email avant de vous connecter.', { exact: true })).toBeVisible();
  await preuve(page, info, 'connexion-erreurs');
  await page.getByRole('button', { name: 'Mot de passe oublié ?' }).click();
  await page.getByLabel('Email de votre compte', { exact: true }).fill('RECETTE@example.invalid');
  await page.getByRole('button', { name: 'Envoyer le lien', exact: true }).click();
  await expect(page.getByRole('status').filter({ hasText: 'Si un compte existe' })).toBeVisible();
  await expect(page.getByRole('button', { name: /Renvoyer dans/ })).toBeDisabled();
  expect(state.calls.find(c => c.name === 'recover')?.body.email).toBe('recette@example.invalid');
  for (const route of ['/soignant/tableau-de-bord', '/etablissement/tableau-de-bord']) {
    await page.goto(route); await expect(page).toHaveURL(/\/connexion/);
    await expect(page.getByTestId('login-submit')).toBeVisible();
  }
  await page.goto('/reset-password');
  await expect(page.getByText('Lien invalide ou expiré', { exact: true })).toBeVisible();
  await preuve(page, info, 'reset-invalide');
  await page.getByRole('button', { name: 'Retour à la connexion', exact: true }).click();
  await expect(page).toHaveURL(/\/connexion$/);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

for (const role of ['soignant', 'etablissement']) test(`inscription ${role} : mot de passe divulgué expliqué en français, formulaire conservé`, async ({ page }, info) => {
  const state = await simulerPublic(page);
  await page.goto(`/inscription/${role}`);
  await page.getByLabel('Email', { exact: true }).fill('recette@example.invalid');
  await page.getByLabel('Mot de passe', { exact: true }).fill('Password123!');
  if (role === 'soignant') await page.getByLabel('Profession', { exact: true }).selectOption('IDE');
  else await page.getByLabel('Nom de l’établissement', { exact: true }).fill('Établissement de simulation');
  await page.getByRole('checkbox', { name: /CGU/ }).check();
  if (role === 'etablissement') await page.getByRole('checkbox', { name: /conditions générales de vente/ }).check();
  await page.getByRole('button', { name: 'Créer mon compte', exact: true }).click();
  await expect(page.getByText('Ce mot de passe est trop facile à deviner ou a déjà été divulgué. Choisissez un autre mot de passe.', { exact: true })).toBeVisible();
  await expect(page.getByLabel('Email', { exact: true })).toHaveValue('recette@example.invalid');
  await expect(page.getByRole('button', { name: 'Créer mon compte', exact: true })).toBeEnabled();
  await preuve(page, info, `inscription-${role}-erreur`);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('contact : échec conserve le message, nouvelle tentative aboutit une seule fois', async ({ page }, info) => {
  const state = await simulerPublic(page); state.failures.add('contact-form');
  await page.goto('/contact');
  await page.getByLabel('Votre nom *', { exact: true }).fill('Recette Jolene');
  await page.getByLabel('Votre email *', { exact: true }).fill('recette@example.invalid');
  await page.getByLabel('Sujet', { exact: true }).fill('Simulation');
  await page.getByLabel('Message *', { exact: true }).fill('Message simulé, aucun email ne doit être envoyé.');
  await page.getByRole('button', { name: 'Envoyer le message', exact: true }).click();
  await expect(page.getByText('Envoi impossible, réessayez plus tard.', { exact: true })).toBeVisible();
  await expect(page.getByLabel('Message *', { exact: true })).toHaveValue('Message simulé, aucun email ne doit être envoyé.');
  state.failures.clear();
  await page.getByRole('button', { name: 'Envoyer le message', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Message envoyé', exact: true })).toBeVisible();
  expect(state.calls.filter(c => c.name === 'contact-form')).toHaveLength(2);
  await preuve(page, info, 'contact-envoye');
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});
