import { test, expect } from '@playwright/test';
import { creerActionsNationales, stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// NON_AUTORISE est le contrat des deux RPC : compte inactif ou droits retirés.
// Les causes et les permissions réelles sont qualifiées en SQL, pas par ces mocks.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`SIGNATURE AUTORISATION — ${role} : demande et validation refusées après reload`, async ({ browser }, info) => {
    for (const etapeRefusee of ['demande', 'validation'] as const) {
      const context = await browser.newContext({ ...info.project.use });
      const { state, installer, control } = creerActionsNationales();
      state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
      const premierePartie = role === 'SOIGNANT' ? 'etablissement' : 'soignant';
      Object.assign(state.contrat, {
        statut: role === 'SOIGNANT' ? 'SIGNE_ETABLISSEMENT' : 'SIGNE_SOIGNANT',
        signature_soignant: premierePartie === 'soignant', signature_etablissement: premierePartie === 'etablissement',
        ['signature_' + premierePartie + '_le']: now,
      });
      state.signatures.push({ id: 'preuve-autorisation-synthetique', contrat_id: ids.contrat,
        signataire_user_id: premierePartie === 'soignant' ? ids.soignant : ids.etablissement,
        signataire_role: premierePartie, signe_a: now, otp_valide_a: now, statut_signature: 'signe',
        hash_document: state.contrat.hash_document, cree_le: now,
        ip_signature: '127.0.0.1', user_agent: 'Simulation uniquement', rpps_verifie: false, psc_session_active: false });
      const original = structuredClone(state.contrat), historique = structuredClone(state.signatures);
      const generations: string[] = [];
      await installer(context, role);
      await context.route(url => url.href === 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap', async route => {
        if (route.request().method() !== 'GET' || route.request().resourceType() !== 'stylesheet') return route.fallback();
        return route.fulfill({ contentType: 'text/css', body: '' });
      });
      await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
        generations.push(route.request().method());
        return route.fulfill({ status: 409, json: { error: 'Original synthétique à conserver' },
          headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
      });
      const page = await context.newPage(); page.setDefaultTimeout(12_000);
      await page.clock.setFixedTime(new Date(now));
      try {
        await page.goto(`/contrat/${ids.contrat}`);
        for (let tentative = 0; tentative < 2; tentative++) {
          await expect(page.getByRole('heading', { name: 'Document fictif de recette', exact: true })).toBeVisible();
          await expect(page.getByText(premierePartie === 'soignant' ? /^Soignant\(e\) : ✅ Signé/ : /^Établissement : ✅ Signé/)).toBeVisible();
          const accord = page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ });
          const demander = page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true });
          await expect(accord).not.toBeChecked(); await expect(demander).toBeDisabled();
          await accord.check();
          if (etapeRefusee === 'demande') control.refuser('fn_envoyer_otp_signature', { success: false, error_code: 'NON_AUTORISE' });
          await demander.click();
          if (etapeRefusee === 'validation') {
            await page.getByRole('textbox', { name: 'Code SMS à 6 chiffres' }).fill('123456');
            control.refuser('fn_signer_contrat_otp', { success: false, error_code: 'NON_AUTORISE' });
            await page.getByRole('button', { name: 'Signer', exact: true }).click();
            await expect(page.getByRole('alert')).toHaveText("Vous n'êtes pas autorisé(e) à signer ce contrat.");
            await expect(page.getByRole('button', { name: 'Signer', exact: true })).toBeDisabled();
            await expect(page.getByRole('button', { name: 'Renvoyer le code', exact: true })).toBeDisabled();
            expect(state.calls.filter(call => call.name === 'fn_signer_contrat_otp').at(-1)?.body).toMatchObject({
              p_contrat_id: ids.contrat, p_otp_code: '123456', p_hash_document: original.hash_document,
            });
          } else {
            await expect(page.getByRole('alert')).toHaveText("Vous n'êtes pas autorisé(e) à signer ce contrat.");
            await expect(demander).toBeDisabled();
            await expect(page.getByRole('textbox', { name: 'Code SMS à 6 chiffres' })).toHaveCount(0);
            await expect(page.getByRole('button', { name: 'Signer', exact: true })).toHaveCount(0);
          }
          await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toHaveCount(0);
          expect(state.calls.filter(call => call.name === 'fn_envoyer_otp_signature')).toHaveLength(tentative + 1);
          expect(state.calls.filter(call => call.name === 'fn_signer_contrat_otp')).toHaveLength(etapeRefusee === 'validation' ? tentative + 1 : 0);
          expect(state.sms).toHaveLength(etapeRefusee === 'validation' ? tentative + 1 : 0);
          expect(state.contrat).toEqual(original); expect(state.signatures).toEqual(historique);
          expect(generations).toEqual([]);
          await preuveMission(page, info, role+'-'+etapeRefusee+'-non-autorise-'+tentative);
          await stabiliserActionsNationales(page);
          if (tentative === 0) await page.reload();
        }
        expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
      } finally {
        await info.attach('signature-autorisation-simulee-'+role+'-'+etapeRefusee, {
          body: JSON.stringify({ etapeRefusee, calls: state.calls, sms: state.sms, generations,
            signatures: state.signatures, statut: state.contrat.statut,
            unknown: state.unknown, external: state.external, errors: state.errors }), contentType: 'application/json',
        });
        await context.close();
      }
    }
  });
}
