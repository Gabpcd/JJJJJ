"""Witness preparation checks only. PostgreSQL behaviour runs in CI PG17."""
import importlib.util
import os
from pathlib import Path
from unittest import TestCase, mock, main

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


if __name__ == '__main__':
    main()
