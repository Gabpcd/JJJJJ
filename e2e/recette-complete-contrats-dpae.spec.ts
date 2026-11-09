import { test, expect, type BrowserContext, type Locator, type Page, type TestInfo } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import { creerMissionSimulee, ids, now, preuveMission } from './helpers/recette-complete-mission';

// DPAE de /contrat/:id selon le type de contrat : CDDU et VACATION sont des contrats
// salariés (DPAE obligatoire, C. trav. art. L.1221-10 ; CDD d'usage = CDD, art. L.1242-2 3°
// et D.1242-1), le remplacement libéral n'en a pas. Décision prise par Claude sur délégation
// explicite de Gabrielle du 08/11/2026. Compte à rebours : « sous 72h », jamais « sous72h ».
// Simulation UI stricte : Auth, contrat et RPC DPAE sont fictifs (helper recette-complete-mission) ;
// aucun backend, URSSAF, signature, SMS ni e-mail réel. Les états « signé par l'établissement »
// sont des états serveur explicitement simulés, sans geste de signature.
const BLOC_DPAE = 'DPAE obligatoire — Mission salariée';
const BOUTON_PREPARER = 'Préparer les données DPAE';
const RAPPEL_DPAE = "⚠️ Rappel légal : effectuez la Déclaration Préalable à l'Embauche (DPAE) sur net-entreprises.fr avant le début de la mission.";
const RAPPEL_DPAE_SUITE = "La DPAE est obligatoire pour ce contrat salarié. Pour une mission libérale directe, elle n'est pas requise.";
const RAPPEL_DPAE_FAITE = "✅ DPAE déclarée comme effectuée par l'établissement le 24 septembre 2026";
const COMPTE_A_REBOURS = 'Signature à finaliser sous 72h 00m 00s';
const DEJA_SIGNE = '✅ Vous avez déjà signé ce contrat';
const MENTION_SALARIEE = 'Contrat salarié écrit — art. L.1242-12 du Code du travail.';
const MENTION_LIBERALE = 'Contrat de prestation entre l’établissement et le professionnel libéral.';
const NUMERO_DPAE = 'SIM2026DPAE01';

function preparer(type: string, regime: 'SALARIE' | 'LIBERAL') {
  const banc = creerMissionSimulee();
  const { state } = banc;
  state.contratCree = true;
  Object.assign(state.mission, { statut: 'ASSIGNEE', soignant_assigne_id: ids.soignant,
    type_contrat_applique: regime, type_contrat_recherche: regime });
  Object.assign(state.soignant, { type_exercice: regime });
  Object.assign(state.contrat, { type_contrat: type, numero_contrat: `SIM-CONTRAT-${type}`,
    dpae_effectuee: false, dpae_numero: null, dpae_effectuee_le: null,
    contenu_html: `<article><h2>Contrat fictif ${type}</h2><p>Camille Recette — Clinique Simulation</p></article>` });
  return banc;
}

// Encadrés DPAE localisés par data-testid (DPAEStatus, BandeauRappelDPAE) ; data-etat
// distingue « à déclarer / déclarée » et « à effectuer / effectuée ».
const statutDpae = (page: Page) => page.getByTestId('dpae-statut');
const rappelDpae = (page: Page) => page.getByTestId('rappel-dpae');

async function ouvrir(page: Page, type: string) {
  await expect(page.getByRole('heading', { name: `Contrat SIM-CONTRAT-${type}`, exact: true, level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: `Contrat fictif ${type}`, exact: true })).toBeVisible();
}

async function verifierCompteARebours(page: Page) {
  const minuteur = page.getByRole('timer');
  await expect(minuteur).toHaveCount(1);
  await expect(minuteur).toHaveText(COMPTE_A_REBOURS);
  expect((await minuteur.innerText()).trim()).toBe(COMPTE_A_REBOURS);
  expect(await page.locator('body').innerText()).not.toContain('sous72h');
}

async function verifierPiedDePage(page: Page, attendue: string, absente: string) {
  const pied = page.getByRole('main').locator('p').filter({ hasText: /Signature électronique simple\./ });
  await expect(pied).toHaveCount(1);
  await expect(pied).toContainText(attendue);
  await expect(pied).not.toContainText(absente);
}

async function deposerDump(info: TestInfo, label: string, locator: Locator) {
  const aria = await locator.ariaSnapshot();
  await writeFile(info.outputPath(`${label}.aria.yml`), aria + '\n');
  await info.attach(`${label}-aria`, { body: aria, contentType: 'text/plain' });
  return aria;
}

for (const type of ['CDDU', 'VACATION'] as const) {
  test(`DPAE CONTRAT — établissement : contrat ${type}, statut puis rappel DPAE, déclaration et reprise après rechargement`, async ({ context, page }, info) => {
    const { state, installer } = preparer(type, 'SALARIE');
    await installer(context, 'ADMIN_ETABLISSEMENT');
    await page.clock.setFixedTime(new Date(now));
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
    const label = `dpae-${type}-ADMIN_ETABLISSEMENT-${info.project.name}`;
    const blocDpae = statutDpae(page);
    try {
      // 1. Contrat salarié en attente de signatures : préparation DPAE proposée avant toute signature.
      await page.goto(`/contrat/${ids.contrat}`);
      await ouvrir(page, type);
      await verifierCompteARebours(page);
      await expect(blocDpae).toHaveCount(1);
      await expect(blocDpae).toHaveAttribute('data-etat', 'a-declarer');
      await expect(blocDpae.getByText(BLOC_DPAE, { exact: true })).toBeVisible();
      await expect(rappelDpae(page)).toHaveCount(0);
      await expect(blocDpae).toContainText("La Déclaration Préalable à l'Embauche doit être effectuée auprès de l'URSSAF avant la prise de poste (art. R1221-2 Code travail).");
      await expect(page.getByRole('button', { name: BOUTON_PREPARER, exact: true })).toBeVisible();
      await expect(page.getByText(RAPPEL_DPAE, { exact: true })).toHaveCount(0);
      await verifierPiedDePage(page, MENTION_SALARIEE, MENTION_LIBERALE);
      await deposerDump(info, `${label}-1-bloc-dpae-attente`, blocDpae);
      await deposerDump(info, `${label}-1-compte-a-rebours`, page.getByRole('timer'));
      await preuveMission(page, info, `${label}-1-attente-signatures`);

      // 2. État serveur simulé : l'établissement a signé. Le rappel DPAE s'ajoute au bloc.
      Object.assign(state.contrat, { signature_etablissement: true, signature_etablissement_le: now, statut: 'SIGNE_ETABLISSEMENT' });
      await page.reload();
      await ouvrir(page, type);
      await expect(page.getByText(DEJA_SIGNE, { exact: true })).toBeVisible();
      const rappel = rappelDpae(page);
      await expect(rappel).toHaveCount(1);
      await expect(rappel).toHaveAttribute('data-etat', 'a-effectuer');
      await expect(rappel.getByText(RAPPEL_DPAE, { exact: true })).toBeVisible();
      await expect(rappel).toContainText(RAPPEL_DPAE_SUITE);
      await expect(blocDpae).toHaveCount(1);
      await expect(blocDpae).toHaveAttribute('data-etat', 'a-declarer');
      await verifierCompteARebours(page);
      await deposerDump(info, `${label}-2-rappel-dpae`, rappel);
      await preuveMission(page, info, `${label}-2-signe-etablissement-rappel`);

      // 3. Préparation des données (RPC simulée) puis saisie du numéro URSSAF.
      await page.getByRole('button', { name: BOUTON_PREPARER, exact: true }).click();
      const donnees = blocDpae.locator('pre');
      await expect(donnees).toContainText("=== DPAE — Déclaration Préalable à l'Embauche ===");
      await expect(donnees).toContainText(new RegExp(`type_contrat\\s+: ${type}`));
      await expect(blocDpae.getByRole('link', { name: 'Transmettre sur Net-Entreprises' }))
        .toHaveAttribute('href', 'https://www.net-entreprises.fr/declaration-prealable-embauche/');
      await blocDpae.getByPlaceholder('Ex : 2026XXXXXXXX').fill(NUMERO_DPAE);
      await blocDpae.getByRole('button', { name: 'Enregistrer le numéro DPAE', exact: true }).click();
      const blocDeclare = statutDpae(page);
      await expect(blocDeclare).toHaveAttribute('data-etat', 'declaree');
      await expect(blocDeclare).toHaveText(`DPAE déclarée Numéro DPAE : ${NUMERO_DPAE}`, { useInnerText: true });
      await expect(page.getByText(BLOC_DPAE, { exact: true })).toHaveCount(0);
      await deposerDump(info, `${label}-3-bloc-dpae-declaree`, blocDeclare);

      // 4. Reprise après rechargement : le numéro relu du contrat, le rappel devient confirmation.
      await page.reload();
      await ouvrir(page, type);
      await expect(blocDeclare).toHaveAttribute('data-etat', 'declaree');
      await expect(blocDeclare).toHaveText(`DPAE déclarée Numéro DPAE : ${NUMERO_DPAE}`, { useInnerText: true });
      const confirmation = rappelDpae(page);
      await expect(confirmation).toHaveCount(1);
      await expect(confirmation).toHaveAttribute('data-etat', 'effectuee');
      await expect(confirmation.getByText(RAPPEL_DPAE_FAITE, { exact: true })).toBeVisible();
      await expect(page.getByText(RAPPEL_DPAE, { exact: true })).toHaveCount(0);
      await expect(page.getByRole('button', { name: BOUTON_PREPARER, exact: true })).toHaveCount(0);
      await verifierCompteARebours(page);
      await verifierPiedDePage(page, MENTION_SALARIEE, MENTION_LIBERALE);
      await deposerDump(info, `${label}-4-confirmation-apres-reload`, confirmation);
      await writeFile(info.outputPath(`${label}.main.aria.yml`), await page.getByRole('main').ariaSnapshot() + '\n');
      await preuveMission(page, info, `${label}-4-dpae-declaree-apres-reload`);

      const appelsDpae = state.calls.filter(call => call.name.includes('dpae'));
      expect(appelsDpae.map(call => [call.name, call.body])).toEqual([
        ['fn_generer_donnees_dpae', { p_contrat_id: ids.contrat }],
        ['fn_enregistrer_numero_dpae', { p_contrat_id: ids.contrat, p_dpae_numero: NUMERO_DPAE }],
      ]);
      expect(state.contrat).toMatchObject({ type_contrat: type, dpae_numero: NUMERO_DPAE, dpae_effectuee: true, dpae_effectuee_le: now });
      expect(state.emails).toEqual([{ simulated: true, type: 'DPAE_DECLAREE_SOIGNANT', destinataire_id: ids.soignant }]);
      expect(state.calls.filter(call => ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp', 'generate-contrat-mission-pdf'].includes(call.name))).toEqual([]);
      expect(state.unknown).toEqual([]);
      expect(state.external).toEqual([]);
      expect(state.errors).toEqual([]);
      expect(state.signatures).toEqual([]);
      expect(state.sms).toEqual([]);
    } finally {
      await info.attach(`${label}-journal-simule`, {
        body: JSON.stringify({ simulationSeulement: true, type, calls: state.calls, unknown: state.unknown,
          external: state.external, errors: state.errors, emails: state.emails }),
        contentType: 'application/json',
      });
    }
  });
}

test('DPAE CONTRAT — établissement : remplacement libéral, ni statut ni rappel DPAE, avant et après signature', async ({ context, page }, info) => {
  const type = 'REMPLACEMENT_LIBERAL';
  const { state, installer } = preparer(type, 'LIBERAL');
  await installer(context, 'ADMIN_ETABLISSEMENT');
  await page.clock.setFixedTime(new Date(now));
  await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  const label = `dpae-${type}-ADMIN_ETABLISSEMENT-${info.project.name}`;
  const aucuneDpae = async () => {
    await expect(statutDpae(page)).toHaveCount(0);
    await expect(rappelDpae(page)).toHaveCount(0);
    await expect(page.getByText(BLOC_DPAE, { exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: BOUTON_PREPARER, exact: true })).toHaveCount(0);
    await expect(page.getByText(RAPPEL_DPAE, { exact: true })).toHaveCount(0);
    expect(await page.getByRole('main').innerText()).not.toContain('DPAE');
    await verifierPiedDePage(page, MENTION_LIBERALE, MENTION_SALARIEE);
    await verifierCompteARebours(page);
  };
  try {
    await page.goto(`/contrat/${ids.contrat}`);
    await ouvrir(page, type);
    await aucuneDpae();
    await preuveMission(page, info, `${label}-1-attente-signatures`);
    Object.assign(state.contrat, { signature_etablissement: true, signature_etablissement_le: now, statut: 'SIGNE_ETABLISSEMENT' });
    await page.reload();
    await ouvrir(page, type);
    await expect(page.getByText(DEJA_SIGNE, { exact: true })).toBeVisible();
    await aucuneDpae();
    await writeFile(info.outputPath(`${label}.main.aria.yml`), await page.getByRole('main').ariaSnapshot() + '\n');
    await preuveMission(page, info, `${label}-2-signe-etablissement`);
    expect(state.calls.filter(call => call.name.includes('dpae'))).toEqual([]);
    expect(state.unknown).toEqual([]);
    expect(state.external).toEqual([]);
    expect(state.errors).toEqual([]);
  } finally {
    await info.attach(`${label}-journal-simule`, {
      body: JSON.stringify({ simulationSeulement: true, type, calls: state.calls, unknown: state.unknown, external: state.external, errors: state.errors }),
      contentType: 'application/json',
    });
  }
});

// Côté soignant : la DPAE est une obligation de l'employeur. Le contrat lui montre la mention
// salariée et le compte à rebours, jamais la préparation ni le rappel DPAE de l'établissement,
// y compris après une déclaration (état serveur simulé) et un rechargement.
for (const type of ['CDDU', 'VACATION'] as const) {
  test(`DPAE CONTRAT — soignant : contrat ${type}, aucune action DPAE employeur, reprise après rechargement`, async ({ context, page }, info) => {
    const { state, installer } = preparer(type, 'SALARIE');
    await installer(context, 'SOIGNANT');
    await page.clock.setFixedTime(new Date(now));
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
    const label = `dpae-${type}-SOIGNANT-${info.project.name}`;
    const verifier = async () => {
      await ouvrir(page, type);
      await verifierCompteARebours(page);
      await verifierPiedDePage(page, MENTION_SALARIEE, MENTION_LIBERALE);
      await expect(statutDpae(page)).toHaveCount(0);
      await expect(rappelDpae(page)).toHaveCount(0);
      await expect(page.getByText(BLOC_DPAE, { exact: true })).toHaveCount(0);
      await expect(page.getByRole('button', { name: BOUTON_PREPARER, exact: true })).toHaveCount(0);
      await expect(page.getByText(RAPPEL_DPAE, { exact: true })).toHaveCount(0);
      await expect(page.getByText(RAPPEL_DPAE_FAITE, { exact: true })).toHaveCount(0);
    };
    try {
      await page.goto(`/contrat/${ids.contrat}`);
      await verifier();
      await deposerDump(info, `${label}-1-compte-a-rebours`, page.getByRole('timer'));
      await preuveMission(page, info, `${label}-1-attente-signatures`);
      Object.assign(state.contrat, { dpae_numero: NUMERO_DPAE, dpae_effectuee: true, dpae_effectuee_le: now });
      await page.reload();
      await verifier();
      await writeFile(info.outputPath(`${label}.main.aria.yml`), await page.getByRole('main').ariaSnapshot() + '\n');
      await preuveMission(page, info, `${label}-2-apres-reload`);
      expect(state.calls.filter(call => call.name.includes('dpae'))).toEqual([]);
      expect(state.unknown).toEqual([]);
      expect(state.external).toEqual([]);
      expect(state.errors).toEqual([]);
    } finally {
      await info.attach(`${label}-journal-simule`, {
        body: JSON.stringify({ simulationSeulement: true, type, calls: state.calls, unknown: state.unknown, external: state.external, errors: state.errors }),
        contentType: 'application/json',
      });
    }
  });
}

// ── Administrateur plateforme : /admin/contrats/:id et /admin/contrats ──
// Les RPC admin (droits, détail, liste) sont simulées ici ; le reste passe par le helper,
// qui refuse et journalise tout endpoint non prévu (state.unknown).
const TYPES_ADMIN = ['CDDU', 'VACATION', 'REMPLACEMENT_LIBERAL', 'CDD'] as const;
type TypeAdmin = typeof TYPES_ADMIN[number];
const idAdmin = (type: TypeAdmin) => `71000000-0000-4000-8000-00000000010${TYPES_ADMIN.indexOf(type) + 1}`;
const DPAE_ATTENTE_ADMIN = '⏳ DPAE non encore transmise / numéro non saisi.';
const A_TRAITER = 'À traiter (signatures en attente, DPAE manquantes)';
const HISTORIQUE = 'Historique (signés, annulés, expirés)';

function contratAdmin(type: TypeAdmin, dpae: { numero: string | null; le: string | null } = { numero: null, le: null }) {
  return { id: idAdmin(type), numero_contrat: `SIM-ADMIN-${type}`, mission_id: ids.mission,
    mission_intitule: `Mission fictive ${type}`, mission_debut_le: '2026-09-24T07:00:00.000Z', mission_fin_le: '2026-09-24T15:00:00.000Z',
    soignant_id: ids.soignant, soignant_nom: 'Camille Recette', soignant_email: 'soignant-mission@example.invalid', soignant_rpps: null,
    etablissement_id: ids.etablissement, etablissement_nom: 'Clinique Simulation', etablissement_siret: null,
    type_contrat: type, statut: 'SIGNE_COMPLET', mode_signature: 'OTP', hash_document: null, hash_court: null,
    signature_soignant: true, signature_soignant_le: now, signature_ip_soignant: null, signature_navigateur_soignant: null,
    signature_etablissement: true, signature_etablissement_le: now, signature_ip_etablissement: null, signature_navigateur_etablissement: null,
    dpae_effectuee: !!dpae.numero, dpae_effectuee_le: dpae.le, dpae_numero: dpae.numero,
    storage_path: null, pdf_cle_s3: null, cree_le: now };
}

async function installerAdmin(context: BrowserContext, page: Page, contrats: Map<string, any>) {
  const banc = creerMissionSimulee();
  await banc.installer(context, 'ADMIN_PLATEFORME');
  await page.clock.setFixedTime(new Date(now));
  await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  const appelsAdmin: { name: string; body: any }[] = [];
  await context.route('**/rest/v1/rpc/fn_admin_*', async route => {
    const req = route.request();
    const name = new URL(req.url()).pathname.split('/').pop()!;
    if (req.method() === 'OPTIONS') return route.fallback();
    const body = req.postData() ? JSON.parse(req.postData()!) : null;
    const json = (data: any) => route.fulfill({ status: 200, json: data, headers: { 'access-control-allow-origin': '*' } });
    if (name === 'fn_admin_mes_acces') { appelsAdmin.push({ name, body }); return json({ acces_total: true, groupes: [] }); }
    if (name === 'fn_admin_detail_contrat') {
      appelsAdmin.push({ name, body });
      const contrat = contrats.get(body?.p_contrat_id);
      return json(contrat ? { success: true, contrat, signatures: [], audit_trail: [] } : { success: false, error: 'Contrat introuvable' });
    }
    if (name === 'fn_admin_lister_contrats') {
      appelsAdmin.push({ name, body });
      const liste = [...contrats.values()];
      return json({ success: true, total: liste.length, contrats: liste });
    }
    return route.fallback();
  });
  return { ...banc, appelsAdmin };
}

function verifierJournalAdmin(state: ReturnType<typeof creerMissionSimulee>['state']) {
  expect(state.calls.filter(call => call.name.includes('dpae'))).toEqual([]);
  expect(state.unknown).toEqual([]);
  expect(state.external).toEqual([]);
  expect(state.errors).toEqual([]);
}

for (const type of ['CDDU', 'VACATION', 'REMPLACEMENT_LIBERAL'] as const) {
  const salarie = type !== 'REMPLACEMENT_LIBERAL';
  test(`DPAE CONTRAT — administrateur : détail d'un contrat ${type}, carte DPAE ${salarie ? 'en attente puis validée' : 'absente'}, reprise après rechargement`, async ({ context, page }, info) => {
    const contrats = new Map([[idAdmin(type), contratAdmin(type)]]);
    const { state, appelsAdmin } = await installerAdmin(context, page, contrats);
    const label = `dpae-${type}-ADMIN_PLATEFORME-detail-${info.project.name}`;
    const carte = page.getByTestId('carte-dpae-admin');
    try {
      await page.goto(`/admin/contrats/${idAdmin(type)}`);
      await expect(page.getByRole('heading', { name: `SIM-ADMIN-${type}`, exact: true, level: 1 })).toBeVisible();
      await expect(page.getByText(type, { exact: true })).toBeVisible();
      if (salarie) {
        await expect(carte).toHaveCount(1);
        await expect(carte.getByRole('heading', { name: 'DPAE', exact: true, level: 2 })).toBeVisible();
        await expect(carte).toHaveText(`DPAE${DPAE_ATTENTE_ADMIN}`);
        await deposerDump(info, `${label}-1-carte-dpae-attente`, carte);
        await preuveMission(page, info, `${label}-1-attente`);
        // État serveur simulé : l'établissement a saisi le numéro URSSAF.
        contrats.set(idAdmin(type), contratAdmin(type, { numero: NUMERO_DPAE, le: now }));
        await page.reload();
        await expect(page.getByRole('heading', { name: `SIM-ADMIN-${type}`, exact: true, level: 1 })).toBeVisible();
        await expect(carte).toHaveCount(1);
        await expect(carte.getByText('DPAE validée le 24 sept. 2026', { exact: true })).toBeVisible();
        await expect(carte.getByText(`N° URSSAF : ${NUMERO_DPAE}`, { exact: true })).toBeVisible();
        await expect(carte.getByText(DPAE_ATTENTE_ADMIN, { exact: true })).toHaveCount(0);
        await deposerDump(info, `${label}-2-carte-dpae-validee-apres-reload`, carte);
        await preuveMission(page, info, `${label}-2-validee-apres-reload`);
      } else {
        for (const etape of ['1-initial', '2-apres-reload']) {
          if (etape === '2-apres-reload') {
            await page.reload();
            await expect(page.getByRole('heading', { name: `SIM-ADMIN-${type}`, exact: true, level: 1 })).toBeVisible();
          }
          await expect(carte).toHaveCount(0);
          await expect(page.getByRole('heading', { name: 'DPAE', exact: true })).toHaveCount(0);
          expect(await page.getByRole('main').innerText()).not.toContain('DPAE');
          await preuveMission(page, info, `${label}-${etape}`);
        }
      }
      await writeFile(info.outputPath(`${label}.main.aria.yml`), await page.getByRole('main').ariaSnapshot() + '\n');
      expect(appelsAdmin.filter(a => a.name === 'fn_admin_detail_contrat').map(a => a.body))
        .toEqual([{ p_contrat_id: idAdmin(type) }, { p_contrat_id: idAdmin(type) }]);
      verifierJournalAdmin(state);
    } finally {
      await info.attach(`${label}-journal-simule`, {
        body: JSON.stringify({ simulationSeulement: true, type, appelsAdmin, calls: state.calls, unknown: state.unknown, external: state.external, errors: state.errors }),
        contentType: 'application/json',
      });
    }
  });
}

test('DPAE CONTRAT — administrateur : liste des contrats, badge et file « À traiter » pour CDDU et VACATION, libéral non requis', async ({ context, page }, info) => {
  const contrats = new Map<string, any>([
    [idAdmin('CDDU'), contratAdmin('CDDU')],
    [idAdmin('VACATION'), contratAdmin('VACATION')],
    [idAdmin('REMPLACEMENT_LIBERAL'), contratAdmin('REMPLACEMENT_LIBERAL')],
    [idAdmin('CDD'), contratAdmin('CDD', { numero: NUMERO_DPAE, le: now })],
  ]);
  const { state, appelsAdmin } = await installerAdmin(context, page, contrats);
  const label = `dpae-ADMIN_PLATEFORME-liste-${info.project.name}`;
  // Table (≥ 768 px) ou cartes (mobile) : une ligne par contrat, numéro exact (CDD ≠ CDDU).
  const ligne = (zone: Locator, type: TypeAdmin) => zone.getByRole('row').or(zone.getByRole('listitem'))
    .filter({ has: page.getByText(`SIM-ADMIN-${type}`, { exact: true }) });
  const aTraiter = page.getByRole('region', { name: A_TRAITER, exact: true });
  const historique = page.getByRole('region', { name: HISTORIQUE, exact: true });
  const verifierListe = async () => {
    await expect(page.getByRole('heading', { name: 'Suivre les signatures de contrats', level: 1 })).toBeVisible();
    await expect(aTraiter.getByRole('heading', { name: `2 ${A_TRAITER}`, exact: true, level: 2 })).toBeVisible();
    for (const type of ['CDDU', 'VACATION'] as const) {
      const contrat = ligne(aTraiter, type);
      await expect(contrat).toHaveCount(1);
      await expect(contrat.getByText('DPAE manquante', { exact: true })).toBeVisible();
      await expect(contrat.getByText('⏳ À déclarer', { exact: true })).toBeVisible();
      await expect(contrat.getByText('Non requise', { exact: true })).toHaveCount(0);
    }
    await expect(ligne(aTraiter, 'REMPLACEMENT_LIBERAL')).toHaveCount(0);
    await expect(ligne(aTraiter, 'CDD')).toHaveCount(0);
    const bouton = historique.getByRole('button', { name: /^Historique \(signés, annulés, expirés\)/ });
    await expect(bouton).toHaveAttribute('aria-expanded', 'false');
    await bouton.click();
    await expect(bouton).toHaveAttribute('aria-expanded', 'true');
    const liberal = ligne(historique, 'REMPLACEMENT_LIBERAL');
    await expect(liberal).toHaveCount(1);
    await expect(liberal.getByText('Non requise', { exact: true })).toBeVisible();
    await expect(liberal.getByText('DPAE manquante', { exact: true })).toHaveCount(0);
    await expect(ligne(historique, 'CDD').getByText(`Validée · ${NUMERO_DPAE.slice(0, 8)}…`, { exact: true })).toBeVisible();
    await expect(ligne(historique, 'CDDU')).toHaveCount(0);
    await expect(ligne(historique, 'VACATION')).toHaveCount(0);
  };
  try {
    await page.goto('/admin/contrats');
    await verifierListe();
    await deposerDump(info, `${label}-1-a-traiter`, aTraiter);
    await deposerDump(info, `${label}-1-historique`, historique);
    await preuveMission(page, info, `${label}-1-liste`);
    await page.reload();
    await verifierListe();
    await preuveMission(page, info, `${label}-2-liste-apres-reload`);
    // Lien profond depuis la file : le contrat VACATION ouvre son détail, carte DPAE en attente.
    await ligne(aTraiter, 'VACATION').getByText('SIM-ADMIN-VACATION', { exact: true }).click();
    await expect(page).toHaveURL(new RegExp(`/admin/contrats/${idAdmin('VACATION')}$`));
    await expect(page.getByRole('heading', { name: 'SIM-ADMIN-VACATION', exact: true, level: 1 })).toBeVisible();
    await expect(page.getByTestId('carte-dpae-admin')).toHaveText(`DPAE${DPAE_ATTENTE_ADMIN}`);
    await preuveMission(page, info, `${label}-3-detail-vacation-depuis-file`);
    expect(appelsAdmin.filter(a => a.name === 'fn_admin_lister_contrats')).toHaveLength(2);
    expect(appelsAdmin.filter(a => a.name === 'fn_admin_detail_contrat').map(a => a.body)).toEqual([{ p_contrat_id: idAdmin('VACATION') }]);
    verifierJournalAdmin(state);
  } finally {
    await info.attach(`${label}-journal-simule`, {
      body: JSON.stringify({ simulationSeulement: true, appelsAdmin, calls: state.calls, unknown: state.unknown, external: state.external, errors: state.errors }),
      contentType: 'application/json',
    });
  }
});
