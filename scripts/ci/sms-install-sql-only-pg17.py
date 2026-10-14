"""CI PG17 witness for the SMS SQL-only resume, never a staging operator.

The canonical OTP/ledger sources and the complete pinned supplement are exact.
Additional observed tables are reduced synthetic annexes, not the full staging
catalogue. A distinct owner and SELECT-only ACL reproduce the cron.job refusal.
Only a fresh, loopback, GitHub-hosted CI PostgreSQL service is accepted.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ADMIN = 'sms_fixture_admin'
CRON_OWNER = 'sms_fixture_cron_owner'
ADMIN_PASSWORD = 'fixture-ci-ephemere'
DEMOTE_SQL = 'ALTER ROLE postgres NOSUPERUSER BYPASSRLS;'
RENDERED_SHA256 = 'e67b1284644ca2aab7f51006e4641ff921175810897813a12a0f922d45ff45cf'
CONTRACT = ROOT / 'scripts/ci/install-sms-staging-closed.contract.json'
CANONICAL_SPEC = importlib.util.spec_from_file_location(
    'sms_install_canonical', ROOT / 'scripts/ci/sms-signature-staging-pg17.py')
CANONICAL = importlib.util.module_from_spec(CANONICAL_SPEC)
CANONICAL_SPEC.loader.exec_module(CANONICAL)

EMPTY = """SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0
 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN
 ('auth','extensions','private','vault','net','cron','supabase_migrations'))=0
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN
 ('anon','authenticated','service_role','sms_fixture_cron_owner'))=0
 AND (SELECT oid=10 AND rolsuper FROM pg_roles WHERE rolname='sms_fixture_admin')"""
ROLE_STATE = """SELECT jsonb_build_object('superuser',rolsuper,'bypassrls',rolbypassrls,'bootstrap',oid=10)
 FROM pg_roles WHERE rolname='postgres'"""
PRIVILEGES = """SELECT jsonb_build_object(
 'samePostgresSession',current_user='postgres' AND session_user='postgres',
 'nonSuperuser',NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user),
 'nonBootstrapPostgres',(SELECT oid<>10 FROM pg_roles WHERE rolname=current_user),
 'bypassRls',(SELECT rolbypassrls FROM pg_roles WHERE rolname=current_user),
 'distinctCronOwner',(SELECT relowner='sms_fixture_cron_owner'::regrole
   AND relrowsecurity AND NOT relforcerowsecurity FROM pg_class WHERE oid='cron.job'::regclass),
 'notCronOwnerMember',NOT pg_has_role(current_user,'sms_fixture_cron_owner','MEMBER'),
 'cronSelectOnly',has_table_privilege(current_user,'cron.job','SELECT')
   AND NOT has_table_privilege(current_user,'cron.job','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'),
 'allCronRowsVisible',(SELECT count(*)=1 FROM cron.job),
 'networkExtensionAbsent',NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname IN('pg_net','http')))
"""
CLEANUP = """DROP SCHEMA IF EXISTS auth,extensions,private,vault,net,cron,supabase_migrations,public CASCADE;
 CREATE SCHEMA public;
 DROP ROLE IF EXISTS anon,authenticated,service_role,sms_fixture_cron_owner;
"""
NODE_BUILD = """import{readFileSync as read}from'node:fs';
 import{snapshotSql,transactionSql}from'./scripts/ci/install-sms-staging-closed-sql.mjs';
 import{transactionSqlOnly}from'./scripts/ci/resume-sms-staging-sql-only-sql.mjs';
 const input=JSON.parse(read(0,'utf8'));
 if(input.mode==='snapshot')process.stdout.write(snapshotSql(input.contract,false));
 else if(input.mode==='historical')process.stdout.write(transactionSql(input.contract,input.rendered,input.before,false));
 else if(input.mode==='resume')process.stdout.write(transactionSqlOnly(input.contract,input.rendered,input.before,false));
 else throw Error('SMS_SQL_ONLY_WITNESS_BUILD_MODE');
"""


class WitnessFailure(Exception):
    def __init__(self, code, sqlstate=None, denied_cron_job=False):
        self.code, self.sqlstate, self.denied_cron_job = code, sqlstate, denied_cron_job


def guard(env):
    expected = {'CI': 'true', 'GITHUB_ACTIONS': 'true',
        'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_REPOSITORY': 'Gabpcd/JJJJJ',
        'JOLENE_SMS_INSTALL_SQL_ONLY_WITNESS': 'CI_EPHEMERE', 'PGHOST': '127.0.0.1',
        'PGPORT': '54329', 'PGDATABASE': 'sms_install_sql_only_diagnostic',
        'PGUSER': 'postgres', 'PGPASSWORD': 'fixture-ci-ephemere'}
    if (any(env.get(key) != value for key, value in expected.items())
            or any(env.get(key) for key in ('PGSERVICE', 'PGSERVICEFILE', 'PGHOSTADDR', 'PGOPTIONS'))):
        raise WitnessFailure('SMS_SQL_ONLY_CI_DESTINATION_REFUSED')


def render():
    result = subprocess.run(['node', '--input-type=module', '-e',
        "import{readFileSync as r}from'node:fs';import{renderSignatureSmsStaging as f}from'./scripts/ci/sms-signature-staging-render.mjs';process.stdout.write(f(r('scripts/ci/sms-signature-staging-otp.source.sql','utf8'),r('scripts/ci/sms-signature-staging.sql','utf8')));"],
        cwd=ROOT, text=True, capture_output=True, timeout=15, check=True)
    if hashlib.sha256(result.stdout.encode()).hexdigest() != RENDERED_SHA256:
        raise WitnessFailure('SMS_SQL_ONLY_RENDER_PIN_REFUSED')
    return result.stdout


def build_fixture():
    # Reuse the canonical fixture without installing its closed supplement yet.
    # No function body or assertion in the actual constructors is changed.
    canonical, _, canonical_hash = CANONICAL.build_fixture()
    rendered = render()
    suffix = rendered + '\nCOMMIT;\n'
    if canonical_hash != RENDERED_SHA256 or not canonical.endswith(suffix):
        raise WitnessFailure('SMS_SQL_ONLY_FIXTURE_BOUNDARY_REFUSED')
    setup = canonical[:-len(suffix)]
    # These annexes are deliberately reduced: only the constructor's observed
    # columns and rows are required. They do not claim exact staging structure.
    for table in ['mission_creneaux', 'candidatures', 'factures_honoraires', 'factures',
            'litiges', 'paiements_soignant', 'paiements_mission', 'paiements_escrow',
            'stripe_transfers', 'stripe_payment_flow_claims', 'stripe_webhook_events',
            'stripe_refunds_queue', 'escrow_release_queue', 'externalisation_actions',
            'invoice_audit_log', 'notifications', 'email_queue', 'sms_envoyes', 'journaux_audit']:
        setup += f'CREATE TABLE public.{table}(id uuid PRIMARY KEY,statut text);\n'
    setup += f"""
CREATE TABLE auth.sessions(id uuid PRIMARY KEY);
CREATE TABLE auth.refresh_tokens(id bigint PRIMARY KEY);
CREATE TABLE private.stripe_connect_release_gate(id uuid PRIMARY KEY,enabled boolean NOT NULL DEFAULT false);
CREATE TABLE private.stripe_connect_test_capacities(id uuid PRIMARY KEY,enabled boolean NOT NULL DEFAULT false);
CREATE SCHEMA supabase_migrations;
CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);
INSERT INTO supabase_migrations.schema_migrations VALUES('synthetic-ci-only','fixture',ARRAY['no real migration']);
CREATE SCHEMA cron;
CREATE ROLE {CRON_OWNER} NOLOGIN;
CREATE TABLE cron.job(jobid bigint PRIMARY KEY,active boolean NOT NULL,command text NOT NULL);
INSERT INTO cron.job VALUES(1,false,'synthetic CI row, never scheduled');
ALTER TABLE cron.job OWNER TO {CRON_OWNER};
ALTER TABLE cron.job ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON cron.job FROM PUBLIC,postgres;
GRANT SELECT ON cron.job TO postgres;
CREATE TABLE cron.job_run_details(runid bigint PRIMARY KEY,status text,end_time timestamptz);
CREATE TABLE net.http_request_queue(id bigint PRIMARY KEY);
COMMIT;
"""
    contract = json.loads(CONTRACT.read_text())
    if contract['renderedSha256'] != RENDERED_SHA256:
        raise WitnessFailure('SMS_SQL_ONLY_CONTRACT_RENDER_PIN_REFUSED')
    return setup, rendered, contract


def build_sql(mode, contract, rendered=None, before=None):
    if mode not in ('snapshot', 'historical', 'resume'):
        raise WitnessFailure('SMS_SQL_ONLY_WITNESS_BUILD_MODE')
    result = subprocess.run(['node', '--input-type=module', '-e', NODE_BUILD],
        input=json.dumps({'mode': mode, 'contract': contract, 'rendered': rendered, 'before': before}),
        cwd=ROOT, text=True, capture_output=True, timeout=15)
    if result.returncode:
        raise WitnessFailure('SMS_SQL_ONLY_CONSTRUCTOR_REFUSED')
    if not result.stdout.rstrip().endswith('ROLLBACK;') or re.search(r'^\s*COMMIT\s*;', result.stdout, re.M):
        raise WitnessFailure('SMS_SQL_ONLY_ROLLBACK_REQUIRED')
    return result.stdout


def psql(env, source, timeout=100):
    result = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-v', 'VERBOSITY=verbose'], input=source, env=env, text=True,
        capture_output=True, timeout=timeout)
    if result.returncode:
        # Never publish SQL, rows, error context, commands or raw stderr.
        match = re.search(r'ERROR:\s+([A-Z0-9]{5}):', result.stderr)
        denied_cron = bool(re.search(r'ERROR:\s+42501:\s+permission denied for table job(?:\n|$)', result.stderr))
        raise WitnessFailure('SMS_SQL_ONLY_PG17_SQL_REFUSED', match.group(1) if match else None, denied_cron)
    return result.stdout.strip()


def snapshot(text):
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) != 1:
        raise WitnessFailure('SMS_SQL_ONLY_SNAPSHOT_CARDINALITY')
    value = json.loads(lines[0])
    if not isinstance(value, dict) or set(value) != {'quiet', 'absent', 'closed', 'routines', 'invariant', 'targets'}:
        raise WitnessFailure('SMS_SQL_ONLY_SNAPSHOT_SHAPE')
    return value


def check_snapshot(value, contract, after=False, before=None):
    expected = contract['afterRoutines' if after else 'beforeRoutines']
    if (value['quiet'] is not True or value['absent'] is not (not after)
            or value['closed'] is not after or len(value['routines']) != len(expected)):
        raise WitnessFailure('SMS_SQL_ONLY_SNAPSHOT_STATE')
    actual = {row['signature']: row for row in value['routines']}
    if len(actual) != len(expected):
        raise WitnessFailure('SMS_SQL_ONLY_ROUTINE_DUPLICATE')
    for row in expected:
        found = actual.get(row['signature'])
        if found is not None and 'definition_md5' not in row:
            found = {key: item for key, item in found.items() if key != 'definition_md5'}
        if found != row:
            raise WitnessFailure('SMS_SQL_ONLY_ROUTINE_PIN_REFUSED')
    if before is not None and value['invariant'] != before['invariant']:
        raise WitnessFailure('SMS_SQL_ONLY_INVARIANT_CHANGED')


def demote_from_admin(env):
    # The service bootstrap is a different OID10 role. Never try to demote the
    # bootstrap superuser, and establish the reduced login in a fresh session.
    return psql({**env, 'PGUSER': ADMIN, 'PGPASSWORD': ADMIN_PASSWORD}, DEMOTE_SQL, timeout=15)


def clean(env, initial_role):
    admin_env = {**env, 'PGUSER': ADMIN, 'PGPASSWORD': ADMIN_PASSWORD}
    restore = 'ALTER ROLE postgres SUPERUSER ' + ('BYPASSRLS' if initial_role['bypassrls'] else 'NOBYPASSRLS') + ';'
    try:
        psql(admin_env, restore, timeout=15)
    except Exception:
        # Do not broaden the destination or retry DDL if the admin session fails.
        if json.loads(psql(env, ROLE_STATE, timeout=15)) != initial_role:
            return False
    psql(env, CLEANUP, timeout=30)
    return psql(env, EMPTY, timeout=15) == 't' and json.loads(psql(env, ROLE_STATE, timeout=15)) == initial_role


def main():
    # All destination and CI guards run before git, Node, psql or any process.
    guard(os.environ)
    source_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if os.environ.get('GITHUB_SHA') != source_sha or not re.fullmatch('[a-f0-9]{40}', source_sha):
        raise WitnessFailure('SMS_SQL_ONLY_SOURCE_PIN_REFUSED')
    if subprocess.check_output(['git', 'diff', 'HEAD', '--', 'scripts/ci', 'tests/fixtures', 'tests/python', 'supabase'], cwd=ROOT, text=True).strip():
        raise WitnessFailure('SMS_SQL_ONLY_SOURCE_DIRTY')
    env = {key: os.environ[key] for key in ('PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD') if key in os.environ}
    report = {'schemaVersion': 1, 'completed': False, 'sourceSha': source_sha,
        'mode': 'PG17_EPHEMERAL_SMS_SQL_ONLY_RESUME', 'providerCalls': 0,
        'stagingAccessed': False, 'realTestBackend': False, 'frontendVerified': False,
        'physicalDevicesVerified': False, 'renderedSupplementSha256': RENDERED_SHA256,
        'scope': 'Exact canonical OTP/ledger routines and pinned complete supplement; reduced observed table annexes. Not the full staging catalogue, pg_cron scheduler, provider or frontend.',
        'routineMetadataAdaptations': [], 'cronJobLockMode': 'ACCESS SHARE',
        'cronJobDmlSerialized': False, 'cases': {}}
    mounted, initial_role = False, None
    stage = 'prepare'
    try:
        setup, rendered, contract = build_fixture()
        stage = 'verify-empty-pg17'
        if psql(env, "SELECT current_setting('server_version_num')::int/10000") != '17':
            raise WitnessFailure('SMS_SQL_ONLY_PG17_REQUIRED')
        if psql(env, EMPTY) != 't':
            raise WitnessFailure('SMS_SQL_ONLY_DATABASE_NOT_EMPTY')
        initial_role = json.loads(psql(env, ROLE_STATE))
        if initial_role['superuser'] is not True or initial_role['bootstrap'] is not False:
            raise WitnessFailure('SMS_SQL_ONLY_BOOTSTRAP_SUPERUSER_REQUIRED')
        stage = 'mount-canonical-and-reduced-annexes'
        mounted = True
        psql(env, setup)
        stage = 'demote-non-bootstrap-postgres-from-admin'
        demote_from_admin(env)
        stage = 'prove-managed-style-privileges'
        privileges = json.loads(psql(env, 'BEGIN READ ONLY; SET LOCAL row_security=off; ' + PRIVILEGES + '; ROLLBACK;'))
        if len(privileges) != 9 or any(value is not True for value in privileges.values()):
            raise WitnessFailure('SMS_SQL_ONLY_PRIVILEGES_REFUSED')
        report['cases']['non-superuser-postgres-bypassrls-select-only-distinct-cron-owner'] = True
        stage = 'read-exact-before-routine-pins'
        before_sql = build_sql('snapshot', contract)
        before = snapshot(psql(env, before_sql))
        check_snapshot(before, contract)
        report['cases']['five-original-routine-metadata-pins-exact'] = True
        stage = 'reproduce-historical-share-refusal'
        try:
            psql(env, build_sql('historical', contract, rendered, before))
        except WitnessFailure as error:
            if error.sqlstate != '42501' or not error.denied_cron_job:
                raise
        else:
            raise WitnessFailure('SMS_SQL_ONLY_HISTORICAL_SHARE_ACCEPTED')
        if snapshot(psql(env, before_sql)) != before:
            raise WitnessFailure('SMS_SQL_ONLY_HISTORICAL_FAILURE_MUTATED')
        report['cases']['historical-share-refuses-42501-before-ddl'] = True
        stage = 'execute-complete-resume-dry-run'
        after = snapshot(psql(env, build_sql('resume', contract, rendered, before)))
        check_snapshot(after, contract, after=True, before=before)
        report['cases']['complete-constructor-exact-render-empty-closed-capability'] = True
        stage = 'read-initial-state-after-rollback'
        if snapshot(psql(env, before_sql)) != before:
            raise WitnessFailure('SMS_SQL_ONLY_ROLLBACK_READBACK_CHANGED')
        if json.loads(psql(env, 'BEGIN READ ONLY; SET LOCAL row_security=off; ' + PRIVILEGES + '; ROLLBACK;')) != privileges:
            raise WitnessFailure('SMS_SQL_ONLY_PRIVILEGES_CHANGED')
        if psql(env, 'SELECT count(*)=0 FROM net.fixture_requests') != 't':
            raise WitnessFailure('SMS_SQL_ONLY_HTTP_DOUBLE_INVOKED')
        report['cases']['exact-initial-snapshot-and-privileges-restored-after-rollback'] = True
        report['cases']['no-synthetic-http-request'] = True
        stage = 'cleanup'
        report['cleanupVerified'] = clean(env, initial_role)
        if not report['cleanupVerified']:
            raise WitnessFailure('SMS_SQL_ONLY_CLEANUP_FAILED')
        mounted = False
        report['completed'] = True
    except Exception as error:
        report['failureStage'] = stage
        report['error'] = error.code if isinstance(error, WitnessFailure) else 'SMS_SQL_ONLY_WITNESS_FAILED'
        if isinstance(error, WitnessFailure) and error.sqlstate:
            report['sqlstate'] = error.sqlstate
    finally:
        if mounted and initial_role is not None:
            try:
                report['failureCleanupVerified'] = clean(env, initial_role)
            except Exception:
                report['failureCleanupVerified'] = False
    report['casesPassed'] = sum(value is True for value in report['cases'].values())
    print(json.dumps(report))
    return 0 if report['completed'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        print(json.dumps({'schemaVersion': 1, 'completed': False,
            'error': 'SMS_SQL_ONLY_PREFLIGHT_REFUSED', 'providerCalls': 0}))
        raise SystemExit(1)
