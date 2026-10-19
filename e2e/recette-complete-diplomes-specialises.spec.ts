import { test, expect } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, attendreAPI, preuve, sansDebordement, ids } from './helpers/recette-complete-soignant';
import {
  simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures,
  preuve as preuveEtablissement, ids as idsEtablissement, mission as missionEtablissement,
} from './helpers/recette-complete-etablissement';

// Réponses fictives uniquement : ni Annuaire, ni IA, ni Storage, ni attribution
// réelle. La qualification serveur est prouvée séparément par le témoin SQL.
for (const profession of ['IADE', 'IBODE']) {
  test(`SOIGNANT ${profession} — diplôme spécialisé requis, reprise et RPPS conservé`, async ({ page }, info) => {
    const state = await simulerSoignant(page);
    Object.assign(state.profile, { profession, rpps_verifie: true, tous_documents_valides: true });
    state.tables.set('documents_requis_par_profession', ['DIPLOME', 'RPPS_ADELI'].map(type_document => ({
      id: `${profession}-${type_document}`, profession, type_document, type_exercice_requis: 'TOUS', est_critique: true,
    })));
    const documents: Record<string, any>[] = [];
    state.tables.set('documents_soignants', documents);
    const consoleErrors: string[] = [];
    const failedRequests: string[] = [];
    page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    page.on('requestfailed', request => failedRequests.push(`${request.method()} ${new URL(request.url()).pathname}`));
    let verifications = 0;
    await page.route('**/functions/v1/verify-document', async route => {
      const request = route.request();
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS' };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      const expected = request.method() === 'POST'
        && request.headers().authorization === 'Bearer fixture-auth'
        && request.postData() === JSON.stringify({ document_id: 'diplome-specialise-simule' })
        && verifications === 0 && documents.length === 1;
      if (!expected) { state.unknown.push('Vérification hors contrat de simulation'); return route.fulfill({ status: 501, headers, json: { error: 'Hors simulation' } }); }
      verifications++;
      // Le service simulé requalifie le document ; aucun contrôle officiel n’est
      // revendiqué par cette réponse ni par le badge RPPS déjà présent.
      documents[0].profession_certifiee = profession;
      return route.fulfill({ headers, json: { verdict: 'VERIFIE' } });
    });

    await entrer(page, 'connexion');
    await expect(page.getByText('RPPS Vérifié', { exact: true })).toBeVisible();
    const checklist = page.getByRole('button', { name: /prochaine étape : Tes documents$/ });
    await expect(checklist).toBeVisible();
    await expect(checklist).toContainText('Il te reste 1 document');
    await checklist.click();
    await expect(page).toHaveURL(/\/soignant\/mes-documents$/);
    await expect(page.getByRole('heading', { name: "Diplôme d'État", exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Attestation RPPS / ADELI', exact: true })).toHaveCount(0);
    await page.getByRole('button', { name: "Téléverser — Diplôme d'État", exact: true }).click();
    const dialog = page.getByRole('dialog', { name: '📤 Téléverser', exact: true });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Téléverser', exact: true })).toBeDisabled();
    await dialog.getByRole('button', { name: 'Annuler', exact: true }).click();
    await expect(dialog).toHaveCount(0);
    await recharger(page);
    await expect(page.getByRole('heading', { name: "Diplôme d'État", exact: true })).toBeVisible();

    // Un diplôme IDE historiquement VERIFIE ne suffit pas à confirmer IADE/IBODE.
    documents.push({ id: 'diplome-specialise-simule', soignant_id: ids.user, type_document: 'DIPLOME',
      nom_fichier: 'DIPLOME-FICTIF.pdf', statut_verification: 'VERIFIE', profession_certifiee: 'IDE',
      televerse_le: '2026-10-01T12:00:00Z', valide_jusqua: null, supprime_le: null, revoque_le: null });
    await recharger(page);
    await expect(page.getByRole('status').filter({ hasText: `La qualification ${profession}` })).toBeVisible();
    await expect(page.getByText(/Tous tes documents obligatoires sont à jour/)).toHaveCount(0);
    await page.getByRole('button', { name: 'Remplacer', exact: true }).click();
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Annuler', exact: true }).click();
    await sansDebordement(page);
    await preuve(page, `${profession}-diplome-ide-insuffisant`, info, true);
    await page.getByRole('button', { name: 'Revérifier', exact: true }).click();
    await expect(page.getByText(/Tous tes documents obligatoires sont à jour/)).toBeVisible();
    await recharger(page);
    await expect(page.getByText(/Tous tes documents obligatoires sont à jour/)).toBeVisible();
    await expect(page.getByRole('status').filter({ hasText: `La qualification ${profession}` })).toHaveCount(0);
    await preuve(page, `${profession}-diplome-specialise-confirme-simulation`, info, true);
    await aller(page, '/soignant/tableau-de-bord');
    await expect(page.getByText('RPPS Vérifié', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: /prochaine étape : Tes documents$/ })).toHaveCount(0);
    await attendreAPI(page);
    expect(verifications).toBe(1);
    expect(state.profile.rpps_verifie).toBe(true);
    expect(state.calls.filter(call => /storage|generate-invoice|accepter_mission|signer_contrat/.test(call.name))).toEqual([]);
    expect(state.unknown).toEqual([]);
    expect(state.errors).toEqual([]);
    expect(consoleErrors).toEqual([]);
    expect(failedRequests).toEqual([]);
    await info.attach('simulation-diplome-specialise', { body: JSON.stringify({ profession, verifications, officialIdentityVerified: false, assignmentVerified: false, calls: state.calls }), contentType: 'application/json' });
  });
}

for (const profession of ['IADE', 'IBODE']) {
  test(`ETABLISSEMENT ${profession} — états FIRST_COME sans attribution puis contrat, réponses simulées`, async ({ page }, info) => {
    const { etat } = await simulerEtablissement(page);
    etat.donnees = true;
    const mission = { ...missionEtablissement, profession_requise: profession,
      intitule: `Mission ${profession} — diplôme spécialisé simulé`, mode_attribution: 'FIRST_COME',
      statut: 'OUVERTE', type_contrat_applique: null as string | null, soignant_assigne_id: null as string | null };
    etat.overrides.set('fn_alerte_cddu_repetitif', { alerte: false });
    // maybeSingle transforme normalement une réponse vide [] en null ; ne pas
    // fabriquer un HTTP406 dans ce scénario où aucun contrat employeur n'existe.
    etat.overrides.set('contrats_travail_missions', []);
    etat.overrides.set('fn_soignant_pour_etablissement', { id: idsEtablissement.soignant, prenom: 'Camille', nom: 'Spécialité fictive', profession, score_fiabilite: null, total_missions_terminees: 0 });
    let contrat: Record<string, unknown> | null = null;
    let lecturesContrat = 0;
    const consoleErrors: string[] = [];
    const failedRequests: string[] = [];
    page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    page.on('requestfailed', request => failedRequests.push(`${request.method()} ${new URL(request.url()).pathname}`));
    await page.route('**/rest/v1/contrats_mission?**', async route => {
      const request = route.request();
      const url = new URL(request.url());
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,OPTIONS' };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      const attendu: Record<string, string> = {
        select: 'id,numero_contrat,statut,signature_soignant,signature_etablissement',
        mission_id: `eq.${idsEtablissement.mission}`,
        statut: 'in.(BROUILLON,EN_ATTENTE_SIGNATURES,SIGNE_SOIGNANT,SIGNE_ETABLISSEMENT,SIGNE_COMPLET)',
        order: 'cree_le.desc', limit: '1',
      };
      if (request.method() !== 'GET' || request.headers().authorization !== 'Bearer fixture-auth'
        || [...url.searchParams].length !== Object.keys(attendu).length
        || !Object.entries(attendu).every(([key, value]) => url.searchParams.get(key) === value)) {
        etat.inconnues.push('Lecture contrat hors mission de simulation');
        return route.fulfill({ status: 501, headers, json: { error: 'Hors simulation' } });
      }
      lecturesContrat++;
      return route.fulfill({ headers, json: contrat });
    });

    await entrerEtablissement(page, 'connexion');
    // Le dashboard vient de terminer ses lectures de liste (array). Le détail
    // qui suit lit une mission unique (object), sans modifier le banc partagé.
    etat.overrides.set('missions', mission);
    await allerA(page, `/etablissement/missions/${idsEtablissement.mission}`);
    await expect(page.getByRole('heading', { name: mission.intitule, exact: true })).toBeVisible();
    // FIRST_COME appartient à l’action du soignant. Aucun bouton employeur
    // d’acceptation n’est inventé ici. Le refus réel est testé sous rollback SQL.
    await expect(page.getByText("En attente d'un soignant", { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Accepter cette candidature', exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Ouvrir et signer le contrat', exact: true })).toHaveCount(0);
    await stabiliserLectures(page);
    expect(contrat).toBeNull(); expect(mission.soignant_assigne_id).toBeNull();
    await preuveEtablissement(page, `${profession}-etab-apres-refus-simule`, info);

    // Transition de réponse serveur explicitement simulée APRÈS une preuve
    // spécialisée exacte. Elle ne démontre pas que le navigateur qualifie ou
    // attribue une mission : ces deux gardes sont exercées dans le témoin SQL.
    mission.statut = 'ASSIGNEE'; mission.soignant_assigne_id = idsEtablissement.soignant;
    mission.type_contrat_applique = 'SALARIE';
    contrat = { id: '79000000-0000-4000-8000-000000000079', numero_contrat: `SIM-${profession}-SPECIALISE`,
      statut: 'EN_ATTENTE_SIGNATURES', signature_soignant: false, signature_etablissement: false };
    await stabiliserLectures(page); await page.reload();
    await expect(page.getByRole('heading', { name: mission.intitule, exact: true })).toBeVisible();
    await expect(page.getByText("En attente d'un soignant", { exact: true })).toHaveCount(0);
    await expect(page.getByRole('link', { name: 'Camille Spécialité fictive', exact: true })).toBeVisible();
    await expect(page.getByText('Contrat électronique Jolene', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Ouvrir et signer le contrat', exact: true })).toBeVisible();
    await stabiliserLectures(page);
    await preuveEtablissement(page, `${profession}-etab-attribution-contrat-simules-recharge`, info);
    expect(lecturesContrat).toBe(2);
    expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
    expect(etat.erreurs).toEqual([]); expect(etat.inconnues).toEqual([]);
    expect(consoleErrors).toEqual([]); expect(failedRequests).toEqual([]);
    await info.attach('etats-attribution-simules', { body: JSON.stringify({ profession, modeAttribution: 'FIRST_COME',
      refusalExecutedInBrowser: false, realAssignmentVerified: false, contractSigned: false, lecturesContrat }), contentType: 'application/json' });
  });
}
