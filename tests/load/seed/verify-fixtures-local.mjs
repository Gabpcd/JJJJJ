// Vérification SQL facultative hors réseau. PGlite doit être déjà disponible.
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { creerManifeste, sqlPreparation, sqlNettoyage } from '../../../scripts/ci/prepare-load-fixtures.mjs';
const db = new PGlite();
await db.exec(`
CREATE SCHEMA cron; CREATE TABLE cron.job(active boolean);
CREATE SCHEMA auth; CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT NULL::uuid$$;
CREATE TYPE public.type_etablissement AS ENUM ('CLINIQUE_PRIVEE','PHARMACIE_OFFICINE');
CREATE TYPE public.type_profession AS ENUM ('IDE','AS','IADE','IBODE','AES','AUXILIAIRE_PUERICULTURE','KINE','SAGE_FEMME','MEDECIN','DENTISTE');
CREATE TYPE public.statut_mission AS ENUM ('OUVERTE','ASSIGNEE','TERMINEE');
CREATE TABLE public.etablissements(id uuid PRIMARY KEY, nom text NOT NULL,siret text UNIQUE NOT NULL,type public.type_etablissement,
 adresse_rue text,adresse_ville text,adresse_code_postal text,email_contact text,est_compte_test boolean,
 statut_verification text,peut_publier_missions boolean,sms_actif boolean,chorus_pro_actif boolean,source_acquisition text,supprime_le timestamptz);
CREATE TABLE public.missions(id uuid PRIMARY KEY,etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),intitule text,description text,
 profession_requise public.type_profession,service text,debut_le timestamptz,fin_le timestamptz,duree_heures numeric,taux_horaire_base numeric,
 statut public.statut_mission,soignant_assigne_id uuid,est_urgente boolean,mode_attribution text,type_contrat_recherche text,cree_le timestamptz DEFAULT now(),
 CHECK(debut_le<fin_le));
CREATE TABLE public.soignants(id uuid,supprime_le timestamptz);
CREATE FUNCTION public.fn_soignant_eligible_mission(uuid,uuid,boolean) RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
CREATE FUNCTION public.fn_est_exclu(uuid,uuid) RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
CREATE TABLE public.audit_outbox(table_name text);
CREATE TABLE public.journaux_audit(id uuid PRIMARY KEY,acteur_id uuid,type_acteur text NOT NULL CHECK(type_acteur='SYSTEME'),
 action text NOT NULL CHECK(action='SYSTEM'),type_ressource text,details jsonb);
CREATE TABLE public.alertes_systeme(type_alerte text,severite text,source text,message text,details jsonb);
CREATE FUNCTION public.proteger_audit() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'Journal immuable';END$$;
CREATE TRIGGER audit_immuable BEFORE UPDATE OR DELETE ON public.journaux_audit FOR EACH ROW EXECUTE FUNCTION public.proteger_audit();
CREATE FUNCTION public.spy_outbound() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN INSERT INTO public.audit_outbox VALUES (TG_TABLE_NAME);RETURN NEW;END$$;
CREATE TRIGGER spy_etab AFTER INSERT ON public.etablissements FOR EACH ROW EXECUTE FUNCTION public.spy_outbound();
CREATE TRIGGER spy_mission AFTER INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION public.spy_outbound();
CREATE TRIGGER spy_disabled AFTER INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION public.spy_outbound();
ALTER TABLE public.missions DISABLE TRIGGER spy_disabled;
CREATE TABLE public.candidatures(id uuid PRIMARY KEY,mission_id uuid REFERENCES public.missions(id) ON DELETE CASCADE);
`);
const migration=readFileSync(new URL('../../../supabase/migrations/20260712163000_lot21_finaliser_cascade_profession_mission.sql',import.meta.url),'utf8');
const begin=migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(');
const end=migration.indexOf('$function$;',begin)+'$function$;'.length;
await db.exec(migration.slice(begin,end));
const miroir=readFileSync(new URL('../../../supabase/migrations/20260712230000_p0_securite_auth_rls.sql',import.meta.url),'utf8');
const miroirBegin=miroir.indexOf('CREATE OR REPLACE FUNCTION public.fn_mirror_teleportation_alerte_systeme()');
const miroirEnd=miroir.indexOf('\n$$;',miroirBegin)+'\n$$;'.length;
await db.exec(miroir.slice(miroirBegin,miroirEnd));
await db.exec('CREATE TRIGGER trg_mirror_teleportation_alerte_systeme AFTER INSERT ON public.journaux_audit FOR EACH ROW EXECUTE FUNCTION public.fn_mirror_teleportation_alerte_systeme();');
for (const [file,name] of [
  ['20260714122337_corriger_compteurs_heures_canoniques.sql','dec_maj_compteurs_soignant'],
  ['20260810173851_securiser_transition_candidature_transactionnelle.sql','fn_enforce_etablissement_rbac_trigger'],
]) {
  const source=readFileSync(new URL(`../../../supabase/migrations/${file}`,import.meta.url),'utf8');
  const start=source.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  const declaration=source.slice(start).match(/AS (\$[a-zA-Z_]*\$)/);
  assert.ok(start>=0&&declaration,`Définition canonique ${name} présente`);
  const stop=source.indexOf(declaration[1]+';',start+declaration.index+declaration[0].length)+declaration[1].length+1;
  await db.exec(source.slice(start,stop));
}
await db.exec(`CREATE FUNCTION public.est_admin() RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
 CREATE TRIGGER dec_maj_compteurs AFTER INSERT OR UPDATE OR DELETE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.dec_maj_compteurs_soignant();
 CREATE TRIGGER trg_p0_rbac_missions BEFORE INSERT OR UPDATE OR DELETE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_etablissement_rbac_trigger('missions');`);
const m=creerManifeste({runId:'local-sql-20260925',count:500});
// PGlite n’a qu’une session : prouve acquisition/libération réelle, pas la contention multi-session.
async function avecVerrouVerifie(sql) {
  const commit=sql.indexOf('COMMIT;');
  await db.exec(sql.slice(0,commit));
  assert.equal((await db.query("SELECT count(*)::int AS n FROM pg_locks WHERE locktype='advisory' AND granted")).rows[0].n,1);
  await db.exec(sql.slice(commit));
  assert.equal((await db.query("SELECT count(*)::int AS n FROM pg_locks WHERE locktype='advisory' AND granted")).rows[0].n,0);
}
await avecVerrouVerifie(sqlPreparation(m));
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.missions')).rows[0].n,500);
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.audit_outbox')).rows[0].n,0);
assert.equal((await db.query("SELECT count(*)::int AS n FROM public.fn_missions_publiques_recherche(NULL,NULL)")).rows[0].n,500);
assert.equal((await db.query('SHOW session_replication_role')).rows[0].session_replication_role,'origin');
assert.deepEqual((await db.query("SELECT tgname,tgenabled FROM pg_trigger WHERE tgname IN ('spy_etab','spy_mission','spy_disabled') ORDER BY tgname")).rows,
  [{tgname:'spy_disabled',tgenabled:'D'},{tgname:'spy_etab',tgenabled:'O'},{tgname:'spy_mission',tgenabled:'O'}]);
console.log('SQL local : 500 missions visibles, 10 établissements, zéro trigger externe, état initial exact des triggers restauré.');
await assert.rejects(db.exec(sqlPreparation(m)),/IDs du run déjà présents/);await db.exec('ROLLBACK;');
await db.query('INSERT INTO public.candidatures VALUES ($1,$2)',['ffffffff-ffff-4fff-afff-ffffffffffff',m.missions[0].id]);
await assert.rejects(db.exec(sqlNettoyage(m)),/Dépendance métier/);await db.exec('ROLLBACK;');
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.missions')).rows[0].n,500);
await db.exec('DELETE FROM public.candidatures;');
await db.exec('CREATE TRIGGER nouveau_delete BEFORE DELETE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.proteger_audit();');
await assert.rejects(db.exec(sqlNettoyage(m)),/Trigger de suppression non prévu/);await db.exec('ROLLBACK;');
await db.exec('DROP TRIGGER nouveau_delete ON public.missions;');
await avecVerrouVerifie(sqlNettoyage(m));
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.missions')).rows[0].n,0);
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.etablissements')).rows[0].n,0);
console.log('SQL local : dépendance tierce refuse le cleanup ; après retrait, zéro mission/établissement restant.');
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.journaux_audit')).rows[0].n,1);
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.alertes_systeme')).rows[0].n,0);
await assert.rejects(db.exec(sqlPreparation(m)),/Run déjà nettoyé/);await db.exec('ROLLBACK;');
await db.exec(sqlNettoyage(m));
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.journaux_audit')).rows[0].n,1);
const tardif=creerManifeste({runId:'local-sql-retard-pre-db',count:100});
await avecVerrouVerifie(sqlNettoyage(tardif));
await assert.rejects(db.exec(sqlPreparation(tardif)),/Run déjà nettoyé/);await db.exec('ROLLBACK;');
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.missions')).rows[0].n,0);
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.journaux_audit')).rows[0].n,2);
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.alertes_systeme')).rows[0].n,0);
console.log('SQL local : verrou détenu jusqu’au commit puis libéré ; prepare→cleanup et cleanup→prepare tardif protégés par deux reçus immuables, zéro alerte.');
await db.exec('INSERT INTO cron.job VALUES (true);');
await assert.rejects(db.exec(sqlPreparation(m)),/cron staging est actif/);await db.exec('ROLLBACK;');
assert.equal((await db.query('SELECT count(*)::int AS n FROM public.missions')).rows[0].n,0);
console.log('SQL local : cron actif refuse la préparation avant toute insertion.');
await db.close();
