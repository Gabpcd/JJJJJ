"""Numérotation et baux : vraies transactions PostgreSQL 17, trois connexions.

Charge la migration entière, les vrais types/tables de pièces, les index actifs,
le trigger de période et l'émetteur. Les tables annexes sont minimales : aucune
preuve de RLS Supabase, de Storage, d'email ou du graphe métier complet.
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
if (os.environ.get('JOLENE_NUMBERING_WITNESS') != 'CI_EPHEMERE'
        or os.environ.get('PGHOST') != '127.0.0.1'
        or os.environ.get('PGDATABASE') != 'numerotation_temoin'):
    raise SystemExit('Refus : PostgreSQL éphémère loopback explicitement désigné requis')
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
CTX = "SET statement_timeout='12s'; SET lock_timeout='8s'; SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);"


def run(source):
    return subprocess.run(PSQL, input=source, text=True, capture_output=True, timeout=20)


def sql(source):
    r = run(source)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def value(source):
    return json.loads(sql(CTX+source).splitlines()[-1])


def refuse(source, code, message):
    r = run(CTX+source)
    assert r.returncode != 0 and code in r.stderr and message in r.stderr, r.stderr


def literal(value):
    return "'"+str(value).replace("'", "''")+"'"


def exact(pattern, source):
    matches = re.findall(pattern, source, re.S)
    assert len(matches) == 1, (pattern, len(matches))
    return matches[0]


assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace") == '0'
assert sql("SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace") == '0'
snapshot = (ROOT/'supabase/schema/public.sql').read_text()
migration = (ROOT/'supabase/migrations/20261001144604_reserver_numeros_honoraires_atomiquement.sql').read_text()
historique = (ROOT/'tests/fixtures/numerotation-historique.sql').read_text()
sql((ROOT/'tests/fixtures/numerotation-concurrence-pg17.sql').read_text())
for name in ['type_document_facture', 'statut_litige_facture', 'mode_remboursement_avoir']:
    sql(exact(r'CREATE TYPE "public"\."'+name+r'" AS ENUM \(.*?\n\);', snapshot))
for name in ['factures_honoraires', 'factures_honoraires_documents']:
    sql(exact(r'CREATE TABLE IF NOT EXISTS "public"\."'+name+r'" \(.*?\n\);', snapshot))
for name in ['factures_honoraires_pkey', 'factures_honoraires_numero_facture_key',
             'factures_honoraires_documents_pkey', 'factures_honoraires_documents_pdf_unique',
             'factures_honoraires_documents_xml_unique']:
    sql(exact(r'ALTER TABLE ONLY "public"\."[^"]+"\n    ADD CONSTRAINT "'+name+r'"[^;]+;', snapshot))
for name in ['uniq_fh_mission_finale_active', 'uniq_fh_mission_semaine_active']:
    sql(exact(r'CREATE UNIQUE INDEX "'+name+r'"[^;]+;', snapshot))
for name in ['fn_emettre_document_facturation_honoraires', 'fn_verrouiller_periode_facture_honoraires']:
    definition = exact(r'CREATE OR REPLACE FUNCTION "public"\."'+name+r'"\(.*?\nALTER FUNCTION "public"\."'+name+r'"[^;]+;', snapshot)
    sql(definition)
    print(json.dumps({'source': name, 'sha256': hashlib.sha256(definition.encode()).hexdigest()}), flush=True)
sql(exact(r'CREATE OR REPLACE TRIGGER "trg_verrouiller_periode_facture_honoraires"[^;]+;', snapshot))
sql(historique)
for signature in ['next_invoice_number(uuid)', 'next_avoir_number(uuid)']:
    sql(f'REVOKE ALL ON FUNCTION public.{signature} FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.{signature} TO service_role;')
sql('REVOKE ALL ON FUNCTION public.fn_emettre_document_facturation_honoraires(uuid,text,text) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.fn_emettre_document_facturation_honoraires(uuid,text,text) TO service_role;')

S = 'f1710000-0000-4000-8000-000000000001'
S2 = 'f1710000-0000-4000-8000-000000000002'
E = 'f1710000-0000-4000-8000-000000000003'
M = 'f1710000-0000-4000-8000-000000000004'
M2 = 'f1710000-0000-4000-8000-000000000005'


def seed(installed=True):
    lease = 'private.generations_factures_honoraires,' if installed else ''
    sql(f'TRUNCATE {lease}public.factures_honoraires_documents,public.invoice_audit_log,public.notifications,public.stripe_refunds_queue,public.factures_honoraires,public.missions,public.soignants;'
        f"INSERT INTO public.soignants VALUES('{S}',NULL),('{S2}',NULL);"
        f"INSERT INTO public.missions(id,soignant_assigne_id,etablissement_id,type_contrat_applique) VALUES('{M}','{S}','{E}','LIBERAL'),('{M2}','{S}','{E}','LIBERAL');")


def document(mission=M):
    return dict(mission_id=mission, soignant_id=S, etablissement_id=E,
                montant_ht=80, montant_tva=0, montant_ttc=80, taux_tva=0,
                exoneration_tva=True, date_emission='2026-10-01', date_echeance='2026-10-31',
                periode_debut='2026-09-21', periode_fin='2026-09-27',
                numero_semaine_iso=39, annee_iso=2026, est_facture_finale_mission=False,
                quantite_heures_snapshot=4, taux_horaire_snapshot=20,
                emetteur_identite_snapshot="Łukasz L'Été & İpek", mandat_version='fixture',
                template_version='v2_facturx', is_public_sector=False)


def reserve(d=None):
    return 'SELECT public.fn_reserver_facture_honoraires('+literal(json.dumps(d or document(), ensure_ascii=False))+'::jsonb);'


def direct(number, issuer=S, mission=M, kind='FACTURE', nature='ORIGINALE', parent='NULL', status='ERREUR_GENERATION'):
    return f"INSERT INTO public.factures_honoraires(numero_facture,soignant_id,etablissement_id,mission_id,montant_ht,montant_ttc,periode_debut,periode_fin,type_document,nature_correction,facture_precedente_id,statut) VALUES({literal(number)},'{issuer}','{E}','{mission}',80,80,'2026-09-21','2026-09-27','{kind}','{nature}',{parent},'{status}') RETURNING id;"


# Reproduction historique stricte : deux véritables générateurs, pas une copie.
seed(False)
for case, siret, siret2 in [('uuid_prefixe_identique', 'NULL', 'NULL'),
                            ('siret_prefixe_identique', "'99123456000010'", "'99123456000028'")]:
    sql(f"UPDATE public.soignants SET siret_liberal=CASE WHEN id='{S}' THEN {siret} ELSE {siret2} END")
    for function in ['next_invoice_number', 'next_avoir_number']:
        a = sql(f"SELECT public.{function}('{S}')")
        b = sql(f"SELECT public.{function}('{S2}')")
        assert a == b, (case, function, a, b)
        print(json.dumps({'historique': case, 'fonction': function, 'collision_exacte': True}), flush=True)
a = sql(f"SELECT public.next_invoice_number('{S}')")
b = sql(f"SELECT public.next_invoice_number('{S}')")
assert a == b
sql(direct(a))
refuse(direct(b, issuer=S2), '23505', 'factures_honoraires_numero_facture_key')
print('HISTORIQUE_DEUX_TRANSACTIONS_SANS_RESERVATION_ET_UNICITE_GLOBALE', flush=True)
before = sql('SELECT row_to_json(f) FROM public.factures_honoraires f')
# Préflight, corps, ACL, table privée et registre sont appliqués sans extraction.
sql(migration)
assert sql('SELECT row_to_json(f) FROM public.factures_honoraires f') == before
print(json.dumps({'migration_sha256': hashlib.sha256(migration.encode()).hexdigest(), 'historique_inchange': True}), flush=True)
for function in ['next_invoice_number', 'next_avoir_number']:
    a = sql(f"SELECT public.{function}('{S}')")
    b = sql(f"SELECT public.{function}('{S2}')")
    assert a != b and S.replace('-', '') in a and S2.replace('-', '') in b
sql(direct('JOL-ANCIEN-2020-99999'))
assert sql(f"SELECT public.next_invoice_number('{S}')").endswith('-100000')
print('SERIES_NON_AMBIGUES_CONTINUITE_SIX_CHIFFRES', flush=True)


def session(statement):
    p = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    p.stdin.write('BEGIN;'+CTX+"SELECT 'PID:'||pg_backend_pid();"+statement+"SELECT 'PRET';\n")
    p.stdin.flush()
    p.output_buffer = ''
    os.set_blocking(p.stdout.fileno(), False)
    return p


def line(p, prefix):
    deadline = time.monotonic()+12
    sel = selectors.DefaultSelector(); sel.register(p.stdout, selectors.EVENT_READ)
    try:
        while time.monotonic() < deadline:
            while '\n' in p.output_buffer:
                value, p.output_buffer = p.output_buffer.split('\n', 1)
                if value.strip().startswith(prefix):
                    return value.strip()
            if not sel.select(timeout=0.2):
                if p.poll() is not None:
                    raise AssertionError(p.stderr.read())
                continue
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk and p.poll() is not None:
                raise AssertionError(p.stderr.read())
            p.output_buffer += chunk.decode()
        raise AssertionError('Session sans marqueur attendu')
    finally:
        sel.close()


def race(name, first, second, check):
    a = b = None
    try:
        a = session(first); pid_a = int(line(a, 'PID:')[4:]); line(a, 'PRET')
        b = session(second); pid_b = int(line(b, 'PID:')[4:])
        deadline = time.monotonic()+5; blocked = False
        while time.monotonic() < deadline:
            blocked = sql(f"SELECT wait_event_type='Lock' AND {pid_a}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={pid_b}") == 't'
            if blocked:
                break
            if b.poll() is not None:
                raise AssertionError('Écrivain B terminé sans attendre A : '+b.stderr.read())
            time.sleep(0.05)
        assert blocked, 'Aucun verrou de A réellement attendu par B'
        a.stdin.write('COMMIT;\n'); a.stdin.close(); a.wait(timeout=12)
        assert a.returncode == 0, a.stderr.read()
        line(b, 'PRET'); b.stdin.write('COMMIT;\n'); b.stdin.close(); b.wait(timeout=12)
        assert b.returncode == 0, b.stderr.read()
        assert sql(check) == 't', name
        print(json.dumps({'cas': name, 'attente_pid_a_prouvee': True, 'invariants': True}), flush=True)
    finally:
        for p in [a, b]:
            if p is not None and p.poll() is None:
                p.kill(); p.wait(timeout=5)


seed()
race('meme_emetteur_missions_distinctes', reserve(), reserve(document(M2)),
     "SELECT count(*)=2 AND count(DISTINCT numero_facture)=2 AND min(split_part(numero_facture,'-',4)::int)=1 AND max(split_part(numero_facture,'-',4)::int)=2 FROM public.factures_honoraires")
seed()
race('meme_mission_une_reservation', reserve(), reserve(),
     "SELECT (SELECT count(*) FROM public.factures_honoraires)=1 AND (SELECT count(*) FROM private.generations_factures_honoraires)=1")
f = value(reserve())
assert f['cree'] is False
fid = f['facture_id']
before = sql(f"SELECT row_to_json(f) FROM public.factures_honoraires f WHERE id='{fid}'")
d = document(); d['montant_ht'] = 999; d['emetteur_identite_snapshot'] = 'Profil modifié'
assert value(reserve(d))['facture_id'] == fid
assert sql(f"SELECT row_to_json(f) FROM public.factures_honoraires f WHERE id='{fid}'") == before
d = document(); d['periode_fin'] = '2026-09-26'
refuse(reserve(d), '23514', 'FACTURE_RESERVATION_PERIODE_DIFFERENTE')
print('RESERVATION_CANONIQUE_SNAPSHOTS_ET_PERIODE', flush=True)


def docs(f):
    path = f"invoices/{S}/{f['numero_facture']}/"
    return dict(pdf_s3_key=path+'f1710000-0000-4000-8000-000000000010.pdf',
                facturx_xml_url=path+'f1710000-0000-4000-8000-000000000011.xml',
                pdf_sha256='a'*64, xml_sha256='b'*64)


def finish(f, token=None, documents=None):
    content = 'NULL' if documents is None else literal(json.dumps(documents))+'::jsonb'
    return f"SELECT public.fn_terminer_generation_honoraires('{f['facture_id']}','{token or f['token']}',{content});"


seed()
a = value(reserve()); a_id = a['facture_id']
value(finish(a))
assert sql(f"SELECT statut FROM public.factures_honoraires WHERE id='{a_id}'") == 'ERREUR_GENERATION'
assert value(reserve())['facture_id'] == a_id
b = value(f"SELECT public.fn_acquerir_generation_honoraires('{a_id}');")
assert b['acquise'] is True and b['token'] != a['token']
b.update(numero_facture=a['numero_facture'])
before = sql(f"SELECT row_to_json(b) FROM private.generations_factures_honoraires b WHERE facture_id='{a_id}'")
for document_arg in [None, docs(a)]:
    refuse(finish(a, documents=document_arg), '23514', 'FACTURE_GENERATION_TOKEN_PERIME')
assert sql(f"SELECT row_to_json(b) FROM private.generations_factures_honoraires b WHERE facture_id='{a_id}'") == before
sql(f"UPDATE private.generations_factures_honoraires SET expire_le=clock_timestamp()-interval '1 second' WHERE facture_id='{a_id}'")
for document_arg in [None, docs(b)]:
    refuse(finish(b, documents=document_arg), '23514', 'FACTURE_GENERATION_BAIL_EXPIRE')
race('reprise_expiree_une_seule_acquisition',
     f"SELECT public.fn_acquerir_generation_honoraires('{a_id}');",
     f"SELECT public.fn_acquerir_generation_honoraires('{a_id}');",
     f"SELECT (SELECT count(*) FROM public.factures_honoraires)=1 AND token<>'{b['token']}' AND expire_le>clock_timestamp() FROM private.generations_factures_honoraires WHERE facture_id='{a_id}'")
c = dict(facture_id=a_id, numero_facture=a['numero_facture'], token=sql(f"SELECT token FROM private.generations_factures_honoraires WHERE facture_id='{a_id}'"))
for document_arg in [None, docs(b)]:
    refuse(finish(b, documents=document_arg), '23514', 'FACTURE_GENERATION_TOKEN_PERIME')
wrong = docs(c); wrong['pdf_s3_key'] = wrong['pdf_s3_key'].replace(S, S2)
refuse(finish(c, documents=wrong), '23514', 'FACTURE_GENERATION_DOCUMENTS_INVALIDES')
assert sql('SELECT count(*) FROM public.factures_honoraires_documents') == '0'
race('finalisation_concurrente_meme_token', finish(c, documents=docs(c)), finish(c, documents=docs(c)),
     "SELECT (SELECT count(*) FROM public.factures_honoraires_documents)=1 AND (SELECT count(*) FROM public.notifications)=2 AND (SELECT count(*) FROM public.invoice_audit_log)=1")
result = value(finish(c, documents=docs(c)))
state = sql(f"SELECT row_to_json(f) FROM public.factures_honoraires f WHERE id='{a_id}'")
sql(f"UPDATE private.generations_factures_honoraires SET expire_le=clock_timestamp()-interval '1 second' WHERE facture_id='{a_id}'")
assert value(finish(c, documents=docs(c))) == result
assert value(finish(c)) == result
assert sql(f"SELECT row_to_json(f) FROM public.factures_honoraires f WHERE id='{a_id}'") == state
assert value(reserve())['facture_id'] == a_id
assert sql('SELECT count(*) FROM public.factures_honoraires_documents') == '1'
print('PANNE_REPRISE_TARDIVE_REPONSE_PERDUE_UNE_EMISSION', flush=True)

# Un ancien historique ambigu n'est jamais résolu par « dernière pièce ».
seed()
for n in ['JOL-ANCIEN-2026-00001', 'JOL-ANCIEN-2026-00002']:
    sql(direct(n))
sql("UPDATE public.factures_honoraires SET annee_iso=2026,numero_semaine_iso=39")
refuse(reserve(), '23514', 'FACTURE_RESERVATION_HISTORIQUE_AMBIGU')
assert sql('SELECT count(*) FROM private.generations_factures_honoraires') == '0'
print('HISTORIQUE_ERREUR_AMBIGU_REFUSE', flush=True)

# La première émission d'un avoir garde son parent exact et les notifications
# uniques. Pas de mode AUTO_STRIPE, pas de file fournisseur dans ce scénario.
seed()
parent = sql(direct('JOL-ANCIEN-2026-00001', status='EMISE'))
parent_before = sql(f"SELECT row_to_json(f) FROM public.factures_honoraires f WHERE id='{parent}'")
number = sql(f"SELECT public.next_avoir_number('{S}')")
credit_id = sql(direct(number, kind='AVOIR', nature='AVOIR', parent=literal(parent), status='BROUILLON'))
credit = value(f"SELECT public.fn_acquerir_generation_honoraires('{credit_id}');")
credit['numero_facture'] = number
credit_docs = {key: val.replace('invoices/', 'avoirs/') if isinstance(val, str) else val for key, val in docs(credit).items()}
credit_result = value(finish(credit, documents=credit_docs))
assert credit_result['success'] is True
assert value(finish(credit, documents=credit_docs)) == credit_result
assert sql(f"SELECT chorus_avoir_reference_invoice FROM public.factures_honoraires WHERE id='{credit_id}'") == 'JOL-ANCIEN-2026-00001'
assert sql(f"SELECT row_to_json(f) FROM public.factures_honoraires f WHERE id='{parent}'") == parent_before
assert sql('SELECT (SELECT count(*) FROM public.factures_honoraires_documents)=1 AND (SELECT count(*) FROM public.notifications)=2 AND (SELECT count(*) FROM public.stripe_refunds_queue)=0') == 't'
print('AVOIR_PARENT_EXACT_UNE_EMISSION_SANS_FOURNISSEUR', flush=True)

# Refus des deux frontières : aucune écriture publique à la table de baux,
# RPCs non exécutables par authenticated, service sans JWT service également refusé.
for signature in ['fn_reserver_facture_honoraires(jsonb)', 'fn_acquerir_generation_honoraires(uuid)', 'fn_terminer_generation_honoraires(uuid,uuid,jsonb)']:
    assert sql(f"SELECT NOT has_function_privilege('authenticated','public.{signature}','EXECUTE') AND has_function_privilege('service_role','public.{signature}','EXECUTE')") == 't'
refuse("SET ROLE authenticated;"+reserve(), '42501', 'permission denied')
refuse("SELECT set_config('request.jwt.claims','{\"role\":\"authenticated\"}',false);"+reserve(), '42501', 'Réservé au service de facturation')
refuse('SET ROLE service_role; SELECT * FROM private.generations_factures_honoraires;', '42501', 'permission denied')
print('ACL_ET_JWT_FERMES_PAS_DE_STORAGE_OU_FOURNISSEUR', flush=True)

# Les quatre anciens préparateurs réels tiennent une FH avant d'attendre la
# mission. Le même entrelacement s'exécute avant/après la seule migration d'ordre.
# Les fonctions Auth et annexes sont minimales ; aucun constat RLS n'en découle.
sql((ROOT/'tests/fixtures/numerotation-commissions-pg17.sql').read_text())
sql(exact(r'CREATE TABLE IF NOT EXISTS "public"\."factures" \(.*?\n\);', snapshot))
for name in ['factures_pkey', 'factures_numero_facture_key']:
    sql(exact(r'ALTER TABLE ONLY "public"\."factures"\n    ADD CONSTRAINT "'+name+r'"[^;]+;', snapshot))
for name in ['next_avoir_commission_number', 'fn_ecrire_audit_safe']:
    definition = exact(r'CREATE OR REPLACE FUNCTION "public"\."'+name+r'"\(.*?\nALTER FUNCTION "public"\."'+name+r'"[^;]+;', snapshot)
    sql(definition)
    print(json.dumps({'source': name, 'sha256': hashlib.sha256(definition.encode()).hexdigest()}), flush=True)
commission_history = (ROOT/'tests/fixtures/numerotation-commissions-historique.sql').read_text()
commission_migration = (ROOT/'supabase/migrations/20261001160404_ordonner_verrous_commissions_honoraires.sql').read_text()
sql(commission_history)
commission_cases = [
    ('periode', 'fn_preparer_facture_commission_periode', 'FACTURE', 'ORIGINALE', 80, 12, 2.4, 14.4),
    ('complement', 'fn_preparer_commission_complement_honoraires', 'FACTURE', 'COMPLEMENT', 20, 3, .6, 3.6),
    ('remplacement', 'fn_preparer_commission_remplacement_honoraires', 'FACTURE', 'REMPLACEMENT', 72, 10.8, 2.16, 12.96),
    ('avoir', 'fn_preparer_avoir_commission_honoraires', 'AVOIR', 'AVOIR', 20, 3, .6, 3.6),
]
for _, name, *_ in commission_cases:
    signature = name+'(uuid)'
    sql(f"REVOKE ALL ON FUNCTION public.{signature} FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.{signature} TO service_role;"
        f"INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5) SELECT '{signature}','SERVICE_ONLY_REVOQUE',md5(prosrc) FROM pg_proc WHERE oid='public.{signature}'::regprocedure;")
print(json.dumps({'commissions_anciennes_sha256': hashlib.sha256(commission_history.encode()).hexdigest()}), flush=True)


def commission_seed(case):
    label, function, kind, nature, amount, ht, tva, ttc = case
    sql('TRUNCATE public.factures,public.etablissements,public.journaux_audit;')
    seed()
    sql(f"INSERT INTO public.etablissements VALUES('{E}',false)")
    parent = None
    if nature != 'ORIGINALE':
        status = 'REMPLACEE' if nature == 'REMPLACEMENT' else 'PAYEE'
        parent = sql(direct('JOL-PARENT-2026-00001', status=status))
        sql(f"INSERT INTO public.factures(etablissement_id,mission_id,facture_honoraire_id,numero_facture,montant_ht,montant_tva,montant_ttc,statut,periode_debut,periode_fin) VALUES('{E}','{M}','{parent}','JOL-COMMISSION-PARENT',12,2.4,14.4,'EMISE','2026-09-21','2026-09-27')")
    parent_expr = literal(parent) if parent else 'NULL'
    target = sql(f"INSERT INTO public.factures_honoraires(numero_facture,soignant_id,etablissement_id,mission_id,montant_ht,montant_ttc,periode_debut,periode_fin,type_document,nature_correction,facture_precedente_id,litige_id,statut,est_facture_finale_mission) VALUES('JOL-CIBLE-2026-00001','{S}','{E}','{M}',{amount},{amount},'2026-09-21','2026-09-27','{kind}','{nature}',{parent_expr},gen_random_uuid(),'EMISE',false) RETURNING id")
    return target, f"SELECT public.{function}('{target}');"


def commission_interleaving(case, corrected):
    target, helper = commission_seed(case)
    a = b = None
    try:
        # A représente l'entrée mission du vrai acquéreur. B commence le vrai
        # préparateur, puis A poursuit ce même acquéreur jusqu'à sa FH.
        a = session(f"SELECT id FROM public.missions WHERE id='{M}' FOR UPDATE;")
        pid_a = int(line(a, 'PID:')[4:]); line(a, 'PRET')
        b = session(helper+'COMMIT;')
        pid_b = int(line(b, 'PID:')[4:])
        deadline = time.monotonic()+5
        while time.monotonic() < deadline:
            if sql(f"SELECT wait_event_type='Lock' AND {pid_a}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={pid_b}") == 't':
                break
            if b.poll() is not None:
                raise AssertionError('Préparateur terminé avant le verrou attendu : '+b.stderr.read())
            time.sleep(.05)
        else:
            raise AssertionError('Préparateur sans attente prouvée du PID A')
        a.stdin.write(f"SELECT public.fn_acquerir_generation_honoraires('{target}'); COMMIT;\n")
        a.stdin.close(); b.stdin.close()
        a.wait(timeout=12); b.wait(timeout=12)
        errors = [a.stderr.read(), b.stderr.read()]
        codes = [a.returncode, b.returncode]
        if not corrected:
            assert sum(code != 0 for code in codes) == 1, (codes, errors)
            error = errors[0] if codes[0] else errors[1]
            assert '40P01' in error and 'deadlock detected' in error, error
            assert '55P03' not in error and '57014' not in error, error
            print(json.dumps({'cas': case[0], 'avant': '40P01', 'attente_pid_a_prouvee': True}), flush=True)
        else:
            assert codes == [0, 0], errors
            _, _, kind, _, _, ht, tva, ttc = case
            assert sql(f"SELECT count(*)=1 AND bool_and(type_document='{kind}' AND montant_ht={ht} AND montant_tva={tva} AND montant_ttc={ttc}) FROM public.factures WHERE facture_honoraire_id='{target}'") == 't'
            before = sql('SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM public.factures f')
            assert value(helper)['existing'] is True
            assert sql('SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM public.factures f') == before
            assert sql('SELECT count(*) FROM public.stripe_refunds_queue') == '0'
            if case[0] == 'avoir':
                assert sql('SELECT count(*) FROM public.journaux_audit') == '1'
            print(json.dumps({'cas': case[0], 'apres': 'commission_exacte_et_rejeu', 'attente_pid_a_prouvee': True}), flush=True)
    finally:
        for p in [a, b]:
            if p is not None and p.poll() is None:
                p.kill(); p.wait(timeout=5)


for case in commission_cases:
    commission_interleaving(case, False)
before_migration = sql('SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM public.factures f')
sql(commission_migration)
assert sql('SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM public.factures f') == before_migration
print(json.dumps({'migration_ordre_sha256': hashlib.sha256(commission_migration.encode()).hexdigest(), 'pieces_inchangees': True}), flush=True)
for case in commission_cases:
    commission_interleaving(case, True)

# Le finaliseur touche réellement le trigger de période, qui prend l'advisory
# puis FOR SHARE sur l'origine d'un complément. A représente seulement le
# préfixe mission/origine du résolveur, pas son graphe métier intégral.
old_finalizer = (ROOT/'tests/fixtures/numerotation-finaliseur-historique.sql').read_text()
new_finalizer = exact(r'CREATE OR REPLACE FUNCTION public.fn_terminer_generation_honoraires\(.*?\$terminer\$;', migration)
for corrected in [False, True]:
    sql(new_finalizer if corrected else old_finalizer)
    target, _ = commission_seed(commission_cases[1])
    parent = sql(f"SELECT facture_precedente_id FROM public.factures_honoraires WHERE id='{target}'")
    parent_before = sql(f"SELECT to_jsonb(f) FROM public.factures_honoraires f WHERE id='{parent}'")
    sql(f"UPDATE public.factures_honoraires SET statut='BROUILLON' WHERE id='{target}'")
    lease = value(f"SELECT public.fn_acquerir_generation_honoraires('{target}');")
    lease['numero_facture'] = 'JOL-CIBLE-2026-00001'
    a = b = None
    try:
        a = session(f"SELECT id FROM public.missions WHERE id='{M}' FOR UPDATE; SELECT id FROM public.factures_honoraires WHERE id='{parent}' FOR UPDATE;")
        pid_a = int(line(a, 'PID:')[4:]); line(a, 'PRET')
        b = session(finish(lease, documents=docs(lease))+'COMMIT;')
        pid_b = int(line(b, 'PID:')[4:])
        deadline = time.monotonic()+5
        while time.monotonic() < deadline:
            if sql(f"SELECT wait_event_type='Lock' AND {pid_a}=ANY(pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={pid_b}") == 't':
                break
            if b.poll() is not None:
                raise AssertionError('Finaliseur terminé sans verrou attendu : '+b.stderr.read())
            time.sleep(.05)
        else:
            raise AssertionError('Finaliseur sans attente prouvée du PID A')
        a.stdin.write(f"UPDATE public.factures_honoraires SET statut=statut WHERE id='{parent}'; COMMIT;\n")
        a.stdin.close(); b.stdin.close()
        a.wait(timeout=12); b.wait(timeout=12)
        errors = [a.stderr.read(), b.stderr.read()]
        codes = [a.returncode, b.returncode]
        if corrected:
            assert codes == [0, 0], errors
            assert sql(f"SELECT to_jsonb(f) FROM public.factures_honoraires f WHERE id='{parent}'") == parent_before
            assert sql(f"SELECT statut='EMISE' AND (SELECT count(*) FROM public.factures_honoraires_documents)=1 AND (SELECT count(*) FROM public.notifications)=2 FROM public.factures_honoraires WHERE id='{target}'") == 't'
            assert value(finish(lease, documents=docs(lease)))['success'] is True
        else:
            assert sum(code != 0 for code in codes) == 1, (codes, errors)
            error = errors[0] if codes[0] else errors[1]
            assert '40P01' in error and 'deadlock detected' in error, error
            assert '55P03' not in error and '57014' not in error, error
        print(json.dumps({'cas': 'finaliseur_complement_origine_advisory', 'corrige': corrected, 'attente_pid_a_prouvee': True, 'resultat': 'emission_unique' if corrected else '40P01'}), flush=True)
    finally:
        for p in [a, b]:
            if p is not None and p.poll() is None:
                p.kill(); p.wait(timeout=5)
