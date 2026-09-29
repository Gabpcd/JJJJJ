import { test, expect, type Page } from '@playwright/test';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { simulerEtablissement, entrer as entrerEtab, preuve as preuveEtab } from './helpers/recette-complete-etablissement';
import { simulerSoignant, entrer as entrerSoignant, preuve as preuveSoignant, ids as soignantIds } from './helpers/recette-complete-soignant';
import { recetteCopies, pdfFictif } from './helpers/recette-copies-bulletins';

const section = (page: Page) => page.getByRole('region', { name: 'Copies des bulletins officiels', exact: true });
const aucunPaiement = (appels: { nom: string }[]) => expect(appels.some(a => /paiement|escrow|stripe|cotisation/.test(a.nom))).toBe(false);
async function ouvrirDepot(page: Page, pdf: ReturnType<typeof pdfFictif>, remplacement = false, verifierRendu = true) {
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
  if (!verifierRendu) return dialog;
  const canvas = dialog.getByTestId('apercu-pdf-canvas');
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  await expect(dialog.getByTestId('apercu-pdf-pagination')).toHaveText('Page 1 sur 2');
  const pixelsSombres = () => canvas.evaluate((el: HTMLCanvasElement) => {
    const data = el.getContext('2d')!.getImageData(0, 0, el.width, el.height).data;
    let sombres = 0; for (let i = 0; i < data.length; i += 4) if (data[i + 3] > 0 && data[i] + data[i + 1] + data[i + 2] < 600) sombres++;
    return sombres;
  });
  expect(await pixelsSombres()).toBeGreaterThan(50);
  await dialog.getByRole('button', { name: 'Page suivante', exact: true }).click();
  await expect(dialog.getByTestId('apercu-pdf-pagination')).toHaveText('Page 2 sur 2');
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  expect(await pixelsSombres()).toBeGreaterThan(50);
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
  await preuveEtab(page, 'copie-apercu-deuxieme-page-visible', info);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await expect(section(page)).toContainText('Une copie disponible ne confirme pas le paiement du salaire.');
  expect(r.state.copies).toHaveLength(1); expect(r.state.copies[0].mission_ids).toHaveLength(2);
  await page.reload(); await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await preuveEtab(page, 'copie-officielle-publiee-etablissement', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]);
  const contexte = await browser.newContext({ baseURL: info.project.use.baseURL, viewport: page.viewportSize()!, locale: 'fr-FR', serviceWorkers: 'block', isMobile: info.project.name !== 'ordinateur', hasTouch: info.project.name !== 'ordinateur' });
  try {
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

test('dépôt : destinataire et missions de deuxième page accessibles après plus de 200 profils', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies(); const pdf = r.enregistrerPdf();
  const profils = Array.from({ length: 200 }, (_, i) => ({
    id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, prenom: `Salarié ${i}`, nom: 'Pagination',
  }));
  r.state.profils = [...profils, ...r.state.profils];
  r.state.missions = [...profils.map((p, i) => ({ ...r.state.missions[0],
    id: `10000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
    intitule: `Mission antérieure ${i}`, soignant_assigne_id: p.id,
  })), ...r.state.missions];
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const dialog = await ouvrirDepot(page, pdf);
  expect(r.state.profils).toHaveLength(201); expect(r.state.missions).toHaveLength(202);
  expect(r.state.pagesProfils).toContain(200); expect(r.state.pagesMissions).toContain(200);
  await expect(dialog.getByText('Destinataire : Camille Recette', { exact: true })).toBeVisible();
  await expect(dialog.getByText('2 missions sélectionnées', { exact: true })).toBeVisible();
  await preuveEtab(page, 'copie-destinataire-deuxieme-page-selectionne', info);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.copies).toHaveLength(1);
  expect(r.state.copies[0].soignant_id).toBe(soignantIds.user);
  expect(r.state.copies[0].mission_ids).toEqual(r.state.missions.slice(200).map(m => m.id));
  await page.reload(); await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]); aucunPaiement(r.state.appels);
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

test('upload reçu puis réponse perdue : reprise après rechargement sur doublon HTTP 400, sans randomUUID', async ({ page }, info) => {
  await page.addInitScript(() => {
    Object.defineProperty(globalThis.crypto, 'randomUUID', { configurable: true, value: undefined });
  });
  const e = await simulerEtablissement(page); const r = recetteCopies(); const pdf = r.enregistrerPdf();
  r.state.perdreReponseUpload = true;
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  let dialog = await ouvrirDepot(page, pdf);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('L’envoi n’a pas été confirmé');
  await expect(dialog.getByRole('alert')).toBeInViewport({ ratio: 1 });
  expect(r.state.intentions.size).toBe(1); expect(r.state.uploads.size).toBe(1); expect(r.state.copies).toHaveLength(0);
  const [cle, reservation] = [...r.state.intentions.entries()][0];
  expect(cle).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  const reservationInitiale = structuredClone(reservation);
  await preuveEtab(page, 'copie-upload-recu-reponse-perdue', info);

  await page.reload(); dialog = await ouvrirDepot(page, pdf);
  r.state.pannePublication = true;
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('La publication n’a pas été confirmée');
  await expect(dialog.getByRole('alert')).toBeInViewport({ ratio: 1 });
  expect(r.state.intentions.size).toBe(1); expect(r.state.intentions.get(cle)).toEqual(reservationInitiale);
  expect(r.state.uploads.size).toBe(1); expect(r.state.uploads.get(reservation.storage_path)).toEqual(pdf.buffer);
  expect(r.state.copies).toHaveLength(0);
  expect(r.state.appels.filter(a => a.nom === 'copies-bulletins' && a.body.action === 'finaliser')).toHaveLength(1);
  await preuveEtab(page, 'copie-doublon-400-verification-encore-requise', info);

  r.state.pannePublication = false;
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.intentions.size).toBe(1); expect(r.state.uploads.size).toBe(1); expect(r.state.copies).toHaveLength(1);
  expect(r.state.copies[0].sha256).toBe(pdf.sha256);
  expect(r.state.appels.filter(a => a.nom === 'upload')).toHaveLength(3);
  expect(r.state.appels.filter(a => a.nom === 'fn_reserver_copie_bulletin').map(a => a.body.p_idempotence)).toEqual([cle, cle, cle]);
  await page.reload(); await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await preuveEtab(page, 'copie-reprise-doublon-400-publiee', info);
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

test('publication : PDF refusé par le serveur, formulaire conservé et autre PDF publié après confirmation', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies();
  // The preview can render this fixture; only the server response is simulated
  // here. Parser validation against real invalid PDFs is covered separately.
  const refuse = r.enregistrerPdf(pdfFictif('Fichier fictif refusé par le serveur'));
  const valide = r.enregistrerPdf({ ...pdfFictif('Fichier fictif corrigé et lisible'), name: 'copie-corrigee.pdf' });
  r.state.pdfRefuses.add(refuse.sha256);
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const dialog = await ouvrirDepot(page, refuse);
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  const alerte = dialog.getByRole('alert');
  await expect(alerte).toHaveText('Le PDF a été refusé : il est illisible, invalide ou protégé. Choisissez « Modifier le dépôt », puis sélectionnez un PDF lisible et non protégé.');
  await expect(alerte).toBeInViewport({ ratio: 1 });
  // Text presence alone misses an alert clipped by the scrolling body/footer.
  const positionAlerte = await alerte.evaluate(el => {
    const rect = el.getBoundingClientRect();
    const corps = el.parentElement!.getBoundingClientRect();
    const boutons = el.parentElement!.nextElementSibling!.getBoundingClientRect();
    return { haut: rect.top, bas: rect.bottom, hautVisible: Math.max(corps.top, 0), basVisible: Math.min(corps.bottom, boutons.top, window.innerHeight) };
  });
  expect(positionAlerte.haut).toBeGreaterThanOrEqual(positionAlerte.hautVisible);
  expect(positionAlerte.bas).toBeLessThanOrEqual(positionAlerte.basVisible);
  await expect(dialog).not.toContainText('COPIE_PDF_INVALIDE');
  await expect(dialog.getByText('Destinataire : Camille Recette', { exact: true })).toBeVisible();
  await expect(dialog.getByText('Période : du 01/09/2026 au 30/09/2026', { exact: true })).toBeVisible();
  await expect(dialog.getByText('2 missions sélectionnées', { exact: true })).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Modifier le dépôt', exact: true })).toBeEnabled();
  expect(r.state.copies).toHaveLength(0); expect(r.state.intentions.size).toBe(1); expect(r.state.uploads.size).toBe(1);
  const [ancienneCle, ancienneReservation] = [...r.state.intentions.entries()][0];
  const reservationInitiale = structuredClone(ancienneReservation);
  await preuveEtab(page, 'copie-refus-serveur-pdf-modifiable', info);

  await dialog.getByRole('button', { name: 'Modifier le dépôt', exact: true }).click();
  await expect(dialog.getByLabel('Début de période', { exact: true })).toHaveValue('2026-09-01');
  await expect(dialog.getByLabel('Fin de période', { exact: true })).toHaveValue('2026-09-30');
  await expect(dialog.getByRole('combobox', { name: 'Destinataire', exact: true })).toHaveValue(soignantIds.user);
  for (const n of [1, 2]) await expect(dialog.getByRole('checkbox', { name: new RegExp(`Mission salariée ${n}`) })).toBeChecked();
  await expect(dialog.getByText(`Fichier sélectionné : ${refuse.name}`, { exact: true })).toBeVisible();
  await dialog.getByLabel('PDF officiel (10 Mo maximum)', { exact: true }).setInputFiles(valide);
  await expect(dialog.getByText(`Fichier sélectionné : ${valide.name}`, { exact: true })).toBeVisible();
  await dialog.getByRole('button', { name: 'Aperçu et confirmation', exact: true }).click();
  await expect(dialog.getByTestId('apercu-pdf-canvas')).toHaveAttribute('data-ready', 'true');
  await expect(dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ })).not.toBeChecked();
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeDisabled();
  expect(r.state.intentions.size).toBe(1);
  expect(r.state.appels.filter(a => a.nom === 'fn_reserver_copie_bulletin')).toHaveLength(1);
  expect(r.state.appels.filter(a => a.nom === 'copies-bulletins' && a.body.action === 'finaliser')).toHaveLength(1);
  await dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ }).check();
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.copies).toHaveLength(1); expect(r.state.copies[0].sha256).toBe(valide.sha256);
  expect(r.state.intentions.size).toBe(2); expect(r.state.uploads.size).toBe(2);
  expect(r.state.intentions.get(ancienneCle)).toEqual(reservationInitiale);
  expect(r.state.uploads.get(ancienneReservation.storage_path)).toEqual(refuse.buffer);
  await page.reload(); await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  await preuveEtab(page, 'copie-autre-pdf-apres-refus-publie', info);
  expect(e.etat.erreurs).toEqual([]); expect(e.etat.inconnues).toEqual([]); aucunPaiement(r.state.appels);
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

test('aperçu : PDF illisible refusé, réessai explicite et remplacement par un fichier lisible', async ({ page }, info) => {
  await simulerEtablissement(page); const r = recetteCopies();
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const buffer = Buffer.from('%PDF-1.7\nDocument fictif tronqué sans catalogue\n%%EOF');
  const invalide = { name: 'illisible.pdf', mimeType: 'application/pdf', buffer, sha256: createHash('sha256').update(buffer).digest('hex') };
  const dialog = await ouvrirDepot(page, invalide, false, false);
  await expect(dialog.getByRole('alert')).toContainText('L’aperçu du PDF est indisponible');
  await expect(dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ })).toBeDisabled();
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeDisabled();
  await dialog.getByRole('button', { name: 'Réessayer l’aperçu', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('L’aperçu du PDF est indisponible');
  expect(r.state.intentions.size).toBe(0);
  await preuveEtab(page, 'copie-apercu-illisible-publication-interdite', info);
  await dialog.getByRole('button', { name: 'Modifier le dépôt', exact: true }).click();
  await dialog.getByLabel('PDF officiel (10 Mo maximum)', { exact: true }).setInputFiles(r.enregistrerPdf());
  await dialog.getByRole('button', { name: 'Aperçu et confirmation', exact: true }).click();
  await expect(dialog.getByTestId('apercu-pdf-canvas')).toHaveAttribute('data-ready', 'true');
  await expect(dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ })).toBeEnabled();
  await expect(dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ })).not.toBeChecked();
  await dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ }).check();
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.copies).toHaveLength(1); aucunPaiement(r.state.appels);
});

test('aperçu : PDF scanné visible sans OffscreenCanvas, publication après contrôle du destinataire', async ({ page }, info) => {
  const e = await simulerEtablissement(page); const r = recetteCopies();
  await page.addInitScript(() => {
    Object.defineProperty(globalThis, 'OffscreenCanvas', { configurable: true, value: undefined });
    Object.defineProperty(Promise, 'withResolvers', { configurable: true, writable: true, value: undefined });
    Object.defineProperty(ArrayBuffer.prototype, 'transferToFixedLength', { configurable: true, writable: true, value: undefined });
    Object.defineProperty(globalThis, 'structuredClone', { configurable: true, writable: true, value: undefined });
    Object.defineProperty(Array.prototype, 'at', { configurable: true, writable: true, value: undefined });
  });
  let workerSansOffscreen = false;
  await page.route('**/pdf.worker.copie-*.js', async route => {
    const response = await route.fetch();
    workerSansOffscreen = true;
    await route.fulfill({ response, body: 'self.OffscreenCanvas = undefined; Promise.withResolvers = undefined; ArrayBuffer.prototype.transferToFixedLength = undefined; self.structuredClone = undefined; Array.prototype.at = undefined;\n' + await response.text() });
  });
  const buffer = readFileSync(new URL('./fixtures/copies-bulletins/scan-fictif.pdf', import.meta.url));
  const pdf = r.enregistrerPdf({ name: 'scan-fictif.pdf', mimeType: 'application/pdf', buffer, sha256: createHash('sha256').update(buffer).digest('hex') });
  await r.installer(page); await entrerEtab(page, 'connexion'); await page.goto('/etablissement/export-paie');
  const dialog = await ouvrirDepot(page, pdf, false, false);
  const canvas = dialog.getByTestId('apercu-pdf-canvas');
  await expect(canvas).toHaveAttribute('data-ready', 'true');
  await expect(dialog.getByTestId('apercu-pdf-pagination')).toHaveText('Page 1 sur 1');
  expect(workerSansOffscreen).toBe(true);
  const sombres = await canvas.evaluate((el: HTMLCanvasElement) => {
    const data = el.getContext('2d')!.getImageData(0, 0, el.width, el.height).data;
    let count = 0; for (let i = 0; i < data.length; i += 4) if (data[i + 3] > 0 && data[i] + data[i + 1] + data[i + 2] < 600) count++;
    return count;
  });
  expect(sombres).toBeGreaterThan(500);
  await expect(dialog.getByRole('button', { name: 'Confirmer la publication', exact: true })).toBeDisabled();
  await preuveEtab(page, 'copie-apercu-scan-sans-offscreen-visible', info);
  await dialog.getByRole('checkbox', { name: /Je confirme le destinataire/ }).check();
  await dialog.getByRole('button', { name: 'Confirmer la publication', exact: true }).click();
  await expect(section(page).getByText('Copie disponible', { exact: true })).toBeVisible();
  expect(r.state.copies).toHaveLength(1); expect(e.etat.inconnues).toEqual([]); aucunPaiement(r.state.appels);
});
