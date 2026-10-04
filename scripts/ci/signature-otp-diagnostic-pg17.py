"""Diagnostic de la fonction OTP exacte, PG17 éphémère sans fournisseur.

Deux tables de preuve et quatre tables RBAC exactes du snapshot. Auth.users est
une annexe réduite ; auth.uid est la définition catalogue déjà versionnée.
Seuls les deux triggers de conservation du contrat sont montés. Ce banc ne
prouve ni SMS, ni Storage, ni le graphe complet RLS/notifications de Jolene.
Tout, rôles et schémas compris, est annulé dans la même transaction.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_DB = 'signature_otp_diagnostic'
BEFORE_BODY = 'cba647b62c44ad94a570037b73c2e350b9a8080a41ab7b2523731ccd1698cd29'


def guard(env):
    if (env.get('JOLENE_SIGNATURE_WITNESS') != 'CI_EPHEMERE'
            or env.get('PGHOST') != '127.0.0.1'
            or env.get('PGPORT') != '54329'
            or env.get('PGDATABASE') != EXPECTED_DB
            or env.get('PGUSER') != 'postgres'
            or any(env.get(k) for k in ('PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS'))):
        raise RuntimeError('SIGNATURE_WITNESS_DESTINATION_REFUSED')


def exact(pattern, source):
    matches = re.findall(pattern, source, re.S)
    if len(matches) != 1:
        raise RuntimeError('SIGNATURE_SOURCE_CARDINALITY')
    return matches[0]


def definition(snapshot, name):
    return exact(r'CREATE OR REPLACE FUNCTION "public"\."'+name+r'"\(.*?\nALTER FUNCTION "public"\."'+name+r'"[^;]+;', snapshot)


def build_sql(snapshot, before, auth):
    before_body = exact(r'AS \$function\$(.*?)\$function\$', before['definition'])
    source_body = exact(r'AS \$\$(.*?)\$\$;', definition(snapshot, 'fn_signer_contrat_otp'))
    assert before_body == source_body
    assert hashlib.sha256(before_body.encode()).hexdigest() == BEFORE_BODY
    assert before['acl'] == '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
    assert before['owner'] == 'postgres'
    sql = ['BEGIN;', "SET LOCAL statement_timeout='12s'; SET LOCAL lock_timeout='8s'; SET LOCAL TIME ZONE 'UTC';",
           'CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;',
           'CREATE SCHEMA auth; CREATE SCHEMA extensions;',
           'CREATE EXTENSION "uuid-ossp" WITH SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;',
           "CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_app_meta_data jsonb, deleted_at timestamptz, banned_until timestamptz, email_confirmed_at timestamptz);"]
    sql.extend(re.findall(r'CREATE TYPE "public"\."[^"]+" AS ENUM \(.*?\n\);', snapshot, re.S))
    tables = ['contrats_mission', 'signatures_contrats', 'soignants', 'etablissements', 'equipe_admin', 'membres_etablissement']
    for name in tables:
        sql.append(exact(r'CREATE TABLE IF NOT EXISTS "public"\."'+name+r'" \(.*?\n\);', snapshot))
        sql.append(exact(r'ALTER TABLE ONLY "public"\."'+name+r'"\n    ADD CONSTRAINT "[^"]+" PRIMARY KEY [^;]+;', snapshot))
    uid = [row for row in auth['routines'] if row['signature'] == 'auth.uid()']
    assert len(uid) == 1
    sql.append(uid[0]['definition']+';')
    for name in ['est_admin_valide', 'est_admin', 'fn_compte_auth_actif', 'fn_role_etablissement_courant',
                 'est_admin_etablissement', 'est_soignant', 'dec_proteger_signature_contrat', 'fn_protect_contrat_integrity']:
        sql.append(definition(snapshot, name))
    for name in ['dec_proteger_signature_contrat', 'trg_protect_contrat_integrity']:
        sql.append(exact(r'CREATE OR REPLACE TRIGGER "'+name+r'"[^;]+;', snapshot))
    sql.append(before['definition']+';')
    sql.append('ALTER FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) OWNER TO postgres; '
               'REVOKE ALL ON FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) FROM PUBLIC,anon; '
               'GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) TO authenticated,service_role;')
    sql.append(r"""
INSERT INTO auth.users(id,raw_app_meta_data,email_confirmed_at) VALUES
 ('f1040000-0000-4000-8000-000000000001','{"role":"SOIGNANT"}',now()),
 ('f1040000-0000-4000-8000-000000000002','{"role":"ADMIN_ETABLISSEMENT"}',now());
INSERT INTO public.soignants(id,prenom,nom,email,est_compte_test)
 VALUES('f1040000-0000-4000-8000-000000000001','Banc','Synthétique','witness@example.invalid',true);
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
 VALUES('f1040000-0000-4000-8000-000000000002','Banc synthétique','99104000000018','EHPAD','Fixture','Fixture','75001','witness@example.invalid',true);
CREATE FUNCTION pg_temp.seed_signature(who text) RETURNS void LANGUAGE plpgsql AS $seed$
DECLARE uid uuid;
BEGIN
 DELETE FROM public.signatures_contrats; DELETE FROM public.contrats_mission;
 uid := CASE who WHEN 'soignant' THEN 'f1040000-0000-4000-8000-000000000001'::uuid
                ELSE 'f1040000-0000-4000-8000-000000000002'::uuid END;
 INSERT INTO public.contrats_mission(id,mission_id,etablissement_id,soignant_id,type_contrat,numero_contrat,statut,
   contenu_html,hash_document,storage_path,contenu_html_rendu_le)
 VALUES('f1040000-0000-4000-8000-000000000003','f1040000-0000-4000-8000-000000000004',
   'f1040000-0000-4000-8000-000000000002','f1040000-0000-4000-8000-000000000001','REMPLACEMENT_LIBERAL','BANC-OTP',
   'EN_ATTENTE_SIGNATURES','<!doctype html><p>Contrat synthétique été €</p>',
   encode(extensions.digest(convert_to('<!doctype html><p>Contrat synthétique été €</p>','UTF8'),'sha256'),'hex'),
   'f1040000-0000-4000-8000-000000000003/original.html',now());
 INSERT INTO public.signatures_contrats(contrat_id,signataire_user_id,signataire_role,otp_envoye_a,otp_code_hash,statut_signature)
 VALUES('f1040000-0000-4000-8000-000000000003',uid,who,now(),
   encode(extensions.digest('123456|f1040000-0000-4000-8000-000000000003|'||uid::text,'sha256'),'hex'),'otp_envoye');
 PERFORM set_config('request.jwt.claim.sub',uid::text,true);
 PERFORM set_config('request.headers','{}',true);
END;
$seed$;
CREATE TEMP TABLE observations(case_name text PRIMARY KEY, observed jsonb);
DO $witness$
DECLARE r jsonb; h text; who text;
BEGIN
 IF has_function_privilege('anon','public.fn_signer_contrat_otp(uuid,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.fn_signer_contrat_otp(uuid,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'WITNESS_ACL'; END IF;
 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
   PERFORM pg_temp.seed_signature(who);
   SELECT hash_document INTO h FROM public.contrats_mission;
   r := public.fn_signer_contrat_otp('f1040000-0000-4000-8000-000000000003',NULL,h,NULL);
   IF (r->>'success')::boolean IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE statut_signature='signe')
   THEN RAISE EXCEPTION 'NULL_BYPASS_NOT_REPRODUCED'; END IF;
   INSERT INTO observations VALUES('null-otp-'||who,jsonb_build_object('returnedSuccess',true,'persistedSignature',true));
 END LOOP;
 PERFORM pg_temp.seed_signature('etablissement');
 r := public.fn_signer_contrat_otp('f1040000-0000-4000-8000-000000000003','123456',repeat('f',64),NULL);
 IF (r->>'success')::boolean IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE hash_document=repeat('f',64))
 THEN RAISE EXCEPTION 'FOREIGN_HASH_NOT_REPRODUCED'; END IF;
 INSERT INTO observations VALUES('arbitrary-document-hash',jsonb_build_object('returnedSuccess',true,'persistedForeignHash',true));
 PERFORM pg_temp.seed_signature('etablissement');
 r := public.fn_signer_contrat_otp('f1040000-0000-4000-8000-000000000003','123456',NULL,NULL);
 IF (r->>'success')::boolean IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE statut_signature='signe' AND hash_document IS NULL)
 THEN RAISE EXCEPTION 'NULL_HASH_NOT_REPRODUCED'; END IF;
 INSERT INTO observations VALUES('null-document-hash',jsonb_build_object('returnedSuccess',true,'persistedNullHash',true));
 PERFORM pg_temp.seed_signature('soignant');
 PERFORM set_config('jolene.signature_soignant_en_cours','',true);
 SELECT hash_document INTO h FROM public.contrats_mission;
 r := public.fn_signer_contrat_otp('f1040000-0000-4000-8000-000000000003','123456',h,NULL);
 INSERT INTO observations SELECT 'empty-signature-guc',jsonb_build_object('returnedSuccess',r->'success',
   'signatureSoignant',signature_soignant,'statut',statut) FROM public.contrats_mission;
END;
$witness$;
SELECT jsonb_build_object('schemaVersion',1,'phase','original-diagnostic','postgresMajor',17,
 'networkProvidersCalled',false,'cases',(SELECT jsonb_object_agg(case_name,observed) FROM observations));
ROLLBACK;
""")
    return '\n'.join(sql)


def main():
    guard(os.environ)
    env = {k: os.environ[k] for k in ('PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD') if k in os.environ}
    psql = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']
    def run(source):
        result = subprocess.run(psql, input=source, env=env, text=True, capture_output=True, timeout=60)
        if result.returncode:
            # Inputs are all synthetic, yet keep SQL/error text out of public logs.
            raise RuntimeError('SIGNATURE_PG17_SQL_FAILED')
        return result.stdout.strip()
    empty = "SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','extensions'))=0 AND (SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role'))=0"
    assert run("SELECT current_setting('server_version_num')::int/10000") == '17'
    assert run(empty) == 't'
    snapshot = (ROOT/'supabase/schema/public.sql').read_text()
    before = json.loads((ROOT/'tests/fixtures/signature-otp-catalogue-before.json').read_text())
    auth = json.loads((ROOT/'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text())
    report = json.loads(run(build_sql(snapshot, before, auth)).splitlines()[-1])
    assert run(empty) == 't'
    report.update({'rollbackVerified':True,'bodySha256':BEFORE_BODY,'scope':'local PG17 canonical OTP and two contract guards; not SMS/Storage/full RLS'})
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print(json.dumps({'schemaVersion':1,'completed':False,'error':'SIGNATURE_WITNESS_FAILED'}))
        raise SystemExit(1)
