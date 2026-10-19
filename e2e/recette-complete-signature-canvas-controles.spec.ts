import { test, expect, type Page } from '@playwright/test';
import { creerMissionSimulee, ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// Simulation frontend : aucun compte, SMS, original personnel ou fournisseur réel.
// Les refus correspondent aux cas du banc SQL signature-canvas-controles.test.sql.
async function preparerSignature(page: Page) {
  await page.getByText('✍️ Signature manuscrite (canvas)', { exact: true }).click();
  const canvas = page.locator('canvas');
  await canvas.scrollIntoViewIfNeeded();
  const box = await canvas.boundingBox();
  expect(box).not.toBeNull();
  for (const offset of [25, 60]) {
    await page.mouse.move(box!.x + 20, box!.y + offset);
    await page.mouse.down();
    await page.mouse.move(box!.x + Math.min(160, box!.width - 20), box!.y + offset + 20, { steps: 6 });
    await page.mouse.up();
  }
  await page.getByRole('button', { name: 'Valider la signature', exact: true }).click();
  await page.getByRole('checkbox', { name: 'Je reconnais avoir lu et accepté les termes de ce contrat.' }).check();
  await expect(page.getByRole('button', { name: '✍️ Signer définitivement', exact: true })).toBeEnabled();
}

async function confirmerSignature(page: Page) {
  await page.getByRole('button', { name: '✍️ Signer définitivement', exact: true }).click();
  await page.getByRole('dialog', { name: 'Confirmer la signature' })
    .getByRole('button', { name: '✍️ Signer', exact: true }).click();
}

for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`CANVAS — ${role} : refus serveur, aucune fausse réussite, reprise et signature autorisée`, async ({ context, page }, info) => {
    const { state, installer } = creerMissionSimulee();
    state.contratCree = true;
    const initial = structuredClone(state.contrat);
    const appels: { name: string; contratId: string; imagePresente: boolean; resultat: string }[] = [];
    let erreur: 'CONTRAT_INACTIF' | 'NON_AUTORISE' | 'HASH_DOCUMENT_CHANGE' | null = null;
    await installer(context, role);
    await page.clock.setFixedTime(new Date(now));
    await context.route('**/rest/v1/rpc/fn_signer_contrat_*', async route => {
      if (route.request().method() === 'OPTIONS') return route.fallback();
      const name = new URL(route.request().url()).pathname.split('/').pop()!;
      const body = route.request().postDataJSON();
      expect(name).toBe(role === 'SOIGNANT' ? 'fn_signer_contrat_soignant' : 'fn_signer_contrat_etablissement');
      expect(body.p_contrat_id).toBe(ids.contrat);
      expect(body.p_signature_image).toMatch(/^data:image\/png;base64,/);
      appels.push({ name, contratId: body.p_contrat_id, imagePresente: true, resultat: erreur ?? 'SUCCESS' });
      if (!erreur) Object.assign(state.contrat, role === 'SOIGNANT'
        ? { signature_soignant: true, signature_soignant_le: now, signature_image_soignant: body.p_signature_image, statut: 'SIGNE_SOIGNANT' }
        : { signature_etablissement: true, signature_etablissement_le: now, signature_image_etablissement: body.p_signature_image, statut: 'SIGNE_ETABLISSEMENT' });
      await route.fulfill({ json: erreur ? { success: false, error_code: erreur,
        error: erreur === 'CONTRAT_INACTIF' ? 'Ce contrat ne peut plus être signé.'
          : erreur === 'NON_AUTORISE' ? 'Ce contrat ne vous concerne pas'
            : 'Le document a changé ou sa preuve est indisponible. Rechargez la page avant de signer.' } : { success: true },
      headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    });
    try {
      for (const refus of ['CONTRAT_INACTIF', 'NON_AUTORISE', 'HASH_DOCUMENT_CHANGE'] as const) {
        Object.assign(state.contrat, initial);
        erreur = refus;
        await page.goto(`/contrat/${ids.contrat}`);
        await expect(page.getByRole('heading', { name: 'Document fictif de recette', exact: true })).toBeVisible();
        await preparerSignature(page);
        // Une page peut être ouverte avant l'annulation ou la révocation des droits.
        if (refus === 'CONTRAT_INACTIF') state.contrat.statut = 'ANNULE';
        if (refus === 'HASH_DOCUMENT_CHANGE') state.contrat.hash_document = '0'.repeat(64);
        const avant = structuredClone(state.contrat);
        await confirmerSignature(page);
        const message = refus === 'CONTRAT_INACTIF'
          ? 'Ce contrat ne peut plus être signé. Rechargez la page pour afficher son état.'
          : refus === 'NON_AUTORISE' ? 'Vous n’avez pas l’autorisation de signer ce contrat.'
            : 'La preuve du document est indisponible ou a changé. Rechargez la page ; si le problème persiste, contactez le support.';
        await expect(page.getByText(message, { exact: true })).toBeVisible();
        await expect(page.getByText('Contrat signé avec succès !', { exact: true })).toHaveCount(0);
        await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toHaveCount(0);
        expect(state.contrat).toEqual(avant);
        await preuveMission(page, info, role + '-' + refus);
        await page.reload();
        await expect(page.getByRole('heading', { name: 'Document fictif de recette', exact: true })).toBeVisible();
        expect(state.contrat).toEqual(avant);
        if (refus === 'CONTRAT_INACTIF') {
          await expect(page.getByRole('button', { name: '✍️ Signer définitivement', exact: true })).toHaveCount(0);
          await expect(page.getByText('Votre signature', { exact: true })).toHaveCount(0);
        }
      }
      Object.assign(state.contrat, initial);
      erreur = null;
      await page.reload();
      await preparerSignature(page);
      await confirmerSignature(page);
      await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
      expect(appels.map(a => a.resultat)).toEqual(['CONTRAT_INACTIF', 'NON_AUTORISE', 'HASH_DOCUMENT_CHANGE', 'SUCCESS']);
      expect(state.contrat.signature_soignant).toBe(role === 'SOIGNANT');
      expect(state.contrat.signature_etablissement).toBe(role === 'ADMIN_ETABLISSEMENT');
      expect(state.contrat.contenu_html).toBe(initial.contenu_html);
      const signe = structuredClone(state.contrat);
      await page.reload();
      await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Document fictif de recette', exact: true })).toBeVisible();
      expect(state.contrat).toEqual(signe);
      expect(appels).toHaveLength(4);
      expect(state.sms).toEqual([]);
      expect(state.emails).toEqual([]);
      expect(state.unknown).toEqual([]);
      expect(state.errors).toEqual([]);
      await preuveMission(page, info, role + '-signe-apres-rechargement');
    } finally {
      await info.attach('signature-canvas-simulation', { body: JSON.stringify({ role, appels,
        errors: state.errors, unknown: state.unknown, integrationReelle: false }), contentType: 'application/json' });
    }
  });
}
