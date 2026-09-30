import { createHash, randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { STAGING_REF, STAGING_URL } from './prepare-load-fixtures.mjs';
import { dashboardFixtureValide, exigerDashboardMetier } from '../../tests/load/helpers/contrats.js';

const literal = value => `'${String(value).replaceAll("'", "''")}'`;
export function configurationDashboard(env) {
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING_REF || env.STAGING_SUPABASE_URL !== STAGING_URL) {
    throw new Error('Fixture dashboard réservée au staging Jolene.');
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(env.LOAD_TEST_RUN_ID ?? '')) throw new Error('Run dashboard explicite requis.');
  return { runId: env.LOAD_TEST_RUN_ID,
    manifestPath: resolve(env.LOAD_DASHBOARD_MANIFEST || 'tests/load/results/fixture-dashboard-manifest.json') };
}
export function manifesteDashboard({ runId }) {
  const h = createHash('sha256').update(`jolene-load-dashboard-v1:${STAGING_REF}:${runId}`).digest('hex');
  const userId = `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;
  return { version: 1, projectRef: STAGING_REF, runId, userId,
    email: `recette-dashboard-${userId}@example.invalid`, marker: `RECETTE DASHBOARD ${runId}`, profession: 'AS',
    prenom: 'Recette', nom: `Dashboard ${userId}` };
}
export function utilisateurFixtureValide(user, m) {
  return user?.id === m.userId && user.email === m.email && user.app_metadata?.role === 'SOIGNANT'
    && user.app_metadata.est_compte_test === true && user.app_metadata.is_test_playwright === true
    && user.app_metadata.load_fixture_kind === 'DASHBOARD' && user.app_metadata.load_fixture_run === m.runId;
}
const hashTriggers = (table, bit) => `(SELECT md5(string_agg(tgname || ':' || tgtype::text || ':' || tgenabled::text || ':' || md5(pg_get_functiondef(tgfoid)), '|' ORDER BY tgname))
  FROM pg_trigger WHERE tgrelid='${table}'::regclass AND NOT tgisinternal AND tgenabled <> 'D' AND (tgtype&${bit})<>0)`;
// Définitions de tous les triggers concernés relues sur staging le 25/09/2026.
const gardes = `
  IF EXISTS (SELECT 1 FROM cron.job WHERE active) THEN RAISE EXCEPTION 'Cron staging actif'; END IF;
  IF auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'Identité Management sans utilisateur requise'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Lecture complète des dépendances requise'; END IF;
  IF ${hashTriggers('public.soignants',4)} IS DISTINCT FROM '17824a99822321af3c3150b1009757f7'
    OR ${hashTriggers('auth.users',8)} IS DISTINCT FROM 'cc475f9517e0f6e3be8e5070c1829195'
    OR ${hashTriggers('public.preferences_notifications','(4|16)')} IS DISTINCT FROM '2618b424c236bdc9e3a9d67e3cd067e5'
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND tgenabled <> 'D' AND (
      (tgrelid='auth.users'::regclass AND (tgtype&(4|16))<>0)
      OR (tgrelid IN ('public.soignants'::regclass,'public.preferences_notifications'::regclass) AND (tgtype&8)<>0)))
    THEN RAISE EXCEPTION 'Trigger non prévu : fixture abandonnée'; END IF;
`;
const authAppartient = m => `u.id=${literal(m.userId)}::uuid AND u.email=${literal(m.email)}
  AND u.raw_app_meta_data->>'role'='SOIGNANT'
  AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
  AND u.raw_app_meta_data->'is_test_playwright'='true'::jsonb
  AND u.raw_app_meta_data->>'load_fixture_kind'='DASHBOARD'
  AND u.raw_app_meta_data->>'load_fixture_run'=${literal(m.runId)}`;
const entete = m => `BEGIN;
SET LOCAL statement_timeout='25s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{}';
SET LOCAL request.jwt.claim.sub='';
SET LOCAL request.jwt.claim.role='';
DO $fixture_lock$ BEGIN PERFORM pg_advisory_xact_lock(${BigInt('0x'+createHash('sha256').update(`dashboard:${m.userId}`).digest('hex').slice(0,15))}::bigint); END $fixture_lock$;
`;

export function sqlVerifierDashboardAvantAuth(m) {
  return `${entete(m)}DO $fixture_guard$ BEGIN
${gardes}
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=${literal(m.userId)}::uuid OR email=${literal(m.email)})
    OR EXISTS (SELECT 1 FROM public.soignants WHERE id=${literal(m.userId)}::uuid) THEN
    RAISE EXCEPTION 'Identité du run déjà présente : aucune réutilisation'; END IF;
END $fixture_guard$;
ROLLBACK;
SELECT true AS pret;`;
}
export function sqlPreparerDashboard(m) {
  return `${entete(m)}DO $fixture_profile$ BEGIN
${gardes}
  PERFORM 1 FROM auth.users u WHERE ${authAppartient(m)} FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Identité test du run non confirmée'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=${literal(m.userId)}::uuid
    AND raw_app_meta_data->'load_cleanup_pending'='true'::jsonb) THEN
    RAISE EXCEPTION 'Nettoyage déjà commencé'; END IF;
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id=${literal(m.userId)}::uuid) THEN
    RAISE EXCEPTION 'Profil préexistant refusé'; END IF;
  INSERT INTO public.soignants (id,prenom,nom,email,profession,type_exercice,est_compte_test,
    source_acquisition,sms_actif,sms_alertes_actives,telephone,numero_rpps,numero_adeli,
    identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides)
  VALUES (${literal(m.userId)}::uuid,${literal(m.prenom)},${literal(m.nom)},${literal(m.email)},'AS','SALARIE',true,
    ${literal(m.marker)},false,false,NULL,NULL,NULL,false,false,false,false);
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id=${literal(m.userId)}::uuid;
  IF NOT EXISTS (SELECT 1 FROM public.soignants WHERE id=${literal(m.userId)}::uuid
      AND est_compte_test AND profession='AS' AND NOT identite_verifiee AND NOT tous_documents_valides)
    OR NOT EXISTS (SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id=${literal(m.userId)}::uuid
      AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app) THEN
    RAISE EXCEPTION 'Profil test ou transports non confirmés'; END IF;
END $fixture_profile$;
COMMIT;
SELECT true AS profil_prepare;`;
}
export function sqlNettoyerDashboard(m) {
  return `${entete(m)}DO $fixture_cleanup$
DECLARE v_fk record; v_count bigint;
BEGIN
${gardes}
  PERFORM 1 FROM auth.users WHERE id=${literal(m.userId)}::uuid FOR UPDATE;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=${literal(m.userId)}::uuid)
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE ${authAppartient(m)}) THEN
    RAISE EXCEPTION 'Compte hors fixture : nettoyage refusé'; END IF;
  PERFORM 1 FROM public.soignants WHERE id=${literal(m.userId)}::uuid FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id=${literal(m.userId)}::uuid AND
    (email IS DISTINCT FROM ${literal(m.email)} OR source_acquisition IS DISTINCT FROM ${literal(m.marker)}
      OR prenom IS DISTINCT FROM ${literal(m.prenom)} OR nom IS DISTINCT FROM ${literal(m.nom)}
      OR est_compte_test IS DISTINCT FROM true OR profession IS DISTINCT FROM 'AS'
      OR identite_verifiee OR diplome_verifie OR rpps_verifie OR tous_documents_valides
      OR telephone IS NOT NULL OR stripe_account_id IS NOT NULL OR mandat_facturation_signe)) THEN
    RAISE EXCEPTION 'Profil modifié : nettoyage manuel requis'; END IF;
  -- Refuser toutes les dépendances métier, même quand leur FK permet CASCADE.
  -- Seules identité/session techniques Auth et préférences créées par le trigger sont attendues.
  FOR v_fk IN SELECT c.conrelid::regclass AS enfant,c.conkey,c.confkey,a.attname AS colonne,ref.attname AS colonne_parent
    FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
    JOIN pg_attribute ref ON ref.attrelid=c.confrelid AND ref.attnum=c.confkey[1]
    WHERE c.contype='f' AND c.confrelid IN ('public.soignants'::regclass,'auth.users'::regclass)
      AND c.conrelid NOT IN ('auth.identities'::regclass,'auth.sessions'::regclass,'public.preferences_notifications'::regclass)
  LOOP
    IF cardinality(v_fk.conkey)<>1 OR cardinality(v_fk.confkey)<>1 OR v_fk.colonne_parent<>'id' THEN
      RAISE EXCEPTION 'Dépendance composite ou clé référencée non prévue'; END IF;
    EXECUTE format('SELECT count(*) FROM %s WHERE %I=$1',v_fk.enfant,v_fk.colonne)
      INTO v_count USING ${literal(m.userId)}::uuid;
    IF v_count>0 THEN RAISE EXCEPTION 'Dépendance métier : nettoyage refusé'; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE destinataire_id=${literal(m.userId)}::uuid) THEN
    RAISE EXCEPTION 'Notification non prévue : nettoyage refusé'; END IF;
  -- Le même verrou que prepare + marqueur privé empêchent un seed SQL retardé.
  UPDATE auth.users SET raw_app_meta_data=raw_app_meta_data || '{"load_cleanup_pending":true}'::jsonb
    WHERE id=${literal(m.userId)}::uuid;
  DELETE FROM public.preferences_notifications WHERE utilisateur_id=${literal(m.userId)}::uuid;
  DELETE FROM public.soignants WHERE id=${literal(m.userId)}::uuid;
END $fixture_cleanup$;
COMMIT;
SELECT (SELECT count(*)::integer FROM public.soignants WHERE id=${literal(m.userId)}::uuid) AS profils_restants;`;
}
export function sqlConfirmerNettoyageDashboard(m) {
  return `SELECT (SELECT count(*)::integer FROM auth.users WHERE id=${literal(m.userId)}::uuid) AS auth_restants,
    (SELECT count(*)::integer FROM public.soignants WHERE id=${literal(m.userId)}::uuid) AS profils_restants,
    (SELECT count(*)::integer FROM public.preferences_notifications WHERE utilisateur_id=${literal(m.userId)}::uuid) AS preferences_restantes;`;
}

export async function executerFixtureDashboard({ action, env=process.env, fetchImpl=fetch, log=console.log,
  genererMotDePasse=()=>`Aa1!${randomBytes(36).toString('base64url')}`, transmettreIdentite }={}) {
  if (!['prepare','cleanup'].includes(action)) throw new Error('Action dashboard attendue : prepare ou cleanup.');
  const c=configurationDashboard(env); const m=manifesteDashboard(c);
  const management=env.STAGING_SUPABASE_ACCESS_TOKEN, service=env.STAGING_SUPABASE_SERVICE_ROLE_KEY, anon=env.STAGING_SUPABASE_ANON_KEY;
  if (!management || !service || !anon) throw new Error('Accès staging incomplets.');
  const save = status => writeFileSync(c.manifestPath,JSON.stringify({...m,status},null,2)+'\n',{mode:0o600});
  const request = async (url,{method='GET',body,auth=service,apikey=service,absent=false}={}) => {
    let r;
    try { r=await fetchImpl(url,{method,redirect:'error',headers:{Authorization:`Bearer ${auth}`,apikey,'Content-Type':'application/json'},
      ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(35_000)}); }
    catch { throw new Error('Réponse staging ambiguë : manifeste conservé, aucun succès déduit.'); }
    if (absent && r.status===404) return null;
    if (!r.ok) throw new Error(`Requête staging refusée (HTTP ${Number(r.status)||0}), manifeste conservé.`);
    try { return await r.json(); } catch { throw new Error('Réponse JSON staging invalide.'); }
  };
  const sql = query => request(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`,{method:'POST',body:{query},auth:management,apikey:management});
  const userURL=`${STAGING_URL}/auth/v1/admin/users/${m.userId}`;
  if (action==='cleanup') {
    if (!existsSync(c.manifestPath)) { log('Aucun manifeste dashboard : aucun compte supprimé.'); return {skipped:true}; }
    let fichier; try { fichier=JSON.parse(readFileSync(c.manifestPath,'utf8')); } catch { throw new Error('Manifeste dashboard invalide.'); }
    if (Object.keys(m).some(key=>JSON.stringify(fichier[key])!==JSON.stringify(m[key]))) throw new Error('Manifeste dashboard incohérent.');
    if (!['planned','auth-created','prepared','cleanup-started','cleaned'].includes(fichier.status)) throw new Error('État de manifeste dashboard invalide.');
    const user=await request(userURL,{absent:true});
    if (user && !utilisateurFixtureValide(user,m)) throw new Error('Identité hors fixture : suppression refusée.');
    if (!user && fichier.status==='planned') throw new Error('Création Auth ambiguë et compte absent : conserver le manifeste pour contrôle ultérieur.');
    save('cleanup-started');
    const [nettoyage]=await sql(sqlNettoyerDashboard(m));
    if (nettoyage?.profils_restants!==0) throw new Error('Nettoyage du profil non confirmé.');
    if (user) {
      const garde=await request(userURL,{absent:true});
      if (garde) {
        if (!utilisateurFixtureValide(garde,m) || garde.app_metadata.load_cleanup_pending!==true) throw new Error('Garde finale Auth non confirmée.');
        await request(userURL,{method:'DELETE',body:{should_soft_delete:false}});
      }
    }
    const [verification]=await sql(sqlConfirmerNettoyageDashboard(m));
    if (verification?.auth_restants!==0 || verification.profils_restants!==0 || verification.preferences_restantes!==0) throw new Error('Nettoyage dashboard incomplet.');
    save('cleaned'); log('Fixture dashboard nettoyée : zéro compte, profil et préférence du run restants.');
    return verification;
  }
  if (!env.GITHUB_ENV) throw new Error('GITHUB_ENV requis pour transmettre le secret sans artifact.');
  const password=genererMotDePasse();
  if (typeof password!=='string' || password.length<32 || /[\r\n]/.test(password)) throw new Error('Mot de passe aléatoire invalide.');
  const [garde]=await sql(sqlVerifierDashboardAvantAuth(m));
  if (garde?.pret!==true) throw new Error('Préconditions dashboard non confirmées.');
  mkdirSync(dirname(c.manifestPath),{recursive:true});
  writeFileSync(c.manifestPath,JSON.stringify({...m,status:'planned'},null,2)+'\n',{flag:'wx',mode:0o600});
  log(`::add-mask::${password}`);
  const user=await request(`${STAGING_URL}/auth/v1/admin/users`,{method:'POST',body:{id:m.userId,email:m.email,password,email_confirm:true,
    app_metadata:{role:'SOIGNANT',est_compte_test:true,is_test_playwright:true,load_fixture_kind:'DASHBOARD',load_fixture_run:m.runId}}});
  if (!utilisateurFixtureValide(user,m)) throw new Error('Création Auth du run non confirmée.');
  save('auth-created');
  const [profil]=await sql(sqlPreparerDashboard(m));
  if (profil?.profil_prepare!==true) throw new Error('Profil dashboard non confirmé.');
  const session=await request(`${STAGING_URL}/auth/v1/token?grant_type=password`,{method:'POST',body:{email:m.email,password},auth:anon,apikey:anon});
  if (!session?.access_token || !utilisateurFixtureValide(session.user,m)) throw new Error('Login du compte dédié non confirmé.');
  const dashboard=await request(`${STAGING_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`,{method:'POST',body:{},auth:session.access_token,apikey:anon});
  exigerDashboardMetier(dashboard);
  if (!dashboardFixtureValide(dashboard,m.userId)) throw new Error('Profil de recette minimal du run attendu.');
  if (transmettreIdentite) transmettreIdentite({runId:m.runId,userId:m.userId,email:m.email,password});
  else for (const [name,value] of Object.entries({LOAD_DASHBOARD_EMAIL:m.email,LOAD_DASHBOARD_PASSWORD:password,LOAD_DASHBOARD_USER_ID:m.userId})) {
    appendFileSync(env.GITHUB_ENV,`${name}=${value}\n`);
  }
  save('prepared'); log('Fixture E prête : un seul profil AS minimal non vérifié ; aucun compte fixe utilisé.');
  return {userId:m.userId,profession:'AS',identites:1};
}
if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  try { await executerFixtureDashboard({action:process.argv[2]}); }
  catch (error) { console.error(error.message); process.exitCode=1; }
}
