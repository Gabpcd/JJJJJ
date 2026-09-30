import { test, expect, type BrowserContext, type Page, type Request } from '@playwright/test';
import { creerMissionSimulee, ids, preuveMission } from './helpers/recette-complete-mission';

// Simulation frontend seulement : les réponses RPC ci-dessous ne prouvent pas
// l'autorisation PostgreSQL, exercée dans cloture-mission-tenant.test.sql.
function missionEnCours() {
  const simulation = creerMissionSimulee();
  const { state } = simulation;
  state.mission.statut = 'EN_COURS';
  state.mission.soignant_assigne_id = ids.soignant;
  state.mission.type_contrat_applique = 'LIBERAL';
  const segment = { id: '71000000-0000-4000-8000-000000000021',
    mission_id: ids.mission, debut: state.mission.debut_le, fin: state.mission.fin_le,
    ordre: 1, type_creneau: 'EFFECTIF', est_pause: false };
  state.creneaux.push(segment);
  state.segments.push(segment);
  state.presence = { id: ids.presence, mission_id: ids.mission, soignant_id: ids.soignant,
    pointage_arrivee_le: segment.debut, pointage_depart_le: segment.fin,
    valide_par_etablissement: true, missions: { ...state.mission, presences: undefined } };
  state.mission.presences = [{ ...state.presence, missions: undefined }];
  return simulation;
}

async function dependancesSimulees(context: BrowserContext) {
  // Ressources tierces neutralisées à la frontière HTTP, sans filtrer les
  // erreurs console/page. Aucun chargement de police ou SDK fournisseur réel.
  await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  await context.route('https://js.stripe.com/**', route => route.fulfill({ contentType: 'application/javascript',
    body: 'window.Stripe = function(){ return {}; };' }));
  await context.route('**/rest/v1/rpc/fn_score_etab_public', route => route.fulfill({ json: { score_qualite: null, niveau: null } }));
  await context.route('**/rest/v1/rpc/fn_user_id_pour_etablissement', route => route.fulfill({ json: ids.etablissement }));
}

function suivreLectures(page: Page) {
  const enCours = new Set<Request>();
  let dernierEvenement = 0;
  page.on('request', requete => {
    if (/\/(auth|rest|functions|storage)\/v1\//.test(requete.url())) {
      enCours.add(requete);
      dernierEvenement = Date.now();
    }
  });
  const terminer = (requete: Request) => { if (enCours.delete(requete)) dernierEvenement = Date.now(); };
  page.on('requestfinished', terminer);
  page.on('requestfailed', terminer);
  // Attendre la fin du rafraîchissement déclenché par le succès avant de
  // détruire le document. Aucune erreur de requête annulée n'est filtrée.
  return () => expect.poll(() => enCours.size === 0 && Date.now() - dernierEvenement >= 500,
    { message: 'Lectures API terminées avant rechargement/contrôle des erreurs' }).toBe(true);
}

test('clôture établissement : refus uniforme visible, reprise autorisée et rechargement', async ({ context, page }, info) => {
  const stabiliser = suivreLectures(page);
  const simulation = missionEnCours();
  const { state } = simulation;
  const consoleErrors: string[] = [];
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  let autorise = false;
  let tentatives = 0;
  await simulation.installer(context, 'ADMIN_ETABLISSEMENT');
  await dependancesSimulees(context);
  await context.route('**/rest/v1/rpc/fn_terminer_mission', async route => {
    expect(route.request().postDataJSON()).toEqual({ p_mission_id: ids.mission });
    tentatives++;
    if (!autorise) return route.fulfill({ json: { success: false, error: 'Accès refusé' } });
    return route.fallback();
  });
  await page.clock.setFixedTime(new Date('2026-09-24T15:30:00Z'));
  try {
    await page.goto(`/etablissement/missions/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Terminer la mission', exact: true }).click();
    await expect(page.getByRole('dialog', { name: 'Terminer cette mission ?' })).toBeVisible();
    await page.getByRole('dialog').getByRole('button', { name: 'Terminer la mission', exact: true }).click();
    await expect(page.getByText('Accès refusé', { exact: true })).toBeVisible();
    expect(state.mission.statut).toBe('EN_COURS');
    expect(tentatives).toBe(1);
    await expect(page.getByText('Mission terminée', { exact: true })).toHaveCount(0);
    await preuveMission(page, info, '01-refus-sans-succes');
    await stabiliser();
    await page.reload();
    await expect(page.getByRole('button', { name: 'Terminer la mission', exact: true })).toBeEnabled();
    // Le droit est rétabli côté réponse simulée ; le nouveau clic utilisateur
    // emprunte la même surface et la réponse de succès habituelle.
    autorise = true;
    await page.getByRole('button', { name: 'Terminer la mission', exact: true }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Terminer la mission', exact: true }).click();
    await expect(page.getByText('Mission terminée', { exact: true })).toBeVisible();
    await expect.poll(() => state.mission.statut).toBe('TERMINEE');
    await expect(page.getByRole('button', { name: 'Terminer la mission', exact: true })).toHaveCount(0);
    expect(tentatives).toBe(2);
    await preuveMission(page, info, '02-cloture-autorisee');
    await stabiliser();
    await page.reload();
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Terminer la mission', exact: true })).toHaveCount(0);
    await preuveMission(page, info, '03-cloture-apres-rechargement');
    await stabiliser();
    expect(state.errors).toEqual([]);
    expect(consoleErrors).toEqual([]);
    expect(state.unknown).toEqual([]);
    expect(state.external).toEqual([]);
  } finally {
    await info.attach('journal-cloture-simulee', { body: JSON.stringify({ tentatives, consoleErrors,
      pageErrors: state.errors, unknown: state.unknown, external: state.external, statut: state.mission.statut }), contentType: 'application/json' });
  }
});

test('soignant : consultation sans commande de clôture avant et après rechargement', async ({ context, page }, info) => {
  const stabiliser = suivreLectures(page);
  const simulation = missionEnCours();
  const { state } = simulation;
  const consoleErrors: string[] = [];
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  await simulation.installer(context, 'SOIGNANT');
  await dependancesSimulees(context);
  await page.clock.setFixedTime(new Date('2026-09-24T15:30:00Z'));
  try {
    await page.goto(`/soignant/missions/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Terminer la mission', exact: true })).toHaveCount(0);
    await preuveMission(page, info, '04-soignant-en-cours');
    // Conséquence reçue d'une clôture établissement simulée, après rechargement.
    state.mission.statut = 'TERMINEE';
    await stabiliser();
    await page.reload();
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Terminer la mission', exact: true })).toHaveCount(0);
    await preuveMission(page, info, '05-soignant-terminee');
    await stabiliser();
    expect(state.calls.some(call => call.name === 'fn_terminer_mission')).toBe(false);
    expect(state.errors).toEqual([]);
    expect(consoleErrors).toEqual([]);
    expect(state.unknown).toEqual([]);
    expect(state.external).toEqual([]);
  } finally {
    await info.attach('journal-soignant-simule', { body: JSON.stringify({ consoleErrors,
      pageErrors: state.errors, unknown: state.unknown, external: state.external }), contentType: 'application/json' });
  }
});

test('admin valide : clôture anticipée avec litige, confirmation et rechargement', async ({ context, page }, info) => {
  const stabiliser = suivreLectures(page);
  const simulation = missionEnCours();
  const { state } = simulation;
  const consoleErrors: string[] = [];
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  // Le départ est effectué mais le dernier créneau planifié n'est pas échu.
  state.mission.fin_le = '2026-09-24T17:00:00.000Z';
  state.creneaux[0].fin = state.mission.fin_le;
  const litigeId = '71000000-0000-4000-8000-000000000022';
  await simulation.installer(context, 'ADMIN_PLATEFORME');
  await dependancesSimulees(context);
  await context.route('**/rest/v1/rpc/fn_get_my_role', route => route.fulfill({ json: { role: 'ADMIN_PLATEFORME' } }));
  await context.route('**/rest/v1/rpc/fn_admin_mes_acces', route => route.fulfill({ json: { acces_total: true, groupes: [] } }));
  await context.route('**/rest/v1/rpc/fn_litige_pour_mission', route => route.fulfill({ json: {
    exists: true, litige_id: litigeId, statut: 'REVUE_ADMIN', motif: 'Arbitrage fictif de recette',
  } }));
  await page.clock.setFixedTime(new Date('2026-09-24T15:30:00Z'));
  try {
    await page.goto(`/admin/missions/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Clôturer après arbitrage', exact: true }).click();
    const dialogue = page.getByRole('dialog', { name: 'Clôturer cette mission après arbitrage ?' });
    await expect(dialogue).toContainText('le litige actif restera traçable');
    await preuveMission(page, info, '06-admin-confirmation-arbitrage');
    await dialogue.getByRole('button', { name: 'Confirmer la clôture admin', exact: true }).click();
    await expect(page.getByText('Mission terminée', { exact: true })).toBeVisible();
    await expect.poll(() => state.mission.statut).toBe('TERMINEE');
    await stabiliser();
    await page.reload();
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Clôturer après arbitrage', exact: true })).toHaveCount(0);
    await preuveMission(page, info, '07-admin-apres-rechargement');
    await stabiliser();
    expect(state.calls.filter(call => call.name === 'fn_terminer_mission')).toHaveLength(1);
    expect(state.errors).toEqual([]);
    expect(consoleErrors).toEqual([]);
    expect(state.unknown).toEqual([]);
    expect(state.external).toEqual([]);
  } finally {
    await info.attach('journal-admin-simule', { body: JSON.stringify({ consoleErrors,
      pageErrors: state.errors, unknown: state.unknown, external: state.external }), contentType: 'application/json' });
  }
});
