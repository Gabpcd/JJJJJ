import { expect, test, type Page } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Réponses backend simulées : aucun brouillon réel, aucun email, aucun CRM réel.
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
      corps: 'Bonjour,\n\nJe suis Gabrielle, fondatrice de Jolene.\n\nVos coordonnées professionnelles proviennent du répertoire public FINESS. Si vous ne souhaitez plus être contacté par Jolene, répondez simplement « STOP » à cet email : nous ne vous écrirons plus.',
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

const entonnoir = {
  periode: { debut: '2026-11-01T11:00:00Z', fin: '2026-11-08T11:00:00Z' }, genere_le: '2026-11-08T11:00:00Z', cohorte: 'REELLE',
  soignants: { inscrits_total: 2, inscrits_periode: 0, avec_document: 1, documents_valides: 1, onboarding_termine: 0, ayant_candidate: 0, ayant_realise_mission: 0, actifs_periode: 0 },
  etablissements: { inscrits_total: 0, inscrits_periode: 0, peuvent_publier: 0, ayant_publie: 0 },
  missions: { publiees_periode: 0, pourvues_periode: 0, terminees_periode: 0, ouvertes_a_venir: 0, ouvertes_sans_candidature: 0, candidatures_periode: 0 },
  prospection: { prospects_etablissements: 64058, prospects_avec_email: 30633, prospects_contactes_total: 0, emails_journalises_periode: 0, crm_par_statut: {}, crm_reponses_positives: 0, crm_stop: 0 },
  agents: { crees_periode: 23, valides_periode: 0, envoyes_periode: 0, rejetes_periode: 0, en_attente: 23, par_agent: {} },
  sources_inscriptions_periode: {}, exclus_cohorte_test: { soignants_test: 1100, etablissements_test: 917 },
};

async function simulerAgents(page: Page) {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  const brouillons = fixtures();
  const decisions: Array<{ p_id: string; p_action: string; p_sujet: string | null }> = [];
  let executions: Array<Record<string, unknown>> = [];
  let lancements = 0;
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
  await page.route('**/rest/v1/growth_rapports_hebdo**', (route) => route.fulfill({ json: [], headers: { ...cors, 'content-range': '*/0' } }));
  await page.route('**/rest/v1/growth_agent_executions**', (route) => route.fulfill({ json: executions, headers: cors }));
  await page.route('**/rest/v1/rpc/fn_admin_growth_entonnoir', async (route) => {
    expect(route.request().postDataJSON()).toEqual({ p_jours: 7 });
    return route.fulfill({ json: entonnoir, headers: cors });
  });
  await page.route('**/rest/v1/rpc/fn_admin_growth_executer_agents', async (route) => {
    lancements++;
    executions = ['PROSPECTION_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'].map((agent, i) => ({
      id: i + 1, agent, declencheur: 'ADMIN', debut_le: '2026-11-08T11:05:00Z', brouillons_crees: agent === 'PROSPECTION_ETABLISSEMENT' ? 20 : agent === 'POST_SOCIAL' ? 7 : 0, erreur: null,
    }));
    return route.fulfill({ json: { declencheur: 'ADMIN', expires: 0, agents: {
      PROSPECTION_ETABLISSEMENT: { brouillons_crees: 20 }, POST_SOCIAL: { brouillons_crees: 7 },
      MISSION_A_POURVOIR: { brouillons_crees: 0 }, REACTIVATION: { brouillons_crees: 0 } } }, headers: cors });
  });
  await page.route('**/rest/v1/rpc/fn_admin_growth_brouillon_decider', async (route) => {
    const p = route.request().postDataJSON();
    decisions.push({ p_id: p.p_id, p_action: p.p_action, p_sujet: p.p_sujet });
    const b = brouillons.find((x) => x.id === p.p_id)!;
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
  return { etat, brouillons, decisions, lancements: () => lancements };
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
  await expect(tilleuls.getByLabel('Message')).toHaveValue(/répertoire public FINESS[\s\S]*« STOP »/);
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

  // État 6 — agents : lancement manuel, brouillons seulement.
  await page.getByRole('tab', { name: 'Agents' }).click();
  await expect(page.getByText('Dernier passage : aucun pour l’instant')).toHaveCount(4);
  await page.getByRole('button', { name: 'Préparer maintenant' }).click();
  await expect(page.getByText('27 nouveau(x) brouillon(s). Rien n’a été envoyé.')).toBeVisible();
  await expect(page.getByText(/Dernier passage : .*\(manuel\) · 20 brouillon\(s\)/)).toBeVisible();
  await expect(page.getByText('Brouillons seulement', { exact: true })).toHaveCount(4);
  expect(sim.lancements()).toBe(1);
  await preuve(page, 'agents-croissance-agents', info);

  // Aucune écriture hors des trois RPC prévues, aucune requête externe.
  expect(sim.decisions.map((d) => d.p_action)).toEqual(['VALIDER', 'VALIDER', 'MARQUER_ENVOYE']);
  expect(sim.etat.ecritures).toEqual([]);
  expect(sim.etat.inconnues).toEqual([]);
  expect(sim.etat.erreurs).toEqual([]);
});
