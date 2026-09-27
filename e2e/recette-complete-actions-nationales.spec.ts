import { test, expect } from '@playwright/test';
import { creerActionsNationales, stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { ids, now, preuveMission } from './helpers/recette-complete-mission';

test('ACTIONS — OTP : refus bloquant, interruption et reprise du contrat sans signature parasite', async ({ context, page }, info) => {
  const { state, installer, control } = creerActionsNationales();
  state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
  await installer(context, 'SOIGNANT'); await page.clock.setFixedTime(new Date(now));
  try {
    await page.goto(`/soignant/missions/${ids.mission}`);
    await expect(page.getByRole('heading', { name: state.mission.intitule, exact: true })).toBeVisible();
    await stabiliserActionsNationales(page);
    await page.goto(`/contrat/${ids.contrat}`);
    const accord = page.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ });
    const sms = page.getByRole('button', { name: 'Recevoir le code SMS pour signer', exact: true });
    await accord.check();
    const liberer = control.retenir('fn_envoyer_otp_signature');
    await sms.dblclick();
    await expect.poll(() => control.appelsRetenus.filter(n => n === 'fn_envoyer_otp_signature').length).toBe(1);
    await expect(sms).toBeDisabled();
    await page.getByRole('button', { name: /Retour/ }).filter({ visible: true }).click();
    await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
    liberer(); await expect.poll(() => state.sms.length).toBe(1);
    await expect(page.getByText(/Code envoyé au/)).not.toBeVisible();
    expect(state.signatures).toHaveLength(0);
    await stabiliserActionsNationales(page);
    await page.goto(`/contrat/${ids.contrat}`);
    await expect(accord).not.toBeChecked(); await expect(sms).toBeDisabled();
    await accord.check(); await sms.click();
    const code = page.getByRole('textbox', { name: 'Code SMS à 6 chiffres' });
    await code.fill('123456');
    control.refuser('fn_signer_contrat_otp', { success: false, error_code: 'HASH_DOCUMENT_CHANGE' });
    await page.getByRole('button', { name: 'Signer', exact: true }).click();
    await expect(page.getByText('Le contrat a été modifié depuis votre chargement. Rechargez la page avant de signer.', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Signer', exact: true })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Renvoyer le code', exact: true })).toBeDisabled();
    expect(state.signatures).toHaveLength(0);
    await preuveMission(page, info, 'national-otp-document-refuse');
    await stabiliserActionsNationales(page);
    await page.reload(); await accord.check(); await sms.click(); await code.fill('123456');
    await page.getByRole('button', { name: 'Signer', exact: true }).dblclick();
    await expect(page.getByText('✅ Vous avez déjà signé ce contrat', { exact: true })).toBeVisible();
    expect(state.signatures).toHaveLength(1);
    expect(state.calls.filter(c => c.name === 'fn_signer_contrat_otp')).toHaveLength(2);
    expect(state.contrat.signature_etablissement).toBe(false);
    await preuveMission(page, info, 'national-otp-reprise-unique');
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  } finally { await info.attach('journal-actions-simulees', { body: JSON.stringify(state, null, 2), contentType: 'application/json' }); }
});

test('ACTIONS — pointage de nuit : réseau perdu, relecture lente, pause et code rejoué', async ({ context, page }, info) => {
  const { state, installer, control } = creerActionsNationales();
  state.contratCree = true; state.contrat.statut = 'SIGNE_COMPLET'; state.contrat.signature_soignant = true; state.contrat.signature_etablissement = true;
  state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
  state.mission.debut_le = '2026-09-24T18:00:00.000Z'; state.mission.fin_le = '2026-09-25T06:00:00.000Z';
  state.creneaux[0].debut = state.mission.debut_le; state.creneaux[0].fin = state.mission.fin_le;
  await installer(context, 'SOIGNANT'); await page.clock.setFixedTime(new Date('2026-09-24T18:00:00Z'));
  try {
    await page.goto('/soignant/presences?tab=aujourdhui');
    const code = page.getByRole('textbox', { name: 'Code de pointage à 6 chiffres' });
    await expect(code).toBeVisible(); await code.fill(control.codePointage);
    control.horsLigne = true; await context.setOffline(true);
    await page.getByRole('button', { name: 'Pointer mon arrivée', exact: true }).click();
    await expect(page.getByText('Erreur de connexion. Vérifiez votre accès internet.', { exact: true })).toBeVisible();
    await expect(page.getByText(/Pointage enregistré/)).not.toBeVisible();
    await expect(code).toHaveValue('654321');
    await expect(page.getByRole('button', { name: 'Pointer mon arrivée', exact: true })).toBeEnabled();
    expect(state.segments).toHaveLength(0);
    control.horsLigne = false; await context.setOffline(false);
    const liberer = control.retenir('fn_etat_pointage_mission');
    await page.getByRole('button', { name: 'Pointer mon arrivée', exact: true }).dblclick();
    await expect.poll(() => state.segments.length).toBe(1);
    await expect.poll(() => control.appelsRetenus.includes('fn_etat_pointage_mission')).toBe(true);
    await code.fill(control.codePointage);
    await expect(page.getByRole('button', { name: 'Pointer mon arrivée', exact: true })).toBeDisabled();
    const scansAvant = state.calls.filter(c => c.name === 'fn_scanner_code_pointage').length;
    liberer();
    await expect(page.getByRole('button', { name: 'Pointer mon départ / pause', exact: true })).toBeEnabled();
    await code.fill('654321'); await page.getByRole('button', { name: 'Pointer mon départ / pause', exact: true }).click();
    await expect(page.getByText('Code de pointage invalide ou expiré. Demande le code actuel à l’établissement.', { exact: true })).toBeVisible();
    expect(state.segments[0].fin).toBeNull();
    expect(state.calls.filter(c => c.name === 'fn_scanner_code_pointage')).toHaveLength(scansAvant + 1);
    for (const [instant, label] of [
      ['2026-09-24T23:00:00.000Z', 'Pointer mon départ / pause'],
      ['2026-09-24T23:30:00.000Z', 'Pointer mon arrivée'],
      ['2026-09-25T06:00:00.000Z', 'Pointer mon départ / pause'],
    ]) {
      control.heurePointage = instant; await page.clock.setFixedTime(new Date(instant));
      await code.fill(control.codePointage);
      await page.getByRole('button', { name: label, exact: true }).click();
      if (instant === '2026-09-25T06:00:00.000Z') await page.getByRole('button', { name: 'Plus tard', exact: true }).click();
      await expect(code).toHaveValue('');
    }
    expect(state.segments.map(s => [s.debut, s.fin])).toEqual([
      ['2026-09-24T18:00:00.000Z', '2026-09-24T23:00:00.000Z'],
      ['2026-09-24T23:30:00.000Z', '2026-09-25T06:00:00.000Z'],
    ]);
    expect(state.segments.reduce((ms, s) => ms + Date.parse(s.fin) - Date.parse(s.debut), 0) / 3600000).toBe(11.5);
    await preuveMission(page, info, 'national-pointage-nuit-deux-segments');
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  } finally { await context.setOffline(false); await info.attach('journal-actions-simulees', { body: JSON.stringify(state, null, 2), contentType: 'application/json' }); }
});

test('ACTIONS — candidature : refus de droits, session expirée et reprise sans double demande', async ({ context, page }, info) => {
  const { state, installer, control } = creerActionsNationales();
  await installer(context, 'SOIGNANT'); await page.clock.setFixedTime(new Date(now));
  try {
    await page.goto(`/soignant/missions/${ids.mission}`);
    await page.getByRole('button', { name: /Vérifier et postuler/ }).click();
    const confirmer = page.getByRole('button', { name: 'Envoyer ma candidature', exact: true });
    control.refuser('fn_confirmer_action_planning_v1', { success: false, error: 'Impossible de candidater : autorisation refusée.' });
    await confirmer.click();
    await expect(page.getByText('Impossible de candidater : autorisation refusée.', { exact: true })).toBeVisible();
    expect(state.candidature).toBeNull();
    control.refuser('fn_confirmer_action_planning_v1', { code: 'PGRST301', message: 'JWT expired' }, 401);
    await page.getByRole('button', { name: /Vérifier et postuler/ }).click();
    await confirmer.click();
    await expect(page.getByText(/Session expirée|session a expiré/i)).toBeVisible();
    expect(state.candidature).toBeNull();
    await preuveMission(page, info, 'national-candidature-refus-session');
    // Le service d’authentification de recette est rétabli ; aucune action n’est rejouée automatiquement.
    await page.getByRole('button', { name: /Vérifier et postuler/ }).click();
    await confirmer.dblclick();
    await expect(page.getByText('✅ Candidature envoyée — En attente de réponse', { exact: true })).toBeVisible();
    expect(state.calls.filter(c => c.name === 'fn_confirmer_action_planning_v1')).toHaveLength(3);
    expect(state.candidature.statut).toBe('EN_ATTENTE');
    expect(state.contratCree).toBe(false); expect(state.signatures).toHaveLength(0);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
    await preuveMission(page, info, 'national-candidature-reprise');
  } finally { await info.attach('journal-actions-simulees', { body: JSON.stringify(state, null, 2), contentType: 'application/json' }); }
});
