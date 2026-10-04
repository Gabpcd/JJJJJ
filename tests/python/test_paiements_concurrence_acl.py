"""Tests purs : aucun import du lanceur PG17 ni connexion PostgreSQL."""
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'paiements_concurrence_acl', ROOT / 'scripts/ci/paiements_concurrence_acl.py'
)
ACL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ACL)

OLD_TARGET = 'public.fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)'
NEW_TARGET = ('"public"."fn_stripe_payment_flow_claim_connect_v1"'
              '("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid", "p_mission_id" "uuid")')
OLD = [f'REVOKE ALL ON FUNCTION {OLD_TARGET} FROM PUBLIC,anon,authenticated;',
       f'GRANT ALL ON FUNCTION {OLD_TARGET} TO service_role;']
NEW = [f'REVOKE ALL ON FUNCTION {NEW_TARGET} FROM PUBLIC;',
       f'GRANT ALL ON FUNCTION {NEW_TARGET} TO "service_role";']


class ClaimAclTests(unittest.TestCase):
    def test_both_dump_forms_preserve_exact_sql_and_ignore_other_functions(self):
        for statements in [OLD, NEW, ['  ' + line + '  ' for line in NEW]]:
            with self.subTest(statements=statements):
                unrelated = 'GRANT ALL ON FUNCTION public.other(text) TO anon;'
                snapshot = unrelated + '\n' + '\n'.join(statements) + '\n'
                self.assertEqual(ACL.extract_claim_acl(snapshot), statements)

    def test_current_snapshot_is_accepted_without_normalization(self):
        snapshot = (ROOT / 'supabase/schema/public.sql').read_text()
        statements = ACL.extract_claim_acl(snapshot)
        self.assertEqual(statements, NEW)
        for statement in statements:
            self.assertIn(statement, snapshot)

    def test_missing_duplicate_and_additional_acl_are_rejected(self):
        for statements in [[], NEW[:1], NEW[1:], NEW + NEW[:1], NEW + NEW[1:],
                           NEW + [f'GRANT EXECUTE ON FUNCTION {OLD_TARGET} TO anon;'],
                           NEW + [f'GRANT EXECUTE\nON FUNCTION {OLD_TARGET} TO anon;'],
                           NEW + [f'GRANT EXECUTE ON FUNCTION\n{OLD_TARGET} TO anon;'],
                           NEW + [f'GRANT EXECUTE ON FUNCTION {OLD_TARGET}\nTO anon;']]:
            with self.subTest(statements=statements), self.assertRaises(ValueError):
                ACL.extract_claim_acl('\n'.join(statements))

    def test_unsafe_rights_and_signatures_are_rejected(self):
        cases = [
            [NEW[0].replace('FROM PUBLIC', 'FROM anon'), NEW[1]],
            [NEW[0].replace('FROM PUBLIC', 'FROM "PUBLIC"'), NEW[1]],
            [NEW[0].replace('FROM PUBLIC', 'FROM PUBLIC,PUBLIC'), NEW[1]],
            [NEW[0], NEW[1].replace('TO "service_role"', 'TO anon')],
            [NEW[0], NEW[1].replace('TO "service_role"', 'TO authenticated')],
            [NEW[0], NEW[1].replace('TO "service_role"', 'TO PUBLIC')],
            [NEW[0], NEW[1].replace('TO "service_role"', 'TO "service_role",anon')],
            [NEW[0], NEW[1].replace('TO "service_role"', 'TO "service_role" WITH GRANT OPTION')],
            [NEW[0], NEW[1].replace('GRANT ALL', 'GRANT SELECT')],
            [line.replace('"p_mission_id" "uuid"', '"p_mission_id" "text"') for line in NEW],
            [line.replace('"p_owner_token"', '"wrong_parameter"') for line in NEW],
            [NEW[0], NEW[1] + ' GRANT ALL ON FUNCTION public.other(text) TO anon;'],
            [NEW[0], NEW[1].removesuffix(';')],
            [NEW[0], NEW[1].replace(' ON FUNCTION ', '\nON FUNCTION ')],
            list(reversed(NEW)),
        ]
        for statements in cases:
            with self.subTest(statements=statements), self.assertRaises(ValueError):
                ACL.extract_claim_acl('\n'.join(statements))


if __name__ == '__main__':
    unittest.main()
