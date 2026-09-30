import { test, expect, type Download } from '@playwright/test';
import { simulerEtablissement, entrer, allerA, preuve, ids, etablissement } from './helpers/recette-complete-etablissement';

async function lireJson(download: Download) {
  expect(download.suggestedFilename()).toMatch(/^mes-donnees-jolene-\d{4}-\d{2}-\d{2}\.json$/);
  expect(await download.failure()).toBeNull();
  const stream = await download.createReadStream();
  expect(stream).toBeTruthy();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

test('établissement : JSON téléchargé de 201 missions et contrats, erreur sans fichier puis reprise après rechargement', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  const donnees = {
    etablissement: { nom: etablissement.nom, type: 'EHPAD', siret: etablissement.siret, finess: null,
      email_contact: etablissement.email_contact, telephone_contact: '0100000000', adresse_rue: etablissement.adresse_rue,
      adresse_code_postal: '75001', adresse_ville: 'Paris', convention_collective: null, cree_le: '2026-01-01T00:00:00Z', modifie_le: '2026-01-01T00:00:00Z' },
    missions: Array.from({ length: 201 }, (_, i) => ({ id: `99022001-0000-4000-8000-${String(201 - i).padStart(12, '0')}`,
      intitule: `Mission export ${201 - i}`, statut: 'OUVERTE', debut_le: '2046-01-01T08:00:00Z', fin_le: '2046-01-01T16:00:00Z',
      taux_horaire_base: 20, total_brut: 160, cree_le: '2026-01-01T00:00:00Z' })),
    contrats: Array.from({ length: 201 }, (_, i) => ({ type_contrat: 'CDD', statut: 'BROUILLON', cree_le: '2026-01-01T00:00:00Z',
      modifie_le: new Date(Date.UTC(2026, 0, 1, 0, 0, 201 - i)).toISOString() })),
    factures: [], export_date: '2026-09-30T08:00:00Z',
  };
  let mode: 'succes' | 'refus' | 'panne' = 'succes';
  let requetesExport = 0, auditsExport = 0, telechargements = 0;
  page.on('download', () => { telechargements++; });
  await page.route('**/rest/v1/rpc/*', async route => {
    const req = route.request(), nom = new URL(req.url()).pathname.split('/').pop();
    if (nom === 'fn_exporter_rgpd_etablissement') {
      expect(req.method()).toBe('POST'); expect(req.postDataJSON()).toEqual({});
      requetesExport++;
      if (mode === 'refus') return route.fulfill({ json: { error: 'Accès refusé' } });
      if (mode === 'panne') return route.fulfill({ status: 503, json: { message: 'Export temporairement indisponible. Réessayez.' } });
      return route.fulfill({ json: donnees });
    }
    if (nom === 'fn_ecrire_audit_safe' && req.postDataJSON().p_action === 'RGPD_EXPORT_DONNEES') {
      expect(req.postDataJSON().p_acteur_id).toBe(ids.user); auditsExport++;
      return route.fulfill({ json: null });
    }
    return route.fallback();
  });
  await entrer(page, 'connexion');
  await allerA(page, '/etablissement/parametres?tab=securite');
  const bouton = page.getByRole('button', { name: /Télécharger mes données \(RGPD\)/ });
  await expect(page.getByRole('tab', { name: 'Sécurité & RGPD', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(bouton).toBeEnabled();
  await preuve(page, 'export-etablissement-avant', info);
  async function exporter() {
    const attente = page.waitForEvent('download'); await bouton.click();
    const contenu = await lireJson(await attente);
    expect(contenu).toEqual(donnees);
    expect(contenu.missions).toHaveLength(201); expect(contenu.contrats).toHaveLength(201);
    expect(contenu.missions[200].intitule).toBe('Mission export 1');
    await expect(page.getByText('Données exportées.', { exact: true }).last()).toBeVisible();
    await expect(bouton).toBeEnabled();
    await info.attach('export-201-elements-verifie', { body: JSON.stringify(contenu), contentType: 'application/json' });
  }
  await exporter();
  expect(telechargements).toBe(1); expect(auditsExport).toBe(1);
  for (const panne of ['refus', 'panne'] as const) {
    mode = panne; await bouton.click();
    const message = panne === 'refus' ? 'Accès refusé' : 'Une erreur est survenue. Veuillez réessayer.';
    const alerte = page.getByRole('alert').filter({ hasText: message });
    await expect(alerte).toBeVisible();
    await info.attach(`message-export-${panne}`, { body: await alerte.ariaSnapshot(), contentType: 'text/plain' });
    await expect(bouton).toBeEnabled();
    expect(telechargements).toBe(1); expect(auditsExport).toBe(1);
    await preuve(page, `export-etablissement-${panne}`, info);
  }
  mode = 'succes'; await exporter();
  await allerA(page, '/etablissement/parametres?tab=securite');
  await exporter();
  expect(requetesExport).toBe(5); expect(telechargements).toBe(3); expect(auditsExport).toBe(3);
  await preuve(page, 'export-etablissement-reprise-rechargement', info);
  await page.screenshot({ path: info.outputPath('export-etablissement-reprise.png'), fullPage: true, animations: 'disabled' });
  expect(etat.erreurs).toEqual([]); expect(etat.inconnues).toEqual([]);
});
