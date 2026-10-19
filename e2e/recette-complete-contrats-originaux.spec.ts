import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import { createHash } from 'node:crypto';
import { creerMissionSimulee, ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';
import { rendreCddEmployeur, validerDonneesCdd, type DonneesCdd } from '../supabase/functions/_shared/cdd-employeur';

// Simulation UI stricte : réponses locales uniquement, aucun original personnel ni backend réel.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`CONTRAT ORIGINAL — ${role} : lecture, téléchargement, absence, refus et reprise`, async ({ context, page }, info) => {
    const { state, installer } = creerMissionSimulee();
    state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
    Object.assign(state.contrat, { statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true,
      contenu_html: '<article><h2>Original synthétique signé</h2><p>Texte historique : 10h/jour (L3121-18)</p></article>' });
    const original = { ...state.contrat };
    await installer(context, role); await page.clock.setFixedTime(new Date(now));
    let renduAutorise = false, lectureAutorisee = true;
    const generations: unknown[] = [];
    await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
      if (route.request().method() === 'OPTIONS') return route.fulfill({ json: {}, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
      generations.push(route.request().postDataJSON());
      if (renduAutorise) Object.assign(state.contrat, { storage_path: 'simulation/nouveau-original.html', hash_document: 'b'.repeat(64), contenu_html_rendu_le: now,
        contenu_html: '<article><h2>Nouveau document autorisé</h2><p>Rendu synthétique figé.</p></article>' });
      await route.fulfill({ status: renduAutorise ? 200 : 403, json: renduAutorise ? { success: true } : { error: 'Accès au contrat refusé.' },
        headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    });
    await context.route('**/rest/v1/contrats_mission*', async route => {
      if (lectureAutorisee) return route.fallback();
      return route.fulfill({ status: 403, json: { message: 'Accès refusé' }, headers: { 'access-control-allow-origin': '*' } });
    });
    try {
      await page.goto(`/contrat/${ids.contrat}`);
      await expect(page.getByRole('heading', { name: 'Original synthétique signé', exact: true })).toBeVisible();
      await expect(page.getByText('Texte historique : 10h/jour (L3121-18)', { exact: true })).toBeVisible();
      await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
      const downloadPromise = page.waitForEvent('download');
      await page.getByRole('button', { name: 'Télécharger le contrat', exact: true }).click();
      const download = await downloadPromise; expect(download.suggestedFilename()).toBe('SIM-2026-0001.html');
      const stream = await download.createReadStream(); const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(chunk);
      const bytes = Buffer.concat(chunks).toString('utf8'); expect(bytes).toContain(original.contenu_html);
      expect(bytes).not.toContain('Nouveau document autorisé');
      await page.reload(); await expect(page.getByRole('heading', { name: 'Original synthétique signé', exact: true })).toBeVisible();
      expect(generations).toHaveLength(0); expect(state.contrat).toEqual(original);
      await preuveMission(page, info, role+'-original-apres-reload');
      // Le hash serveur seul manque : le fallback HTML local ne doit pas autoriser un OTP.
      Object.assign(state.contrat, { statut: role === 'SOIGNANT' ? 'SIGNE_ETABLISSEMENT' : 'SIGNE_SOIGNANT',
        signature_soignant: role !== 'SOIGNANT', signature_etablissement: role === 'SOIGNANT', hash_document: null });
      const sansEmpreinteServeur = structuredClone(state.contrat);
      for (let lecture = 0; lecture < 2; lecture++) {
        await page.reload();
        await expect(page.getByRole('heading', { name: 'Original synthétique signé', exact: true })).toBeVisible();
        await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
        await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeDisabled();
        expect(state.contrat).toEqual(sansEmpreinteServeur);
        expect(state.calls.filter(call => ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp'].includes(call.name))).toEqual([]);
        expect(generations).toHaveLength(0);
      }
      await preuveMission(page, info, role+'-hash-serveur-manquant');
      // Une seule partie a signé : même interdiction de reconstitution automatique.
      Object.assign(state.contrat, { statut: role === 'SOIGNANT' ? 'SIGNE_ETABLISSEMENT' : 'SIGNE_SOIGNANT',
        signature_soignant: role !== 'SOIGNANT', signature_etablissement: role === 'SOIGNANT',
        contenu_html: null, storage_path: null, hash_document: null, contenu_html_rendu_le: null });
      await page.reload();
      await expect(page.getByText('Le document signé d’origine est indisponible. Aucune reconstitution automatique n’est effectuée.', { exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Télécharger le contrat', exact: true })).toBeDisabled();
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeDisabled();
      expect(generations).toHaveLength(0);
      await preuveMission(page, info, role+'-original-manquant');
      // Brouillon sans preuve : refus serveur visible, puis reprise après reload.
      Object.assign(state.contrat, { statut: 'EN_ATTENTE_SIGNATURES', signature_soignant: false, signature_etablissement: false });
      await page.reload(); await expect(page.getByRole('alert')).toContainText('Le document contractuel final n’a pas pu être préparé.');
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeDisabled();
      expect(generations).toHaveLength(1); await preuveMission(page, info, role+'-rendu-refuse');
      renduAutorise = true; await page.reload();
      await expect(page.getByRole('heading', { name: 'Nouveau document autorisé', exact: true })).toBeVisible();
      await expect(page.getByRole('alert')).toHaveCount(0);
      await page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ }).check();
      await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toBeEnabled();
      expect(generations).toHaveLength(2); await page.reload();
      await expect(page.getByRole('heading', { name: 'Nouveau document autorisé', exact: true })).toBeVisible();
      expect(generations).toHaveLength(2); await preuveMission(page, info, role+'-reprise-figee');
      // La lecture ordinaire refusée après fermeture/révocation n'affiche plus le contrat.
      lectureAutorisee = false; await page.reload(); await expect(page.getByText('Contrat introuvable', { exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Télécharger le contrat', exact: true })).toHaveCount(0);
      expect(generations).toHaveLength(2); expect(state.signatures).toEqual([]); expect(state.sms).toEqual([]);
      expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    } finally {
      await info.attach('journal-synthetique', { body: JSON.stringify({ generations, calls: state.calls, errors: state.errors, unknown: state.unknown }), contentType: 'application/json' });
    }
  });
}

// Vérification ciblée du formulaire CDD : serveur/Storage et permissions simulés.
// Les helpers purs sont réels ; aucun effet SQL, contrat distant, SMS ou paiement.
const confirmationCdd = /^Je confirme pour l’employeur l’exactitude et la complétude/;
const boutonPreparationCdd = 'Confirmer ces informations et préparer le document';
const donneesPriveesCdd = {
  cadre: 'PRIVE_TERME_PRECIS', confirme: true,
  representant_nom: 'Ariane Employeur fictive', representant_qualite: 'Responsable RH de simulation',
  motif_type: 'REMPLACEMENT', motif_precis: 'Remplacement temporaire synthétique de la personne nommée ci-dessous.',
  remplace_nom: 'Dominique Personne fictive', remplace_qualification: 'Qualification professionnelle synthétique',
  poste: 'Poste de consultation fictif', qualification: 'Qualification du salarié fictif', lieu_travail: '2 rue de la Simulation, Paris',
  risques: 'OUI', risques_precisions: 'Risque particulier synthétique décrit par cet employeur fictif.',
  convention_collective: 'Convention collective de simulation — intitulé déclaré uniquement pour ce banc',
  renouvellement: 'Aucun renouvellement prévu pour cette simulation', essai: 'AUCUN',
  remuneration_accessoires: 'Base brute : 80 EUR par heure. Primes, indemnités et accessoires : détail synthétique confirmé par cet employeur.',
  temps_partiel: 'OUI', temps_partiel_conditions: '8 heures hebdomadaires le jeudi de 9h à 17h ; répartition, modifications, communication et limites des heures complémentaires décrites pour cette simulation uniquement.',
  retraite_nom: 'Caisse complémentaire fictive', retraite_adresse: '3 rue de la Simulation, 75001 Paris',
  prevoyance: 'OUI', prevoyance_nom: 'Organisme de prévoyance fictif', prevoyance_adresse: '4 rue de la Simulation, 75001 Paris',
};
const donneesTexteCdd = {
  cadre: 'TEXTE_EMPLOYEUR', confirme: true,
  representant_nom: 'Ariane Employeur fictive', representant_qualite: 'Responsable de simulation',
  cadre_declare: 'Engagement de droit public fictif : cadre fourni uniquement pour la simulation.',
  texte_employeur: 'CONTRAT INTÉGRAL SYNTHÉTIQUE fourni par l’employeur.\nParties : Clinique Simulation et Camille Recette.\nMission du 24 septembre 2026, de 9h à 17h. Poste et rémunération explicitement déclarés dans ce texte fictif.\nLa mention <texte employeur> est du texte, pas une balise HTML.\nAucune qualification juridique réelle n’est attestée par ce banc.',
};

async function bancPreparationCdd(context: BrowserContext, page: Page, role: RoleRecette,
  options: { permission: boolean; attendu?: Record<string, unknown>; premierRefus503?: boolean }) {
  const { state, installer } = creerMissionSimulee();
  state.contratCree = true;
  Object.assign(state.mission, { statut: 'ASSIGNEE', soignant_assigne_id: ids.soignant,
    type_contrat_applique: 'SALARIE', type_contrat_recherche: 'SALARIE' });
  Object.assign(state.soignant, { type_exercice: 'SALARIE' });
  Object.assign(state.contrat, { type_contrat: 'CDD', contenu_html: '<p>Préparation non rendue : {{motif_cdd}}</p>',
    storage_path: null, hash_document: null, contenu_html_rendu_le: null });
  const initial = structuredClone(state.contrat);
  const generations: unknown[] = [], permissions: unknown[] = [], statuts: number[] = [];
  const requetesEchouees: { method: string; path: string; reason: string | null }[] = [];
  const erreursConsole: { text: string; url: string }[] = [];
  context.on('requestfailed', req => requetesEchouees.push({ method: req.method(), path: new URL(req.url()).pathname,
    reason: req.failure()?.errorText || null }));
  page.on('console', message => { if (message.type() === 'error') erreursConsole.push({ text: message.text(), url: message.location().url }); });
  await installer(context, role);
  await page.clock.setFixedTime(new Date(now));
  // Feuille externe exacte déjà utilisée par le shell : CSS vide explicitement simulé.
  await context.route(url => url.href === 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap', async route => {
    if (route.request().method() !== 'GET' || route.request().resourceType() !== 'stylesheet') return route.fallback();
    return route.fulfill({ contentType: 'text/css', body: '' });
  });
  const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS' };
  const origineLocale = (url: URL) => ['localhost', '127.0.0.1'].includes(url.hostname) && url.search === '';
  await context.route('**/rest/v1/rpc/fn_a_permission_etablissement', async route => {
    const req = route.request(), url = new URL(req.url());
    if (!origineLocale(url)) { state.unknown.push('CDD_PERMISSION_ORIGIN'); return route.fulfill({ status: 501, json: {}, headers }); }
    if (req.method() === 'OPTIONS') return route.fulfill({ json: {}, headers });
    const body = req.postDataJSON();
    expect(req.method()).toBe('POST');
    expect(req.headers().authorization).toBe('Bearer simulation-mission-ADMIN_ETABLISSEMENT');
    expect(body).toEqual({ p_permission: 'contrats', p_etablissement_id: ids.etablissement });
    permissions.push(body);
    return route.fulfill({ json: options.permission, headers });
  });
  await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
    const req = route.request(), url = new URL(req.url());
    if (!origineLocale(url)) { state.unknown.push('CDD_GENERATION_ORIGIN'); return route.fulfill({ status: 501, json: {}, headers }); }
    if (req.method() === 'OPTIONS') return route.fulfill({ json: {}, headers });
    expect(req.method()).toBe('POST');
    expect(role).toBe('ADMIN_ETABLISSEMENT');
    expect(options.permission).toBe(true);
    expect(req.headers().authorization).toBe('Bearer simulation-mission-ADMIN_ETABLISSEMENT');
    const body = req.postDataJSON();
    expect(Object.keys(body).sort()).toEqual(['contrat_id', 'donnees_cdd']);
    expect(body.contrat_id).toBe(ids.contrat);
    expect(body.donnees_cdd).toEqual(options.attendu);
    const validation = validerDonneesCdd(body.donnees_cdd);
    expect(validation.champs).toEqual([]); expect(validation.donnees).not.toBeNull();
    generations.push(body);
    if (options.premierRefus503 && generations.length === 1) {
      statuts.push(503);
      return route.fulfill({ status: 503, json: { error: 'Interruption synthétique avant tout rendu' }, headers });
    }
    const valeurs = { numero_contrat: state.contrat.numero_contrat, etablissement_nom: state.etablissement.nom,
      etablissement_siret: state.etablissement.siret, etablissement_adresse: '2 rue de la Simulation, 75001 Paris',
      soignant_nom: state.soignant.nom, soignant_prenom: state.soignant.prenom, soignant_date_naissance: '15 juin 1985',
      soignant_adresse: '1 rue de la Simulation, 75001 Paris', intitule_mission: state.mission.intitule,
      debut_le: '24 septembre 2026 à 09:00', fin_le: '24 septembre 2026 à 17:00', duree_heures: '8', taux_horaire: '80.00' };
    const html = '<!doctype html><html lang="fr"><body>' + rendreCddEmployeur(valeurs, validation.donnees as DonneesCdd, ids.etablissement, now) + '</body></html>';
    Object.assign(state.contrat, { contenu_html: html, storage_path: `${ids.contrat}/simulation-cdd.html`,
      hash_document: createHash('sha256').update(html, 'utf8').digest('hex'), contenu_html_rendu_le: now });
    statuts.push(200);
    return route.fulfill({ json: { success: true, contrat_id: ids.contrat,
      storage_path: state.contrat.storage_path, hash_document: state.contrat.hash_document }, headers });
  });
  return { state, initial, generations, permissions, statuts, async verifierJournal() {
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]); expect(state.external).toEqual([]);
    expect(requetesEchouees).toEqual([]); expect(state.sms).toEqual([]); expect(state.signatures).toEqual([]); expect(state.emails).toEqual([]);
    // Seul le diagnostic HTTP du503 explicitement provoqué est admissible ; un CORS/pageerror reste rouge.
    for (const erreur of erreursConsole) {
      expect(options.premierRefus503).toBe(true); expect(statuts.filter(s => s === 503)).toHaveLength(1);
      expect(erreur.text).toMatch(/^Failed to load resource: the server responded with a status of 503(?: \(.*\))?$/);
      const url = new URL(erreur.url);
      expect(origineLocale(url)).toBe(true); expect(url.pathname).toBe('/functions/v1/generate-contrat-mission-pdf');
    }
  }, journal: () => ({ simulationSeulement: true, role, generations, permissions, statuts,
    requetesEchouees, erreursConsole, unknown: state.unknown, external: state.external, errors: state.errors,
    aucunBackendNiStorageReel: true, aucunSmsNiPaiement: true }) };
}

// Les champs sont ciblés avec leur libellé visible ; l'aide associée reste dans leur nom accessible.
function champCdd(page: Page, label: string) {
  return page.getByRole('form', { name: 'Préparer le contrat salarié', exact: true }).getByLabel(label);
}

test('CDD PRÉPARATION — employeur : conditions privées obligatoires, essai explicite et reprise', async ({ context, page }, info) => {
  const b = await bancPreparationCdd(context, page, 'ADMIN_ETABLISSEMENT', { permission: true, attendu: donneesPriveesCdd });
  try {
    await page.goto(`/contrat/${ids.contrat}`);
    const form = page.getByRole('form', { name: 'Préparer le contrat salarié', exact: true });
    await expect(form).toBeVisible();
    await expect(form.getByRole('button', { name: boutonPreparationCdd, exact: true })).toBeDisabled();
    await champCdd(page, 'Document à préparer').selectOption('PRIVE_TERME_PRECIS');
    await expect(champCdd(page, 'Cas de recours déclaré')).toHaveValue('');
    await expect(champCdd(page, 'Période d’essai expressément convenue')).toHaveValue('');
    await champCdd(page, 'Cas de recours déclaré').selectOption('REMPLACEMENT');
    await champCdd(page, 'Poste présentant des risques particuliers').selectOption('OUI');
    await champCdd(page, 'Engagement à temps partiel').selectOption('OUI');
    await champCdd(page, 'Prévoyance applicable à cet engagement').selectOption('OUI');
    const textes: [string, string][] = [
      ['Nom du représentant de l’employeur', donneesPriveesCdd.representant_nom],
      ['Qualité du représentant de l’employeur', donneesPriveesCdd.representant_qualite],
      ['Motif précis du CDD', donneesPriveesCdd.motif_precis],
      ['Prénom et nom de la personne remplacée', donneesPriveesCdd.remplace_nom],
      ['Poste de travail', donneesPriveesCdd.poste], ['Qualification du salarié pour ce poste', donneesPriveesCdd.qualification],
      ['Lieu de travail et adresse', donneesPriveesCdd.lieu_travail], ['Risques particuliers du poste', donneesPriveesCdd.risques_precisions],
      ['Renouvellement éventuel', donneesPriveesCdd.renouvellement], ['Conditions du temps partiel', donneesPriveesCdd.temps_partiel_conditions],
      ['Intitulé exact de la convention collective applicable', donneesPriveesCdd.convention_collective],
      ['Rémunération, primes, indemnités et accessoires', donneesPriveesCdd.remuneration_accessoires],
      ['Nom de la caisse de retraite complémentaire', donneesPriveesCdd.retraite_nom],
      ['Adresse de la caisse de retraite complémentaire', donneesPriveesCdd.retraite_adresse],
      ['Nom de l’organisme de prévoyance', donneesPriveesCdd.prevoyance_nom],
      ['Adresse de l’organisme de prévoyance', donneesPriveesCdd.prevoyance_adresse],
    ];
    for (const [label, valeur] of textes) await champCdd(page, label).fill(valeur);
    const accord = form.getByRole('checkbox', { name: confirmationCdd });
    await expect(accord).not.toBeChecked();
    await accord.check();
    await form.getByRole('button', { name: boutonPreparationCdd, exact: true }).click();
    expect(await champCdd(page, 'Qualification professionnelle de la personne remplacée').evaluate(e => (e as HTMLTextAreaElement).validity.valueMissing)).toBe(true);
    expect(b.generations).toEqual([]); expect(b.state.contrat).toEqual(b.initial);
    await champCdd(page, 'Qualification professionnelle de la personne remplacée').fill(donneesPriveesCdd.remplace_qualification);
    await expect(accord).not.toBeChecked();
    await accord.check(); await form.getByRole('button', { name: boutonPreparationCdd, exact: true }).click();
    expect(await champCdd(page, 'Période d’essai expressément convenue').evaluate(e => (e as HTMLSelectElement).validity.valueMissing)).toBe(true);
    expect(b.generations).toEqual([]);
    await champCdd(page, 'Période d’essai expressément convenue').selectOption('AUCUN');
    await expect(champCdd(page, 'Durée exacte de l’essai et unité')).toHaveCount(0);
    await expect(accord).not.toBeChecked(); await accord.check();
    await form.getByRole('button', { name: boutonPreparationCdd, exact: true }).click();
    await expect(form).toHaveCount(0);
    await expect(page.getByText('DPAE obligatoire — Mission salariée', { exact: true })).toBeVisible();
    const document = page.locator('.contrat-print');
    await expect(document).toContainText('Aucune période d’essai n’est convenue.');
    for (const texte of [donneesPriveesCdd.motif_precis, donneesPriveesCdd.remplace_nom, donneesPriveesCdd.remplace_qualification,
      donneesPriveesCdd.convention_collective, donneesPriveesCdd.remuneration_accessoires,
      donneesPriveesCdd.retraite_adresse, donneesPriveesCdd.prevoyance_adresse]) await expect(document).toContainText(texte);
    await expect(document).not.toContainText('remplacement / surcroît'); await expect(document).not.toContainText('1 jour');
    expect(b.generations).toEqual([{ contrat_id: ids.contrat, donnees_cdd: donneesPriveesCdd }]);
    const original = structuredClone(b.state.contrat);
    await page.reload(); await expect(document).toContainText(donneesPriveesCdd.remplace_nom);
    await expect(form).toHaveCount(0); expect(b.state.contrat).toEqual(original); expect(b.generations).toHaveLength(1);
    await expect(page.getByText('DPAE obligatoire — Mission salariée', { exact: true })).toBeVisible();
    await b.verifierJournal(); await preuveMission(page, info, 'CDD-prive-confirme-original-recharge');
  } finally { await info.attach('CDD-prive-journal-simule', { body: JSON.stringify(b.journal()), contentType: 'application/json' }); }
});

test('CDD PRÉPARATION — employeur : texte intégral, erreur503 sans effet puis reprise explicite', async ({ context, page }, info) => {
  const b = await bancPreparationCdd(context, page, 'ADMIN_ETABLISSEMENT', { permission: true, attendu: donneesTexteCdd, premierRefus503: true });
  let signatureEtablissementSimulee = false;
  const verifierCadreDeclare = async () => {
    await expect(page.getByText('DPAE — formalité à vérifier selon le cadre déclaré', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Préparer les données DPAE', exact: true })).toBeVisible();
    await expect(page.getByText(/^Contrat salarié préparé selon le cadre déclaré par l’employeur\./)).toBeVisible();
    await expect(page.getByText(/^Contrat salarié écrit — art\. L\.1242-12/)).toHaveCount(0);
  };
  try {
    await page.goto(`/contrat/${ids.contrat}`);
    const form = page.getByRole('form', { name: 'Préparer le contrat salarié', exact: true });
    await expect(form).toBeVisible();
    await champCdd(page, 'Document à préparer').selectOption('TEXTE_EMPLOYEUR');
    await expect(champCdd(page, 'Cas de recours déclaré')).toHaveCount(0);
    await champCdd(page, 'Nom du représentant de l’employeur').fill(donneesTexteCdd.representant_nom);
    await champCdd(page, 'Qualité du représentant de l’employeur').fill(donneesTexteCdd.representant_qualite);
    await champCdd(page, 'Cadre juridique déclaré par l’employeur').fill(donneesTexteCdd.cadre_declare);
    await champCdd(page, 'Texte intégral du contrat fourni par l’employeur').fill(donneesTexteCdd.texte_employeur);
    const bouton = form.getByRole('button', { name: boutonPreparationCdd, exact: true });
    await expect(bouton).toBeDisabled(); await form.getByRole('checkbox', { name: confirmationCdd }).check();
    await bouton.click();
    await expect(form.getByRole('alert')).toHaveText('Le document n’a pas été confirmé. Vos informations restent dans cette page. Réessayez après avoir vérifié le contrat.');
    await expect(champCdd(page, 'Texte intégral du contrat fourni par l’employeur')).toHaveValue(donneesTexteCdd.texte_employeur);
    expect(b.statuts).toEqual([503]); expect(b.generations).toHaveLength(1); expect(b.state.contrat).toEqual(b.initial);
    await preuveMission(page, info, 'CDD-texte-employeur-refus503-sans-rendu');
    await expect(bouton).toBeEnabled(); await bouton.click();
    const document = page.locator('.contrat-print');
    await expect(form).toHaveCount(0);
    await expect(document).toContainText(donneesTexteCdd.texte_employeur, { useInnerText: true });
    await expect(document.locator('texte')).toHaveCount(0);
    await expect(document).not.toContainText('Contrat de droit privé à terme précis');
    await expect(document).not.toContainText('Aucune période d’essai n’est convenue.');
    await verifierCadreDeclare();
    expect(b.statuts).toEqual([503, 200]); expect(b.generations).toEqual([
      { contrat_id: ids.contrat, donnees_cdd: donneesTexteCdd }, { contrat_id: ids.contrat, donnees_cdd: donneesTexteCdd },
    ]);
    const original = structuredClone(b.state.contrat);
    await page.reload(); await expect(document).toContainText(donneesTexteCdd.texte_employeur, { useInnerText: true });
    await expect(document.locator('texte')).toHaveCount(0);
    await expect(form).toHaveCount(0); expect(b.state.contrat).toEqual(original); expect(b.generations).toHaveLength(2);
    await verifierCadreDeclare();
    await b.verifierJournal(); await preuveMission(page, info, 'CDD-texte-employeur-original-recharge');
    // État serveur de signature explicitement simulé : aucun geste CANVAS/OTP ni RPC de signature.
    Object.assign(b.state.contrat, { signature_etablissement: true, signature_etablissement_le: now, statut: 'SIGNE_ETABLISSEMENT' });
    signatureEtablissementSimulee = true;
    const signeSimule = structuredClone(b.state.contrat);
    await page.reload();
    await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
    await expect(page.getByText('Formalités employeur : vérifiez les démarches applicables au cadre déclaré pour cet engagement.', { exact: true })).toBeVisible();
    await expect(page.getByText(/^⚠️ Rappel légal : effectuez la Déclaration Préalable/)).toHaveCount(0);
    await verifierCadreDeclare();
    await expect(document).toContainText(donneesTexteCdd.texte_employeur, { useInnerText: true });
    expect(b.state.contrat).toEqual(signeSimule);
    expect(b.state.contrat.hash_document).toBe(original.hash_document);
    expect(b.state.contrat.contenu_html).toBe(original.contenu_html);
    expect(b.state.contrat.storage_path).toBe(original.storage_path);
    expect(b.generations).toHaveLength(2);
    await b.verifierJournal(); await preuveMission(page, info, 'CDD-texte-employeur-rappel-apres-signature-simulee');
  } finally { await info.attach('CDD-texte-employeur-journal-simule', { body: JSON.stringify({ ...b.journal(), signatureEtablissementSimulee }), contentType: 'application/json' }); }
});

test('CDD PRÉPARATION — soignant et membre sans permission : aucune autogénération ni signature', async ({ browser }, info) => {
  for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
    const context = await browser.newContext({ ...info.project.use });
    const page = await context.newPage();
    const b = await bancPreparationCdd(context, page, role, { permission: false });
    try {
      await page.goto(`/contrat/${ids.contrat}`);
      for (let lecture = 0; lecture < 2; lecture++) {
        await expect(page.getByRole('status').filter({ hasText: 'Le contrat doit être préparé et confirmé par un représentant autorisé de l’employeur avant les signatures.' })).toBeVisible();
        await expect(page.getByRole('form', { name: 'Préparer le contrat salarié', exact: true })).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Télécharger le contrat', exact: true })).toBeDisabled();
        await expect(page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true })).toHaveCount(0);
        await expect(page.getByRole('button', { name: /Signer définitivement/ })).toHaveCount(0);
        expect(b.generations).toEqual([]); expect(b.state.contrat).toEqual(b.initial);
        if (lecture === 0) await page.reload();
      }
      expect(b.permissions).toHaveLength(role === 'SOIGNANT' ? 0 : 2);
      await b.verifierJournal(); await preuveMission(page, info, 'CDD-non-preparateur-'+role);
    } finally {
      await info.attach('CDD-non-preparateur-'+role+'-journal-simule', { body: JSON.stringify(b.journal()), contentType: 'application/json' });
      await context.close();
    }
  }
});
