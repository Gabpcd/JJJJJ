import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Simulation fermée : documents et déclaration admin fictifs, aucun virement, Stripe, SQL ou envoi réel.
test('admin — notification de remboursement manuel, onglet Avoirs, pièces, déclaration, panne et rechargement', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('fn_admin_incoherences_identite', []);
  etat.overrides.set('documents_soignants', []);
  await page.route('**/rest/v1/stripe_refunds_queue?*', async route => {
    expect(route.request().method()).toBe('GET');
    expect(new URL(route.request().url()).searchParams.get('statut')).toBe('in.(EN_ATTENTE,EN_COURS)');
    await route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*',
      'access-control-expose-headers': 'content-range', 'content-range': '*/0' } });
  });
  etat.overrides.set('soignants', [{ id: ids.soignant, prenom: 'Camille', nom: 'Recette' }]);
  etat.overrides.set('etablissements', [{ id: ids.etab, nom: 'Établissement de recette' }]);
  const avoir = { id: ids.facture, numero_facture: 'AV-RECETTE-001', type_document: 'AVOIR', statut: 'EMISE',
    mode_remboursement: 'VIREMENT_MANUEL', montant_ht: 60, montant_tva: 12, montant_ttc: 72,
    date_emission: '2026-10-01T10:00:00Z', date_remboursement: null as string | null, reference_remboursement: null as string | null,
    soignant_id: ids.soignant, etablissement_id: ids.etab, litige_id: null,
    facture_precedente_id: '79000000-0000-4000-8000-000000000092' };
  etat.overrides.set('factures_honoraires', [avoir]);
  // Les octets sont volontairement synthétiques : on prouve leur restitution,
  // pas la validité comptable d'un PDF ni l'existence d'une preuve bancaire.
  const documents = [
    { id: avoir.id, numero_facture: avoir.numero_facture, pdf_s3_key: 'recette/avoir.pdf', bytes: Buffer.from('%PDF-1.4\n% AVOIR SYNTHETIQUE AV-RECETTE-001 72 EUR\n%%EOF\n') },
    { id: avoir.facture_precedente_id, numero_facture: 'F-ORIGINE-RECETTE-001', pdf_s3_key: 'recette/origine.pdf', bytes: Buffer.from('%PDF-1.4\n% FACTURE SYNTHETIQUE F-ORIGINE-RECETTE-001\n%%EOF\n') },
  ];
  const lecturesDocuments: string[] = [];
  await page.route('**/rest/v1/factures_honoraires?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    expect(req.method()).toBe('GET');
    if (!url.searchParams.has('id')) return route.fallback();
    expect(url.searchParams.get('select')).toBe('numero_facture,pdf_s3_key');
    const document = documents.find(d => `eq.${d.id}` === url.searchParams.get('id'));
    expect(document).toBeTruthy();
    lecturesDocuments.push(`document:${document!.id}`);
    return route.fulfill({ json: { numero_facture: document!.numero_facture, pdf_s3_key: document!.pdf_s3_key }, headers: { 'access-control-allow-origin': '*' } });
  });
  await page.route('**/storage/v1/object/sign/jolene-documents/**', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(['127.0.0.1', 'localhost']).toContain(url.hostname);
    const key = decodeURIComponent(url.pathname.slice('/storage/v1/object/sign/jolene-documents/'.length));
    const document = documents.find(d => d.pdf_s3_key === key);
    expect(document).toBeTruthy();
    if (req.method() === 'POST') {
      expect(url.search).toBe('');
      expect(req.postDataJSON()).toEqual({ expiresIn: 300 });
      lecturesDocuments.push(`signature:${document!.id}`);
      return route.fulfill({ json: { signedURL: `/object/sign/jolene-documents/${key}?token=synthetique` }, headers: { 'access-control-allow-origin': '*' } });
    }
    expect(req.method()).toBe('GET'); expect(url.search).toBe('?token=synthetique');
    lecturesDocuments.push(`octets:${document!.id}`);
    return route.fulfill({ contentType: 'application/pdf', body: document!.bytes, headers: { 'access-control-allow-origin': '*' } });
  });
  const declarations: unknown[] = [];
  await page.route('**/rest/v1/rpc/fn_confirmer_remboursement_avoir', async route => {
    const req = route.request();
    expect(['127.0.0.1', 'localhost']).toContain(new URL(req.url()).hostname);
    expect(req.method()).toBe('POST');
    const args = req.postDataJSON();
    expect(args).toEqual({ p_avoir_id: avoir.id, p_reference_virement: 'VIR-SYNTHETIQUE-RECETTE-001' });
    expect(declarations).toHaveLength(0); declarations.push(args);
    avoir.statut = 'REMBOURSE'; avoir.date_remboursement = '2026-10-04T16:00:00Z';
    avoir.reference_remboursement = args.p_reference_virement;
    return route.fulfill({ json: { ok: true }, headers: { 'access-control-allow-origin': '*' } });
  });
  const notification = { id: '79000000-0000-4000-8000-000000000091', destinataire_id: ids.user,
    titre: '💸 Remboursement manuel à traiter', corps: 'Avoir AV-RECETTE-001 — 72,00 €. Remboursement manuel à traiter et à confirmer après vérification de la preuve bancaire.',
    type: 'REMBOURSEMENT_MANUEL_A_FAIRE', lien: '/admin/moderation?onglet=avoirs',
    lue: false, cree_le: '2026-10-01T10:00:00Z' };
  let marquages = 0;
  await page.route('**/rest/v1/notifications?*', async route => {
    const req = route.request(), url = new URL(req.url());
    expect(url.searchParams.get('destinataire_id')).toBe(`eq.${ids.user}`);
    if (req.method() === 'PATCH') {
      expect(url.searchParams.get('id')).toBe(`in.(${notification.id})`);
      expect(req.postDataJSON()).toMatchObject({ lue: true });
      marquages++; notification.lue = true;
      return route.fulfill({ status: 204 });
    }
    expect(['GET', 'HEAD']).toContain(req.method());
    return route.fulfill({ json: req.method() === 'GET' ? [notification] : undefined, body: req.method() === 'HEAD' ? '' : undefined,
      headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': notification.lue ? '*/0' : '0-0/1' } });
  });
  await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
    user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-10-01T10:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
    access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
    expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  })), { id: ids.user });

  await page.goto('/admin/moderation?onglet=documents&origine=recette');
  await expect(page.getByRole('tab', { name: /^Documents/ })).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('button', { name: /^Notifications/ }).first().click();
  await expect(page.getByText(notification.corps, { exact: true })).toBeVisible();
  etat.pannes.add('factures_honoraires');
  await page.getByText(notification.titre, { exact: true }).click();
  await expect(page).toHaveURL(/\/admin\/moderation\?onglet=avoirs$/);
  await expect(page.getByRole('tab', { name: 'Avoirs', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByTestId('avoirs-list')).toContainText('Avoirs indisponibles');
  await expect(page.getByText('Aucun avoir à rembourser', { exact: true })).toHaveCount(0);
  await preuve(page, 'notification-avoir-erreur', info);
  etat.pannes.delete('factures_honoraires');
  await page.getByTestId('avoirs-list').getByRole('button', { name: 'Réessayer', exact: true }).click();
  const ligne = page.locator(`[data-avoir-id="${ids.facture}"]`);
  await expect(ligne).toContainText('AV-RECETTE-001');
  await expect(ligne).toContainText('Camille Recette');
  await expect(ligne).toContainText('Établissement de recette');
  await expect(ligne).toContainText('Virement manuel requis');
  await expect(ligne).toContainText('Émis — en attente remboursement');
  for (const valeur of ['AV-RECETTE-001', '60,00 €', '12,00 €', '72,00 €']) {
    const cellule = ligne.getByRole('cell', { name: valeur, exact: true });
    await expect(cellule).toBeVisible();
    expect(await cellule.evaluate(element => {
      const range = document.createRange();
      range.selectNodeContents(element);
      return new Set([...range.getClientRects()].map(rect => Math.round(rect.top))).size;
    }), `${valeur} doit rester sur une ligne`).toBe(1);
  }
  await expect.poll(() => marquages).toBe(1);
  await preuve(page, 'notification-avoir-reprise', info);
  await page.screenshot({ path: info.outputPath('avoir-lisible.png'), fullPage: true, animations: 'disabled' });
  await ligne.getByRole('button', { name: 'Confirmer remboursement avoir AV-RECETTE-001', exact: true }).click();
  const dialogue = page.getByRole('dialog');
  await expect(dialogue.getByRole('heading', { name: 'Confirmer le remboursement manuel' })).toBeVisible();
  await dialogue.getByRole('heading', { name: 'Confirmer le remboursement manuel' }).scrollIntoViewIfNeeded();
  await expect(dialogue.getByRole('heading', { name: 'Confirmer le remboursement manuel' })).toBeInViewport();
  expect(await dialogue.evaluate(element => element.scrollWidth <= element.clientWidth + 1)).toBe(true);
  await dialogue.screenshot({ path: info.outputPath('avoir-dialogue-haut.png'), animations: 'disabled' });
  await expect(dialogue.getByRole('button', { name: 'Confirmer 72,00 € TTC', exact: true })).toBeDisabled();
  await expect(dialogue.getByText('Camille Recette', { exact: true })).toBeVisible();
  await expect(dialogue.getByText('Établissement de recette', { exact: true })).toBeVisible();
  await expect(dialogue.getByText(/ne désignent pas à elles seules le bénéficiaire bancaire/)).toBeVisible();
  await expect(dialogue.getByText(/Jolene ne vérifie pas automatiquement le virement/)).toBeVisible();
  await expect(dialogue.getByText(/au bénéficiaire indiqué/)).toHaveCount(0);
  for (const [index, label] of ['Consulter l’avoir', 'Consulter la facture d’origine'].entries()) {
    const pending = page.waitForEvent('download');
    await dialogue.getByRole('button', { name: label, exact: true }).click();
    const download = await pending;
    expect(download.suggestedFilename()).toBe(`${documents[index].numero_facture}.pdf`);
    expect(await download.failure()).toBeNull();
    const stream = await download.createReadStream(); expect(stream).toBeTruthy();
    const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
    expect(Buffer.concat(chunks).equals(documents[index].bytes)).toBe(true);
    await download.delete();
  }
  expect(lecturesDocuments).toEqual(documents.flatMap(d => [`document:${d.id}`, `signature:${d.id}`, `octets:${d.id}`]));
  await expect(dialogue.getByRole('checkbox')).not.toBeChecked();
  await expect(dialogue.getByRole('button', { name: 'Confirmer 72,00 € TTC', exact: true })).toBeDisabled();
  await dialogue.screenshot({ path: info.outputPath('avoir-parties-et-declaration.png'), animations: 'disabled' });
  await preuve(page, 'confirmation-manuelle-non-validee', info);
  await dialogue.getByRole('button', { name: 'Annuler', exact: true }).click();
  await stabiliserLectures(page);
  await page.reload();
  await expect(page.getByRole('tab', { name: 'Avoirs', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(ligne).toBeVisible();
  await page.getByRole('tab', { name: /^Documents/ }).click();
  await expect(page).toHaveURL(/onglet=documents/);
  await stabiliserLectures(page);
  await page.reload();
  await expect(page.getByRole('tab', { name: /^Documents/ })).toHaveAttribute('aria-selected', 'true');
  await stabiliserLectures(page);
  await page.goto('/admin/moderation?onglet=inconnu&origine=recette');
  await expect(page.getByRole('tab', { name: /^Litiges/ })).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('tab', { name: 'Avoirs', exact: true }).click();
  await expect(page).toHaveURL(/onglet=avoirs&origine=recette$/);
  await expect(ligne).toBeVisible();
  await stabiliserLectures(page);
  await expect(page.getByRole('alert')).toHaveCount(0);
  await preuve(page, 'onglet-avoir-conserve', info);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
  expect(etat.operations).toEqual([]); expect(etat.ecritures).toEqual([]);
  expect(avoir.date_remboursement).toBeNull();
  expect(declarations).toEqual([]);
  // Une déclaration opérateur est simulée seulement après les assertions de lecture seule.
  await ligne.getByRole('button', { name: 'Confirmer remboursement avoir AV-RECETTE-001', exact: true }).click();
  await expect(dialogue.getByRole('textbox', { name: 'Référence virement' })).toHaveValue('');
  await expect(dialogue.getByRole('checkbox')).not.toBeChecked();
  await dialogue.getByRole('textbox', { name: 'Référence virement' }).fill('VIR-SYNTHETIQUE-RECETTE-001');
  await expect(dialogue.getByRole('button', { name: 'Confirmer 72,00 € TTC', exact: true })).toBeDisabled();
  await dialogue.getByRole('checkbox', { name: /Je confirme avoir vérifié les pièces, le bénéficiaire bancaire et la preuve/ }).check();
  await expect(dialogue.getByRole('button', { name: 'Confirmer 72,00 € TTC', exact: true })).toBeEnabled();
  await dialogue.getByRole('button', { name: 'Confirmer 72,00 € TTC', exact: true }).click();
  await expect(dialogue).toHaveCount(0);
  await expect.poll(() => declarations.length).toBe(1);
  await expect(page.getByText('Aucun avoir à rembourser', { exact: true })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByRole('tab', { name: 'Avoirs', exact: true })).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('button', { name: /Historique \(remboursés, annulés, brouillons\)/ }).click();
  await expect(ligne.getByText('Remboursé', { exact: true })).toBeVisible();
  await expect(ligne.getByRole('button', { name: /Confirmer remboursement/ })).toHaveCount(0);
  await preuve(page, 'avoir-declaration-simulee-apres-reload', info);
  expect(declarations).toHaveLength(1);
  expect(avoir.reference_remboursement).toBe('VIR-SYNTHETIQUE-RECETTE-001');
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
  expect(etat.operations).toEqual([]); expect(etat.ecritures).toEqual([]);

  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
});
