"""Witness preparation checks only. PostgreSQL behaviour runs in CI PG17."""
import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest import TestCase, mock, main, skipUnless

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('sms_staging_witness', ROOT / 'scripts/ci/sms-signature-staging-pg17.py')
WITNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WITNESS)


class SmsWitnessPreparationTests(TestCase):
    def test_refuses_remote_or_unapproved_execution_before_any_process(self):
        approved = {'CI': 'true', 'JOLENE_SIGNATURE_WITNESS': 'CI_EPHEMERE',
            'JOLENE_SMS_STAGING_WITNESS': 'CI_EPHEMERE', 'PGHOST': '127.0.0.1',
            'PGPORT': '54329', 'PGDATABASE': 'signature_otp_diagnostic', 'PGUSER': 'postgres'}
        for change in [{'PGHOST': 'mejpriaetwgtcstbgfid.supabase.co'}, {'PGDATABASE': 'postgres'},
                       {'CI': 'false'}, {'JOLENE_SMS_STAGING_WITNESS': ''}, {'PGOPTIONS': '-c search_path=evil'}]:
            with self.subTest(change=change), mock.patch.dict(os.environ, {**approved, **change}, clear=True), \
                 mock.patch.object(WITNESS.subprocess, 'check_output') as process:
                with self.assertRaises((AssertionError, RuntimeError)):
                    WITNESS.main()
                process.assert_not_called()

    def test_builder_retains_exact_function_sources_and_closed_installation(self):
        setup, fixture, rendered_hash = WITNESS.build_fixture()
        self.assertTrue(setup.startswith('BEGIN;'))
        self.assertTrue(setup.endswith('COMMIT;\n'))
        self.assertEqual(len(rendered_hash), 64)
        self.assertIn('CREATE TABLE IF NOT EXISTS private.sms_dispatch_idempotency', setup)
        self.assertIn('CREATE TABLE net.fixture_requests', setup)
        self.assertNotIn('CREATE EXTENSION pg_net', setup)
        self.assertNotIn('INSERT INTO private.signature_sms_test_capacities', setup)
        self.assertIn('CREATE TEMP TABLE sms_observations', fixture)
        self.assertIn("'second-sms-zero-budget-no-resend-valid-signature-'", fixture)
        for observation in ['admission-keeps-original-otp-expiry-',
                            'capacity-expiry-bounds-current-otp-',
                            'second-otp-expiry-survives-readmission-zero-budget-']:
            self.assertIn("'" + observation + "'", fixture)
        self.assertIn('INTO STRICT code FROM net.fixture_requests WHERE body', fixture)
        self.assertIn('BEGIN;', fixture)

    def test_service_rpc_arguments_need_no_table_read_under_reduced_rls_role(self):
        # The fixture's service_role intentionally lacks BYPASSRLS. This guards
        # against accidental SELECT subqueries evaluated as service_role before
        # the SECURITY DEFINER reservation routine has even been entered.
        key = 'otp-signature.' + WITNESS.CID + '.' + WITNESS.SID + '.soignant.1791979200.1'
        observer = mock.Mock()
        observer.run.return_value = '{"otpHash":"' + 'c' * 64 + '","key":"' + key + '"}'
        bound = WITNESS.reserve_call(WITNESS.current_request(observer))
        self.assertNotIn('SELECT', bound.upper())
        self.assertIn("'" + key + "'", bound)
        self.assertIn("'" + 'c' * 64 + "'", bound)

    def test_sql_diagnostics_keep_only_reviewed_code_or_sqlstate(self):
        with tempfile.TemporaryDirectory(prefix='sms-witness-diagnostic-') as temporary:
            errorfile = Path(temporary) / 'synthetic.stderr'
            session = WITNESS.Session.__new__(WITNESS.Session)
            session.err = SimpleNamespace(name=str(errorfile))
            reviewed = 'SIGNATURE_SMS_TEST_SCOPE_REFUSED'
            WITNESS.SQL_ERROR_CODES.add(reviewed)
            for raw, expected in [
                ('ERROR: 42601: syntax error containing private@example.invalid\nCONTEXT: secret fixture text', 'SMS_SQLSTATE_42601'),
                ('ERROR: P0001: ' + reviewed + '\nCONTEXT: secret fixture text', reviewed),
                ('ERROR: P0001: UNREVIEWED_PRIVATE_MESSAGE\n', 'SMS_SQLSTATE_P0001'),
            ]:
                with self.subTest(expected=expected):
                    errorfile.write_text(raw)
                    with mock.patch.object(WITNESS.RACE.Session, 'wait', side_effect=RuntimeError('PSQL_SESSION_FAILED')):
                        with self.assertRaisesRegex(RuntimeError, '^' + expected + '$'):
                            session.wait('MARKER')

    @skipUnless(importlib.util.find_spec('pglast'), 'Optional existing parser; CI validates with real PG17 instead')
    def test_all_fixture_and_setup_plpgsql_units_parse(self):
        from pglast import parse_sql, parse_plpgsql
        setup, fixture, _ = WITNESS.build_fixture()
        self.assertGreater(len(parse_sql(setup)), 100)
        self.assertGreater(len(parse_plpgsql(setup)), 20)
        self.assertEqual(len(parse_plpgsql(fixture)), 5)
        self.assertGreater(len(parse_sql(fixture)), 5)
        # Regression of the real first CI failure: the unparenthesised CASE
        # closes PLpgSQL's IF expression at its inner THEN token.
        historical = fixture.replace(
            "IS DISTINCT FROM (CASE WHEN label='ENVOYE' THEN 'DEJA_ENVOYE' ELSE label END)",
            "IS DISTINCT FROM CASE WHEN label='ENVOYE' THEN 'DEJA_ENVOYE' ELSE label END")
        self.assertNotEqual(historical, fixture)
        with self.assertRaises(Exception):
            parse_plpgsql(historical)


if __name__ == '__main__':
    main()
