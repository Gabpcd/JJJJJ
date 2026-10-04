"""Pure builder regressions; no database or provider calls."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'otp_fix', ROOT / 'scripts/ci/signature-otp-fix-pg17.py')
FIX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIX)
DIAGNOSTIC = FIX.diagnostic


class SignatureWitnessBuilderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = (ROOT / 'supabase/schema/public.sql').read_text()
        cls.before = json.loads(
            (ROOT / 'tests/fixtures/signature-otp-catalogue-before.json').read_text())
        cls.auth = json.loads(
            (ROOT / 'tests/fixtures/connect-pretransfer-auth-dependencies.json').read_text())
        cls.migration = (ROOT / 'supabase/migrations' / FIX.MIGRATION).read_text()
        definition = DIAGNOSTIC.definition(cls.snapshot, 'fn_signer_contrat_otp')
        body = DIAGNOSTIC.exact(r'AS \$function\$(.*?)\$function\$', cls.before['definition'])
        historical, count = re.subn(
            r'AS (\$[A-Za-z_0-9]*\$).*?\1;',
            lambda _: 'AS $$' + body + '$$;', definition, flags=re.S)
        assert count == 1
        cls.historical_snapshot = cls.snapshot.replace(definition, historical, 1)

    def test_historical_diagnostic_still_accepts_exact_original(self):
        sql = DIAGNOSTIC.build_sql(self.historical_snapshot, self.before, self.auth)
        self.assertIn(self.before['definition'], sql)
        self.assertTrue(sql.endswith('ROLLBACK;\n'))

    def test_historical_diagnostic_rejects_corrected_body(self):
        with self.assertRaises((RuntimeError, AssertionError)):
            DIAGNOSTIC.build_sql(self.snapshot, self.before, self.auth)

    def test_fixed_witness_is_identical_after_snapshot_refresh(self):
        original = FIX.build_sql(
            self.historical_snapshot, self.before, self.auth, self.migration)
        refreshed = FIX.build_sql(self.snapshot, self.before, self.auth, self.migration)
        self.assertEqual(refreshed, original)
        self.assertIn(self.before['definition'], refreshed)
        self.assertIn(self.migration.strip(), refreshed)

    def test_historical_body_fingerprint_cannot_be_bypassed(self):
        before = copy.deepcopy(self.before)
        before['definition'] = before['definition'].replace('AS $function$', 'AS $function$\n', 1)
        with self.assertRaises(AssertionError):
            FIX.build_sql(self.snapshot, before, self.auth, self.migration)

    def test_historical_owner_cannot_be_bypassed(self):
        before = copy.deepcopy(self.before)
        before['owner'] = 'anon'
        with self.assertRaises(AssertionError):
            FIX.build_sql(self.snapshot, before, self.auth, self.migration)

    def test_historical_acl_cannot_be_bypassed(self):
        before = copy.deepcopy(self.before)
        before['acl'] = '{postgres=X/postgres,anon=X/postgres}'
        with self.assertRaises(AssertionError):
            FIX.build_sql(self.snapshot, before, self.auth, self.migration)


if __name__ == '__main__':
    unittest.main()
