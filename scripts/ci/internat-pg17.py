"""PG17 isolé : migration entière, routines LIVE, fixtures sans personne réelle.

Ne prouve ni une authentification ANS, ni l'IA, ni le fournisseur de stockage.
Les politiques périphériques non liées à l'internat ne sont pas recréées ; une
politique permissive témoin permet de tester la nouvelle politique restrictive.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
if (os.environ.get('JOLENE_INTERNAT_WITNESS') != 'LOCAL_EPHEMERE'
        or os.environ.get('PGHOST') != '127.0.0.1'
        or os.environ.get('PGPORT') != '54329'
        or os.environ.get('PGDATABASE') != 'internat_temoin'
        or os.environ.get('PGUSER') != 'postgres'
        or any(os.environ.get(k) for k in ['PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS'])):
    raise SystemExit('INTERNAT_WITNESS_DESTINATION_REFUSED')
ENV = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
CTX = "SET statement_timeout='12s'; SET lock_timeout='8s'; SET TIME ZONE 'UTC';"


def run(source):
    return subprocess.run(PSQL, input=CTX+source, env=ENV, text=True, capture_output=True, timeout=20)


def sql(source):
    result = run(source)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def value(source):
    return json.loads(sql(source).splitlines()[-1])


def refused(source, code):
    result = run(source)
    assert result.returncode != 0 and code in result.stderr, (code, result.stdout, result.stderr)


def literal(value):
    return "'"+str(value).replace("'", "''")+"'"


def exact(pattern, source):
    matches = re.findall(pattern, source, re.S)
    assert len(matches) == 1, (pattern, len(matches))
    return matches[0]


assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace") == '0'
assert sql("SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','private','extensions')") == '0'
assert sql("SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','supabase_auth_admin','dashboard_user')") == '0'
snapshot = (ROOT/'supabase/schema/public.sql').read_text()
migration = (ROOT/'supabase/migrations/20261029080849_internat_specialite_et_choix_etablissement.sql').read_text()
rows = {}
for filename in ['internat-live-full-closure-20261029.json', 'internat-live-admission-dependencies-20261029.json']:
    raw = (ROOT/'tests/fixtures'/filename).read_bytes()
    for row in json.loads(raw)['routines']:
        previous = rows.get(row['signature'])
        assert previous is None or previous['definition'] == row['definition'], row['signature']
        rows[row['signature']] = row
    print(json.dumps({'source': filename, 'sha256': hashlib.sha256(raw).hexdigest()}), flush=True)
definitions = '\n'.join(row['definition'] for row in rows.values())
sql("CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN BYPASSRLS;"
    "CREATE ROLE supabase_auth_admin NOLOGIN; CREATE ROLE dashboard_user NOLOGIN;"
    "CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA extensions;"
    "CREATE EXTENSION pgcrypto WITH SCHEMA extensions;"
    "CREATE FUNCTION extensions.uuid_generate_v4() RETURNS uuid LANGUAGE sql AS $$ SELECT gen_random_uuid() $$;"
    "CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;"
    "CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT auth.jwt()->>'role' $$;"
    "GRANT USAGE ON SCHEMA auth,public,private,extensions TO anon,authenticated,service_role,supabase_auth_admin,dashboard_user;")
for definition in re.findall(r'CREATE TYPE "public"\."[^"]+" AS ENUM \(.*?\n\);', snapshot, re.S):
    sql(definition)
tables = set(re.findall(r'(?:FROM|JOIN|UPDATE|INTO)\s+(?:public\.)?([a-z_][a-z_0-9]*)', definitions+migration, re.I))
tables |= {'equipe_admin','membres_etablissement','specialites_medicales','documents_requis_par_profession','equivalences_scolarite'}
tables = sorted(name for name in tables if re.search(r'CREATE TABLE IF NOT EXISTS "public"\."'+name+'"', snapshot))
for name in tables:
    definition = exact(r'CREATE TABLE IF NOT EXISTS "public"\."'+name+r'" \(.*?\n\);', snapshot)
    sql(definition)
    keys = re.findall(r'ALTER TABLE ONLY "public"\."'+name+r'"\n    ADD CONSTRAINT "[^"]+" PRIMARY KEY [^;]+;', snapshot)
    for key in keys:
        sql(key)
sql("CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text NOT NULL,definition_md5 text NOT NULL,justification text NOT NULL,recense_le timestamptz NOT NULL);"
    "CREATE TABLE auth.users(id uuid PRIMARY KEY,raw_app_meta_data jsonb,deleted_at timestamptz,banned_until timestamptz,email_confirmed_at timestamptz);")
auth = json.loads((ROOT/'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text())['routines']
uid = next(row for row in auth if row['signature']=='auth.uid()')
sql(uid['definition'])
for row in rows.values():
    signature = row['signature'] if '.' in row['signature'].split('(')[0] else 'public.'+row['signature']
    # Creation order only. Every exercised function is executed below on actual PG17.
    sql("SET check_function_bodies=false;"+row['definition']+';'+f"ALTER FUNCTION {signature} OWNER TO {row['owner']}; REVOKE ALL ON FUNCTION {signature} FROM PUBLIC;")
    for entry in (row['acl'] or '').strip('{}').split(','):
        if not entry:
            continue
        grantee, grantor = entry.split('=X/')
        assert grantor == row['owner']
        sql(f"SET ROLE {grantor}; GRANT EXECUTE ON FUNCTION {signature} TO {grantee or 'PUBLIC'};")
    if 'SECURITY DEFINER' in row['definition']:
        sql("INSERT INTO private.security_definer_inventory SELECT "+literal(row['signature'])+",'SERVICE_ONLY_REVOQUE',md5(prosrc),'Source LIVE du témoin',now() FROM pg_proc WHERE oid="+literal(signature)+"::regprocedure;")
# Observed profile/document, urgent score and mission counter lock paths.
# Other business triggers and the full production RLS graph remain outside this witness.
admission_dependencies = json.loads((ROOT/'tests/fixtures/internat-live-admission-dependencies-20261029.json').read_text())
for trigger in admission_dependencies['triggers']:
    sql('SET search_path=public,private;'+trigger['definition'])
for fk in admission_dependencies['fks']:
    sql(f"SET search_path=public; ALTER TABLE {fk['table']} ADD CONSTRAINT {fk['name']} {fk['definition']}")
sql("GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated,service_role;"
    "GRANT INSERT,UPDATE,DELETE ON public.candidatures,public.missions TO authenticated,service_role;")
# Detect out-of-band source drift before any new schema object is committed.
refused("BEGIN; ALTER FUNCTION public.fn_soignant_compatible_mission(public.type_profession,text,public.type_profession,text,boolean) RENAME TO changed_helper;"+migration+"ROLLBACK;", 'INTERNAT_DEPENDANCE_MODIFIEE')
assert sql("SELECT to_regclass('private.qualifications_medicales') IS NULL") == 't'
sql('BEGIN;'+migration+'COMMIT;')
print(json.dumps({'migration_sha256': hashlib.sha256(migration.encode()).hexdigest(), 'scope': 'PG17_LOCAL_SANS_FOURNISSEUR'}), flush=True)

S, S2, E, A, D, L, M, M2, M3, C = [f'10290000-0000-4000-8000-{n:012d}' for n in range(1,11)]


def context(actor=S, role='authenticated', app_role='SOIGNANT'):
    claims = json.dumps({'sub': actor, 'role': role, 'app_metadata': {'role': app_role}})
    return f"SET ROLE {role}; SELECT set_config('request.jwt.claims',{literal(claims)},false);"


admin = context(A, app_role='ADMIN_PLATEFORME')
etab = context(E, app_role='ADMIN_ETABLISSEMENT')
sql(f"""
INSERT INTO auth.users(id,raw_app_meta_data,email_confirmed_at) VALUES
('{S}','{{"role":"SOIGNANT"}}',now()),('{S2}','{{"role":"SOIGNANT"}}',now()),
('{E}','{{"role":"ADMIN_ETABLISSEMENT"}}',now()),('{A}','{{"role":"ADMIN_PLATEFORME"}}',now());
INSERT INTO public.equipe_admin(user_id,nom,prenom,email,acces_groupes) VALUES('{A}','Fixture','Admin','admin@example.invalid',
 ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
INSERT INTO public.soignants(id,nom,prenom,email,profession,est_etudiant,numero_rpps,rpps_verifie,specialite_medicale) VALUES
('{S}','Fixture','Interne','interne@example.invalid','MEDECIN',true,'10000000001',true,'SM02'),
('{S2}','Fixture','Medecin','medecin@example.invalid','MEDECIN',false,'10000000002',true,'SM02');
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
 peut_publier_missions,statut_verification,contrat_service_signe,siret_verifie,finess_verifie,representant_identite_verifiee,rattachement_verifie)
VALUES('{E}','Fixture sans activité','99102900000018','EHPAD','Fixture','Fixture','75001','etab@example.invalid',true,'VERIFIE',true,true,true,true,true);
INSERT INTO public.specialites_medicales(code,label,profession_parent,actif) VALUES
('SM01','Médecine générale','MEDECIN',true),('SM02','Cardiologie','MEDECIN',true),('SM03','Ancienne spécialité','MEDECIN',false);
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut,specialite_medicale_requise,accepte_non_specialises,type_contrat_recherche) VALUES
('{M}','{E}','Fixture compatible','MEDECIN',now()+interval '2 days',now()+interval '2 days 8 hours',50,'OUVERTE','SM01',false,'SALARIE'),
('{M2}','{E}','Fixture autre spécialité','MEDECIN',now()+interval '2 days',now()+interval '2 days 8 hours',50,'OUVERTE','SM02',false,'SALARIE'),
('{M3}','{E}','Fixture sans accord','MEDECIN',now()+interval '2 days',now()+interval '2 days 8 hours',50,'OUVERTE','SM01',false,'SALARIE');
INSERT INTO public.documents_soignants(id,soignant_id,type_document,nom_fichier,s3_bucket,s3_cle,type_mime,taille_octets,
 statut_verification,verifie_le,coherence_nom,valide_depuis,valide_jusqua,resultat_ia) VALUES
('{L}','{S}','LICENCE_REMPLACEMENT','licence-fictive.pdf','jolene-documents','fixture/licence-v1.pdf','application/pdf',100,
 'VERIFIE',now(),true,current_date-1,current_date+30,
 '{{"verdict_serveur":"VERIFIE","type_correspond":true,"document_lisible":true,"document_complet":true,"licence_remplacement_specialite":"Médecine générale","licence_remplacement_specialite_code":"SM01"}}'),
('{D}','{S}','CARTE_ORDRE','attestation-fictive.pdf','jolene-documents','fixture/ordre-v1.pdf','application/pdf',100,
 'VERIFIE',now(),true,current_date-1,NULL,'{{}}');
""")
assert value(f"SELECT private.fn_statut_internat_medical('{S}')")['specialite_code'] == 'SM01'
assert sql(f"SELECT private.fn_compatibilite_profil_mission('{S}','MEDECIN','SM02',true,true,now()+interval '1 day')") == 'f'
assert sql(f"SELECT private.fn_compatibilite_profil_mission('{S}','MEDECIN','SM01',true,false,now()+interval '1 day')") == 'f'
assert sql("SELECT private.fn_code_specialite_licence_exact('Ancienne spécialité') IS NULL") == 't'
refused(context()+f"UPDATE public.missions SET accepte_internes=true WHERE id='{M}';", '23514')


def accept_interns(mission, code):
    # Same private intent as public wrappers; the permission check is the LIVE tenant routine.
    return sql(etab+f"BEGIN; RESET ROLE; INSERT INTO private.mission_internat_intent VALUES(pg_backend_pid(),txid_current(),'{E}','{mission}',true,'{code}');"
        +f"SET ROLE authenticated; UPDATE public.missions SET accepte_internes=true WHERE id='{mission}';"
        +"RESET ROLE; DELETE FROM private.mission_internat_intent WHERE backend_pid=pg_backend_pid(); COMMIT;")


accept_interns(M, 'SM01')
accept_interns(M2, 'SM02')
# Public publication wrapper and unchanged publication engine, transaction rolled back.
creneaux = "jsonb_build_array(jsonb_build_object('debut',now()+interval '4 days','fin',now()+interval '4 days 8 hours'))"
published = value(etab+"BEGIN; SELECT public.fn_creer_mission_multi_jours_v4('Publication témoin','Aucun travail réel','MEDECIN','Médecine',50,false,1,'CANDIDATURE','SM01',false,"+creneaux+",'SALARIE','TAUX_HORAIRE',NULL,NULL,true);"
    +"SELECT jsonb_build_object('accord',accepte_internes,'acteur',accepte_internes_confirme_par,'specialite',specialite_medicale_requise) FROM public.missions WHERE intitule='Publication témoin'; ROLLBACK;")
assert published == {'accord': True, 'acteur': E, 'specialite': 'SM01'}
# A suspended actor keeps the existing access-denied contract before the
# intern-specific BEFORE triggers. The clinical profession does not change it.
for profession in ['IDE', 'MEDECIN']:
    for suspension in [f"UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='{S2}';",
                       f"UPDATE public.soignants SET supprime_le=now() WHERE id='{S2}';"]:
        setup = f"BEGIN; UPDATE public.soignants SET profession='{profession}' WHERE id='{S2}';"+suspension+context(S2)
        refused(setup+f"INSERT INTO public.candidatures(mission_id,soignant_id,statut) VALUES('{M}','{S2}','EN_ATTENTE');", '42501')
        refused(setup+f"UPDATE public.missions SET soignant_assigne_id='{S2}' WHERE id='{M}';", '42501')
assert sql(context(role='service_role')+f"SELECT public.fn_soignant_eligible_mission('{S}','{M}',false);").splitlines()[-1] == 't'
for mission in [M2,M3]:
    assert sql(context(role='service_role')+f"SELECT public.fn_soignant_eligible_mission('{S}','{mission}',false);").splitlines()[-1] == 'f'
    refused(context()+f"INSERT INTO public.candidatures(mission_id,soignant_id,statut) VALUES('{mission}','{S}','EN_ATTENTE');", '23514')
sql(context()+f"INSERT INTO public.candidatures(id,mission_id,soignant_id,statut) VALUES('{C}','{M}','{S}','EN_ATTENTE');")
sql(f"UPDATE public.soignants SET est_etudiant=false,internat_medical_identifie=false WHERE id='{S}';")
assert sql(f"SELECT internat_medical_identifie FROM public.soignants WHERE id='{S}'") == 't'
sql(f"UPDATE public.documents_soignants SET valide_jusqua=current_date WHERE id='{L}';")
assert value(f"SELECT private.fn_statut_internat_medical('{S}')")['statut'] == 'EXPIRE'
refused(context()+f"UPDATE public.missions SET soignant_assigne_id='{S}' WHERE id='{M}';", '23514')
sql(f"UPDATE public.documents_soignants SET valide_jusqua=current_date+30 WHERE id='{L}';")
boundary = value(f"SELECT private.fn_statut_internat_medical('{S}')")
assert sql(f"SELECT private.fn_internat_compatible({literal(json.dumps(boundary))}::jsonb,'MEDECIN','SM01',true,((current_date+30)::text||' 00:00 Europe/Paris')::timestamptz,false)") == 'f'
assert sql(f"SELECT private.fn_internat_compatible({literal(json.dumps(boundary))}::jsonb,'MEDECIN','SM01',true,((current_date+29)::text||' 23:59 Europe/Paris')::timestamptz,false)") == 't'

# Qualification distincte : rôle, preuve exacte, CAS, relecture, révocation.
for role in ['anon','authenticated','service_role']:
    assert sql(f"SELECT has_table_privilege('{role}','private.qualifications_medicales','SELECT,INSERT,UPDATE,DELETE')") == 'f'
refused(context()+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')", '42501')
review = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
assert review['documents'][0]['s3_cle']=='fixture/ordre-v1.pdf'
assert review['qualification'] is None


def approve(review, specialty='SM01'):
    return admin+f"SELECT public.fn_admin_decider_qualification_medicale('{S}','{D}',{literal(review['documents'][0]['empreinte'])},"+(
        literal(review['decision_id']) if review['decision_id'] else 'NULL')+f",'{specialty}','10000000001',true,true,'Attestation fictive et qualification contrôlées dans le banc local');"


sql(f"UPDATE public.documents_soignants SET s3_cle='fixture/ordre-v2.pdf' WHERE id='{D}';")
refused(approve(review), '40001')
review = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
assert review['documents'][0]['s3_cle']=='fixture/ordre-v2.pdf'
qualified = value(approve(review))
assert qualified['qualification']['specialite_code']=='SM01'
assert value(approve(review))['decision_id'] == qualified['decision_id']
assert sql('SELECT count(*) FROM private.qualifications_medicales') == '1'
assert value(f"SELECT private.fn_statut_internat_medical('{S}')")['qualification_confirmee'] is True
assert sql(context(role='service_role')+f"SELECT public.fn_soignant_eligible_mission('{S}','{M3}',false);").splitlines()[-1] == 't'
refused(context()+f"INSERT INTO public.candidatures(mission_id,soignant_id,statut) VALUES('{M2}','{S}','EN_ATTENTE');", '23514')
refused(f"UPDATE public.documents_soignants SET soignant_id='{S2}' WHERE id='{D}';", '23514')
sql(f"UPDATE public.documents_soignants SET s3_cle='fixture/ordre-v3.pdf' WHERE id='{D}';")
invalidated = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
assert invalidated['decision_invalidee'] and invalidated['qualification'] is None
refused(approve(qualified), '40001')
qualified = value(approve(invalidated))
decision = qualified['decision_id']
revocation = admin+f"SELECT public.fn_admin_revoquer_qualification_medicale('{S}','{decision}','Révocation fictive après contrôle documentaire');"
assert value(revocation)['decision_id'] is None
assert value(revocation)['decision_id'] is None
assert sql('SELECT count(*) FROM private.qualifications_medicales WHERE revoque_le IS NULL') == '0'

# Two real sessions, observed pg locks; no sleeps substituting for synchronization.
def session(statement):
    process = subprocess.Popen(PSQL, env=ENV, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    process.stdin.write('BEGIN;'+CTX+"SELECT 'PID:'||pg_backend_pid();"+statement+"SELECT 'PRET';\n")
    process.stdin.flush()
    process.buffer = ''
    os.set_blocking(process.stdout.fileno(), False)
    return process


def line(process, prefix):
    deadline = time.monotonic()+12
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        while time.monotonic() < deadline:
            while '\n' in process.buffer:
                item, process.buffer = process.buffer.split('\n', 1)
                if item.startswith(prefix):
                    return item
            if selector.select(timeout=.2):
                process.buffer += os.read(process.stdout.fileno(), 65536).decode()
            if process.poll() is not None:
                raise AssertionError(process.stderr.read())
        raise AssertionError('INTERNAT_SESSION_TIMEOUT')
    finally:
        selector.close()


def blocked_by(first, second):
    first_pid = int(line(first,'PID:')[4:])
    second_pid = int(line(second,'PID:')[4:])
    deadline = time.monotonic()+5
    while time.monotonic() < deadline:
        if sql(f"SELECT wait_event_type='Lock' AND {first_pid}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={second_pid}") == 't':
            return
        time.sleep(.05)
    raise AssertionError('INTERNAT_LOCK_NOT_OBSERVED')


def finish(process):
    process.stdin.write('COMMIT;\n')
    process.stdin.close()
    process.wait(timeout=12)
    assert process.returncode == 0, process.stderr.read()


def cleanup(*processes):
    for process in processes:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=5)


# Licence invalidated first: waiting admission must re-read the committed proof.
a = b = None
try:
    a = session(f"UPDATE public.documents_soignants SET valide_jusqua=current_date WHERE id='{L}';")
    # Retain PID while waiting until UPDATE has acquired the profile lock.
    pid_a = line(a, 'PID:'); line(a, 'PRET'); a.buffer = pid_a+'\n'+a.buffer
    b = session(context()+f"UPDATE public.candidatures SET statut='ACCEPTEE' WHERE id='{C}';")
    blocked_by(a,b); finish(a)
    b.stdin.close(); b.wait(timeout=12)
    assert b.returncode != 0 and '23514' in b.stderr.read()
    assert sql(f"SELECT statut FROM public.candidatures WHERE id='{C}'") == 'EN_ATTENTE'
finally:
    cleanup(a,b)
sql(f"UPDATE public.documents_soignants SET valide_jusqua=current_date+30 WHERE id='{L}';")
# Admission first: document mutation waits without a profile/document lock cycle.
a = b = None
try:
    a = session(context()+f"UPDATE public.candidatures SET statut='ACCEPTEE' WHERE id='{C}';")
    pid_a = line(a, 'PID:'); line(a, 'PRET'); a.buffer = pid_a+'\n'+a.buffer
    b = session(f"UPDATE public.documents_soignants SET valide_jusqua=current_date WHERE id='{L}';")
    blocked_by(a,b); finish(a); line(b,'PRET'); finish(b)
    assert value(f"SELECT private.fn_statut_internat_medical('{S}')")['statut'] == 'EXPIRE'
    assert sql(f"SELECT statut FROM public.candidatures WHERE id='{C}'") == 'ACCEPTEE'
finally:
    cleanup(a,b)
sql(f"UPDATE public.documents_soignants SET valide_jusqua=current_date+30 WHERE id='{L}';")
# Two differing administrative decisions on one snapshot: only the first wins.
review = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
a = b = None
try:
    a = session(approve(review))
    pid_a = line(a,'PID:'); line(a,'PRET'); a.buffer = pid_a+'\n'+a.buffer
    b = session(approve(review,'SM02'))
    blocked_by(a,b); finish(a)
    b.stdin.close(); b.wait(timeout=12)
    assert b.returncode != 0 and '40001' in b.stderr.read()
    assert sql('SELECT count(*) FROM private.qualifications_medicales WHERE revoque_le IS NULL') == '1'
finally:
    cleanup(a,b)
current = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
value(admin+f"SELECT public.fn_admin_revoquer_qualification_medicale('{S}','{current['decision_id']}','Fin de la décision fictive du banc de concurrence');")
print('INTERNAT_CONCURRENCE_LICENCE_ADMISSION_ET_DECISIONS_CAS_OK', flush=True)

# Actual urgent-admission RPC exercises the new guard and the LIVE urgent score trigger.
sql(f"UPDATE public.missions SET est_urgente=true,mode_attribution='CANDIDATURE' WHERE id='{M3}';")
review = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
qualified = value(approve(review))
urgent_rpc = context()+f"SELECT 'RESULT:'||public.fn_accepter_mission_urgence('{M3}')::text;"
result = sql('BEGIN;'+urgent_rpc+"ROLLBACK;")
assert json.loads(next(row[7:] for row in result.splitlines() if row.startswith('RESULT:')))['success'] is True
result = value('BEGIN;'+context()+f"SELECT public.fn_accepter_mission_urgence('{M3}');"
    +f"SELECT jsonb_build_object('candidatures',(SELECT count(*) FROM public.candidatures WHERE mission_id='{M3}'),"
    +f"'scores',(SELECT count(*) FROM public.scoring_breakdown WHERE soignant_id='{S}' AND raison_recalcul='engagement_urgence')); ROLLBACK;")
assert result['candidatures']==1 and result['scores']>0
attribution = value("BEGIN; INSERT INTO public.templates_contrat(type_contrat,nom,contenu_html) VALUES('CDD','Témoin local','<p>Contrat fictif sans signature</p>');"
    +context(role='service_role')+f"SELECT public.fn_finaliser_attribution_mission('{M3}','{S}','SALARIE');"
    +f"SELECT jsonb_build_object('statut',m.statut,'soignant',m.soignant_assigne_id,'contrat',c.statut,'type',c.type_contrat) FROM public.missions m JOIN public.contrats_mission c ON c.mission_id=m.id WHERE m.id='{M3}'; ROLLBACK;")
assert attribution == {'statut': 'ASSIGNEE', 'soignant': S, 'contrat': 'EN_ATTENTE_SIGNATURES', 'type': 'CDD'}

# Revocation wins: the waiting RPC must re-read before admitting on the qualification.
revoke_rpc = admin+f"SELECT public.fn_admin_revoquer_qualification_medicale('{S}','{qualified['decision_id']}','Révocation fictive concurrente à une admission urgente');"
a = b = None
try:
    a = session(revoke_rpc)
    pid_a = line(a,'PID:'); line(a,'PRET'); a.buffer = pid_a+'\n'+a.buffer
    b = session(urgent_rpc)
    blocked_by(a,b); finish(a)
    b.stdin.close(); b.wait(timeout=12)
    assert b.returncode != 0 and '23514' in b.stderr.read()
    assert sql(f"SELECT count(*) FROM public.candidatures WHERE mission_id='{M3}'") == '0'
finally:
    cleanup(a,b)

# Admission wins: revocation waits for the profile lock; no inverted score/FK lock.
review = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
qualified = value(approve(review))
revoke_rpc = admin+f"SELECT public.fn_admin_revoquer_qualification_medicale('{S}','{qualified['decision_id']}','Révocation fictive après admission urgente simultanée');"
a = b = None
try:
    a = session(urgent_rpc)
    pid_a = line(a,'PID:'); assert json.loads(line(a,'RESULT:')[7:])['success'] is True
    line(a,'PRET'); a.buffer = pid_a+'\n'+a.buffer
    b = session(revoke_rpc)
    blocked_by(a,b); finish(a); line(b,'PRET'); finish(b)
    assert sql(f"SELECT count(*) FROM public.candidatures WHERE mission_id='{M3}'") == '1'
    assert sql(context(role='service_role')+f"SELECT public.fn_soignant_eligible_mission('{S}','{M3}',false);").splitlines()[-1] == 'f'
finally:
    cleanup(a,b)
sql(f"DELETE FROM public.candidatures WHERE mission_id='{M3}';")
# The real profile identity trigger invalidates both proofs and any prior qualification.
review = value(admin+f"SELECT public.fn_admin_lire_qualification_medicale('{S}')")
qualified = value(approve(review))
identity_state = value(f"BEGIN; UPDATE public.soignants SET nom='Identité fictive modifiée' WHERE id='{S}';"
    +f"SELECT jsonb_build_object('qualification',private.fn_qualification_medicale_actuelle('{S}'),"
    +f"'statut',private.fn_statut_internat_medical('{S}')->>'statut'); ROLLBACK;")
assert identity_state == {'qualification': None, 'statut': 'A_VERIFIER'}
value(admin+f"SELECT public.fn_admin_revoquer_qualification_medicale('{S}','{qualified['decision_id']}','Fin des scénarios fictifs de qualification et identité');")
print('INTERNAT_RPC_URGENCE_SCORE_FK_QUALIFICATION_CONCURRENTE_ET_IDENTITE_OK', flush=True)

# Nouvelle politique restrictive réelle, avec permissive témoin explicite.
sql("ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY; CREATE POLICY temoin_missions ON public.missions FOR SELECT TO authenticated USING (true);")
assert value(context()+"SELECT coalesce(jsonb_agg(id),'[]') FROM public.missions;") == [M]
sql(f"UPDATE public.missions SET soignant_assigne_id='{S}' WHERE id='{M}';")
sql(f"UPDATE public.documents_soignants SET valide_jusqua=current_date WHERE id='{L}';")
sql(f"UPDATE public.missions SET intitule='Attribution conservée' WHERE id='{M}';")
assert sql(context()+f"SELECT intitule FROM public.missions WHERE id='{M}';").splitlines()[-1]=='Attribution conservée'
print('INTERNAT_SPECIALITE_CHOIX_PREUVE_QUALIFICATION_REVOCATION_ET_RLS_OK', flush=True)
