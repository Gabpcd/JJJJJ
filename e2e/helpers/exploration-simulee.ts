import type { Page } from '@playwright/test';

const userId = '69000000-0000-4000-8000-000000000071';
export const missionId = '69000000-0000-4000-8000-000000000072';
export async function compteNeuf(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT', offres = false, nombreOffres = 1) {
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return ['127.0.0.1', 'localhost'].includes(url.hostname) ? route.continue() : route.abort();
  });
  const roleCompte = {role:'INCONNU',etablissement_id:null as string | null};
  const lecturesProtegees: string[] = [];
  const errors: string[] = []; page.on('pageerror', e => errors.push(e.message));
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  // Ces comptes sont simulés : aucune télémétrie de fixture ne part vers Sentry.
  await page.route(/https:\/\/[^/]+\.ingest\.[^/]+\.sentry\.io\/api\/[^/]+\/envelope\//,
    route => route.fulfill({ json: {} }));
  const user = { id: userId, email: 'recette-navigation@example.invalid', aud: 'authenticated', role: 'authenticated', email_confirmed_at: new Date().toISOString(), app_metadata: {}, user_metadata: {}, identities: [] };
  const session = { user, token_type: 'bearer', access_token: 'fixture-auth', refresh_token: 'fixture-refresh', expires_in: 3600, expires_at: Math.floor(Date.now()/1000)+3600 };
  const parcours = { user_id: userId, type_compte: type, donnees: type === 'SOIGNANT' ? {profession: 'IDE'} as Record<string, unknown> : {nom: 'Résidence Camille'}, modifie_le: new Date().toISOString() };
  const mutations: string[] = [];
  const lectures: Record<string, number> = {};
  const debut = new Date(Date.now()+7*86400000).toISOString();
  const fin = new Date(Date.now()+7*86400000+8*3600000).toISOString();
  const mission = { id: missionId, cree_le: new Date().toISOString(), intitule: 'Remplacement infirmier de jour', profession_requise: 'IDE', description: 'Renfort équipe de jour.', debut_le: debut, fin_le: fin, duree_heures: 8, nb_creneaux: 1, taux_horaire_base: 30, total_brut: 240, net_estime: 240, net_a_payer: 240, mode_remuneration: 'TAUX_HORAIRE', statut: 'OUVERTE', mode_attribution: 'CANDIDATURE', type_contrat_recherche: 'SALARIE', etablissement_id: '69000000-0000-4000-8000-000000000073', etablissements: {id: '69000000-0000-4000-8000-000000000073', nom: 'Résidence Camille', type:'EHPAD', adresse_ville:'Paris', adresse_code_postal:'75001',adresse_lat:48.8566,adresse_lng:2.3522}, creneaux: [{id:'creneau',mission_id:missionId,debut,fin,est_pause:false,type_creneau:'PREVISIONNEL'}] };
  await page.route('**/auth/v1/**', async route => {
    const url = new URL(route.request().url());
    await route.fulfill({json: url.pathname.endsWith('/user') ? user : session});
  });
  await page.route('**/rest/v1/**', async route => {
    const req = route.request(); const url = new URL(req.url()); const nom = url.pathname.split('/').pop()!; lectures[nom] = (lectures[nom] || 0) + 1;
    if (!['GET','HEAD','OPTIONS'].includes(req.method()) && !url.pathname.includes('/rpc/')) mutations.push(nom);
    if (/^(presences|contrats_mission|fn_lister_membres_etab|fn_rechercher_soignants_etab|fn_mes_filleuls_etab|fn_mes_credits_etab|fn_mon_score_etab|fn_litiges_etablissement|fn_stats_rh_etablissement|fn_analytics_etablissement)$/.test(nom)) lecturesProtegees.push(nom);
    let data: unknown = [];
    if (nom === 'fn_get_my_role') data = roleCompte;
    else if (nom === 'parcours_inscription') data = req.headers().accept?.includes('object') ? parcours : [parcours];
    else if (nom === 'fn_demarrer_inscription') data = parcours;
    else if (nom === 'fn_enregistrer_parcours_inscription') { Object.assign(parcours.donnees, req.postDataJSON().p_donnees); data = parcours; }
    else if (nom === 'fn_modifier_favori_inscription') {
      const {p_mission_id,p_actif} = req.postDataJSON();
      const ids = new Set(parcours.donnees.missionsSauvegardees as string[] || []);
      if (p_actif) ids.add(p_mission_id); else ids.delete(p_mission_id);
      parcours.donnees.missionsSauvegardees = [...ids]; data = null;
    }
    else if (nom === 'fn_explorer_missions_inscription') data = offres
      ? Array.from({ length: nombreOffres }, (_, i) => {
        if (i === 0) return mission;
        const id = `69000000-0000-4000-8000-${String(100 + i).padStart(12, '0')}`;
        return {
          ...mission, id, intitule: `Renfort infirmier ${i + 1}`,
          creneaux: mission.creneaux.map(creneau => ({ ...creneau, id: `creneau-${i}`, mission_id: id })),
        };
      }) : [];
    else if (nom === 'fn_mon_profil_soignant_complet' || nom === 'fn_mon_etablissement_complet') data = {error:'Profil introuvable'};
    else if (nom === 'fn_compte_auth_actif') data = true;
    else if (nom === 'fn_onboarding_soignant_statut') data = null;
    else if (/candidatur|creer_mission|enregistrer_swipe/.test(nom) && req.method() === 'POST') { mutations.push(nom); data = []; }
    else if (req.headers().accept?.includes('object')) data = null;
    await route.fulfill({json:data, headers:{'content-range':'0-0/0'}});
  });
  await page.route('**/functions/v1/**', route => route.fulfill({json: {}}));
  return { parcours, mutations, errors, roleCompte, lecturesProtegees, lectures };
}
export async function inscrire(page: Page, type: 'SOIGNANT' | 'ETABLISSEMENT') {
  await page.goto(`/inscription/${type === 'SOIGNANT' ? 'soignant' : 'etablissement'}`);
  await page.getByLabel('Email', {exact:true}).fill('recette-navigation@example.invalid');
  await page.getByLabel('Mot de passe', {exact:true}).fill('Mot!Solide-Recette2026');
  if (type === 'SOIGNANT') await page.getByLabel('Profession', {exact:true}).selectOption('IDE');
  else await page.getByLabel('Nom de l’établissement', {exact:true}).fill('Résidence Camille');
  await page.getByRole('checkbox',{name:/CGU/}).check();
  if (type === 'ETABLISSEMENT') await page.getByRole('checkbox',{name:/conditions générales de vente/}).check();
  await page.getByRole('button',{name:'Créer mon compte',exact:true}).click();
}
