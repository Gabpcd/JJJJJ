"""PG17 CI-only qualification of the closed SMS supplement; no provider/socket.

Reuses the canonical OTP fixture, imports the real ledger and exact rendered
supplement, then tests SQL behaviour and locks. It never connects to Supabase.
The only net.http_post implementation is a synthetic local table writer.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
CID = 'f1040000-0000-4000-8000-000000000003'
MID = 'f1040000-0000-4000-8000-000000000004'
SID = 'f1040000-0000-4000-8000-000000000001'
EID = 'f1040000-0000-4000-8000-000000000002'
EMPTY = """SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0
 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','extensions','private','vault','net'))=0
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role'))=0"""
CLEANUP = 'DROP SCHEMA IF EXISTS auth,extensions,private,vault,net,public CASCADE; CREATE SCHEMA public; DROP ROLE IF EXISTS anon,authenticated,service_role;'


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


FIXED = module('sms_canonical_otp', 'scripts/ci/signature-otp-fix-pg17.py')
RACE = module('sms_canonical_sessions', 'scripts/ci/recette107-signature-race.py')
SQL_ERROR_CODES = set()


class Session(RACE.Session):
    def __init__(self, env, directory, name):
        super().__init__(env, directory, name)
        # SQLSTATE only, never SQL/error context, is safe to retain when a
        # syntax/catalogue error prevents any reviewed RAISE from running.
        self.process.stdin.write('\\set VERBOSITY verbose\n')
        self.process.stdin.flush()

    def wait(self, marker, timeout=20):
        try:
            return super().wait(marker, timeout)
        except RuntimeError:
            # Never publish stderr/SQL context, even though this DB is synthetic.
            # Preserve only RAISE constants declared in the reviewed source.
            error = Path(self.err.name).read_text(errors='replace')[-12000:]
            found = re.search(r'ERROR:\s+(?:[A-Z0-9]{5}:\s+)?([A-Z][A-Z0-9_]+)(?:\n|$)', error)
            if found and found.group(1) in SQL_ERROR_CODES:
                raise RuntimeError(found.group(1)) from None
            state = re.search(r'ERROR:\s+([A-Z0-9]{5}):', error)
            if state:
                raise RuntimeError('SMS_SQLSTATE_' + state.group(1)) from None
            raise


def build_fixture():
    snapshot = (ROOT / 'supabase/schema/public.sql').read_text()
    whole = FIXED.build_sql(snapshot,
        json.loads((ROOT / 'tests/fixtures/signature-otp-catalogue-before.json').read_text()),
        json.loads((ROOT / 'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text()),
        (ROOT / 'supabase/migrations' / FIXED.MIGRATION).read_text())
    setup, _ = whole.split('CREATE TEMP TABLE observations', 1)
    assert setup.startswith('BEGIN;'), 'FIXTURE_BOUNDARY_CHANGED'
    for table in ['missions', 'preferences_notifications']:
        setup += FIXED.diagnostic.exact(r'CREATE TABLE IF NOT EXISTS "public"\."' + table + r'" \(.*?\n\);', snapshot) + '\n'
        setup += FIXED.diagnostic.exact(r'ALTER TABLE ONLY "public"\."' + table + r'"\n    ADD CONSTRAINT "[^"]+" PRIMARY KEY [^;]+;', snapshot) + '\n'
    # The July ledger's bodies match the supplement's independently pinned LIVE
    # md5 values; the supplement preflight still enforces those exact bodies.
    security = (ROOT / 'supabase/migrations/20260729121442_securiser_auth_et_crons_critiques.sql').read_text()
    setup += FIXED.diagnostic.exact(
        r'(CREATE TABLE IF NOT EXISTS private\.sms_dispatch_idempotency \(.*?)(?=CREATE OR REPLACE FUNCTION public\.fn_reserver_envoi_sms_idempotent)', security)
    for routine in ['fn_reserver_envoi_sms_idempotent', 'fn_finaliser_envoi_sms_idempotent']:
        setup += FIXED.diagnostic.definition(snapshot, routine) + '\n'
        signature = routine + ('(text,text)' if routine.startswith('fn_reserver') else '(text,text,text,text,text)')
        setup += f'REVOKE ALL ON FUNCTION public.{signature} FROM PUBLIC,anon,authenticated; GRANT EXECUTE ON FUNCTION public.{signature} TO service_role;\n'
    setup += "GRANT USAGE ON SCHEMA private TO service_role;\n"
    source = (ROOT / 'scripts/ci/sms-signature-staging-otp.source.sql').read_text()
    setup += source + ';\nALTER FUNCTION public.fn_envoyer_otp_signature(uuid) OWNER TO postgres;\n'
    setup += "REVOKE ALL ON FUNCTION public.fn_envoyer_otp_signature(uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_signature(uuid) TO authenticated,service_role;\n"
    setup += "INSERT INTO vault.decrypted_secrets VALUES('supabase_url','https://mejpriaetwgtcstbgfid.supabase.co'),('service_role_key','synthetic-ci-only-not-a-token');\n"
    rendered = subprocess.run(['node', '--input-type=module', '-e',
        "import{readFileSync as r}from'node:fs';import{renderSignatureSmsStaging as f}from'./scripts/ci/sms-signature-staging-render.mjs';process.stdout.write(f(r('scripts/ci/sms-signature-staging-otp.source.sql','utf8'),r('scripts/ci/sms-signature-staging.sql','utf8')));"],
        cwd=ROOT, text=True, capture_output=True, timeout=15, check=True).stdout
    assert rendered.count('CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_signature') == 1, 'SENDER_CARDINALITY'
    setup += rendered + '\nCOMMIT;\n'
    fixture = (ROOT / 'tests/fixtures/sms-signature-staging-pg17.sql').read_text()
    SQL_ERROR_CODES.update(re.findall(r"RAISE EXCEPTION '([A-Z][A-Z0-9_]+)'", setup + fixture))
    return setup, fixture, hashlib.sha256(rendered.encode()).hexdigest()


def current_request(observer):
    result = json.loads(observer.run(f"""SELECT jsonb_build_object('otpHash',otp_code_hash,
      'key','otp-signature.'||contrat_id::text||'.'||signataire_user_id::text||'.soignant.'||extract(epoch FROM sms_premier_envoi_a)::bigint::text||'.'||sms_envoyes_count::text)
      FROM public.signatures_contrats WHERE contrat_id='{CID}' AND signataire_role='soignant'"""))
    assert re.fullmatch('[a-f0-9]{64}', result['otpHash']), 'SYNTHETIC_OTP_HASH_INVALID'
    assert re.fullmatch(r'otp-signature\.' + re.escape(CID) + r'\.' + re.escape(SID) + r'\.soignant\.[0-9]+\.[1-3]', result['key']), 'SYNTHETIC_KEY_INVALID'
    return result


def reserve_call(request, fingerprint='d' * 64):
    # All values are synthetic constants. No OTP, phone, key, source rows or
    # function body from these sessions is copied to the public receipt.
    return f"""public.fn_reserver_sms_signature_recette(
      'sms-signature-pg17-synthetic','{ 'a' * 40 }','{ 'b' * 64 }','{CID}','{MID}','{SID}',
      '+33600000001','{request['otpHash']}','{request['key']}',
      '{fingerprint}','AC{ 'a' * 32 }','+33100000000')"""


def service_claims():
    return "BEGIN; SET LOCAL statement_timeout='25s'; SET LOCAL lock_timeout='20s'; SET LOCAL ROLE service_role; SELECT set_config('request.jwt.claim.role','service_role',true);"


def blocked_on(observer, waiting_pid, holder_pid):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        found = observer.run(f"SELECT {holder_pid}=ANY(pg_blocking_pids({waiting_pid})) AND EXISTS(SELECT 1 FROM pg_locks WHERE pid={waiting_pid} AND NOT granted)")
        if found == 't':
            return
        time.sleep(0.05)
    raise AssertionError('CONTRACT_LOCK_NOT_OBSERVED')


def concurrency(observer, env, directory, report):
    for conflict in [False, True]:
        observer.run("SELECT pg_temp.seed_sms('soignant'); UPDATE private.signature_sms_test_capacities SET soignant_attempts=1;")
        # The deliberately reduced fixture service role has no BYPASSRLS.
        # Materialise synthetic Edge arguments as owner before switching role;
        # never widen table grants just to make the concurrency witness pass.
        request = current_request(observer)
        holder = Session(env, directory, 'holder-' + str(conflict))
        waiter = Session(env, directory, 'waiter-' + str(conflict))
        try:
            holder.run(f"BEGIN; SET LOCAL statement_timeout='25s'; SELECT id FROM public.contrats_mission WHERE id='{CID}' FOR UPDATE;")
            holder_pid = int(holder.run('SELECT pg_backend_pid()'))
            holder.run("SET LOCAL ROLE service_role; SELECT set_config('request.jwt.claim.role','service_role',true);")
            assert json.loads(holder.run('SELECT ' + reserve_call(request)))['statut'] == 'RESERVE', 'LAST_SLOT_NOT_RESERVED'
            waiter.run(service_claims())
            waiting_pid = int(waiter.run('SELECT pg_backend_pid()'))
            marker = waiter.issue('SELECT ' + reserve_call(request, 'e' * 64 if conflict else 'd' * 64))
            blocked_on(observer, waiting_pid, holder_pid)
            holder.run('COMMIT')
            second = json.loads(waiter.wait(marker))
            waiter.run('COMMIT')
            assert second['statut'] == ('CONFLIT' if conflict else 'EN_COURS'), 'DUPLICATE_LOCK_RESULT'
            assert observer.run("SELECT soignant_attempts=2 AND etablissement_attempts=0 FROM private.signature_sms_test_capacities") == 't', 'CONCURRENT_BUDGET_OVERFLOW'
            assert observer.run('SELECT count(*)=1 FROM private.sms_dispatch_idempotency') == 't', 'CONCURRENT_LEDGER_DUPLICATE'
            report['cases']['last-slot-contract-lock-' + ('conflict' if conflict else 'same-request')] = True
        finally:
            waiter.close()
            holder.close()

    observer.run("SELECT pg_temp.seed_sms('soignant'); BEGIN;")
    request = current_request(observer)
    observer.run(f"SELECT id FROM public.contrats_mission WHERE id='{CID}' FOR UPDATE")
    holder_pid = int(observer.run('SELECT pg_backend_pid()'))
    waiter = Session(env, directory, 'revoked-waiter')
    try:
        waiter.run(service_claims())
        waiting_pid = int(waiter.run('SELECT pg_backend_pid()'))
        marker = waiter.issue(f"""DO $refuse$ BEGIN
          BEGIN PERFORM {reserve_call(request)}; RAISE EXCEPTION 'REVOKED_CLAIM_ALLOWED';
          EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'SIGNATURE_SMS_TEST_SCOPE_REFUSED' THEN RAISE; END IF; END;
        END; $refuse$; SELECT 'REVOKED_REFUSED';""")
        # Inspect locks from another session: observer itself holds the contract.
        inspector = Session(env, directory, 'revoke-inspector')
        try:
            blocked_on(inspector, waiting_pid, holder_pid)
        finally:
            inspector.close()
        observer.run("UPDATE private.signature_sms_test_capacities SET enabled=false,revoked_at=clock_timestamp(); COMMIT;")
        assert waiter.wait(marker) == 'REVOKED_REFUSED', 'REVOKED_CLAIM_RESULT'
        waiter.run('COMMIT')
        assert observer.run('SELECT count(*)=0 FROM private.sms_dispatch_idempotency') == 't', 'REVOKED_LEDGER_MUTATED'
        assert observer.run('SELECT soignant_attempts=0 AND etablissement_attempts=0 FROM private.signature_sms_test_capacities') == 't', 'REVOKED_BUDGET_MUTATED'
        report['cases']['revocation-rechecked-after-contract-lock'] = True
    finally:
        waiter.close()


def main():
    FIXED.diagnostic.guard(os.environ)
    assert os.environ.get('CI') == 'true', 'CI_REQUIRED'
    assert os.environ.get('JOLENE_SMS_STAGING_WITNESS') == 'CI_EPHEMERE', 'SMS_WITNESS_REQUIRED'
    actual_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert os.environ.get('GITHUB_SHA') == actual_sha, 'SOURCE_PIN_MISMATCH'
    assert not subprocess.check_output(['git', 'diff', 'HEAD', '--', 'scripts/ci', 'tests/fixtures', 'supabase'], cwd=ROOT, text=True).strip(), 'SOURCE_DIRTY'
    env = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}
    report = {'schemaVersion': 1, 'completed': False, 'sourceSha': actual_sha,
        'mode': 'PG17_EPHEMERAL_SQL_ONLY_SMS_SUPPLEMENT', 'providerCalls': 0, 'realSmsReceived': False,
        'scope': 'Canonical OTP/ledger and closed supplement; synthetic Vault/SQL HTTP double, not full App RLS, live staging, provider, frontend or physical-device proof.', 'cases': {}}
    mounted = False
    observer = None
    stage = 'prepare-fixture'
    try:
        setup, fixture, rendered_hash = build_fixture()
        report['renderedSupplementSha256'] = rendered_hash
        with tempfile.TemporaryDirectory(prefix='jolene-sms-pg17-') as scratch:
            observer = Session(env, Path(scratch), 'observer')
            stage = 'verify-empty-pg17'
            assert observer.run("SELECT current_setting('server_version_num')::int/10000") == '17', 'PG17_REQUIRED'
            assert observer.run(EMPTY) == 't', 'DATABASE_NOT_EMPTY'
            mounted = True
            stage = 'mount-canonical-fixture-and-closed-supplement'
            observer.run(setup, timeout=45)
            assert observer.run("SELECT count(*)=0 FROM pg_extension WHERE extname='pg_net'") == 't', 'NETWORK_EXTENSION_PRESENT'
            assert observer.run('SELECT count(*)=0 FROM private.signature_sms_test_capacities') == 't', 'INSTALLATION_NOT_CLOSED'
            stage = 'qualify-scope-budget-idempotence-and-second-otp'
            report['cases'].update(json.loads(observer.run(fixture, timeout=45).splitlines()[-1]))
            stage = 'qualify-real-lock-order-and-revocation'
            concurrency(observer, env, Path(scratch), report)
            assert report['cases'] and all(value is True for value in report['cases'].values()), 'FAILED_CASES'
            stage = 'cleanup'
            observer.run(CLEANUP, timeout=30)
            report['cleanupVerified'] = observer.run(EMPTY) == 't'
            assert report['cleanupVerified'], 'CLEANUP_NOT_EMPTY'
            mounted = False
            report['completed'] = True
    except Exception as error:
        message = str(error)
        report['failureStage'] = stage
        report['error'] = message if re.fullmatch('[A-Z][A-Z0-9_]+', message) else 'SMS_PG17_WITNESS_FAILED'
    finally:
        if observer:
            if mounted:
                try:
                    observer.run('ROLLBACK; ' + CLEANUP, timeout=30)
                    report['failureCleanupVerified'] = observer.run(EMPTY) == 't'
                except Exception:
                    # ON_ERROR_STOP may have ended the original observer. A new
                    # connection still targets only the already guarded empty
                    # disposable CI DB, never any existing deployment.
                    cleaned = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                        input=CLEANUP + '\n' + EMPTY, env=env, text=True,
                        capture_output=True, timeout=30)
                    report['failureCleanupVerified'] = cleaned.returncode == 0 and cleaned.stdout.strip() == 't'
            observer.close()
    report['casesPassed'] = sum(value is True for value in report['cases'].values())
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report['completed'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        print(json.dumps({'schemaVersion': 1, 'completed': False, 'error': 'SMS_PG17_PREFLIGHT_REFUSED', 'providerCalls': 0}))
        raise SystemExit(1)
