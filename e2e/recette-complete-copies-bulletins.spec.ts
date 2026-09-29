import { test, expect, type Page } from '@playwright/test';
import { createHash } from 'node:crypto';
import { simulerEtablissement, entrer as entrerEtab, preuve as preuveEtab } from './helpers/recette-complete-etablissement';
import { simulerSoignant, entrer as entrerSoignant, preuve as preuveSoignant, ids as soignantIds } from './helpers/recette-complete-soignant';
import { recetteCopies, pdfFictif } from './helpers/recette-copies-bulletins';

// Le blocage SW de Playwright injecte son code dans tous les cadres, dont le
// PDF sandboxé sans même origine. Bloquer l'inscription dans l'app seulement,
// sans relâcher le sandbox du produit ni filtrer ses erreurs JavaScript.
test.use({ serviceWorkers: 'allow' });
function bloquerServiceWorkerRecette() {
  if (window === window.top && 'serviceWorker' in navigator) navigator.serviceWorker.register = async () => { throw new Error('Service worker désactivé pour cette simulation'); };
}
test.beforeEach(async ({ context }) => { await context.addInitScript(bloquerServiceWorkerRecette); });

const section = (page: Page) => page.getByRole('region', { name: 'Copies des bulletins officiels', exact: true });
const aucunPaiement = (appels: { nom: string }[]) => expect(appels.some(a => /paiement|escrow|stripe|cotisation/.test(a.nom))).toBe(false);
async function ouvrirDepot(page: Page, pdf: ReturnType<typeof pdfFictif>, remplacement = false) {
  if (!remplacement) await section(page).getByRole('button', { name: 'Déposer une copie officielle', exact: true }).click();
  const dialog = page.getByRole('dialog');
  if (!remplacement) {
    await dialog.getByLabel('Début de période', { exact: true }).fill('2026-09-01');
    await dialog.getByLabel('Fin de période', { exact: true }).fill('2026-09-30');
    await expect(dialog.getByRole('combobox', { name: 'Destinataire', exact: true })).toBeEnabled();
    await dialog.getByRole('combobox', { name: 'Destinataire', exact: true }).selectOption(soignantIds.user);
    for (const n of [1, 2]) await dialog.getByRole('checkbox', { name: new RegExp(`Mission salariée ${n}`) }).check();
  }
  await dialog.getByLabel('PDF officiel (10 Mo maximum)', { exact: true }).setInputFiles(pdf);
  await dialog.getByRole('button', { name: 'Aperçu et confirmation', exact: true }).click();
  await expect(dialog.getByText('Destinataire : Camille Recette', { exact: true })).toBeVisible();
  await expect(dialog.getByText(/2 missions sélectionnées/)).toBeVisible();
  await expect(dialog.locator('iframe[title="Aperçu de la copie du bulletin officiel"]')).toHaveAttribute('src', /^blob:/);
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeDisabled();
  await dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ }).check();
  return dialog;
}
async function ouvrirPdf(page: Page, sha256: string) {
  // Chromium headless télécharge le PDF ; WebKit l'affiche dans l'onglet.
  // Les deux chemins doivent restituer exactement les octets originaux.
  const resultat = page.waitForEvent('popup').then(async popup => {
    const bytes = await Promise.any([
      popup.waitForEvent('download').then(async download => {
        expect(await download.failure()).toBeNull();
        const stream = await download.createReadStream(); expect(stream).toBeTruthy();
        const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
        return Buffer.concat(chunks);
      }),
      popup.waitForURL(/^blob:/).then(async () => Buffer.from(await page.evaluate(async url => Array.from(new Uint8Array(await (await fetch(url)).arrayBuffer())), popup.url()))),
    ]);
    expect(createHash('sha256').update(bytes).digest('hex')).toBe(sha256);
    await popup.close();
  });
  await section(page).getByRole('button', { name: 'Ouvrir / télécharger le PDF original', exact: true }).first().click();
  await resultat;
}

test('copie officielle : dépôt unique pour deux missions, consultation salarié et historique après passage libéral', async ({ page, browser }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies(); const pdf = r.enregistrerPdf();
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const dialog = await ouvrirDepot(page, pdf);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await expect(section(page)).toContainText('Une copie disponible ne confirme pas le paiement du salaire.');
  expect(r.state.copies).toHaveLength(1); expect(r.state.copies[0].mission_ids).toHaveLength(2);
  await page.reload(); await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await preuveEtab(page, 'copie-officielle-publiee-etablissement', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]);
  const contexte = await browser.newContext({ baseURL: info.project.use.baseURL, viewport: page.viewportSize()!, locale: 'fr-FR', isMobile: info.project.name !== 'ordinateur', hasTouch: info.project.name !== 'ordinateur' });
  try {
    await contexte.addInitScript(bloquerServiceWorkerRecette);
    const salarie = await contexte.newPage(); const s = await simulerSoignant(salarie);
    // Son historique salarié reste accessible après un changement de mode.
    s.profile.type_exercice = 'LIBERAL'; await r.installer(salarie);
    await entrerSoignant(salarie, 'connexion'); await salarie.goto('/soignant/mes-gains?tab=bulletins');
    await expect(salarie.getByRole('tab', { name: 'Paie', exact: true })).toHaveAttribute('aria-selected', 'true');
    await expect(section(salarie).getByText('Copie disponible', { exact: true })).toBeVisible();
    await ouvrirPdf(salarie, pdf.sha256);
    await salarie.reload(); await expect(section(salarie).getByText('Copie disponible', { exact: true })).toBeVisible();
    await preuveSoignant(salarie, 'copie-officielle-consultee-historique-salarie', info, true);
    expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
  } finally { await contexte.close(); }
  aucunPaiement(r.state.appels);
});

test('dépôt : envoi en panne puis publication en panne, reprise même intention et même PDF', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies(); const pdf = r.enregistrerPdf(); r.state.panneUpload = true;
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const dialog = await ouvrirDepot(page, pdf);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('L’envoi n’a pas été confirmé');
  expect(r.state.copies).toHaveLength(0);
  r.state.panneUpload = false; r.state.pannePublication = true;
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('La publication n’a pas été confirmée');
  expect(r.state.uploads.size).toBe(1); expect(r.state.copies).toHaveLength(0);
  await preuveEtab(page, 'copie-publication-indisponible-reprise', info);
  r.state.pannePublication = false;
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.intentions.size).toBe(1); expect(r.state.copies).toHaveLength(1); expect(r.state.uploads.size).toBe(1);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]); aucunPaiement(r.state.appels);
});

test('publication enregistrée mais réponse perdue : réessai sans nouvelle copie', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies(); const pdf = r.enregistrerPdf(); r.state.perdreReponsePublication = true;
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const dialog = await ouvrirDepot(page, pdf);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('La publication n’a pas été confirmée');
  expect(r.state.copies).toHaveLength(1);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.intentions.size).toBe(1); expect(r.state.copies).toHaveLength(1);
  expect(r.state.appels.filter(a => a.nom === 'upload')).toHaveLength(1);
  await preuveEtab(page, 'copie-reponse-perdue-idempotente', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]);
});

test('remplacement : nouvelle version, ancienne conservée, retrait sans toucher au paiement', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies(); r.copiePubliee(); const nouveau = r.enregistrerPdf(pdfFictif('Copie fictive corrigée - version 2'));
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  await section(page).getByRole('button', { name: 'Remplacer cette version', exact: true }).click();
  const dialog = await ouvrirDepot(page, nouveau, true);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Version remplacée', { exact: true })).toBeVisible();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  const actuelle = section(page).getByRole('article', { name: 'Copie du bulletin, version 2', exact: true });
  await actuelle.getByRole('button', { name: 'Retirer l’accès au PDF', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirmer le retrait', exact: true }).click();
  await expect(actuelle.getByText('Copie retirée', { exact: true })).toBeVisible();
  await expect(actuelle.getByRole('button', { name: 'Ouvrir / télécharger le PDF original', exact: true })).toHaveCount(0);
  await page.reload(); await expect(actuelle.getByText('Copie retirée', { exact: true })).toBeVisible();
  expect(r.state.copies.map(c => c.statut)).toEqual(['REMPLACEE', 'RETIREE']);
  await preuveEtab(page, 'copies-historique-remplacement-retrait', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]); aucunPaiement(r.state.appels);
});

test('salarié : mauvaise destination signalée, accès au PDF retiré après rechargement', async ({ page }, info) => {
  const s = await simulerSoignant(page); const r = recetteCopies(); r.copiePubliee();
  await r.installer(page); await entrerSoignant(page, 'connexion'); await page.goto('/soignant/mes-gains?tab=bulletins');
  await section(page).getByRole('button', { name: 'Signaler une erreur', exact: true }).click();
  await page.getByRole('dialog').getByRole('radio', { name: 'Ce document ne me concerne pas', exact: true }).check();
  await page.getByRole('dialog').getByRole('button', { name: 'Envoyer le signalement', exact: true }).click();
  await expect(section(page).getByText('Copie retirée', { exact: true })).toBeVisible();
  await expect(section(page).getByRole('button', { name: 'Ouvrir / télécharger le PDF original', exact: true })).toHaveCount(0);
  await page.reload(); await expect(section(page).getByText('Copie retirée', { exact: true })).toBeVisible();
  await preuveSoignant(page, 'copie-mauvais-destinataire-retiree', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]); aucunPaiement(r.state.appels);
});

test('copie retirée : nouveau dépôt identique explicite, confirmation renouvelée, ancien document inchangé', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies(); const pdf = r.enregistrerPdf();
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  let dialog = await ouvrirDepot(page, pdf);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  const ancienId = r.state.copies[0].id;
  await section(page).getByRole('button', { name: 'Retirer l’accès au PDF', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirmer le retrait', exact: true }).click();
  await expect(section(page).getByText('Copie retirée', { exact: true })).toBeVisible();
  await page.reload();
  dialog = await ouvrirDepot(page, pdf);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(dialog.getByRole('button', { name: 'Préparer un nouveau dépôt', exact: true })).toBeVisible();
  expect(r.state.intentions.size).toBe(1);
  await dialog.getByRole('button', { name: 'Préparer un nouveau dépôt', exact: true }).click();
  await expect(dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ })).not.toBeChecked();
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeDisabled();
  await dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ }).check();
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.intentions.size).toBe(2); expect(r.state.copies).toHaveLength(2);
  expect(r.state.copies.find(c => c.id === ancienId)?.statut).toBe('RETIREE');
  await page.reload(); await expect(section(page).getByText('Copie retirée', { exact: true })).toBeVisible();
  await preuveEtab(page, 'copie-nouveau-depot-apres-retrait', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]); aucunPaiement(r.state.appels);
});

test('copies : liste malformée ou indisponible, puis reprise sans faux état vide', async ({ page }, info) => {
  const s = await simulerSoignant(page); const r = recetteCopies(); r.copiePubliee(); r.state.listeInvalide = true;
  await r.installer(page); await entrerSoignant(page, 'connexion'); await page.goto('/soignant/mes-gains?tab=bulletins');
  await expect(section(page).getByRole('alert')).toBeVisible();
  await expect(section(page).getByText(/Aucune copie/)).toHaveCount(0);
  r.state.listeInvalide = false; r.state.panneListe = true;
  await section(page).getByRole('button', { name: 'Réessayer les copies', exact: true }).click();
  await expect(section(page).getByRole('alert')).toContainText('Impossible de charger');
  r.state.panneListe = false;
  await section(page).getByRole('button', { name: 'Réessayer les copies', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await preuveSoignant(page, 'copie-liste-reprise', info, true);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});

test('document modifié ou accès refusé : aucun PDF ouvert, reprise contrôlée', async ({ page }, info) => {
  const s = await simulerSoignant(page); const r = recetteCopies(); r.copiePubliee(); r.state.lectureCorrompue = true;
  await r.installer(page); await entrerSoignant(page, 'connexion'); await page.goto('/soignant/mes-gains?tab=bulletins');
  await section(page).getByRole('button', { name: 'Ouvrir / télécharger le PDF original', exact: true }).click();
  await expect(section(page).getByRole('alert')).toContainText('L’intégrité du PDF ne peut pas être confirmée');
  r.state.lectureCorrompue = false; r.state.panneLecture = true;
  await section(page).getByRole('button', { name: 'Ouvrir / télécharger le PDF original', exact: true }).click();
  await expect(section(page).getByRole('alert')).toContainText('Le PDF ne peut pas être ouvert');
  await preuveSoignant(page, 'copie-pdf-refuse', info, true);
  r.state.panneLecture = false; await ouvrirPdf(page, r.state.copies[0].sha256);
  await expect(section(page).getByRole('alert')).toHaveCount(0);
  expect(s.errors).toEqual([]); expect(s.unknown).toEqual([]);
});

test('droit lecture seule : aucune lecture ni publication des copies employeur', async ({ page }, info) => {
  const e = await simulerEtablissement(page); e.etat.permissions = 'LECTURE_SEULE'; const r = recetteCopies(); r.copiePubliee();
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  await expect(page.getByText(/La consultation et le dépôt des copies sont réservés/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Déposer une copie officielle', exact: true })).toHaveCount(0);
  expect(r.state.appels).toEqual([]);
  await preuveEtab(page, 'copies-droits-restreints', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]);
});

test('dépôt : fichier non PDF et période incohérente bloqués avant réservation', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies();
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  await section(page).getByRole('button', { name: 'Déposer une copie officielle', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('PDF officiel (10 Mo maximum)', { exact: true }).setInputFiles({ name: 'faux.pdf', mimeType: 'application/pdf', buffer: Buffer.from('aucun PDF') });
  await expect(dialog.getByRole('alert')).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Aperçu et confirmation', exact: true })).toBeDisabled();
  await dialog.getByLabel('Fin de période', { exact: true }).fill('2026-08-01');
  await expect(dialog.getByText('La fin de période doit être postérieure ou égale au début.', { exact: true })).toBeVisible();
  expect(r.state.intentions.size).toBe(0);
  await preuveEtab(page, 'copie-fichier-periode-refuses', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]);
});
