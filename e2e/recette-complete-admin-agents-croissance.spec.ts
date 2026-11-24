import { expect, test, type Page } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Réponses backend simulées : aucun brouillon réel, aucun email, aucun appel, aucun CRM réel.
// Le serveur simulé garde l'état des brouillons pour prouver la reprise après rechargement.

type Statut = 'BROUILLON' | 'VALIDE' | 'REJETE' | 'ENVOYE' | 'EXPIRE';
interface Brouillon {
  id: string; agent: string; canal: string; cible_type: string; cible_id: string | null;
  destinataire_nom: string | null; destinataire_email: string | null; departement: string | null;
  profession: string | null; sequence_etape: number | null; sujet: string | null; corps: string;
  lien: string | null; contexte: Record<string, unknown>; score: number | null; statut: Statut;
  motif_rejet: string | null; cree_le: string; expire_le: string | null; valide_le: string | null; envoye_le: string | null;
}

const base = { cible_id: null, score: null, motif_rejet: null, cree_le: '2026-11-08T05:50:00Z', expire_le: '2026-11-22T05:50:00Z', valide_le: null, envoye_le: null, lien: null, sequence_etape: null, profession: null, sujet: null } as const;

function fixtures(): Brouillon[] {
  return [
    {
      ...base, id: '99110000-0000-4000-8000-000000000001', agent: 'PROSPECTION_ETABLISSEMENT', canal: 'EMAIL',
      cible_type: 'PROSPECT_ETABLISSEMENT', cible_id: '560000001', destinataire_nom: 'EHPAD Les Tilleuls — recette',
      destinataire_email: 'contact@ehpad-tilleuls.example.invalid', departement: '56', sequence_etape: 1, score: 67,
      sujet: 'Renforts soignants pour EHPAD Les Tilleuls — recette',
      corps: 'Bonjour,\n\nJe suis Gabrielle, fondatrice de Jolene.\n\nVos coordonnées professionnelles proviennent des annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé). Si vous ne souhaitez plus être contacté par Jolene, répondez simplement « STOP » à cet email : nous ne vous écrirons plus.',
      contexte: { type_etablissement: 'EHPAD', ville: 'Lorient', score: { signal_boamp_90j: 0 }, bmo_as: { difficulte_pct: 74, projets: 971, annee: 2026 } },
      statut: 'BROUILLON',
    },
    {
      ...base, id: '99110000-0000-4000-8000-000000000002', agent: 'PROSPECTION_ETABLISSEMENT', canal: 'EMAIL',
      cible_type: 'PROSPECT_ETABLISSEMENT', cible_id: '920000002', destinataire_nom: 'Centre de santé Opposition — recette',
      destinataire_email: 'rh@centre-opposition.example.invalid', departement: '92', sequence_etape: 1, score: 45,
      sujet: 'Renforts soignants pour Centre de santé Opposition — recette', corps: 'Bonjour,\n\nMessage de recette.',
      contexte: { type_etablissement: 'CENTRE_SANTE', ville: 'Nanterre', score: {} }, statut: 'BROUILLON',
    },
    {
      ...base, id: '99110000-0000-4000-8000-000000000003', agent: 'POST_SOCIAL', canal: 'FACEBOOK_GROUPE',
      cible_type: 'PUBLIC', departement: '75', profession: 'AS',
      corps: 'Aides-soignants du 75 : inscrivez-vous gratuitement sur Jolene et soyez prévenu dès qu’un établissement proche de chez vous publie une mission.',
      contexte: { semaine: '2026-S45', groupes_suggeres: [{ nom: 'Aides-soignants Île-de-France — recette', url: 'https://www.facebook.com/groups/recette', membres: 12000 }] },
      statut: 'BROUILLON',
    },
  ];
}

const SCRIPT_APPEL = [
  'Bonjour, Gabrielle, fondatrice de Jolene. Pourrais-je parler à la personne qui organise les remplacements de soignants ?',
  'Jolene est une plateforme de mise en relation directe entre les établissements de santé et des soignants vérifiés, pour des missions et remplacements ponctuels.',
  'Vous publiez votre besoin, des soignants vérifiés candidatent, et le contrat est signé en ligne.',
  'Jolene facture à l\'établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée, majorations et indemnités incluses lorsqu’elles entrent dans cette base. Il n’y a ni abonnement ni frais d’entrée : vous ne payez que lorsque vous recrutez.',
  'Nous démarrons dans votre secteur : je vous propose de publier votre première mission avec vous, au téléphone. Auriez-vous quinze minutes cette semaine ?',
  'Si vous préférez ne pas être rappelé, dites-le-moi : je le note et Jolene ne vous rappellera plus.',
].join('\n\n');

const ID_APPEL = '99110000-0000-4000-8000-000000000011';
const ID_APPEL_OPPOSITION = '99110000-0000-4000-8000-000000000012';
const ID_APPEL_STOP = '99110000-0000-4000-8000-000000000013';

function fichesAppel(): Brouillon[] {
  const fiche = { ...base, agent: 'APPEL_ETABLISSEMENT', canal: 'TELEPHONE', cible_type: 'PROSPECT_ETABLISSEMENT', destinataire_email: null, corps: SCRIPT_APPEL, statut: 'BROUILLON' as Statut, cree_le: '2026-11-24T05:50:00Z', expire_le: '2026-12-08T05:50:00Z' };
  return [
    { ...fiche, id: ID_APPEL, cible_id: '750000011', destinataire_nom: 'EHPAD Les Glycines — recette', departement: '75', score: 40,
      contexte: { type_etablissement: 'EHPAD', ville: 'Paris', telephone: '01 00 00 10 01', semaine: '2026-S48', score: { type: 40, signal_boamp_90j: 0, tension_bmo_as: 0 } } },
    { ...fiche, id: ID_APPEL_OPPOSITION, cible_id: '920000012', destinataire_nom: 'Hôpital Opposition — recette', departement: '92', score: 35,
      contexte: { type_etablissement: 'HOPITAL', ville: 'Nanterre', telephone: '01 00 00 10 02', semaine: '2026-S48', score: { type: 35, signal_boamp_90j: 0, tension_bmo_as: 0 } } },
    { ...fiche, id: ID_APPEL_STOP, cible_id: '560000013', destinataire_nom: 'SSIAD du Port — recette', departement: '56', score: 25,
      contexte: { type_etablissement: 'DOMICILE', ville: 'Lorient', telephone: '02.00.00.10.03', semaine: '2026-S48', score: { type: 25, signal_boamp_90j: 0, tension_bmo_as: 0 } } },
  ];
}

// Constat de production du 20/11/2026 (lecture seule) : aucune adresse utilisable, 2 017 téléphones.
const cibles = {
  departements: ['56', '75', '92'], etablissements_cibles: 2318, adresses_fermees: 656,
  adresses_utilisables: 0, adresses_restantes: 0, telephones_utilisables: 2017, telephones_restants: 2017,
};
const RESULTATS_APPEL = ['APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE', 'A_RAPPELER', 'PAS_INTERESSE', 'STOP'];

const entonnoir = {
  periode: { debut: '2026-11-01T11:00:00Z', fin: '2026-11-08T11:00:00Z' }, genere_le: '2026-11-08T11:00:00Z', cohorte: 'REELLE',
  soignants: { inscrits_total: 2, inscrits_periode: 0, avec_document: 1, documents_valides: 1, onboarding_termine: 0, ayant_candidate: 0, ayant_realise_mission: 0, actifs_periode: 0 },
  etablissements: { inscrits_total: 0, inscrits_periode: 0, peuvent_publier: 0, ayant_publie: 0 },
  missions: { publiees_periode: 0, pourvues_periode: 0, terminees_periode: 0, ouvertes_a_venir: 0, ouvertes_sans_candidature: 0, candidatures_periode: 0 },
  prospection: { prospects_etablissements: 64058, prospects_avec_email: 30633, prospects_contactes_total: 0, emails_journalises_periode: 0, crm_par_statut: {}, crm_reponses_positives: 0, crm_stop: 0 },
  agents: { crees_periode: 23, valides_periode: 0, envoyes_periode: 0, rejetes_periode: 0, en_attente: 23, par_agent: {} },
  sources_inscriptions_periode: {}, exclus_cohorte_test: { soignants_test: 1100, etablissements_test: 917 },
};

async function simulerAgents(page: Page, { appels = false }: { appels?: boolean } = {}) {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  const brouillons = appels ? fichesAppel() : fixtures();
  const decisions: Array<{ p_id: string; p_action: string; p_sujet: string | null }> = [];
  const resultats: Array<{ p_id: string; p_motif: string | null }> = [];
  // Passage automatique du matin : l'agent email ne prépare rien et le dit, l'agent d'appels a préparé trois fiches.
  let executions: Array<Record<string, unknown>> = appels ? [
    { id: 11, agent: 'APPEL_ETABLISSEMENT', declencheur: 'CRON', debut_le: '2026-11-24T05:50:01Z', brouillons_crees: 3, erreur: null, details: { fiches_appel: 3, places_de_la_semaine: 30 } },
    { id: 10, agent: 'PROSPECTION_ETABLISSEMENT', declencheur: 'CRON', debut_le: '2026-11-24T05:50:00Z', brouillons_crees: 0, erreur: null, details: { premiers_contacts: 0, places_du_jour: 20, cibles } },
  ] : [];
  const rapports = appels ? [{ semaine_debut: '2026-11-16', donnees: { ...entonnoir, prospection: { ...entonnoir.prospection, appels_journalises_periode: 2, cibles_agent: cibles } } }] : [];
  let lancements = 0;
  let planifActive = false;
  const bascules: Array<boolean | null> = [];
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-expose-headers': 'content-range' };

  await page.route('**/rest/v1/growth_brouillons**', async (route) => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors, body: '' });
    expect(route.request().method()).toBe('GET');
    const url = new URL(route.request().url());
    const filtre = url.searchParams.get('statut') ?? '';
    const statuts = filtre.replace(/^in\.\(/, '').replace(/\)$/, '').split(',');
    const agent = url.searchParams.get('agent')?.replace(/^eq\./, '');
    const rows = brouillons.filter((b) => statuts.includes(b.statut) && (!agent || b.agent === agent));
    return route.fulfill({ json: rows, headers: { ...cors, 'content-range': rows.length ? `0-${rows.length - 1}/${rows.length}` : '*/0' } });
  });
  await page.route('**/rest/v1/growth_rapports_hebdo**', (route) => route.fulfill({ json: rapports, headers: { ...cors, 'content-range': rapports.length ? `0-${rapports.length - 1}/${rapports.length}` : '*/0' } }));
  await page.route('**/rest/v1/growth_agent_executions**', (route) => {
    // Mêmes filtres que PostgREST : agent, exécutions sans erreur, limite (lignes déjà triées du plus récent au plus ancien).
    const url = new URL(route.request().url());
    const agent = url.searchParams.get('agent')?.replace(/^eq\./, '');
    const sansErreur = url.searchParams.get('erreur') === 'is.null';
    const limite = Number(url.searchParams.get('limit') ?? '100');
    const rows = executions.filter((e) => (!agent || e.agent === agent) && (!sansErreur || e.erreur === null)).slice(0, limite);
    return route.fulfill({ json: rows, headers: cors });
  });
  await page.route('**/rest/v1/rpc/fn_admin_growth_entonnoir', async (route) => {
    expect(route.request().postDataJSON()).toEqual({ p_jours: 7 });
    return route.fulfill({ json: entonnoir, headers: cors });
  });
  await page.route('**/rest/v1/rpc/fn_admin_growth_planification', async (route) => {
    const p = route.request().postDataJSON();
    bascules.push(p.p_actif);
    if (p.p_actif !== null) planifActive = p.p_actif;
    const jobs = ['jolene_growth_agents_quotidien', 'jolene_growth_rapport_hebdo'].map((jobname) => ({ jobname, schedule: jobname.endsWith('hebdo') ? '15 5 * * 1' : '50 5 * * *', active: planifActive }));
    return route.fulfill({ json: { actif: planifActive, pg_cron: true, jobs }, headers: cors });
  });
  await page.route('**/rest/v1/rpc/fn_admin_growth_executer_agents', async (route) => {
    lancements++;
    executions = ['PROSPECTION_ETABLISSEMENT', 'APPEL_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'].map((agent, i) => ({
      id: i + 1, agent, declencheur: 'ADMIN', debut_le: '2026-11-08T11:05:00Z', brouillons_crees: agent === 'PROSPECTION_ETABLISSEMENT' ? 20 : agent === 'POST_SOCIAL' ? 7 : 0, erreur: null,
    }));
    return route.fulfill({ json: { declencheur: 'ADMIN', expires: 0, agents: {
      PROSPECTION_ETABLISSEMENT: { brouillons_crees: 20 }, APPEL_ETABLISSEMENT: { brouillons_crees: 0 }, POST_SOCIAL: { brouillons_crees: 7 },
      MISSION_A_POURVOIR: { brouillons_crees: 0 }, REACTIVATION: { brouillons_crees: 0 } } }, headers: cors });
  });
  await page.route('**/rest/v1/rpc/fn_admin_growth_brouillon_decider', async (route) => {
    const p = route.request().postDataJSON();
    decisions.push({ p_id: p.p_id, p_action: p.p_action, p_sujet: p.p_sujet });
    const b = brouillons.find((x) => x.id === p.p_id)!;
    if (b.canal === 'TELEPHONE') {
      // Fiche d'appel : opposition revérifiée à la validation, résultat exigé au constat (comme le décideur SQL).
      if (p.p_action === 'VALIDER' && b.id === ID_APPEL_OPPOSITION) {
        b.statut = 'REJETE'; b.motif_rejet = 'Opposition (STOP) ou contact perdu';
        return route.fulfill({ json: { success: false, id: b.id, statut: 'REJETE', raison: 'Contact en opposition (STOP) ou perdu : ne pas appeler' }, headers: cors });
      }
      if (p.p_action === 'MARQUER_ENVOYE') {
        resultats.push({ p_id: p.p_id, p_motif: p.p_motif });
        if (b.statut !== 'VALIDE' || !RESULTATS_APPEL.includes(p.p_motif)) {
          return route.fulfill({ status: 400, json: { code: 'P0001', message: 'Résultat d\'appel requis : APPEL_REPONDU, SANS_REPONSE, INTERESSE, A_RAPPELER, PAS_INTERESSE ou STOP' }, headers: cors });
        }
        b.statut = 'ENVOYE'; b.envoye_le = '2026-11-24T09:12:00Z'; b.contexte = { ...b.contexte, resultat_appel: p.p_motif };
        return route.fulfill({ json: { success: true, id: b.id, statut: 'ENVOYE', contact_crm_id: '99110000-0000-4000-8000-0000000000c2' }, headers: cors });
      }
    }
    if (p.p_action === 'VALIDER' && b.destinataire_email?.startsWith('rh@centre-opposition')) {
      b.statut = 'REJETE'; b.motif_rejet = 'Opposition (STOP) ou contact perdu';
      return route.fulfill({ json: { success: false, id: b.id, statut: 'REJETE', raison: 'Contact en opposition (STOP) ou perdu : aucun envoi possible' }, headers: cors });
    }
    if (p.p_action === 'VALIDER') { b.statut = 'VALIDE'; b.valide_le = '2026-11-08T11:10:00Z'; if (p.p_sujet) b.sujet = p.p_sujet; }
    if (p.p_action === 'MARQUER_ENVOYE') { b.statut = 'ENVOYE'; b.envoye_le = '2026-11-08T11:12:00Z'; }
    if (p.p_action === 'REJETER') { b.statut = 'REJETE'; b.motif_rejet = p.p_motif; }
    return route.fulfill({ json: { success: true, id: b.id, statut: b.statut, contact_crm_id: p.p_action === 'MARQUER_ENVOYE' ? '99110000-0000-4000-8000-0000000000c1' : null }, headers: cors });
  });

  await page.addInitScript(({ id }) => {
    sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-28T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    }));
    // Aucune fenêtre externe : on capture l'URL Gmail au lieu de l'ouvrir.
    (window as unknown as { __ouverts: string[] }).__ouverts = [];
    window.open = ((url?: string | URL) => { (window as unknown as { __ouverts: string[] }).__ouverts.push(String(url)); return null; }) as typeof window.open;
  }, { id: ids.user });
  return { etat, brouillons, decisions, resultats, lancements: () => lancements, bascules };
}

test('admin — agents de croissance : file, validation Gmail, constat d’envoi, opposition, reprise, entonnoir', async ({ page }, info) => {
  const sim = await simulerAgents(page);
  await page.goto('/admin/fondateur/agents');

  // État 1 — file à valider, rien n'est parti.
  await expect(page.getByRole('heading', { name: 'Agents de croissance', exact: true })).toBeVisible();
  await expect(page.getByText(/Aucun envoi automatique\./)).toBeVisible();
  const cartes = page.getByTestId('brouillon-croissance');
  await expect(cartes).toHaveCount(3);
  const tilleuls = cartes.filter({ hasText: 'EHPAD Les Tilleuls — recette' });
  await expect(tilleuls.getByText('Pourquoi : EHPAD · Lorient · dépt 56 · recrutement AS jugé difficile à 74 % (BMO)', { exact: true })).toBeVisible();
  await expect(tilleuls.getByText('À valider', { exact: true })).toBeVisible();
  await expect(tilleuls.getByText('Étape 1/3', { exact: true })).toBeVisible();
  await expect(tilleuls.getByRole('button', { name: 'Valider et ouvrir Gmail' })).toBeEnabled();
  await expect(tilleuls.getByLabel('Message')).toHaveValue(/\(répertoire FINESS et Annuaire Santé\)[\s\S]*« STOP »/);
  const post = cartes.filter({ hasText: 'Aides-soignants du 75' });
  await expect(post.getByRole('link', { name: 'Aides-soignants Île-de-France — recette' })).toHaveAttribute('href', 'https://www.facebook.com/groups/recette');
  await expect(post.getByRole('button', { name: 'Valider et copier' })).toBeEnabled();
  await expect(page.locator('a[href="/admin/fondateur/agents"]').first()).toBeAttached();
  await preuve(page, 'agents-croissance-file', info);

  // État 2 — objet modifié, validation, Gmail pré-rempli (sans ouverture réelle).
  await tilleuls.getByLabel('Objet').fill('Renforts pour vos absences — Jolene');
  await tilleuls.getByRole('button', { name: 'Valider et ouvrir Gmail' }).click();
  await expect(tilleuls.getByText('Validé, à envoyer', { exact: true })).toBeVisible();
  await expect(tilleuls.getByRole('button', { name: 'J’ai envoyé' })).toBeVisible();
  const ouverts = await page.evaluate(() => (window as unknown as { __ouverts: string[] }).__ouverts);
  expect(ouverts).toHaveLength(1);
  expect(ouverts[0]).toContain('https://mail.google.com/mail/?view=cm&fs=1&to=contact%40ehpad-tilleuls.example.invalid');
  expect(ouverts[0]).toContain('&su=Renforts%20pour%20vos%20absences%20%E2%80%94%20Jolene');
  expect(sim.decisions.at(-1)).toEqual({ p_id: '99110000-0000-4000-8000-000000000001', p_action: 'VALIDER', p_sujet: 'Renforts pour vos absences — Jolene' });
  await preuve(page, 'agents-croissance-valide', info);

  // État 3 — opposition arrivée entre-temps : rejet affiché, la carte quitte la file.
  const opposition = cartes.filter({ hasText: 'Centre de santé Opposition — recette' });
  await opposition.getByRole('button', { name: 'Valider et ouvrir Gmail' }).click();
  await expect(page.getByText('Contact en opposition (STOP) ou perdu : aucun envoi possible')).toBeVisible();
  await expect(cartes.filter({ hasText: 'Centre de santé Opposition — recette' })).toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { __ouverts: string[] }).__ouverts.length)).toBe(1);

  // État 4 — constat d'envoi : la carte sort de la file et passe à l'historique.
  await tilleuls.getByRole('button', { name: 'J’ai envoyé' }).click();
  await expect(page.getByText('Envoi enregistré dans le CRM')).toBeVisible();
  await expect(cartes.filter({ hasText: 'EHPAD Les Tilleuls — recette' })).toHaveCount(0);
  await expect(cartes).toHaveCount(1);

  // Reprise après rechargement : l'état vient du serveur, pas du navigateur.
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByRole('heading', { name: 'Agents de croissance', exact: true })).toBeVisible();
  await expect(cartes).toHaveCount(1);
  await page.getByRole('button', { name: 'Voir l’historique' }).click();
  await expect(cartes).toHaveCount(2);
  const envoye = cartes.filter({ hasText: 'EHPAD Les Tilleuls — recette' });
  await expect(envoye.getByText('Envoyé', { exact: true })).toBeVisible();
  await expect(envoye.getByLabel('Objet')).toHaveValue('Renforts pour vos absences — Jolene');
  await expect(envoye.getByLabel('Objet')).toBeDisabled();
  await expect(envoye.getByRole('button')).toHaveCount(0);
  const rejete = cartes.filter({ hasText: 'Centre de santé Opposition — recette' });
  await expect(rejete.getByText('Motif : Opposition (STOP) ou contact perdu', { exact: true })).toBeVisible();
  await preuve(page, 'agents-croissance-historique', info);

  // État 5 — entonnoir réel, goulot affiché.
  await page.getByRole('tab', { name: 'Entonnoir' }).click();
  await expect(page).toHaveURL(/\/admin\/fondateur\/agents\?vue=entonnoir$/);
  await expect(page.getByText('Cohorte réelle uniquement : les comptes de test sont exclus.')).toBeVisible();
  const soignants = page.getByRole('list', { name: 'Soignants (cumul)' });
  await expect(soignants.getByRole('listitem')).toHaveCount(5);
  await expect(soignants.getByRole('listitem').nth(1)).toContainText('Au moins un document');
  await expect(soignants.getByRole('listitem').nth(1)).toContainText('50 %');
  await expect(page.getByText('Goulot actuel :').first()).toContainText('Ont candidaté');
  const etabs = page.getByRole('list', { name: 'Établissements (cumul)' });
  await expect(etabs.getByRole('listitem').first()).toContainText(/30\s633/);
  await expect(page.getByText('Goulot actuel :').nth(1)).toContainText('Contactés');
  await expect(page.getByText('Le premier rapport sera figé lundi matin pour la semaine écoulée.')).toBeVisible();
  await preuve(page, 'agents-croissance-entonnoir', info);

  // État 6 — agents : préparation automatique en pause par défaut, activation explicite.
  await page.getByRole('tab', { name: 'Agents' }).click();
  const planification = page.getByTestId('planification-croissance');
  await expect(planification.getByText('En pause', { exact: true })).toBeVisible();
  await expect(page.getByText('Dernier passage : aucun pour l’instant')).toHaveCount(5);
  await planification.getByRole('button', { name: 'Activer la préparation automatique' }).click();
  await expect(planification.getByText('Activée', { exact: true })).toBeVisible();
  await expect(planification.getByRole('button', { name: 'Mettre en pause' })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByTestId('planification-croissance').getByText('Activée', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Préparer maintenant' }).click();
  await expect(page.getByText('27 nouveau(x) brouillon(s). Rien n’a été envoyé.')).toBeVisible();
  await expect(page.getByText(/Dernier passage : .*\(manuel\) · 20 brouillon\(s\)/)).toBeVisible();
  await expect(page.getByText('Brouillons seulement', { exact: true })).toHaveCount(5);
  // Sans décompte dans le dernier passage, aucun avertissement n'est inventé.
  await expect(page.getByTestId('alerte-cibles-prospection')).toHaveCount(0);
  expect(sim.lancements()).toBe(1);
  await preuve(page, 'agents-croissance-agents', info);

  // Aucune écriture hors des trois RPC prévues, aucune requête externe.
  expect(sim.decisions.map((d) => d.p_action)).toEqual(['VALIDER', 'VALIDER', 'MARQUER_ENVOYE']);
  expect(sim.bascules).toEqual([null, true, null, null]);
  expect(sim.etat.ecritures).toEqual([]);
  expect(sim.etat.inconnues).toEqual([]);
  expect(sim.etat.erreurs).toEqual([]);
});

test('admin — zéro visible et liste d’appels : avertissement, fiche, appel noté, opposition, STOP, reprise', async ({ page }, info) => {
  const sim = await simulerAgents(page, { appels: true });
  await page.goto('/admin/fondateur/agents');
  // Les deux formats de référence de la recette : iPhone 390 × 844 et ordinateur 1440 × 900.
  if (info.project.name === 'iphone') expect(page.viewportSize()).toEqual({ width: 390, height: 844 });
  if (info.project.name === 'ordinateur') expect(page.viewportSize()).toEqual({ width: 1440, height: 900 });
  const sansDebordement = async () => expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);

  // État 1 — le zéro n'est plus muet : avertissement en haut de page, dès l'arrivée.
  await expect(page.getByRole('heading', { name: 'Agents de croissance', exact: true })).toBeVisible();
  await expect(page.getByText(/Aucun envoi automatique\. Chaque email reste un brouillon jusqu’à votre validation, aucun appel n’est passé à votre place/)).toBeVisible();
  const alerte = page.getByTestId('alerte-cibles-prospection');
  await expect(alerte).toHaveAttribute('role', 'status');
  await expect(alerte.getByText('Prospection par email à l’arrêt', { exact: true })).toBeVisible();
  await expect(alerte).toContainText(/Aucune adresse utilisable parmi les 2\s318 établissements ciblés \(56, 75, 92\)\. 656 ont une adresse, toutes en messagerie de santé fermée \(MSSanté, Apicrypt\), où un email envoyé depuis Gmail est rejeté\. 2\s017 ont un téléphone : les fiches d’appel de la semaine sont dans « Appels établissements »\./);
  await expect(alerte.getByText('Constat du dernier passage de l’agent, le 24/11/2026 06:50.', { exact: true })).toBeVisible();
  const cartes = page.getByTestId('brouillon-croissance');
  await expect(cartes).toHaveCount(3);
  await sansDebordement();
  await preuve(page, 'agents-appels-avertissement', info);

  // État 2 — filtre « email » : la file vide s'explique.
  await page.getByRole('group', { name: 'Filtrer par agent' }).getByRole('button', { name: 'Prospection établissements' }).click();
  await expect(page.getByText('Aucun email à valider : aucune adresse utilisable parmi les établissements ciblés (voir l’avertissement en haut de page).', { exact: true })).toBeVisible();
  await expect(cartes).toHaveCount(0);

  // État 3 — de l'avertissement aux fiches d'appel : numéro, raisons, script, aucun lien d'appel avant validation.
  await alerte.getByRole('button', { name: 'Voir les fiches d’appel' }).click();
  await expect(page.getByRole('group', { name: 'Filtrer par agent' }).getByRole('button', { name: 'Appels établissements (3)' })).toHaveAttribute('aria-pressed', 'true');
  await expect(cartes).toHaveCount(3);
  const glycines = cartes.filter({ hasText: 'EHPAD Les Glycines — recette' });
  await expect(glycines.getByText('Appels établissements', { exact: true })).toBeVisible();
  await expect(glycines.getByText('Téléphone', { exact: true })).toBeVisible();
  await expect(glycines.getByText('À valider', { exact: true })).toBeVisible();
  await expect(glycines.getByText('Téléphone : 01 00 00 10 01', { exact: true })).toBeVisible();
  await expect(glycines.getByText('Pourquoi : EHPAD · Paris · dépt 75', { exact: true })).toBeVisible();
  await expect(glycines.getByLabel('Script d’appel')).toHaveValue(/Jolene facture à l'établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée[\s\S]*Jolene ne vous rappellera plus\.$/);
  await expect(glycines.getByLabel('Objet')).toHaveCount(0);
  await expect(glycines.getByText(/Étape/)).toHaveCount(0);
  await expect(glycines.getByRole('link')).toHaveCount(0);
  await expect(glycines.getByRole('group', { name: 'Résultat de l’appel' })).toHaveCount(0);
  await expect(glycines.getByRole('button', { name: 'Valider la fiche' })).toBeEnabled();
  await expect(glycines.getByRole('button', { name: 'Ne pas appeler' })).toBeEnabled();
  await sansDebordement();
  await preuve(page, 'agents-appels-file', info);

  // État 4 — validation : le numéro devient un lien que la fondatrice touche elle-même ; rien n'est composé ni ouvert.
  await glycines.getByRole('button', { name: 'Valider la fiche' }).click();
  await expect(page.getByText('Fiche validée. Appelez, puis notez le résultat de l’appel.')).toBeVisible();
  await expect(glycines.getByText('Validée, à appeler', { exact: true })).toBeVisible();
  await expect(glycines.getByRole('link', { name: 'Appeler le 01 00 00 10 01' })).toHaveAttribute('href', 'tel:0100001001');
  const resultat = glycines.getByRole('group', { name: 'Résultat de l’appel' });
  await expect(resultat.getByRole('button')).toHaveText(['A répondu', 'Sans réponse', 'Intéressé', 'À rappeler', 'Pas intéressé', 'STOP']);
  await expect(glycines.getByRole('button', { name: 'Valider la fiche' })).toHaveCount(0);
  expect(sim.decisions.at(-1)).toEqual({ p_id: ID_APPEL, p_action: 'VALIDER', p_sujet: '' });
  expect(await page.evaluate(() => (window as unknown as { __ouverts: string[] }).__ouverts)).toEqual([]);
  expect(sim.resultats).toEqual([]);
  await sansDebordement();
  await preuve(page, 'agents-appels-validee', info);

  // État 5 — opposition arrivée entre-temps : la validation refuse, la fiche quitte la file, aucun lien d'appel.
  const opposition = cartes.filter({ hasText: 'Hôpital Opposition — recette' });
  await opposition.getByRole('button', { name: 'Valider la fiche' }).click();
  await expect(page.getByText('Contact en opposition (STOP) ou perdu : ne pas appeler')).toBeVisible();
  await expect(cartes.filter({ hasText: 'Hôpital Opposition — recette' })).toHaveCount(0);
  await expect(cartes).toHaveCount(2);

  // État 6 — appel noté « sans réponse » : la fiche sort de la file, la suite est au CRM.
  await resultat.getByRole('button', { name: 'Sans réponse' }).click();
  await expect(page.getByText('Appel noté dans le CRM. La suite est dans Prospects, « Actions du jour ».')).toBeVisible();
  await expect(cartes.filter({ hasText: 'EHPAD Les Glycines — recette' })).toHaveCount(0);
  expect(sim.resultats).toEqual([{ p_id: ID_APPEL, p_motif: 'SANS_REPONSE' }]);

  // État 7 — STOP : confirmation explicite ; un refus ne note rien, un accord est définitif.
  const ssiad = cartes.filter({ hasText: 'SSIAD du Port — recette' });
  await expect(ssiad.getByText('Téléphone : 02.00.00.10.03', { exact: true })).toBeVisible();
  await ssiad.getByRole('button', { name: 'Valider la fiche' }).click();
  await expect(ssiad.getByRole('link', { name: 'Appeler le 02.00.00.10.03' })).toHaveAttribute('href', 'tel:0200001003');
  const messages: string[] = [];
  page.once('dialog', (d) => { messages.push(d.message()); void d.dismiss(); });
  await ssiad.getByRole('group', { name: 'Résultat de l’appel' }).getByRole('button', { name: 'STOP' }).click();
  await expect.poll(() => messages.length).toBe(1);
  expect(messages[0]).toBe('STOP : ne plus jamais solliciter SSIAD du Port — recette, par téléphone comme par email ?');
  expect(sim.resultats).toHaveLength(1);
  await expect(ssiad.getByText('Validée, à appeler', { exact: true })).toBeVisible();
  page.once('dialog', (d) => { messages.push(d.message()); void d.accept(); });
  await ssiad.getByRole('group', { name: 'Résultat de l’appel' }).getByRole('button', { name: 'STOP' }).click();
  await expect(page.getByText('Appel noté. Cet établissement ne sera plus sollicité.')).toBeVisible();
  await expect(cartes).toHaveCount(0);
  await expect(page.getByText('Aucun brouillon en attente. Les agents passent chaque matin vers 6 h 50, ou cliquez sur « Préparer maintenant ».', { exact: true })).toBeVisible();
  expect(sim.resultats).toEqual([{ p_id: ID_APPEL, p_motif: 'SANS_REPONSE' }, { p_id: ID_APPEL_STOP, p_motif: 'STOP' }]);

  // Reprise après rechargement : l'avertissement et l'historique viennent du serveur.
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByTestId('alerte-cibles-prospection').getByText('Prospection par email à l’arrêt', { exact: true })).toBeVisible();
  await expect(cartes).toHaveCount(0);
  await page.getByRole('button', { name: 'Voir l’historique' }).click();
  await expect(cartes).toHaveCount(3);
  const note = cartes.filter({ hasText: 'EHPAD Les Glycines — recette' });
  await expect(note.getByText('Appel noté', { exact: true })).toBeVisible();
  await expect(note.getByText('Résultat de l’appel : Sans réponse', { exact: true })).toBeVisible();
  await expect(note.getByLabel('Script d’appel')).toBeDisabled();
  await expect(note.getByRole('button')).toHaveCount(0);
  await expect(note.getByRole('link')).toHaveCount(0);
  const rejetee = cartes.filter({ hasText: 'Hôpital Opposition — recette' });
  await expect(rejetee.getByText('Rejeté', { exact: true })).toBeVisible();
  await expect(rejetee.getByText('Motif : Opposition (STOP) ou contact perdu', { exact: true })).toBeVisible();
  await expect(rejetee.getByRole('link')).toHaveCount(0);
  await expect(cartes.filter({ hasText: 'SSIAD du Port — recette' }).getByText('Résultat de l’appel : STOP', { exact: true })).toBeVisible();
  await sansDebordement();
  await preuve(page, 'agents-appels-historique', info);

  // État 8 — onglet Agents : la carte de l'agent email dit qu'il n'a plus de cible, avec le décompte.
  await page.getByRole('tab', { name: 'Agents' }).click();
  await expect(page.getByText('Aucune cible joignable', { exact: true })).toHaveCount(1);
  await expect(page.getByTestId('cibles-prospection')).toHaveText(/^Cibles : 2\s318 établissements ciblés · 0 adresse utilisable · 656 en messagerie fermée · 2\s017 téléphones$/);
  await expect(page.getByText('Brouillons seulement', { exact: true })).toHaveCount(4);
  await expect(page.getByRole('heading', { name: 'Appels établissements', exact: true })).toBeVisible();
  await expect(page.getByText('Dernier passage : 24/11/2026 06:50 (automatique) · 3 brouillon(s)', { exact: true })).toBeVisible();
  await expect(page.getByText('Dernier passage : 24/11/2026 06:50 (automatique) · 0 brouillon(s)', { exact: true })).toBeVisible();
  await sansDebordement();
  await preuve(page, 'agents-appels-agents', info);

  // État 9 — rapport hebdomadaire : appels notés et adresses utilisables figés avec la semaine.
  await page.getByRole('tab', { name: 'Entonnoir' }).click();
  await expect(page.getByRole('columnheader', { name: 'Appels notés' })).toBeVisible();
  await expect(page.getByRole('columnheader', { name: 'Adresses utilisables' })).toBeVisible();
  const semaine = page.getByRole('row').filter({ hasText: '16/11/2026' });
  await expect(semaine.getByRole('cell')).toHaveText(['16/11/2026', '0', '0', '0', '0', '0', '2', '0']);
  await expect(page.getByTestId('alerte-cibles-prospection')).toBeVisible();
  await preuve(page, 'agents-appels-entonnoir', info);

  // Trois validations, deux constats d'appel ; aucune écriture hors du décideur, aucune requête externe.
  expect(sim.decisions.map((d) => d.p_action)).toEqual(['VALIDER', 'VALIDER', 'MARQUER_ENVOYE', 'VALIDER', 'MARQUER_ENVOYE']);
  expect(sim.lancements()).toBe(0);
  expect(sim.etat.ecritures).toEqual([]);
  expect(sim.etat.inconnues).toEqual([]);
  expect(sim.etat.erreurs).toEqual([]);
});
