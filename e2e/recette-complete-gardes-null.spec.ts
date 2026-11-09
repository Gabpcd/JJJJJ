import { test, expect, type Page } from '@playwright/test';
import { creerMissionSimulee, ids, now } from './helpers/recette-complete-mission';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { REFUS, neutraliserTiers, preuveGardes, surchargerRpc, surchargerTable, type AppelRpc } from './helpers/recette-complete-gardes-null';

// Recette B9 « gardes NULL » (20261109010957), niveau SIMULATION : réponses
// simulées identiques aux corps LIVE, écrans réellement montés par les routes
// (App.tsx). La garde SQL elle-même est prouvée par
// tests/security/gardes-null-security-definer.test.sql (staging, sous ROLLBACK).
// « Avant » = réponse que la fonction LIVE non corrigée rendait à cet appelant ;
// « après » = réponse de la fonction corrigée. Aucune des deux n'est exécutée ici.

const heureRecette = '2026-09-24T18:00:00Z';

/** Présence pointée par un AUTRE soignant (relevé GPS et méthode), telle que fn_presences_detail_mission LIVE la renvoie. */
const detailPresenceAutreSoignant = {
  pointage_effectue: true, heures_planifiees: 8, heures_reelles: 8,
  pointage_arrivee: '2026-09-24T07:00:00.000Z', pointage_depart: '2026-09-24T15:00:00.000Z',
  methode_arrivee: 'GPS', methode_depart: 'GPS', retard_min: 0, depart_anticipe_min: 0,
  duree_brute_min: 480, duree_pause_min: 0, duree_nette_min: 480, nb_pauses: 0, pauses: [],
  distance_m: 37, perimetre_valide: true, alerte_teleportation: false, alertes: null, valide: false,
};
/** Présence du soignant assigné lui-même (code rotatif, sans relevé GPS). */
const detailPresenceAssignee = { ...detailPresenceAutreSoignant, methode_arrivee: 'CODE_ROTATIF', methode_depart: 'CODE_ROTATIF', distance_m: null, perimetre_valide: null };

async function verifierSansFuitePointage(page: Page) {
  const main = page.locator('main');
  await expect(main.getByText('Synthèse des présences', { exact: true })).toBeVisible();
  for (const fuite of ['Distance GPS', 'Méthode', '37m', 'GPS', '🚨 Alerte téléportation détectée']) {
    await expect(main.getByText(fuite, { exact: true })).toHaveCount(0);
  }
}

test.describe('soignant — fiche établissement du contrat (fn_etablissement_pour_mission)', () => {
  test('contrat non signé d’une mission réattribuée : fiche refusée, « — » sans fuite ni erreur', async ({ context, page }, info) => {
    const { state, installer } = creerMissionSimulee();
    state.contratCree = true;
    Object.assign(state.contrat, { statut: 'ANNULE', contenu_html: null, storage_path: null, hash_document: null, contenu_html_rendu_le: null });
    const appels: AppelRpc[] = [];
    await installer(context, 'SOIGNANT');
    await neutraliserTiers(context);
    // RLS : la mission réattribuée n'est plus lisible par l'ancien soignant.
    await surchargerTable(context, 'missions', () => []);
    await surchargerRpc(context, new Map([['fn_etablissement_pour_mission', () => REFUS.accesRefuse]]), appels);
    await page.clock.setFixedTime(new Date(now));
    await page.goto(`/contrat/${ids.contrat}`);
    await expect(page.getByRole('heading', { name: `Contrat ${state.contrat.numero_contrat}`, level: 1 }).first()).toBeVisible();
    await expect(page.getByText('❌ Ce contrat a été annulé suite à l\'annulation de la mission.', { exact: true })).toBeVisible();
    const main = page.locator('main');
    await expect(main.getByText('Le document original n\'était pas stocké ; cette version a été reconstituée automatiquement à partir des données de la mission.', { exact: true })).toBeVisible();
    await expect(main.getByRole('heading', { name: 'Établissement', level: 2, exact: true })).toBeVisible();
    await expect(main).toContainText('SIRET : —');
    await expect(main).toContainText('Adresse : —');
    await expect(main).toContainText('Téléphone : —');
    await expect(main).not.toContainText(state.etablissement.nom);
    await expect(main).not.toContainText(state.etablissement.siret);
    expect(appels).toEqual([{ nom: 'fn_etablissement_pour_mission', corps: { p_etablissement_id: ids.etablissement } }]);
    await preuveGardes(page, info, 'soignant-contrat-reattribue-fiche-refusee');
    // Reprise après rechargement : même refus, même rendu, aucune fuite.
    await page.reload();
    await expect(main.getByRole('heading', { name: 'Établissement', level: 2, exact: true })).toBeVisible();
    await expect(main).toContainText('SIRET : —');
    await expect(main).not.toContainText(state.etablissement.nom);
    expect(appels).toHaveLength(2);
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });
});

test.describe('présences d’une mission (fn_presences_detail_mission)', () => {
  test('soignant tiers sur une mission republiée : le pointage de l’ancien soignant n’est plus renvoyé', async ({ context, page }, info) => {
    const { state, installer } = creerSuiviSimule();
    // Mission republiée après désistement : OUVERTE (lisible par tout soignant
    // via pol_mission_select), plus d'assigné ; le relevé de l'ancien soignant
    // reste en base mais la RLS presences ne le montre pas au soignant tiers.
    state.mission.statut = 'OUVERTE';
    state.mission.soignant_assigne_id = null;
    state.presence = null;
    let reponse: unknown = detailPresenceAutreSoignant;
    const appels: AppelRpc[] = [];
    await installer(context, 'SOIGNANT');
    await neutraliserTiers(context);
    await surchargerRpc(context, new Map([['fn_presences_detail_mission', () => reponse]]), appels);
    await page.clock.setFixedTime(new Date(heureRecette));

    // Avant (LIVE non corrigé, simulé) : la garde valait NULL, le relevé fuyait.
    await page.goto(`/soignant/presences/mission/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, level: 1 })).toBeVisible();
    const main = page.locator('main');
    await expect(main.getByText('Distance GPS', { exact: true })).toBeVisible();
    await expect(main.getByText('37m', { exact: true })).toBeVisible();
    await expect(main.getByText('GPS', { exact: true })).toBeVisible();
    await preuveGardes(page, info, 'soignant-tiers-presences-avant-fuite-simulee');

    // Après (fonction corrigée) : refus, plus aucune donnée de pointage d'un tiers.
    reponse = REFUS.accesRefuse;
    await stabiliserActionsNationales(page);
    await page.reload();
    await expect(page.getByRole('heading', { name: state.mission.intitule, level: 1 })).toBeVisible();
    await verifierSansFuitePointage(page);
    await expect(main).not.toContainText('NaN');
    await preuveGardes(page, info, 'soignant-tiers-presences-apres-refus');
    expect(appels).toEqual([
      { nom: 'fn_presences_detail_mission', corps: { p_mission_id: ids.mission } },
      { nom: 'fn_presences_detail_mission', corps: { p_mission_id: ids.mission } },
    ]);
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });

  test('soignant assigné : sa propre synthèse reste affichée (accès conservé)', async ({ context, page }, info) => {
    const { state, installer } = creerSuiviSimule();
    state.mission.statut = 'TERMINEE';
    state.mission.soignant_assigne_id = ids.soignant;
    const appels: AppelRpc[] = [];
    await installer(context, 'SOIGNANT');
    await neutraliserTiers(context);
    await surchargerRpc(context, new Map([['fn_presences_detail_mission', () => detailPresenceAssignee]]), appels);
    await page.clock.setFixedTime(new Date(heureRecette));
    await page.goto(`/soignant/presences/mission/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, level: 1 })).toBeVisible();
    const main = page.locator('main');
    await expect(main.getByText('Synthèse des présences', { exact: true })).toBeVisible();
    await expect(main.getByText('Méthode', { exact: true })).toBeVisible();
    await expect(main.getByText('CODE_ROTATIF', { exact: true })).toBeVisible();
    await preuveGardes(page, info, 'soignant-assigne-presences-conservees');
    await stabiliserActionsNationales(page);
    await page.reload();
    await expect(main.getByText('CODE_ROTATIF', { exact: true })).toBeVisible();
    expect(appels.map(a => a.corps)).toEqual([{ p_mission_id: ids.mission }, { p_mission_id: ids.mission }]);
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });

  test('établissement propriétaire : synthèse et relevé GPS de sa mission conservés', async ({ context, page }, info) => {
    const { state, installer } = creerSuiviSimule();
    state.mission.statut = 'TERMINEE';
    state.mission.soignant_assigne_id = ids.soignant;
    const appels: AppelRpc[] = [];
    await installer(context, 'ADMIN_ETABLISSEMENT');
    await neutraliserTiers(context);
    await surchargerRpc(context, new Map([['fn_presences_detail_mission', () => detailPresenceAutreSoignant]]), appels);
    await page.clock.setFixedTime(new Date(heureRecette));
    await page.goto(`/etablissement/presences/mission/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, level: 1 })).toBeVisible();
    const main = page.locator('main');
    await expect(main).toContainText(`👤 ${state.soignant.prenom} ${state.soignant.nom} · ${state.soignant.profession}`);
    await expect(main.getByText('Distance GPS', { exact: true })).toBeVisible();
    await expect(main.getByText('37m', { exact: true })).toBeVisible();
    await preuveGardes(page, info, 'etablissement-presences-conservees');
    await stabiliserActionsNationales(page);
    await page.reload();
    await expect(main.getByText('37m', { exact: true })).toBeVisible();
    expect(appels.map(a => a.corps)).toEqual([{ p_mission_id: ids.mission }, { p_mission_id: ids.mission }]);
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });
});

test.describe('fiche mission établissement (fn_booster_mission, fn_activer_garantie_mission)', () => {
  test('établissement propriétaire : boost et protection remplacement acceptés, repris après rechargement', async ({ context, page }, info) => {
    const { state, installer } = creerSuiviSimule();
    const appels: AppelRpc[] = [];
    await installer(context, 'ADMIN_ETABLISSEMENT');
    await neutraliserTiers(context);
    await surchargerRpc(context, new Map<string, (corps: any) => unknown>([
      ['fn_booster_mission', () => { (state.mission as any).boostee_le = heureRecette; return { success: true, soignants_notifies: 3, prix_ht: 0 }; }],
      ['fn_activer_garantie_mission', corps => { (state.mission as any).garantie_remplacement = corps.p_actif; return { success: true, garantie: corps.p_actif }; }],
    ]), appels);
    await page.clock.setFixedTime(new Date(now));
    await page.goto(`/etablissement/missions/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, level: 1 })).toBeVisible();
    const main = page.locator('main');
    await expect(main.getByText('Booster cette mission', { exact: true })).toBeVisible();
    await main.getByRole('button', { name: 'Booster', exact: true }).click();
    await expect(page.getByText('Mission boostée — 3 soignants compatibles notifiés, priorité dans le feed.', { exact: true })).toBeVisible();
    await main.getByRole('button', { name: 'Activer', exact: true }).click();
    await expect(page.getByText('Protection remplacement activée ✓', { exact: true })).toBeVisible();
    await expect(main.getByRole('button', { name: 'Activée ✓', exact: true })).toBeVisible();
    expect(appels).toEqual([
      { nom: 'fn_booster_mission', corps: { p_mission_id: ids.mission } },
      { nom: 'fn_activer_garantie_mission', corps: { p_mission_id: ids.mission, p_actif: true } },
    ]);
    await preuveGardes(page, info, 'etablissement-boost-garantie-conserves');
    await stabiliserActionsNationales(page);
    await page.reload();
    await expect(main.getByRole('button', { name: 'Activée ✓', exact: true })).toBeVisible();
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });
});

test.describe('DPAE du contrat (fn_generer_donnees_dpae, fn_enregistrer_numero_dpae)', () => {
  function contratSalarie() {
    const banc = creerMissionSimulee();
    const { state } = banc;
    state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = 'SALARIE'; state.mission.type_contrat_recherche = 'SALARIE';
    state.mission.type_paiement_soignant = 'BULLETIN_PAIE';
    // CHECK contrats_mission.type_contrat : CDD, CDDU, VACATION, REMPLACEMENT_LIBERAL (« SALARIE » n'existe pas en base).
    state.contrat.type_contrat = 'CDD';
    state.contrat.contenu_html = '<article><h2>Contrat salarié fictif de recette</h2><p>Camille Recette — Clinique Simulation</p></article>';
    return banc;
  }

  test('établissement propriétaire : préparation puis numéro DPAE enregistré, repris après rechargement', async ({ context, page }, info) => {
    const { state, installer } = contratSalarie();
    await installer(context, 'ADMIN_ETABLISSEMENT');
    await neutraliserTiers(context);
    await page.clock.setFixedTime(new Date(now));
    await page.goto(`/contrat/${ids.contrat}`);
    await expect(page.getByText('DPAE obligatoire — Mission salariée', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Préparer les données DPAE', exact: true }).click();
    await expect(page.getByText(/=== DPAE — Déclaration Préalable à l'Embauche ===/)).toBeVisible();
    await expect(page.getByText(new RegExp(state.soignant.date_naissance))).toBeVisible();
    await page.getByRole('textbox', { name: /Après transmission par vos soins/ }).fill('SIM202600001');
    await page.getByRole('button', { name: 'Enregistrer le numéro DPAE', exact: true }).click();
    await expect(page.getByText('DPAE déclarée', { exact: true })).toBeVisible();
    await expect(page.getByText('SIM202600001', { exact: true })).toBeVisible();
    expect(state.contrat.dpae_numero).toBe('SIM202600001');
    expect(state.calls.filter(c => ['fn_generer_donnees_dpae', 'fn_enregistrer_numero_dpae'].includes(c.name) && c.method === 'POST')
      .map(c => [c.name, c.body])).toEqual([
      ['fn_generer_donnees_dpae', { p_contrat_id: ids.contrat }],
      ['fn_enregistrer_numero_dpae', { p_contrat_id: ids.contrat, p_dpae_numero: 'SIM202600001' }],
    ]);
    await preuveGardes(page, info, 'etablissement-dpae-enregistree');
    await page.reload();
    await expect(page.getByText('DPAE déclarée', { exact: true })).toBeVisible();
    await expect(page.getByText('SIM202600001', { exact: true })).toBeVisible();
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });

  test('membre révoqué en cours de session : préparation refusée « Non autorisé », aucune donnée du salarié', async ({ context, page }, info) => {
    const { state, installer } = contratSalarie();
    // Avant (LIVE non corrigé, simulé) : mon_etablissement_id() NULL, la garde
    // valait NULL et les données DPAE du salarié étaient renvoyées.
    let revoque = false;
    const appels: AppelRpc[] = [];
    await installer(context, 'ADMIN_ETABLISSEMENT');
    await neutraliserTiers(context);
    // Avant la révocation : réponse du harnais (données DPAE) ; après : refus LIVE corrigé.
    await surchargerRpc(context, new Map([['fn_generer_donnees_dpae', () => REFUS.dpae]]), appels, () => revoque);
    await page.clock.setFixedTime(new Date(now));
    await page.goto(`/contrat/${ids.contrat}`);
    await expect(page.getByText('DPAE obligatoire — Mission salariée', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Préparer les données DPAE', exact: true }).click();
    await expect(page.getByText(new RegExp(state.soignant.date_naissance))).toBeVisible();
    await preuveGardes(page, info, 'revoque-dpae-avant-fuite-simulee');

    // Après (fonction corrigée), même session ouverte après la révocation.
    revoque = true;
    await page.reload();
    await expect(page.getByText('DPAE obligatoire — Mission salariée', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Préparer les données DPAE', exact: true }).click();
    const alerte = page.getByRole('region', { name: 'Notifications', exact: true }).getByRole('alert');
    const verifierRefus = async () => {
      await expect(alerte.getByText('Non autorisé', { exact: true })).toBeVisible();
      await expect(page.getByText(/=== DPAE — Déclaration Préalable à l'Embauche ===/)).toHaveCount(0);
      await expect(page.locator('main')).not.toContainText(state.soignant.date_naissance);
      await expect(page.getByRole('button', { name: 'Enregistrer le numéro DPAE', exact: true })).toHaveCount(0);
      await expect(page.getByRole('button', { name: 'Préparer les données DPAE', exact: true })).toBeEnabled();
    };
    await verifierRefus();
    // Dump pris tant que la notification d'erreur (7 s) est affichée.
    await preuveGardes(page, info, 'revoque-dpae-apres-refus');
    // Reprise après rechargement : même refus, aucune donnée, aucun numéro.
    await page.reload();
    await page.getByRole('button', { name: 'Préparer les données DPAE', exact: true }).click();
    await verifierRefus();
    expect(appels).toEqual([
      { nom: 'fn_generer_donnees_dpae', corps: { p_contrat_id: ids.contrat } },
      { nom: 'fn_generer_donnees_dpae', corps: { p_contrat_id: ids.contrat } },
    ]);
    expect(state.contrat.dpae_numero).toBeUndefined();
    expect(state.emails).toEqual([]);
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
  });
});
