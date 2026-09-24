import { type Page, type Route } from '@playwright/test';
import { simulerEtablissement, etablissement, mission, ids } from './recette-complete-etablissement';

export const siretRecette = '90000000000001';
export const nomRecette = 'Établissement de complétion — simulation';

/** Extension explicite : seuls les endpoints du parcours peuvent écrire en mémoire. */
export async function simulerCompletionEtablissement(page: Page) {
  const base = await simulerEtablissement(page, 'minimal');
  const { etat } = base;
  const state = {
    erreurInscription: false, erreurPublication: false, erreurModification: false,
    appels: [] as { nom: string; payload: Record<string, unknown> }[],
    profil: { ...etablissement, nom: nomRecette, siret: siretRecette, statut_verification: 'EN_ATTENTE', est_verifie: false, peut_publier_missions: false, contrat_service_signe: false, contrat_service_statut: 'NON_SIGNE' },
    mission: null as Record<string, unknown> | null,
    creneaux: [] as Record<string, unknown>[],
  };
  const repondre = (route: Route, json: unknown, status = 200) => route.fulfill({ status, json });
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url());
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.fallback();
    const nom = url.pathname.split('/').pop()!;
    const endpoint = url.pathname.startsWith('/functions/v1/') && ['verify-siret', 'verify-finess', 'register-etablissement'].includes(nom)
      || url.pathname.startsWith('/rest/v1/rpc/') && ['fn_mon_etablissement_complet', 'fn_creer_mission_multi_jours_v3', 'fn_modifier_mission_etablissement_v4'].includes(nom);
    const table = url.pathname.startsWith('/rest/v1/') && ['etablissements', 'missions', 'mission_creneaux'].includes(nom);
    if (!endpoint && !table) return route.fallback();
    if ((endpoint && req.method() !== 'POST') || (table && !['GET', 'HEAD'].includes(req.method()))) {
      etat.inconnues.push(`${req.method()} ${url.pathname}`);
      return repondre(route, { message: 'Méthode non préparée pour la complétion' }, 501);
    }
    if (endpoint) {
      const p = req.postDataJSON() as Record<string, unknown>;
      state.appels.push({ nom, payload: p });
      if (nom === 'verify-siret') {
        if (p.siret !== siretRecette) return repondre(route, { message: 'SIRET non préparé' }, 400);
        return repondre(route, { statut: 'ALERTE', raison_sociale: nomRecette, est_actif: true, est_sante: true, est_public: false, code_naf: '8710A', message: 'Vérification simulée : dossier à examiner.' });
      }
      if (nom === 'verify-finess') return repondre(route, { trouve: false, verifie: false });
      if (nom === 'register-etablissement') {
        if (p.nom !== nomRecette || p.siret !== siretRecette || p.type !== 'EHPAD' || p.adresse_ville !== 'Paris') return repondre(route, { ok: false, code: 'MISSING_REQUIRED_FIELDS', message: 'Dossier de simulation incohérent.' }, 400);
        if (state.erreurInscription) return repondre(route, { ok: false, code: 'NETWORK_ERROR', message: 'Enregistrement temporairement indisponible. Votre saisie est conservée.' }, 503);
        etat.mode = 'complet';
        return repondre(route, { ok: true, success: true, etablissement_id: ids.etab, auto_verifie: false, statut_verification: 'EN_ATTENTE', peut_publier_missions: false, siret_verifie: false, finess_verifie: false, verification_complete_requise: true });
      }
      if (nom === 'fn_mon_etablissement_complet') return repondre(route, etat.mode === 'minimal' ? { error: 'Profil introuvable' } : state.profil);
      if (etat.mode !== 'complet' || state.profil.peut_publier_missions !== true || state.profil.contrat_service_signe !== true) return repondre(route, { success: false, error: 'VERIFICATION_INCOMPLETE', message: 'Votre établissement doit être vérifié avant publication.' });
      if ((nom === 'fn_creer_mission_multi_jours_v3' && state.erreurPublication) || (nom === 'fn_modifier_mission_etablissement_v4' && state.erreurModification)) return repondre(route, { message: 'Enregistrement de mission temporairement indisponible.' }, 503);
      const creneaux = p.p_creneaux as { debut: string; fin: string }[];
      if (!Array.isArray(creneaux) || creneaux.length !== 1 || !p.p_intitule || p.p_profession_requise !== 'IDE' || p.p_type_contrat_recherche !== 'SALARIE' || p.p_taux_horaire_base !== 30) return repondre(route, { success: false, error: 'PAYLOAD_RECETTE_INVALIDE' }, 400);
      if (nom === 'fn_modifier_mission_etablissement_v4' && (!state.mission || p.p_mission_id !== ids.mission)) return repondre(route, { success: false, error: 'MISSION_INTROUVABLE' }, 404);
      const dureeHeures = creneaux.reduce((somme, c) => somme + (Date.parse(c.fin) - Date.parse(c.debut)) / 3_600_000, 0);
      if (!Number.isFinite(dureeHeures) || dureeHeures <= 0) return repondre(route, { success: false, error: 'CRENEAUX_RECETTE_INVALIDES' }, 400);
      state.mission = { ...mission, intitule: p.p_intitule, description: p.p_description, service: p.p_service, profession_requise: p.p_profession_requise, type_contrat_recherche: p.p_type_contrat_recherche, mode_attribution: p.p_mode_attribution, est_urgente: p.p_est_urgente, taux_horaire_base: p.p_taux_horaire_base, duree_heures: dureeHeures, total_brut: dureeHeures * Number(p.p_taux_horaire_base), nb_creneaux: creneaux.length, debut_le: creneaux[0].debut, fin_le: creneaux.at(-1)!.fin, etablissements: state.profil };
      state.creneaux = creneaux.map((c, i) => ({ ...c, id: `creneau-completion-${i}`, mission_id: ids.mission, type_creneau: 'PREVISIONNEL', est_pause: false }));
      etat.donnees = true;
      return repondre(route, { success: true, mission_id: ids.mission });
    }
    let rows: Record<string, unknown>[] = nom === 'etablissements' ? etat.mode === 'complet' ? [state.profil] : [] : nom === 'missions' ? state.mission ? [state.mission] : [] : state.creneaux;
    for (const key of ['id', 'etablissement_id', 'mission_id', 'statut', 'type_creneau', 'est_pause']) {
      const filtre = url.searchParams.get(key);
      if (filtre?.startsWith('eq.')) rows = rows.filter(r => String(r[key]) === filtre.slice(3));
      if (filtre?.startsWith('in.')) rows = rows.filter(r => filtre.slice(3).replace(/[()]/g, '').split(',').includes(String(r[key])));
    }
    const objet = req.headers().accept?.includes('object');
    if (objet && rows.length === 0) return repondre(route, { code: 'PGRST116', message: '0 rows' }, 406);
    // Le chargeur de planning exige le total exact pour refuser les pages tronquées.
    // Reproduire aussi la plage PostgREST ; un simple tableau 200 ne suffit pas.
    const total = rows.length;
    const offset = Number(url.searchParams.get('offset') ?? 0);
    const limite = Number(url.searchParams.get('limit') ?? total);
    const pageRows = rows.slice(offset, offset + limite);
    return route.fulfill({ status: 200, json: objet ? rows[0] : pageRows, headers: {
      'content-range': pageRows.length ? `${offset}-${offset + pageRows.length - 1}/${total}` : `*/${total}`,
      'access-control-expose-headers': 'content-range',
    } });
  });
  return { ...base, state };
}
