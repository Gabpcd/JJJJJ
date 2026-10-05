"""Bounded streaming witnesses; no APK, Gradle or provider access."""
import hashlib
import importlib.util
import io
from pathlib import Path
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('r8', Path(__file__).resolve().parents[3] / 'scripts/native/check_android_r8.py')
r8 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r8)
HEADER = b'# compiler: R8\nexample.Plugin -> example.Plugin:\nexample.Helper -> a.b:\n'
PLUGINS = [{'classpath': 'example.Plugin'}]
CLASSES = {'example.Plugin', 'app.jolene.android.MainActivity', 'a.b'}


class RepeatedLines:
    def __init__(self, header, line, count):
        self.header, self.line, self.count = header.splitlines(keepends=True), line, count
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def readline(self, limit):
        if limit != r8.MAPPING_LINE_LIMIT + 1: raise AssertionError('unbounded read')
        if self.header: return self.header.pop(0)
        if self.count:
            self.count -= 1
            return self.line[:limit]
        return b''


class MappingStreamTests(unittest.TestCase):
    def read_bytes(self, raw, expected=None):
        with mock.patch.object(r8.Path, 'open', return_value=io.BytesIO(raw)):
            return r8.read_mapping(Path('mapping.txt'), len(raw) if expected is None else expected)

    def refused(self, raw, reason, expected=None):
        with self.assertRaises(r8.R8Refused) as cm:
            self.read_bytes(raw, expected)
        self.assertEqual(cm.exception.reason, reason)

    def test_large_realistic_method_metadata_is_hashed_without_retention(self):
        line = b'    1:1:void helper(' + b'x' * 60_000 + b'):1:1 -> a\n'
        count = 600
        size = len(HEADER) + len(line) * count
        self.assertGreater(size, 32 * 1024 * 1024)
        expected = hashlib.sha256(HEADER)
        for _ in range(count): expected.update(line)
        with mock.patch.object(r8.Path, 'open', return_value=RepeatedLines(HEADER, line, count)):
            compact, digest = r8.read_mapping(Path('mapping.txt'), size)
        self.assertEqual(compact.encode(), HEADER)
        self.assertEqual(digest, expected.hexdigest())
        self.assertEqual(r8.inspect_r8(compact, '', PLUGINS, CLASSES)['renamedClasses'], 1)

    def test_digest_covers_ignored_method_metadata_and_missing_final_newline(self):
        raw = HEADER + b'    1:void method() -> a'
        compact, digest = self.read_bytes(raw)
        self.assertEqual(compact.encode(), HEADER)
        self.assertEqual(digest, hashlib.sha256(raw).hexdigest())

    def test_existing_compiler_plugin_and_duplicate_guards_remain_effective(self):
        for raw, reason in [
            (HEADER.replace(b'# compiler: R8\n', b''), 'R8_COMPILER_MARKER'),
            (HEADER.replace(b'example.Plugin -> example.Plugin:', b'example.Plugin -> p:'), 'PLUGIN_NOT_PRESERVED'),
            (HEADER + b'example.Plugin -> p:\n', 'MAPPING_CLASS_ENTRIES'),
        ]:
            compact, _ = self.read_bytes(raw)
            with self.assertRaises(r8.R8Refused) as cm:
                r8.inspect_r8(compact, '', PLUGINS, CLASSES)
            self.assertEqual(cm.exception.reason, reason)
        compact, _ = self.read_bytes(HEADER)
        for flag in ['dontoptimize', 'dontshrink', 'dontobfuscate']:
            with self.assertRaises(r8.R8Refused):
                r8.inspect_r8(compact, '-' + flag, PLUGINS, CLASSES)

    def test_refuses_oversize_lines_before_retention(self):
        self.refused(b'x' * (r8.MAPPING_LINE_LIMIT + 1), 'MAPPING_LINE_SIZE')

    def test_refuses_changed_size_oversize_input_and_false_size(self):
        for expected in [len(HEADER) - 1, len(HEADER) + 1, 0, True, r8.MAPPING_STREAM_LIMIT + 1]:
            self.refused(HEADER, 'MAPPING_STREAM_SIZE', expected)

    def test_retained_class_table_is_independently_bounded(self):
        with mock.patch.object(r8, 'MAPPING_TABLE_LIMIT', 10):
            self.refused(HEADER, 'MAPPING_TABLE_SIZE')
        entry = b'example.Helper -> a.b:\n'
        size = len(HEADER) + len(entry) * 100_000
        with mock.patch.object(r8.Path, 'open', return_value=RepeatedLines(HEADER, entry, 100_000)):
            with self.assertRaises(r8.R8Refused) as cm:
                r8.read_mapping(Path('mapping.txt'), size)
        self.assertEqual(cm.exception.reason, 'MAPPING_TABLE_SIZE')

    def test_invalid_utf8_in_ignored_metadata_is_not_silently_skipped(self):
        with self.assertRaises(UnicodeDecodeError):
            self.read_bytes(HEADER + b'    \xff\n')


if __name__ == '__main__': unittest.main()
