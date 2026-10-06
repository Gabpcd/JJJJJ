"""Two-session PG17 witness of resend/signature ordering; no SMS/network provider.

Uses the current candidate functions and the existing 98-case witness fixture. The only
HTTP implementation is that fixture's SQL table writer. A held row lock, observed
with pg_locks/pg_blocking_pids, controls ordering; elapsed time never proves it.
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

PIN = os.environ.get('GITHUB_SHA')
CID = 'f1040000-0000-4000-8000-000000000003'
ROLE = os.environ.get('RECETTE_SIGNATURE_ROLE', 'soignant')
assert ROLE in ['soignant','etablissement'], 'ROLE_REFUSED'
UID = 'f1040000-0000-4000-8000-000000000001' if ROLE=='soignant' else 'f1040000-0000-4000-8000-000000000002'
EMPTY = """SELECT (SELECT count(*) FROM pg_class WHERE relnamespace='public'::regnamespace)=0
 AND (SELECT count(*) FROM pg_namespace WHERE nspname IN('auth','extensions','private','vault','net'))=0
 AND (SELECT count(*) FROM pg_roles WHERE rolname IN('anon','authenticated','service_role'))=0"""
PHOTO = f"""SELECT jsonb_build_object(
 'proofStatus',s.statut_signature,'proofSignedAt',s.signe_a,'otpValidatedAt',s.otp_valide_a,
 'proofUser',s.signataire_user_id,'documentHash',s.hash_document,'smsCount',s.sms_envoyes_count,
 'contractSigned',c.signature_{ROLE},'contractStatus',c.statut,
 'syntheticHttpRequests',(SELECT count(*) FROM net.fixture_requests))
 FROM public.signatures_contrats s JOIN public.contrats_mission c ON c.id=s.contrat_id
 WHERE c.id='{CID}' AND s.signataire_role='{ROLE}'"""


def build_fixture(product):
    spec = importlib.util.spec_from_file_location('signature_fixed', product / 'scripts/ci/signature-otp-fix-pg17.py')
    fixed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixed)
    snapshot = (product / 'supabase/schema/public.sql').read_text()
    migration = (product / 'supabase/migrations' / fixed.MIGRATION).read_text()
    for name in ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp']:
        files = [p.name for p in sorted((product / 'supabase/migrations').glob('*.sql'))
                 if re.search(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public|"public")\s*\.\s*"?' + name + r'"?\s*\(', p.read_text(), re.I)]
        assert files[-1] == fixed.MIGRATION, 'LATEST_FUNCTION_CHANGED'
    whole = fixed.build_sql(snapshot,
        json.loads((product / 'tests/fixtures/signature-otp-catalogue-before.json').read_text()),
        json.loads((product / 'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text()), migration)
    # Keep the exact fixture + complete migration, omit its single-session cases.
    setup, tests = whole.split('CREATE TEMP TABLE observations', 1)
    assert setup.startswith('BEGIN;') and tests.rstrip().endswith('ROLLBACK;')
    assert migration in setup
    hashes = {}
    for name in ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp']:
        definition = re.search(r'CREATE OR REPLACE FUNCTION public\.' + name + r'\(.*?AS \$function\$(.*?)\$function\$', migration, re.S).group(0)
        body = re.search(r'\bAS\s+(\$[A-Za-z_0-9]*\$)(.*?)\1', definition, re.S).group(2)
        hashes[name] = hashlib.sha256(body.encode()).hexdigest()
    setup += f"""
SELECT pg_temp.seed_signature('{ROLE}');
UPDATE public.soignants SET telephone='+33600000001';
UPDATE public.etablissements SET telephone_contact='+33600000002';
INSERT INTO vault.decrypted_secrets VALUES
 ('supabase_url','https://'||repeat('a',20)||'.supabase.co'),
 ('service_role_key','synthetic-ci-only-not-a-token');
COMMIT;
"""
    return fixed.diagnostic, setup, hashes, hashlib.sha256(migration.encode()).hexdigest()


class Session:
    def __init__(self, env, directory, name):
        self.path = directory / (name + '.stdout')
        self.out = self.path.open('wb')
        self.err = (directory / (name + '.stderr')).open('wb')
        self.process = subprocess.Popen(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
            stdin=subprocess.PIPE, stdout=self.out, stderr=self.err,
            env={**env, 'PGAPPNAME': 'recette107-otp-' + name}, text=True)
        self.offset = 0
        self.sequence = 0

    def issue(self, sql):
        self.sequence += 1
        marker = 'RECETTE107_END_' + str(self.sequence)
        self.process.stdin.write(sql.rstrip('; \n') + ";\n\\echo " + marker + '\n')
        self.process.stdin.flush()
        return marker

    def wait(self, marker, timeout=20):
        deadline = time.monotonic() + timeout
        needle = (marker + '\n').encode()
        while time.monotonic() < deadline:
            data = self.path.read_bytes()
            end = data.find(needle, self.offset)
            if end >= 0:
                value = data[self.offset:end].decode().strip()
                self.offset = end + len(needle)
                return value
            if self.process.poll() is not None:
                raise RuntimeError('PSQL_SESSION_FAILED')
            time.sleep(0.05)
        raise RuntimeError('PSQL_SESSION_TIMEOUT')

    def run(self, sql, timeout=20):
        return self.wait(self.issue(sql), timeout)

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.out.close()
        self.err.close()


def main():
    product = Path(os.environ['RECETTE_PRODUCT_DIR']).resolve()
    proofs = Path(os.environ['RECETTE_PROOFS_DIR']).resolve()
    proofs.mkdir(parents=True, exist_ok=True)
    report = {'schemaVersion': 1, 'sourceSha': subprocess.check_output(['git','-C',str(product),'rev-parse','HEAD'],text=True).strip(), 'completed': False,
              'mode': 'PG17_EPHEMERAL_EXACT_FUNCTIONS_SQL_HTTP_DOUBLE',
              'providerCalls': 0, 'realTestBackend': False, 'concurrentSessions': 2,
              'observerSessions': 1, 'isolation': 'READ COMMITTED', 'role':ROLE,
              'scope': 'Existing 98-case fixture: canonical tables/functions, contract guards and certificate policies; no full App RLS, Storage, pg_net, provider or physical device.'}
    env = {k: os.environ[k] for k in ['PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD'] if k in os.environ}
    stage = 'guard'
    mounted = False
    sessions = []
    observer = None
    try:
        assert os.environ.get('CI') == 'true', 'CI_REQUIRED'
        actual = subprocess.check_output(['git', '-C', str(product), 'rev-parse', 'HEAD'], text=True).strip()
        assert PIN and actual == PIN, 'SOURCE_PIN_MISMATCH'
        # A pin alone does not exclude dirty working files.
        assert not subprocess.check_output(['git', '-C', str(product), 'diff', 'HEAD', '--',
            'supabase', 'scripts/ci', 'tests/fixtures'], text=True).strip(), 'PRODUCT_DIRTY'
        diagnostic, setup, hashes, migration_hash = build_fixture(product)
        diagnostic.guard(os.environ)
        report['expectedRoutineBodySha256'] = hashes
        report['migrationSha256'] = migration_hash
        with tempfile.TemporaryDirectory(prefix='recette107-otp-') as scratch:
            directory = Path(scratch)
            observer = Session(env, directory, 'observer'); sessions.append(observer)
            stage = 'empty-database'
            assert observer.run("SELECT current_setting('server_version_num')::int/10000") == '17', 'PG17_REQUIRED'
            assert observer.run(EMPTY) == 't', 'DATABASE_NOT_EMPTY'
            stage = 'mount-existing-fixture-and-source'
            # Multi-session visibility requires COMMIT in this disposable DB.
            # Cleanup replaces the single-transaction ROLLBACK of the old witness.
            mounted = True
            observer.run(setup, timeout=45)
            actual_hashes = json.loads(observer.run("""SELECT jsonb_object_agg(proname,
                encode(extensions.digest(convert_to(prosrc,'UTF8'),'sha256'),'hex'))
                FROM pg_proc WHERE oid IN ('public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure,
                  'public.fn_envoyer_otp_signature(uuid)'::regprocedure)"""))
            assert actual_hashes == hashes, 'FUNCTION_BODY_DIFFERS_FROM_SOURCE'
            report['actualRoutineBodySha256'] = actual_hashes
            assert observer.run("SELECT count(*) FROM pg_extension WHERE extname='pg_net'") == '0', 'NETWORK_EXTENSION_PRESENT'
            report['before'] = json.loads(observer.run(PHOTO))
            assert report['before']['proofStatus'] == 'otp_envoye' and report['before']['contractSigned'] is False
            signer = Session(env, directory, 'signer'); sessions.append(signer)
            sender = Session(env, directory, 'sender'); sessions.append(sender)
            claims = f"""BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s'; SET LOCAL lock_timeout='30s';
SELECT set_config('request.jwt.claim.sub','{UID}',true);
SELECT set_config('request.headers','{{}}',true);"""
            signer.run(claims); sender.run(claims)
            signer_pid = int(signer.run('SELECT pg_backend_pid()'))
            sender_pid = int(sender.run('SELECT pg_backend_pid()'))
            stage = 'hold-pending-signature-row'
            signer.run(f"SELECT id FROM public.contrats_mission WHERE id='{CID}' FOR UPDATE")
            signer.run(f"SELECT id FROM public.signatures_contrats WHERE contrat_id='{CID}' AND signataire_role='{ROLE}' FOR UPDATE")
            stage = 'resend-blocked-on-contract'
            sender.run('SET LOCAL ROLE authenticated')
            marker = sender.issue(f"SELECT public.fn_envoyer_otp_signature('{CID}')")
            lock_sql = f"""SELECT jsonb_build_object('senderPid',a.pid,'blockers',pg_blocking_pids(a.pid),
 'waitEventType',a.wait_event_type,'waitEvent',a.wait_event,
 'signatureWriteLock',EXISTS(SELECT 1 FROM pg_locks l WHERE l.pid=a.pid AND l.granted
  AND l.relation='public.signatures_contrats'::regclass AND l.mode='RowExclusiveLock'),
 'ungrantedLocks',COALESCE((SELECT jsonb_agg(jsonb_build_object('type',l.locktype,'mode',l.mode))
  FROM pg_locks l WHERE l.pid=a.pid AND NOT l.granted),'[]'::jsonb))
 FROM pg_stat_activity a WHERE a.pid={sender_pid} AND a.wait_event_type='Lock'
 AND {signer_pid}=ANY(pg_blocking_pids(a.pid))"""
            deadline = time.monotonic() + 15
            lock = None
            while time.monotonic() < deadline:
                result = observer.run(lock_sql)
                if result:
                    candidate = json.loads(result)
                    if candidate['ungrantedLocks']:
                        lock = candidate
                        break
                if sender.process.poll() is not None:
                    raise RuntimeError('SENDER_EXITED_BEFORE_LOCK')
                time.sleep(0.05)
            assert lock is not None, 'CONTRACT_LOCK_NOT_OBSERVED'
            report['blockedResend'] = lock
            stage = 'sign-while-resend-awaits-row'
            signer.run('SET LOCAL ROLE authenticated')
            report['signatureResult'] = json.loads(signer.run(f"SELECT public.fn_signer_contrat_otp('{CID}','123456',(SELECT hash_document FROM public.contrats_mission WHERE id='{CID}'),NULL)"))
            assert report['signatureResult'].get('success') is True, 'SIGNATURE_DID_NOT_SUCCEED'
            signer.run('RESET ROLE')
            report['afterSignatureBeforeCommit'] = json.loads(signer.run(PHOTO))
            assert report['afterSignatureBeforeCommit']['proofStatus'] == 'signe' and report['afterSignatureBeforeCommit']['contractSigned'] is True
            signer.run('COMMIT')
            stage = 'release-and-observe-resend'
            report['resendResult'] = json.loads(sender.wait(marker))
            sender.run('COMMIT')
            report['afterResendCommit'] = json.loads(observer.run(PHOTO))
            final = report['afterResendCommit']
            resend_accepted = report['resendResult'].get('success') is True
            resend_refused = report['resendResult'].get('error_code') in ['DEJA_SIGNE', 'CONTRAT_DEJA_COMPLET']
            assert resend_accepted or resend_refused, 'UNEXPECTED_RESEND_RESULT'
            assert final['syntheticHttpRequests'] == (1 if resend_accepted else 0), 'SYNTHETIC_TRANSPORT_COUNT'
            report['proofRegressed'] = final['contractSigned'] is True and final['proofStatus'] == 'otp_envoye'
            report['signedProofPreserved'] = final['contractSigned'] is True and final['proofStatus'] == 'signe'
            assert report['proofRegressed'] or report['signedProofPreserved'], 'UNEXPECTED_FINAL_STATE'
            assert resend_refused and report['signedProofPreserved'], 'SIGNED_PROOF_REGRESSED'
            assert final == report['afterSignatureBeforeCommit'], 'SIGNED_PROOF_MUTATED_BY_RESEND'
            report['completed'] = True
            stage = 'cleanup'
            signer.close(); sender.close()
            observer.run('DROP SCHEMA auth,extensions,private,vault,net,public CASCADE; CREATE SCHEMA public; DROP ROLE anon,authenticated,service_role;', timeout=30)
            report['cleanupVerified'] = observer.run(EMPTY) == 't'
            assert report['cleanupVerified'], 'CLEANUP_NOT_EMPTY'
            mounted = False
    except Exception as error:
        report['completed'] = False
        report['failureStage'] = stage
        code = str(error)
        report['error'] = code if re.fullmatch('[A-Z][A-Z0-9_]+', code) else 'WITNESS_FAILED'
    finally:
        for session in reversed(sessions):
            session.close()
        # On any failure, dispose of the entire dedicated CI database state.
        if mounted:
            try:
                cleanup = subprocess.run(['psql','-X','-qAt','-v','ON_ERROR_STOP=1'], env=env,
                    input='DROP SCHEMA IF EXISTS auth,extensions,private,vault,net,public CASCADE; CREATE SCHEMA public; DROP ROLE IF EXISTS anon,authenticated,service_role;',
                    text=True, capture_output=True, timeout=30)
                report['failureCleanupSucceeded'] = cleanup.returncode == 0
            except subprocess.TimeoutExpired:
                report['failureCleanupSucceeded'] = False
        (proofs / 'signature-race.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({'completed': report['completed'], 'proofRegressed': report.get('proofRegressed'), 'failureStage': report.get('failureStage')}))
    # A proved regression is a failing audit, even though the witness completed.
    return 0 if report['completed'] and report.get('signedProofPreserved') else 1


if __name__ == '__main__':
    raise SystemExit(main())
