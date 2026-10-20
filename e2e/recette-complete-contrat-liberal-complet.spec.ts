import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import { creerMissionSimulee, ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';
import { rendreContratLiberal } from '../supabase/functions/_shared/contrat-liberal';

// Vrai helper de rendu et master v3 ; profils, API, Storage et signatures sont
// simulés. Ces tests ne constituent ni une signature ni une validation juridique.
// Six scénarios × cinq formats de playwright.recette-complete.config.ts.
const master = readFileSync(new URL('../tests/admin/security/fixtures/contrat-liberal-master-v3.html', import.meta.url), 'utf8');
const titre = 'CONTRAT DE REMPLACEMENT EN EXERCICE LIBÉRAL';
const boutonSms = 'Recevoir le code SMS pour signer';
const roles: RoleRecette[] = ['SOIGNANT', 'ADMIN_ETABLISSEMENT'];
type Mode = 'TAUX_HORAIRE' | 'RETROCESSION';
const modes: Mode[] = ['TAUX_HORAIRE', 'RETROCESSION'];
const echapper = (value: unknown) => String(value ?? '').replace(/&/g, '&amp;')
  .replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

async function banc(context: BrowserContext, page: Page, role: RoleRecette, mode: Mode, incomplet = false) {
  const { state, installer } = creerMissionSimulee();
  state.contratCree = true;
  Object.assign(state.mission, {
    statut: 'ASSIGNEE', type_contrat_applique: 'LIBERAL', soignant_assigne_id: ids.soignant,
    debut_le: mode === 'TAUX_HORAIRE' ? '2026-01-15T07:00:00Z' : '2026-07-15T07:00:00Z',
    fin_le: mode === 'TAUX_HORAIRE' ? '2026-01-15T15:00:00Z' : '2026-07-15T15:00:00Z',
    duree_heures: 8, taux_horaire_base: mode === 'TAUX_HORAIRE' ? 42.5 : null,
    mode_remuneration: mode, retrocession_pct: 75.5,
    ...(incomplet ? { debut_le: null } : {}),
  });
  Object.assign(state.etablissement, { siret: '22222222222222', adresse_ville: 'Paris' });
  Object.assign(state.contrat, {
    type_contrat: 'REMPLACEMENT_LIBERAL', contenu_html: null, storage_path: null,
    hash_document: null, contenu_html_rendu_le: null,
  });
  const initial = structuredClone(state.contrat);
  let template = master;
  const generations: unknown[] = [], statuts: number[] = [], champsRefuses: string[][] = [];
  const requetesRefusees: string[] = [], requetesEchouees: string[] = [];
  const erreursConsole: { text: string; url: string }[] = [];
  context.on('requestfailed', req => requetesEchouees.push(`${req.method()} ${new URL(req.url()).pathname}: ${req.failure()?.errorText}`));
  page.on('console', msg => { if (msg.type() === 'error') erreursConsole.push({ text: msg.text(), url: msg.location().url }); });
  await installer(context, role);
  await page.clock.setFixedTime(new Date(now));
  await context.route('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap', route =>
    route.request().method() === 'GET' && route.request().resourceType() === 'stylesheet'
      ? route.fulfill({ contentType: 'text/css', body: '' }) : route.fallback());
  const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS' };
  const locale = (url: URL) => ['127.0.0.1', 'localhost'].includes(url.hostname);
  await context.route('**/rest/v1/templates_contrat*', async route => {
    const req = route.request(), url = new URL(req.url());
    if (!locale(url)) {
      requetesRefusees.push('ORIGINE_MODELE');
      return route.fulfill({ status: 501, json: {}, headers });
    }
    if (req.method() === 'OPTIONS') return route.fulfill({ json: {}, headers });
    if (req.method() !== 'GET' || req.headers().authorization !== `Bearer simulation-mission-${role}`
      || url.searchParams.get('select') !== 'contenu_html'
      || url.searchParams.get('type_contrat') !== 'eq.REMPLACEMENT_LIBERAL'
      || url.searchParams.get('est_actif') !== 'eq.true' || [...url.searchParams].length !== 3) {
      requetesRefusees.push(`${req.method()} ${url.pathname} ${url.search}`);
      return route.fulfill({ status: 501, json: {}, headers });
    }
    return route.fulfill({ json: { contenu_html: template }, headers });
  });
  await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
    const req = route.request(), url = new URL(req.url());
    if (!locale(url) || url.search) {
      requetesRefusees.push('ORIGINE_RENDU');
      return route.fulfill({ status: 501, json: {}, headers });
    }
    if (req.method() === 'OPTIONS') return route.fulfill({ json: {}, headers });
    expect(req.method()).toBe('POST');
    expect(req.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
    expect(req.postDataJSON()).toEqual({ contrat_id: ids.contrat });
    generations.push(req.postDataJSON());
    // Aucun rendu fictif ne doit masquer une régénération d'un original.
    expect(state.contrat.storage_path).toBeNull();
    expect(state.contrat.hash_document).toBeNull();
    expect(state.contrat.signature_soignant).toBe(false);
    expect(state.contrat.signature_etablissement).toBe(false);
    const communes = {
      numero_contrat: echapper(state.contrat.numero_contrat),
      etablissement_nom: echapper(state.etablissement.nom),
      etablissement_siret: echapper(state.etablissement.siret),
      etablissement_adresse: echapper([state.etablissement.adresse_rue, state.etablissement.adresse_code_postal, state.etablissement.adresse_ville].join(', ')),
      soignant_prenom: echapper(state.soignant.prenom), soignant_nom: echapper(state.soignant.nom),
      profession: echapper(state.soignant.profession), soignant_rpps: echapper(state.soignant.numero_rpps),
      date_signature: '24/09/2026',
    };
    const rendu = rendreContratLiberal(template, communes, state.mission, state.etablissement);
    if (rendu.html === null) {
      statuts.push(422); champsRefuses.push(rendu.champs);
      return route.fulfill({ status: 422, json: {
        error: 'Les informations du contrat libéral sont incomplètes. Complétez-les avant de signer.',
        code: 'CONTRAT_LIBERAL_DONNEES_REQUISES', champs: rendu.champs,
      }, headers });
    }
    const html = '<!doctype html><html lang="fr"><body>' + rendu.html + '</body></html>';
    Object.assign(state.contrat, {
      contenu_html: html, storage_path: `${ids.contrat}/simulation-liberal-complet.html`,
      hash_document: createHash('sha256').update(html, 'utf8').digest('hex'), contenu_html_rendu_le: now,
    });
    statuts.push(200);
    return route.fulfill({ json: { success: true, contrat_id: ids.contrat,
      storage_path: state.contrat.storage_path, hash_document: state.contrat.hash_document }, headers });
  });
  return {
    state, initial, generations, statuts, champsRefuses,
    changerModele() { template = '<h1>Modèle futur modifié</h1><p>{{inconnue}}</p>'; },
    verifierJournal() {
      expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
      expect(requetesRefusees).toEqual([]); expect(requetesEchouees).toEqual([]);
      expect(state.sms).toEqual([]); expect(state.signatures).toEqual([]); expect(state.emails).toEqual([]);
      expect(state.calls.filter(call => ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp'].includes(call.name))).toEqual([]);
      for (const erreur of erreursConsole) {
        expect(incomplet).toBe(true);
        expect(erreur.text).toMatch(/^Failed to load resource: the server responded with a status of 422(?: \(.*\))?$/);
        const url = new URL(erreur.url);
        expect(locale(url)).toBe(true);
        expect(url.pathname).toBe('/functions/v1/generate-contrat-mission-pdf');
      }
      expect(erreursConsole.length).toBeLessThanOrEqual(statuts.filter(s => s === 422).length);
    },
    journal: () => ({ simulationSeulement: true, role, mode, generations, statuts, champsRefuses,
      requetesRefusees, requetesEchouees, erreursConsole, calls: state.calls, unknown: state.unknown,
      external: state.external, errors: state.errors, aucunBackendNiStorageReel: true, aucunSmsNiPaiement: true }),
  };
}

async function verifierRendu(page: Page, mode: Mode) {
  const document = page.locator('.contrat-print');
  await expect(document.getByRole('heading', { name: titre, exact: true })).toBeVisible();
  await expect(page.getByText(/Document officiel figé le/)).toBeVisible();
  await expect(document).toContainText(mode === 'TAUX_HORAIRE'
    ? 'du 15/01/2026 à 08:00 au 15/01/2026 à 16:00 (8 heures)'
    : 'du 15/07/2026 à 09:00 au 15/07/2026 à 17:00 (8 heures)');
  await expect(document).toContainText(mode === 'TAUX_HORAIRE'
    ? 'Mode de rémunération : Taux horaire' : 'Mode de rémunération : Rétrocession d’honoraires');
  await expect(document).toContainText(mode === 'TAUX_HORAIRE' ? '42.50 € par heure' : '75.5 %');
  await expect(document).not.toContainText(mode === 'TAUX_HORAIRE' ? 'Si rétrocession' : 'Si taux horaire');
  await expect(document).not.toContainText(mode === 'TAUX_HORAIRE' ? '75.5 %' : '€ par heure');
  await expect(document).toContainText('Fait à Paris, le 24/09/2026');
  await expect(document).toContainText('Camille Recette');
  await expect(document).toContainText('Clinique Simulation');
  await expect(document).not.toContainText('{{');
}

for (const role of roles) {
  for (const mode of modes) {
    test(`LIBÉRAL COMPLET — ${role} / ${mode} : original complet, reprise et conservation après signature simulée`, async ({ context, page }, info) => {
      const b = await banc(context, page, role, mode);
      try {
        await page.goto(`/contrat/${ids.contrat}`);
        for (const phase of ['initial', 'recharge']) {
          if (phase === 'recharge') await page.reload();
          await verifierRendu(page, mode);
          await expect(page.getByRole('alert')).toHaveCount(0);
          await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
          await expect(page.getByRole('button', { name: boutonSms, exact: true })).toBeEnabled();
          await info.attach(`${phase}-signature-prete-simulee`, { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
        }
        expect(b.generations).toHaveLength(1); expect(b.statuts).toEqual([200]);
        const original = structuredClone(b.state.contrat);
        // Les données actuelles deviennent impropres à un nouveau rendu. L'UI
        // doit continuer de lire les octets de l'original déjà enregistré.
        Object.assign(b.state.soignant, { prenom: 'Profil changé', numero_rpps: '' });
        Object.assign(b.state.etablissement, { nom: 'Structure changée', adresse_ville: '' });
        Object.assign(b.state.mission, { debut_le: null, taux_horaire_base: null, retrocession_pct: null });
        b.changerModele();
        await page.reload(); await verifierRendu(page, mode);
        expect(b.state.contrat).toEqual(original); expect(b.generations).toHaveLength(1);
        await expect(page.locator('.contrat-print')).not.toContainText('Profil changé');
        await expect(page.locator('.contrat-print')).not.toContainText('Structure changée');
        await expect(page.locator('.contrat-print')).not.toContainText('Modèle futur modifié');
        // État de signature simulé explicitement, sans appeler les transports.
        Object.assign(b.state.contrat, { statut: 'SIGNE_COMPLET', signature_soignant: true,
          signature_etablissement: true, signature_soignant_le: now, signature_etablissement_le: now });
        const signe = structuredClone(b.state.contrat);
        await page.reload(); await verifierRendu(page, mode);
        await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: boutonSms, exact: true })).toHaveCount(0);
        expect(b.state.contrat).toEqual(signe); expect(b.generations).toHaveLength(1);
        expect(b.state.contrat.contenu_html).toBe(original.contenu_html);
        expect(b.state.contrat.hash_document).toBe(original.hash_document);
        expect(b.state.contrat.storage_path).toBe(original.storage_path);
        const downloadPromise = page.waitForEvent('download');
        await page.getByRole('button', { name: 'Télécharger le contrat', exact: true }).click();
        const download = await downloadPromise;
        expect(download.suggestedFilename()).toBe('SIM-2026-0001.html');
        const stream = await download.createReadStream(), chunks: Buffer[] = [];
        for await (const chunk of stream!) chunks.push(chunk);
        const fichier = Buffer.concat(chunks).toString('utf8');
        expect(fichier).toContain('Mode de rémunération');
        expect(fichier).toContain(mode === 'TAUX_HORAIRE' ? '42.50' : '75.5');
        expect(fichier).not.toMatch(/Profil changé|Structure changée|Modèle futur modifié|\{\{/);
        b.verifierJournal();
        await preuveMission(page, info, `${role}-${mode}-original-preserve`);
      } finally {
        await info.attach('liberal-journal-simule', { body: JSON.stringify(b.journal()), contentType: 'application/json' });
      }
    });
  }

  test(`LIBÉRAL INCOMPLET — ${role} : réponse 422, erreur visible et signature bloquée après rechargement`, async ({ context, page }, info) => {
    const b = await banc(context, page, role, 'TAUX_HORAIRE', true);
    try {
      for (let passage = 0; passage < 2; passage++) {
        const reponsePromise = page.waitForResponse(response =>
          response.request().method() === 'POST'
          && new URL(response.url()).pathname === '/functions/v1/generate-contrat-mission-pdf');
        if (passage) await page.reload();
        else await page.goto(`/contrat/${ids.contrat}`);
        const reponse = await reponsePromise;
        expect(reponse.status()).toBe(422);
        expect(await reponse.finished()).toBeNull();
        await expect(page.getByRole('alert')).toContainText('Le document contractuel final n’a pas pu être préparé.');
        await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
        await expect(page.getByRole('button', { name: boutonSms, exact: true })).toBeDisabled();
        await expect(page.getByText(/Document officiel figé le/)).toHaveCount(0);
        expect(b.state.contrat).toEqual(b.initial);
        expect(b.generations).toHaveLength(passage + 1);
        expect(b.statuts).toEqual(Array(passage + 1).fill(422));
        expect(b.champsRefuses).toEqual(Array.from({ length: passage + 1 }, () => ['debut_le']));
      }
      b.verifierJournal();
      await preuveMission(page, info, `${role}-422-sans-original-ni-signature`);
    } finally {
      await info.attach('liberal-refus-journal-simule', { body: JSON.stringify(b.journal()), contentType: 'application/json' });
    }
  });
}
