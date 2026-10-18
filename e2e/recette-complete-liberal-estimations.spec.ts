import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids as idsMission, preuveMission } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { simulerEtablissement, entrer, allerA, stabiliserLectures, etablissement, ids, preuve } from './helpers/recette-complete-etablissement';

// Vrai frontend et réponses fictives : aucun SQL, publication ou fournisseur.
// Exécution sur les cinq projets de playwright.recette-complete.config.ts.
const maintenant = '2026-10-18T06:00:00.000Z';
const debut = '2026-10-25T08:00:00.000Z';
const fin = '2026-10-25T08:10:00.000Z';
const mode = { niveau: 'NON_PROPOSE', categorie: 'prive',
  source_libelle: 'Configuration fictive : choix libéral disponible.',
  source_force: 'CONFORMITE_JOLENE', source_url: null };

async function activer(page: Page, cible: Locator, info: TestInfo) {
  await cible.scrollIntoViewIfNeeded();
  if (info.project.use.hasTouch) await cible.tap(); else await cible.click();
}

for (const role of ['ADMIN_ETABLISSEMENT', 'SOIGNANT'] as const) {
  test(`Choix LIBERAL avant attribution : régime et base serveur stables après recharge — ${role}`, async ({ page, context }, info) => {
    const simulation = creerSuiviSimule();
    const { state } = simulation;
    Object.assign(state.etablissement, { type: 'EHPAD', est_secteur_public: false });
    Object.assign(state.soignant, { profession: 'IDE' });
    Object.assign(state.mission, {
      intitule: 'IDE libéral — dix minutes dimanche', profession_requise: 'IDE',
      debut_le: debut, fin_le: fin, duree_heures: 0.17, taux_horaire_base: 30,
      type_contrat_recherche: 'LIBERAL', type_contrat_applique: null, statut: 'OUVERTE',
      soignant_assigne_id: null, total_brut: 7.5, net_a_payer: 7.5, net_estime: 5.85,
      heures_dimanche: 0.17, montant_majoration_dimanche: 2.5,
      montant_commission_ht: 1.13, montant_commission_tva: 0.23, montant_commission_ttc: 1.36,
      taux_commission: 15, taux_commission_fige: null,
    });
    Object.assign(state.creneaux[0], { debut, fin });
    await simulation.installer(context, role);
    // CSS de police remplacé localement ; toute autre origine reste refusée.
    await context.route('https://fonts.googleapis.com/**', async route => {
      if (route.request().method() !== 'GET') return route.fallback();
      return route.fulfill({ contentType: 'text/css', body: '' });
    });
    await page.clock.setFixedTime(new Date(maintenant));
    await page.route('**/rest/v1/rpc/fn_mode_exercice', async route => {
      expect(['localhost', '127.0.0.1']).toContain(new URL(route.request().url()).hostname);
      expect(route.request().postDataJSON()).toEqual({ p_profession: 'IDE', p_type_etab: 'EHPAD', p_finess_secteur: null });
      return route.fulfill({ json: mode });
    });
    try {
      const espace = role === 'SOIGNANT' ? 'soignant' : 'etablissement';
      await page.goto(`/${espace}/missions/${idsMission.mission}`);
      for (const recharge of [false, true]) {
        if (recharge) { await stabiliserActionsNationales(page); await page.reload(); }
        await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
        const bloc = page.getByRole('heading', { name: /Décomposition financière/ }).locator('..').locator('..');
        await expect(bloc.getByText('Contrat libéral', { exact: true })).toBeVisible();
        await expect(bloc.getByText('Contrat salarié (CDD)', { exact: true })).toHaveCount(0);
        await expect(bloc.getByText('Base hors majorations', { exact: true }).locator('..')).toContainText(/5,00\s*€/);
        await expect(bloc.getByText('Majorations', { exact: true }).locator('..')).toContainText(/2,50\s*€/);
        await expect(bloc.getByText('Brut honoraires soignant', { exact: true }).locator('..')).toContainText(/7,50\s*€/);
        await expect(bloc).not.toContainText(/5,10\s*€|5,85\s*€/);
        const commission = bloc.getByText('Commission Jolene prévisionnelle', { exact: true });
        if (role === 'ADMIN_ETABLISSEMENT') await expect(commission.locator('..')).toContainText(/1,36\s*€ TTC/);
        else await expect(commission).toHaveCount(0);
        await preuveMission(page, info, `liberal-avant-attribution-${role}-${recharge ? 'recharge' : 'initial'}`);
      }
      expect(state.mission.soignant_assigne_id).toBeNull();
      expect(state.mission.type_contrat_applique).toBeNull();
      expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
      expect(state.sms).toEqual([]); expect(state.signatures).toEqual([]);
    } finally {
      await info.attach('liberal-avant-attribution-reponses-fictives', { body: JSON.stringify({
        simulation: true, backendVerified: false, providerVerified: false, role,
        mission: state.mission, appels: state.calls, inconnus: state.unknown,
      }, null, 2), contentType: 'application/json' });
    }
  });
}

test('Création LIBERAL : récap 7,50 + 1,36 = 8,86, attente, erreur et reprise après recharge', async ({ page }, info) => {
  const { etat, parcours } = await simulerEtablissement(page);
  const appelsCalcul: unknown[] = [];
  let reponseInvalide = false;
  let liberer!: () => void;
  let attente: Promise<void> | null = new Promise(resolve => { liberer = resolve; });
  Object.assign(parcours.donnees, { brouillonMission: true, missionFormulaire: {
    intitule: 'IDE libéral — estimation dimanche', profession: 'IDE', service: 'Soins',
    description: 'Brouillon fictif repris par le vrai formulaire.', tauxHoraire: '30',
    estUrgente: false, modeAttribution: 'CANDIDATURE', contratPreference: 'SALARIE',
    creneaux: [{ debut, fin }],
  } });
  etat.overrides.set('fn_mon_etablissement_complet', { ...etablissement, est_secteur_public: false,
    taux_commission_effectif: 15, taux_majoration_nuit_pourcent: 25,
    taux_majoration_dimanche_pourcent: 50, taux_majoration_ferie_pourcent: 100 });
  etat.overrides.set('fn_mode_exercice', mode);
  await page.clock.setFixedTime(new Date(maintenant));
  await page.route('**/rest/v1/rpc/fn_calculer_remuneration_mission', async route => {
    const requete = route.request();
    expect(['localhost', '127.0.0.1']).toContain(new URL(requete.url()).hostname);
    expect(requete.method()).toBe('POST');
    const corps = requete.postDataJSON(); appelsCalcul.push(corps);
    expect(corps).toMatchObject({ p_etablissement_id: ids.etab, p_taux_base: 30 });
    expect(new Date(corps.p_debut).toISOString()).toBe(debut);
    expect(new Date(corps.p_fin).toISOString()).toBe(fin);
    expect(corps.p_soignant_id ?? null).toBeNull();
    if (attente) await attente;
    return route.fulfill({ json: reponseInvalide ? { total_brut: null } : {
      total_brut: 7.5, montant_base: 5, montant_majoration_dimanche: 2.5,
      // Le défaut CDD de cette RPC ne doit jamais gonfler les honoraires LIBERAL.
      net_a_payer: 9.08, montant_ifm: 0.75, montant_icp: 0.83,
    } });
  });
  const ouvrirRecap = async () => {
    await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('IDE libéral — estimation dimanche');
    const choixLiberal = page.getByRole('radio', { name: /^Libéral Honoraires/ });
    await expect(choixLiberal).toBeEnabled();
    await activer(page, choixLiberal, info);
    await page.getByRole('radio', { name: /^Soin à finalité thérapeutique/ }).check();
    await expect(page.getByText('Base des honoraires HT, hors majorations', { exact: true })).toBeVisible();
    await activer(page, page.getByRole('button', { name: 'Publier la mission', exact: true }), info);
    return page.getByRole('dialog');
  };
  const verifierMontants = async (dialogue: Locator) => {
    await expect(dialogue.getByText('Honoraires estimés HT, majorations incluses', { exact: true }).locator('..')).toHaveText(/Honoraires estimés HT, majorations incluses\s*7\.50 €/);
    await expect(dialogue.getByText('Frais Jolene (15% HT)', { exact: true }).locator('..')).toContainText('+1.13 €');
    await expect(dialogue.getByText('TVA 20 % sur les frais Jolene', { exact: true }).locator('..')).toContainText('+0.23 €');
    await expect(dialogue.getByText('Total estimé hors éventuelle TVA sur les honoraires', { exact: true }).locator('..')).toContainText('8.86 €');
    await expect(dialogue).not.toContainText('5.90 €');
    await expect(dialogue).not.toContainText('9.08 €');
    await expect(dialogue.getByRole('button', { name: /Publier/ })).toBeEnabled();
  };
  try {
    await entrer(page, 'connexion');
    await allerA(page, '/etablissement/missions/creer');
    let dialogue = await ouvrirRecap();
    await expect(dialogue.getByRole('status')).toHaveText('Calcul des honoraires et majorations…');
    await expect(dialogue.getByRole('button', { name: /Publier/ })).toBeDisabled();
    await expect(dialogue.getByText('Total estimé hors éventuelle TVA sur les honoraires', { exact: true })).toHaveCount(0);
    await expect.poll(() => appelsCalcul.length).toBe(1);
    attente = null; liberer();
    await verifierMontants(dialogue);
    await preuve(page, 'liberal-recap-montants-initiaux', info);
    await activer(page, dialogue.getByRole('button', { name: /Modifier/ }), info);
    await expect(dialogue).toBeHidden();
    await stabiliserLectures(page); await page.reload();
    dialogue = await ouvrirRecap();
    await verifierMontants(dialogue);
    await preuve(page, 'liberal-recap-montants-recharge', info);
    await activer(page, dialogue.getByRole('button', { name: /Modifier/ }), info);
    reponseInvalide = true;
    dialogue = await ouvrirRecap();
    await expect(dialogue.getByRole('alert')).toContainText('Le coût avec majorations ne peut pas être calculé');
    await expect(dialogue.getByRole('button', { name: /Publier/ })).toBeDisabled();
    await expect(dialogue.getByText('Total estimé hors éventuelle TVA sur les honoraires', { exact: true })).toHaveCount(0);
    await preuve(page, 'liberal-recap-calcul-indisponible', info);
    await activer(page, dialogue.getByRole('button', { name: /Modifier/ }), info);
    reponseInvalide = false;
    dialogue = await ouvrirRecap();
    await verifierMontants(dialogue);
    await preuve(page, 'liberal-recap-reprise-calcul', info);
    // La publication réelle n'est pas exercée dans ce banc d'affichage.
    expect(etat.operations).toEqual([]); expect(etat.ecritures).toEqual([]);
    expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
    expect(appelsCalcul).toHaveLength(4);
  } finally {
    liberer();
    await info.attach('liberal-recap-reponses-fictives', { body: JSON.stringify({
      simulation: true, backendVerified: false, providerVerified: false,
      published: false, appelsCalcul, inconnus: etat.inconnues, erreurs: etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});
