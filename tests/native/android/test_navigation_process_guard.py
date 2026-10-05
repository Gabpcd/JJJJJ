"""Exercise only shell control flow with fake commands; never invoke Android."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = (ROOT / 'scripts/native/run-android-recette.sh').read_text()
NAVIGATION = (ROOT / 'tests/native/android/navigation.mjs').read_text()
GUARD = SCRIPT[SCRIPT.index('# Bound the entire child,'):]
CLEANUP = SCRIPT[SCRIPT.index('collect_cleanup_adb() {'):SCRIPT.index('\ntrap cleanup EXIT')]


class NavigationProcessGuard(unittest.TestCase):
    def run_guard(self, code, directory_present=True):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            if directory_present:
                (root / 'test-results/android-native').mkdir(parents=True)
            prefix = f'''timeout() {{ printf '%s\\n' "$*" >> calls; return {code}; }}
node() {{ printf 'UNEXPECTED_REAL_CHILD'; return 98; }}
'''
            run = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + prefix + GUARD],
                                 cwd=root, capture_output=True, text=True, timeout=3)
            calls = (root / 'calls').read_text().splitlines()
            receipt = root / 'test-results/android-native/navigation-process.json'
            return run, calls, json.loads(receipt.read_text()) if receipt.exists() else None

    def test_success_and_failures_preserve_exit_without_retry(self):
        for code, outcome in ((0, 'completed'), (1, 'failed'), (124, 'timeout_exit'),
                              (137, 'killed_exit'), (125, 'failed'), (143, 'failed')):
            with self.subTest(code=code):
                run, calls, receipt = self.run_guard(code)
                self.assertEqual(run.returncode, code)
                self.assertEqual(run.stdout, '')
                self.assertEqual(calls, ['--signal=TERM --kill-after=15s 600s node tests/native/android/navigation.mjs'])
                self.assertEqual(receipt, {'schema': 1, 'scope': 'navigation-process-only',
                    'outcome': outcome, 'exitCode': code, 'limitSeconds': 600,
                    'killAfterSeconds': 15, 'uiValidated': False})

    def test_receipt_failure_never_erases_original_failure(self):
        for code in (1, 124, 137):
            with self.subTest(code=code):
                run, calls, receipt = self.run_guard(code, directory_present=False)
                self.assertEqual(run.returncode, code)
                self.assertEqual(len(calls), 1)
                self.assertIsNone(receipt)

    def test_receipt_failure_refuses_apparent_success(self):
        run, calls, receipt = self.run_guard(0, directory_present=False)
        self.assertEqual(run.returncode, 1)
        self.assertEqual(len(calls), 1)
        self.assertIsNone(receipt)

    def test_cleanup_continues_when_every_mocked_capture_fails(self):
        for variant in ('debug', 'optimized'):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / 'test-results/android-native').mkdir(parents=True)
                prefix = '''timeout() { printf '%s\\n' "$*" >> calls; return 124; }
kill() { printf 'api-stop\\n' >> calls; }
'''
                script = (f'set -euo pipefail\nrecette_variant={variant}\nrecette_api_pid=123\n'
                          + prefix + CLEANUP + '\ncleanup\n')
                run = subprocess.run(['bash', '-c', script], cwd=root,
                                     capture_output=True, text=True, timeout=3)
                calls = (root / 'calls').read_text().splitlines()
                self.assertEqual(run.returncode, 0)
                self.assertEqual(run.stdout, '')
                self.assertEqual(len(calls), 11)
                self.assertEqual(calls[-1], 'api-stop')
                self.assertTrue(all(call.startswith('--signal=TERM --kill-after=2s 10s adb ')
                                    for call in calls[:-1]))
                self.assertFalse(any('force-stop' in call or 'input keyevent' in call for call in calls))

    def test_exit_trap_and_guard_are_after_setup_and_firewall(self):
        self.assertLess(SCRIPT.index('trap cleanup EXIT'), SCRIPT.index('# Bound the entire child,'))
        self.assertLess(SCRIPT.index('ip6tables -I OUTPUT'), SCRIPT.index('# Bound the entire child,'))
        self.assertEqual(SCRIPT.count('node tests/native/android/navigation.mjs'), 1)
        self.assertNotIn('--preserve-status', GUARD)

    def test_actual_exit_trap_keeps_receipt_and_original_status(self):
        for code in (0, 124, 137):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / 'test-results/android-native').mkdir(parents=True)
                prefix = f'''timeout() {{
  if [ "$3" = 600s ]; then return {code}; fi
  if [ -f test-results/android-native/navigation-process.json ]; then
    printf 'receipt-before-cleanup\\n' >> calls
  fi
  return 124
}}
kill() {{ printf 'api-stop\\n' >> calls; }}
'''
                script = ('set -euo pipefail\nrecette_variant=debug\nrecette_api_pid=123\n'
                          + prefix + CLEANUP + '\ntrap cleanup EXIT\n' + GUARD)
                run = subprocess.run(['bash', '-c', script], cwd=root,
                                     capture_output=True, text=True, timeout=3)
                self.assertEqual(run.returncode, code)
                self.assertEqual((root / 'calls').read_text().splitlines(),
                                 ['receipt-before-cleanup'] * 10 + ['api-stop'])

    def test_original_error_is_written_before_native_failure_capture(self):
        tail = NAVIGATION[NAVIGATION.index('} catch (error) {\n  // Record the original cause'):]
        self.assertLess(tail.index("save('failure.json'"), tail.index("capture('failure')"))
        self.assertLess(tail.index("capture('failure')"), tail.index('captureAccessibility('))
        self.assertIn('finally {\n    throw error;', tail)
        self.assertRegex(NAVIGATION, re.compile(r'await device\.wait\(\{ pkg, text:.*?timeout: 10000', re.S))


if __name__ == '__main__':
    unittest.main()
