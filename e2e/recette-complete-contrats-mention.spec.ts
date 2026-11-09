import { test, expect } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import { creerMissionSimulee, ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// Mention du pied de page de /contrat/:id selon le type de contrat : CDDU et VACATION sont
// des contrats salariés (décision de Gabrielle du 08/11/2026, HARD STOP n°4), le remplacement
// libéral garde la mention de prestation. Simulation UI stricte : Auth, contrat et autres
// réponses API sont fictifs ; aucun backend, rendu serveur, signature, SMS ni e-mail réel.
const MENTION_SALARIEE = 'Contrat salarié écrit — art. L.1242-12 du Code du travail.';
const MENTION_LIBERALE = 'Contrat de prestation entre l’établissement et le professionnel libéral.';
const SUITE_PIED_DE_PAGE = 'Signature électronique simple. Les montants prévisionnels sont régularisés selon les heures validées et les éventuelles corrections contradictoires.';

const cas = [
  { type: 'CDDU', regime: 'SALARIE', attendue: MENTION_SALARIEE, absente: MENTION_LIBERALE },
  { type: 'VACATION', regime: 'SALARIE', attendue: MENTION_SALARIEE, absente: MENTION_LIBERALE },
  { type: 'REMPLACEMENT_LIBERAL', regime: 'LIBERAL', attendue: MENTION_LIBERALE, absente: MENTION_SALARIEE },
] as const;

for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  for (const c of cas) {
    test(`MENTION CONTRAT — ${role} : pied de page d'un contrat ${c.type}, puis reprise après rechargement`, async ({ context, page }, info) => {
      const { state, installer } = creerMissionSimulee();
      state.contratCree = true;
      Object.assign(state.mission, { statut: 'ASSIGNEE', soignant_assigne_id: ids.soignant,
        type_contrat_applique: c.regime, type_contrat_recherche: c.regime });
      Object.assign(state.soignant, { type_exercice: c.regime });
      const numero = `SIM-MENTION-${c.type}`;
      Object.assign(state.contrat, { type_contrat: c.type, numero_contrat: numero,
        contenu_html: `<article><h2>Contrat fictif ${c.type}</h2><p>Camille Recette — Clinique Simulation</p></article>` });
      const initial = structuredClone(state.contrat);
      await installer(context, role);
      await page.clock.setFixedTime(new Date(now));
      await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
      const label = `mention-${c.type}-${role}-${info.project.name}`;
      const piedDePage = page.getByRole('main').locator('p').filter({ hasText: /Signature électronique simple\./ });
      const verifierPiedDePage = async () => {
        await expect(page.getByRole('heading', { name: `Contrat ${numero}`, exact: true, level: 1 })).toBeVisible();
        await expect(page.getByRole('heading', { name: `Contrat fictif ${c.type}`, exact: true })).toBeVisible();
        await expect(piedDePage).toHaveCount(1);
        await expect(piedDePage).toHaveText(`${c.attendue} ${SUITE_PIED_DE_PAGE}`);
        await expect(piedDePage).toContainText(c.attendue);
        await expect(piedDePage).not.toContainText(c.absente);
        await expect(page.getByText(c.attendue)).toHaveCount(1);
        await expect(page.getByText(c.absente)).toHaveCount(0);
        expect(await page.locator('body').innerText()).not.toContain(c.absente);
      };
      try {
        await page.goto(`/contrat/${ids.contrat}`);
        await verifierPiedDePage();
        const ariaPiedDePage = await piedDePage.ariaSnapshot();
        const textePiedDePage = (await piedDePage.innerText()).trim();
        await writeFile(info.outputPath(`${label}.pied-de-page.aria.yml`), ariaPiedDePage + '\n');
        await writeFile(info.outputPath(`${label}.pied-de-page.txt`), textePiedDePage + '\n');
        await writeFile(info.outputPath(`${label}.main.aria.yml`), await page.getByRole('main').ariaSnapshot() + '\n');
        await info.attach(`${label}-pied-de-page-aria`, { body: ariaPiedDePage, contentType: 'text/plain' });
        await preuveMission(page, info, `${label}-initial`);
        await page.reload();
        await verifierPiedDePage();
        expect(await piedDePage.ariaSnapshot()).toBe(ariaPiedDePage);
        await preuveMission(page, info, `${label}-apres-reload`);
        expect(state.contrat).toEqual(initial);
        expect(state.calls.filter(call => call.name === 'generate-contrat-mission-pdf')).toEqual([]);
        expect(state.unknown).toEqual([]);
        expect(state.external).toEqual([]);
        expect(state.errors).toEqual([]);
        expect(state.signatures).toEqual([]);
        expect(state.sms).toEqual([]);
        expect(state.emails).toEqual([]);
      } finally {
        await info.attach(`${label}-journal-simule`, {
          body: JSON.stringify({ simulationSeulement: true, role, type: c.type, calls: state.calls,
            unknown: state.unknown, external: state.external, errors: state.errors }),
          contentType: 'application/json',
        });
      }
    });
  }
}
