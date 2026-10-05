import { expect, type BrowserContext } from '@playwright/test';
import { chargerHtmlLocal } from './recette-complete-mission';

/** Simulation frontend seulement : aucune identité Auth, RPC ou qualification réelle. */
export const maintenant = '2026-09-30T08:00:00.000Z';
export const identifiants = {
  as1: 'dc300000-0000-4000-8000-000000000001',
  as2: 'dc300000-0000-4000-8000-000000000002',
  etablissement: 'dc300000-0000-4000-8000-000000000003',
  tiers: 'dc300000-0000-4000-8000-000000000004',
  mission: 'dc300000-0000-4000-8000-000000000010',
};
export type Acteur = 'as1' | 'as2' | 'etablissement' | 'tiers';

export function creerCandidaturesDeuxAs() {
  const soignants = ['as1', 'as2'].map((acteur, i) => ({
    id: identifiants[acteur as 'as1' | 'as2'], prenom: i ? 'Basile' : 'Aline', nom: 'Simulation',
    profession: 'AS', type_exercice: 'SALARIE', date_naissance: '1990-01-15',
    telephone: `+3360000000${i + 1}`, email: `${acteur}@example.invalid`,
    identite_verifiee: false, diplome_verifie: false, rpps_verifie: false, numero_rpps: null,
    tous_documents_valides: false, est_compte_test: true, statut: 'ACTIF',
    adresse_rue: '1 rue Fictive', adresse_code_postal: '75001', adresse_ville: 'Paris',
    adresse_lat: 48.86, adresse_lng: 2.35, premiere_mission_le: null,
  }));
  const etablissement = {
    id: identifiants.etablissement, nom: 'Clinique fictive candidatures AS', type: 'CLINIQUE_PRIVEE',
    statut_verification: 'EN_ATTENTE', peut_publier: false, est_compte_test: true,
    adresse_rue: '2 rue Fictive', adresse_code_postal: '75001', adresse_ville: 'Paris',
    adresse_lat: 48.86, adresse_lng: 2.35, email_contact: 'clinique@example.invalid',
    telephone_contact: '+33600000003', contrat_service_signe: false,
  };
  const mission = {
    id: identifiants.mission, etablissement_id: etablissement.id,
    intitule: 'Mission AS — deux candidatures fictives', description: 'Recette sans attribution.',
    service: 'Soins', profession_requise: 'AS', statut: 'OUVERTE', mode_attribution: 'CANDIDATURE',
    type_contrat_recherche: 'SALARIE', type_contrat_applique: null, choix_contrat_soignant: null,
    type_paiement_soignant: 'BULLETIN_PAIE', mode_paiement_soignant: 'DIRECT',
    soignant_assigne_id: null, est_urgente: false, niveau_urgence: null,
    debut_le: '2026-10-02T07:00:00.000Z', fin_le: '2026-10-02T11:00:00.000Z',
    duree_heures: 4, nb_creneaux: 1, taux_horaire_base: 20, total_brut: 80, net_estime: 62,
    net_a_payer: 62, mode_remuneration: 'TAUX_HORAIRE', cree_le: maintenant, modifie_le: maintenant,
    etablissements: etablissement, presences: [],
  };
  const creneaux = [{ id: 'dc300000-0000-4000-8000-000000000020', mission_id: mission.id,
    debut: mission.debut_le, fin: mission.fin_le, est_pause: false, type_creneau: 'PREVISIONNEL' }];
  const state = { soignants, etablissement, mission, creneaux,
    candidatures: [] as Array<{ id: string; mission_id: string; soignant_id: string; message: string | null; statut: string; cree_le: string; choix_contrat: string }>,
    indisponible: null as 'mission' | 'postuler' | 'candidatures' | null,
    calls: [] as Array<{ acteur: Acteur; name: string; method: string; body: any }>,
    unknown: [] as string[], external: [] as string[], errors: [] as string[], refusPlanning: 0,
  };
  async function installer(context: BrowserContext, acteur: Acteur) {
    const estSoignant = acteur === 'as1' || acteur === 'as2';
    const profil = soignants.find(s => s.id === identifiants[acteur]);
    const role = estSoignant ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT';
    const user = { id: identifiants[acteur], email: profil?.email ?? `${acteur}@example.invalid`,
      aud: 'authenticated', role: 'authenticated', email_confirmed_at: maintenant,
      app_metadata: { role, etablissement_id: estSoignant ? null : identifiants[acteur] },
      user_metadata: { prenom: profil?.prenom ?? 'Clinique', nom: 'Simulation' }, identities: [] };
    const session = { user, token_type: 'bearer', access_token: `simulation-candidature-${acteur}`,
      refresh_token: 'simulation-refresh', expires_in: 86400, expires_at: 1799999999 };
    await context.addInitScript(session => {
      if (!['localhost', '127.0.0.1'].includes(location.hostname)) return;
      sessionStorage.setItem('sb-127-auth-token', JSON.stringify(session));
      localStorage.setItem('cookie-consent', 'refused');
      // stripe-js charge son SDK dès l'import du détail établissement. Aucune
      // dépendance distante dans cette recette; une invocation financière échoue.
      Object.defineProperty(window, 'Stripe', { value: () => { throw new Error('Stripe interdit dans la recette candidature'); } });
    }, session);
    await context.routeWebSocket('**/*', socket => socket.close());
    const erreurs = (page: import('@playwright/test').Page) => page.on('pageerror', e => state.errors.push(e.message));
    context.pages().forEach(erreurs); context.on('page', erreurs);
    await context.route('**/*', async route => {
      const req = route.request(), url = new URL(req.url()), name = url.pathname.split('/').pop()!;
      const json = (data: unknown, status = 200, headers = {}) => route.fulfill({ status, json: data,
        headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*',
          'access-control-expose-headers': 'content-range', ...headers } });
      if (!['localhost', '127.0.0.1'].includes(url.hostname)) {
        state.external.push(url.origin); return route.abort('blockedbyclient');
      }
      if (url.pathname.startsWith('/auth/v1/')) {
        if (['user', 'token', 'logout'].includes(name)) return json(name === 'user' ? user : name === 'logout' ? {} : session);
      } else if (!/^\/(rest|functions|storage)\/v1\//.test(url.pathname)) {
        if (req.isNavigationRequest() && req.resourceType() === 'document') {
          // Une seule reprise TCP du GET HTML local ; les erreurs restent bloquantes.
          const response = await chargerHtmlLocal(route);
          // Hints réseau et police distante exclus uniquement du banc de recette local.
          return route.fulfill({ response, body: (await response.text())
            .replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '')
            .replace(/<link\b(?=[^>]*\bhref=["']https:\/\/fonts\.googleapis\.com\/)[^>]*>/gi, '') });
        }
        return route.continue();
      }
      const body = req.postDataJSON();
      state.calls.push({ acteur, name, method: req.method(), body });
      if (req.method() === 'OPTIONS') return json({});
      if (url.pathname.includes('/rpc/') && req.method() === 'POST') {
        switch (name) {
          case 'fn_get_my_role': return json({ role, etablissement_id: estSoignant ? null : identifiants[acteur] });
          case 'fn_compte_auth_actif': return json(true);
          case 'fn_mon_profil_soignant_complet': return json(profil);
          case 'fn_dashboard_soignant_complet': return json({ profil, missions_ouvertes:[mission], mes_missions:[], documents:[], heures_semaine:0,
            gains_mois:{net_total:0,brut_total:0,nb_missions:0}, gains_6mois:[], missions_semaine_cal:[], propositions:[], heures_totales_terminees:0, missions_oubliees_count:0, notifs_non_lues:0 });
          case 'fn_mon_etablissement_complet': return json({ ...etablissement, id: identifiants[acteur] });
          case 'fn_stats_dashboard_etablissement': return json({ missions_ouvertes: 1, candidatures_en_attente: state.candidatures.length });
          case 'fn_mes_soignants_etablissement': return json([]); // Aucun soignant affecté.
          case 'fn_mon_score_etab': return json({ score_qualite: null, niveau: null, composantes: { notation_pct: null, nb_notations: 0, paiement_pct: null, nb_factures: 0, nb_litiges_perdus: 0 } });
          case 'fn_bfa_info': return json({ eligible: false }); // Aucun groupe dans cette fixture.
          case 'fn_etablissement_public': return json(null); // Les comptes test sont exclus de la fiche publique.
          case 'fn_etablissement_pour_mission': return json(etablissement);
          case 'fn_etablissements_safe': return json([etablissement]);
          case 'fn_lire_candidatures_mission_habilitee': {
            // La route secondaire conserve le refus SQL pour un établissement tiers.
            expect(acteur).toBe('tiers');
            expect(body).toEqual({ p_mission_id: mission.id });
            return json({ code: '42501', message: 'Mission indisponible ou accès refusé' }, 403);
          }
          case 'fn_soignant_pour_etablissement': {
            const candidat = acteur === 'etablissement' ? soignants.find(s => s.id === body.p_soignant_id) : null;
            // Le RPC LIVE conserve le prénom mais masque le nom et le téléphone
            // tant qu'aucune relation contractuelle n'existe avec l'établissement.
            return json(candidat ? { ...candidat, nom: candidat.nom.slice(0, 1) + '.', nom_anonymise: true, telephone: null } : null);
          }
          case 'fn_mes_permissions_etab': return json({ success: true, role: 'PROPRIETAIRE', etablissement_id: identifiants[acteur],
            permissions: Object.fromEntries(['lecture', 'missions', 'candidatures', 'contrats', 'lecture_contrats', 'profil_etab'].map(p => [p, true])) });
          case 'fn_messages_non_lus': return json(0);
          case 'fn_update_presence': case 'fn_onboarding_soignant_statut': return json(null);
          case 'fn_note_moyenne': return json({ moyenne: null, total: 0 });
          case 'fn_param_bool': return json(false);
          case 'fn_mode_exercice': return json({ niveau: 'AUTORISE', categorie: 'prive', source_libelle: 'Réponse de matrice simulée', source_force: 'CONFORMITE_JOLENE', source_url: null });
          case 'fn_confirmer_action_planning_v1': {
            expect(estSoignant).toBe(true);
            expect(body).toMatchObject({ p_mission_id: mission.id, p_action: 'POSTULER', p_candidature_id: null });
            expect([null, 'SALARIE']).toContain(body.p_choix_contrat);
            if (state.indisponible === 'postuler') return json({ message: 'Service temporairement indisponible. Réessayez.' }, 503);
            if (JSON.stringify(body.p_creneaux_confirmes) !== JSON.stringify(creneaux.map(({ debut, fin }) => ({ debut, fin })))) {
              state.refusPlanning++;
              return json({ success: false, error: 'Le planning a changé. Recharge la mission puis confirme les nouveaux horaires.' });
            }
            expect(state.candidatures.some(c => c.soignant_id === user.id)).toBe(false);
            const candidature = { id: `dc300000-0000-4000-8000-00000000003${acteur === 'as1' ? 1 : 2}`,
              mission_id: mission.id, soignant_id: user.id, message: body.p_message, statut: 'EN_ATTENTE', cree_le: maintenant, choix_contrat: 'SALARIE' };
            state.candidatures.push(candidature);
            return json({ success: true, candidature_id: candidature.id, choix_contrat: 'SALARIE', profession_requise: 'AS', docs_a_completer: true, documents_requis_pour: 'SALARIE' });
          }
        }
      }
      if (url.pathname.startsWith('/rest/v1/') && !url.pathname.includes('/rpc/') && ['GET', 'HEAD'].includes(req.method())) {
        const visible = acteur !== 'tiers';
        if (name === 'missions' && state.indisponible === 'mission') return json({ message: 'Interruption simulée persistante' }, 503);
        if (name === 'candidatures' && state.indisponible === 'candidatures' && acteur === 'etablissement') return json({ message: 'Candidatures indisponibles. Réessayez.' }, 503);
        const data: Record<string, any[]> = {
          missions: visible ? [mission] : [], mission_creneaux: visible ? creneaux : [],
          candidatures: visible ? state.candidatures.filter(c => !estSoignant || c.soignant_id === user.id) : [],
          soignants: profil ? [profil] : [], etablissements: [{ ...etablissement, id: identifiants[acteur] }],
          contrats_mission: [], contrats_travail_missions: [], parcours_inscription: [], notifications: [],
          documents_soignants: [], favoris: [], notations_missions: [], evaluations: [], paliers_commission: [],
          stripe_connect_onboarding: [], litiges: [],
          documents_requis_par_profession: [{profession:'AS',type_document:'CARTE_IDENTITE',est_critique:true,type_exercice_requis:'TOUS'}],
        };
        if (name in data) {
          const rows = data[name].filter(row => [...url.searchParams.entries()].every(([key, value]) => {
            if (['select', 'order', 'limit', 'offset'].includes(key)) return true;
            if (value.startsWith('eq.')) return String(row[key]) === value.slice(3);
            if (value.startsWith('neq.')) return String(row[key]) !== value.slice(4);
            if (value.startsWith('in.(')) return value.slice(4, -1).split(',').map(v => v.replaceAll('"', '')).includes(String(row[key]));
            if (['debut_le', 'fin_le'].includes(key) && /^(gte|lte)\./.test(value)) {
              const borne = Date.parse(value.slice(4)), instant = Date.parse(String(row[key]));
              return Number.isFinite(borne) && Number.isFinite(instant) && (value.startsWith('gte.') ? instant >= borne : instant <= borne);
            }
            if (value === 'is.null') return row[key] == null;
            state.unknown.push(`Filtre non géré ${name}.${key}=${value}`); return false;
          }));
          const single = req.headers().accept?.includes('object');
          if (single && !rows.length && name === 'missions') return json({ code: 'PGRST116', message: 'Mission indisponible' }, 406);
          return json(single ? rows[0] ?? null : rows, 200, { 'content-range': `0-${Math.max(0, rows.length - 1)}/${rows.length}` });
        }
      }
      state.unknown.push(`${acteur} ${req.method()} ${url.pathname} ${url.search}`);
      return json({ message: `Requête interdite ou non prévue dans cette recette : ${name}` }, 501);
    });
  }
  function verifierBornes() {
    expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
    expect(mission.statut).toBe('OUVERTE'); expect(mission.soignant_assigne_id).toBeNull();
    expect(mission.type_contrat_applique).toBeNull();
    expect(state.candidatures.every(c => c.statut === 'EN_ATTENTE')).toBe(true);
    // Le dashboard lit l'état local d'onboarding, sans appeler Stripe. Seule
    // cette lecture est permise ; les écritures et endpoints financiers restent interdits.
    expect(state.calls.filter(c => /accepter|traiter_candidature|generer_contrat|signer|payer|checkout|stripe|dpae/i.test(c.name)
      && !(c.name === 'stripe_connect_onboarding' && c.method === 'GET' && c.body === null
        && (c.acteur === 'as1' || c.acteur === 'as2')))).toEqual([]);
    for (const profil of soignants) expect(profil).toMatchObject({ profession: 'AS', type_exercice: 'SALARIE',
      identite_verifiee: false, diplome_verifie: false, rpps_verifie: false, tous_documents_valides: false, est_compte_test: true });
    expect(etablissement).toMatchObject({ statut_verification: 'EN_ATTENTE', peut_publier: false, est_compte_test: true });
  }
  return { state, installer, verifierBornes };
}
