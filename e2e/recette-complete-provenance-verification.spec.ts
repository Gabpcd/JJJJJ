import { expect, test } from '@playwright/test';
import { aller, entrer, ids, preuve, recharger, sansDebordement, simulerSoignant } from './helpers/recette-complete-soignant';

// Frontend avec réponses entièrement simulées : aucune vérification officielle,
// aucun fournisseur et aucune modification de compte ou de qualification réelle.
const titrePersistant = 'Contrôle RPPS enregistré';
const sourcePersistante = 'Source de vérification non disponible dans le profil.';
const formats = ['iphone', 'android', 'ipad-portrait', 'ipad-paysage', 'ordinateur'];

for (const scenario of [
  { nom: 'test', source: 'Mode test contrôlé', titre: 'Contrôle RPPS de test — aucune vérification officielle' },
  { nom: 'officiel', source: 'FHIR Annuaire Santé v2', titre: 'RPPS vérifié dans l’Annuaire Santé' },
  { nom: 'inconnu', source: 'SOURCE_INCONNUE', titre: titrePersistant },
]) {
  test(`RPPS — réponse ${scenario.nom} puis rechargement sans provenance`, async ({ page }, info) => {
    expect(formats).toContain(info.project.name);
    const state = await simulerSoignant(page, 'complet');
    Object.assign(state.profile, { numero_rpps: '00100123456', rpps_verifie: false, tous_documents_valides: false });
    await page.route(url => url.pathname === '/functions/v1/verify-rpps', async route => {
      const request = route.request();
      const url = new URL(request.url());
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.abort();
      const headers = {
        'access-control-allow-origin': '*',
        'access-control-allow-headers': 'authorization,apikey,content-type',
        'access-control-allow-methods': 'POST,OPTIONS',
      };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      if (request.method() !== 'POST') {
        state.unknown.push(`${request.method()} ${url.pathname}`);
        return route.fulfill({ status: 501, json: { code: 'RECETTE_INCONNU' } });
      }
      state.calls.push({ name: 'verify-rpps', method: request.method(), body: request.postDataJSON(), url: url.pathname });
      // Le contrat actuel persiste le verdict, sans provenance dans le profil.
      Object.assign(state.profile, { rpps_verifie: true, rpps_verifie_le: '2026-10-15T00:00:00.000Z' });
      return route.fulfill({ headers, json: {
        ok: true, trouve: true, correspond: true, nom_api: 'Recette', prenom_api: 'Camille',
        profession_api: 'IDE', source: scenario.source,
      } });
    });
    await entrer(page, 'connexion');
    await aller(page, '/soignant/profil');
    await expect(page.locator('#rpps-numero')).toHaveValue('00100123456');
    await page.getByRole('button', { name: 'Vérifier mon RPPS', exact: true }).click();

    const notifications = page.getByRole('region', { name: 'Notifications', exact: true });
    const notification = notifications.getByRole('status').filter({ hasText: scenario.titre });
    await expect(notification).toContainText(scenario.titre);
    if (scenario.nom !== 'officiel') await expect(notifications).not.toContainText('Annuaire Santé');
    await info.attach(`rpps-${scenario.nom}-notification`, { body: await notification.ariaSnapshot(), contentType: 'text/plain' });
    await preuve(page, `rpps-${scenario.nom}-reponse-simulee`, info, true);
    await expect(notification).toHaveCount(0);
    await recharger(page);

    const main = page.locator('main');
    await expect(main.getByText(sourcePersistante, { exact: true })).toBeVisible();
    await expect(main.getByText(titrePersistant, { exact: true }).first()).toBeVisible();
    await expect(main.getByText('Source : Annuaire Santé (ANS).', { exact: true })).toHaveCount(0);
    await expect(main.getByText(/RPPS vérifié|Vérifiée RPPS|vérifié RPPS/)).toHaveCount(0);
    for (const champ of ['#profil-rpps', '#profil-prenom', '#profil-nom', '#profil-date-naissance']) {
      await expect(page.locator(champ)).toHaveAttribute('readonly', '');
    }
    await sansDebordement(page);
    await preuve(page, `rpps-${scenario.nom}-rechargement-sans-source`, info, true);

    // Les badges réutilisés ailleurs ne réinventent pas la provenance perdue.
    for (const route of ['/soignant/tableau-de-bord', '/soignant/mon-compte']) {
      await aller(page, route);
      await expect(page.locator('main').getByText(titrePersistant, { exact: true })).toBeVisible();
      await expect(page.locator('main').getByText('RPPS Vérifié', { exact: true })).toHaveCount(0);
      await sansDebordement(page);
    }
    const verification = state.calls.filter(call => call.name === 'verify-rpps');
    expect(verification).toHaveLength(1);
    expect(verification[0].body).toMatchObject({ rpps: '00100123456', numero_rpps: '00100123456', soignant_id: ids.user });
    expect(state.profile.type_exercice).toBe('SALARIE');
    expect(state.calls.some(call => call.name === 'fn_activer_liberal')).toBe(false);
    expect(state.unknown).toEqual([]);
    expect(state.errors).toEqual([]);
  });
}

for (const scenario of [
  { nom: 'registre', source: 'REGISTRE_OFFICIEL', texte: 'Source : registre officiel — concordance d’identité vérifiée.' },
  { nom: 'manuel', source: 'REVUE_MANUELLE_IDENTITE', texte: 'Source : revue manuelle de l’identité.' },
  { nom: 'sans-source', source: null, texte: 'SIRET enregistré — source de vérification non renseignée.' },
]) {
  test(`SIRET — provenance ${scenario.nom} conservée au rechargement`, async ({ page }, info) => {
    expect(formats).toContain(info.project.name);
    const state = await simulerSoignant(page, 'complet');
    Object.assign(state.profile, {
      siret_liberal: '99000000000000', siret_liberal_verifie: true,
      siret_liberal_verifie_le: '2026-10-15T00:00:00.000Z', siret_liberal_coherence_identite: true,
      siret_liberal_source_verification: scenario.source, siret_liberal_raison_sociale: null,
      statut_liberal: 'EN_COURS', type_contrat: 'CDD', assujetti_tva: false, numero_tva: null,
    });
    await entrer(page, 'connexion');
    await aller(page, '/soignant/passer-en-liberal');
    const source = page.getByText(scenario.texte, { exact: true });
    const activation = page.getByRole('button', { name: 'Activer mon statut libéral', exact: true });
    await expect(source).toBeVisible();
    await expect(activation).toBeEnabled();
    await expect(page.getByText('SIRET officiel actif et identité vérifiée.', { exact: true })).toHaveCount(0);
    await recharger(page);
    await expect(source).toBeVisible();
    await expect(activation).toBeEnabled();
    await sansDebordement(page);
    await preuve(page, `siret-${scenario.nom}-rechargement-source`, info, true);

    await page.getByLabel('SIRET', { exact: true }).fill('99000000000001');
    await expect(source).toHaveCount(0);
    await expect(activation).toBeDisabled();
    expect(state.calls.some(call => ['verify-siret', 'fn_activer_liberal', 'fn_modifier_tva_liberal'].includes(call.name))).toBe(false);
    expect(state.profile.type_exercice).toBe('SALARIE');
    expect(state.profile.statut_liberal).toBe('EN_COURS');
    expect(state.unknown).toEqual([]);
    expect(state.errors).toEqual([]);
  });
}
