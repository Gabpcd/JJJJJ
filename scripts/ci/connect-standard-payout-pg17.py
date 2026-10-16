"""Ledger payout : vrais SQL/trigger/leases en PostgreSQL17 éphémère, zéro fournisseur.

Les profils non-TEST ci-dessous sont des lignes fictives dans cette base fraîche
locale uniquement, pour exercer la branche production SQL. Aucun acteur distant
n'est reclassé, aucun SDK fournisseur n'est chargé, aucun transport n'est simulé
comme une preuve de banque. Le RLS complet relève du test ACL de staging.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
if (os.environ.get('JOLENE_PG_CONCURRENCY') != 'CI_EPHEMERE'
    or os.environ.get('PGHOST') != '127.0.0.1'
    or os.environ.get('PGDATABASE') != 'connect_standard_payouts'):
    raise SystemExit('Refus : base PostgreSQL éphémère loopback connect_standard_payouts requise')
PSQL = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
CTX = "SET statement_timeout='10s'; SET lock_timeout='8s'; SET request.jwt.claims='{\"role\":\"service_role\"}';"

def sql(source):
    r = subprocess.run(PSQL, input=CTX + source, text=True, capture_output=True, timeout=20)
    if r.returncode:
        raise AssertionError(r.stderr)
    return r.stdout.strip()

assert sql("SELECT current_setting('server_version_num')::int/10000") == '17'
assert sql("SELECT count(*) FROM pg_tables WHERE schemaname='public'") == '0'
engine = (ROOT/'supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql').read_text()
migration = (ROOT/'supabase/migrations/20261016125516_securiser_beneficiaire_connect_et_versements_standard.sql').read_text()
fixture = """
CREATE SCHEMA auth; CREATE SCHEMA private;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT current_setting('request.jwt.claims')::jsonb $$;
DO $$BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END$$;
CREATE TABLE public.missions(id uuid PRIMARY KEY,soignant_assigne_id uuid,etablissement_id uuid,type_contrat_applique text,statut text);
CREATE TABLE public.soignants(id uuid PRIMARY KEY,est_compte_test boolean,supprime_le timestamptz,statut_compte text);
CREATE TABLE public.etablissements(id uuid PRIMARY KEY,est_compte_test boolean,supprime_le timestamptz,stripe_customer_id text);
CREATE TABLE public.factures_honoraires(id uuid PRIMARY KEY,mission_id uuid,soignant_id uuid,etablissement_id uuid,type_document text,statut text,montant_ttc numeric);
CREATE TABLE public.factures(id uuid PRIMARY KEY,mission_id uuid,etablissement_id uuid,facture_honoraire_id uuid,type_document text,statut text,montant_ttc numeric);
CREATE TABLE public.stripe_connect_onboarding(soignant_id uuid,stripe_account_id text,statut text);
CREATE TABLE public.stripe_transfers(id uuid PRIMARY KEY,mission_id uuid,soignant_id uuid,etablissement_id uuid,facture_id uuid,facture_honoraire_id uuid,
 montant_soignant numeric,montant_commission numeric,montant_total numeric,stripe_transfer_id text,stripe_payment_intent_id text,
 stripe_charge_id text,stripe_checkout_session_id text,stripe_payout_id text,statut text,erreur text,paye_le timestamptz,
 stripe_reversal_statut text DEFAULT 'AUCUN',stripe_amount_reversed_cents integer DEFAULT 0,dispute_statut text);
CREATE TABLE public.litiges(id uuid PRIMARY KEY,mission_id uuid,facture_id uuid,statut text);
CREATE TABLE public.paiements_soignant(mission_id uuid,facture_honoraire_id uuid,statut text);
CREATE TABLE public.paiements_escrow(id uuid,mission_id uuid,soignant_id uuid,statut text,stripe_payout_id text,honoraires_cents integer);
CREATE TABLE public.journaux_audit(acteur_id uuid,type_acteur text,action text,type_ressource text,id_ressource uuid,details jsonb,navigateur_acteur text);
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text,definition_md5 text,justification text);
"""
sql(fixture)
table = engine[engine.index('CREATE TABLE private.stripe_connect_avant_transfert'):engine.index('CREATE FUNCTION private.fn_connect_exiger_service')]
functions = []
for name in ['fn_connect_exiger_service', 'fn_connect_operation_verrouiller', 'fn_connect_protocole_ouvert', 'fn_connect_creation_autorisee']:
    match = re.search(r'CREATE FUNCTION private\.' + name + r'\([\s\S]*?\$f\$;', engine)
    assert match, name
    functions.append(match[0])
gate = re.search(r"CREATE TABLE private\.stripe_connect_release_gate \([\s\S]*?INSERT INTO private\.stripe_connect_release_gate\(protocol,enabled\) VALUES\('CONNECT_PRETRANSFER_V1',false\);", engine)[0]
sql(table + '\n' + gate + '\n' + '\n'.join(functions))
sql(migration)
print(json.dumps({'migration_sha256': hashlib.sha256(migration.encode()).hexdigest(),
    'canonical_engine_sha256': hashlib.sha256(('\n'.join(functions)).encode()).hexdigest(), 'postgres': 17}), flush=True)

def uid(n):
    return f'98400000-0000-4000-8000-{n:012d}'

M, S, E, H, F, T, O, OWNER, OTHER = [uid(n) for n in range(1, 10)]
sql(f"""
INSERT INTO public.soignants VALUES('{S}',false,NULL,'ACTIF');
INSERT INTO public.etablissements VALUES('{E}',false,NULL,'cus_fixture');
INSERT INTO public.stripe_connect_onboarding VALUES('{S}','acct_fixture','COMPLET');
INSERT INTO public.missions VALUES('{M}','{S}','{E}','LIBERAL','TERMINEE');
INSERT INTO public.factures_honoraires VALUES('{H}','{M}','{S}','{E}','FACTURE','EMISE',100);
INSERT INTO public.factures VALUES('{F}','{M}','{E}','{H}','FACTURE','EMISE',18);
INSERT INTO public.stripe_transfers(id,mission_id,soignant_id,etablissement_id,facture_id,facture_honoraire_id,
 montant_soignant,montant_commission,montant_total,stripe_transfer_id,stripe_payment_intent_id,stripe_charge_id,stripe_checkout_session_id,statut)
VALUES('{T}','{M}','{S}','{E}','{F}','{H}',100,18,118,'tr_fixture','pi_fixture','ch_fixture','cs_fixture','EN_ATTENTE');
INSERT INTO private.stripe_connect_avant_transfert(id,attempt_key,trace_id,session_id,mission_id,etablissement_id,soignant_id,
 facture_honoraire_id,facture_commission_id,customer_id,destination_id,soignant_cents,commission_cents,total_cents,payment_intent_id,charge_id,livemode,orientation)
VALUES('{O}','fixture','{T}','cs_fixture','{M}','{E}','{S}','{H}','{F}','cus_fixture','acct_fixture',10000,1800,11800,'pi_fixture','ch_fixture',true,'TRANSFER');
UPDATE public.stripe_transfers SET statut='TRANSFERE' WHERE id='{T}';
""")
assert sql(f"SELECT standard_payout_state='WAITING' AND standard_payout_account_id='acct_fixture' FROM public.stripe_transfers WHERE id='{T}'") == 't'
assert json.loads(sql("SELECT public.fn_connect_payouts_a_traiter(5)")) == [{'id': T}]
sql(f"UPDATE private.stripe_connect_avant_transfert SET livemode=false WHERE id='{O}'")
assert json.loads(sql("SELECT public.fn_connect_payouts_a_traiter(5)")) == []
sql(f"UPDATE private.stripe_connect_avant_transfert SET livemode=true WHERE id='{O}'; UPDATE public.soignants SET est_compte_test=true WHERE id='{S}'")
assert json.loads(sql("SELECT public.fn_connect_payouts_a_traiter(5)")) == []
sql(f"UPDATE public.soignants SET est_compte_test=false WHERE id='{S}'")

# Deux sessions : la seconde attend le verrou SQL puis constate le lease gagné.
p = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
p.stdin.write(CTX + f"BEGIN; SELECT public.fn_connect_payout_prendre('{T}','{OWNER}'); SELECT pg_sleep(1); COMMIT;")
p.stdin.close()
first = p.stdout.readline().strip()
assert json.loads(first)['id'] == T, first
assert sql(f"SELECT public.fn_connect_payout_prendre('{T}','{OTHER}')") == 'null'
assert p.wait(timeout=15) == 0, p.stderr.read()
assert sql(f"SELECT public.fn_connect_payout_demarrer('{T}','{OWNER}')") == 'f'
assert sql(f"SELECT standard_payout_first_post_at IS NULL FROM public.stripe_transfers WHERE id='{T}'") == 't'
sql("UPDATE private.stripe_connect_release_gate SET enabled=true WHERE protocol='CONNECT_PRETRANSFER_V1'")
assert sql(f"SELECT public.fn_connect_payout_demarrer('{T}','{OTHER}')") == 'f'
# Un escrow d'une AUTRE mission du même soignant ferme aussi le nouveau POST.
sql(f"INSERT INTO public.paiements_escrow(id,mission_id,soignant_id,statut) VALUES('{uid(30)}','{uid(31)}','{S}','DEBITE')")
assert sql(f"SELECT public.fn_connect_payout_demarrer('{T}','{OWNER}')") == 'f'
assert sql(f"SELECT standard_payout_first_post_at IS NULL FROM public.stripe_transfers WHERE id='{T}'") == 't'
sql(f"UPDATE public.paiements_escrow SET statut='PAYE' WHERE id='{uid(30)}'")
assert sql(f"SELECT public.fn_connect_payout_demarrer('{T}','{OWNER}')") == 't'
print('ADMISSION_CANONIQUE_LEASE_CONCURRENT_GATE_ET_CAS', flush=True)

def payout_object(status, attempt=0, payout_id='po_fixture'):
    obj = {'id': payout_id, 'status': status, 'amount': 10000, 'currency': 'eur', 'livemode': True, 'automatic': False,
        'metadata': {'type': 'CONNECT_STANDARD_PAYOUT', 'trace_id': T, 'transfer_id': 'tr_fixture',
            'mission_id': M, 'soignant_id': S, 'attempt': str(attempt)}}
    return obj

def observe(status, attempt=0, payout_id='po_fixture'):
    payload = json.dumps(payout_object(status, attempt, payout_id)).replace("'", "''")
    return json.loads(sql(f"SELECT public.fn_connect_payout_constater('{T}','acct_fixture','{payload}'::jsonb)"))

def known(payout_id):
    payload = json.dumps(payout_object('pending', 0, payout_id)).replace("'", "''")
    return sql(f"SELECT public.fn_connect_payout_est_connu('acct_fixture','{payload}'::jsonb)")

assert known('po_fixture') == 'f'
assert observe('pending')['recorded'] is True
assert known('po_fixture') == 't'
assert known('po_external') == 'f'
assert sql(f"SELECT standard_payout_state='SUBMITTED' AND statut='TRANSFERE' FROM public.stripe_transfers WHERE id='{T}'") == 't'
assert observe('paid')['recorded'] is True
assert observe('pending') == {'ignored': True}
assert observe('in_transit') == {'ignored': True}
assert observe('paid')['recorded'] is True
assert sql(f"SELECT standard_payout_state='PAID' AND statut='PAYE' FROM public.stripe_transfers WHERE id='{T}'") == 't'
assert sql("SELECT count(*) FROM public.journaux_audit WHERE action='FINANCE_PAYOUT_PAID'") == '1'
assert observe('failed') == {'review': True}
assert sql(f"SELECT standard_payout_state='REVIEW' AND statut='TRANSFERE' FROM public.stripe_transfers WHERE id='{T}'") == 't'
print('PAID_PUIS_PENDING_INTRANSIT_NE_REGRESSE_PAS_AUDIT_UNIQUE', flush=True)

# État initial d'un autre cas logique : setup local contrôlé, jamais une API.
sql(f"UPDATE public.stripe_transfers SET standard_payout_state='SUBMITTED',statut='TRANSFERE' WHERE id='{T}'")
assert observe('failed')['recorded'] is True
assert observe('pending') == {'ignored': True}
assert sql(f"SELECT public.fn_connect_payout_reessayer('{T}','{OTHER}','po_fixture')") == 'f'
assert sql(f"SELECT public.fn_connect_payout_reessayer('{T}','{OWNER}','po_fixture')") == 't'
assert sql(f"SELECT standard_payout_attempt=1 AND stripe_payout_id IS NULL AND standard_payout_previous_id='po_fixture' FROM public.stripe_transfers WHERE id='{T}'") == 't'
assert observe('failed') == {'ignored': True}
assert observe('pending', 1, 'po_retry')['recorded'] is True
assert sql(f"SELECT standard_payout_state='SUBMITTED' AND stripe_payout_id='po_retry' FROM public.stripe_transfers WHERE id='{T}'") == 't'
print('FAILED_PUIS_PENDING_IGNORE_RETRY_CAS_ET_ANCIEN_TERMINAL_IGNORE', flush=True)

# Absence de POST après expiration de la seule tentative ambiguë.
sql(f"UPDATE public.stripe_transfers SET standard_payout_state='WAITING',stripe_payout_id=NULL,standard_payout_first_post_at=now()-interval '21 hours' WHERE id='{T}'")
assert sql(f"SELECT public.fn_connect_payout_demarrer('{T}','{OWNER}')") == 'f'
assert sql(f"SELECT standard_payout_state FROM public.stripe_transfers WHERE id='{T}'") == 'REVIEW'
assert sql("SELECT count(*) FROM private.security_definer_inventory WHERE signature LIKE 'public.%'") == '0'
print('AMBIGUITE_EXPIREE_REFUSEE_INVENTAIRE_CANONIQUE', flush=True)
print('CONNECT_STANDARD_PAYOUT_LEDGER_PASS', flush=True)
