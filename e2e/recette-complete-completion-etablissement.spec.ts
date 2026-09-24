import { test, expect, type Page } from '@playwright/test';
import { simulerCompletionEtablissement, nomRecette, siretRecette } from './helpers/recette-complete-completion-etablissement';
import { entrer, allerA, preuve, stabiliserLectures, ids, email, simulerEtablissement, mission } from './helpers/recette-complete-etablissement';

test.setTimeout(180_000);
test.use({ actionTimeout: 15_000 });
const jour = '2030-10-15';
const titre = 'Renfort IDE — brouillon conservé';

async function remplirProfil(page: Page) {
  await page.getByLabel("Nom de l'établissement *", { exact: true }).fill(nomRecette);
  await page.getByLabel('SIRET * (14 chiffres)', { exact: true }).fill(siretRecette);
  await page.getByLabel("Type d'établissement *", { exact: true }).selectOption('EHPAD');
  await page.getByLabel('Ville *', { exact: true }).fill('Paris');
  await expect(page.getByText('Vérification simulée : dossier à examiner.', { exact: true })).toBeVisible();
}

test('complétion établissement : validation, sauvegarde partielle, panne et reprise depuis inscription', async ({ page }, info) => {
  const { etat, parcours, state } = await simulerCompletionEtablissement(page);
  await entrer(page, 'inscription');
  await allerA(page, '/etablissement/mon-compte');
  await page.getByRole('button', { name: 'Mon établissement', exact: true }).click();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  const nom = page.getByLabel("Nom de l'établissement *", { exact: true });
  await nom.fill('');
  await page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('nom, SIRET valide, type d’établissement, ville');
  expect(state.appels.some(a => a.nom === 'register-etablissement')).toBe(false);
  await nom.fill(nomRecette); await page.getByLabel('Ville *', { exact: true }).fill('Paris');
  await page.getByRole('button', { name: 'Enregistrer et continuer plus tard', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
  expect(parcours.donnees).toMatchObject({ nom: nomRecette, ville: 'Paris' });
  expect(etat.mode).toBe('minimal');
  await allerA(page, '/inscription/completer');
  await expect(nom).toHaveValue(nomRecette); await expect(page.getByLabel('Ville *', { exact: true })).toHaveValue('Paris');
  await page.getByLabel('SIRET * (14 chiffres)', { exact: true }).fill('123');
  await page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('SIRET valide');
  await remplirProfil(page);
  state.erreurInscription = true;
  await page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Enregistrement temporairement indisponible. Votre saisie est conservée.');
  await expect(nom).toHaveValue(nomRecette); await expect(page.getByLabel('SIRET * (14 chiffres)', { exact: true })).toHaveValue(siretRecette);
  expect(etat.mode).toBe('minimal');
  await preuve(page, 'completion-etablissement-panne-conservee', info);
  state.erreurInscription = false;
  await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
  await expect(page.getByText('Votre compte est en cours de vérification', { exact: true })).toBeVisible();
  expect(state.appels.filter(a => a.nom === 'register-etablissement')).toHaveLength(2);
  expect(state.appels.find(a => a.nom === 'register-etablissement')?.payload).toMatchObject({ nom: nomRecette, siret: siretRecette, type: 'EHPAD', adresse_ville: 'Paris', email_contact: email, finess: null, telephone_contact: null });
  await allerA(page, '/etablissement/equipe');
  await expect(page.getByRole('heading', { name: 'Mon équipe', exact: true })).toBeVisible();
  await preuve(page, 'completion-etablissement-retour-app', info);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

test('onglets complémentaires : planning, sections facturation et retours aux vues métier', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.donnees = true;
  await page.clock.setFixedTime(new Date('2026-09-24T10:00:00Z'));
  const mobile = (page.viewportSize()?.width ?? 1440) < 768;
  await entrer(page, 'connexion');
  const geometrie = await page.evaluate(() => {
    const largeur = document.documentElement.clientWidth;
    const cartes = Array.from(document.querySelectorAll('main button')).filter(element => ['Missions ouvertes', 'Assignées', 'En cours', 'Terminées'].some(nom => element.textContent?.startsWith(nom))).map(element => {
      const r = element.getBoundingClientRect(), cellule = element.parentElement!.getBoundingClientRect();
      return { texte: element.textContent?.trim(), gauche: r.left, droite: r.right, celluleGauche: cellule.left, celluleDroite: cellule.right };
    });
    return { largeur, contenu: document.documentElement.scrollWidth, cartes, debordements: Array.from(document.querySelectorAll('main button, main .grid > div')).map(element => {
      const r = element.getBoundingClientRect();
      return { texte: element.textContent?.trim().slice(0, 90), gauche: r.left, droite: r.right, largeur: r.width };
    }).filter(r => r.droite > largeur + 1 || r.gauche < -1) };
  });
  await info.attach('dashboard-rempli-geometrie', { body: JSON.stringify(geometrie, null, 2), contentType: 'application/json' });
  expect(geometrie.contenu, JSON.stringify(geometrie)).toBeLessThanOrEqual(geometrie.largeur + 1);
  expect(geometrie.debordements).toEqual([]);
  expect(geometrie.cartes).toHaveLength(4);
  for (const carte of geometrie.cartes) {
    expect(carte.gauche, carte.texte).toBeGreaterThanOrEqual(carte.celluleGauche - 1);
    expect(carte.droite, carte.texte).toBeLessThanOrEqual(carte.celluleDroite + 1);
  }
  const planning = page.locator('.card-base').filter({ has: page.getByRole('heading', { name: 'Planning missions à venir', exact: true }) });
  for (const nom of mobile ? ['Semaine', 'Liste'] : ['Semaine', 'Liste', 'Mois']) {
    const onglet = page.getByRole('tab', { name: nom, exact: true });
    await onglet.click();
    await expect(onglet).toHaveAttribute('aria-selected', 'true');
    if (nom === 'Semaine') await expect(planning.getByRole('button', { name: 'Semaine suivante', exact: true })).toBeVisible();
    if (nom === 'Liste') {
      await expect(planning.getByText(mission.intitule, { exact: true })).toBeVisible();
      await expect(planning).toContainText('07:00 → 19:00');
    }
    if (nom === 'Mois') {
      await planning.getByRole('button', { name: 'Mois suivant', exact: true }).click();
      await expect(planning.getByText('octobre 2026', { exact: true })).toBeVisible();
      await expect(planning.getByRole('button', { name: `07:00 ${mission.intitule}`, exact: true })).toBeVisible();
    }
    await preuve(page, `planning-${nom.toLowerCase()}`, info);
  }
  if (mobile) await expect(page.getByRole('tab', { name: 'Mois', exact: true })).toHaveCount(0);

  await allerA(page, '/etablissement/facturation');
  const sections = [
    ['À payer', 'section-a-payer', 'Échéances à payer aux soignants (0)', 'Aucune échéance en attente de paiement soignant.'],
    ['En attente', 'section-attente', 'Paiements en attente (0)', 'Aucun paiement en attente de confirmation soignant.'],
    ['Commissions', 'section-commissions', 'Commissions Jolene (0)', 'Aucune facture de commission à régler ou en cours.'],
    ['Historique', 'section-historique', 'Historique paiements (0 confirmé)', "Aucun paiement confirmé pour l'instant."],
    ['Exports', 'section-exports', 'Exports comptables', 'Téléchargez vos données financières pour votre comptabilité.'],
  ];
  for (const [nom, id, titreSection, contenu] of sections) {
    const section = page.locator(`#${id}`);
    const declencheur = section.getByRole('button', { name: titreSection, exact: true });
    if (mobile) {
      await page.getByRole('button', { name: nom, exact: true }).click();
    } else {
      await expect(declencheur).toHaveAttribute('aria-expanded', 'true');
      await declencheur.click();
      await expect(declencheur).toHaveAttribute('aria-expanded', 'false');
      await expect(section.getByText(contenu, { exact: true })).toBeHidden();
      await declencheur.click();
    }
    await expect(declencheur).toHaveAttribute('aria-expanded', 'true');
    await expect(section.getByText(contenu, { exact: true })).toBeVisible();
    await preuve(page, `facturation-section-${id}`, info);
  }
  await page.getByRole('button', { name: /Export comptable \/ Paie/ }).click();
  await expect(page).toHaveURL(/\/etablissement\/export-paie$/);
  await expect(page.getByRole('heading', { name: 'Export Paie', exact: true })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Aucune période salariée validée', exact: true })).toBeVisible();

  await allerA(page, '/etablissement/rh');
  await page.getByRole('tab', { name: 'Analytics', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Indicateurs de performance', exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Statistiques RH', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Statistiques RH', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByText('Coût moyen / heure', { exact: true })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Indicateurs de performance', exact: true })).toBeHidden();
  await preuve(page, 'retour-statistiques-rh', info);

  await allerA(page, '/etablissement/litiges');
  await page.getByRole('tab', { name: 'Réclamations générales', exact: true }).click();
  await expect(page.getByText('Aucune réclamation pour le moment.', { exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Litiges mission', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Litiges mission', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByText('Aucun litige en cours', { exact: true })).toBeVisible();
  await expect(page.getByText('Aucune réclamation pour le moment.', { exact: true })).toBeHidden();
  await preuve(page, 'retour-litiges-mission', info);

  const statutsReclames: unknown[] = [];
  page.on('request', requete => {
    if (new URL(requete.url()).pathname === '/rest/v1/rpc/fn_mes_reclamations') statutsReclames.push(requete.postDataJSON()?.p_statut);
  });
  await allerA(page, '/etablissement/mes-reclamations');
  await expect(page.getByText('Aucune réclamation', { exact: true })).toBeVisible();
  for (const [nom, statut] of [['En attente', 'PENDING'], ['Traitées', 'TRAITEE'], ['Toutes', null]] as const) {
    await page.getByRole('button', { name: nom, exact: true }).click();
    await expect.poll(() => statutsReclames.at(-1)).toBe(statut);
    await expect(page.getByText('Aucune réclamation', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: nom, exact: true })).toHaveClass(/bg-primary/);
    await preuve(page, `reclamations-filtre-${nom.replaceAll(' ', '-')}`, info);
  }

  await allerA(page, `/etablissement/missions/${ids.mission}`);
  await page.getByRole('tab', { name: 'Soignants recommandés', exact: true }).click();
  await expect(page.getByText('Aucun soignant disponible pour cette profession.', { exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Détails', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Détails', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('heading', { name: mission.intitule, exact: true })).toBeVisible();
  await expect(page.getByText(mission.description, { exact: true })).toBeVisible();
  await expect(page.getByText('Aucun soignant disponible pour cette profession.', { exact: true })).toBeHidden();
  await preuve(page, 'retour-details-mission', info);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

test('complétion depuis mission : brouillon conservé, garde publication, création puis modification simulées', async ({ page }, info) => {
  const { etat, parcours, state } = await simulerCompletionEtablissement(page);
  await entrer(page, 'inscription');
  await page.locator('main').getByRole('button', { name: 'Publier une mission', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/missions\/creer/);
  await page.getByLabel('Intitulé *', { exact: true }).fill(titre);
  await page.getByLabel('Description', { exact: true }).fill('Une mission préparée avant de renseigner le dossier.');
  await page.locator('#mission-profession').click();
  await page.getByRole('option', { name: /Infirmier.*Diplômé.*IDE/ }).click();
  await page.getByRole('radio', { name: /^Salarié/ }).check();
  await page.getByLabel('Première date affichée *', { exact: true }).fill(jour);
  await page.getByLabel('Dernière date affichée *', { exact: true }).fill(jour);
  await page.getByRole('button', { name: 'Toutes les dates', exact: true }).click();
  await page.getByLabel(`Début du créneau 1 du ${jour}`, { exact: true }).fill('07:00');
  await page.getByLabel(`Fin du créneau 1 du ${jour}`, { exact: true }).fill('19:00');
  await page.getByLabel('Taux horaire brut * (€/h)', { exact: true }).fill('30');
  await page.getByRole('button', { name: 'Publier la mission', exact: true }).click();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  expect(state.mission).toBeNull();
  expect(parcours.donnees.missionFormulaire).toMatchObject({ intitule: titre, profession: 'IDE', contratPreference: 'SALARIE', tauxHoraire: '30', creneaux: [{ debut: '2030-10-15T05:00:00.000Z', fin: '2030-10-15T17:00:00.000Z' }] });
  await remplirProfil(page);
  await page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/missions\/creer\?inscription=1$/);
  await expect(page.getByText(`Brouillon repris — ${titre}`, { exact: true })).toBeVisible();
  await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue(titre);
  await expect(page.getByLabel('Première date affichée *', { exact: true })).toHaveValue(jour);
  await expect(page.getByLabel(`Début du créneau 1 du ${jour}`, { exact: true })).toHaveValue('07:00');
  await expect(page.getByLabel(`Fin du créneau 1 du ${jour}`, { exact: true })).toHaveValue('19:00');
  await expect(page.getByRole('button', { name: 'Publier la mission', exact: true })).toBeDisabled();
  expect(state.mission).toBeNull();
  await preuve(page, 'mission-apres-completion-garde-verification', info);

  // Événement serveur explicitement simulé : vérification et contrat de service validés.
  // Ce test ne prétend pas accomplir ces contrôles externes ni signer le contrat de service.
  Object.assign(state.profil, { statut_verification: 'VERIFIE', est_verifie: true, peut_publier_missions: true, contrat_service_signe: true, contrat_service_statut: 'SIGNE' });
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue(titre);
  await page.getByRole('button', { name: 'Publier la mission', exact: true }).click();
  const recap = page.getByRole('dialog');
  await expect(recap).toContainText('12h00'); await expect(recap).toContainText('360.00 €');
  state.erreurPublication = true;
  await recap.getByRole('button', { name: '📤 Publier', exact: true }).click();
  await expect(page.getByText('Une erreur est survenue. Veuillez réessayer.', { exact: true })).toBeVisible();
  expect(state.mission).toBeNull(); await expect(recap).toBeVisible();
  state.erreurPublication = false;
  await recap.getByRole('button', { name: '📤 Publier', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/missions$/);
  await expect(page.getByText(titre, { exact: true }).first()).toBeVisible();
  expect(parcours.donnees.brouillonMission).toBe(false);
  expect(state.mission).toMatchObject({ intitule: titre, debut_le: '2030-10-15T05:00:00.000Z', fin_le: '2030-10-15T17:00:00.000Z', total_brut: 360 });
  expect(state.appels.filter(a => a.nom === 'fn_creer_mission_multi_jours_v3')).toHaveLength(2);
  await allerA(page, `/etablissement/missions/${ids.mission}/modifier`);
  await page.getByLabel('Intitulé *', { exact: true }).fill(`${titre} — modifiée`);
  await page.getByRole('button', { name: 'Enregistrer les modifications', exact: true }).click();
  state.erreurModification = true;
  await recap.getByRole('button', { name: '💾 Enregistrer', exact: true }).click();
  await expect(page.getByText('Une erreur est survenue. Veuillez réessayer.', { exact: true })).toBeVisible();
  expect(state.mission?.intitule).toBe(titre);
  state.erreurModification = false;
  await recap.getByRole('button', { name: '💾 Enregistrer', exact: true }).click();
  await expect(page).toHaveURL(`/etablissement/missions/${ids.mission}`);
  await expect(page.getByRole('heading', { name: `${titre} — modifiée`, exact: true })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByRole('heading', { name: `${titre} — modifiée`, exact: true })).toBeVisible();
  expect(state.appels.filter(a => a.nom === 'fn_modifier_mission_etablissement_v4')).toHaveLength(2);
  expect(state.appels.filter(a => a.nom === 'fn_modifier_mission_etablissement_v4').at(-1)?.payload).toMatchObject({ p_mission_id: ids.mission, p_intitule: `${titre} — modifiée`, p_creneaux: [{ debut: '2030-10-15T05:00:00.000Z', fin: '2030-10-15T17:00:00.000Z' }] });
  await preuve(page, 'mission-publiee-modifiee-relue', info);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});
