import { expect, test } from '@playwright/test';
import { creerMissionSimulee, ids, now } from './helpers/recette-complete-mission';
import { preuve } from './helpers/recette-complete-etablissement';

// Parcours établissement réel avec réponses intégralement simulées : aucun
// droit d’exercice, contrat, message ou mouvement financier distant n’est créé.
for (const profession of ['AS', 'MEDECIN'] as const) {
  test(`candidature étudiante ${profession} — attestation aide-soignant réservée au profil AS`, async ({ context, page }, info) => {
    const simulation = creerMissionSimulee();
    const { state } = simulation;
    const aideSoignant = profession === 'AS';
    const mode = aideSoignant ? 'SALARIE' : 'LIBERAL';
    Object.assign(state.soignant, { profession, est_etudiant: true, type_exercice: mode });
    Object.assign(state.mission, {
      intitule: `Candidature étudiant ${profession} — simulation`, profession_requise: profession,
      type_contrat_recherche: mode,
      type_paiement_soignant: aideSoignant ? 'BULLETIN_PAIE' : 'NOTE_HONORAIRES',
    });
    state.contrat.type_contrat = aideSoignant ? 'CDD' : 'LIBERAL';
    state.candidature = {
      id: ids.candidature, mission_id: ids.mission, soignant_id: ids.soignant,
      statut: 'EN_ATTENTE', cree_le: now, message: `Candidature fictive étudiant ${profession}`,
    };
    await simulation.installer(context, 'ADMIN_ETABLISSEMENT');
    await page.clock.setFixedTime(new Date(now));
    await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
    await page.route('https://js.stripe.com/**', route => route.fulfill({ contentType: 'application/javascript', body: 'window.Stripe = function(){ throw new Error("Stripe interdit dans cette simulation"); };' }));
    const acceptations: Record<string, unknown>[] = [];
    await page.route(url => url.pathname === '/rest/v1/rpc/fn_traiter_candidature_planning_v1', async route => {
      const req = route.request();
      const url = new URL(req.url());
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) {
        state.external.push(url.origin);
        return route.abort();
      }
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS' };
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, body: '', headers });
      expect(req.method()).toBe('POST');
      expect(req.headers().authorization).toBe('Bearer simulation-mission-ADMIN_ETABLISSEMENT');
      const body = req.postDataJSON();
      expect(body).toEqual({
        p_candidature_id: ids.candidature, p_decision: 'ACCEPTEE',
        p_creneaux_confirmes: state.creneaux.map(({ debut, fin }) => ({ debut, fin })),
        p_motif: aideSoignant ? 'CADRE_ETUDIANT_AS_CONFIRME' : null,
      });
      expect(state.candidature.statut).toBe('EN_ATTENTE');
      acceptations.push(body);
      state.calls.push({ role: 'ADMIN_ETABLISSEMENT', name: 'fn_traiter_candidature_planning_v1', method: req.method(), body });
      state.candidature.statut = 'ACCEPTEE';
      state.mission.statut = 'ASSIGNEE';
      state.mission.soignant_assigne_id = ids.soignant;
      state.mission.type_contrat_applique = mode;
      state.contratCree = true;
      return route.fulfill({ json: { success: true, contrat_id: ids.contrat }, headers });
    });

    await page.goto(`/etablissement/missions/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByText(`"Candidature fictive étudiant ${profession}"`, { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Accepter cette candidature', exact: true }).click();
    const dialogue = page.getByRole('dialog', { name: 'Confirmer l’acceptation', exact: true });
    await expect(dialogue).toBeVisible();
    await expect(dialogue).toContainText('1 créneau · 8 h au total');
    await expect(dialogue).toContainText('09:00 → 17:00');
    const attestation = dialogue.getByRole('checkbox', { name: /mission est salariée.*temporairement comme aide-soignant/ });
    const confirmer = dialogue.getByRole('button', { name: 'Confirmer et assigner', exact: true });
    expect(acceptations).toEqual([]);
    if (aideSoignant) {
      await expect(attestation).toBeVisible();
      await expect(attestation).not.toBeChecked();
      await expect(confirmer).toBeDisabled();
      await preuve(page, 'candidature-etudiant-as-attestation-requise', info);
      await attestation.check();
    } else {
      await expect(attestation).toHaveCount(0);
      await expect(dialogue).not.toContainText('temporairement comme aide-soignant');
      await preuve(page, 'candidature-interne-medecin-sans-attestation-as', info);
    }
    await expect(confirmer).toBeEnabled();
    await confirmer.click();
    await expect(dialogue).toBeHidden();
    await expect(page.getByText('Assignée', { exact: true }).first()).toBeVisible();
    expect(acceptations).toHaveLength(1);
    await page.waitForLoadState('networkidle');
    await page.reload();
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByText('Assignée', { exact: true }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'Accepter cette candidature', exact: true })).toHaveCount(0);
    await preuve(page, `candidature-etudiant-${profession.toLowerCase()}-assignation-rechargee`, info);
    expect(acceptations).toHaveLength(1);
    expect(state.sms).toEqual([]); expect(state.emails).toEqual([]);
    expect(state.signatures).toEqual([]); expect(state.facture).toBeNull();
    expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]);
    await info.attach('acceptation-simulee', { body: JSON.stringify(acceptations, null, 2), contentType: 'application/json' });
  });
}
