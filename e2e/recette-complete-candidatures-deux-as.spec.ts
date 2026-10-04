import { test, expect, type Page } from '@playwright/test';
import { creerCandidaturesDeuxAs, identifiants, maintenant } from './helpers/recette-candidatures-deux-as';
import { preuveMission } from './helpers/recette-complete-mission';

const chemin = `/soignant/missions/${identifiants.mission}`;
const envoye = '✅ Candidature envoyée — En attente de réponse';
const rappel = 'Candidature envoyée ! Valide tes documents pour pouvoir être accepté.';
async function confirmer(page: Page) {
  await expect(page.getByRole('button', { name: /Vérifier et postuler/ })).toBeEnabled();
  await page.getByRole('button', { name: /Vérifier et postuler/ }).click();
  const dialogue = page.getByRole('dialog', { name: 'Vérifie ton engagement' });
  await expect(dialogue).toBeVisible();
  await expect(dialogue).toContainText('09h00');
  await expect(dialogue).toContainText('13h00');
  await dialogue.getByRole('button', { name: 'Envoyer ma candidature', exact: true }).click();
  await expect(dialogue).toBeHidden();
}

test('deux AS non vérifiés candidatent : planning exact, rappel documents et deux dossiers en attente après reload', async ({ browser, context, page }, info) => {
  const simulation = creerCandidaturesDeuxAs(), { state } = simulation;
  await simulation.installer(context, 'as1'); await page.clock.setFixedTime(new Date(maintenant));
  const deuxieme = await browser.newContext({ ...info.project.use });
  const clinique = await browser.newContext({ ...info.project.use });
  await simulation.installer(deuxieme, 'as2'); await simulation.installer(clinique, 'etablissement');
  const as2 = await deuxieme.newPage(), etab = await clinique.newPage();
  for (const acteur of [as2, etab]) await acteur.clock.setFixedTime(new Date(maintenant));
  try {
    for (const [index, acteur] of [page, as2].entries()) {
      await acteur.goto(chemin);
      await expect(acteur.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
      await acteur.getByPlaceholder('Présente-toi brièvement…').fill(`Candidature fictive AS ${index + 1}, disponible sur tous les horaires.`);
      await confirmer(acteur);
      await expect(acteur.getByText(envoye, { exact: true })).toBeVisible();
      await expect(acteur.getByText(rappel, { exact: true })).toBeVisible();
      await expect(acteur.getByRole('button', { name: 'Mes documents', exact: true })).toBeVisible();
      await preuveMission(acteur, info, `as${index + 1}-documents-et-attente`);
      await acteur.reload();
      await expect(acteur.getByText(envoye, { exact: true })).toBeVisible();
      await expect(acteur.getByRole('button', { name: /Vérifier et postuler/ })).toBeHidden();
    }
    expect(state.candidatures.map(c => c.soignant_id)).toEqual([identifiants.as1, identifiants.as2]);
    const envois = state.calls.filter(c => c.name === 'fn_confirmer_action_planning_v1');
    expect(envois).toHaveLength(2);
    for (const appel of envois) expect(appel.body).toMatchObject({ p_action: 'POSTULER', p_mission_id: identifiants.mission,
      p_creneaux_confirmes: [{ debut: state.mission.debut_le, fin: state.mission.fin_le }], p_choix_contrat: null, p_candidature_id: null });
    await etab.goto(`/etablissement/missions/${identifiants.mission}`);
    for (const rechargement of [false, true]) {
      if (rechargement) await etab.reload();
      await expect(etab.getByRole('heading', { name: 'Candidatures (2)', exact: true })).toBeVisible();
      await expect(etab.getByText('En attente (2)', { exact: true })).toBeVisible();
      await expect(etab.getByText(/Aline S\./)).toBeVisible();
      await expect(etab.getByText(/Basile S\./)).toBeVisible();
      await expect(etab.getByText(/Aline Simulation|Basile Simulation/)).toHaveCount(0);
      await expect(etab.getByText('📄 Documents en vérification', { exact: true })).toHaveCount(2);
      await expect(etab.getByRole('button', { name: 'Accepter cette candidature', exact: true })).toHaveCount(2);
    }
    await preuveMission(etab, info, 'etablissement-deux-candidatures-rechargees');
    simulation.verifierBornes();
  } finally {
    await info.attach('journal-simulation', { body: JSON.stringify(state, null, 2), contentType: 'application/json' });
    await deuxieme.close(); await clinique.close();
  }
});

test('candidature : panne persistante, réessai, planning périmé refusé puis recharge explicite', async ({ context, page }, info) => {
  const simulation = creerCandidaturesDeuxAs(), { state } = simulation;
  await simulation.installer(context, 'as1'); await page.clock.setFixedTime(new Date(maintenant));
  try {
    state.indisponible = 'mission'; await page.goto(chemin);
    await expect(page.getByRole('heading', { name: 'Impossible de charger la mission', exact: true })).toBeVisible();
    expect(state.calls.filter(c => c.name === 'missions' && c.method === 'GET').length).toBeGreaterThanOrEqual(2);
    expect(state.candidatures).toHaveLength(0);
    state.indisponible = null; await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    state.indisponible = 'postuler'; await confirmer(page);
    // En build compilé, les détails HTTP inconnus passent par le message
    // utilisateur générique ; le préfixe « Erreur: » est réservé au mode DEV.
    await expect(page.getByText('Une erreur est survenue. Veuillez réessayer.', { exact: true })).toBeVisible();
    await expect(page.getByText(envoye, { exact: true })).toBeHidden(); expect(state.candidatures).toHaveLength(0);
    await preuveMission(page, info, 'candidature-erreur-sans-succes');
    state.indisponible = null;
    // Le serveur simulé change APRÈS le chargement de l'écran : aucun faux succès sur l'ancien planning.
    state.creneaux[0].debut = '2026-10-02T08:00:00.000Z'; state.creneaux[0].fin = '2026-10-02T12:00:00.000Z';
    await confirmer(page);
    await expect(page.getByText('Le planning a changé. Recharge la mission puis confirme les nouveaux horaires.', { exact: true })).toBeVisible();
    expect(state.refusPlanning).toBe(1); expect(state.candidatures).toHaveLength(0);
    await page.reload();
    await page.getByRole('button', { name: /Vérifier et postuler/ }).click();
    const dialogue = page.getByRole('dialog', { name: 'Vérifie ton engagement' });
    await expect(dialogue).toContainText('10h00'); await expect(dialogue).toContainText('14h00');
    await dialogue.getByRole('button', { name: 'Envoyer ma candidature', exact: true }).click();
    await expect(dialogue).toBeHidden();
    await expect(page.getByText(envoye, { exact: true })).toBeVisible();
    await expect(page.getByText(rappel, { exact: true })).toBeVisible();
    expect(state.candidatures).toHaveLength(1);
    expect(state.calls.filter(c => c.name === 'fn_confirmer_action_planning_v1')).toHaveLength(3);
    await page.reload(); await expect(page.getByText(envoye, { exact: true })).toBeVisible();
    await preuveMission(page, info, 'planning-reconfirme-candidature-rechargee');
    simulation.verifierBornes();
  } finally { await info.attach('journal-simulation', { body: JSON.stringify(state, null, 2), contentType: 'application/json' }); }
});

test('établissement tiers : aucune mission ni candidature visible, y compris après recharge', async ({ context, page }, info) => {
  const simulation = creerCandidaturesDeuxAs(), { state } = simulation;
  // Deux dossiers existent : le refus ne doit pas réussir seulement parce que la liste est vide.
  state.candidatures.push(...state.soignants.map((soignant, index) => ({
    id: `dc300000-0000-4000-8000-00000000003${index + 1}`, mission_id: identifiants.mission,
    soignant_id: soignant.id, message: `Dossier confidentiel AS ${index + 1}`, statut: 'EN_ATTENTE',
    cree_le: maintenant, choix_contrat: 'SALARIE',
  })));
  await simulation.installer(context, 'tiers'); await page.clock.setFixedTime(new Date(maintenant));
  try {
    for (const rechargement of [false, true]) {
      const refus = page.waitForResponse(response => new URL(response.url()).pathname === '/rest/v1/rpc/fn_lire_candidatures_mission_habilitee');
      if (rechargement) await page.reload();
      else await page.goto(`/etablissement/missions/${identifiants.mission}`);
      const reponse = await refus;
      expect(reponse.request().method()).toBe('POST');
      expect(reponse.request().postDataJSON()).toEqual({ p_mission_id: identifiants.mission });
      expect(reponse.status()).toBe(403);
      expect(await reponse.json()).toEqual({ code: '42501', message: 'Mission indisponible ou accès refusé' });
      await expect(page.getByRole('heading', { name: 'Impossible de charger la mission', exact: true })).toBeVisible();
      await expect(page.getByText(state.mission.intitule, { exact: true })).toBeHidden();
      for (const soignant of state.soignants) await expect(page.getByText(soignant.prenom, { exact: true })).toHaveCount(0);
      for (const candidature of state.candidatures) await expect(page.getByText(candidature.message!, { exact: true })).toHaveCount(0);
      await expect(page.getByRole('button', { name: 'Accepter cette candidature', exact: true })).toHaveCount(0);
    }
    expect(state.calls.filter(c => c.name === 'fn_lire_candidatures_mission_habilitee')).toHaveLength(2);
    expect(state.calls.filter(c => ['candidatures', 'mission_creneaux', 'soignants', 'fn_soignant_pour_etablissement'].includes(c.name))).toEqual([]);
    expect(state.candidatures).toHaveLength(2);
    await preuveMission(page, info, 'etablissement-tiers-refuse-apres-reload');
    simulation.verifierBornes();
  } finally { await info.attach('journal-simulation', { body: JSON.stringify(state, null, 2), contentType: 'application/json' }); }
});
