import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

const roles: RoleRecette[] = ['SOIGNANT', 'ADMIN_ETABLISSEMENT'];
const region = (page: Page) => page.getByRole('region', { name: 'Suivi de la mission', exact: true });
async function ouvrirDetail(page: Page) {
  const bouton = region(page).getByRole('button', { name: /^(Afficher|Masquer) le détail du suivi$/ });
  await expect(bouton).toBeVisible();
  if (await bouton.getAttribute('aria-expanded') === 'false') await bouton.click();
  await expect(region(page).getByRole('button', { name: 'Masquer le détail du suivi', exact: true })).toHaveAttribute('aria-expanded', 'true');
}
async function etape(page: Page, id: string, statut: string) {
  await ouvrirDetail(page);
  await expect(region(page).getByTestId(`suivi-${id}`).getByText(statut, { exact: true })).toBeVisible();
}
async function compact(page: Page, info: TestInfo, nom: string, hauteurMax = 260) {
  const bouton = region(page).getByRole('button', { name: 'Afficher le détail du suivi', exact: true });
  await expect(bouton).toHaveAttribute('aria-expanded', 'false');
  await expect(region(page).getByRole('list', { name: 'Repères du suivi' }).getByRole('listitem')).toHaveCount(6);
  await expect(region(page).getByRole('heading', { name: 'Contrat Jolene', exact: true })).toHaveCount(0);
  const box = await region(page).boundingBox();
  expect(box?.height).toBeLessThanOrEqual(hauteurMax);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await info.attach(`${nom}-geometrie`, { body: JSON.stringify(box), contentType: 'application/json' });
  await region(page).scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath(`${nom}.png`) });
  await info.attach(nom, { path: info.outputPath(`${nom}.png`), contentType: 'image/png' });
}
async function recharger(page: Page) { await stabiliserActionsNationales(page); await page.reload(); await expect(region(page).getByRole('button', { name: 'Actualiser le suivi' })).toBeEnabled(); }
async function actualiser(page: Page) { await region(page).getByRole('button', { name: 'Actualiser le suivi' }).click(); await expect(region(page).getByRole('button', { name: 'Actualiser le suivi' })).toBeEnabled(); }
const chemin = (role: RoleRecette) => `${role === 'SOIGNANT' ? '/soignant' : '/etablissement'}/missions/${ids.mission}`;

for (const role of roles) {
  test(`SUIVI ${role} — attribution, deux signatures, heures et réception restent des étapes distinctes`, async ({ context, page }, info) => {
    const { state, installer, suivi } = creerSuiviSimule();
    state.candidature = { id: ids.candidature, mission_id: ids.mission, soignant_id: ids.soignant, statut: 'EN_ATTENTE', cree_le: now };
    await installer(context, role); await page.clock.setFixedTime(new Date(now));
    try {
      await page.goto(chemin(role)); await expect(region(page)).toBeVisible();
      if (role === 'SOIGNANT') {
        const remuneration = page.getByRole('region', { name: 'Rémunération de la mission' });
        await expect(remuneration).toBeInViewport();
        const finance = await remuneration.boundingBox();
        expect(finance!.y).toBeLessThan(page.viewportSize()!.height / 2);
        expect((await region(page).boundingBox())!.y).toBeGreaterThan(finance!.y + finance!.height);
      }
      await compact(page, info, `suivi-${role}-compact-candidature`);
      if (role === 'ADMIN_ETABLISSEMENT') await expect(page.getByRole('heading', { name: /^Candidatures/ })).toBeInViewport();
      await etape(page, 'attribution', role === 'SOIGNANT' ? 'Candidature envoyée' : 'En attente d’attribution');
      await etape(page, 'document', 'Régime à confirmer');
      expect(suivi.lectures).toEqual([]);

      state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant; state.mission.type_contrat_applique = 'LIBERAL';
      state.candidature.statut = 'ACCEPTEE'; state.candidature.acceptee_a = now; state.contratCree = true;
      await recharger(page); await etape(page, 'attribution', 'Soignant attribué'); await etape(page, 'contrat', 'Signatures à compléter');
      state.contrat.signature_soignant = true; state.contrat.signature_etablissement = true; state.contrat.statut = 'SIGNE_COMPLET';
      await actualiser(page); await etape(page, 'contrat', 'Deux signatures enregistrées');
      await region(page).getByRole('link', { name: 'Consulter le contrat', exact: true }).click();
      await expect(page).toHaveURL(new RegExp(`/contrat/${ids.contrat}$`));
      await expect(page.getByText('Document fictif de recette', { exact: true })).toBeVisible();
      await page.getByRole('button', { name: /Retour/ }).filter({ visible: true }).click();
      await expect(region(page)).toBeVisible();

      state.mission.statut = 'TERMINEE';
      state.presence = { id: ids.presence, mission_id: ids.mission, soignant_id: ids.soignant,
        pointage_arrivee_le: state.mission.debut_le, pointage_depart_le: state.mission.fin_le, valide_par_etablissement: false };
      state.mission.presences = [state.presence];
      state.creneaux.push({ id: 'segment-suivi', mission_id: ids.mission, debut: state.mission.debut_le, fin: state.mission.fin_le, est_pause: false, type_creneau: 'EFFECTIF' });
      await recharger(page);
      if (role === 'ADMIN_ETABLISSEMENT') {
        await expect(page.getByRole('heading', { name: 'Mission terminée 🎉', exact: true })).toBeVisible();
        await page.getByRole('button', { name: 'Fermer', exact: true }).click();
      }
      await etape(page, 'mission', 'Terminée'); await etape(page, 'heures', 'Validation attendue');
      await etape(page, 'document', 'Aucun document disponible'); await etape(page, 'reglement', 'Règlement non confirmé');
      state.presence.valide_par_etablissement = true;
      state.facture = { id: '71000000-0000-4000-8000-000000000008', mission_id: ids.mission, numero_facture: 'SIM-HON-SUIVI',
        statut: 'EMISE', type_document: 'FACTURE', montant_ht: 640, montant_ttc: 640, montant_signe: 640, date_emission: '2026-09-24', template_version: 2 };
      suivi.paiements = [{ statut: 'DECLARE', confirme_par_soignant: false, conteste: false }];
      await actualiser(page); await etape(page, 'heures', 'Présences enregistrées validées'); await etape(page, 'document', 'Document disponible');
      await etape(page, 'reglement', 'Déclaré, à confirmer');
      await region(page).getByRole('button', { name: 'Masquer le détail du suivi' }).click();
      await expect(region(page).getByTestId('suivi-resume')).toHaveText('Règlement · Déclaré, à confirmer');
      await compact(page, info, `suivi-${role}-compact-declare`);
      await ouvrirDetail(page);
      await preuveMission(page, info, `suivi-${role}-declare-non-confirme`);
      suivi.paiements[0].statut = 'CONFIRME'; suivi.paiements[0].confirme_par_soignant = true;
      await actualiser(page); await etape(page, 'reglement', 'Réception enregistrée');
      await expect(region(page).getByText(/Ce suivi ne calcule pas le solde restant/)).toBeVisible();
      await region(page).getByRole('link', { name: 'Voir les présences', exact: true }).click();
      await expect(page).toHaveURL(new RegExp(`/presences/mission/${ids.mission}$`));
      await expect(page.getByRole('heading', { name: 'Mission médecin — recette intégrale', exact: true })).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Détail des créneaux travaillés (1 segment)', exact: true })).toBeVisible();
      await stabiliserActionsNationales(page); await page.goBack(); await expect(region(page)).toBeVisible();
      if (role === 'ADMIN_ETABLISSEMENT') {
        await expect(page.getByRole('heading', { name: 'Mission terminée 🎉', exact: true })).toBeVisible();
        await page.getByRole('button', { name: 'Fermer', exact: true }).click();
      }
      await preuveMission(page, info, `suivi-${role}-reception-enregistree`);
      expect(suivi.lectures.every(l => l.missionId === `eq.${ids.mission}`)).toBe(true);
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
      expect(state.signatures).toHaveLength(0); expect(state.sms).toHaveLength(0); expect(state.emails).toHaveLength(0);
    } finally { await info.attach('suivi-api-simulee', { body: JSON.stringify({ state, suivi: { ...suivi, erreurs: [...suivi.erreurs] } }, null, 2), contentType: 'application/json' }); }
  });

  test(`SUIVI ${role} — salarié, panne, litige, annulation et accès financier limité`, async ({ context, page }, info) => {
    const { state, installer, suivi } = creerSuiviSimule();
    state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant; state.mission.type_contrat_applique = 'SALARIE';
    state.mission.type_contrat_recherche = 'SALARIE'; state.mission.type_paiement_soignant = 'PAIE_ETABLISSEMENT';
    state.contrat.type_contrat = 'SALARIE'; state.contratCree = true;
    state.presence = { id: ids.presence, mission_id: ids.mission, soignant_id: ids.soignant,
      pointage_arrivee_le: state.mission.debut_le, pointage_depart_le: state.mission.fin_le, valide_par_etablissement: true };
    state.mission.presences = [state.presence];
    suivi.bulletins = [{ statut: 'EMIS', pdf_s3_key: null }]; suivi.erreurs.add('presences');
    await installer(context, role); await page.clock.setFixedTime(new Date(now));
    try {
      await page.goto(chemin(role)); await etape(page, 'heures', 'Information indisponible');
      await expect(region(page).getByRole('alert')).toHaveText('Une partie du suivi n’a pas pu être chargée. Les étapes concernées restent à vérifier.');
      await etape(page, 'document', 'Document à vérifier');
      await expect(region(page).getByRole('heading', { name: 'Bulletin de paie', exact: true })).toBeVisible();
      await expect(region(page).getByText(/contrat de travail de l’employeur se consulte séparément/)).toBeVisible();
      await region(page).getByRole('button', { name: 'Masquer le détail du suivi' }).click();
      await expect(region(page).getByRole('alert')).toBeVisible();
      await compact(page, info, `suivi-${role}-compact-erreur`, 340);
      suivi.erreurs.clear(); suivi.bulletins[0].pdf_s3_key = 'simulation/bulletin.pdf';
      await actualiser(page); await etape(page, 'heures', 'Présences enregistrées validées'); await etape(page, 'document', 'Document disponible');
      await expect(region(page).getByRole('alert')).toHaveCount(0);
      suivi.litige = true; suivi.paiements = [{ statut: 'CONTESTE', confirme_par_soignant: false, conteste: true }];
      state.mission.statut = 'ANNULEE_PAR_ETABLISSEMENT';
      await recharger(page); await etape(page, 'mission', 'Annulée'); await etape(page, 'heures', 'À vérifier — litige en cours');
      await etape(page, 'reglement', 'Règlement contesté');
      await region(page).getByRole('button', { name: 'Masquer le détail du suivi' }).click();
      await expect(region(page).getByRole('status')).toHaveText('Un litige est en cours sur cette mission.');
      await expect(region(page).getByTestId('suivi-resume')).toHaveText('Mission · Annulée');
      await compact(page, info, `suivi-${role}-compact-litige`, 300);
      await ouvrirDetail(page);
      await preuveMission(page, info, `suivi-${role}-salarie-annule-litige`);
      if (role === 'ADMIN_ETABLISSEMENT') {
        suivi.financeAutorisee = false;
        const avant = suivi.lectures.filter(l => ['bulletins_paie', 'paiements_soignant'].includes(l.table)).length;
        await recharger(page); await etape(page, 'document', 'Accès limité'); await etape(page, 'reglement', 'Accès limité');
        await region(page).getByRole('button', { name: 'Masquer le détail du suivi' }).click();
        await expect(region(page).getByText('Accès limité à certaines informations du suivi.')).toBeVisible();
        await compact(page, info, `suivi-${role}-compact-acces-limite`, 340);
        await expect(region(page).getByRole('link', { name: 'Consulter les finances' })).toHaveCount(0);
        expect(suivi.lectures.filter(l => ['bulletins_paie', 'paiements_soignant'].includes(l.table))).toHaveLength(avant);
      }
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
      expect(state.calls.filter(c => ['fn_signer_contrat_otp', 'fn_scanner_code_pointage', 'fn_valider_presence', 'send-email'].includes(c.name))).toEqual([]);
    } finally { await info.attach('suivi-api-simulee', { body: JSON.stringify({ state, suivi: { ...suivi, erreurs: [...suivi.erreurs] } }, null, 2), contentType: 'application/json' }); }
  });
}
