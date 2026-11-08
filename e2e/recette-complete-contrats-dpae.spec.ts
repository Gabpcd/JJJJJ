import { test, expect, type Locator, type Page, type TestInfo } from '@playwright/test';
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

// Racine du bloc (DPAEStatus ou BandeauRappelDPAE) qui porte ce texte.
const encadre = (page: Page, texte: string) => page.getByText(texte, { exact: true })
  .locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " rounded-xl ")][1]');

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
    const blocDpae = encadre(page, BLOC_DPAE);
    try {
      // 1. Contrat salarié en attente de signatures : préparation DPAE proposée avant toute signature.
      await page.goto(`/contrat/${ids.contrat}`);
      await ouvrir(page, type);
      await verifierCompteARebours(page);
      await expect(blocDpae).toHaveCount(1);
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
      const rappel = encadre(page, RAPPEL_DPAE);
      await expect(rappel).toHaveCount(1);
      await expect(rappel).toContainText(RAPPEL_DPAE_SUITE);
      await expect(blocDpae).toHaveCount(1);
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
      const blocDeclare = encadre(page, 'DPAE déclarée');
      await expect(blocDeclare).toHaveText(`DPAE déclarée Numéro DPAE : ${NUMERO_DPAE}`, { useInnerText: true });
      await expect(page.getByText(BLOC_DPAE, { exact: true })).toHaveCount(0);
      await deposerDump(info, `${label}-3-bloc-dpae-declaree`, blocDeclare);

      // 4. Reprise après rechargement : le numéro relu du contrat, le rappel devient confirmation.
      await page.reload();
      await ouvrir(page, type);
      await expect(blocDeclare).toHaveText(`DPAE déclarée Numéro DPAE : ${NUMERO_DPAE}`, { useInnerText: true });
      const confirmation = encadre(page, RAPPEL_DPAE_FAITE);
      await expect(confirmation).toHaveCount(1);
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
