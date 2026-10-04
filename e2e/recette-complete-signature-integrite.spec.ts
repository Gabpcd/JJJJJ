import { test, expect } from '@playwright/test';
import { creerActionsNationales, stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';

// Contrat UI entièrement simulé : ni code SMS reçu, ni calcul SQL, ni compte distant.
for (const role of ['SOIGNANT', 'ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
  test(`SIGNATURE INTÉGRITÉ — ${role} : première preuve incohérente conservée après refus et reload`, async ({ browser }, info) => {
    // Une scène indépendante par variante garde les limites SMS réalistes (deux demandes).
    for (const variante of ['hash-null', 'hash-divergent'] as const) {
      const context = await browser.newContext({ ...info.project.use });
      const { state, installer, control } = creerActionsNationales();
      state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
      const partieCourante = role === 'SOIGNANT' ? 'soignant' : 'etablissement';
      const premierePartie = role === 'SOIGNANT' ? 'etablissement' : 'soignant';
      const premiereSignatureVisible = premierePartie === 'soignant' ? /^Soignant\(e\) : ✅ Signé/ : /^Établissement : ✅ Signé/;
      Object.assign(state.contrat, {
        statut: role === 'SOIGNANT' ? 'SIGNE_ETABLISSEMENT' : 'SIGNE_SOIGNANT',
        signature_soignant: premierePartie === 'soignant', signature_etablissement: premierePartie === 'etablissement',
        ['signature_' + premierePartie + '_le']: now,
      });
      state.signatures.push({ id: 'preuve-historique-synthetique', contrat_id: ids.contrat,
        signataire_user_id: premierePartie === 'soignant' ? ids.soignant : ids.etablissement,
        signataire_role: premierePartie, signe_a: now, otp_valide_a: now, statut_signature: 'signe',
        hash_document: variante === 'hash-null' ? null : 'b'.repeat(64), cree_le: now,
        ip_signature: '127.0.0.1', user_agent: 'Simulation uniquement', rpps_verifie: false, psc_session_active: false });
      const original = structuredClone(state.contrat), preuveHistorique = structuredClone(state.signatures);
      await installer(context, role);
      // La feuille externe du shell est simulee localement, comme les API.
      // Toute autre destination reste bloquee et fait echouer state.external.
      await context.route(url => url.href === 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap', async route => {
        if (route.request().method() !== 'GET' || route.request().resourceType() !== 'stylesheet') return route.fallback();
        return route.fulfill({ contentType: 'text/css', body: '' });
      });
      const page = await context.newPage(); page.setDefaultTimeout(12_000);
      await page.clock.setFixedTime(new Date(now));
      const generations: string[] = [];
      await context.route('**/functions/v1/generate-contrat-mission-pdf', async route => {
        generations.push(route.request().method());
        await route.fulfill({ status: 409, json: { error: 'Original synthétique à conserver' },
          headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
      });
      try {
        await page.goto(`/contrat/${ids.contrat}`);
        for (let tentative = 0; tentative < 2; tentative++) {
          await expect(page.getByRole('heading', { name: 'Document fictif de recette', exact: true })).toBeVisible();
          await expect(page.getByText(premiereSignatureVisible)).toBeVisible();
          const accord = page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ });
          await expect(accord).not.toBeChecked(); await accord.check();
          await page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true }).click();
          await page.getByRole('textbox', { name: 'Code SMS à 6 chiffres' }).fill('123456');
          const compteur = page.getByText(/^\d{2}:\d{2}$/, { exact: true });
          await expect(compteur).toBeVisible();
          const geometrie = await compteur.evaluate(element => {
            const texte = Array.from(element.childNodes).find(node =>
              node.nodeType === Node.TEXT_NODE && /^\d{2}:\d{2}$/.test(node.textContent?.trim() || ''));
            const icone = element.querySelector('svg');
            if (!texte || !icone || !element.parentElement) throw new Error('Compteur OTP incomplet');
            const range = document.createRange(); range.selectNodeContents(texte);
            const lignes = Array.from(range.getClientRects()).filter(rect => rect.width > 0 && rect.height > 0);
            const bloc = element.getBoundingClientRect(), parent = element.parentElement.getBoundingClientRect();
            const svg = icone.getBoundingClientRect();
            return { texte: texte.textContent?.trim(), lignes: lignes.length,
              iconeLargeur: svg.width, iconeHauteur: svg.height,
              ecartTexteIcone: lignes.length ? lignes[0].left - svg.right : null,
              depassement: Math.max(0, parent.left - bloc.left, bloc.right - parent.right,
                ...lignes.map(rect => rect.right - bloc.right)) };
          });
          await info.attach('otp-compteur-'+role+'-'+variante+'-'+tentative, {
            body: JSON.stringify(geometrie), contentType: 'application/json',
          });
          expect(geometrie.lignes, 'Le compteur OTP tient sur une seule ligne').toBe(1);
          expect(geometrie.iconeLargeur, 'L’icône garde sa largeur').toBeGreaterThanOrEqual(11);
          expect(geometrie.iconeHauteur).toBeGreaterThanOrEqual(11);
          expect(geometrie.ecartTexteIcone, 'Le texte ne recouvre pas l’icône').toBeGreaterThanOrEqual(3);
          expect(geometrie.depassement, 'Le compteur reste dans sa ligne').toBeLessThanOrEqual(1);
          // Code arrêté par le correctif serveur proposé : aucune réparation d'historique.
          control.refuser('fn_signer_contrat_otp', { success: false, error_code: 'HASH_DOCUMENT_CHANGE' });
          await page.getByRole('button', { name: 'Signer', exact: true }).click();
          await expect(page.getByRole('alert')).toHaveText('Le contrat a été modifié depuis votre chargement. Rechargez la page avant de signer.');
          await expect(page.getByRole('button', { name: 'Signer', exact: true })).toBeDisabled();
          await expect(page.getByRole('button', { name: 'Renvoyer le code', exact: true })).toBeDisabled();
          expect(state.calls.filter(call => call.name === 'fn_signer_contrat_otp').at(-1)?.body).toMatchObject({
            p_contrat_id: ids.contrat, p_otp_code: '123456', p_hash_document: original.hash_document,
          });
          expect(state.contrat['signature_' + partieCourante]).toBe(false);
          expect(state.contrat.statut).not.toBe('SIGNE_COMPLET');
          expect(state.contrat).toEqual(original); expect(state.signatures).toEqual(preuveHistorique);
          expect(generations).toEqual([]);
          await preuveMission(page, info, role+'-'+variante+'-refus-'+tentative);
          await stabiliserActionsNationales(page); await page.reload();
        }
        await expect(page.getByRole('heading', { name: 'Document fictif de recette', exact: true })).toBeVisible();
        await expect(page.getByText(premiereSignatureVisible)).toBeVisible();
        await expect(page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ })).not.toBeChecked();
        await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toHaveCount(0);
        expect(state.sms).toHaveLength(2);
        expect(state.calls.filter(call => call.name === 'fn_signer_contrat_otp')).toHaveLength(2);
        expect(state.contrat).toEqual(original); expect(state.signatures).toEqual(preuveHistorique);
        expect(generations).toEqual([]); expect(state.unknown).toEqual([]);
        expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
      } finally {
        await info.attach('signature-historique-simulee-'+role+'-'+variante, {
          body: JSON.stringify({ variante, generations, calls: state.calls, signatures: state.signatures,
            statut: state.contrat.statut, errors: state.errors, unknown: state.unknown, external: state.external }), contentType: 'application/json',
        });
        await context.close();
      }
    }
  });
}
