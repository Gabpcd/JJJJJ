import { readFileSync } from 'node:fs';
import { STAGING_REF, STAGING_URL } from './prepare-load-fixtures.mjs';
import { manifestePoolDashboard } from './prepare-dashboard-pool.mjs';
import { lirePoolDashboard } from '../../tests/load/helpers/dashboard-pool.js';

export const ORIGINE_UI = 'http://localhost:5173';
export const contratEcritures = JSON.parse(readFileSync(new URL('./dashboard-ui-write-contract.json', import.meta.url), 'utf8'));
const triggers = {
  dec_age_minimum: ['soignants', 23, 'dec_verifier_age_minimum'],
  dec_bloquer_desinscrip: ['soignants', 19, 'dec_bloquer_desinscription_missions'],
  trg_00_verrouiller_transition_liberale: ['soignants', 19, 'fn_verrouiller_transition_liberale'],
  trg_protect_adeli_verification: ['soignants', 19, 'fn_protect_adeli_verification'],
  trg_protect_soignant_verification: ['soignants', 19, 'fn_protect_soignant_verification'],
  trg_protect_specialite_medicale_verifiee: ['soignants', 19, 'fn_protect_specialite_medicale_verifiee'],
  trg_proteger_verification_siret_liberal: ['soignants', 19, 'fn_proteger_verification_siret_liberal'],
  trg_sync_types_contrat: ['soignants', 19, 'dec_sync_types_contrat_exercice'],
  trg_verifier_type_exercice: ['soignants', 23, 'dec_verifier_type_exercice_profession'],
  trg_mirror_teleportation_alerte_systeme: ['journaux_audit', 5, 'fn_mirror_teleportation_alerte_systeme'],
};
export function configurationUI(env) {
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING_REF || env.STAGING_SUPABASE_URL !== STAGING_URL
    || !env.STAGING_SUPABASE_ACCESS_TOKEN || !env.STAGING_SUPABASE_ANON_KEY) throw new Error('UI réservée au staging, accès existants requis.');
  const pool = lirePoolDashboard(env.LOAD_DASHBOARD_POOL_JSON, env.LOAD_TEST_RUN_ID);
  const attendus = manifestePoolDashboard(env.LOAD_TEST_RUN_ID).membres;
  if (pool.some((m, i) => m.userId !== attendus[i].userId)) throw new Error('Pool UI différent du manifeste déterministe.');
  return pool.slice(0, 2);
}
export const sqlGardeUI = `WITH triggers_ui AS (SELECT t.*,c.relname,p.proname,pn.nspname
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace pn ON pn.oid=p.pronamespace
    WHERE NOT t.tgisinternal AND t.tgenabled<>'D' AND (
      (t.tgrelid='public.soignants'::regclass AND (t.tgtype&16)<>0 AND (t.tgattr=''::int2vector
        OR EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=t.tgrelid AND a.attnum=ANY(t.tgattr::smallint[]) AND a.attname='derniere_activite_le')))
      OR (t.tgrelid='public.journaux_audit'::regclass AND (t.tgtype&4)<>0))
) SELECT
  (SELECT count(*)::integer FROM cron.job WHERE active) AS crons_actifs,
  (SELECT count(*)::integer FROM pg_proc WHERE pronamespace='public'::regnamespace
    AND proname IN (${Object.keys(contratEcritures).map(n => `'${n}'`).join(',')})) AS fonctions_count,
  (SELECT count(*)::integer FROM pg_constraint WHERE contype='f' AND conrelid='public.journaux_audit'::regclass
    AND confrelid IN ('auth.users'::regclass,'public.soignants'::regclass)) AS audit_fk,
  (SELECT coalesce(jsonb_object_agg(p.proname,jsonb_build_object('source_md5',md5(p.prosrc),'security_definer',p.prosecdef,
    'config',p.proconfig,'owner',pg_get_userbyid(p.proowner))), '{}'::jsonb)
    FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
    AND p.proname IN (${Object.keys(contratEcritures).map(n => `'${n}'`).join(',')})) AS fonctions,
  (SELECT count(*)::integer FROM triggers_ui) AS triggers_count,
  (SELECT coalesce(jsonb_object_agg(t.tgname,jsonb_build_object('table',t.relname,'type',t.tgtype,
    'fonction',t.proname,'schema_fonction',t.nspname,'enabled',t.tgenabled,'condition',pg_get_expr(t.tgqual,t.tgrelid),
    'arguments',encode(t.tgargs,'hex'))),'{}'::jsonb)
    FROM triggers_ui t) AS triggers;`;

export function verifierGardeUI(data) {
  if (data?.crons_actifs !== 0 || data.audit_fk !== 0) throw new Error('Cron actif ou audit lié par FK : UI refusée.');
  if (data.fonctions_count !== Object.keys(contratEcritures).length) throw new Error('Fonction UI absente ou surchargée.');
  if (JSON.stringify(Object.keys(data.fonctions || {}).sort()) !== JSON.stringify(Object.keys(contratEcritures).sort())) throw new Error('Inventaire fonctions UI inattendu.');
  for (const [nom, attendu] of Object.entries(contratEcritures)) {
    if (Object.keys(attendu).some(k => JSON.stringify(data.fonctions[nom]?.[k]) !== JSON.stringify(attendu[k]))) throw new Error('Définition d’écriture UI différente du contrat revu.');
  }
  if (data.triggers_count !== Object.keys(triggers).length) throw new Error('Nombre de triggers UI inattendu.');
  if (JSON.stringify(Object.keys(data.triggers || {}).sort()) !== JSON.stringify(Object.keys(triggers).sort())) throw new Error('Inventaire triggers UI inattendu.');
  for (const [nom, [table, type, fonction]] of Object.entries(triggers)) {
    const t = data.triggers[nom];
    if (t.table !== table || t.type !== type || t.fonction !== fonction || t.schema_fonction !== 'public'
      || t.enabled !== 'O' || t.condition !== null || t.arguments !== '') throw new Error('Trigger UI différent du contrat revu.');
  }
}
export function projectionEtatUI(lignes) {
  const champs = ['slot','auth','profils','preferences','sessions','identites','profil_empreinte','activite',
    'notifications','presences','audits','audits_connexion','preferences_off'];
  return lignes.map(ligne => Object.fromEntries(champs.map(k => [k, ligne[k]])));
}
export function sqlEtatUI(membres) {
  if (!Array.isArray(membres) || membres.length !== 2 || membres.some((m, i) => m.slot !== i || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-a[a-f0-9]{3}-[a-f0-9]{12}$/.test(m.userId))) throw new Error('Deux UUID UI attendus.');
  const valeurs = membres.map(m => `(${m.slot},'${m.userId}'::uuid)`).join(',');
  return `WITH membres(slot,id) AS (VALUES ${valeurs}) SELECT m.slot,
    (SELECT count(*)::integer FROM auth.users WHERE id=m.id) AS auth,
    (SELECT count(*)::integer FROM public.soignants WHERE id=m.id) AS profils,
    (SELECT count(*)::integer FROM public.preferences_notifications WHERE utilisateur_id=m.id) AS preferences,
    (SELECT count(*)::integer FROM auth.sessions WHERE user_id=m.id) AS sessions,
    (SELECT count(*)::integer FROM auth.identities WHERE user_id=m.id) AS identites,
    (SELECT md5((to_jsonb(s)-'derniere_activite_le')::text) FROM public.soignants s WHERE id=m.id) AS profil_empreinte,
    (SELECT derniere_activite_le FROM public.soignants WHERE id=m.id) AS activite,
    (SELECT count(*)::integer FROM public.notifications WHERE destinataire_id=m.id) AS notifications,
    (SELECT count(*)::integer FROM public.presence_status WHERE user_id=m.id) AS presences,
    (SELECT count(*)::integer FROM public.journaux_audit WHERE acteur_id=m.id) AS audits,
    (SELECT count(*)::integer FROM public.journaux_audit WHERE acteur_id=m.id AND action='CONNEXION' AND type_acteur='SOIGNANT'
      AND type_ressource='session' AND id_ressource=m.id AND details->>'method'='email_password') AS audits_connexion,
    (SELECT count(*)::integer FROM public.preferences_notifications WHERE utilisateur_id=m.id
      AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app) AS preferences_off
    FROM membres m ORDER BY m.slot;`;
}
export function verifierEtatUI(lignes, avant, nettoye = false) {
  if (!Array.isArray(lignes) || lignes.length !== 2 || lignes.some((r, i) => r.slot !== i)) throw new Error('État UI incomplet.');
  for (const [i, r] of lignes.entries()) {
    if (r.notifications !== 0 || r.presences !== 0 || r.audits !== r.audits_connexion || r.audits !== (avant ? 1 : 0)) throw new Error('Effet UI imprévu ou audit connexion non confirmé.');
    if (nettoye) {
      if ([r.auth,r.profils,r.preferences,r.sessions,r.identites].some(n => n !== 0)) throw new Error('Cleanup UI incomplet.');
    } else {
      if (r.auth !== 1 || r.profils !== 1 || r.preferences !== 1 || r.preferences_off !== 1 || r.sessions < 1 || r.identites !== 1
        || !/^[a-f0-9]{32}$/.test(r.profil_empreinte || '')) throw new Error('Profil minimal UI non confirmé.');
      if (avant && (r.profil_empreinte !== avant[i].profil_empreinte || !r.activite || r.activite === avant[i].activite)) throw new Error('Écriture UI du profil inattendue.');
    }
  }
}

const lecturesRpc = new Set(['fn_get_my_role','fn_compte_auth_actif','fn_dashboard_soignant_complet','fn_messages_non_lus',
  'fn_mon_profil_soignant_complet','fn_param_bool','fn_est_bloque']);
const tables = new Set(['soignants','notifications','missions','litiges','stripe_connect_onboarding','documents_requis_par_profession',
  'documents_soignants','evaluations','notations_missions','etablissements','admins_groupe_sante','parcours_inscription']);
export function requeteUIAutorisee({ url, method, body }, membre) {
  const u = new URL(url);
  if (u.origin === ORIGINE_UI) return method === 'GET' && !u.pathname.startsWith('/auth/') && !u.pathname.startsWith('/rest/');
  if (u.origin !== STAGING_URL) return false;
  if (method === 'OPTIONS') return ['/auth/v1/token','/auth/v1/user'].includes(u.pathname)
    || (u.pathname.startsWith('/rest/v1/rpc/') && ['fn_audit_connexion','fn_maj_activite_soignant',...lecturesRpc].includes(u.pathname.slice('/rest/v1/rpc/'.length)))
    || (u.pathname.startsWith('/rest/v1/') && tables.has(u.pathname.slice('/rest/v1/'.length)));
  if (u.pathname === '/auth/v1/token') return method === 'POST' && u.search === '?grant_type=password'
    && body?.email === membre.email && body?.password === membre.password && Object.keys(body).every(k => ['email','password','gotrue_meta_security'].includes(k));
  if (u.pathname === '/auth/v1/user') return method === 'GET';
  if (u.pathname.startsWith('/rest/v1/rpc/')) {
    const nom = u.pathname.slice('/rest/v1/rpc/'.length);
    if (method !== 'POST') return false;
    if (nom === 'fn_audit_connexion') return JSON.stringify(body) === JSON.stringify({ p_action: 'CONNEXION' });
    return nom === 'fn_maj_activite_soignant' ? JSON.stringify(body) === '{}' : lecturesRpc.has(nom);
  }
  return ['GET','HEAD'].includes(method) && u.pathname.startsWith('/rest/v1/') && tables.has(u.pathname.slice('/rest/v1/'.length));
}
