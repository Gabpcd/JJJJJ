"""Pure preparation checks. The actual PostgreSQL behaviour runs only in CI."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from types import SimpleNamespace
from unittest import TestCase, main, mock, skipUnless

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'sms_sql_only_witness', ROOT / 'scripts/ci/sms-install-sql-only-pg17.py')
WITNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WITNESS)


def approved_environment():
    return {'CI': 'true', 'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
        'GITHUB_REPOSITORY': 'Gabpcd/JJJJJ',
        'JOLENE_SMS_INSTALL_SQL_ONLY_WITNESS': 'CI_EPHEMERE', 'PGHOST': '127.0.0.1',
        'PGPORT': '54329', 'PGDATABASE': 'sms_install_sql_only_diagnostic', 'PGUSER': 'postgres',
        'PGPASSWORD': 'fixture-ci-ephemere'}


def synthetic_before(contract):
    return {'quiet': True, 'absent': True, 'closed': False,
        'routines': copy.deepcopy(contract['beforeRoutines']),
        'invariant': {key: 'a' * 32 for key in ('structure', 'routines', 'inventory', 'registry', 'rows')},
        'targets': 'b' * 32}


class SmsSqlOnlyPreparationTests(TestCase):
    @classmethod
    def setUpClass(cls):
        cls.setup, cls.rendered, cls.contract = WITNESS.build_fixture()

    def test_all_destination_guards_precede_every_process(self):
        changes = [{'PGHOST': 'mejpriaetwgtcstbgfid.supabase.co'}, {'PGHOSTADDR': '127.0.0.1'},
            {'PGDATABASE': 'postgres'}, {'PGPORT': '5432'}, {'PGUSER': 'sms_fixture_admin'},
            {'PGPASSWORD': 'another-password'}, {'PGOPTIONS': '-c search_path=evil'},
            {'PGSERVICE': 'unreviewed'}, {'PGSERVICEFILE': '/tmp/unreviewed'},
            {'CI': 'false'}, {'GITHUB_ACTIONS': ''}, {'RUNNER_ENVIRONMENT': 'self-hosted'},
            {'GITHUB_REPOSITORY': 'another/repository'}, {'PGDATABASE': 'signature_otp_diagnostic'},
            {'JOLENE_SMS_INSTALL_SQL_ONLY_WITNESS': ''}]
        for change in changes:
            with self.subTest(change=change), mock.patch.dict(os.environ,
                    {**approved_environment(), **change}, clear=True), \
                    mock.patch.object(WITNESS.subprocess, 'run') as run, \
                    mock.patch.object(WITNESS.subprocess, 'check_output') as output:
                with self.assertRaises((WITNESS.WitnessFailure, RuntimeError)):
                    WITNESS.main()
                run.assert_not_called()
                output.assert_not_called()

    def test_cli_invalid_environment_exits_one_with_fixed_public_receipt(self):
        # Launch Python absolutely; no destination or git/Node/psql is available.
        # The guard test above separately proves no child-process call is made.
        self.assertTrue(Path(sys.executable).is_absolute())
        result = subprocess.run(
            [sys.executable, '-B', str(ROOT / 'scripts/ci/sms-install-sql-only-pg17.py')],
            cwd=ROOT, env={'PATH': '', 'PYTHONDONTWRITEBYTECODE': '1'},
            text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, '')
        self.assertEqual(json.loads(result.stdout), {
            'schemaVersion': 1, 'completed': False,
            'error': 'SMS_SQL_ONLY_PREFLIGHT_REFUSED', 'providerCalls': 0})

    def test_canonical_routines_and_render_are_not_adapted_for_fixture(self):
        self.assertTrue(self.setup.startswith('BEGIN;'))
        self.assertTrue(self.setup.endswith('COMMIT;\n'))
        self.assertNotIn('CREATE TABLE private.signature_sms_test_capacities', self.setup)
        self.assertNotIn('INSERT INTO private.signature_sms_test_capacities', self.setup)
        self.assertEqual(hashlib.sha256(self.rendered.encode()).hexdigest(), WITNESS.RENDERED_SHA256)
        self.assertEqual(self.contract['renderedSha256'], WITNESS.RENDERED_SHA256)
        self.assertIn('CREATE TABLE IF NOT EXISTS private.sms_dispatch_idempotency', self.setup)
        self.assertIn('CREATE TABLE net.fixture_requests', self.setup)
        self.assertNotIn('CREATE EXTENSION pg_net', self.setup)
        self.assertNotIn('ALTER ROLE postgres NOSUPERUSER', self.setup)
        self.assertNotIn('CREATE ROLE sms_fixture_admin', self.setup)
        self.assertIn('ALTER TABLE cron.job OWNER TO sms_fixture_cron_owner;', self.setup)
        self.assertIn('ALTER TABLE cron.job ENABLE ROW LEVEL SECURITY;', self.setup)
        self.assertIn('REVOKE ALL ON cron.job FROM PUBLIC,postgres;\nGRANT SELECT ON cron.job TO postgres;', self.setup)
        # This does not substitute for pg_get_functiondef metadata assertions in
        # PG17. It catches a changed canonical body before that CI execution.
        definitions = re.findall(
            r'CREATE(?: OR REPLACE)? FUNCTION\s+(?:"?public"?|private)\.[\s\S]*?\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*?)\1', self.setup)
        bodies = {hashlib.md5(body.encode()).hexdigest() for _, body in definitions}
        for routine in self.contract['beforeRoutines']:
            with self.subTest(signature=routine['signature']):
                self.assertIn(routine['body_md5'], bodies)

    def test_service_bootstrap_and_demotion_use_distinct_real_logins(self):
        workflow = (ROOT / '.github/workflows/sms-install-sql-only-pg17.yml').read_text()
        self.assertIn('POSTGRES_USER: sms_fixture_admin', workflow)
        self.assertIn('PGUSER: postgres', workflow)
        self.assertIn('CREATE ROLE postgres LOGIN SUPERUSER', workflow)
        self.assertIn('ALTER DATABASE sms_install_sql_only_diagnostic OWNER TO postgres;', workflow)
        self.assertIn('ALTER SCHEMA public OWNER TO postgres;', workflow)
        self.assertIn("'bootstrap',oid=10", WITNESS.ROLE_STATE)
        self.assertIn("'nonBootstrapPostgres',(SELECT oid<>10", WITNESS.PRIVILEGES)
        self.assertNotIn('sms_fixture_admin', WITNESS.CLEANUP)
        with mock.patch.object(WITNESS, 'psql', return_value='') as query:
            WITNESS.demote_from_admin(approved_environment())
        args, kwargs = query.call_args
        self.assertEqual(args[0]['PGUSER'], 'sms_fixture_admin')
        self.assertEqual(args[0]['PGHOST'], '127.0.0.1')
        self.assertEqual(args[0]['PGDATABASE'], 'sms_install_sql_only_diagnostic')
        self.assertEqual(args[1], 'ALTER ROLE postgres NOSUPERUSER BYPASSRLS;')
        self.assertEqual(kwargs, {'timeout': 15})

    def test_both_real_constructors_receive_unchanged_pins_and_render(self):
        before = synthetic_before(self.contract)
        old = WITNESS.build_sql('historical', self.contract, self.rendered, before)
        resume = WITNESS.build_sql('resume', self.contract, self.rendered, before)
        reader = WITNESS.build_sql('snapshot', self.contract)
        self.assertTrue(reader.startswith('BEGIN READ ONLY;'))
        self.assertTrue(old.endswith('ROLLBACK;'))
        self.assertTrue(resume.endswith('ROLLBACK;'))
        self.assertIn(self.rendered, old)
        self.assertIn(self.rendered, resume)
        self.assertIn('LOCK TABLE cron.job IN ACCESS SHARE MODE NOWAIT;', resume)
        self.assertIn('cron.job,cron.job_run_details,net.http_request_queue IN SHARE MODE NOWAIT;', old)
        self.assertNotIn('cron.job,cron.job_run_details', resume)
        self.assertIn("current_user<>'postgres' OR session_user<>'postgres'", resume)
        for changed in [dict(before, quiet=False), dict(before, absent=False),
                        dict(before, invariant=dict(before['invariant'], rows='bad'))]:
            with self.subTest(changed=changed):
                with self.assertRaisesRegex(WITNESS.WitnessFailure, 'SMS_SQL_ONLY_CONSTRUCTOR_REFUSED'):
                    WITNESS.build_sql('resume', self.contract, self.rendered, changed)

    def test_snapshot_never_accepts_duplicate_rows_or_metadata_adaptation(self):
        before = synthetic_before(self.contract)
        self.assertEqual(WITNESS.snapshot(json.dumps(before)), before)
        WITNESS.check_snapshot(before, self.contract)
        for raw in ['', json.dumps(before) + '\n' + json.dumps(before), '{}', '[]']:
            with self.subTest(raw=raw):
                with self.assertRaises(WITNESS.WitnessFailure):
                    WITNESS.snapshot(raw)
        changed = copy.deepcopy(before)
        changed['routines'][0]['definition_md5'] = 'c' * 32
        with self.assertRaisesRegex(WITNESS.WitnessFailure, 'SMS_SQL_ONLY_ROUTINE_PIN_REFUSED'):
            WITNESS.check_snapshot(changed, self.contract)
        changed = copy.deepcopy(before)
        changed['routines'][1] = copy.deepcopy(changed['routines'][0])
        with self.assertRaisesRegex(WITNESS.WitnessFailure, 'SMS_SQL_ONLY_ROUTINE_DUPLICATE'):
            WITNESS.check_snapshot(changed, self.contract)

    def test_sql_errors_retain_only_sqlstate_without_sql_or_raw_context(self):
        raw = 'ERROR: 42501: permission denied for table job\nCONTEXT: secret command fixture\n'
        with mock.patch.object(WITNESS.subprocess, 'run', return_value=SimpleNamespace(
                returncode=1, stdout='private fixture row', stderr=raw)):
            with self.assertRaises(WITNESS.WitnessFailure) as caught:
                WITNESS.psql({}, 'not executed')
        self.assertEqual(caught.exception.code, 'SMS_SQL_ONLY_PG17_SQL_REFUSED')
        self.assertEqual(caught.exception.sqlstate, '42501')
        self.assertTrue(caught.exception.denied_cron_job)
        self.assertNotIn('permission', str(caught.exception))
        with mock.patch.object(WITNESS.subprocess, 'run', return_value=SimpleNamespace(
                returncode=1, stdout='', stderr='ERROR: 42501: unrelated permission failure\n')):
            with self.assertRaises(WITNESS.WitnessFailure) as caught:
                WITNESS.psql({}, 'not executed')
        self.assertFalse(caught.exception.denied_cron_job)

    @skipUnless(importlib.util.find_spec('pglast'), 'Optional existing parser; CI executes real PG17')
    def test_extended_fixture_and_complete_dry_run_parse(self):
        from pglast import parse_plpgsql, parse_sql
        dry_run = WITNESS.build_sql('resume', self.contract, self.rendered, synthetic_before(self.contract))
        self.assertGreater(len(parse_sql(self.setup)), 100)
        self.assertGreater(len(parse_plpgsql(self.setup)), 20)
        self.assertGreater(len(parse_sql(dry_run)), 20)
        self.assertGreater(len(parse_plpgsql(dry_run)), 10)


if __name__ == '__main__':
    main()
