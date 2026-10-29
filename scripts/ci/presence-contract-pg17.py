"""Isolated PG17 witness, LIVE authorization helpers and synthetic records only.

This verifies the new read-only predicate and contract RLS; it is not a STAGING
scan, payment, physical-device or native-interface validation.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
if (os.environ.get('JOLENE_PRESENCE_WITNESS') != 'LOCAL_EPHEMERE'
        or os.environ.get('PGHOST') != '127.0.0.1'
        or os.environ.get('PGPORT') != '54329'
        or os.environ.get('PGDATABASE') != 'presence_temoin'
        or os.environ.get('PGUSER') != 'postgres'
        or any(os.environ.get(k) for k in ['PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS'])):
    raise SystemExit('PRESENCE_WITNESS_DESTINATION_REFUSED')
ENV = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}
CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']

def run(source):
    return subprocess.run(CMD, input="SET statement_timeout='8s'; SET lock_timeout='3s';"+source,
                          env=ENV, text=True, capture_output=True, timeout=15)

def sql(source):
    result = run(source)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()

def refused(source, code):
    result = run(source)
    assert result.returncode != 0 and code in result.stderr, (result.stdout, result.stderr)

def as_user(user, query, role='authenticated'):
    claims = json.dumps({'sub': user, 'role': role} if user else {'role': role})
    return f"SET ROLE {role}; SET request.jwt.claim.sub='{user}'; SET request.jwt.claims='{claims}';"+query

assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace") == '0'
sql("""
DO $roles$ BEGIN
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;
CREATE SCHEMA auth; CREATE SCHEMA private;
CREATE TABLE auth.users(id uuid PRIMARY KEY,raw_app_meta_data jsonb,deleted_at timestamptz,banned_until timestamptz,email_confirmed_at timestamptz);
CREATE TABLE public.soignants(id uuid PRIMARY KEY,supprime_le timestamptz);
CREATE TABLE public.etablissements(id uuid PRIMARY KEY,supprime_le timestamptz);
CREATE TABLE public.equipe_admin(user_id uuid,actif boolean,acces_groupes text[]);
CREATE TABLE public.membres_etablissement(user_id uuid,etablissement_id uuid,role text,actif boolean);
CREATE TABLE public.missions(id uuid PRIMARY KEY,etablissement_id uuid,soignant_assigne_id uuid);
CREATE TABLE public.contrats_mission(id uuid PRIMARY KEY,mission_id uuid,etablissement_id uuid,soignant_id uuid,statut text);
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text,definition_md5 text,justification text,recense_le timestamptz);
GRANT USAGE ON SCHEMA auth,public TO authenticated,anon,service_role;
""")
fixture = (ROOT/'tests/fixtures/presence-contract-live-20261029.json').read_bytes()
rows = {row['signature']: row for row in json.loads(fixture)['routines']}
for signature in ['auth.uid()', 'fn_compte_auth_actif()', 'fn_role_etablissement_courant(uuid)',
                  'est_admin_valide()', 'est_admin()', 'fn_a_permission_etablissement(text,uuid)', 'mon_etablissement_id()']:
    sql(rows[signature]['definition'])
sql("""
ALTER TABLE public.contrats_mission ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.contrats_mission TO authenticated;
CREATE POLICY pol_contrat_select ON public.contrats_mission FOR SELECT TO authenticated USING (
  (SELECT public.est_admin()) OR soignant_id=(SELECT auth.uid()) OR
  (etablissement_id=(SELECT public.mon_etablissement_id()) AND public.fn_a_permission_etablissement('lecture_contrats',etablissement_id))
);
CREATE POLICY pol_compte_auth_actif_restrictive ON public.contrats_mission AS RESTRICTIVE TO authenticated
USING ((SELECT public.fn_compte_auth_actif())) WITH CHECK ((SELECT public.fn_compte_auth_actif()));
""")
migration = (ROOT/'supabase/migrations/20261030000100_lecture_signature_pour_pointage.sql').read_text()
sql(migration)

user = '10000000-0000-4000-8000-000000000001'
other = '10000000-0000-4000-8000-000000000002'
member = '10000000-0000-4000-8000-000000000003'
outsider = '10000000-0000-4000-8000-000000000004'
etab = '20000000-0000-4000-8000-000000000001'
other_etab = '20000000-0000-4000-8000-000000000002'
mission = '30000000-0000-4000-8000-000000000001'
contract = '40000000-0000-4000-8000-000000000001'
for uid, role in [(user, 'SOIGNANT'), (other, 'SOIGNANT'), (member, 'ETABLISSEMENT'), (outsider, 'ETABLISSEMENT')]:
    sql(f"INSERT INTO auth.users VALUES('{uid}',jsonb_build_object('role','{role}'),NULL,NULL,now());")
sql(f"""
INSERT INTO public.soignants(id) VALUES('{user}'),('{other}');
INSERT INTO public.etablissements(id) VALUES('{etab}'),('{other_etab}');
INSERT INTO public.membres_etablissement VALUES('{member}','{etab}','POINTAGE_ONLY',true),('{outsider}','{other_etab}','RH',true);
INSERT INTO public.missions VALUES('{mission}','{etab}','{user}');
INSERT INTO public.contrats_mission VALUES('{contract}','{mission}','{etab}','{user}','SIGNE_COMPLET');
""")
read = f"SELECT public.fn_contrat_signe_pour_pointage('{mission}');"
for uid in [user, member]:
    assert sql(as_user(uid, read)) == 't'
assert sql(as_user(member, "SELECT count(*) FROM public.contrats_mission")) == '0'
assert sql(as_user(member, f"SELECT public.fn_a_permission_etablissement('lecture_contrats','{etab}')")) == 'f'
assert sql(as_user(user, "SELECT count(*) FROM public.contrats_mission")) == '1'
for uid in ['', other, outsider]:
    refused(as_user(uid, read), '42501')
for role in ['anon', 'service_role']:
    refused(as_user(member, read, role), '42501')
refused(as_user(member, "SELECT public.fn_contrat_signe_pour_pointage(NULL)"), '42501')

for status in ['BROUILLON', 'EN_ATTENTE_SIGNATURE', 'SIGNE_ETAB', 'SIGNE_SOIGNANT', 'ANNULE', 'EXPIRE', 'RUPTURE_ETAB', 'RUPTURE_SOIGNANT']:
    sql(f"UPDATE public.contrats_mission SET statut='{status}'")
    assert sql(as_user(member, read)) == 'f', status
sql("UPDATE public.contrats_mission SET statut='SIGNE_COMPLET'")
for column, wrong, original in [('soignant_id', other, user), ('etablissement_id', other_etab, etab), ('mission_id', other, mission)]:
    sql(f"UPDATE public.contrats_mission SET {column}='{wrong}'")
    assert sql(as_user(member, read)) == 'f', column
    sql(f"UPDATE public.contrats_mission SET {column}='{original}'")

for role in ['LECTURE_SEULE', 'INCONNU']:
    sql(f"UPDATE public.membres_etablissement SET role='{role}' WHERE user_id='{member}'")
    refused(as_user(member, read), '42501')
for role in ['PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY']:
    sql(f"UPDATE public.membres_etablissement SET role='{role}' WHERE user_id='{member}'")
    assert sql(as_user(member, read)) == 't'
sql(f"UPDATE public.membres_etablissement SET actif=false WHERE user_id='{member}'")
refused(as_user(member, read), '42501')
sql(f"UPDATE public.membres_etablissement SET actif=true WHERE user_id='{member}'")
for uid in [user, member]:
    for column, value in [('banned_until', "now()+interval '1 day'"), ('deleted_at', 'now()')]:
        sql(f"UPDATE auth.users SET {column}={value} WHERE id='{uid}'")
        refused(as_user(uid, read), '42501')
        sql(f"UPDATE auth.users SET {column}=NULL WHERE id='{uid}'")
sql(f"UPDATE public.etablissements SET supprime_le=now() WHERE id='{etab}'")
refused(as_user(member, read), '42501')
sql(f"UPDATE public.etablissements SET supprime_le=NULL WHERE id='{etab}'")
sql(f"UPDATE public.missions SET soignant_assigne_id='{other}'")
refused(as_user(user, read), '42501')
assert sql(as_user(other, read)) == 'f'
assert sql(as_user(member, read)) == 'f'
sql(f"UPDATE public.missions SET soignant_assigne_id='{user}'")

assert sql("SELECT provolatile='s' AND prosecdef AND proconfig=ARRAY['search_path=\"\"'] FROM pg_proc WHERE oid='public.fn_contrat_signe_pour_pointage(uuid)'::regprocedure") == 't'
before = sql("SELECT md5(jsonb_agg(to_jsonb(c) ORDER BY id)::text) FROM public.contrats_mission c")
assert sql(as_user(member, read)) == 't'
refused(as_user(member, "UPDATE public.contrats_mission SET statut='ANNULE'"), '42501')
after = sql("SELECT md5(jsonb_agg(to_jsonb(c) ORDER BY id)::text) FROM public.contrats_mission c")
assert before == after
refused(migration, 'PRESENCE_CONTRACT_READER_ALREADY_EXISTS')
assert sql(as_user(member, read)) == 't'
print(json.dumps({'migration_sha256': hashlib.sha256(migration.encode()).hexdigest(), 'fixture_sha256': hashlib.sha256(fixture).hexdigest()}))
print('POINTAGE_ONLY_SIGNATURE_SANS_LECTURE_CONTRAT_SCOPE_REVOCATION_ET_RLS_OK')
