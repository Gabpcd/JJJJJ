"""Pure mock tests: never run Gradle, install, build, or use the network."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('compiler_diagnostic', ROOT / 'scripts/native/android_compiler_diagnostic.py')
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class MockProcess:
    def __init__(self, content=b'', code=1):
        self.stdout = io.BytesIO(content)
        self.code = code
        self.waited = False

    def wait(self):
        self.waited = True
        return self.code


class DiagnosticTests(unittest.TestCase):
    def result(self, content=b'', code=1, variant='optimized'):
        process = MockProcess(content, code)
        launcher = Mock(return_value=process)
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = diagnostic.run_compiler(Path('/fixture'), variant, launcher)
        self.assertEqual(stdout.getvalue(), '')
        self.assertEqual(stderr.getvalue(), '')
        self.assertTrue(process.waited)
        diagnostic.encode_closed(result)
        return result, launcher

    def test_exact_original_commands_and_cwd_no_new_flags(self):
        for variant, task in [('debug', 'assembleDebug'), ('optimized', 'assembleRecetteOptimized')]:
            result, launcher = self.result(code=0, variant=variant)
            launcher.assert_called_once_with(['./gradlew', '--no-daemon', task],
                cwd=Path('/fixture/android'), stdout=diagnostic.subprocess.PIPE,
                stderr=diagnostic.subprocess.STDOUT)
            self.assertEqual(result['wrapperExitCode'], 0)
            self.assertEqual(result['failureCategories'], [])

    def test_every_nonzero_normal_exit_code_propagates(self):
        for code in range(1, 256):
            result, _ = self.result(code=code)
            self.assertEqual(result['gradleExitCode'], code)
            self.assertEqual(result['wrapperExitCode'], code)
            self.assertEqual(result['assemblyResult'], 'failed')

    def test_signal_exit_codes_match_shell(self):
        for signal, expected in [(-9, 137), (-15, 143), (-2, 130)]:
            result, _ = self.result(code=signal)
            self.assertEqual(result['wrapperExitCode'], expected)

    def test_unknown_exit_code_is_never_success(self):
        for code in [None, True, '0', 256, -128]:
            result, _ = self.result(code=code)
            self.assertIsNone(result['gradleExitCode'])
            self.assertEqual(result['wrapperExitCode'], 1)
            self.assertEqual(result['assemblyResult'], 'unknown')

    def test_fixed_category_signals_only(self):
        fixtures = {
            'r8_missing_classes': b'ERROR: Missing classes detected while running R8. private details',
            'r8_compilation': b'R8: Compilation failed to complete',
            'resource_linker': b'Android resource linking failed',
            'manifest': b'> Manifest merger failed with multiple errors',
            'dependency_resolution': b'> Could not resolve all files for configuration secret.',
            'java_compile': b'> Compilation failed; see the compiler error output for details.',
            'kotlin_compile': b'> A failure occurred while executing org.jetbrains.kotlin.compilerRunner.GradleCompilerRunnerWithWorkers',
            'gradle_configuration': b"A problem occurred configuring project ':secret'.",
            'gradle_daemon': b'Gradle build daemon disappeared unexpectedly (secret)',
            'disk_space': b'java.io.IOException: No space left on device',
        }
        self.assertEqual(set(fixtures), set(diagnostic.SIGNALS))
        for category, content in fixtures.items():
            result, _ = self.result(content)
            self.assertEqual(result['failureCategories'], [category])

    def test_multiple_signals_are_observations_not_a_chosen_cause(self):
        result, _ = self.result(b'Manifest merger failed\nAndroid resource linking failed\n')
        self.assertEqual(result['failureCategories'], ['manifest', 'resource_linker'])

    def test_unknown_output_does_not_claim_a_cause(self):
        result, _ = self.result(b'Unrecognized failure\n')
        self.assertEqual(result['failureCategories'], ['unclassified_failure'])

    def test_only_allowlisted_failed_tasks_of_selected_variant(self):
        raw = (b"> Task :app:minifyRecetteOptimizedWithR8 FAILED\n"
               b"Execution failed for task ':app:processRecetteOptimizedResources'.\n"
               b"> Task :privateSecret:customTask FAILED\n"
               b"> Task :app:assembleDebug FAILED\n"
               b"> Task :app:assembleRecetteOptimized FAILED arbitrary suffix\n")
        result, _ = self.result(raw)
        self.assertEqual(result['failedTasks'], [':app:minifyRecetteOptimizedWithR8', ':app:processRecetteOptimizedResources'])
        self.assertTrue(result['unrecognizedFailedTask'])

    def test_arbitrary_sensitive_text_cannot_be_serialized(self):
        forbidden = ['fakeCredentialCanary', 'https://secret.invalid/path',
                     'com.private.CustomerClass', '/home/private/file.kt',
                     'Authorization: Bearer fakeToken', 'ENV_SECRET=fakeValue']
        raw = ('ERROR: Missing classes detected while running R8. ' + ' '.join(forbidden)
               + "\nExecution failed for task ':fakeCredentialCanary'.\n").encode()
        result, _ = self.result(raw)
        encoded = diagnostic.encode_closed(result).decode()
        for canary in forbidden:
            self.assertNotIn(canary, encoded)
        self.assertLessEqual(len(encoded), diagnostic.MAX_JSON_BYTES)

    def test_schema_rejects_open_keys_values_and_wrong_types(self):
        clean, _ = self.result()
        mutations = [
            {'raw': 'sensitive'}, {'variant': 'secret'},
            {'failureCategories': ['secret']}, {'failedTasks': [':secret:task']},
            {'diagnosticStatus': 'secret'}, {'assemblyResult': 'secret'},
            {'gradleExitCode': 'secret'}, {'wrapperExitCode': True},
            {'unrecognizedFailedTask': 'secret'}, {'compilerStarted': 1},
            {'schemaVersion': True}, {'failureCategories': ['manifest', 'manifest']},
        ]
        for mutation in mutations:
            with self.assertRaises(ValueError):
                diagnostic.encode_closed({**clean, **mutation})

    def test_capture_exact_limit_is_complete(self):
        with patch.object(diagnostic, 'MAX_CAPTURE_BYTES', 64):
            result, _ = self.result(b'x' * 64)
        self.assertEqual(result['diagnosticStatus'], 'complete')

    def test_overflow_drains_to_eof_discards_all_classification_and_keeps_exit(self):
        class DrainWitness(io.BytesIO):
            saw_eof = False
            def read(self, size):
                chunk = super().read(min(size, 16))
                self.saw_eof |= not chunk
                return chunk
        process = MockProcess(code=37)
        process.stdout = DrainWitness(b'Android resource linking failed\n' + b'x' * 300)
        with patch.object(diagnostic, 'MAX_CAPTURE_BYTES', 64):
            result = diagnostic.run_compiler(Path('/fixture'), 'optimized', Mock(return_value=process))
        self.assertTrue(process.stdout.saw_eof)
        self.assertTrue(process.waited)
        self.assertEqual(result['wrapperExitCode'], 37)
        self.assertEqual(result['diagnosticStatus'], 'output_limit_refused')
        self.assertEqual(result['failureCategories'], [])
        self.assertEqual(result['failedTasks'], [])

    def test_overflow_on_gradle_success_fails_diagnostic_closed(self):
        with patch.object(diagnostic, 'MAX_CAPTURE_BYTES', 3):
            result, _ = self.result(b'four', code=0)
        self.assertEqual(result['gradleExitCode'], 0)
        self.assertEqual(result['wrapperExitCode'], 1)

    def test_binary_invalid_utf8_and_terminal_controls_refuse_all_classification(self):
        for invalid in [b'\xff', b'\x00', b'\x1b[31m']:
            result, _ = self.result(b'Android resource linking failed\n' + invalid, code=28)
            self.assertEqual(result['diagnosticStatus'], 'text_format_refused')
            self.assertEqual(result['wrapperExitCode'], 28)
            self.assertEqual(result['failureCategories'], [])

    def test_launch_errors_and_invalid_variant_never_echo_exception(self):
        launcher = Mock(side_effect=OSError('fakeCredentialCanary'))
        result = diagnostic.run_compiler(Path('/fixture'), 'optimized', launcher)
        self.assertEqual(result['diagnosticStatus'], 'launch_failed')
        self.assertNotIn('fakeCredentialCanary', diagnostic.encode_closed(result).decode())
        launcher.reset_mock()
        result = diagnostic.run_compiler(Path('/fixture'), 'secret', launcher)
        launcher.assert_not_called()
        self.assertEqual(result['variant'], 'unknown')

    def test_read_error_never_echoes_raw_error_and_keeps_failure(self):
        process = MockProcess(code=44)
        process.stdout = Mock(read=Mock(side_effect=OSError('fakeCredentialCanary')))
        result = diagnostic.run_compiler(Path('/fixture'), 'optimized', Mock(return_value=process))
        self.assertEqual(result['diagnosticStatus'], 'collection_failed')
        self.assertEqual(result['wrapperExitCode'], 44)
        self.assertNotIn('fakeCredentialCanary', diagnostic.encode_closed(result).decode())

    def test_output_is_single_closed_private_file_no_raw_sibling(self):
        result, _ = self.result(b'secret text')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            diagnostic.write_closed(root, result)
            output = root.joinpath(*diagnostic.OUTPUT_PARTS)
            self.assertEqual(json.loads(output.read_text()), result)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(output.parent.iterdir()), [output])
            with self.assertRaises(FileExistsError):
                diagnostic.write_closed(root, result)

    def test_output_refuses_symlink_parent(self):
        result, _ = self.result()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'outside').mkdir()
            (root / 'test-results').symlink_to(root / 'outside')
            with self.assertRaises(ValueError):
                diagnostic.write_closed(root, result)
            self.assertEqual(list((root / 'outside').iterdir()), [])

    def test_main_gates_upload_and_keeps_compiler_failure(self):
        document, _ = self.result(code=42)
        with tempfile.TemporaryDirectory() as temp:
            gh_output = Path(temp) / 'step-output'
            env = {'CI': 'true', 'NATIVE_RECETTE': '1', 'NATIVE_RECETTE_VARIANT': 'optimized', 'GITHUB_OUTPUT': str(gh_output)}
            with patch.dict(os.environ, env, clear=True), patch.object(diagnostic.sys, 'argv', ['diagnostic']), \
                 patch.object(diagnostic, 'run_compiler', return_value=document), patch.object(diagnostic, 'write_closed'):
                self.assertEqual(diagnostic.main(), 42)
            self.assertEqual(gh_output.read_text(), 'diagnostic_ready=true\n')

    def test_write_rejection_never_signals_upload_readiness(self):
        for code in [0, 57]:
            document, _ = self.result(code=code)
            with tempfile.TemporaryDirectory() as temp:
                gh_output = Path(temp) / 'step-output'
                env = {'CI': 'true', 'NATIVE_RECETTE': '1', 'NATIVE_RECETTE_VARIANT': 'debug', 'GITHUB_OUTPUT': str(gh_output)}
                with patch.dict(os.environ, env, clear=True), patch.object(diagnostic.sys, 'argv', ['diagnostic']), \
                     patch.object(diagnostic, 'run_compiler', return_value=document), \
                     patch.object(diagnostic, 'write_closed', side_effect=ValueError('secret')):
                    self.assertEqual(diagnostic.main(), code or 1)
                self.assertFalse(gh_output.exists())

    def test_invalid_context_never_starts_compiler(self):
        with tempfile.TemporaryDirectory() as temp:
            for env in [{}, {'CI': 'true'}, {'NATIVE_RECETTE': '1'}]:
                env = {**env, 'GITHUB_OUTPUT': str(Path(temp) / 'output')}
                with patch.dict(os.environ, env, clear=True), patch.object(diagnostic.sys, 'argv', ['diagnostic']), \
                     patch.object(diagnostic, 'run_compiler') as compiler, patch.object(diagnostic, 'write_closed'):
                    self.assertEqual(diagnostic.main(), 1)
                    compiler.assert_not_called()

    def test_workflow_upload_is_distinct_exact_file_and_gated(self):
        workflow = (ROOT / '.github/workflows/android-native-recette.yml').read_text()
        self.assertIn('python3 scripts/native/android_compiler_diagnostic.py', workflow)
        self.assertIn("if: ${{ !cancelled() && steps.compiler_assembly.outputs.diagnostic_ready == 'true' }}", workflow)
        self.assertIn('path: test-results/android-compiler-diagnostic/diagnostic.json\n', workflow)
        self.assertIn('name: android-compiler-diagnostic-${{ matrix.variant }}-', workflow)
        self.assertIn('path: test-results/android-native/\n', workflow)
        self.assertNotIn('continue-on-error', workflow)


if __name__ == '__main__':
    unittest.main()
