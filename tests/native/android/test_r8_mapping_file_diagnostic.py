"""Pure metadata and mocked pipeline witnesses; no Gradle, APK build or installation."""
import copy
from contextlib import ExitStack
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('r8', Path(__file__).resolve().parents[3] / 'scripts/native/check_android_r8.py')
r8 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r8)
MIB = 1024 * 1024
CANARY = 'private-path-message-token-must-not-escape'


def info(size=1, mode=stat.S_IFREG | 0o600):
    return SimpleNamespace(st_size=size, st_mode=mode)


def row(name, category='0_32M', present=True, regular=True, symlink=False):
    return dict(file=name, present=present, regular=regular, symlink=symlink, sizeCategory=category)


class MappingDiagnosticTests(unittest.TestCase):
    def test_all_size_boundaries_for_both_files(self):
        for size, category in [(0, '0'), (1, '0_32M'), (32*MIB, '0_32M'),
                               (32*MIB+1, '32_128M'), (128*MIB, '32_128M'),
                               (128*MIB+1, '128_256M'), (256*MIB, '128_256M'),
                               (256*MIB+1, 'over256M')]:
            with self.subTest(size=size), mock.patch.object(r8.Path, 'lstat', return_value=info(size)) as ls:
                value = r8.mapping_file_states(Path('/fixed/private'))
                self.assertEqual(value, [row(name, category) for name in r8.MAPPING_FILES])
                self.assertEqual(ls.call_count, 2)

    def test_absent_and_oversize_both_captured_in_fixed_order(self):
        with mock.patch.object(r8.Path, 'lstat', side_effect=[FileNotFoundError(CANARY), info(33*MIB)]):
            value = r8.mapping_file_states(Path('/fixed/private'))
        self.assertEqual(value, [row('mapping.txt', 'absent', False, False, False),
                                 row('configuration.txt', '32_128M')])
        self.assertNotIn(CANARY, json.dumps(value))

    def test_symlink_and_broken_symlink_never_follow_target_or_read_contents(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            target = directory / 'private-target'
            target.write_text(CANARY)
            (directory / 'mapping.txt').symlink_to(target)
            (directory / 'configuration.txt').symlink_to(directory / 'absent-target')
            def reject_following_stat(path, *, follow_symlinks=True):
                # Python 3.12 implements Path.lstat via stat(follow_symlinks=False).
                # Permit that exact non-following call, never a normal stat.
                if follow_symlinks is not False:
                    raise AssertionError('following stat')
                return os.lstat(path)
            with mock.patch.object(r8.Path, 'read_text', side_effect=AssertionError('content read')), \
                 mock.patch.object(r8.Path, 'stat', new=reject_following_stat):
                result = r8.mapping_file_states(directory)
                self.assertEqual(stat.S_IFMT((directory / 'mapping.txt').stat(follow_symlinks=False).st_mode), stat.S_IFLNK)
                with self.assertRaisesRegex(AssertionError, 'following stat'):
                    (directory / 'mapping.txt').stat()
        self.assertEqual(result, [row(name, 'not_regular', True, False, True) for name in r8.MAPPING_FILES])

    def test_directory_and_special_file_are_not_regular(self):
        for mode in [stat.S_IFDIR, stat.S_IFIFO, stat.S_IFSOCK]:
            with mock.patch.object(r8.Path, 'lstat', return_value=info(1, mode)):
                value = r8.mapping_file_states(Path('/fixed/private'))
                self.assertEqual(value, [row(name, 'not_regular', True, False, False) for name in r8.MAPPING_FILES])

    def test_access_errors_are_unknown_and_do_not_hide_second_file(self):
        for error in [PermissionError(CANARY), OSError(CANARY)]:
            with mock.patch.object(r8.Path, 'lstat', side_effect=[error, info(0)]):
                value = r8.mapping_file_states(Path('/fixed/private'))
            self.assertEqual(value[0], row('mapping.txt', 'unavailable', None, None, None))
            self.assertEqual(value[1], row('configuration.txt', '0'))
            self.assertNotIn(CANARY, json.dumps(value))

    def test_invalid_stat_size_is_unavailable(self):
        for size in [-1, True, '1', None]:
            with mock.patch.object(r8.Path, 'lstat', return_value=info(size)):
                self.assertEqual(r8.mapping_file_states(Path('/fixed/private')), r8.unavailable_mapping_files())

    def test_projection_reconstructs_all_allowed_closed_states(self):
        samples = [row('mapping.txt', c) for c in r8.MAPPING_SIZE_CATEGORIES]
        samples += [row('mapping.txt', 'absent', False, False, False),
                    row('mapping.txt', 'not_regular', True, False, False),
                    row('mapping.txt', 'not_regular', True, False, True),
                    row('mapping.txt', 'unavailable', None, None, None)]
        for first in samples:
            value = [first, row('configuration.txt')]
            projected = r8.closed_mapping_files(value)
            self.assertEqual(projected, value)
            self.assertIsNot(projected, value)
            self.assertIsNot(projected[0], first)

    def test_projection_rejects_unknown_keys_values_names_order_and_bool_impostors(self):
        good = [row('mapping.txt'), row('configuration.txt')]
        invalid = [None, {}, good[:1], good + [row(CANARY)], list(reversed(good))]
        for key, val in [('file', CANARY), ('sizeCategory', CANARY), ('message', CANARY),
                         ('present', 1), ('regular', 1), ('symlink', 0), ('sizeCategory', []),
                         ('regular', None), ('present', CANARY), ('file', None)]:
            changed = copy.deepcopy(good)
            changed[0][key] = val
            invalid.append(changed)
        for value in invalid:
            result = r8.closed_mapping_files(value)
            self.assertEqual(result, r8.unavailable_mapping_files())
            self.assertNotIn(CANARY, json.dumps(result))

    def test_projection_rejects_inconsistent_flags_and_categories(self):
        for invalid in [row('mapping.txt', 'absent'), row('mapping.txt', 'not_regular'),
                        row('mapping.txt', 'unavailable'), row('mapping.txt', '0', True, True, True),
                        row('mapping.txt', '0', False, False, False)]:
            self.assertEqual(r8.closed_mapping_files([invalid, row('configuration.txt')]), r8.unavailable_mapping_files())

    def test_mapping_metadata_only_on_mapping_refusal(self):
        for reason in r8.REASONS:
            error = r8.R8Refused(reason)
            error.mapping_files = [row('mapping.txt'), row('configuration.txt')]
            result = r8.closed_failure(error)
            self.assertEqual('mappingFiles' in result, reason == 'MAPPING_FILE')
            self.assertEqual(result['reason'], reason)
            self.assertFalse(result['uiValidated'])
            self.assertFalse(result['storeBuild'])

    def test_missing_and_forged_error_metadata_are_closed(self):
        error = r8.R8Refused('MAPPING_FILE')
        self.assertEqual(r8.closed_failure(error)['mappingFiles'], r8.unavailable_mapping_files())
        error.mapping_files = [{'file': CANARY, 'message': CANARY}]
        result = r8.closed_failure(error)
        self.assertEqual(result['mappingFiles'], r8.unavailable_mapping_files())
        self.assertNotIn(CANARY, json.dumps(result))
        error.reason = CANARY
        self.assertEqual(r8.closed_failure(error)['reason'], 'UNCLASSIFIED')
        self.assertNotIn('mappingFiles', r8.closed_failure(error))

    def test_maximum_output_is_small_and_contains_no_path_or_exception(self):
        error = r8.R8Refused('MAPPING_FILE')
        error.mapping_files = [row(name, '128_256M') for name in r8.MAPPING_FILES]
        error.args = (CANARY,)
        encoded = json.dumps(r8.closed_failure(error), sort_keys=True)
        self.assertLessEqual(len(encoded.encode()), 8192)
        self.assertNotIn(CANARY, encoded)
        self.assertEqual(set(json.loads(encoded)), {'schemaVersion', 'status', 'reason', 'exceptionKind', 'uiValidated', 'storeBuild', 'mappingFiles'})

    def failed_main(self, *, mapping_size=0, configuration_size=1, metadata_error=None):
        # Run only the Python checks with every process/archive/content input mocked.
        sha = 'a' * 40
        files = {'mapping.txt': mapping_size, 'configuration.txt': configuration_size}
        def file_stat(path):
            return info(files.get(path.name, 1))
        archive = mock.MagicMock()
        archive.__enter__.return_value = archive
        archive.infolist.return_value = [SimpleNamespace(filename='classes.dex', file_size=112)]
        archive.read.return_value = b'pure mock'
        with ExitStack() as stack:
            stack.enter_context(mock.patch.dict(r8.os.environ, {'CI': 'true', 'NATIVE_RECETTE': '1', 'NATIVE_RECETTE_VARIANT': 'optimized', 'GIT_COMMIT_SHA': sha}, clear=True))
            stack.enter_context(mock.patch.object(r8.subprocess, 'check_output', return_value=sha))
            stack.enter_context(mock.patch.object(r8.zipfile, 'ZipFile', return_value=archive))
            stack.enter_context(mock.patch.object(r8, 'dex_classes', return_value={'example.Class'}))
            stack.enter_context(mock.patch.object(r8.Path, 'exists', return_value=False))
            stack.enter_context(mock.patch.object(r8.Path, 'is_file', return_value=True))
            stack.enter_context(mock.patch.object(r8.Path, 'is_symlink', return_value=False))
            stack.enter_context(mock.patch.object(r8.Path, 'stat', autospec=True, side_effect=file_stat))
            ls = stack.enter_context(mock.patch.object(r8.Path, 'lstat', autospec=True, side_effect=file_stat))
            reads = stack.enter_context(mock.patch.object(r8.Path, 'read_text', return_value='private content'))
            if metadata_error:
                stack.enter_context(mock.patch.object(r8, 'mapping_file_states', side_effect=metadata_error))
            with self.assertRaises(r8.R8Refused) as cm:
                r8.main()
            self.assertEqual(cm.exception.reason, 'MAPPING_FILE')
            self.assertEqual(reads.call_count, 0)
            return cm.exception, ls.call_count

    def test_first_mapping_failure_captures_both_files_without_content_reads(self):
        error, calls = self.failed_main(mapping_size=0, configuration_size=33*MIB)
        self.assertEqual(calls, 2)
        self.assertEqual(r8.closed_failure(error)['mappingFiles'],
                         [row('mapping.txt', '0'), row('configuration.txt', '32_128M')])

    def test_second_mapping_failure_captures_both_files(self):
        error, calls = self.failed_main(mapping_size=1, configuration_size=0)
        self.assertEqual(calls, 2)
        self.assertEqual(r8.closed_failure(error)['mappingFiles'],
                         [row('mapping.txt'), row('configuration.txt', '0')])

    def test_diagnostic_failure_preserves_original_refusal(self):
        error, calls = self.failed_main(metadata_error=RuntimeError(CANARY))
        self.assertEqual(calls, 0)
        result = r8.closed_failure(error)
        self.assertEqual(result['reason'], 'MAPPING_FILE')
        self.assertEqual(result['mappingFiles'], r8.unavailable_mapping_files())
        self.assertNotIn(CANARY, json.dumps(result))


if __name__ == '__main__':
    unittest.main()
