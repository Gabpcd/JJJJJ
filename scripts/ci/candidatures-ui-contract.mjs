import { isDeepStrictEqual as egal } from 'node:util';
import { isAbsolute, join } from 'node:path';
import { manifesteD, STAGING_REF, STAGING_URL, literal as q } from './candidatures-fixture-contract.mjs';
export { STAGING_REF, STAGING_URL };
export { ORIGINE_UI } from './dashboard-ui-contract.mjs';
import { ORIGINE_UI } from './dashboard-ui-contract.mjs';

export function configurationFrontendD(env, now = Date.now(), action = 'run') {
  if (!['check','catalogue','verify-preview','prepare','run','snapshot','cleanup','verify-cleanup'].includes(action)) throw new Error('Action UI D2 inconnue.');
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ') throw new Error('D2 UI manuel uniquement.');
  if (env.LOAD_D_FRONTEND_ONLY !== 'true' || env.LOAD_D_SQL_ONLY !== 'false' || env.LOAD_D_SQL_JOUR
    || env.LOAD_TEST_SCENARIO !== '04-candidatures-simultanees' || env.DASHBOARD_FIXTURE_ONLY !== 'false'
    || env.DIAGNOSTIC_SQL !== 'false' || env.LOAD_TEST_VUS || env.LOAD_TEST_DURATION || env.LOAD_FIXTURE_COUNT) throw new Error('D2 UI exclusif requis.');
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING_REF || env.STAGING_SUPABASE_URL !== STAGING_URL) throw new Error('Staging D2 exact requis.');
  if (!/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID || '') || !/^[1-9][0-9]{0,5}$/.test(env.GITHUB_RUN_ATTEMPT || '')
    || !/^[a-f0-9]{40}$/.test(env.GITHUB_SHA || '') || !isAbsolute(env.RUNNER_TEMP || '')) throw new Error('Run et dossier privé CI requis.');
  if (typeof env.LOAD_D_JOUR !== 'string') throw new Error('Jour D2 ISO explicite requis.');
  const m = manifesteD(`ui-d2-ci-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}`, env.LOAD_D_JOUR);
  const debut = Date.parse(m.debut);
  // La fenêtre protège la création et le parcours. Un lot déjà lancé doit
  // rester nettoyable après cette borne, avec les mêmes IDs et jour exacts.
  const reprise = ['snapshot','cleanup','verify-cleanup'].includes(action);
  if (!Number.isFinite(now) || (!reprise && (debut <= now + 86400000 || debut > now + 31 * 86400000))) throw new Error('Jour D2 futur entre un et 31 jours requis.');
  return { m, env: { ...env, LOAD_TEST_RUN_ID: m.runId, LOAD_D_MANIFEST: join(env.RUNNER_TEMP, 'd2-frontend-manifest.json'), LOAD_D_EXECUTION_APPROUVEE: 'DEUX_PROFILS' } };
}
export function identitesFrontendD(env, m) {
  let data; try { data = JSON.parse(env.LOAD_CANDIDATURES_JSON); } catch { throw new Error('Identités privées D2 absentes.'); }
  if (!data || !egal(Object.keys(data).sort(), [...Object.keys(m), 'identites'].sort())
    || Object.keys(m).some(k => !egal(data[k], m[k])) || !Array.isArray(data.identites) || data.identites.length !== 3) throw new Error('Identités D2 étrangères.');
  for (const [i, a] of data.identites.entries()) {
    if (!egal(Object.keys(a).sort(), [...Object.keys(m.membres[i]), 'password'].sort()) || Object.keys(m.membres[i]).some(k => a[k] !== m.membres[i][k])
      || typeof a.password !== 'string' || a.password.length < 32 || /[\r\n]/.test(a.password)) throw new Error('Identité D2 altérée.');
  }
  if (new Set(data.identites.map(a => a.password)).size !== 3) throw new Error('Mots de passe D2 distincts requis.');
  return data.identites;
}
export const rpcLectureD = new Set(['fn_get_my_role','fn_compte_auth_actif','fn_messages_non_lus','fn_dashboard_soignant_complet',
  'fn_mon_profil_soignant_complet','fn_mon_etablissement_complet','fn_stats_dashboard_etablissement','fn_mes_soignants_etablissement']);
export const rpcParametresD = new Set(['fn_etablissement_public','fn_etablissements_safe','fn_soignant_pour_etablissement','fn_mes_permissions_etab','fn_note_moyenne','fn_mode_exercice','fn_est_bloque','fn_mon_score_etab','fn_bfa_info']);
export const rpcEcritureD = new Set(['fn_audit_connexion','fn_maj_activite_soignant','fn_ecrire_audit_safe','fn_confirmer_action_planning_v1']);
export const tablesLectureD = new Set(['soignants','etablissements','missions','mission_creneaux','candidatures','notifications','contrats_mission',
  'documents_soignants','stripe_connect_onboarding','litiges','parcours_inscription','notations_missions','evaluations','paliers_commission','documents_requis_par_profession']);
const exact = (body, attendu) => egal(body ?? {}, attendu);
const instantExact = (value, attendu) => typeof value === 'string'
  && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3}0{0,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)
  && Date.parse(value) === Date.parse(attendu);
export function requeteFrontendD({ url, method, body }, a, m) {
  let u; try { u = new URL(url); } catch { return false; }
  if (u.username || u.password) return false;
  if (u.origin === ORIGINE_UI) return method === 'GET' && !/^\/(auth|rest|functions|storage)\//.test(u.pathname);
  if (u.origin !== STAGING_URL) return false;
  const rpc = u.pathname.startsWith('/rest/v1/rpc/') ? u.pathname.slice('/rest/v1/rpc/'.length) : null;
  const table = u.pathname.startsWith('/rest/v1/') ? u.pathname.slice('/rest/v1/'.length) : null;
  // Deux cartes du dashboard, auditées LIVE : lectures STABLE du tenant
  // courant. Aucun paramètre, année libre ou accès depuis un slot soignant.
  if (rpc === 'fn_mon_score_etab' || rpc === 'fn_bfa_info') {
    return a.slot === 2 && !u.search && (method === 'OPTIONS' ? body === undefined : method === 'POST' && egal(body, {}));
  }
  if (method === 'OPTIONS') return ['/auth/v1/token','/auth/v1/user'].includes(u.pathname) || rpcLectureD.has(rpc) || rpcParametresD.has(rpc) || rpcEcritureD.has(rpc) || tablesLectureD.has(table);
  if (u.pathname === '/auth/v1/token') return method === 'POST' && u.search === '?grant_type=password' && body?.email === a.email && body?.password === a.password
    && Object.keys(body).every(k => ['email','password','gotrue_meta_security'].includes(k)) && (body.gotrue_meta_security === undefined || exact(body.gotrue_meta_security, {}));
  if (u.pathname === '/auth/v1/user') return method === 'GET' && !u.search;
  if (rpc) {
    if (method !== 'POST' || u.search) return false;
    if (rpc === 'fn_audit_connexion') return exact(body, { p_action: 'CONNEXION' });
    if (rpc === 'fn_maj_activite_soignant') return a.slot < 2 && exact(body, {});
    if (rpc === 'fn_ecrire_audit_safe') return a.slot === 2 && typeof body?.p_navigateur === 'string' && body.p_navigateur.length < 512
      && exact(body, { p_acteur_id:a.userId,p_type_acteur:'ADMIN_ETABLISSEMENT',p_action:'DONNEES_PERSO_CONSULTATION',p_type_ressource:'etablissement',p_id_ressource:a.userId,p_cle_s3:null,p_details:{page:'dashboard_etablissement'},p_ip:null,p_navigateur:body.p_navigateur });
    if (rpc === 'fn_confirmer_action_planning_v1') {
      const c=body?.p_creneaux_confirmes;
      // PostgREST utilise +00:00 ; le navigateur conserve ces chaînes. Comparer
      // les instants exacts, sans accepter dates locales ou précision tronquée.
      return a.slot < 2 && Array.isArray(c) && c.length===1 && exact(Object.keys(c[0]||{}).sort(),['debut','fin'])
        && instantExact(c[0].debut,m.debut) && instantExact(c[0].fin,m.fin)
        && exact(body, { p_mission_id:m.missionId,p_action:'POSTULER',p_creneaux_confirmes:c,p_message:m.marker,p_choix_contrat:null,p_candidature_id:null });
    }
    if (rpcLectureD.has(rpc)) return exact(body, {});
    if (rpc === 'fn_etablissement_public') return exact(body, { p_etablissement_id:m.membres[2].userId });
    if (rpc === 'fn_etablissements_safe') return exact(body, { p_ids:[m.membres[2].userId] });
    if (rpc === 'fn_soignant_pour_etablissement') return a.slot === 2 && m.membres.slice(0,2).some(s => exact(body, {p_soignant_id:s.userId}));
    if (rpc === 'fn_mes_permissions_etab') return a.slot === 2 && [null,a.userId].some(id => exact(body, {p_etablissement_id:id}));
    if (rpc === 'fn_note_moyenne') return exact(body, {p_user_id:m.membres[2].userId});
    if (rpc === 'fn_mode_exercice') return exact(body, {p_profession:'AS',p_type_etab:'CLINIQUE_PRIVEE',p_finess_secteur:null});
    if (rpc === 'fn_est_bloque') return exact(body, {p_cible_id:m.membres[2].userId});
    return false;
  }
  if (!['GET','HEAD'].includes(method) || !tablesLectureD.has(table)) return false;
  const eq = (cle,id) => u.searchParams.getAll(cle).length === 1 && u.searchParams.get(cle) === `eq.${id}`;
  const lot = (cle,ids) => eq(cle,ids[0]) || (u.searchParams.getAll(cle).length === 1 && /^in\.\(.+\)$/.test(u.searchParams.get(cle) || '') && u.searchParams.get(cle).slice(4,-1).split(',').every(id=>ids.includes(id.replaceAll('"',''))));
  if (['paliers_commission','documents_requis_par_profession'].includes(table)) return true;
  if (table === 'missions') {
    // DashboardSoignant complète le planning après son RPC avec cette seule
    // projection. Aucun autre ID, prédicat ou jeu de colonnes n'est admis ici.
    const metadataDashboard = a.slot<2 && method==='GET' && u.searchParams.size===2
      && u.searchParams.getAll('select').length===1 && u.searchParams.get('select')==='id,nb_creneaux'
      && u.searchParams.getAll('id').length===1 && u.searchParams.get('id')===`in.(${m.missionId})`;
    return metadataDashboard || eq('id',m.missionId) || eq('etablissement_id',m.membres[2].userId) || (a.slot<2 && eq('soignant_assigne_id',a.userId));
  }
  if (['mission_creneaux','candidatures','contrats_mission'].includes(table)) return lot('mission_id',[m.missionId]);
  if (table === 'notifications') return eq('destinataire_id',a.userId);
  if (table === 'etablissements') return eq('id',m.membres[2].userId);
  if (table === 'soignants') return lot('id',a.slot<2?[a.userId]:m.membres.slice(0,2).map(s=>s.userId));
  if (table === 'parcours_inscription') return eq('user_id',a.userId);
  return eq('soignant_id',a.userId) || lot('mission_id',[m.missionId]);
}

/** Un seul exemplaire de chaque écriture attendue, consommé AVANT réseau. */
export function budgetEcrituresD(a) {
  const compte = new Map();
  const attendus = new Set(['auth-token','fn_audit_connexion',...(a.slot<2?['fn_maj_activite_soignant','fn_confirmer_action_planning_v1']:['fn_ecrire_audit_safe'])]);
  return { consommer(nom) { if (!attendus.has(nom) || compte.has(nom)) throw new Error('Écriture D2 hors budget.'); compte.set(nom,1); },
    complet() { return compte.size === attendus.size; }, projection() { return Object.fromEntries(compte); } };
}
export function sqlAuditsFrontendD(m) {
  return `WITH membres(slot,id,role) AS (VALUES ${m.membres.map(a=>`(${a.slot},${q(a.userId)}::uuid,${q(a.role)})`).join(',')}) SELECT m.slot,
  (SELECT count(*)::integer FROM public.journaux_audit WHERE acteur_id=m.id) AS total,
  (SELECT count(*)::integer FROM public.journaux_audit WHERE acteur_id=m.id AND action='CONNEXION' AND type_acteur=m.role AND type_ressource='session' AND id_ressource=m.id AND details->>'method'='email_password') AS connexions,
  (SELECT count(*)::integer FROM public.journaux_audit WHERE acteur_id=m.id AND m.slot=2 AND action='DONNEES_PERSO_CONSULTATION' AND type_acteur=m.role AND type_ressource='etablissement' AND id_ressource=m.id AND details='{"page":"dashboard_etablissement"}'::jsonb) AS consultation,
  (SELECT derniere_activite_le IS NOT NULL FROM public.soignants WHERE id=m.id) AS activite,
  (SELECT md5(derniere_activite_le::text) FROM public.soignants WHERE id=m.id) AS activite_empreinte,
  (SELECT count(*)::integer FROM public.presence_status WHERE user_id=m.id) AS presences,
  (SELECT count(*)::integer FROM public.tokens_push WHERE utilisateur_id=m.id) AS push,
  (SELECT count(*)::integer FROM public.email_queue WHERE destinataire_id=m.id OR data->>'mission_id'=${q(m.missionId)}) AS emails
  FROM membres m ORDER BY slot;`;
}
export function projectionAuditsD(rows) {
  const champs = ['slot','total','connexions','consultation','activite','activite_empreinte','presences','push','emails'];
  if (!Array.isArray(rows) || rows.length !== 3 || rows.some((r,i)=>r?.slot!==i || champs.filter(k=>!['activite','activite_empreinte'].includes(k)).some(k=>!Number.isInteger(r[k])||r[k]<0) || ![null,true,false].includes(r.activite) || (r.activite_empreinte!==null&&!/^[a-f0-9]{32}$/.test(r.activite_empreinte||'')))) throw new Error('Compteurs UI D2 incomplets.');
  return rows.map(r=>Object.fromEntries(champs.map(k=>[k,r[k]])));
}
export function verifierAuditsD(rows, phase, avantCleanup) {
  rows = projectionAuditsD(rows);
  if (rows.some(r=>r.presences!==0||r.push!==0||r.emails!==0||r.total!==r.connexions+r.consultation)) throw new Error('Effet UI D2 hors contrat.');
  if (phase==='avant' && rows.some(r=>r.total!==0)) throw new Error('Audits UI D2 préexistants.');
  if (phase==='apres' && rows.some(r=>r.connexions!==1||r.consultation!==(r.slot===2?1:0)||(r.slot<2&&(r.activite!==true||!avantCleanup||r.activite_empreinte===avantCleanup[r.slot]?.activite_empreinte)))) throw new Error('Écritures UI D2 non confirmées.');
  if (phase==='cleanup' && (!avantCleanup || rows.some((r,i)=>['total','connexions','consultation'].some(k=>r[k]!==avantCleanup[i]?.[k])||r.activite!==null||r.activite_empreinte!==null))) throw new Error('Audits D2 non conservés ou profil restant.');
  return rows;
}
