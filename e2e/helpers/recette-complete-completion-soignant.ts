import { expect, type Page } from '@playwright/test';
import { entrer, ids, mission, simulerSoignant } from './recette-complete-soignant';

/** Simulation du seul contrat HTTP de finalisation. Aucun annuaire, PSC ou document réel. */
export async function simulerCompletionSoignant(page: Page) {
  page.setDefaultTimeout(15_000);
  const state = await simulerSoignant(page, 'minimal');
  state.offers = true;
  Object.assign(state.profile, {
    prenom: '', nom: '', telephone: null, date_naissance: null, numero_rpps: null,
    rpps_verifie: false, tous_documents_valides: false, bio: '',
    adresse_rue: null, adresse_ville: null, adresse_code_postal: null,
    adresse_lat: null, adresse_lng: null,
  });
  state.overrides.set('fn_soignant_dpae_complet', { complet: false, manquants: ['sexe', 'lieu_naissance_commune', 'numero_securite_sociale'] });
  const completion = { refusFinalisation: false, professionRppsCorrespond: true, soumissions: [] as Record<string, any>[] };
  await page.route(url => ['register-soignant', 'verify-rpps'].some(n => url.pathname === `/functions/v1/${n}`), async route => {
    const req = route.request(), url = new URL(req.url()), name = url.pathname.split('/').pop()!;
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.abort();
    if (req.method() !== 'POST') {
      state.unknown.push(`${req.method()} ${url.pathname}`);
      return route.fulfill({ status: 501, json: { code: 'RECETTE_INCONNU' } });
    }
    const body = req.postDataJSON();
    state.calls.push({ name, method: req.method(), body, url: url.pathname });
    if (name === 'verify-rpps') {
      expect(body).toMatchObject({ prenom: 'Camille', nom: 'Recette', profession: 'IDE' });
      expect(body.rpps).toMatch(/^1000000000[01]$/);
      return route.fulfill({ json: { trouve: true, prenom: 'Camille', nom_api: 'Recette', profession_api: completion.professionRppsCorrespond ? 'IDE' : 'Médecin', profession_correspond: completion.professionRppsCorrespond } });
    }
    expect(req.headers().authorization).toBe('Bearer fixture-auth');
    expect(body).toMatchObject({ prenom: 'Camille', nom: 'Recette', telephone: '0100000000', dateNaissance: '1990-01-01', profession: 'IDE', typesContrat: ['SALARIE'], rpps: '10000000001', est_etudiant: false });
    expect(body).not.toHaveProperty('password');
    expect(body).not.toHaveProperty('motDePasse');
    completion.soumissions.push(body);
    if (completion.refusFinalisation) return route.fulfill({ status: 503, json: { ok: false, code: 'RPPS_API_UNAVAILABLE', message: 'Annuaire Santé temporairement indisponible. Votre saisie est conservée.' } });
    Object.assign(state.profile, {
      prenom: body.prenom, nom: body.nom, telephone: body.telephone,
      date_naissance: body.dateNaissance, profession: body.profession,
      numero_rpps: body.rpps, rpps_verifie: true,
      types_contrat_acceptes: JSON.stringify(body.typesContrat),
      rayon_deplacement_km: body.rayon,
    });
    state.mode = 'complet';
    return route.fulfill({ json: { ok: true, user_id: ids.user } });
  });
  return { state, completion };
}

export async function ouvrirDossierDepuisMission(page: Page, inscription = true) {
  if (inscription) await entrer(page, 'inscription');
  await expect(page.getByRole('heading', { name: 'Explorer', exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  await page.getByText(mission.intitule, { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
  await page.getByRole('button', { name: 'Candidater', exact: true }).first().click();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  await expect(page.getByRole('heading', { name: 'Vos informations professionnelles', exact: true })).toBeVisible();
  await expect(page.getByRole('combobox', { name: 'Profession *', exact: true })).toContainText('Infirmier');
}

export async function remplirIdentite(page: Page) {
  await page.getByLabel(/^Prénom \*/).fill('Camille');
  await page.getByLabel(/^Nom \*/).fill('Recette');
  await page.getByLabel(/^Téléphone \*/).fill('0100000000');
  await page.getByLabel(/^Date de naissance \*/).fill('1990-01-01');
  await page.getByRole('checkbox', { name: 'Salarié', exact: true }).check();
}

export async function verifierRppsSimule(page: Page) {
  const verification = page.waitForResponse(response => response.url().endsWith('/functions/v1/verify-rpps') && response.request().postDataJSON()?.rpps === '10000000001');
  await page.getByPlaceholder(/^11 chiffres/).fill('10000000001');
  expect((await verification).status()).toBe(200);
  await expect(page.getByText(/RPPS vérifié dans l’Annuaire Santé — Camille Recette/)).toBeVisible();
  await expect(page.getByRole('alert').filter({ hasText: 'Ce RPPS correspond à la profession' })).not.toBeVisible();
}
