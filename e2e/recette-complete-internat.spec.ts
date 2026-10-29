import { expect, test } from '@playwright/test';
import { aller, entrer, preuve as preuveSoignant, recharger, sansDebordement, simulerSoignant, profil } from './helpers/recette-complete-soignant';
import { allerA, entrer as entrerEtablissement, ids, preuve, simulerEtablissement, stabiliserLectures } from './helpers/recette-complete-etablissement';
import { simulerCompletionEtablissement } from './helpers/recette-complete-completion-etablissement';

// Vrais écrans, réponses intégralement synthétiques, fournisseurs bloqués.
test('inscription établissement — choix des internes sauvegardé, relu puis retiré du brouillon', async ({ page }, info) => {
  const { etat, state, parcours } = await simulerCompletionEtablissement(page, 'MEDECIN');
  etat.overrides.set('specialites_medicales', [{ code: 'SM01', label: 'Médecine générale', profession_parent: 'MEDECIN', actif: true }]);
  await entrerEtablissement(page, 'inscription');
  await allerA(page, '/etablissement/missions/creer');
  await page.getByLabel('Intitulé *', { exact: true }).fill('Brouillon médical — simulation');
  await page.locator('#mission-profession').click();
  await page.getByRole('option', { name: 'Médecin', exact: true }).click();
  await page.getByRole('combobox').filter({ hasText: 'Toutes spécialités acceptées' }).click();
  await page.getByRole('option', { name: 'Médecine générale', exact: true }).click();
  const accueil = page.getByTestId('mission-accepte-internes');
  await accueil.check();
  await page.getByRole('radio', { name: /^Salarié/ }).check();
  const jour = '2030-10-15';
  await page.getByLabel('Première date affichée *', { exact: true }).fill(jour);
  await page.getByLabel('Dernière date affichée *', { exact: true }).fill(jour);
  await page.getByRole('button', { name: 'Toutes les dates', exact: true }).click();
  await page.getByLabel(`Début du créneau 1 du ${jour}`, { exact: true }).fill('07:00');
  await page.getByLabel(`Fin du créneau 1 du ${jour}`, { exact: true }).fill('19:00');
  await page.getByLabel('Taux horaire brut * (€/h)', { exact: true }).fill('30');
  await page.getByRole('button', { name: 'Publier la mission', exact: true }).click();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  expect(parcours.donnees.missionFormulaire).toMatchObject({ profession: 'MEDECIN', specialite: 'SM01', accepteInternes: true });
  expect(state.mission).toBeNull();
  await allerA(page, '/etablissement/missions/creer');
  await expect(accueil).toBeChecked();
  await stabiliserLectures(page); await page.reload();
  await expect(accueil).toBeChecked();
  await accueil.uncheck();
  await page.getByRole('button', { name: 'Publier la mission', exact: true }).click();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  expect(parcours.donnees.missionFormulaire).not.toHaveProperty('accepteInternes');
  await allerA(page, '/etablissement/missions/creer');
  await expect(accueil).not.toBeChecked();
  await expect(page.getByRole('combobox').filter({ hasText: 'Médecine générale' })).toBeVisible();
  await preuve(page, 'internat-brouillon-choix-retire-relu', info);
  expect(state.mission).toBeNull();
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

test('établissement — accueil explicite des internes, spécialité obligatoire, relecture et duplication sans accord implicite', async ({ page }, info) => {
  const { etat, state } = await simulerCompletionEtablissement(page, 'MEDECIN');
  etat.mode = 'complet';
  Object.assign(state.profil, { statut_verification: 'VERIFIE', est_verifie: true, peut_publier_missions: true, contrat_service_signe: true, contrat_service_statut: 'SIGNE' });
  etat.overrides.set('specialites_medicales', [{ code: 'SM01', label: 'Médecine générale', profession_parent: 'MEDECIN', actif: true }]);
  await entrerEtablissement(page, 'connexion');
  await allerA(page, '/etablissement/missions/creer');
  await page.getByLabel('Intitulé *', { exact: true }).fill('Mission médicale — simulation');
  await page.locator('#mission-profession').click();
  await page.getByRole('option', { name: 'Médecin', exact: true }).click();
  const accueil = page.getByTestId('mission-accepte-internes');
  await expect(accueil).not.toBeChecked();
  await accueil.check();
  await expect(page.getByRole('alert')).toContainText('Choisissez la spécialité de la mission avant d’accepter des internes.');
  await page.getByRole('radio', { name: /^Salarié/ }).check();
  const jour = '2030-10-15';
  await page.getByLabel('Première date affichée *', { exact: true }).fill(jour);
  await page.getByLabel('Dernière date affichée *', { exact: true }).fill(jour);
  await page.getByRole('button', { name: 'Toutes les dates', exact: true }).click();
  await page.getByLabel(`Début du créneau 1 du ${jour}`, { exact: true }).fill('07:00');
  await page.getByLabel(`Fin du créneau 1 du ${jour}`, { exact: true }).fill('19:00');
  await page.getByLabel('Taux horaire brut * (€/h)', { exact: true }).fill('30');
  await expect(page.getByRole('button', { name: 'Publier la mission', exact: true })).toBeDisabled();
  expect(state.mission).toBeNull();
  await page.getByRole('combobox').filter({ hasText: 'Toutes spécialités acceptées' }).click();
  await page.getByRole('option', { name: 'Médecine générale', exact: true }).click();
  await page.getByRole('button', { name: 'Publier la mission', exact: true }).click();
  const recap = page.getByRole('dialog');
  await expect(recap).toContainText('Internes : acceptés sous contrôle des preuves');
  await expect(recap).toContainText('Médecine générale');
  await preuve(page, 'mission-accueil-internes-recap', info);
  await recap.getByRole('button', { name: '📤 Publier', exact: true }).click();
  await expect(page).toHaveURL(/\/etablissement\/missions$/);
  expect(state.mission).toMatchObject({ accepte_internes: true, specialite_medicale_requise: 'SM01' });
  expect(state.appels.filter(a => a.nom === 'fn_creer_mission_multi_jours_v4')).toHaveLength(1);
  await allerA(page, `/etablissement/missions/${ids.mission}/modifier`);
  await expect(accueil).toBeChecked();
  await expect(page.getByRole('combobox').filter({ hasText: 'Médecine générale' })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(accueil).toBeChecked();
  // Le changement visible est enregistré par le même formulaire et relu depuis sa réponse serveur.
  await accueil.uncheck();
  await page.getByRole('button', { name: 'Enregistrer les modifications', exact: true }).click();
  await expect(recap).toContainText('Internes : non acceptés');
  await recap.getByRole('button', { name: '💾 Enregistrer', exact: true }).click();
  await expect(page).toHaveURL(`/etablissement/missions/${ids.mission}`);
  expect(state.mission?.accepte_internes).toBe(false);
  await allerA(page, `/etablissement/missions/${ids.mission}/modifier`);
  await expect(accueil).not.toBeChecked();
  // Préparer une source dont l'accord était actif : la nouvelle mission ne le reprend pas.
  state.mission!.accepte_internes = true;
  await allerA(page, `/etablissement/missions/creer?dupliquer=${ids.mission}`);
  await expect(page.getByText(/Vous dupliquez la mission/)).toBeVisible();
  await expect(accueil).not.toBeChecked();
  await expect(page.getByRole('combobox').filter({ hasText: 'Médecine générale' })).toBeVisible();
  await sansDebordement(page);
  await preuve(page, 'mission-dupliquee-accord-internes-a-renouveler', info);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

test('interne avec RPPS vérifié — licence renouvelable et attestation après internat', async ({ page }, info) => {
  const state = await simulerSoignant(page, 'complet');
  Object.assign(state.profile, { profession: 'MEDECIN', est_etudiant: true, internat_medical_identifie: true, rpps_verifie: true });
  await entrer(page, 'connexion');
  await aller(page, '/soignant/mes-documents?tab=justificatifs');
  const licence = page.locator('.card-base').filter({ has: page.getByText('🩺 Licence de remplacement (interne en médecine)', { exact: true }) });
  await licence.getByRole('button', { name: '+ Téléverser', exact: true }).click();
  const dialogue = page.getByRole('dialog', { name: '📤 Téléverser', exact: true });
  await expect(dialogue).toContainText('Licence de remplacement');
  await expect(dialogue.locator('input[type=file]').first()).toHaveCount(1);
  await dialogue.getByRole('button', { name: 'Fermer la fenêtre de téléversement' }).click();
  await page.getByRole('button', { name: '+ Ajouter l’attestation', exact: true }).click();
  await expect(dialogue).toContainText('Attestation d’inscription à l’Ordre');
  await dialogue.getByRole('button', { name: 'Fermer la fenêtre de téléversement' }).click();
  await recharger(page);
  await expect(licence.getByRole('button', { name: '+ Téléverser', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '+ Ajouter l’attestation', exact: true }).scrollIntoViewIfNeeded();
  await sansDebordement(page);
  await preuveSoignant(page, 'internat-justificatifs-rpps-verifie', info, true);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  expect(state.calls.some(call => call.name === 'verify-document')).toBe(false);
});

test('admin — attestation remplacée, consultation liée à la nouvelle empreinte, décision relue et révocation', async ({ page, context }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  const soignant = { ...profil, id: ids.soignant, profession: 'MEDECIN', est_etudiant: true, internat_medical_identifie: true };
  const doc = { id: '10290000-0000-4000-8000-000000000005', soignant_id: ids.soignant,
    type_document: 'CARTE_ORDRE', nom_fichier: 'attestation-fictive.pdf', statut_verification: 'VERIFIE',
    televerse_le: '2026-10-29T08:00:00Z', s3_bucket: 'jolene-documents', s3_cle: 'fixture/ordre-v1.pdf',
    supprime_le: null, revoque_le: null, valide_jusqua: null };
  let version = 1;
  let decision: string | null = null;
  let tentativesDecision = 0;
  const consultations: string[] = [];
  const decisions: Record<string, unknown>[] = [];
  let revocations = 0;
  const currentReview = () => ({ soignant_id: ids.soignant, numero_rpps: profil.numero_rpps, rpps_verifie: true,
    documents: [{ id: doc.id, nom_fichier: doc.nom_fichier, statut: 'VERIFIE',
      s3_bucket: doc.s3_bucket, s3_cle: `fixture/ordre-v${version}.pdf`, empreinte: `preuve-fictive-v${version}` }],
    decision_id: decision, decision_invalidee: false,
    qualification: decision ? { decision_id: decision, specialite_code: 'SM01', specialite_label: 'Médecine générale' } : null });
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url()), name = url.pathname.split('/').pop();
    if (!['localhost', '127.0.0.1'].includes(url.hostname)) return route.fallback();
    const reply = (json: unknown) => route.fulfill({ json, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    if (req.method() === 'OPTIONS') return route.fallback();
    if (url.pathname.startsWith('/rest/v1/rpc/fn_admin_')) {
      const p = req.postDataJSON();
      if (name === 'fn_admin_lire_qualification_medicale') { expect(p).toEqual({ p_soignant_id: ids.soignant }); return reply(currentReview()); }
      if (name === 'fn_admin_decider_qualification_medicale') {
        expect(consultations.at(-1)).toContain(`/fixture/ordre-v${version}.pdf`);
        expect(p).toEqual({ p_soignant_id: ids.soignant, p_document_id: doc.id,
          p_preuve_empreinte: `preuve-fictive-v${version}`, p_decision_attendue: null, p_specialite_code: 'SM01',
          p_numero_rpps_lu: profil.numero_rpps, p_inscription_confirmee: true, p_qualification_confirmee: true,
          p_motif: 'Attestation fictive examinée pour le scénario de simulation.' });
        if (++tentativesDecision === 1) {
          version = 3;
          return route.fulfill({ status: 409, json: { code: '40001', message: 'La preuve a changé : rechargez la revue.' }, headers: { 'access-control-allow-origin': '*' } });
        }
        decisions.push(p); decision = 'decision-fictive'; return reply(currentReview());
      }
      if (name === 'fn_admin_revoquer_qualification_medicale') {
        expect(p.p_decision_id).toBe('decision-fictive'); revocations++; decision = null; return reply(currentReview());
      }
    }
    if (url.pathname.startsWith('/storage/v1/object/sign/')) {
      expect(req.method()).toBe('POST'); consultations.push(url.pathname);
      return reply({ signedURL: '/object/sign/attestation-fictive-lisible' });
    }
    if (url.pathname.startsWith('/rest/v1/') && req.method() === 'GET') {
      const object = req.headers().accept?.includes('object');
      if (name === 'soignants') return reply(object ? soignant : [soignant]);
      // Keep the parent document snapshot stale to exercise the source/empreinte regression.
      if (name === 'documents_soignants') return reply([doc]);
      if (name === 'documents_requis_par_profession' || name === 'emails_envoyes') return reply([]);
      if (name === 'specialites_medicales') return reply([{ code: 'SM01', label: 'Médecine générale', profession_parent: 'MEDECIN' }]);
    }
    return route.fallback();
  });
  await context.route('**/storage/v1/object/sign/attestation-fictive-lisible', route => route.fulfill({ contentType: 'text/html', body: '<p>Attestation fictive de simulation</p>' }));
  await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
    user: { id, email: 'admin@example.invalid', email_confirmed_at: '2026-10-01T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
    access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now()/1000)+3600,
  })), { id: ids.user });
  await page.goto(`/admin/utilisateurs/${ids.soignant}`);
  await page.getByRole('tab', { name: 'Documents', exact: true }).click();
  const section = page.getByRole('region', { name: 'Qualification après internat', exact: true });
  await expect(section).toBeVisible();
  const approve = section.getByRole('button', { name: 'Confirmer la qualification après internat', exact: true });
  await expect(approve).toBeDisabled();
  await section.getByLabel('Attestation examinée').selectOption(doc.id);
  version = 2;
  await section.getByRole('button', { name: 'Actualiser la revue', exact: true }).click();
  await expect(section.getByRole('button', { name: 'Actualiser la revue', exact: true })).toBeEnabled();
  const popupPromise = page.waitForEvent('popup');
  await section.getByRole('button', { name: 'Consulter l’attestation', exact: true }).click();
  const popup = await popupPromise;
  await expect(popup).toHaveURL(/attestation-fictive-lisible$/); await popup.close();
  await section.getByLabel('RPPS lu sur l’attestation').fill(profil.numero_rpps);
  await section.getByRole('combobox').filter({ hasText: 'Sélectionnez une spécialité' }).click();
  await page.getByRole('option', { name: 'Médecine générale', exact: true }).click();
  await section.getByRole('checkbox', { name: /contrôlé l’inscription actuelle/ }).check();
  await section.getByRole('checkbox', { name: /attestation établit la qualification/ }).check();
  await section.getByLabel(/Motif documenté/).fill('Attestation fictive examinée pour le scénario de simulation.');
  await expect(approve).toBeEnabled(); await approve.click();
  await expect(section.getByText(/Rechargez la revue avant toute autre décision/)).toBeVisible();
  await expect(approve).toBeDisabled();
  expect(decisions).toHaveLength(0);
  await section.getByRole('button', { name: 'Actualiser la revue', exact: true }).click();
  await expect(section.getByRole('button', { name: 'Actualiser la revue', exact: true })).toBeEnabled();
  const nouvellePiecePromise = page.waitForEvent('popup');
  await section.getByRole('button', { name: 'Consulter l’attestation', exact: true }).click();
  const nouvellePiece = await nouvellePiecePromise;
  await expect(nouvellePiece).toHaveURL(/attestation-fictive-lisible$/); await nouvellePiece.close();
  await section.getByRole('checkbox', { name: /contrôlé l’inscription actuelle/ }).check();
  await section.getByRole('checkbox', { name: /attestation établit la qualification/ }).check();
  await expect(approve).toBeEnabled(); await approve.click();
  await expect(section.getByText('Qualification confirmée : Médecine générale.', { exact: true })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await page.getByRole('tab', { name: 'Documents', exact: true }).click();
  await expect(section.getByText('Qualification confirmée : Médecine générale.', { exact: true })).toBeVisible();
  await section.getByLabel(/Motif documenté/).fill('Révocation fictive après examen dans le scénario de simulation.');
  await section.getByRole('checkbox', { name: /confirme la révocation/ }).check();
  await section.getByRole('button', { name: 'Révoquer la décision de qualification', exact: true }).click();
  await expect(section.getByText('Décision révoquée et état relu.', { exact: true })).toBeVisible();
  expect(tentativesDecision).toBe(2); expect(decisions).toHaveLength(1); expect(revocations).toBe(1);
  await preuve(page, 'qualification-apres-internat-revoquee', info);
  expect(await page.evaluate(() => document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(1);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
});
