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
    // Asset unique déclaré dans index.html : simulation CSS vide, aucun appel
    // Google et aucune erreur requestfailed artificiellement ignorée.
    await page.route(url => url.href === 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap', async route => {
      if (route.request().method() !== 'GET') {
        state.unknown.push('Méthode police de simulation inattendue');
        return route.abort();
      }
      return route.fulfill({ contentType: 'text/css', body: '' });
    });
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
        && ['127.0.0.1', 'localhost'].includes(new URL(request.url()).hostname)
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
    let lecturesPlanningContrat = 0;
    let lecturesSuiviContrat = 0;
    const conversationId = '79000000-0000-4000-8000-000000000078';
    const appelsContexte: { nom: string; payload: unknown }[] = [];
    const lecturesPermissions: string[] = [];
    const consoleErrors: string[] = [];
    const failedRequests: string[] = [];
    page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    page.on('requestfailed', request => failedRequests.push(`${request.method()} ${new URL(request.url()).pathname}`));
    await page.route('**/rest/v1/rpc/fn_mes_permissions_etab', async route => {
      const request = route.request();
      const url = new URL(request.url());
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS' };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      const scope = request.postData() === JSON.stringify({ p_etablissement_id: idsEtablissement.etab });
      // useEtabPermissions accepte aussi le scope initial NULL (résolution du
      // compte courant). Garder cet appel, son ledger et la même matrice.
      const initial = request.postData() === JSON.stringify({ p_etablissement_id: null });
      if (request.method() !== 'POST' || request.headers().authorization !== 'Bearer fixture-auth'
        || !['127.0.0.1', 'localhost'].includes(url.hostname) || url.search !== '' || (!scope && !initial)) {
        etat.inconnues.push('Permissions hors établissement de simulation');
        return route.fulfill({ status: 501, headers, json: { error: 'Hors simulation' } });
      }
      etat.appels.push('POST fn_mes_permissions_etab');
      lecturesPermissions.push(scope ? 'scope' : 'initial');
      return route.fulfill({ headers, json: { success: true, etablissement_id: idsEtablissement.etab,
        role: etat.permissions,
        permissions: Object.fromEntries(['gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement',
          'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture'].map(key => [key, etat.permissions === 'PROPRIETAIRE'])),
      } });
    });
    // Contrats exacts des composants montés après attribution : état pointage,
    // conversation vide et affichage de l'interlocuteur. Aucune saisie, message,
    // signature ou scan ; les POST de contexte sont tracés, jamais effacés.
    const rpcsContexte = {
      fn_etat_pointage_mission: { payload: { p_mission_id: idsEtablissement.mission }, reponse: () => ({
        statut: mission.statut, intitule: mission.intitule, prochain_type_scan: 'ARRIVEE', nb_scans: 0,
        segment_ouvert: false, segments: [], code_pointage_actif: null, est_etab: true,
      }) },
      fn_obtenir_conversation: { payload: { p_autre_id: idsEtablissement.soignant, p_mission_id: idsEtablissement.mission }, reponse: () => conversationId },
      fn_interlocuteurs_conversations: { payload: { p_conversation_ids: [conversationId] }, reponse: () => [{
        conversation_id: conversationId, participant_id: idsEtablissement.soignant,
        prenom: 'Camille', nom: 'Spécialité fictive', avatar_url: null, est_jolene: false,
      }] },
      fn_marquer_messages_lus: { payload: { p_conversation_id: conversationId }, reponse: () => null },
      fn_est_bloque: { payload: { p_cible_id: idsEtablissement.soignant }, reponse: () => false },
    };
    await page.route(url => url.pathname.startsWith('/rest/v1/rpc/')
      && Object.hasOwn(rpcsContexte, url.pathname.split('/').pop()!), async route => {
      const request = route.request();
      const url = new URL(request.url());
      const nom = url.pathname.split('/').pop()! as keyof typeof rpcsContexte;
      const attendu = rpcsContexte[nom];
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS' };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      if (request.method() !== 'POST' || request.headers().authorization !== 'Bearer fixture-auth'
        || !['127.0.0.1', 'localhost'].includes(url.hostname)
        || url.search !== '' || mission.statut !== 'ASSIGNEE'
        || request.postData() !== JSON.stringify(attendu.payload)) {
        etat.inconnues.push(`Contexte de mission hors contrat : ${nom}`);
        return route.fulfill({ status: 501, headers, json: { error: 'Hors simulation' } });
      }
      appelsContexte.push({ nom, payload: request.postDataJSON() });
      return route.fulfill({ headers, json: attendu.reponse() });
    });
    await page.route('**/rest/v1/conversations?**', async route => {
      const request = route.request();
      const url = new URL(request.url());
      const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,OPTIONS' };
      if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      if (request.method() !== 'GET' || request.headers().authorization !== 'Bearer fixture-auth'
        || !['127.0.0.1', 'localhost'].includes(url.hostname)
        || mission.statut !== 'ASSIGNEE' || [...url.searchParams].length !== 2
        || url.searchParams.get('select') !== 'archived_at,soignant_id'
        || url.searchParams.get('id') !== `eq.${conversationId}`) {
        etat.inconnues.push('Conversation hors mission de simulation');
        return route.fulfill({ status: 501, headers, json: { error: 'Hors simulation' } });
      }
      return route.fulfill({ headers, json: [{ archived_at: null, soignant_id: idsEtablissement.soignant }] });
    });
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
      const lectureCarte = [...url.searchParams].length === Object.keys(attendu).length
        && Object.entries(attendu).every(([key, value]) => url.searchParams.get(key) === value);
      const lecturePlanning = mission.statut === 'ASSIGNEE' && [...url.searchParams].length === 2
        && url.searchParams.get('select') === 'id,mission_id,statut,cree_le'
        && url.searchParams.get('mission_id') === `eq.${idsEtablissement.mission}`;
      // SuiviMission.tsx : projection distincte de la carte et du planning.
      const lectureSuivi = mission.statut === 'ASSIGNEE' && [...url.searchParams].length === 4
        && url.searchParams.get('select') === 'id,statut,signature_soignant,signature_etablissement'
        && url.searchParams.get('mission_id') === `eq.${idsEtablissement.mission}`
        && url.searchParams.get('order') === 'cree_le.desc' && url.searchParams.get('limit') === '1';
      if (request.method() !== 'GET' || request.headers().authorization !== 'Bearer fixture-auth'
        || !['127.0.0.1', 'localhost'].includes(url.hostname)
        || (!lectureCarte && !lecturePlanning && !lectureSuivi)) {
        etat.inconnues.push('Lecture contrat hors mission de simulation');
        return route.fulfill({ status: 501, headers, json: { error: 'Hors simulation' } });
      }
      if (lecturePlanning) {
        lecturesPlanningContrat++;
        return route.fulfill({ headers, json: contrat ? [{ ...contrat, mission_id: idsEtablissement.mission, cree_le: '2026-10-01T12:00:00Z' }] : [] });
      }
      if (lectureSuivi) {
        lecturesSuiviContrat++;
        return route.fulfill({ headers, json: contrat ? [contrat] : [] });
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
    await expect(page.getByTestId('suivi-resume')).not.toContainText('Vérification du suivi en cours…');
    await expect(page.getByRole('alert').filter({ hasText: 'Une partie du suivi n’a pas pu être chargée' })).toHaveCount(0);
    await preuveEtablissement(page, `${profession}-etab-attribution-contrat-simules-recharge`, info);
    expect(lecturesContrat).toBe(2);
    expect(lecturesPlanningContrat).toBe(1);
    expect(lecturesSuiviContrat).toBe(1);
    expect(appelsContexte.filter(appel => appel.nom === 'fn_obtenir_conversation')).toHaveLength(1);
    expect(appelsContexte.some(appel => appel.nom === 'fn_etat_pointage_mission')).toBe(true);
    expect(lecturesPermissions).toContain('scope');
    expect(etat.ecritures).toEqual([]); expect(etat.operations).toEqual([]);
    expect(etat.erreurs).toEqual([]); expect(etat.inconnues).toEqual([]);
    expect(consoleErrors).toEqual([]); expect(failedRequests).toEqual([]);
    await info.attach('etats-attribution-simules', { body: JSON.stringify({ profession, modeAttribution: 'FIRST_COME',
      refusalExecutedInBrowser: false, realAssignmentVerified: false, contractSigned: false,
      lecturesContrat, lecturesPlanningContrat, lecturesSuiviContrat, appelsContexte, lecturesPermissions }), contentType: 'application/json' });
  });
}
